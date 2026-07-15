import Foundation

/// Manages outbound Discord webhook configurations. Metadata is persisted to
/// disk; the webhook URLs (which embed a secret token) live in the Keychain.
@MainActor
final class WebhookStore: ObservableObject {
    @Published private(set) var webhooks: [WebhookConfig] = []

    private let secrets: any SecretStoring
    private let client: any WebhookSending
    private let logs: LogStore
    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    init(
        secrets: any SecretStoring,
        client: any WebhookSending,
        logs: LogStore,
        fileURL: URL = StorageLocations.webhooksFile
    ) {
        self.secrets = secrets
        self.client = client
        self.logs = logs
        self.fileURL = fileURL
        load()
    }

    // MARK: - CRUD

    /// Validates and stores a new webhook. Throws `WebhookError.invalidURL`
    /// for malformed URLs.
    func add(name: String, urlString: String) throws {
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard DiscordWebhookClient.isValidWebhookURL(trimmedURL) else {
            throw WebhookError.invalidURL
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = WebhookConfig(name: trimmedName.isEmpty ? "Discord Webhook" : trimmedName)
        try secrets.setSecret(trimmedURL, for: config.keychainKey)
        webhooks.append(config)
        scheduleSave()
        logs.log(.info, .webhook, "Webhook “\(config.name)” added")
    }

    func rename(id: UUID, to newName: String) {
        guard let index = webhooks.firstIndex(where: { $0.id == id }) else { return }
        webhooks[index].name = newName
        scheduleSave()
    }

    /// Replaces the stored URL for an existing webhook.
    func updateURL(id: UUID, urlString: String) throws {
        guard let index = webhooks.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard DiscordWebhookClient.isValidWebhookURL(trimmed) else {
            throw WebhookError.invalidURL
        }
        try secrets.setSecret(trimmed, for: webhooks[index].keychainKey)
        webhooks[index].lastDeliveryState = .never
        webhooks[index].lastDeliveryDetail = nil
        scheduleSave()
    }

    func setEnabled(_ enabled: Bool, id: UUID) {
        guard let index = webhooks.firstIndex(where: { $0.id == id }) else { return }
        webhooks[index].isEnabled = enabled
        scheduleSave()
    }

    func delete(id: UUID) {
        guard let index = webhooks.firstIndex(where: { $0.id == id }) else { return }
        let config = webhooks[index]
        try? secrets.deleteSecret(for: config.keychainKey)
        webhooks.remove(at: index)
        scheduleSave()
        logs.log(.info, .webhook, "Webhook “\(config.name)” deleted")
    }

    /// URL for display/editing. Never logged.
    func url(for id: UUID) -> String? {
        guard let config = webhooks.first(where: { $0.id == id }) else { return nil }
        return try? secrets.secret(for: config.keychainKey)
    }

    // MARK: - Delivery

    /// Validates connectivity by fetching webhook metadata, then sends a test message.
    func test(id: UUID) async -> Result<String, Error> {
        guard let config = webhooks.first(where: { $0.id == id }),
              let urlString = url(for: id) else {
            return .failure(WebhookError.invalidURL)
        }
        do {
            let info = try await client.fetchInfo(urlString: urlString)
            try await client.send(
                content: "✅ **Biome Alert Pro** test — webhook “\(config.name)” is connected.",
                urlString: urlString
            )
            markDelivery(id: id, state: .ok, detail: "Test message delivered")
            logs.log(.info, .webhook, "Webhook “\(config.name)” test succeeded")
            return .success("Connected to “\(info.name ?? "webhook")” — test message sent.")
        } catch {
            markDelivery(id: id, state: .failed, detail: error.localizedDescription)
            logs.log(.error, .webhook, "Webhook “\(config.name)” test failed: \(error.localizedDescription)")
            return .failure(error)
        }
    }

    /// Broadcasts an alert summary to every enabled webhook.
    func broadcast(message: String) async {
        for config in webhooks where config.isEnabled {
            guard let urlString = url(for: config.id) else { continue }
            markDelivery(id: config.id, state: .retrying, detail: "Sending…")
            do {
                try await client.send(content: message, urlString: urlString)
                markDelivery(id: config.id, state: .ok, detail: "Alert forwarded")
            } catch {
                markDelivery(id: config.id, state: .failed, detail: error.localizedDescription)
                logs.log(.warning, .webhook, "Delivery to “\(config.name)” failed: \(error.localizedDescription)")
            }
        }
    }

    private func markDelivery(id: UUID, state: WebhookDeliveryState, detail: String?) {
        guard let index = webhooks.firstIndex(where: { $0.id == id }) else { return }
        webhooks[index].lastDeliveryState = state
        webhooks[index].lastDeliveryDate = Date()
        webhooks[index].lastDeliveryDetail = detail
        scheduleSave()
    }

    // MARK: - Persistence (metadata only — URLs stay in the Keychain)

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let stored = try? decoder.decode([WebhookConfig].self, from: data) {
            webhooks = stored
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.persist()
        }
    }

    private func persist() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(webhooks)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logs.log(.error, .webhook, "Failed to save webhooks: \(error.localizedDescription)")
        }
    }
}
