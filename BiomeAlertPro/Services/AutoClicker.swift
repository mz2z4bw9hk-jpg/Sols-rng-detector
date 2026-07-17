import ApplicationServices
import CoreGraphics
import Foundation

/// Synthesizes a real mouse click at a screen point so the app can press the
/// "Click to Join Server" button inside Discord when the join URL is hidden
/// behind a hyperlink (OCR cannot read a hyperlink's target).
///
/// Requirements — both are unavoidable for posting input to another app:
///   • the app must NOT be sandboxed (the sandbox blocks synthetic events), and
///   • the user must grant Accessibility permission (TCC).
///
/// Coordinates are in the global display coordinate space (points, top-left
/// origin), which is what `CGEvent` expects and what `SCWindow.frame` reports.
final class AutoClicker: @unchecked Sendable {
    /// Whether Accessibility permission has been granted.
    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the user to grant Accessibility permission (opens the system
    /// dialog / Settings pane). Safe to call repeatedly.
    static func requestAccessibilityPermission() {
        let key = kAXTrustedCheckOptionPrompt as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Left-clicks at `point`, then restores the cursor to where it was so the
    /// user's pointer doesn't visibly jump and stay moved.
    func click(at point: CGPoint) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let restore = CGEvent(source: nil)?.location

        let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                           mouseCursorPosition: point, mouseButton: .left)
        let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                         mouseCursorPosition: point, mouseButton: .left)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)

        if let restore {
            CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                    mouseCursorPosition: restore, mouseButton: .left)?
                .post(tap: .cghidEventTap)
        }
    }
}
