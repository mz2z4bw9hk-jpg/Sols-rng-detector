import Foundation

/// Delivery state of the most recent send attempt for an outbound webhook.
enum WebhookDeliveryState: String, Codable, Sendable {
    case never
    case ok
    case retrying
    case failed

    var displayName: String {
        switch self {
        case .never: return "No deliveries yet"
        case .ok: return "Delivered"
        case .retrying: return "Retrying"
        case .failed: return "Failed"
        }
    }
}

/// Metadata for a configured outbound Discord webhook.
/// The webhook URL itself contains a secret token, so it is stored in the
/// macOS Keychain and referenced here only by the config's ID.
struct WebhookConfig: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var isEnabled: Bool
    var lastDeliveryState: WebhookDeliveryState
    var lastDeliveryDate: Date?
    var lastDeliveryDetail: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        lastDeliveryState: WebhookDeliveryState = .never,
        lastDeliveryDate: Date? = nil,
        lastDeliveryDetail: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.lastDeliveryState = lastDeliveryState
        self.lastDeliveryDate = lastDeliveryDate
        self.lastDeliveryDetail = lastDeliveryDetail
        self.createdAt = createdAt
    }

    /// Keychain account key under which this webhook's URL is stored.
    var keychainKey: String { "webhook.\(id.uuidString)" }
}
