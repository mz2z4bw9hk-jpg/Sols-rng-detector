import Foundation

/// Where an event entered the app from.
enum EventSource: String, Codable, CaseIterable, Sendable {
    case webhookListener
    case discordBot
    case screenOCR
    case manualTest

    var displayName: String {
        switch self {
        case .webhookListener: return "Webhook Listener"
        case .discordBot: return "Discord Bot"
        case .screenOCR: return "Screen Watcher"
        case .manualTest: return "Manual Test"
        }
    }

    var symbolName: String {
        switch self {
        case .webhookListener: return "antenna.radiowaves.left.and.right"
        case .discordBot: return "bubble.left.and.bubble.right.fill"
        case .screenOCR: return "eye.fill"
        case .manualTest: return "hammer.fill"
        }
    }
}

/// A normalized incoming alert event, regardless of transport.
struct IncomingEvent: Sendable {
    /// Upstream message ID when available (used for duplicate suppression).
    let id: String?
    let source: EventSource
    let sender: String?
    /// Originating Discord channel name (e.g. "glitched-snipes"), when known.
    let channel: String?
    /// Primary message content.
    let content: String
    /// Flattened text extracted from embeds (titles, descriptions, fields, URLs).
    let embedText: String
    /// When the app received the event (basis for latency measurements).
    let receivedAt: Date

    init(
        id: String? = nil,
        source: EventSource,
        sender: String? = nil,
        channel: String? = nil,
        content: String,
        embedText: String = "",
        receivedAt: Date = Date()
    ) {
        self.id = id
        self.source = source
        self.sender = sender
        self.channel = channel
        self.content = content
        self.embedText = embedText
        self.receivedAt = receivedAt
    }

    /// All searchable text for keyword and link detection.
    var fullText: String {
        embedText.isEmpty ? content : content + "\n" + embedText
    }
}
