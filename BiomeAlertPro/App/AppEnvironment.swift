import AppKit
import Foundation
import SwiftUI

/// Composition root: owns every service (dependency injection happens here),
/// wires the event pipeline, and exposes app-wide observable state.
@MainActor
final class AppEnvironment: ObservableObject {
    // MARK: - Services

    let settings: SettingsStore
    let logs: LogStore
    let secrets: any SecretStoring
    let keywords: KeywordStore
    let webhooks: WebhookStore
    let history: HistoryStore
    let stats: StatsStore
    let performance: PerformanceMonitor
    let oauth: DiscordOAuthService
    let launcher: RobloxLauncher
    let notifications: NotificationService
    let sounds: SoundPlayer
    let listener: WebhookListenerService
    let gateway: DiscordGatewayService
    let screenWatcher: ScreenWatcherService
    let hotKeys = HotKeyService()
    let autoClicker = AutoClicker()

    private var pipeline: AlertPipeline?
    private var bootstrapped = false
    /// Most recent joinable link, for the "join last" hotkey / menu action.
    private var lastJoinableLink: RobloxLink?

    // MARK: - Published state

    @Published var isMonitoring = false
    @Published var listenerState: ListenerState = .stopped
    @Published var gatewayStatus: GatewayStatus = .disconnected
    @Published var screenWatcherState: ScreenWatcherState = .stopped
    @Published var notificationsAuthorized = false
    @Published var botTokenConfigured = false

    static let botTokenKeychainKey = "discord.botToken"
    static let listenerSecretKeychainKey = "listener.sharedSecret"

    var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    // MARK: - Init

    init(secrets: any SecretStoring = KeychainService()) {
        let settings = SettingsStore()
        let logs = LogStore()
        self.settings = settings
        self.logs = logs
        self.secrets = secrets
        self.keywords = KeywordStore(logs: logs)
        self.webhooks = WebhookStore(secrets: secrets, client: DiscordWebhookClient(), logs: logs)
        self.history = HistoryStore(logs: logs)
        self.stats = StatsStore()
        self.performance = PerformanceMonitor()
        self.oauth = DiscordOAuthService(settings: settings, secrets: secrets, logs: logs)
        self.launcher = RobloxLauncher(logs: logs)
        self.notifications = NotificationService()
        self.sounds = SoundPlayer()
        self.listener = WebhookListenerService()
        self.gateway = DiscordGatewayService()
        self.screenWatcher = ScreenWatcherService()

        logs.minimumLevel = settings.loggingLevel
        history.limit = settings.historyLimit
        performance.cpuLimitPercent = settings.cpuLimitPercent
        botTokenConfigured = ((try? secrets.secret(for: Self.botTokenKeychainKey)) ?? nil)?.isEmpty == false

        settings.onMenuBarOnlyChanged = { [weak self] _ in
            self?.applyActivationPolicy()
        }
    }

    // MARK: - Lifecycle

    /// One-time startup. Safe to call repeatedly. The real work is deferred
    /// one runloop turn so published state never mutates inside a SwiftUI
    /// view update (callers may be in `.task`/`onAppear`).
    func bootstrap() {
        guard !bootstrapped else { return }
        bootstrapped = true
        Task { @MainActor [weak self] in
            self?.performBootstrap()
        }
    }

