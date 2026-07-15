import Foundation
import SwiftUI

/// App theme preference.
enum AppTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// User-configurable settings backed by `UserDefaults`.
/// Secrets (webhook URLs, tokens, listener shared secret) live in the
/// Keychain, never here.
@MainActor
final class SettingsStore: ObservableObject {
    private let defaults: UserDefaults

    /// Called when the menu-bar-only preference changes so the app can update
    /// its activation policy.
    var onMenuBarOnlyChanged: ((Bool) -> Void)?

    // MARK: - Notifications & sound
    @Published var notificationsEnabled: Bool { didSet { defaults.set(notificationsEnabled, forKey: "notificationsEnabled") } }
    @Published var soundEnabled: Bool { didSet { defaults.set(soundEnabled, forKey: "soundEnabled") } }
    @Published var alertSoundName: String { didSet { defaults.set(alertSoundName, forKey: "alertSoundName") } }

    // MARK: - Roblox launch
    @Published var autoLaunchRoblox: Bool { didSet { defaults.set(autoLaunchRoblox, forKey: "autoLaunchRoblox") } }
    @Published var launchDelaySeconds: Double { didSet { defaults.set(launchDelaySeconds, forKey: "launchDelaySeconds") } }
    @Published var launchCooldownSeconds: Double { didSet { defaults.set(launchCooldownSeconds, forKey: "launchCooldownSeconds") } }
    /// Only auto-launch for rare biomes (vs. every alert containing a link).
    @Published var launchOnlyForRareBiomes: Bool { didSet { defaults.set(launchOnlyForRareBiomes, forKey: "launchOnlyForRareBiomes") } }

    // MARK: - Detection
    @Published var confidenceThreshold: Double { didSet { defaults.set(confidenceThreshold, forKey: "confidenceThreshold") } }
    @Published var duplicateCooldownSeconds: Double { didSet { defaults.set(duplicateCooldownSeconds, forKey: "duplicateCooldownSeconds") } }
    /// How long dedupe cache entries are retained, in minutes.
    @Published var cacheDurationMinutes: Double { didSet { defaults.set(cacheDurationMinutes, forKey: "cacheDurationMinutes") } }
    @Published var fuzzyMatchingEnabled: Bool { didSet { defaults.set(fuzzyMatchingEnabled, forKey: "fuzzyMatchingEnabled") } }

    // MARK: - Webhook listener
    @Published var listenerEnabled: Bool { didSet { defaults.set(listenerEnabled, forKey: "listenerEnabled") } }
    @Published var listenerPort: Int { didSet { defaults.set(listenerPort, forKey: "listenerPort") } }
    @Published var listenerAllowLAN: Bool { didSet { defaults.set(listenerAllowLAN, forKey: "listenerAllowLAN") } }

    // MARK: - Screen watcher
    @Published var screenWatcherEnabled: Bool { didSet { defaults.set(screenWatcherEnabled, forKey: "screenWatcherEnabled") } }
    /// Raw values of `KeywordCategory` biomes that may auto-launch Roblox.
    @Published var autoLaunchBiomes: [String] { didSet { defaults.set(autoLaunchBiomes, forKey: "autoLaunchBiomes") } }

    // MARK: - Discord
    @Published var discordClientID: String { didSet { defaults.set(discordClientID, forKey: "discordClientID") } }
    @Published var forwardAlertsToWebhooks: Bool { didSet { defaults.set(forwardAlertsToWebhooks, forKey: "forwardAlertsToWebhooks") } }

    // MARK: - Appearance & behavior
    @Published var theme: AppTheme { didSet { defaults.set(theme.rawValue, forKey: "theme") } }
    @Published var menuBarEnabled: Bool { didSet { defaults.set(menuBarEnabled, forKey: "menuBarEnabled") } }
    @Published var menuBarOnly: Bool {
        didSet {
            defaults.set(menuBarOnly, forKey: "menuBarOnly")
            onMenuBarOnlyChanged?(menuBarOnly)
        }
    }

