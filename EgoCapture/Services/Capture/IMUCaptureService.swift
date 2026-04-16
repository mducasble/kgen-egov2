import Foundation
import CoreMotion

/// Captures accelerometer + gyroscope data at ~100 Hz using CoreMotion.
/// Uses MonotonicClock for high-precision timestamps shared with all sensors.
/// Stores gyro timing data in memory for post-capture IMU↔head pose consistency analysis.
final class IMUCaptureService {
    
    private let motionManager = CMMotionManager()
    private let operationQueue = OperationQueue()
    private let clock = MonotonicClock.shared
    
    private var writer: JSONLWriter?
    private var startNs: UInt64 = 0
    private var sampleCount: Int = 0
    private var startupSamplesDiscarded: Int = 0
    private var previousSampleNs: UInt64?
    
    private let startupDiscardCount = 10
    private let targetInterval: TimeInterval = 0.01
    private let gapThresholdMs: Double = 50.0
    
    private var continuousDurationSec: Double = 0
    private var continuousIntervalCount: Int = 0
    private var intervalSquaredSumMs: Double = 0
    private var intervalSumMs: Double = 0
    private var maxGapMs: Double = 0
    private(set) var lagEventCount: Int = 0
    
    /// Stored gyro samples for post-capture IMU↔head pose consistency analysis.
    /// Each entry: (timestampNs, gyroX, gyroY, gyroZ) in rad/s.
    private(set) var gyroSamples: [(timestampNs: UInt64, gx: Double, gy: Double, gz: Double)] = []
    
    /// Stored monotonic timestamps for IMU↔video sync analysis.
    private(set) var allTimestampsNs: [UInt64] = []
    
    var totalSamples: Int { sampleCount }
    
    var actualSampleRateHz: Double {
        guard continuousIntervalCount > 0, continuousDurationSec > 0 else { return 0 }
        return Double(continuousIntervalCount) / continuousDurationSec
    }
    
    var sampleIntervalStdDevMs: Double {
        guard continuousIntervalCount > 1 else { return 0 }
        let n = Double(continuousIntervalCount)
        let mean = intervalSumMs / n
        let variance = (intervalSquaredSumMs / n) - (mean * mean)
        return variance > 0 ? sqrt(variance) : 0
    }
    
    var maxGapMsValue: Double { maxGapMs }
    var startupDiscarded: Int { startupSamplesDiscarded }
    
    func start(outputURL: URL, epochStartMs: Double) throws {
        guard motionManager.isDeviceMotionAvailable else { throw IMUError.motionNotAvailable }
        
        writer = try JSONLWriter(fileURL: outputURL)
        startNs = clock.nowNs()
        sampleCount = 0; startupSamplesDiscarded = 0; previousSampleNs = nil
        continuousDurationSec = 0; continuousIntervalCount = 0
        intervalSquaredSumMs = 0; intervalSumMs = 0; maxGapMs = 0; lagEventCount = 0
        gyroSamples = []; allTimestampsNs = []
        
        operationQueue.name = "com.egocapture.imu"
        operationQueue.maxConcurrentOperationCount = 1
        operationQueue.qualityOfService = .userInteractive
        
        motionManager.deviceMotionUpdateInterval = targetInterval
        motionManager.startDeviceMotionUpdates(to: operationQueue) { [weak self] motion, error in
            guard let self = self, let motion = motion else { return }
            self.handleMotionUpdate(motion)
        }
    }
    
    func stop() {
        motionManager.stopDeviceMotionUpdates()
        writer?.close()
    }
    
    private func handleMotionUpdate(_ motion: CMDeviceMotion) {
        let rawCount = sampleCount + startupSamplesDiscarded
        if rawCount < startupDiscardCount { startupSamplesDiscarded += 1; return }
        
        let sampleNs = clock.fromCoreMotionTimestamp(motion.timestamp)
        let relativeMs = clock.toRelativeMs(sampleNs, from: startNs)
        let epochMs = clock.toEpochMs(sampleNs)
        
        if let prevNs = previousSampleNs {
            let intervalMs = clock.toRelativeMs(sampleNs, from: prevNs)
            if intervalMs > 0 && intervalMs < gapThresholdMs {
                continuousDurationSec += intervalMs / 1000.0
                continuousIntervalCount += 1
                intervalSumMs += intervalMs; intervalSquaredSumMs += intervalMs * intervalMs
            }
            if intervalMs > maxGapMs { maxGapMs = intervalMs }
            if intervalMs > gapThresholdMs { lagEventCount += 1 }
        }
        previousSampleNs = sampleNs
        
        let sample = IMUSample(
            timestampEpochMs: epochMs, relativeMs: relativeMs,
            timestampNs: sampleNs, clock: "mach_absolute_time",
            accelerometer: IMUSample.XYZ(
                x: motion.userAcceleration.x + motion.gravity.x,
                y: motion.userAcceleration.y + motion.gravity.y,
                z: motion.userAcceleration.z + motion.gravity.z
            ),
            gyroscope: IMUSample.XYZ(
                x: motion.rotationRate.x,
                y: motion.rotationRate.y,
                z: motion.rotationRate.z
            )
        )
        
        writer?.append(sample)
        
        // Store for post-capture analysis (every 3rd sample to limit memory)
        if sampleCount % 3 == 0 {
            gyroSamples.append((sampleNs, motion.rotationRate.x, motion.rotationRate.y, motion.rotationRate.z))
        }
        allTimestampsNs.append(sampleNs)
        
        sampleCount += 1
    }
    
    enum IMUError: Error { case motionNotAvailable }
}
