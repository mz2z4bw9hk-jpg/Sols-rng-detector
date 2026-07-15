import AppKit
import UniformTypeIdentifiers

/// NSSavePanel / NSOpenPanel helpers used by export & import flows.
/// Sandbox-safe: user-selected locations are granted automatically.
@MainActor
enum Panels {
    static func saveData(_ data: Data, suggestedName: String, contentType: UTType) -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [contentType]
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            presentError("Could not save file: \(error.localizedDescription)")
            return false
        }
    }

    static func openData(contentTypes: [UTType]) -> Data? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = contentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return try? Data(contentsOf: url)
    }

    static func presentError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Something went wrong"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
