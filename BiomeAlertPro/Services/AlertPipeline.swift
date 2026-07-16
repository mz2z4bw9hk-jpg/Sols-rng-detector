import CryptoKit
import Foundation

/// Immutable snapshot of everything the pipeline needs per event, captured
/// from the main actor once per message.
struct DetectionConfiguration: Sendable {
    let keywords: [Keyword]
    let confidenceThreshold: Double
    let duplicateCooldown: TimeInterval
    let cacheDuration: TimeInterval
    let fuzzyEnabled: Bool
    /// Normalized channel names to accept (empty = all). Applies to sources
    /// that report a channel, such as the Discord bot.
    let allowedChannels: Set<String>
    /// Normalized words that, if present in the message, drop the alert.
    let blockWords: [String]
}

/// Background processing stage: consumes normalized incoming events from all
/// sources, suppresses duplicates, runs keyword + link detection, and hands
/// confirmed alerts back to the main actor for delivery. Keeps all string
/// crunching off the UI thread.
actor AlertPipeline {
    private let engine: any KeywordMatching
    private let linkDetector: any LinkDetecting
    private let environment: AppEnvironment

    /// Recently seen event IDs / content hashes → time seen.
    private var recentlySeen: [String: Date] = [:]
    private var consumerTasks: [Task<Void, Never>] = []

    init(
        environment: AppEnvironment,
        engine: any KeywordMatching = KeywordEngine(),
        linkDetector: any LinkDetecting = RobloxLinkDetector()
    ) {
        self.environment = environment
        self.engine = engine
        self.linkDetector = linkDetector
    }

    /// Attaches a source stream; multiple sources are consumed concurrently.
    func consume(_ stream: AsyncStream<IncomingEvent>) {
        let task = Task { [weak self] in
            for await event in stream {
                await self?.ingest(event)
            }
        }
        consumerTasks.append(task)
    }

    func shutdown() {
        for task in consumerTasks { task.cancel() }
        consumerTasks.removeAll()
    }

    /// Processes one event end-to-end.
    func ingest(_ event: IncomingEvent) async {
        let config = await environment.detectionConfiguration()

        // Channel allow-list: for sources that report a channel (the bot),
        // ignore anything outside the user's chosen channels.
        if !config.allowedChannels.isEmpty, let channel = event.channel,
           !config.allowedChannels.contains(channel.lowercased()) {
            await environment.logPipeline(.debug, "Ignored message from #\(channel) (not in channel list)")
            return
        }

        // Blocklist: drop messages containing any blocked word (e.g. a link
        // marked "fake", "expired", or "closed") before doing anything else.
        if !config.blockWords.isEmpty {
            let normalized = KeywordEngine.normalize(event.fullText)
            if let hit = config.blockWords.first(where: { normalized.contains($0) }) {
                await environment.logPipeline(.info, "Ignored alert — blocklisted word “\(hit)”")
                return
            }
        }

        // Expire dedupe cache entries.
        let now = Date()
        let ttl = max(config.cacheDuration, config.duplicateCooldown)
        recentlySeen = recentlySeen.filter { now.timeIntervalSince($0.value) < ttl }

        // Duplicate suppression: upstream message ID first, content hash second.
        if let id = event.id, !id.isEmpty {
            let key = "id:\(event.source.rawValue):\(id)"
            if let seen = recentlySeen[key], now.timeIntervalSince(seen) < config.duplicateCooldown {
                await environment.logPipeline(.debug, "Dropped duplicate event (same ID)")
                return
            }
            recentlySeen[key] = now
        }
        let hashKey = "hash:" + Self.contentHash(event.fullText)
        if let seen = recentlySeen[hashKey], now.timeIntervalSince(seen) < config.duplicateCooldown {
            await environment.logPipeline(.debug, "Dropped duplicate event (same content)")
            return
        }
        recentlySeen[hashKey] = now

        // Detection.
        let detection = engine.detect(in: event.fullText, keywords: config.keywords, fuzzyEnabled: config.fuzzyEnabled)
        let links = linkDetector.detect(in: event.fullText)
        let bestLink = links.first

        // Biome classification: prefer the text match; otherwise infer from the
        // channel name (e.g. a bare link in "singularity-snipes" → Singularity).
        var biomeCategory = detection.biomeCategory
        if biomeCategory == nil, bestLink?.isJoinable == true, let channel = event.channel {
            biomeCategory = KeywordCategory.inferredFromChannel(channel)
        }

        var confidence = detection.confidence
        if let bestLink {
            confidence += bestLink.isJoinable ? 0.25 : 0.1
        }
        // A joinable link posted in a biome-named channel is a strong signal on
        // its own, even if the message text is just the URL.
        if detection.biomeCategory == nil, biomeCategory != nil {
            confidence = max(confidence, 0.6)
        }
        confidence = min(1.0, confidence)

        let isRare = biomeCategory?.isRare ?? false
        let isAlert = confidence >= config.confidenceThreshold
            || isRare
            || (bestLink?.isJoinable == true && !detection.matches.isEmpty)
            || (bestLink?.isJoinable == true && biomeCategory != nil)

        guard isAlert else {
            if !detection.matches.isEmpty || bestLink != nil {
                await environment.logPipeline(
                    .debug,
                    String(format: "Event below threshold (%.2f < %.2f) — ignored", confidence, config.confidenceThreshold)
                )
            }
            return
        }

        let latencyMs = Date().timeIntervalSince(event.receivedAt) * 1_000
        let record = AlertRecord(
            source: event.source.displayName,
            sender: event.sender,
            channel: event.channel,
            content: String(event.fullText.prefix(500)),
            matchedKeywords: detection.matchedKeywordTexts,
            biome: biomeCategory?.displayName,
            isRareBiome: isRare,
            confidence: confidence,
            robloxLink: bestLink?.original,
            linkKind: bestLink?.kind.displayName,
            latencyMs: latencyMs
        )
        await environment.deliver(record: record, link: bestLink)
    }

    private static func contentHash(_ text: String) -> String {
        let normalized = KeywordEngine.normalize(text)
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
