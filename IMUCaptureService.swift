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
    
    /// Number of initial samples to discard (startup noise)
    private let startupDiscardCount = 10
    
    /// Target sample interval (100 Hz = 0.01s)
    private let targetInterval: TimeInterval = 0.01
    
    var totalSamples: Int { sampleCount }
    
    var actualSampleRateHz: Double {
        guard let first = firstSampleTime, let last = lastSampleTime, sampleCount > 1 else { return 0 }
        let duration = last - first
        return duration > 0 ? Double(sampleCount - 1) / duration : 0
    }
    
    var startupDiscarded: Int { startupSamplesDiscarded }
    
    // MARK: - Start / Stop
    
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
        
        operationQueue.name = "com.egocapture.imu"
        operationQueue.maxConcurrentOperationCount = 1
        operationQueue.qualityOfService = .userInteractive
        
        // Use deviceMotion to get synchronized accel + gyro
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
    
    // MARK: - Processing
    
    private func handleMotionUpdate(_ motion: CMDeviceMotion) {
        // Discard startup samples to avoid noise
        let rawCount = sampleCount + startupSamplesDiscarded
        if rawCount < startupDiscardCount {
            startupSamplesDiscarded += 1
            return
        }
        
        let motionTimestamp = motion.timestamp // boot-relative seconds
        
        if firstSampleTime == nil {
            firstSampleTime = motionTimestamp
        }
        lastSampleTime = motionTimestamp
        
        // Calculate epoch and relative time
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
                x: motion.userAcceleration.x + motion.gravity.x, // total acceleration
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
    
    // MARK: - Errors
    
    enum IMUError: Error {
        case motionNotAvailable
    }
}
