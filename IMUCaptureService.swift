import Foundation
import CoreMotion

/// Captures accelerometer + gyroscope data at ~100 Hz using CoreMotion.
/// Discards initial samples to avoid startup noise.
final class IMUCaptureService {
    
    private let motionManager = CMMotionManager()
    private let operationQueue = OperationQueue()
    
    private var writer: JSONLWriter?
    private var recordingStartEpochMs: Double = 0
    private var sampleCount: Int = 0
    private var startupSamplesDiscarded: Int = 0
    private var firstSampleTime: TimeInterval?
    private var lastSampleTime: TimeInterval?
    private var previousSampleTime: TimeInterval?
    
    private let startupDiscardCount = 10
    private let targetInterval: TimeInterval = 0.01
    private let gapThresholdMs: Double = 50.0
    
    private var continuousDurationSec: Double = 0
    private var continuousIntervalCount: Int = 0
    
    var totalSamples: Int { sampleCount }
    
    var actualSampleRateHz: Double {
        guard continuousIntervalCount > 0, continuousDurationSec > 0 else { return 0 }
        return Double(continuousIntervalCount) / continuousDurationSec
    }
    
    var startupDiscarded: Int { startupSamplesDiscarded }
    
    func start(outputURL: URL, epochStartMs: Double) throws {
        guard motionManager.isDeviceMotionAvailable else {
            throw IMUError.motionNotAvailable
        }
        
        writer = try JSONLWriter(fileURL: outputURL)
        recordingStartEpochMs = epochStartMs
        sampleCount = 0
        startupSamplesDiscarded = 0
        firstSampleTime = nil
        lastSampleTime = nil
        previousSampleTime = nil
        continuousDurationSec = 0
        continuousIntervalCount = 0
        
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
        if rawCount < startupDiscardCount {
            startupSamplesDiscarded += 1
            return
        }
        
        let motionTimestamp = motion.timestamp
        
        if firstSampleTime == nil {
            firstSampleTime = motionTimestamp
        }
        
        if let prev = previousSampleTime {
            let intervalMs = (motionTimestamp - prev) * 1000.0
            if intervalMs > 0 && intervalMs < gapThresholdMs {
                continuousDurationSec += (motionTimestamp - prev)
                continuousIntervalCount += 1
            }
        }
        previousSampleTime = motionTimestamp
        lastSampleTime = motionTimestamp
        
        let relativeMs: Double
        if let first = firstSampleTime {
            relativeMs = (motionTimestamp - first) * 1000.0
        } else {
            relativeMs = 0
        }
        let epochMs = recordingStartEpochMs + relativeMs
        
        let sample = IMUSample(
            timestampEpochMs: epochMs,
            relativeMs: relativeMs,
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
        sampleCount += 1
    }
    
    enum IMUError: Error {
        case motionNotAvailable
    }
}
