import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit
import Vision

/// Screen watcher lifecycle state, published to the UI.
enum ScreenWatcherState: Sendable, Equatable {
    case stopped
    case waitingForDiscord
    case watching(windowTitle: String)
    case failed(String)

    var displayName: String {
        switch self {
        case .stopped: return "Stopped"
        case .waitingForDiscord: return "Waiting for a Discord window…"
        case .watching(let title): return "Watching \(title)"
        case .failed(let message): return message
        }
    }

    var isActive: Bool {
        if case .watching = self { return true }
        return false
    }
}

/// Reads biome alerts straight off the user's own screen.
///
/// Captures the Discord window with ScreenCaptureKit (~2 fps, only when the
/// frame content actually changes) and runs Apple's Vision OCR over it. When
/// a *new* joinable Roblox link appears on screen, the surrounding text is
/// fed through the normal detection pipeline, which classifies the biome and
/// launches Roblox directly from the extracted URL.
///
/// Privacy/compliance properties:
/// - 100% local: frames and text never leave the machine.
/// - Read-only: it never clicks, types, or sends anything into Discord, and
///   it talks to no Discord API at all.
/// - Scoped: only Discord app windows are captured, never the whole screen.
/// - Requires the user to grant Screen Recording permission (macOS TCC).
final class ScreenWatcherService: NSObject, @unchecked Sendable {
    let events: AsyncStream<IncomingEvent>
    private let eventContinuation: AsyncStream<IncomingEvent>.Continuation

    /// May be invoked on background queues.
    var onState: (@Sendable (ScreenWatcherState) -> Void)?
    var onLog: (@Sendable (LogLevel, String) -> Void)?

    private let sampleQueue = DispatchQueue(label: "com.biomealert.BiomeAlertPro.screenwatcher")
    private let lock = NSLock()
    private var running = false
    private var stream: SCStream?
    private var lifecycleTask: Task<Void, Never>?

    // Accessed only on `sampleQueue`.
    private var lastFrameHash = 0
    /// Links already handled this session — a link is joined once and never
    /// again while the app runs. Capped to avoid unbounded growth.
    private var seenLinks: Set<String> = []
    private var seenOrder: [String] = []
    /// First OCR pass "primes" the seen set from whatever is already on screen
    /// so startup never joins an old link; only links appearing afterward act.
    private var hasPrimed = false
    private let linkDetector = RobloxLinkDetector()

    /// Configurable max on-screen age in seconds; links whose visible age
    /// exceeds this are skipped. 0 disables the age check.
    private var maxAgeSeconds: Double = 0

    private static let maxSeenLinks = 800

    private static let discordBundleIDs: Set<String> = [
        "com.hnc.discord", "com.hnc.discordptb", "com.hnc.discordcanary"
    ]

    /// Sets the freshness limit in seconds (thread-safe; read on the sampler queue).
    func setMaxLinkAgeSeconds(_ seconds: Double) {
        lock.lock()
        maxAgeSeconds = seconds
        lock.unlock()
    }

    private func currentMaxAgeSeconds() -> Double {
        lock.lock()
        defer { lock.unlock() }
        return maxAgeSeconds
    }

    override init() {
        (events, eventContinuation) = AsyncStream.makeStream(of: IncomingEvent.self)
        super.init()
    }

    // MARK: - Lifecycle

