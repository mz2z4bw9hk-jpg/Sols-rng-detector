import Foundation
import Darwin

/// Samples this process's CPU and memory usage on a low-frequency timer so
/// the dashboard can show live resource figures without meaningfully adding
/// to them.
@MainActor
final class PerformanceMonitor: ObservableObject {
    @Published private(set) var cpuPercent: Double = 0
    @Published private(set) var memoryMB: Double = 0
    @Published private(set) var isOverCPULimit = false

    /// Soft CPU target from settings; exceeding it raises a warning flag and log.
    var cpuLimitPercent: Double = 2.0
    var onWarning: ((String) -> Void)?

    private var samplerTask: Task<Void, Never>?
    private var lastCPUTimeNs: UInt64 = 0
    private var lastWallTimeNs: UInt64 = 0

    func start(interval: Duration = .seconds(5)) {
        stop()
        lastCPUTimeNs = clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID)
        lastWallTimeNs = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)
        samplerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                self?.sample()
            }
        }
    }

    func stop() {
        samplerTask?.cancel()
        samplerTask = nil
    }

    private func sample() {
        // CPU: delta of process CPU time over delta of wall time.
        let cpuNow = clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID)
        let wallNow = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)
        if lastWallTimeNs > 0, wallNow > lastWallTimeNs {
            let cpuDelta = Double(cpuNow &- lastCPUTimeNs)
            let wallDelta = Double(wallNow &- lastWallTimeNs)
            cpuPercent = max(0, min(100, cpuDelta / wallDelta * 100))
        }
        lastCPUTimeNs = cpuNow
        lastWallTimeNs = wallNow

        // Memory: physical footprint via libproc rusage.
        let footprint = Self.physicalFootprintBytes()
        if footprint > 0 {
            memoryMB = Double(footprint) / 1_048_576
        }

        let over = cpuPercent > cpuLimitPercent
        if over && !isOverCPULimit {
            onWarning?(String(format: "CPU usage %.1f%% exceeded the %.1f%% target", cpuPercent, cpuLimitPercent))
        }
        isOverCPULimit = over
    }

    /// Current physical memory footprint of this process in bytes.
    private static func physicalFootprintBytes() -> UInt64 {
        var info = rusage_info_current()
        let result = withUnsafeMutablePointer(to: &info) { pointer -> Int32 in
            pointer.withMemoryRebound(to: (rusage_info_t?).self, capacity: 1) { rebound in
                // Flavor 4 == RUSAGE_INFO_V4 (the macro is not imported into Swift).
                proc_pid_rusage(getpid(), 4, rebound)
            }
        }
        guard result == 0 else { return 0 }
        return info.ri_phys_footprint
    }
}
