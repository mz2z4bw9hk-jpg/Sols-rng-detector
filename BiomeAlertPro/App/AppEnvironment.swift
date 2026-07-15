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

    private var pipeline: AlertPipeline?
    private var bootstrapped = false

    // MARK: - Published state

    @Published var isMonitoring = false
    @Published var listenerState: ListenerState = .stopped
    @Published var gatewayStatus: GatewayStatus = .disconnected
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

        logs.minimumLevel = settings.loggingLevel
        history.limit = settings.historyLimit
        performance.cpuLimitPercent = settings.cpuLimitPercent
        botTokenConfigured = ((try? secrets.secret(for: Self.botTokenKeychainKey)) ?? nil)?.isEmpty == false

        settings.onMenuBarOnlyChanged = { [weak self] _ in
            self?.applyActivationPolicy()
        }
    }

    // MARK: - Lifecycle

    /// One-time startup: wires callbacks, starts the pipeline and any enabled
    /// sources. Safe to call repeatedly.
    func bootstrap() {
        guard !bootstrapped else { return }
        bootstrapped = true

        logs.log(.info, .lifecycle, "Biome Alert Pro \(appVersion) starting up")

        // Pipeline consumes every source stream.
        let pipeline = AlertPipeline(environment: self)
        self.pipeline = pipeline
        let listenerEvents = listener.events
        let gatewayEvents = gateway.events
        Task {
            await pipeline.consume(listenerEvents)
            await pipeline.consume(gatewayEvents)
        }

        // Listener state → published UI state.
        listener.onState = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                let wasActive = self.listenerState.isActive
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.listenerState = state
                }
                if case .failed(let message) = state, wasActive || !message.isEmpty {
                    self.logs.log(.error, .network, "Listener: \(message)")
                }
            }
        }
        listener.onLog = { [weak self] level, message in
            Task { @MainActor in
                self?.logs.log(level, .network, message)
            }
        }

        // Gateway callbacks.
        Task {
            await gateway.setHandlers(
                status: { [weak self] status in
                    Task { @MainActor in
                        guard let self else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            self.gatewayStatus = status
                        }
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

        if settings.listenerEnabled || botTokenConfigured {
            startMonitoring()
        }
        applyActivationPolicy()
    }

    func shutdown() {
        logs.log(.info, .lifecycle, "Biome Alert Pro shutting down")
        stopMonitoring()
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
    }

    func stopMonitoring() {
        isMonitoring = false
        listener.stop()
        Task { await gateway.stop() }
        logs.log(.info, .lifecycle, "Monitoring stopped")
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
            fuzzyEnabled: settings.fuzzyMatchingEnabled
        )
    }

    func logPipeline(_ level: LogLevel, _ message: String) {
        logs.log(level, .detection, message)
    }

    /// Delivers a confirmed alert: history, stats, notification, sound,
    /// optional webhook forwarding, and (optionally) auto-launching Roblox.
    func deliver(record: AlertRecord, link: RobloxLink?) {
        history.add(record)
        stats.recordAlert(record: record)

        let summary = record.biome.map { "\($0) biome" } ?? "Alert"
        logs.log(.info, .detection, String(format: "%@ detected via %@ (confidence %.2f, %.0f ms)",
                                           summary, record.source, record.confidence, record.latencyMs))

        if settings.notificationsEnabled {
            let playOwnSound = settings.soundEnabled
            Task {
                await notifications.postAlert(record: record, link: link, useSystemSound: !playOwnSound)
            }
        }
        if settings.soundEnabled {
            sounds.play(named: settings.alertSoundName)
        }

        if settings.forwardAlertsToWebhooks {
            let message = Self.forwardMessage(for: record)
            Task { await webhooks.broadcast(message: message) }
        }

        // Auto-launch Roblox for joinable links.
        if let link, link.isJoinable {
            if !settings.autoLaunchRoblox {
                history.updateLaunchStatus(id: record.id, status: .disabled)
            } else if settings.launchOnlyForRareBiomes && !record.isRareBiome {
                history.updateLaunchStatus(id: record.id, status: .disabled)
            } else {
                let delay = settings.launchDelaySeconds
                Task { [weak self] in
                    if delay > 0 {
                        try? await Task.sleep(for: .seconds(delay))
                    }
                    self?.performLaunch(recordID: record.id, link: link)
                }
            }
        }
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
        _ = NSApplication.shared.setActivationPolicy(settings.menuBarOnly ? .accessory : .regular)
    }

    private static func forwardMessage(for record: AlertRecord) -> String {
        var parts: [String] = []
        if let biome = record.biome {
            parts.append(record.isRareBiome ? "🌌 **\(biome)** detected!" : "**\(biome)** detected")
        } else {
            parts.append("🔔 Alert detected")
        }
        parts.append("Source: \(record.source)")
        if let link = record.robloxLink {
            parts.append(link)
        }
        return parts.joined(separator: "\n")
    }
}