    private func performBootstrap() {
        logs.log(.info, .lifecycle, "Biome Alert Pro \(appVersion) starting up")

        // Pipeline consumes every source stream.
        let pipeline = AlertPipeline(environment: self)
        self.pipeline = pipeline
        let listenerEvents = listener.events
        let gatewayEvents = gateway.events
        let screenEvents = screenWatcher.events
        Task {
            await pipeline.consume(listenerEvents)
            await pipeline.consume(gatewayEvents)
            await pipeline.consume(screenEvents)
        }

        // Listener state → published UI state.
        listener.onState = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                self.listenerState = state
                if case .failed(let message) = state {
                    self.logs.log(.error, .network, "Listener: \(message)")
                }
            }
        }
        listener.onLog = { [weak self] level, message in
            Task { @MainActor in
                self?.logs.log(level, .network, message)
            }
        }

        // Screen watcher callbacks.
        screenWatcher.onState = { [weak self] state in
            Task { @MainActor in
                self?.screenWatcherState = state
            }
        }
        screenWatcher.onLog = { [weak self] level, message in
            Task { @MainActor in
                self?.logs.log(level, .detection, message)
            }
        }
        screenWatcher.onClickRequest = { [weak self] point, biome in
            Task { @MainActor in
                self?.performJoinClick(at: point, biome: biome)
            }
        }

        // Gateway callbacks.
        Task {
            await gateway.setHandlers(
                status: { [weak self] status in
                    Task { @MainActor in
                        self?.gatewayStatus = status
                    }
                },
                log: { [weak self] level, message in
                    Task { @MainActor in
                        self?.logs.log(level, .network, message)
                    }
                }
            )
        }

        // Notifications: authorization + quick-launch action.
        notifications.launchHandler = { [weak self] linkString in
            Task { @MainActor in
                self?.launchFromNotification(linkString)
            }
        }
        Task {
            let granted = await notifications.setup()
            notificationsAuthorized = granted
            logs.log(granted ? .info : .warning, .lifecycle,
                     granted ? "Notification permission granted" : "Notification permission denied")
        }

        // Restore Discord OAuth session.
        Task {
            await oauth.restoreSession()
        }

        // Performance sampling.
        performance.onWarning = { [weak self] message in
            self?.logs.log(.warning, .performance, message)
        }
        performance.start()

        // Global hotkeys.
        hotKeys.onJoinLast = { [weak self] in
            Task { @MainActor in self?.joinLastLink() }
        }
        hotKeys.onTogglePause = { [weak self] in
            Task { @MainActor in self?.toggleMonitoring() }
        }
        hotKeys.onClickNewest = { [weak self] in
            Task { @MainActor in self?.screenWatcher.requestManualClick() }
        }
        applyHotkeySetting()

        if settings.listenerEnabled || botTokenConfigured || settings.screenWatcherEnabled {
            startMonitoring()
        }
        applyActivationPolicy()
    }

    func shutdown() {
        logs.log(.info, .lifecycle, "Biome Alert Pro shutting down")
        stopMonitoring()
        hotKeys.unregister()
        performance.stop()
    }

    // MARK: - Monitoring control

    func startMonitoring() {
        isMonitoring = true
        logs.log(.info, .lifecycle, "Monitoring started")

        if settings.listenerEnabled {
            let secret = (try? secrets.secret(for: Self.listenerSecretKeychainKey)) ?? nil
            listener.start(
                port: UInt16(clamping: settings.listenerPort),
                sharedSecret: secret,
                allowLAN: settings.listenerAllowLAN
            )
        }
        if botTokenConfigured, let token = (try? secrets.secret(for: Self.botTokenKeychainKey)) ?? nil {
            Task { await gateway.start(token: token) }
        }
        if settings.screenWatcherEnabled {
            screenWatcher.setMaxLinkAgeSeconds(settings.screenWatcherMaxAgeSeconds)
            screenWatcher.setBiomeClickTargets(screenWatcherBiomeTargets())
            screenWatcher.setClickToJoin(settings.autoClickJoinEnabled)
            screenWatcher.start()
        }
        if settings.prewarmRoblox {
            launcher.prewarm()
        }
    }

    /// Map of keyword → biome display name (per enabled auto-launch biome)
    /// that the screen-watcher click mode uses to classify a Join button's
    /// message and decide whether to press it.
    func screenWatcherBiomeTargets() -> [String: String] {
        let enabled = KeywordCategory.allCases.filter { $0.isBiome && settings.isBiomeAutoLaunchEnabled($0) }
        var map: [String: String] = [:]
        for category in enabled {
            map[category.rawValue] = category.displayName
            map[category.displayName] = category.displayName
            for keyword in keywords.enabledKeywords where keyword.category == category {
                map[keyword.text] = category.displayName
            }
        }
        return map
    }

    func stopMonitoring() {
        isMonitoring = false
        listener.stop()
        screenWatcher.stop()
        Task { await gateway.stop() }
        logs.log(.info, .lifecycle, "Monitoring stopped")
    }

    func toggleMonitoring() {
        if isMonitoring {
            stopMonitoring()
        } else {
            startMonitoring()
        }
    }

    /// Registers or removes the global hotkeys per the current setting.
    func applyHotkeySetting() {
        if settings.globalHotkeysEnabled {
            hotKeys.register()
            logs.log(.info, .lifecycle, "Global hotkeys enabled (⌥⌘J join last · ⌥⌘P pause)")
        } else {
            hotKeys.unregister()
        }
    }

    /// Presses a Join button the screen watcher located: brings Discord to the
    /// front if it isn't already (so the click lands), clicks, then records
    /// feedback — biome sound, notification, and an Alert History entry.
    func performJoinClick(at point: CGPoint, biome: String) {
        let discord = NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier?.lowercased().contains("discord") == true
        }
        let discordIsFront = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == discord?.bundleIdentifier

        if discordIsFront || discord == nil {
            autoClicker.click(at: point)
            recordClickFeedback(biome: biome)
        } else {
            // Raise Discord, then click once its window is frontmost.
            discord?.activate(options: [])
            let clicker = autoClicker
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                clicker.click(at: point)
                self?.recordClickFeedback(biome: biome)
            }
        }
    }

    private func recordClickFeedback(biome: String) {
        let category = KeywordCategory.allCases.first { $0.displayName == biome }
        let isRare = category?.isRare ?? false
        let record = AlertRecord(
            source: "Screen Watcher (click)",
            sender: nil,
            content: "Clicked “Click to Join Server” for \(biome)",
            matchedKeywords: [biome],
            biome: biome,
            isRareBiome: isRare,
            confidence: 1.0,
            robloxLink: nil,
            linkKind: "Join button",
            latencyMs: 0,
            launchStatus: .launched
        )
        history.add(record)
        stats.recordAlert(record: record)
        stats.recordLaunch()

        if settings.soundEnabled {
            sounds.play(named: settings.sound(forBiomeDisplayName: biome))
        }
        if settings.notificationsEnabled {
            let playOwnSound = settings.soundEnabled
            Task { await notifications.postAlert(record: record, link: nil, useSystemSound: !playOwnSound) }
        }
        logs.log(.info, .launch, "Joined \(biome) via on-screen button", symbol: category?.symbolName)
    }

    /// Joins the most recently detected joinable link (hotkey / menu action).
    func joinLastLink() {
        guard let link = lastJoinableLink else {
            logs.log(.warning, .launch, "Join-last requested but no link has been detected yet")
            return
        }
        logs.log(.info, .launch, "Join-last triggered")
        performLaunch(recordID: nil, link: link)
    }

    var hasLastLink: Bool { lastJoinableLink != nil }

    /// Applies the screen-watcher toggle immediately while monitoring.
    func applyScreenWatcherSetting() {
        screenWatcher.setMaxLinkAgeSeconds(settings.screenWatcherMaxAgeSeconds)
        screenWatcher.setBiomeClickTargets(screenWatcherBiomeTargets())
        screenWatcher.setClickToJoin(settings.autoClickJoinEnabled)
        guard isMonitoring else { return }
        if settings.screenWatcherEnabled {
            screenWatcher.start()
        } else {
            screenWatcher.stop()
        }
    }

    /// Applies listener setting changes by restarting the endpoint.
    func restartListenerIfRunning() {
        guard isMonitoring, settings.listenerEnabled else {
            listener.stop()
            return
        }
        let secret = (try? secrets.secret(for: Self.listenerSecretKeychainKey)) ?? nil
        listener.start(
            port: UInt16(clamping: settings.listenerPort),
            sharedSecret: secret,
            allowLAN: settings.listenerAllowLAN
        )
    }

    // MARK: - Bot token management

    func saveBotToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try secrets.setSecret(trimmed, for: Self.botTokenKeychainKey)
            botTokenConfigured = true
            logs.log(.info, .security, "Bot token stored in Keychain")
            if isMonitoring {
                Task { await gateway.start(token: trimmed) }
            }
        } catch {
            logs.log(.error, .security, "Failed to store bot token: \(error.localizedDescription)")
        }
    }

    func removeBotToken() {
        try? secrets.deleteSecret(for: Self.botTokenKeychainKey)
        botTokenConfigured = false
        Task { await gateway.stop() }
        logs.log(.info, .security, "Bot token removed")
    }

    func saveListenerSecret(_ secret: String) {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try? secrets.deleteSecret(for: Self.listenerSecretKeychainKey)
        } else {
            try? secrets.setSecret(trimmed, for: Self.listenerSecretKeychainKey)
        }
        restartListenerIfRunning()
    }

    var listenerSecretConfigured: Bool {
        (((try? secrets.secret(for: Self.listenerSecretKeychainKey)) ?? nil)?.isEmpty == false)
    }

    // MARK: - Pipeline hooks (called from the AlertPipeline actor)

    func detectionConfiguration() -> DetectionConfiguration {
        DetectionConfiguration(
            keywords: keywords.enabledKeywords,
            confidenceThreshold: settings.confidenceThreshold,
            duplicateCooldown: settings.duplicateCooldownSeconds,
            cacheDuration: settings.cacheDurationMinutes * 60,
            fuzzyEnabled: settings.fuzzyMatchingEnabled,
            allowedChannels: settings.allowedChannels,
            blockWords: settings.blockedWords
        )
    }

    func logPipeline(_ level: LogLevel, _ message: String) {
        logs.log(level, .detection, message)
    }

    /// Delivers a confirmed alert. Launch happens FIRST — before history,
    /// notification, or sound — because every millisecond counts when a rare
    /// biome server is filling up.
    func deliver(record: AlertRecord, link: RobloxLink?) {
        var pendingRecord = record

        if let link, link.isJoinable {
            lastJoinableLink = link
            if shouldAutoLaunch(record: pendingRecord) {
                let delay = settings.launchDelaySeconds
                if delay <= 0 {
                    // Synchronous fast path: open Roblox before anything else.
                    let result = launcher.launch(link, cooldownSeconds: settings.launchCooldownSeconds)
                    if case .launched = result {
                        stats.recordLaunch()
                    }
                    pendingRecord.launchStatus = result.status
                } else {
                    let recordID = pendingRecord.id
                    Task { [weak self] in
                        try? await Task.sleep(for: .seconds(delay))
                        self?.performLaunch(recordID: recordID, link: link)
                    }
                }
            } else {
                pendingRecord.launchStatus = .disabled
            }
        }

        // Immutable snapshot from here on (safe to capture in Tasks).
        let delivered = pendingRecord

        history.add(delivered)
        stats.recordAlert(record: delivered)

        let summary = delivered.biome.map { "\($0) biome" } ?? "Alert"
        let biomeSymbol = delivered.biome.flatMap { name in
            KeywordCategory.allCases.first { $0.displayName == name }?.symbolName
        }
        logs.log(.info, .detection, String(format: "%@ detected via %@ (confidence %.2f, %.0f ms)",
                                           summary, delivered.source, delivered.confidence, delivered.latencyMs),
                 symbol: biomeSymbol)

        if settings.notificationsEnabled {
            let playOwnSound = settings.soundEnabled
            Task {
                await notifications.postAlert(record: delivered, link: link, useSystemSound: !playOwnSound)
            }
        }
        if settings.soundEnabled {
            sounds.play(named: settings.sound(forBiomeDisplayName: delivered.biome))
        }

        if settings.forwardAlertsToWebhooks {
            let message = Self.forwardMessage(for: delivered, pingEveryone: settings.pingEveryoneOnForward)
            Task { await webhooks.broadcast(message: message) }
        }
    }

    /// Launch policy: master switch → rare-only filter → per-biome selection.
    /// Alerts without a recognized biome (bare links) follow the master switch.
    private func shouldAutoLaunch(record: AlertRecord) -> Bool {
        guard settings.autoLaunchRoblox else { return false }
        if settings.launchOnlyForRareBiomes && !record.isRareBiome { return false }
        if let biome = record.biome,
           let category = KeywordCategory.allCases.first(where: { $0.displayName == biome }) {
            return settings.isBiomeAutoLaunchEnabled(category)
        }
        return true
    }

    private func performLaunch(recordID: UUID?, link: RobloxLink) {
        let result = launcher.launch(link, cooldownSeconds: settings.launchCooldownSeconds)
        if case .launched = result {
            stats.recordLaunch()
        }
        if let recordID {
            history.updateLaunchStatus(id: recordID, status: result.status)
        }
    }

    /// Manual launch from history rows or notification actions.
    func launchLink(_ linkString: String) {
        let detected = RobloxLinkDetector().detect(in: linkString)
        guard let link = detected.first else {
            logs.log(.warning, .launch, "Manual launch failed: unrecognized link")
            return
        }
        performLaunch(recordID: nil, link: link)
    }

    private func launchFromNotification(_ linkString: String) {
        logs.log(.info, .launch, "Launch requested from notification")
        launchLink(linkString)
    }

    // MARK: - Test alert

    /// Injects a synthetic event through the full pipeline (useful for
    /// verifying notifications, sound, and launch behavior end to end).
    func sendTestAlert() {
        guard let pipeline else { return }
        let event = IncomingEvent(
            source: .manualTest,
            sender: "Biome Alert Pro",
            content: "GLITCHED biome test — private server: " +
                "https://www.roblox.com/games/15532962292/Sols-RNG?privateServerLinkCode=TEST-\(Int.random(in: 10_000...99_999))"
        )
        logs.log(.info, .detection, "Test alert injected")
        Task { await pipeline.ingest(event) }
    }

    // MARK: - Appearance

    func applyActivationPolicy() {
        let desired: NSApplication.ActivationPolicy = settings.menuBarOnly ? .accessory : .regular
        if NSApplication.shared.activationPolicy() != desired {
            _ = NSApplication.shared.setActivationPolicy(desired)
        }
    }

    private static func forwardMessage(for record: AlertRecord, pingEveryone: Bool) -> String {
        var parts: [String] = []
        if pingEveryone {
            parts.append("@everyone")
        }
        if let biome = record.biome {
            parts.append(record.isRareBiome ? "🌌 **\(biome)** detected!" : "**\(biome)** detected")
        } else {
            parts.append("🔔 Alert detected")
        }
        var origin = "Source: \(record.source)"
        if let channel = record.channel {
            origin += " · #\(channel)"
        }
        parts.append(origin)
        if let link = record.robloxLink {
            parts.append(link)
        }
        return parts.joined(separator: "\n")
    }
}
