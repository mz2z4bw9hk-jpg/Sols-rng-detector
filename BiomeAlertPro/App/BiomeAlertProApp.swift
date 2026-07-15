import SwiftUI

@main
struct BiomeAlertProApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var environment: AppEnvironment
    @StateObject private var settings: SettingsStore

    init() {
        let environment = AppEnvironment()
        _environment = StateObject(wrappedValue: environment)
        _settings = StateObject(wrappedValue: environment.settings)
        AppDelegate.sharedEnvironment = environment
    }

    var body: some Scene {
        Window("Biome Alert Pro", id: "main") {
            ContentView()
                .environmentObject(environment)
                .environmentObject(settings)
                .frame(minWidth: 960, minHeight: 620)
                .preferredColorScheme(settings.theme.colorScheme)
                .onOpenURL { url in
                    Task { await environment.oauth.handleCallback(url: url) }
                }
                .task {
                    environment.bootstrap()
                }
        }
        .defaultSize(width: 1120, height: 720)

        MenuBarExtra(isInserted: menuBarInsertionBinding) {
            MenuBarView()
                .environmentObject(environment)
                .environmentObject(settings)
        } label: {
            Image(systemName: environment.isMonitoring ? "sparkles" : "pause.circle")
        }
        .menuBarExtraStyle(.window)
    }

    /// MenuBarExtra re-writes its `isInserted` binding during scene updates.
    /// Binding it straight to a @Published property re-publishes on every
    /// write — even identical ones — which spins an infinite update loop
    /// ("Publishing changes from within view updates") and freezes the app.
    /// Dropping same-value writes breaks the cycle.
    private var menuBarInsertionBinding: Binding<Bool> {
        Binding(
            get: { settings.menuBarEnabled },
            set: { newValue in
                guard settings.menuBarEnabled != newValue else { return }
                settings.menuBarEnabled = newValue
            }
        )
    }
}
