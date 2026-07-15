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

    // MARK: - Connection status

    private var statusSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                statusRow(
                    title: "Monitoring",
                    badge: StatusBadge(
                        kind: environment.isMonitoring ? .ok : .neutral,
                        text: environment.isMonitoring ? "Active" : "Paused"
                    )
                )
                Divider()
                statusRow(
                    title: "Webhook Listener",
                    badge: StatusBadge(kind: listenerBadgeKind, text: environment.listenerState.displayName)
                )
                Divider()
                statusRow(
                    title: "Discord Bot",
                    badge: StatusBadge(kind: gatewayBadgeKind, text: environment.gatewayStatus.displayName)
                )
                Divider()
                statusRow(
                    title: "Discord Account",
                    badge: StatusBadge(
                        kind: oauth.isSignedIn ? .ok : .neutral,
                        text: oauth.user.map { "Signed in as \($0.displayName)" } ?? "Not signed in"
                    )
                )
                Divider()
                statusRow(
                    title: "Notifications",
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

    private func statusRow(title: String, badge: StatusBadge) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
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
