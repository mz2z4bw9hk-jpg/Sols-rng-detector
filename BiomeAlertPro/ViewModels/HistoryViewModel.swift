import Foundation
import UniformTypeIdentifiers

/// Search, filter, sort, and export state for the Alert History screen.
@MainActor
final class HistoryViewModel: ObservableObject {
    enum BiomeFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case rareOnly = "Rare Only"
        case withLink = "With Link"
        case launched = "Launched"

        var id: String { rawValue }
    }

    @Published var searchText = ""
    @Published var filter: BiomeFilter = .all
    @Published var selection = Set<UUID>()
    @Published var sortOrder = [KeyPathComparator(\AlertRecord.date, order: .reverse)]

    private let store: HistoryStore

    init(store: HistoryStore) {
        self.store = store
    }

    func filteredRecords() -> [AlertRecord] {
        var records = store.records

        switch filter {
        case .all:
            break
        case .rareOnly:
            records = records.filter(\.isRareBiome)
        case .withLink:
            records = records.filter { $0.robloxLink != nil }
        case .launched:
            records = records.filter { $0.launchStatus == .launched }
        }

        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            records = records.filter { record in
                record.content.lowercased().contains(query)
                    || (record.biome?.lowercased().contains(query) ?? false)
                    || (record.sender?.lowercased().contains(query) ?? false)
                    || record.source.lowercased().contains(query)
                    || record.matchedKeywords.contains { $0.lowercased().contains(query) }
            }
        }

        return records.sorted(using: sortOrder)
    }

    func deleteSelection() {
        guard !selection.isEmpty else { return }
        store.delete(ids: selection)
        selection.removeAll()
    }

    func clearAll() {
        store.clearAll()
        selection.removeAll()
    }

    func exportCSV() {
        let csv = store.exportCSV()
        _ = Panels.saveData(Data(csv.utf8), suggestedName: "BiomeAlertPro-History.csv", contentType: .commaSeparatedText)
    }

    func exportJSON() {
        do {
            let data = try store.exportJSON()
            _ = Panels.saveData(data, suggestedName: "BiomeAlertPro-History.json", contentType: .json)
        } catch {
            Panels.presentError("Export failed: \(error.localizedDescription)")
        }
    }
}