    func start() {
        lock.lock()
        if running {
            lock.unlock()
            return
        }
        running = true
        lock.unlock()

        onState?(.waitingForDiscord)
        onLog?(.info, "Screen watcher starting — looking for a Discord window")
        lifecycleTask?.cancel()
        lifecycleTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    func stop() {
        lock.lock()
        let wasRunning = running
        running = false
        let activeStream = stream
        stream = nil
        lock.unlock()

        lifecycleTask?.cancel()
        lifecycleTask = nil
        if let activeStream {
            Task { try? await activeStream.stopCapture() }
        }
        if wasRunning {
            onState?(.stopped)
            onLog?(.info, "Screen watcher stopped")
        }
    }

    private var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    /// Finds a Discord window and attaches a capture stream, retrying until
    /// stopped. Once attached, the loop exits — frame delivery is
    /// event-driven, and `didStopWithError` re-enters the loop.
    private func runLoop() async {
        while isRunning && !Task.isCancelled {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false,
                    onScreenWindowsOnly: false
                )
                guard isRunning else { return }

                if let window = Self.pickDiscordWindow(from: content.windows) {
                    do {
                        try await attach(to: window)
                        let title = window.owningApplication?.applicationName ?? "Discord"
                        onState?(.watching(windowTitle: title))
                        onLog?(.info, "Screen watcher attached to \(title) window (\(Int(window.frame.width))×\(Int(window.frame.height)))")
                        return
                    } catch {
                        onState?(.failed("Could not capture window: \(error.localizedDescription)"))
                        onLog?(.warning, "Screen capture start failed: \(error.localizedDescription)")
                    }
                } else {
                    onState?(.waitingForDiscord)
                }
            } catch {
                // Most commonly: Screen Recording permission not granted.
                onState?(.failed("Needs Screen Recording permission (System Settings → Privacy & Security → Screen Recording), then relaunch"))
                onLog?(.warning, "Screen capture unavailable: \(error.localizedDescription)")
            }
            try? await Task.sleep(for: .seconds(10))
        }
    }

    private func attach(to window: SCWindow) async throws {
        let configuration = SCStreamConfiguration()
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 2) // ≤ 2 fps
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = 3
        configuration.showsCursor = false
        // Capture at 2× for reliable OCR of long private-server codes.
        configuration.width = min(Int(window.frame.width) * 2, 3584)
        configuration.height = min(Int(window.frame.height) * 2, 2240)

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let newStream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        try await newStream.startCapture()

        storeStream(newStream)
        // Re-prime for the new capture so links already visible aren't joined.
        sampleQueue.async { [weak self] in
            self?.hasPrimed = false
            self?.lastFrameHash = 0
        }
    }

    /// Synchronous helper so async code never touches the lock directly
    /// (NSLock.lock/unlock are unavailable from async contexts in Swift 6).
    private func storeStream(_ newStream: SCStream?) {
        lock.lock()
        stream = newStream
        lock.unlock()
    }

    private static func pickDiscordWindow(from windows: [SCWindow]) -> SCWindow? {
        let candidates = windows.filter { window in
            guard let bundleID = window.owningApplication?.bundleIdentifier.lowercased() else {
                return false
            }
            return discordBundleIDs.contains(bundleID)
                && window.frame.width >= 400
                && window.frame.height >= 300
        }
        // Prefer on-screen windows, then the largest.
        return candidates.max { lhs, rhs in
            let lhsKey = (lhs.isOnScreen ? 1 : 0, lhs.frame.width * lhs.frame.height)
            let rhsKey = (rhs.isOnScreen ? 1 : 0, rhs.frame.width * rhs.frame.height)
            return lhsKey < rhsKey
        }
    }

    // MARK: - Frame processing (always on `sampleQueue`)

    /// Cheap sampled hash so OCR only runs when the window content changed.
    private func frameChanged(_ buffer: CVPixelBuffer) -> Bool {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return true }
        let size = CVPixelBufferGetDataSize(buffer)
        var hasher = Hasher()
        var offset = 0
        while offset < size {
            hasher.combine(base.load(fromByteOffset: offset, as: UInt8.self))
            offset += 4099
        }
        let hash = hasher.finalize()
        if hash == lastFrameHash { return false }
        lastFrameHash = hash
        return true
    }

    private func processFrame(_ buffer: CVPixelBuffer) {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Language correction would "fix" link codes into words — keep it off.
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return
        }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        guard !lines.isEmpty else { return }
        handleRecognized(lines: lines)
    }

    private func handleRecognized(lines: [String]) {
        let joined = lines.joined(separator: "\n")
        // Long URLs wrap across lines and OCR can inject spaces into digit
        // runs — a whitespace-stripped pass reassembles them.
        let condensed = joined.filter { !$0.isWhitespace }

        var links = linkDetector.detect(in: joined)
        for link in linkDetector.detect(in: condensed) where !links.contains(link) {
            links.append(link)
        }

        let candidates = links.filter { $0.isJoinable && !seenLinks.contains($0.dedupeKey) }
        guard !candidates.isEmpty else { return }

        // Prime on the first pass: everything already on screen is recorded as
        // seen but never joined — only links that appear later are acted on.
        if !hasPrimed {
            hasPrimed = true
            candidates.forEach { markSeen($0.dedupeKey) }
            onLog?(.info, "Screen watcher ready — \(candidates.count) link(s) already on screen were ignored; only new drops will launch")
            return
        }

        // Freshness filter: skip links whose visible timestamp is older than
        // the configured limit (guards against scrolled-up history). Links
        // with no readable timestamp are treated as fresh, since priming
        // already guarantees they only just appeared on screen.
        let maxAgeSeconds = currentMaxAgeSeconds()
        var fresh: [RobloxLink] = []
        for link in candidates {
            if maxAgeSeconds > 0,
               let ageSeconds = Self.nearestAgeSeconds(for: link, lines: lines),
               ageSeconds > maxAgeSeconds {
                markSeen(link.dedupeKey)
                onLog?(.debug, "Skipped a ~\(Int(ageSeconds))s-old link (older than the \(Int(maxAgeSeconds))s limit)")
                continue
            }
            fresh.append(link)
        }
        guard !fresh.isEmpty else { return }
        fresh.forEach { markSeen($0.dedupeKey) }

        // Context lines around the link let the keyword engine classify the
        // biome; the reassembled links are appended verbatim so detection
        // works even when the on-screen URL was wrapped.
        let context = Self.contextText(lines: lines)
        let content = context + "\n" + fresh.map(\.original).joined(separator: "\n")

        eventContinuation.yield(IncomingEvent(
            source: .screenOCR,
            sender: "Screen OCR",
            content: String(content.prefix(1_500))
        ))
        onLog?(.info, "Screen watcher spotted \(fresh.count) new Roblox link(s)")
    }

    /// Records a link as handled, evicting the oldest entries past the cap.
    private func markSeen(_ key: String) {
        guard seenLinks.insert(key).inserted else { return }
        seenOrder.append(key)
        if seenOrder.count > Self.maxSeenLinks {
            let drop = seenOrder.removeFirst()
            seenLinks.remove(drop)
        }
    }

    /// Finds the smallest relative age (in seconds) mentioned near a link.
    static func nearestAgeSeconds(for link: RobloxLink, lines: [String]) -> Double? {
        let needle = link.linkCode ?? link.placeID ?? ""
        let anchor = lines.firstIndex { !needle.isEmpty && $0.contains(needle) }
            ?? lines.firstIndex { $0.lowercased().contains("roblox.com") }
        let range: Range<Int>
        if let anchor {
            range = max(0, anchor - 8)..<min(lines.count, anchor + 3)
        } else {
            range = 0..<lines.count
        }
        var smallest: Double?
        for line in lines[range] {
            if let age = parseRelativeAgeSeconds(line) {
                smallest = min(smallest ?? age, age)
            }
        }
        return smallest
    }

    /// Parses Discord-style relative timestamps ("8 minutes ago", "just now",
    /// "an hour ago") into seconds. Returns nil when no timestamp is present.
    /// Note: Discord shows "just now" for anything under a minute, so the
    /// finest real resolution from the UI is ~1 minute — priming is what
    /// actually enforces sub-second freshness.
    static func parseRelativeAgeSeconds(_ line: String) -> Double? {
        let text = line.lowercased()
        if text.contains("just now") || text.contains("moments ago")
            || text.contains("a few seconds") {
            return 0
        }
        if text.contains("a minute ago") || text.contains("an minute ago") { return 60 }
        if text.contains("an hour ago") || text.contains("a hour ago") { return 3_600 }
        if text.contains("a day ago") || text.contains("yesterday") { return 86_400 }

        guard let match = text.firstMatch(of: relativeAgeRegex) else { return nil }
        guard let value = Double(String(match.output.1)) else { return nil }
        let unit = String(match.output.2)
        if unit.hasPrefix("sec") { return value }
        if unit.hasPrefix("min") { return value * 60 }
        if unit.hasPrefix("hour") || unit.hasPrefix("hr") { return value * 3_600 }
        if unit.hasPrefix("day") { return value * 86_400 }
        return nil
    }

    nonisolated(unsafe) private static let relativeAgeRegex =
        #/(\d+)\s*(seconds?|secs?|minutes?|mins?|hours?|hrs?|days?)\s*ago/#
        .ignoresCase()

    private static func contextText(lines: [String]) -> String {
        if let index = lines.firstIndex(where: {
            let lowered = $0.lowercased()
            return lowered.contains("roblox.com") || lowered.contains("linkcode")
        }) {
            let start = max(0, index - 8)
            let end = min(lines.count, index + 4)
            return lines[start..<end].joined(separator: "\n")
        }
        return lines.suffix(12).joined(separator: "\n")
    }
}

// MARK: - ScreenCaptureKit callbacks

extension ScreenWatcherService: SCStreamOutput {
    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen,
              isRunning,
              let pixelBuffer = sampleBuffer.imageBuffer else { return }
        guard frameChanged(pixelBuffer) else { return }
        processFrame(pixelBuffer)
    }
}

extension ScreenWatcherService: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        guard isRunning else { return }
        onLog?(.warning, "Screen capture stopped (\(error.localizedDescription)) — rediscovering Discord window")
        lock.lock()
        self.stream = nil
        lock.unlock()
        onState?(.waitingForDiscord)
        lifecycleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            await self?.runLoop()
        }
    }
}
