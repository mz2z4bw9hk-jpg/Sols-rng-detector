import SwiftUI

/// Sidebar destinations.
enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard
    case sources
    case webhooks
    case keywords
    case history
    case logs
    case settings
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .sources: return "Sources"
        case .webhooks: return "Webhooks"
        case .keywords: return "Keywords"
        case .history: return "Alert History"
        case .logs: return "Logs"
        case .settings: return "Settings"
        case .about: return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "gauge.medium"
        case .sources: return "antenna.radiowaves.left.and.right"
        case .webhooks: return "link.badge.plus"
        case .keywords: return "text.magnifyingglass"
        case .history: return "clock.arrow.circlepath"
        case .logs: return "doc.text.magnifyingglass"
        case .settings: return "gearshape"
        case .about: return "info.circle"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var selection: SidebarItem? = .dashboard

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Monitor") {
                    sidebarRow(.dashboard)
                    sidebarRow(.sources)
                    sidebarRow(.webhooks)
                }
                Section("Detection") {
                    sidebarRow(.keywords)
                    sidebarRow(.history)
                    sidebarRow(.logs)
                }
                Section("App") {
                    sidebarRow(.settings)
                    sidebarRow(.about)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .safeAreaInset(edge: .bottom) {
                monitoringFooter
            }
        } detail: {
            detailView
        }
    }

    private func sidebarRow(_ item: SidebarItem) -> some View {
        Label(item.title, systemImage: item.systemImage)
            .tag(item)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection ?? .dashboard {
        case .dashboard: DashboardView()
        case .sources: SourcesView()
        case .webhooks: WebhooksView()
        case .keywords: KeywordsView()
        case .history: HistoryView()
        case .logs: LogsView()
        case .settings: SettingsView()
        case .about: AboutView()
        }
    }

    private var monitoringFooter: some View {
        VStack(spacing: 8) {
            Divider()
            HStack {
                StatusBadge(
                    kind: environment.isMonitoring ? .ok : .neutral,
                    text: environment.isMonitoring ? "Monitoring" : "Paused"
                )
                Spacer()
                Button {
                    withAnimation {
                        if environment.isMonitoring {
                            environment.stopMonitoring()
                        } else {
                            environment.startMonitoring()
                        }
                    }
                } label: {
                    Image(systemName: environment.isMonitoring ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.borderless)
                .help(environment.isMonitoring ? "Pause monitoring" : "Start monitoring")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }
}
