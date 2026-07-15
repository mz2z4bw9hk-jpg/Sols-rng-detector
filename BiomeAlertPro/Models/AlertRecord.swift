import Foundation

/// Result of attempting to launch Roblox for an alert.
enum LaunchStatus: String, Codable, CaseIterable, Sendable {
    case none
    case launched
    case suppressedDuplicate
    case failed
    case disabled

    var displayName: String {
        switch self {
        case .none: return "—"
        case .launched: return "Launched"
        case .suppressedDuplicate: return "Duplicate"
        case .failed: return "Failed"
        case .disabled: return "Auto-launch Off"
        }
    }

    var symbolName: String {
        switch self {
        case .none: return "minus"
        case .launched: return "checkmark.circle.fill"
        case .suppressedDuplicate: return "arrow.triangle.2.circlepath"
        case .failed: return "xmark.circle.fill"
        case .disabled: return "pause.circle"
        }
    }
}

/// A persisted entry in the alert history.
struct AlertRecord: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let date: Date
    let source: String
    let sender: String?
    /// Message excerpt that triggered the alert.
    let content: String
    let matchedKeywords: [String]
    /// Display name of the detected biome, if any.
    let biome: String?
    let isRareBiome: Bool
    /// 0...1 detection confidence.
    let confidence: Double
    let robloxLink: String?
    let linkKind: String?
    /// Milliseconds from receipt to detection completion.
    let latencyMs: Double
    var launchStatus: LaunchStatus

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        source: String,
        sender: String?,
        content: String,
        matchedKeywords: [String],
        biome: String?,
        isRareBiome: Bool,
        confidence: Double,
        robloxLink: String?,
        linkKind: String?,
        latencyMs: Double,
        launchStatus: LaunchStatus = .none
    ) {
        self.id = id
        self.date = date
        self.source = source
        self.sender = sender
        self.content = content
        self.matchedKeywords = matchedKeywords
        self.biome = biome
        self.isRareBiome = isRareBiome
        self.confidence = confidence
        self.robloxLink = robloxLink
        self.linkKind = linkKind
        self.latencyMs = latencyMs
        self.launchStatus = launchStatus
    }
}
