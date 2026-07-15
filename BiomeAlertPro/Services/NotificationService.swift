import Foundation
import UserNotifications

/// Posts rich alert notifications and handles the "Launch Roblox" quick action.
final class NotificationService: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let categoryID = "BIOME_ALERT"
    static let launchActionID = "LAUNCH_ROBLOX"
    private static let linkUserInfoKey = "robloxLink"

    /// Invoked (on an arbitrary queue) when the user taps the launch action.
    /// The payload is the original Roblox link string.
    var launchHandler: (@Sendable (String) -> Void)?

    private let center = UNUserNotificationCenter.current()

    /// Registers the delegate + category and requests authorization.
    func setup() async -> Bool {
        center.delegate = self

        let launchAction = UNNotificationAction(
            identifier: Self.launchActionID,
            title: "Launch Roblox",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryID,
            actions: [launchAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])

        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    /// Posts a biome-alert notification.
    /// - Parameters:
    ///   - useSystemSound: when false the app plays its own configurable sound instead.
    func postAlert(record: AlertRecord, link: RobloxLink?, useSystemSound: Bool) async {
        let content = UNMutableNotificationContent()

        if let biome = record.biome {
            content.title = record.isRareBiome ? "🌌 Rare biome: \(biome)!" : "Biome detected: \(biome)"
        } else {
            content.title = "Alert detected"
        }

        var subtitleParts = ["via \(record.source)"]
        if let channel = record.channel, !channel.isEmpty {
            subtitleParts.append("#\(channel)")
        }
        if let sender = record.sender, !sender.isEmpty {
            subtitleParts.append("from \(sender)")
        }
        content.subtitle = subtitleParts.joined(separator: " · ")

        var bodyParts: [String] = []
        let snippet = record.content.prefix(120)
        if !snippet.isEmpty { bodyParts.append(String(snippet)) }
        if link != nil { bodyParts.append("Roblox link detected — ready to launch.") }
        bodyParts.append(String(format: "Detected in %.0f ms", record.latencyMs))
        content.body = bodyParts.joined(separator: "\n")

        content.categoryIdentifier = Self.categoryID
        if useSystemSound {
            content.sound = .default
        }
        if let link {
            content.userInfo = [Self.linkUserInfoKey: link.original]
        }

        let request = UNNotificationRequest(
            identifier: record.id.uuidString,
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let link = userInfo[Self.linkUserInfoKey] as? String
        let action = response.actionIdentifier

        if let link,
           action == Self.launchActionID || action == UNNotificationDefaultActionIdentifier {
            launchHandler?(link)
        }
    }
}
