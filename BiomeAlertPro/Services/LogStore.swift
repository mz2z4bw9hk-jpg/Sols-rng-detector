import Foundation
import os

/// Structured application log. Keeps a capped in-memory buffer for the UI and
/// mirrors entries to a JSON-lines file plus the unified system log.
@MainActor
final class LogStore: ObservableObject {
    @Published private(set) var entries: [LogEntry] = []

    /// Entries below this level are discarded.
    var minimumLevel: LogLevel = .info

    private let maxEntries = 2_000
    private let maxFileBytes: UInt64 = 5 * 1024 * 1024
    private let systemLogger = os.Logger(subsystem: "com.biomealert.BiomeAlertPro", category: "app")
    private let encoder: JSONEncoder

    init() {
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        rotateFileIfNeeded()
    }

    func log(_ level: LogLevel, _ category: LogCategory, _ message: String) {
        guard level >= minimumLevel else { return }
        let entry = LogEntry(level: level, category: category, message: message)
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        switch level {
        case .debug: systemLogger.debug("[\(category.rawValue)] \(message)")
        case .info: systemLogger.info("[\(category.rawValue)] \(message)")
        case .warning: systemLogger.warning("[\(category.rawValue)] \(message)")
        case .error: systemLogger.error("[\(category.rawValue)] \(message)")
        }
        appendToFile(entry)
    }

    func clear() {
        entries.removeAll()
    }

    /// Renders the in-memory buffer as human-readable text for export.
    func exportText() -> String {
        let formatter = ISO8601DateFormatter()
        return entries.map { entry in
            "\(formatter.string(from: entry.date)) [\(entry.level.rawValue.uppercased())] [\(entry.category.rawValue)] \(entry.message)"
        }.joined(separator: "\n")
    }

    // MARK: - File mirroring

    private func appendToFile(_ entry: LogEntry) {
        guard var data = try? encoder.encode(entry) else { return }
        data.append(0x0A) // newline
        let url = StorageLocations.logFile
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    private func rotateFileIfNeeded() {
        let url = StorageLocations.logFile
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? UInt64, size > maxFileBytes else { return }
        let archived = url.deletingPathExtension().appendingPathExtension("old.jsonl")
        try? FileManager.default.removeItem(at: archived)
        try? FileManager.default.moveItem(at: url, to: archived)
    }
}
