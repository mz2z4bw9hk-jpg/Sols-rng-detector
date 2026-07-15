import Foundation

/// Owns the user-editable keyword database and persists it to disk.
@MainActor
final class KeywordStore: ObservableObject {
    @Published private(set) var keywords: [Keyword] = []

    private let fileURL: URL
    private let logs: LogStore
    private var saveTask: Task<Void, Never>?

    init(logs: LogStore, fileURL: URL = StorageLocations.keywordsFile) {
        self.logs = logs
        self.fileURL = fileURL
        load()
    }

    var enabledKeywords: [Keyword] {
        keywords.filter(\.isEnabled)
    }

    func keywords(in category: KeywordCategory) -> [Keyword] {
        keywords.filter { $0.category == category }
    }

    // MARK: - Editing

    func add(_ keyword: Keyword) {
        let trimmed = keyword.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var copy = keyword
        copy.text = trimmed
        keywords.append(copy)
        scheduleSave()
        logs.log(.info, .detection, "Keyword added: “\(trimmed)” (\(keyword.category.displayName))")
    }

    func update(_ keyword: Keyword) {
        guard let index = keywords.firstIndex(where: { $0.id == keyword.id }) else { return }
        keywords[index] = keyword
        scheduleSave()
    }

    func delete(ids: Set<UUID>) {
        keywords.removeAll { ids.contains($0.id) }
        scheduleSave()
        logs.log(.info, .detection, "Deleted \(ids.count) keyword(s)")
    }

    func setEnabled(_ enabled: Bool, id: UUID) {
        guard let index = keywords.firstIndex(where: { $0.id == id }) else { return }
        keywords[index].isEnabled = enabled
        scheduleSave()
    }

    func restoreDefaults() {
        keywords = DefaultKeywords.all()
        scheduleSave()
        logs.log(.info, .detection, "Keyword database restored to defaults (\(keywords.count) keywords)")
    }

    // MARK: - Import / export

    func exportData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(keywords)
    }

    /// Imports a keyword database, merging by keyword text (case-insensitive)
    /// so re-imports don't create duplicates.
    func importData(_ data: Data) throws -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let imported = try decoder.decode([Keyword].self, from: data)
        var existing = Set(keywords.map { $0.text.lowercased() + "|" + $0.category.rawValue })
        var added = 0
        for var keyword in imported {
            keyword.id = UUID()
            let key = keyword.text.lowercased() + "|" + keyword.category.rawValue
            if existing.insert(key).inserted {
                keywords.append(keyword)
                added += 1
            }
        }
        scheduleSave()
        logs.log(.info, .detection, "Imported \(added) keyword(s)")
        return added
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            keywords = DefaultKeywords.all()
            scheduleSave()
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let stored = try? decoder.decode([Keyword].self, from: data), !stored.isEmpty {
            keywords = stored
        } else {
            keywords = DefaultKeywords.all()
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
            let data = try exportData()
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logs.log(.error, .detection, "Failed to save keywords: \(error.localizedDescription)")
        }
    }
}
