import Foundation
import simd

/// Post-capture analysis service that computes synchronization quality metrics.
/// All computations happen AFTER recording stops, using the collected timestamps.
///
/// This service does NOT run during capture — it only processes stored data.
final class SyncAnalysisService {
    
    // MARK: - Video ↔ Head Pose Sync (item 1)
    
    struct VideoHeadPoseSyncResult {
        let avgDeltaMs: Double
        let maxDeltaMs: Double
        let p95DeltaMs: Double
        let deltas: [Double] // per-frame deltas for the mapping file
    }
    
    /// Compute sync metrics between video and head pose using monotonic timestamps.
    /// Since both come from the same ARFrame in ARKit mode, deltas should be <1ms.
    static func computeVideoHeadPoseSync(
        videoTimestamps: [VideoTimestamp],
        headPoseSamples: [HeadPoseService.TimingSample]
    ) -> VideoHeadPoseSyncResult {
        guard !videoTimestamps.isEmpty, !headPoseSamples.isEmpty else {
            return VideoHeadPoseSyncResult(avgDeltaMs: 0, maxDeltaMs: 0, p95DeltaMs: 0, deltas: [])
        }
        
        var deltas: [Double] = []
        
        for vts in videoTimestamps {
            let nearest = findNearest(targetNs: vts.timestampNs, in: headPoseSamples)
            let deltaNs = abs(Int64(vts.timestampNs) - Int64(nearest.timestampNs))
            let deltaMs = Double(deltaNs) / 1_000_000.0
            deltas.append(deltaMs)
        }
        
        let sorted = deltas.sorted()
        let avg = sorted.reduce(0, +) / Double(max(sorted.count, 1))
        let maxD = sorted.last ?? 0
        let p95Idx = Int(Double(sorted.count) * 0.95)
        let p95 = p95Idx < sorted.count ? sorted[p95Idx] : maxD
        
        return VideoHeadPoseSyncResult(avgDeltaMs: avg, maxDeltaMs: maxD, p95DeltaMs: p95, deltas: deltas)
    }
    
    // MARK: - IMU ↔ Video Sync (item 2)
    
    struct IMUVideoSyncResult {
        let estimatedOffsetMs: Double?
        let method: String    // "nearest_timestamps" or "motion_peak_alignment"
        let confidence: String // "high", "medium", "low"
    }
    
    /// Estimate the timing offset between IMU and video streams.
    /// Uses nearest-timestamp alignment on monotonic clock.
    /// Both IMU and video use mach_absolute_time, so the offset should be ~0.
    static func computeIMUVideoSync(
        videoTimestamps: [VideoTimestamp],
        imuTimestampsNs: [UInt64]
    ) -> IMUVideoSyncResult {
        guard videoTimestamps.count > 10, imuTimestampsNs.count > 10 else {
            return IMUVideoSyncResult(estimatedOffsetMs: nil, method: "not_computed", confidence: "low")
        }
        
        // For each video frame, find the nearest IMU sample and compute the offset
        var offsets: [Double] = []
        
        // Sample uniformly (every 10th video frame to keep computation fast)
        let stride = max(1, videoTimestamps.count / 50)
        for i in Swift.stride(from: 0, to: videoTimestamps.count, by: stride) {
            let videoNs = videoTimestamps[i].timestampNs
            let nearestIMU = findNearestScalar(targetNs: videoNs, in: imuTimestampsNs)
            let offsetNs = Int64(videoNs) - Int64(nearestIMU)
            offsets.append(Double(offsetNs) / 1_000_000.0)
        }
        
        guard !offsets.isEmpty else {
            return IMUVideoSyncResult(estimatedOffsetMs: nil, method: "not_computed", confidence: "low")
        }
        
        let avgOffset = offsets.reduce(0, +) / Double(offsets.count)
        let stdDev = sqrt(offsets.map { ($0 - avgOffset) * ($0 - avgOffset) }.reduce(0, +) / Double(offsets.count))
        
        // Confidence based on consistency of offset measurements
        let confidence: String
        if stdDev < 2.0 {
            confidence = "high"
        } else if stdDev < 10.0 {
            confidence = "medium"
        } else {
            confidence = "low"
        }
        
        return IMUVideoSyncResult(
            estimatedOffsetMs: avgOffset,
            method: "nearest_timestamps",
            confidence: confidence
        )
    }
    
    // MARK: - IMU ↔ Head Pose Consistency (item 3)
    
    struct IMUPoseConsistencyResult {
        let angularErrorMeanDeg: Double?
        let angularErrorMaxDeg: Double?
        let sampleCount: Int
        let method: String
    }
    
