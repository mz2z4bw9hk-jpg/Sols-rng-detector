import AppKit
import Foundation

/// Outcome of a launch attempt.
enum LaunchResult: Sendable, Equatable {
    case launched(viaDeepLink: Bool)
    case suppressedDuplicate
    case failed(String)

    var status: LaunchStatus {
        switch self {
        case .launched: return .launched
        case .suppressedDuplicate: return .suppressedDuplicate
        case .failed: return .failed
        }
    }
}

/// Launches Roblox for a detected link, preferring the `roblox://` deep link
/// (direct into the private server) and falling back to the HTTPS URL.
/// Suppresses repeat launches of the same server within a cooldown window.
@MainActor
final class RobloxLauncher: ObservableObject {
    @Published private(set) var lastLaunchDate: Date?

    private var recentLaunches: [String: Date] = [:]
    private let logs: LogStore

    init(logs: LogStore) {
        self.logs = logs
    }

    /// Whether the Roblox app is installed (i.e. something claims roblox://).
    var isRobloxInstalled: Bool {
        guard let probe = URL(string: "roblox://placeId=0") else { return false }
        return NSWorkspace.shared.urlForApplication(toOpen: probe) != nil
    }

    /// Whether the Roblox client is currently running.
    var isRobloxRunning: Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier?.lowercased().hasPrefix("com.roblox") == true
        }
    }

    /// Launches the Roblox app in the background (no game) so a later join
    /// skips the client's cold start — a multi-second head start on busy
    /// rare-biome servers.
    func prewarm() {
        guard !isRobloxRunning,
              let probe = URL(string: "roblox://placeId=0"),
              let appURL = NSWorkspace.shared.urlForApplication(toOpen: probe) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration, completionHandler: nil)
        logs.log(.info, .launch, "Pre-warmed Roblox in the background for faster joins")
    }

    func launch(_ link: RobloxLink, cooldownSeconds: Double) -> LaunchResult {
        // Duplicate suppression per server/link code.
        let now = Date()
        recentLaunches = recentLaunches.filter { now.timeIntervalSince($0.value) < max(cooldownSeconds, 1) }
        if let last = recentLaunches[link.dedupeKey],
           now.timeIntervalSince(last) < cooldownSeconds {
            logs.log(.info, .launch, "Suppressed duplicate launch for \(link.kind.displayName)")
            return .suppressedDuplicate
        }

        var openedViaDeepLink = false
        var opened = false

        if isRobloxInstalled, let deepLink = link.deepLinkURL {
            opened = NSWorkspace.shared.open(deepLink)
            openedViaDeepLink = opened
        }
        if !opened, let webURL = link.webURL {
            opened = NSWorkspace.shared.open(webURL)
        }

        guard opened else {
            logs.log(.error, .launch, "Failed to launch Roblox — no handler for link")
            return .failed("macOS could not open the Roblox link. Is Roblox installed?")
        }

        recentLaunches[link.dedupeKey] = now
        lastLaunchDate = now
        logs.log(.info, .launch, "Launched Roblox via \(openedViaDeepLink ? "deep link" : "browser fallback") (\(link.kind.displayName))")
        return .launched(viaDeepLink: openedViaDeepLink)
    }
}
