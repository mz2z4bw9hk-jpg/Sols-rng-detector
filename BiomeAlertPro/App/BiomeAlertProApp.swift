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

        MenuBarExtra(isInserted: $settings.menuBarEnabled) {
            MenuBarView()
                .environmentObject(environment)
                .environmentObject(settings)
        } label: {
            Image(systemName: environment.isMonitoring ? "sparkles" : "pause.circle")
        }
        .menuBarExtraStyle(.window)
    }
}
