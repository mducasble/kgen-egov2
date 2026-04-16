import Foundation

/// Post-capture sync validation for IMU-only mode.
///
/// Both video (AVCapture presentation timestamp) and IMU (CoreMotion timestamp)
/// use mach_absolute_time as their clock source. Timestamps are converted to
/// nanoseconds via the same MonotonicClock, so the offset is 0 by construction.
///
/// This service validates that claim by measuring the observed jitter between
/// nearest IMU/video timestamp pairs.
final class SyncAnalysisService {

    struct IMUVideoSyncResult {
        let estimatedOffsetMs: Double
        let method: String
        let confidence: String
        let observedJitterStdDevMs: Double
        let observedMaxDeltaMs: Double
        let samplePairsUsed: Int
    }

    /// Validate IMU↔video sync using shared-clock deterministic alignment.
    ///
    /// Since both streams derive timestamps from the same hardware clock, the
    /// true offset is 0. We compute nearest-neighbor deltas purely as a health
    /// check: jitter should be bounded by the IMU sampling interval (~10 ms).
    static func computeIMUVideoSync(
        videoTimestamps: [VideoTimestamp],
        imuTimestampsNs: [UInt64]
    ) -> IMUVideoSyncResult {
        guard videoTimestamps.count > 10, imuTimestampsNs.count > 10 else {
            return IMUVideoSyncResult(
                estimatedOffsetMs: 0.0,
                method: "shared_clock",
                confidence: "deterministic",
                observedJitterStdDevMs: 0,
                observedMaxDeltaMs: 0,
                samplePairsUsed: 0
            )
        }

        let sortedIMU = imuTimestampsNs.sorted()
        var deltas: [Double] = []

        let stride = max(1, videoTimestamps.count / 100)
        for i in Swift.stride(from: 0, to: videoTimestamps.count, by: stride) {
            let videoNs = videoTimestamps[i].timestampNs
            let nearestIMU = findNearest(targetNs: videoNs, in: sortedIMU)
            let deltaNs = abs(Int64(videoNs) - Int64(nearestIMU))
            deltas.append(Double(deltaNs) / 1_000_000.0)
        }

        guard !deltas.isEmpty else {
            return IMUVideoSyncResult(
                estimatedOffsetMs: 0.0,
                method: "shared_clock",
                confidence: "deterministic",
                observedJitterStdDevMs: 0,
                observedMaxDeltaMs: 0,
                samplePairsUsed: 0
            )
        }

        let mean = deltas.reduce(0, +) / Double(deltas.count)
        let variance = deltas.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(deltas.count)
        let stdDev = variance > 0 ? sqrt(variance) : 0
        let maxDelta = deltas.max() ?? 0

        return IMUVideoSyncResult(
            estimatedOffsetMs: 0.0,
            method: "shared_clock",
            confidence: "deterministic",
            observedJitterStdDevMs: stdDev,
            observedMaxDeltaMs: maxDelta,
            samplePairsUsed: deltas.count
        )
    }

    // MARK: - Binary Search

    private static func findNearest(targetNs: UInt64, in sorted: [UInt64]) -> UInt64 {
        var lo = 0, hi = sorted.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if sorted[mid] < targetNs { lo = mid + 1 } else { hi = mid }
        }
        if lo == 0 { return sorted[0] }
        let a = sorted[lo - 1], b = sorted[lo]
        return (targetNs - a) <= (b - targetNs) ? a : b
    }
}
