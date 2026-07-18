import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Live checks for the macOS permissions the app depends on. All are cheap,
/// synchronous, and non-prompting — safe to call from a view body.
enum SystemPermissions {
    /// Screen Recording (required by the screen watcher's capture).
    static var screenRecording: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Accessibility (required only for the auto-click feature).
    static var accessibility: Bool {
        AXIsProcessTrusted()
    }

    /// Opens the relevant System Settings privacy pane.
    static func openScreenRecordingSettings() {
        openSettings("Privacy_ScreenCapture")
    }

    static func openAccessibilitySettings() {
        openSettings("Privacy_Accessibility")
    }

    private static func openSettings(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }
}
