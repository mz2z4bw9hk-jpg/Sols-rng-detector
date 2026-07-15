import AppKit

/// AppKit lifecycle glue: keeps the app alive without windows (background
/// monitoring / menu-bar mode) and performs clean shutdown logging.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by `BiomeAlertProApp.init` before the delegate callbacks fire.
    static var sharedEnvironment: AppEnvironment?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.sharedEnvironment?.bootstrap()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep monitoring in the background / menu bar.
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        Self.sharedEnvironment?.shutdown()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }
}