    /// Validate that gyroscope readings are consistent with head pose rotation.
    ///
    /// Method: For consecutive head pose samples, compute angular velocity from
    /// the quaternion delta. Find the nearest IMU gyro sample. Compare magnitudes.
    ///
    /// NOTE: ARKit head pose is Kalman-filtered (visual-inertial fusion) while
    /// gyro is raw. Some discrepancy is expected and does NOT indicate a sync problem.
    /// The error metric reflects both sync quality and filter smoothing.
    static func computeIMUPoseConsistency(
        headPoseSamples: [(timestampNs: UInt64, qx: Double, qy: Double, qz: Double, qw: Double)],
        imuSamples: [(timestampNs: UInt64, gx: Double, gy: Double, gz: Double)]
    ) -> IMUPoseConsistencyResult {
        guard headPoseSamples.count > 10, imuSamples.count > 10 else {
            return IMUPoseConsistencyResult(
                angularErrorMeanDeg: nil, angularErrorMaxDeg: nil,
                sampleCount: 0, method: "gyro_vs_quaternion_delta"
            )
        }
        
        var errors: [Double] = []
        
        // Sample every 3rd head pose pair for performance
        let step = 3
        for i in Swift.stride(from: step, to: headPoseSamples.count, by: step) {
            let prev = headPoseSamples[i - step]
            let curr = headPoseSamples[i]
            
            // Time delta
            let dtNs = Int64(curr.timestampNs) - Int64(prev.timestampNs)
            guard dtNs > 0 else { continue }
            let dtSec = Double(dtNs) / 1_000_000_000.0
            guard dtSec > 0.001 && dtSec < 1.0 else { continue } // skip gaps
            
            // Angular velocity from quaternion delta
            let q1 = simd_quatd(ix: prev.qx, iy: prev.qy, iz: prev.qz, r: prev.qw)
            let q2 = simd_quatd(ix: curr.qx, iy: curr.qy, iz: curr.qz, r: curr.qw)
            let deltaQ = q2 * q1.inverse
            
            // Axis-angle: angle = 2*acos(|w|), angular speed = angle/dt
            let angle = 2.0 * acos(min(abs(deltaQ.real), 1.0))
            let poseAngularSpeed = angle / dtSec // rad/s
            
            // Find nearest IMU gyro sample
            let midNs = UInt64((Int64(prev.timestampNs) + Int64(curr.timestampNs)) / 2)
            let nearestIMU = findNearestIMU(targetNs: midNs, in: imuSamples)
            
            // Gyro magnitude
            let gyroMag = sqrt(nearestIMU.gx * nearestIMU.gx + nearestIMU.gy * nearestIMU.gy + nearestIMU.gz * nearestIMU.gz)
            
            // Error: difference in angular speed (rad/s) → convert to degrees
            let errorRad = abs(poseAngularSpeed - gyroMag)
            let errorDeg = errorRad * 180.0 / .pi
            
            errors.append(errorDeg)
        }
        
        guard !errors.isEmpty else {
            return IMUPoseConsistencyResult(
                angularErrorMeanDeg: nil, angularErrorMaxDeg: nil,
                sampleCount: 0, method: "gyro_vs_quaternion_delta"
            )
        }
        
        let mean = errors.reduce(0, +) / Double(errors.count)
        let maxErr = errors.max() ?? 0
        
        return IMUPoseConsistencyResult(
            angularErrorMeanDeg: mean,
            angularErrorMaxDeg: maxErr,
            sampleCount: errors.count,
            method: "gyro_vs_quaternion_delta"
        )
    }
    
    // MARK: - Nearest Neighbor Search
    
    private static func findNearest(targetNs: UInt64, in samples: [HeadPoseService.TimingSample]) -> HeadPoseService.TimingSample {
        var lo = 0, hi = samples.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if samples[mid].timestampNs < targetNs { lo = mid + 1 } else { hi = mid }
        }
        if lo == 0 { return samples[0] }
        let a = samples[lo - 1], b = samples[lo]
        let da = targetNs > a.timestampNs ? targetNs - a.timestampNs : a.timestampNs - targetNs
        let db = targetNs > b.timestampNs ? targetNs - b.timestampNs : b.timestampNs - targetNs
        return da <= db ? a : b
    }
    
    private static func findNearestScalar(targetNs: UInt64, in timestamps: [UInt64]) -> UInt64 {
        var lo = 0, hi = timestamps.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if timestamps[mid] < targetNs { lo = mid + 1 } else { hi = mid }
        }
        if lo == 0 { return timestamps[0] }
        let a = timestamps[lo - 1], b = timestamps[lo]
        return (targetNs - a) <= (b - targetNs) ? a : b
    }
    
    private static func findNearestIMU(
        targetNs: UInt64,
        in samples: [(timestampNs: UInt64, gx: Double, gy: Double, gz: Double)]
    ) -> (timestampNs: UInt64, gx: Double, gy: Double, gz: Double) {
        var lo = 0, hi = samples.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if samples[mid].timestampNs < targetNs { lo = mid + 1 } else { hi = mid }
        }
        if lo == 0 { return samples[0] }
        let a = samples[lo - 1], b = samples[lo]
        return (targetNs - a.timestampNs) <= (b.timestampNs - targetNs) ? a : b
    }
}
