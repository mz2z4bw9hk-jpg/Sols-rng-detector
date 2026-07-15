import Foundation

/// Central definition of on-disk storage locations inside the sandbox
/// container's Application Support directory.
enum StorageLocations {
    static func appSupportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("BiomeAlertPro", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static var historyFile: URL { appSupportDirectory().appendingPathComponent("history.json") }
    static var keywordsFile: URL { appSupportDirectory().appendingPathComponent("keywords.json") }
    static var webhooksFile: URL { appSupportDirectory().appendingPathComponent("webhooks.json") }
    static var logFile: URL { appSupportDirectory().appendingPathComponent("biomealertpro.log.jsonl") }
}
