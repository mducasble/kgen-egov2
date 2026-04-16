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
        let angularErrorMedianDeg: Double?
        let angularErrorP95Deg: Double?
        let angularErrorMaxDeg: Double?
        let angularErrorMeanRadPerSec: Double?
        let sampleCount: Int
        let outlierCount: Int
        let skippedTrackingLossSamples: Int
        let method: String
        let confidence: String
        let debugRows: [IMUPoseDebugRow]
    }

    struct IMUPoseDebugRow: Codable {
        let timestampNs: UInt64
        let gyroMagnitudeRadPerSec: Double
        let poseAngularSpeedRadPerSec: Double
        let errorDeg: Double
        let trackingState: String
        let used: Bool
        let skipReason: String?
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
        headPoseSamples: [HeadPoseSample],
        imuSamples: [(timestampNs: UInt64, gx: Double, gy: Double, gz: Double)]
    ) -> IMUPoseConsistencyResult {
        guard headPoseSamples.count > 10, imuSamples.count > 10 else {
            return IMUPoseConsistencyResult(
                angularErrorMeanDeg: nil,
                angularErrorMedianDeg: nil,
                angularErrorP95Deg: nil,
                angularErrorMaxDeg: nil,
                angularErrorMeanRadPerSec: nil,
                sampleCount: 0,
                outlierCount: 0,
                skippedTrackingLossSamples: 0,
                method: "gyro_vs_interpolated_quaternion_delta",
                confidence: "low",
                debugRows: []
            )
        }

        guard let prepared = prepareHeadPoseSamples(headPoseSamples) else {
            return IMUPoseConsistencyResult(
                angularErrorMeanDeg: nil,
                angularErrorMedianDeg: nil,
                angularErrorP95Deg: nil,
                angularErrorMaxDeg: nil,
                angularErrorMeanRadPerSec: nil,
                sampleCount: 0,
                outlierCount: 0,
                skippedTrackingLossSamples: 0,
                method: "gyro_vs_interpolated_quaternion_delta",
                confidence: "low",
                debugRows: []
            )
        }

        let imuSorted = imuSamples.sorted { $0.timestampNs < $1.timestampNs }
        var errorDegValues: [Double] = []
        var errorRadValues: [Double] = []
        var debugRows: [IMUPoseDebugRow] = []
        var skippedTrackingLoss = 0

        for i in 1..<(imuSorted.count - 1) {
            let imu = imuSorted[i]
            let prevNs = imuSorted[i - 1].timestampNs
            let nextNs = imuSorted[i + 1].timestampNs
            let dtNs = min(imu.timestampNs - prevNs, nextNs - imu.timestampNs)
            let halfWindowNs = max(UInt64(5_000_000), min(dtNs / 2, UInt64(25_000_000)))
            let t0 = imu.timestampNs > halfWindowNs ? imu.timestampNs - halfWindowNs : 0
            let t1 = imu.timestampNs + halfWindowNs
            let deltaSec = Double(t1 - t0) / 1_000_000_000.0

            guard deltaSec > 0.0005, deltaSec < 0.25 else {
                debugRows.append(IMUPoseDebugRow(
                    timestampNs: imu.timestampNs,
                    gyroMagnitudeRadPerSec: 0,
                    poseAngularSpeedRadPerSec: 0,
                    errorDeg: 0,
                    trackingState: "unknown",
                    used: false,
                    skipReason: "invalid_delta_time"
                ))
                continue
            }

            guard let p0 = interpolatePose(at: t0, in: prepared),
                  let p1 = interpolatePose(at: t1, in: prepared) else {
                debugRows.append(IMUPoseDebugRow(
                    timestampNs: imu.timestampNs,
                    gyroMagnitudeRadPerSec: 0,
                    poseAngularSpeedRadPerSec: 0,
                    errorDeg: 0,
                    trackingState: "unknown",
                    used: false,
                    skipReason: "outside_pose_range"
                ))
                continue
            }

            let trackingState = mergedTrackingState(lhs: p0.trackingState, rhs: p1.trackingState)
            guard trackingState == "normal" else {
                skippedTrackingLoss += 1
                debugRows.append(IMUPoseDebugRow(
                    timestampNs: imu.timestampNs,
                    gyroMagnitudeRadPerSec: 0,
                    poseAngularSpeedRadPerSec: 0,
                    errorDeg: 0,
                    trackingState: trackingState,
                    used: false,
                    skipReason: "tracking_not_normal"
                ))
                continue
            }

            let deltaQ = simd_normalize(p1.quaternion * p0.quaternion.inverse)
            let angleRad = 2.0 * acos(max(-1.0, min(1.0, deltaQ.real)))
            let poseAngularSpeed = angleRad / deltaSec

            let gyroMapped = mapGyroToARKitFrame(gx: imu.gx, gy: imu.gy, gz: imu.gz)
            let gyroMagnitude = simd_length(gyroMapped)

            let errorRad = abs(poseAngularSpeed - gyroMagnitude)
            let errorDeg = errorRad * 180.0 / .pi

            errorRadValues.append(errorRad)
            errorDegValues.append(errorDeg)
            debugRows.append(IMUPoseDebugRow(
                timestampNs: imu.timestampNs,
                gyroMagnitudeRadPerSec: gyroMagnitude,
                poseAngularSpeedRadPerSec: poseAngularSpeed,
                errorDeg: errorDeg,
                trackingState: trackingState,
                used: true,
                skipReason: nil
            ))
        }

        guard !errorDegValues.isEmpty else {
            return IMUPoseConsistencyResult(
                angularErrorMeanDeg: nil,
                angularErrorMedianDeg: nil,
                angularErrorP95Deg: nil,
                angularErrorMaxDeg: nil,
                angularErrorMeanRadPerSec: nil,
                sampleCount: 0,
                outlierCount: 0,
                skippedTrackingLossSamples: skippedTrackingLoss,
                method: "gyro_vs_interpolated_quaternion_delta",
                confidence: "low",
                debugRows: debugRows
            )
        }

        let sortedDeg = errorDegValues.sorted()
        let meanDeg = sortedDeg.reduce(0, +) / Double(sortedDeg.count)
        let medianDeg = percentile(sortedDeg, p: 0.5)
        let p95Deg = percentile(sortedDeg, p: 0.95)
        let maxDeg = sortedDeg.last ?? 0
        let meanRad = errorRadValues.reduce(0, +) / Double(errorRadValues.count)
        let outlierCount = errorDegValues.filter { $0 > 90.0 }.count
        let confidence = consistencyConfidence(sampleCount: errorDegValues.count, p95Deg: p95Deg, outlierRatio: Double(outlierCount) / Double(errorDegValues.count))

        return IMUPoseConsistencyResult(
            angularErrorMeanDeg: meanDeg,
            angularErrorMedianDeg: medianDeg,
            angularErrorP95Deg: p95Deg,
            angularErrorMaxDeg: maxDeg,
            angularErrorMeanRadPerSec: meanRad,
            sampleCount: errorDegValues.count,
            outlierCount: outlierCount,
            skippedTrackingLossSamples: skippedTrackingLoss,
            method: "gyro_vs_interpolated_quaternion_delta",
            confidence: confidence,
            debugRows: debugRows
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

    private struct PreparedPose {
        let timestampNs: UInt64
        let quaternion: simd_quatd
        let trackingState: String
    }

    private static func prepareHeadPoseSamples(_ samples: [HeadPoseSample]) -> [PreparedPose]? {
        let sorted = samples.sorted { $0.timestampNs < $1.timestampNs }
        var prepared: [PreparedPose] = []
        var previous: simd_quatd?
        var previousTs: UInt64?

        for sample in sorted {
            let qRaw = sample.rotationQuaternion
            guard qRaw.x.isFinite, qRaw.y.isFinite, qRaw.z.isFinite, qRaw.w.isFinite else { continue }
            guard sample.timestampNs > 0 else { continue }
            if let prevTs = previousTs, sample.timestampNs <= prevTs { continue }

            var q = simd_quatd(ix: qRaw.x, iy: qRaw.y, iz: qRaw.z, r: qRaw.w)
            let len = simd_length(q.vector)
            guard len.isFinite, len > 1e-12 else { continue }
            q = simd_normalize(q)

            if let prev = previous, simd_dot(prev.vector, q.vector) < 0 {
                q = simd_quatd(vector: -q.vector)
            }

            prepared.append(PreparedPose(timestampNs: sample.timestampNs, quaternion: q, trackingState: sample.trackingState))
            previous = q
            previousTs = sample.timestampNs
        }

        return prepared.count >= 2 ? prepared : nil
    }

    private static func interpolatePose(at timestampNs: UInt64, in samples: [PreparedPose]) -> PreparedPose? {
        guard !samples.isEmpty else { return nil }
        guard timestampNs >= samples.first!.timestampNs, timestampNs <= samples.last!.timestampNs else { return nil }

        var lo = 0
        var hi = samples.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let t = samples[mid].timestampNs
            if t == timestampNs { return samples[mid] }
            if t < timestampNs {
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }

        let rightIndex = min(max(lo, 1), samples.count - 1)
        let leftIndex = rightIndex - 1
        let a = samples[leftIndex]
        let b = samples[rightIndex]
        let dt = b.timestampNs - a.timestampNs
        guard dt > 0 else { return nil }
        let alpha = Double(timestampNs - a.timestampNs) / Double(dt)
        let qInterp = slerp(a.quaternion, b.quaternion, alpha: alpha)
        let state = mergedTrackingState(lhs: a.trackingState, rhs: b.trackingState)
        return PreparedPose(timestampNs: timestampNs, quaternion: qInterp, trackingState: state)
    }

    private static func slerp(_ q0: simd_quatd, _ q1In: simd_quatd, alpha: Double) -> simd_quatd {
        var q1 = simd_normalize(q1In)
        let q0n = simd_normalize(q0)
        var dot = simd_dot(q0n.vector, q1.vector)

        if dot < 0 {
            q1 = simd_quatd(vector: -q1.vector)
            dot = -dot
        }

        if dot > 0.9995 {
            let nlerp = simd_normalize(simd_double4(
                q0n.vector.x + (q1.vector.x - q0n.vector.x) * alpha,
                q0n.vector.y + (q1.vector.y - q0n.vector.y) * alpha,
                q0n.vector.z + (q1.vector.z - q0n.vector.z) * alpha,
                q0n.vector.w + (q1.vector.w - q0n.vector.w) * alpha
            ))
            return simd_quatd(vector: nlerp)
        }

        let theta0 = acos(max(-1.0, min(1.0, dot)))
        let theta = theta0 * alpha
        let sinTheta0 = sin(theta0)
        guard sinTheta0 != 0 else { return q0n }
        let s0 = cos(theta) - dot * sin(theta) / sinTheta0
        let s1 = sin(theta) / sinTheta0
        let v = simd_normalize(q0n.vector * s0 + q1.vector * s1)
        return simd_quatd(vector: v)
    }

    private static func mapGyroToARKitFrame(gx: Double, gy: Double, gz: Double) -> simd_double3 {
        // Explicit mapping layer:
        // CoreMotion gyro is device-frame rad/s on right-handed axes.
        // ARKit camera pose also uses right-handed convention.
        // For the current mounting/capture orientation, identity mapping is used.
        // Keep this utility explicit for future per-device axis remaps.
        simd_double3(gx, gy, gz)
    }

    private static func mergedTrackingState(lhs: String, rhs: String) -> String {
        (lhs == "normal" && rhs == "normal") ? "normal" : "limited"
    }

    private static func percentile(_ sorted: [Double], p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let clamped = min(max(p, 0), 1)
        let index = Int(Double(sorted.count - 1) * clamped)
        return sorted[index]
    }

    private static func consistencyConfidence(sampleCount: Int, p95Deg: Double, outlierRatio: Double) -> String {
        if sampleCount > 200 && p95Deg < 25 && outlierRatio < 0.05 { return "high" }
        if sampleCount > 80 && p95Deg < 60 && outlierRatio < 0.15 { return "medium" }
        return "low"
    }
}
