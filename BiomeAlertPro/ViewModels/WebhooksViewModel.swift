import Foundation

/// Form state and actions for the Webhooks screen.
@MainActor
final class WebhooksViewModel: ObservableObject {
    @Published var isPresentingForm = false
    @Published var editingID: UUID?
    @Published var nameInput = ""
    @Published var urlInput = ""
    @Published var validationMessage: String?
    @Published var testResults: [UUID: String] = [:]
    @Published var testingID: UUID?

    private let store: WebhookStore

    init(store: WebhookStore) {
        self.store = store
    }

    var formTitle: String { editingID == nil ? "Add Webhook" : "Edit Webhook" }

    func presentAddForm() {
        editingID = nil
        nameInput = ""
        urlInput = ""
        validationMessage = nil
        isPresentingForm = true
    }

    func presentEditForm(for webhook: WebhookConfig) {
        editingID = webhook.id
        nameInput = webhook.name
        urlInput = store.url(for: webhook.id) ?? ""
        validationMessage = nil
        isPresentingForm = true
    }

    /// Returns true when the form was saved and can be dismissed.
    func submitForm() -> Bool {
        let url = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard DiscordWebhookClient.isValidWebhookURL(url) else {
            validationMessage = "That doesn't look like a Discord webhook URL. Expected: https://discord.com/api/webhooks/…"
            return false
        }
        do {
            if let editingID {
                store.rename(id: editingID, to: nameInput)
                try store.updateURL(id: editingID, urlString: url)
            } else {
                try store.add(name: nameInput, urlString: url)
            }
            isPresentingForm = false
            return true
        } catch {
            validationMessage = error.localizedDescription
            return false
        }
    }

    func runTest(for webhook: WebhookConfig, pingEveryone: Bool = false) {
        testingID = webhook.id
        testResults[webhook.id] = nil
        Task { [weak self] in
            guard let self else { return }
            let result = await self.store.test(id: webhook.id, pingEveryone: pingEveryone)
            self.testingID = nil
            switch result {
            case .success(let message):
                self.testResults[webhook.id] = "✅ \(message)"
            case .failure(let error):
                self.testResults[webhook.id] = "⚠️ \(error.localizedDescription)"
            }
        }
    }
}
