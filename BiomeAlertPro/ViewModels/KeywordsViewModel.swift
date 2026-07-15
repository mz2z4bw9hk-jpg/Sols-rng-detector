import Foundation
import UniformTypeIdentifiers

/// Form state and actions for the Keywords screen.
@MainActor
final class KeywordsViewModel: ObservableObject {
    @Published var isPresentingForm = false
    @Published var newText = ""
    @Published var newCategory: KeywordCategory = .custom
    @Published var newMatchMode: KeywordMatchMode = .partial
    @Published var newWeight: Double = 0.5
    @Published var selection = Set<UUID>()
    @Published var statusMessage: String?

    private let store: KeywordStore

    init(store: KeywordStore) {
        self.store = store
    }

    func presentAddForm(category: KeywordCategory = .custom) {
        newText = ""
        newCategory = category
        newMatchMode = .partial
        newWeight = 0.5
        isPresentingForm = true
    }

    /// Returns true when the keyword was added and the form can close.
    func submitForm() -> Bool {
        let text = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        if newMatchMode == .regex {
            guard (try? Regex(text)) != nil else {
                statusMessage = "Invalid regular expression."
                return false
            }
        }
        store.add(Keyword(
            text: text,
            category: newCategory,
            matchMode: newMatchMode,
            weight: newWeight,
            allowsFuzzy: text.count >= 5 && newMatchMode != .regex
        ))
        statusMessage = nil
        isPresentingForm = false
        return true
    }

    func deleteSelection() {
        guard !selection.isEmpty else { return }
        store.delete(ids: selection)
        selection.removeAll()
    }

    func restoreDefaults() {
        store.restoreDefaults()
        statusMessage = "Defaults restored."
    }

    func exportDatabase() {
        do {
            let data = try store.exportData()
            if Panels.saveData(data, suggestedName: "BiomeAlertPro-Keywords.json", contentType: .json) {
                statusMessage = "Keyword database exported."
            }
        } catch {
            Panels.presentError("Export failed: \(error.localizedDescription)")
        }
    }

    func importDatabase() {
        guard let data = Panels.openData(contentTypes: [.json]) else { return }
        do {
            let added = try store.importData(data)
            statusMessage = "Imported \(added) new keyword(s)."
        } catch {
            Panels.presentError("Import failed — the file isn't a valid keyword database. (\(error.localizedDescription))")
        }
    }
}
