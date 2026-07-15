import Foundation

/// Rolling dashboard statistics, persisted across launches.
@MainActor
final class StatsStore: ObservableObject {
    @Published private(set) var alertsToday: Int = 0
    @Published private(set) var rareBiomesDetected: Int = 0
    @Published private(set) var robloxLaunchCount: Int = 0
    @Published private(set) var lastDetection: Date?
    @Published private(set) var lastDetectionLatencyMs: Double?
    @Published private(set) var averageLatencyMs: Double?

    private let defaults: UserDefaults
    private var latencySampleCount: Int = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        alertsToday = defaults.integer(forKey: "stats.alertsToday")
        rareBiomesDetected = defaults.integer(forKey: "stats.rareBiomes")
        robloxLaunchCount = defaults.integer(forKey: "stats.launchCount")
        latencySampleCount = defaults.integer(forKey: "stats.latencyCount")
        if defaults.object(forKey: "stats.lastDetection") != nil {
            lastDetection = Date(timeIntervalSince1970: defaults.double(forKey: "stats.lastDetection"))
        }
        if defaults.object(forKey: "stats.avgLatency") != nil {
            averageLatencyMs = defaults.double(forKey: "stats.avgLatency")
        }
        rollOverDayIfNeeded()
    }

    func recordAlert(record: AlertRecord) {
        rollOverDayIfNeeded()
        alertsToday += 1
        if record.isRareBiome {
            rareBiomesDetected += 1
        }
        lastDetection = record.date
        lastDetectionLatencyMs = record.latencyMs

        let previousTotal = (averageLatencyMs ?? 0) * Double(latencySampleCount)
        latencySampleCount += 1
        averageLatencyMs = (previousTotal + record.latencyMs) / Double(latencySampleCount)

        persist()
    }

    func recordLaunch() {
        robloxLaunchCount += 1
        persist()
    }

    func resetCounters() {
        alertsToday = 0
        rareBiomesDetected = 0
        robloxLaunchCount = 0
        lastDetection = nil
        lastDetectionLatencyMs = nil
        averageLatencyMs = nil
        latencySampleCount = 0
        persist()
    }

    // MARK: - Private

    private func rollOverDayIfNeeded() {
        let today = Self.dayKey(for: Date())
        let stored = defaults.string(forKey: "stats.dayKey")
        if stored != today {
            defaults.set(today, forKey: "stats.dayKey")
            alertsToday = 0
            persist()
        }
    }

    private static func dayKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

    private func persist() {
        defaults.set(alertsToday, forKey: "stats.alertsToday")
        defaults.set(rareBiomesDetected, forKey: "stats.rareBiomes")
        defaults.set(robloxLaunchCount, forKey: "stats.launchCount")
        defaults.set(latencySampleCount, forKey: "stats.latencyCount")
        if let lastDetection {
            defaults.set(lastDetection.timeIntervalSince1970, forKey: "stats.lastDetection")
        }
        if let averageLatencyMs {
            defaults.set(averageLatencyMs, forKey: "stats.avgLatency")
        }
    }
}
