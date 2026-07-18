import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        DashboardContent(
            stats: environment.stats,
            performance: environment.performance,
            webhooks: environment.webhooks,
            oauth: environment.oauth,
            settings: environment.settings
        )
    }
}

private struct DashboardContent: View {
    @EnvironmentObject private var environment: AppEnvironment
    @ObservedObject var stats: StatsStore
    @ObservedObject var performance: PerformanceMonitor
    @ObservedObject var webhooks: WebhookStore
    @ObservedObject var oauth: DiscordOAuthService
    @ObservedObject var settings: SettingsStore

    private let columns = [GridItem(.adaptive(minimum: 190), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                heroSection
                readinessSection
                statusSection
                statsSection
                systemSection
            }
            .padding(20)
        }
        .navigationTitle("Dashboard")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    environment.sendTestAlert()
                } label: {
                    Label("Test Alert", systemImage: "bell.badge")
                }
                .help("Send a synthetic alert through the full detection pipeline")
            }
        }
    }

    // MARK: - Readiness

    @State private var readinessRefresh = 0

    private var readinessSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                readinessRow(
                    ok: SystemPermissions.screenRecording,
                    title: "Screen Recording",
                    detail: "Required for the screen watcher",
                    fix: { SystemPermissions.openScreenRecordingSettings() }
                )
                Divider()
                readinessRow(
                    ok: SystemPermissions.accessibility,
                    title: "Accessibility",
                    detail: "Required for auto-clicking the Join button",
                    fix: { SystemPermissions.openAccessibilitySettings() }
                )
                Divider()
                readinessRow(
                    ok: environment.notificationsAuthorized,
                    title: "Notifications",
                    detail: "Biome alerts on screen",
                    fix: nil
                )
                Divider()
                readinessRow(
                    ok: environment.launcher.isRobloxInstalled,
                    title: "Roblox installed",
                    detail: "Direct roblox:// launches (else browser fallback)",
                    fix: nil
                )
            }
            .padding(6)
            .id(readinessRefresh)
        } label: {
            HStack {
                SectionTitle(title: "Readiness", systemImage: "checklist")
                Spacer()
                Button {
                    readinessRefresh += 1
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Re-check permissions")
            }
        }
    }

    private func readinessRow(ok: Bool, title: String, detail: String, fix: (() -> Void)?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !ok, let fix {
                Button("Open Settings", action: fix)
                    .controlSize(.small)
            } else {
                Text(ok ? "Ready" : "Not set")
                    .font(.caption)
                    .foregroundStyle(ok ? .green : .orange)
            }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(environment.isMonitoring ? Color.green.opacity(0.15) : Color.secondary.opacity(0.12))
                    .frame(width: 54, height: 54)
                Image(systemName: environment.isMonitoring ? "sparkles" : "pause.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(environment.isMonitoring ? Color.green : Color.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(environment.isMonitoring ? "Monitoring Active" : "Monitoring Paused")
                    .font(.title2.weight(.bold))
                Text(heroSubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                environment.toggleMonitoring()
            } label: {
                Label(
                    environment.isMonitoring ? "Pause" : "Start",
                    systemImage: environment.isMonitoring ? "pause.fill" : "play.fill"
                )
                .frame(minWidth: 64)
            }
            .buttonStyle(.borderedProminent)
            .tint(environment.isMonitoring ? .orange : .green)
            .controlSize(.large)
        }
        .padding(18)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(.easeInOut(duration: 0.2), value: environment.isMonitoring)
    }

    private var heroSubtitle: String {
        if environment.isMonitoring {
            let count = activeSourceCount
            return count == 0
                ? "No sources connected yet — open Sources to add one"
                : "\(count) source\(count == 1 ? "" : "s") live · watching for rare biomes"
        }
        return "Press Start to resume watching for biome alerts"
    }

    // MARK: - Connection status

    private var statusSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                statusRow(
                    title: "Webhook Listener",
                    systemImage: "antenna.radiowaves.left.and.right",
                    badge: StatusBadge(kind: listenerBadgeKind, text: environment.listenerState.displayName)
                )
                Divider()
                statusRow(
                    title: "Screen Watcher",
                    systemImage: "eye",
                    badge: StatusBadge(kind: screenWatcherBadgeKind, text: environment.screenWatcherState.displayName)
                )
                Divider()
                statusRow(
                    title: "Discord Bot",
                    systemImage: "bubble.left.and.bubble.right",
                    badge: StatusBadge(kind: gatewayBadgeKind, text: environment.gatewayStatus.displayName)
                )
                Divider()
                statusRow(
                    title: "Discord Account",
                    systemImage: "person.crop.circle",
                    badge: StatusBadge(
                        kind: oauth.isSignedIn ? .ok : .neutral,
                        text: oauth.user.map { "Signed in as \($0.displayName)" } ?? "Not signed in"
                    )
                )
                Divider()
                statusRow(
                    title: "Notifications",
                    systemImage: "bell.badge",
                    badge: StatusBadge(
                        kind: environment.notificationsAuthorized ? .ok : .warning,
                        text: environment.notificationsAuthorized ? "Authorized" : "Not authorized"
                    )
                )
            }
            .padding(6)
        } label: {
            SectionTitle(title: "Connections", systemImage: "point.3.connected.trianglepath.dotted")
        }
    }

    private func statusRow(title: String, systemImage: String, badge: StatusBadge) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            badge
        }
    }

    private var listenerBadgeKind: StatusBadge.Kind {
        switch environment.listenerState {
        case .listening: return .ok
        case .starting: return .warning
        case .failed: return .error
        case .stopped: return .neutral
        }
    }

    private var gatewayBadgeKind: StatusBadge.Kind {
        switch environment.gatewayStatus {
        case .connected: return .ok
        case .connecting, .reconnecting: return .warning
        case .failed: return .error
        case .disconnected: return .neutral
        }
    }

    private var screenWatcherBadgeKind: StatusBadge.Kind {
        switch environment.screenWatcherState {
        case .watching: return .ok
        case .waitingForDiscord: return .warning
        case .failed: return .error
        case .stopped: return .neutral
        }
    }

    // MARK: - Alert stats

    private var statsSection: some View {
        GroupBox {
            LazyVGrid(columns: columns, spacing: 12) {
                StatCard(
                    title: "Alerts Today",
                    value: "\(stats.alertsToday)",
                    systemImage: "bell.fill"
                )
                StatCard(
                    title: "Rare Biomes Detected",
                    value: "\(stats.rareBiomesDetected)",
                    systemImage: "sparkles",
                    tint: .purple
                )
                StatCard(
                    title: "Roblox Launches",
                    value: "\(stats.robloxLaunchCount)",
                    systemImage: "play.rectangle.fill",
                    tint: .green
                )
                StatCard(
                    title: "Last Detection",
                    value: lastDetectionText,
                    systemImage: "clock.fill",
                    tint: .orange,
                    caption: stats.lastDetection.map { $0.formatted(date: .abbreviated, time: .shortened) }
                )
                StatCard(
                    title: "Detection Latency",
                    value: latencyText,
                    systemImage: "speedometer",
                    tint: .teal,
                    caption: averageLatencyCaption
                )
                StatCard(
                    title: "Active Sources",
                    value: "\(activeSourceCount)",
                    systemImage: "antenna.radiowaves.left.and.right",
                    tint: .blue,
                    caption: "\(webhooks.webhooks.filter(\.isEnabled).count) outbound webhook(s)"
                )
            }
            .padding(6)
        } label: {
            SectionTitle(title: "Activity", systemImage: "chart.bar.fill")
        }
    }

    private var lastDetectionText: String {
        guard let date = stats.lastDetection else { return "—" }
        return date.formatted(.relative(presentation: .named))
    }

    private var latencyText: String {
        guard let latency = stats.lastDetectionLatencyMs else { return "—" }
        return String(format: "%.0f ms", latency)
    }

    private var averageLatencyCaption: String? {
        guard let average = stats.averageLatencyMs else { return nil }
        return String(format: "avg %.0f ms", average)
    }

    private var activeSourceCount: Int {
        var count = 0
        if environment.listenerState.isActive { count += 1 }
        if environment.gatewayStatus.isConnected { count += 1 }
        if environment.screenWatcherState.isActive { count += 1 }
        return count
    }

    // MARK: - System stats

    private var systemSection: some View {
        GroupBox {
            LazyVGrid(columns: columns, spacing: 12) {
                StatCard(
                    title: "CPU Usage",
                    value: String(format: "%.1f%%", performance.cpuPercent),
                    systemImage: "cpu",
                    tint: performance.isOverCPULimit ? .red : .mint,
                    caption: String(format: "target < %.1f%%", settings.cpuLimitPercent)
                )
                StatCard(
                    title: "Memory",
                    value: String(format: "%.0f MB", performance.memoryMB),
                    systemImage: "memorychip",
                    tint: .indigo,
                    caption: "target < 100 MB"
                )
                StatCard(
                    title: "Version",
                    value: environment.appVersion,
                    systemImage: "app.badge.checkmark",
                    tint: .gray
                )
            }
            .padding(6)
        } label: {
            SectionTitle(title: "System", systemImage: "desktopcomputer")
        }
    }
}
