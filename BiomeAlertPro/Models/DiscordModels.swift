import Foundation

/// Discord-webhook-style payload accepted by the local webhook listener.
/// Mirrors the shape of Discord's "Execute Webhook" JSON body so existing
/// alert forwarders can point at Biome Alert Pro without changes.
struct DiscordWebhookPayload: Codable, Sendable {
    struct Embed: Codable, Sendable {
        struct Field: Codable, Sendable {
            let name: String?
            let value: String?
        }
        let title: String?
        let description: String?
        let url: String?
        let fields: [Field]?

        var flattenedText: String {
            var parts: [String] = []
            if let title { parts.append(title) }
            if let description { parts.append(description) }
            if let url { parts.append(url) }
            for field in fields ?? [] {
                if let name = field.name { parts.append(name) }
                if let value = field.value { parts.append(value) }
            }
            return parts.joined(separator: "\n")
        }
    }

    let id: String?
    let content: String?
    let username: String?
    let embeds: [Embed]?

    var embedText: String {
        (embeds ?? []).map(\.flattenedText).filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

/// Minimal fallback payload: `{"message": "..."}`.
struct SimpleMessagePayload: Codable, Sendable {
    let message: String
}

/// Discord user object returned by `/users/@me` (official OAuth API).
struct DiscordUser: Codable, Sendable {
    let id: String
    let username: String
    let discriminator: String?
    let globalName: String?
    let avatar: String?

    enum CodingKeys: String, CodingKey {
        case id, username, discriminator, avatar
        case globalName = "global_name"
    }

    var displayName: String { globalName ?? username }

    var avatarURL: URL? {
        guard let avatar else { return nil }
        return URL(string: "https://cdn.discordapp.com/avatars/\(id)/\(avatar).png?size=128")
    }
}

/// OAuth token response from Discord's official token endpoint.
struct DiscordTokenResponse: Codable, Sendable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Double
    let refreshToken: String?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
}

/// Webhook metadata returned by GET on a webhook URL (used for validation).
struct DiscordWebhookInfo: Codable, Sendable {
    let id: String
    let name: String?
    let channelID: String?
    let guildID: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case channelID = "channel_id"
        case guildID = "guild_id"
    }
}
