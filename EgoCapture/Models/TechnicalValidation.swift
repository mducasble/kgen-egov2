import Foundation

/// Machine-readable technical quality report for a capture session.
struct TechnicalValidation: Codable {
    let sessionId: String
    let timing: Timing
    let imu: IMU
    let video: Video
    let pose: Pose
    let calibration: Calibration
    let passCriteria: PassCriteria
    
    struct Timing: Codable {
        let videoToHeadPoseAvgDeltaMs: Double?
        let videoToHeadPoseMaxDeltaMs: Double?
        let videoToHeadPoseP95DeltaMs: Double?
        let imuToVideoEstimatedOffsetMs: Double?
    }
    
    struct IMU: Codable {
        let sampleRateHz: Double
        let sampleIntervalStdDevMs: Double
        let maxGapMs: Double
        let totalSamples: Int
    }
    
    struct Video: Codable {
        let fps: Double
        let frameIntervalStdDevMs: Double
        let totalFrames: Int
        let droppedFrames: Int
    }
    
    struct Pose: Codable {
        let headPoseCoveragePercent: Double
        let imuPoseAngularErrorMeanDeg: Double?
        let imuPoseAngularErrorMedianDeg: Double?
        let imuPoseAngularErrorP95Deg: Double?
        let imuPoseAngularErrorMaxDeg: Double?
        let skippedTrackingLossSamples: Int
        let consistencyConfidence: String
        let trackingLossFrames: Int
    }
    
    struct Calibration: Codable {
        let intrinsicsAvailable: Bool
        let distortionAvailable: Bool
        let mountVerified: Bool
        let mountCalibrationErrorDeg: Double?
        let intrinsicsMode: String?
        let extrinsicsMode: String?
    }
    
    struct PassCriteria: Codable {
        /// FPS >= 19.8 and stddev < 10ms
        let videoStable: Bool
        /// Sample rate >= 90Hz and stddev < 2ms
        let imuStable: Bool
        /// videoToHeadPoseAvgDeltaMs < 5ms
        let syncAcceptable: Bool
        /// Intrinsics available
        let calibrationAcceptable: Bool
    }
}
