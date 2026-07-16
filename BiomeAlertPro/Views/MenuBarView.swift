import SwiftUI

/// Compact status panel shown from the menu bar icon.
struct MenuBarView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MenuBarContent(environment: environment, openWindow: { openWindow(id: "main") })
    }
}

private struct MenuBarContent: View {
    @EnvironmentObject private var environment: AppEnvironment
    @ObservedObject var stats: StatsStore
    let openWindow: () -> Void

    init(environment: AppEnvironment, openWindow: @escaping () -> Void) {
        _stats = ObservedObject(wrappedValue: environment.stats)
        self.openWindow = openWindow
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                Text("Biome Alert Pro")
                    .font(.headline)
                Spacer()
                StatusBadge(
                    kind: environment.isMonitoring ? .ok : .neutral,
                    text: environment.isMonitoring ? "Active" : "Paused"
                )
            }

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Alerts today").foregroundStyle(.secondary)
                    Text("\(stats.alertsToday)").monospacedDigit()
                }
                GridRow {
                    Text("Rare biomes").foregroundStyle(.secondary)
                    Text("\(stats.rareBiomesDetected)").monospacedDigit()
                }
                GridRow {
                    Text("Launches").foregroundStyle(.secondary)
                    Text("\(stats.robloxLaunchCount)").monospacedDigit()
                }
                GridRow {
                    Text("Last detection").foregroundStyle(.secondary)
                    Text(stats.lastDetection.map { $0.formatted(.relative(presentation: .named)) } ?? "—")
                }
            }
            .font(.callout)

            Divider()

            Button {
                environment.joinLastLink()
            } label: {
                Label("Join Last Link", systemImage: "arrow.down.right.circle.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(!environment.hasLastLink)
            .help("Launch Roblox for the most recently detected link")

            HStack {
                Button {
                    environment.toggleMonitoring()
                } label: {
                    Label(
                        environment.isMonitoring ? "Pause" : "Start",
                        systemImage: environment.isMonitoring ? "pause.fill" : "play.fill"
                    )
                }

                Button {
                    openWindow()
                    NSApplication.shared.activate(ignoringOtherApps: true)
                } label: {
                    Label("Open Dashboard", systemImage: "macwindow")
                }

                Spacer()

                Button(role: .destructive) {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .help("Quit Biome Alert Pro")
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 300)
    }
}
