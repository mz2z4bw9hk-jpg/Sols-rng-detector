import Foundation

/// A validated Roblox link extracted from an incoming event.
struct RobloxLink: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case privateServer
        case shareLink
        case game
        case deepLink
        case jobID

        var displayName: String {
            switch self {
            case .privateServer: return "Private Server"
            case .shareLink: return "Share Link"
            case .game: return "Game Link"
            case .deepLink: return "Deep Link"
            case .jobID: return "Job ID"
            }
        }
    }

    let kind: Kind
    /// The original URL / identifier as it appeared in the message.
    let original: String
    let placeID: String?
    let linkCode: String?
    let jobID: String?

    /// Whether this link can join a specific server (vs. just opening a game page).
    var isJoinable: Bool {
        switch kind {
        case .privateServer, .shareLink, .jobID, .deepLink: return true
        case .game: return false
        }
    }

    /// Best-effort `roblox://` deep link for direct app launch.
    var deepLinkURL: URL? {
        switch kind {
        case .privateServer:
            guard let placeID, let linkCode else { return nil }
            return URL(string: "roblox://placeId=\(placeID)&linkCode=\(linkCode)")
        case .jobID:
            guard let placeID, let jobID else { return nil }
            return URL(string: "roblox://experiences/start?placeId=\(placeID)&gameInstanceId=\(jobID)")
        case .deepLink:
            return URL(string: original)
        case .shareLink, .game:
            return nil
        }
    }

    /// HTTPS fallback that can be opened in a browser (hands off to Roblox).
    var webURL: URL? {
        if original.lowercased().hasPrefix("http") {
            return URL(string: original)
        }
        if let placeID {
            return URL(string: "https://www.roblox.com/games/\(placeID)")
        }
        return nil
    }

    /// A stable key used for duplicate-launch suppression.
    var dedupeKey: String {
        if let linkCode { return "code:\(linkCode)" }
        if let jobID { return "job:\(jobID)" }
        return "url:\(original.lowercased())"
    }
}
