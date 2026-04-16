import Foundation

/// Machine-readable technical quality report for a capture session (IMU-only mode).
struct TechnicalValidation: Codable {
    let sessionId: String
    let timing: Timing
    let imu: IMU
    let video: Video
    let calibration: Calibration
    let passCriteria: PassCriteria

    struct Timing: Codable {
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

    struct Calibration: Codable {
        let intrinsicsAvailable: Bool
        let distortionAvailable: Bool
        let mountVerified: Bool
        let mountCalibrationErrorDeg: Double?
        let intrinsicsMode: String?
        let extrinsicsMode: String?
    }

    struct PassCriteria: Codable {
        let videoStable: Bool
        let imuStable: Bool
        let syncAcceptable: Bool
        let calibrationAcceptable: Bool
    }
}