    // MARK: - Performance & logging
    @Published var cpuLimitPercent: Double { didSet { defaults.set(cpuLimitPercent, forKey: "cpuLimitPercent") } }
    @Published var loggingLevel: LogLevel { didSet { defaults.set(loggingLevel.rawValue, forKey: "loggingLevel") } }
    @Published var historyLimit: Int { didSet { defaults.set(historyLimit, forKey: "historyLimit") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            "notificationsEnabled": true,
            "soundEnabled": true,
            "alertSoundName": "Glass",
            "autoLaunchRoblox": true,
            "launchDelaySeconds": 0.0,
            "launchCooldownSeconds": 120.0,
            "launchOnlyForRareBiomes": false,
            "confidenceThreshold": 0.5,
            "duplicateCooldownSeconds": 60.0,
            "cacheDurationMinutes": 10.0,
            "fuzzyMatchingEnabled": true,
            "listenerEnabled": true,
            "listenerPort": 8787,
            "listenerAllowLAN": false,
            "screenWatcherEnabled": false,
            "autoLaunchBiomes": KeywordCategory.allCases.filter(\.isBiome).map(\.rawValue),
            "discordClientID": "",
            "forwardAlertsToWebhooks": false,
            "theme": AppTheme.system.rawValue,
            "menuBarEnabled": true,
            "menuBarOnly": false,
            "cpuLimitPercent": 2.0,
            "loggingLevel": LogLevel.info.rawValue,
            "historyLimit": 5_000
        ])

        notificationsEnabled = defaults.bool(forKey: "notificationsEnabled")
        soundEnabled = defaults.bool(forKey: "soundEnabled")
        alertSoundName = defaults.string(forKey: "alertSoundName") ?? "Glass"
        autoLaunchRoblox = defaults.bool(forKey: "autoLaunchRoblox")
        launchDelaySeconds = defaults.double(forKey: "launchDelaySeconds")
        launchCooldownSeconds = defaults.double(forKey: "launchCooldownSeconds")
        launchOnlyForRareBiomes = defaults.bool(forKey: "launchOnlyForRareBiomes")
        confidenceThreshold = defaults.double(forKey: "confidenceThreshold")
        duplicateCooldownSeconds = defaults.double(forKey: "duplicateCooldownSeconds")
        cacheDurationMinutes = defaults.double(forKey: "cacheDurationMinutes")
        fuzzyMatchingEnabled = defaults.bool(forKey: "fuzzyMatchingEnabled")
        listenerEnabled = defaults.bool(forKey: "listenerEnabled")
        listenerPort = defaults.integer(forKey: "listenerPort")
        listenerAllowLAN = defaults.bool(forKey: "listenerAllowLAN")
        screenWatcherEnabled = defaults.bool(forKey: "screenWatcherEnabled")
        autoLaunchBiomes = defaults.stringArray(forKey: "autoLaunchBiomes")
            ?? KeywordCategory.allCases.filter(\.isBiome).map(\.rawValue)
        discordClientID = defaults.string(forKey: "discordClientID") ?? ""
        forwardAlertsToWebhooks = defaults.bool(forKey: "forwardAlertsToWebhooks")
        theme = AppTheme(rawValue: defaults.string(forKey: "theme") ?? "") ?? .system
        menuBarEnabled = defaults.bool(forKey: "menuBarEnabled")
        menuBarOnly = defaults.bool(forKey: "menuBarOnly")
        cpuLimitPercent = defaults.double(forKey: "cpuLimitPercent")
        loggingLevel = LogLevel(rawValue: defaults.string(forKey: "loggingLevel") ?? "") ?? .info
        historyLimit = defaults.integer(forKey: "historyLimit")
    }

    // MARK: - Auto-launch biome helpers

    func isBiomeAutoLaunchEnabled(_ category: KeywordCategory) -> Bool {
        autoLaunchBiomes.contains(category.rawValue)
    }

    func setBiomeAutoLaunch(_ category: KeywordCategory, enabled: Bool) {
        var set = Set(autoLaunchBiomes)
        if enabled {
            set.insert(category.rawValue)
        } else {
            set.remove(category.rawValue)
        }
        autoLaunchBiomes = set.sorted()
    }
}
