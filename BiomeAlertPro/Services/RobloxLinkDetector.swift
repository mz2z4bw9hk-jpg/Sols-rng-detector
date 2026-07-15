import Foundation

/// Abstraction for testability / dependency injection.
protocol LinkDetecting: Sendable {
    func detect(in text: String) -> [RobloxLink]
}

/// Extracts and validates Roblox links from message text.
///
/// Recognized forms (checked in priority order):
/// 1. Private server links: `https://www.roblox.com/games/<id>/...?privateServerLinkCode=<code>`
/// 2. `roblox://` deep links
/// 3. Share links: `https://www.roblox.com/share?code=<code>&type=Server`
/// 4. Game links + standalone job IDs (UUIDs)
/// 5. Plain game links
struct RobloxLinkDetector: LinkDetecting {

    func detect(in text: String) -> [RobloxLink] {
        var links: [RobloxLink] = []
        var seenKeys = Set<String>()

        func append(_ link: RobloxLink) {
            if seenKeys.insert(link.dedupeKey).inserted {
                links.append(link)
            }
        }

        // 1. Private server links.
        for match in text.matches(of: Self.privateServerRegex) {
            let placeID = String(match.output.1)
            let code = String(match.output.2)
            guard Self.isValidPlaceID(placeID), Self.isValidLinkCode(code) else { continue }
            append(RobloxLink(
                kind: .privateServer,
                original: Self.cleanURL(String(match.output.0)),
                placeID: placeID,
                linkCode: code,
                jobID: nil
            ))
        }

        // 2. roblox:// deep links.
        for match in text.matches(of: Self.deepLinkRegex) {
            let raw = Self.cleanURL(String(match.output))
            let placeID = Self.firstCapture(of: Self.deepLinkPlaceIDRegex, in: raw)
            let code = Self.firstCapture(of: Self.deepLinkCodeRegex, in: raw)
            append(RobloxLink(kind: .deepLink, original: raw, placeID: placeID, linkCode: code, jobID: nil))
        }

        // 3. Share links (only server-type shares are joinable).
        for match in text.matches(of: Self.shareLinkRegex) {
            let raw = Self.cleanURL(String(match.output.0))
            let code = String(match.output.1)
            guard Self.isValidLinkCode(code), raw.lowercased().contains("type=server") else { continue }
            append(RobloxLink(kind: .shareLink, original: raw, placeID: nil, linkCode: code, jobID: nil))
        }

        // 4/5. Game links; pair the first one with a standalone job ID if present.
        let gameMatches = text.matches(of: Self.gameLinkRegex)
        let jobID = Self.firstCapture(of: Self.jobIDRegex, in: text)
        for (index, match) in gameMatches.enumerated() {
            let placeID = String(match.output.1)
            guard Self.isValidPlaceID(placeID) else { continue }
            let raw = Self.cleanURL(String(match.output.0))
            if index == 0, let jobID {
                append(RobloxLink(kind: .jobID, original: raw, placeID: placeID, linkCode: nil, jobID: jobID))
            } else {
                append(RobloxLink(kind: .game, original: raw, placeID: placeID, linkCode: nil, jobID: nil))
            }
        }

        // Joinable links first.
        return links.sorted { lhs, rhs in
            (lhs.isJoinable ? 0 : 1) < (rhs.isJoinable ? 0 : 1)
        }
    }

    // MARK: - Patterns

    nonisolated(unsafe) private static let privateServerRegex =
        #/https?://(?:www\.|web\.)?roblox\.com/games/(\d{1,15})[^\s<>"']*?[?&]privateServerLinkCode=([A-Za-z0-9_-]{4,128})/#
        .ignoresCase()

    nonisolated(unsafe) private static let shareLinkRegex =
        #/https?://(?:www\.)?roblox\.com/share\?[^\s<>"']*?code=([A-Za-z0-9_-]{4,128})[^\s<>"']*/#
        .ignoresCase()

    nonisolated(unsafe) private static let gameLinkRegex =
        #/https?://(?:www\.|web\.)?roblox\.com/games/(\d{1,15})[^\s<>"']*/#
        .ignoresCase()

    nonisolated(unsafe) private static let deepLinkRegex =
        #/roblox://[^\s<>"']+/#
        .ignoresCase()

    nonisolated(unsafe) private static let deepLinkPlaceIDRegex =
        #/placeId=(\d{1,15})/#
        .ignoresCase()

    nonisolated(unsafe) private static let deepLinkCodeRegex =
        #/linkCode=([A-Za-z0-9_-]{4,128})/#
        .ignoresCase()

    nonisolated(unsafe) private static let jobIDRegex =
        #/\b([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\b/#

    // MARK: - Validation helpers

    static func isValidPlaceID(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 15 && value.allSatisfy(\.isNumber) && value != "0"
    }

    static func isValidLinkCode(_ value: String) -> Bool {
        value.count >= 4 && value.count <= 128
    }

    /// Strips trailing punctuation that commonly rides along in chat messages
    /// (markdown closers, sentence punctuation).
    static func cleanURL(_ raw: String) -> String {
        var result = raw
        while let last = result.last, ")]>.,;:!\"'".contains(last) {
            result.removeLast()
        }
        return result
    }

    private static func firstCapture(of regex: Regex<(Substring, Substring)>, in text: String) -> String? {
        guard let match = text.firstMatch(of: regex) else { return nil }
        return String(match.output.1)
    }
}
