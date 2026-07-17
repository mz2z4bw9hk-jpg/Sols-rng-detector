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
    /// Use a distinct sound per biome instead of one alert sound.
    @Published var perBiomeSoundsEnabled: Bool { didSet { defaults.set(perBiomeSoundsEnabled, forKey: "perBiomeSoundsEnabled") } }
    /// Biome raw value → system sound name.
    @Published var biomeSounds: [String: String] { didSet { defaults.set(biomeSounds, forKey: "biomeSounds") } }

    // MARK: - Roblox launch
    @Published var autoLaunchRoblox: Bool { didSet { defaults.set(autoLaunchRoblox, forKey: "autoLaunchRoblox") } }
    @Published var launchDelaySeconds: Double { didSet { defaults.set(launchDelaySeconds, forKey: "launchDelaySeconds") } }
    @Published var launchCooldownSeconds: Double { didSet { defaults.set(launchCooldownSeconds, forKey: "launchCooldownSeconds") } }
    /// Only auto-launch for rare biomes (vs. every alert containing a link).
    @Published var launchOnlyForRareBiomes: Bool { didSet { defaults.set(launchOnlyForRareBiomes, forKey: "launchOnlyForRareBiomes") } }
    /// Keep the Roblox client pre-launched while monitoring so joins skip its cold start.
    @Published var prewarmRoblox: Bool { didSet { defaults.set(prewarmRoblox, forKey: "prewarmRoblox") } }

    // MARK: - Detection
    @Published var confidenceThreshold: Double { didSet { defaults.set(confidenceThreshold, forKey: "confidenceThreshold") } }
    /// Comma/newline-separated words that, if present, cause an alert to be ignored.
    @Published var blocklist: String { didSet { defaults.set(blocklist, forKey: "blocklist") } }
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
    /// Skip on-screen links whose visible age exceeds this many seconds. 0 = no age limit.
    @Published var screenWatcherMaxAgeSeconds: Double { didSet { defaults.set(screenWatcherMaxAgeSeconds, forKey: "screenWatcherMaxAgeSeconds") } }
    /// Auto-click the on-screen "Click to Join Server" button (needs Accessibility).
    @Published var autoClickJoinEnabled: Bool { didSet { defaults.set(autoClickJoinEnabled, forKey: "autoClickJoinEnabled") } }

    // MARK: - Channels
    /// Comma-separated Discord channel names the bot should act on. Empty = all channels.
    @Published var channelAllowList: String { didSet { defaults.set(channelAllowList, forKey: "channelAllowList") } }

    // MARK: - Forwarding
    /// Prepend @everyone (and allow the mention) when forwarding alerts to webhooks.
    @Published var pingEveryoneOnForward: Bool { didSet { defaults.set(pingEveryoneOnForward, forKey: "pingEveryoneOnForward") } }

    // MARK: - Discord
    @Published var discordClientID: String { didSet { defaults.set(discordClientID, forKey: "discordClientID") } }
    @Published var forwardAlertsToWebhooks: Bool { didSet { defaults.set(forwardAlertsToWebhooks, forKey: "forwardAlertsToWebhooks") } }

    // MARK: - Hotkeys
    /// Enable system-wide hotkeys (⌥⌘J join last link, ⌥⌘P pause/resume).
    @Published var globalHotkeysEnabled: Bool { didSet { defaults.set(globalHotkeysEnabled, forKey: "globalHotkeysEnabled") } }

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
            "perBiomeSoundsEnabled": false,
            "biomeSounds": Self.defaultBiomeSounds,
            "blocklist": "fake, expired, closed, patched, scam, full, ended, over",
            "globalHotkeysEnabled": false,
            "autoLaunchRoblox": true,
            "launchDelaySeconds": 0.0,
            "launchCooldownSeconds": 120.0,
            "launchOnlyForRareBiomes": false,
            "prewarmRoblox": false,
            "confidenceThreshold": 0.5,
            "duplicateCooldownSeconds": 60.0,
            "cacheDurationMinutes": 10.0,
            "fuzzyMatchingEnabled": true,
            "listenerEnabled": true,
            "listenerPort": 8787,
            "listenerAllowLAN": false,
            "screenWatcherEnabled": false,
            "autoLaunchBiomes": KeywordCategory.allCases.filter(\.isBiome).map(\.rawValue),
            "screenWatcherMaxAgeSeconds": 5.0,
            "autoClickJoinEnabled": false,
            "channelAllowList": "",
            "pingEveryoneOnForward": false,
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
        perBiomeSoundsEnabled = defaults.bool(forKey: "perBiomeSoundsEnabled")
        biomeSounds = (defaults.dictionary(forKey: "biomeSounds") as? [String: String]) ?? Self.defaultBiomeSounds
        blocklist = defaults.string(forKey: "blocklist") ?? ""
        globalHotkeysEnabled = defaults.bool(forKey: "globalHotkeysEnabled")
        autoLaunchRoblox = defaults.bool(forKey: "autoLaunchRoblox")
        launchDelaySeconds = defaults.double(forKey: "launchDelaySeconds")
        launchCooldownSeconds = defaults.double(forKey: "launchCooldownSeconds")
        launchOnlyForRareBiomes = defaults.bool(forKey: "launchOnlyForRareBiomes")
        prewarmRoblox = defaults.bool(forKey: "prewarmRoblox")
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
        screenWatcherMaxAgeSeconds = defaults.double(forKey: "screenWatcherMaxAgeSeconds")
        autoClickJoinEnabled = defaults.bool(forKey: "autoClickJoinEnabled")
        channelAllowList = defaults.string(forKey: "channelAllowList") ?? ""
        pingEveryoneOnForward = defaults.bool(forKey: "pingEveryoneOnForward")
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

    // MARK: - Channel allow-list helpers

    /// Normalized channel names (lowercase, no leading '#'). Empty = allow all.
    var allowedChannels: Set<String> {
        Set(channelAllowList
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .map { $0.hasPrefix("#") ? String($0.dropFirst()) : $0 }
            .filter { !$0.isEmpty })
    }

    /// Whether an alert from `channel` is permitted by the allow-list.
    func isChannelAllowed(_ channel: String?) -> Bool {
        let allowed = allowedChannels
        guard !allowed.isEmpty else { return true }
        guard let channel else { return true } // sources without channel info aren't filtered
        return allowed.contains(channel.lowercased())
    }

    // MARK: - Per-biome sound helpers

    static let defaultBiomeSounds: [String: String] = [
        KeywordCategory.glitched.rawValue: "Sosumi",
        KeywordCategory.dreamspace.rawValue: "Hero",
        KeywordCategory.cyberspace.rawValue: "Submarine",
        KeywordCategory.singularity.rawValue: "Glass"
    ]

    func biomeSound(for category: KeywordCategory) -> String {
        biomeSounds[category.rawValue] ?? alertSoundName
    }

    func setBiomeSound(_ name: String, for category: KeywordCategory) {
        var copy = biomeSounds
        copy[category.rawValue] = name
        biomeSounds = copy
    }

    /// The sound to play for an alert, honoring the per-biome preference.
    func sound(forBiomeDisplayName biome: String?) -> String {
        guard perBiomeSoundsEnabled,
              let biome,
              let category = KeywordCategory.allCases.first(where: { $0.displayName == biome }) else {
            return alertSoundName
        }
        return biomeSound(for: category)
    }

    // MARK: - Blocklist helpers

    /// Normalized block words. An alert whose text contains any of these is dropped.
    var blockedWords: [String] {
        blocklist
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }
}
