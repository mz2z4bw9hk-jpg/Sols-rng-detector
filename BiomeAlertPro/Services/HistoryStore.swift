import Foundation

/// Persisted alert history with search, export, and pruning.
@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var records: [AlertRecord] = []

    /// Maximum records retained (oldest pruned first).
    var limit: Int = 5_000

    private let fileURL: URL
    private let logs: LogStore
    private var saveTask: Task<Void, Never>?

    init(logs: LogStore, fileURL: URL = StorageLocations.historyFile) {
        self.logs = logs
        self.fileURL = fileURL
        load()
    }

    // MARK: - Mutation

    func add(_ record: AlertRecord) {
        records.insert(record, at: 0)
        if records.count > limit {
            records.removeLast(records.count - limit)
        }
        scheduleSave()
    }

    func updateLaunchStatus(id: UUID, status: LaunchStatus) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].launchStatus = status
        scheduleSave()
    }

    func delete(ids: Set<UUID>) {
        records.removeAll { ids.contains($0.id) }
        scheduleSave()
    }

    func clearAll() {
        records.removeAll()
        scheduleSave()
        logs.log(.info, .detection, "Alert history cleared")
    }

    // MARK: - Export

    func exportJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(records)
    }

    func exportCSV() -> String {
        let formatter = ISO8601DateFormatter()
        var lines = ["timestamp,source,sender,biome,rare,confidence,keywords,roblox_link,link_kind,latency_ms,launch_status,content"]
        for record in records {
            let fields: [String] = [
                formatter.string(from: record.date),
                record.source,
                record.sender ?? "",
                record.biome ?? "",
                record.isRareBiome ? "yes" : "no",
                String(format: "%.2f", record.confidence),
                record.matchedKeywords.joined(separator: "; "),
                record.robloxLink ?? "",
                record.linkKind ?? "",
                String(format: "%.1f", record.latencyMs),
                record.launchStatus.rawValue,
                record.content
            ]
            lines.append(fields.map(Self.escapeCSV).joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    static func escapeCSV(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let stored = try? decoder.decode([AlertRecord].self, from: data) {
            records = stored
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.persist()
        }
    }

    private func persist() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(records)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logs.log(.error, .detection, "Failed to save history: \(error.localizedDescription)")
        }
    }
}
