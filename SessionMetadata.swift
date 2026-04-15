import Foundation
import UIKit

/// Complete session metadata written at the end of recording.
struct SessionMetadata: Codable {
    let sessionId: String
    let startTimeEpochMs: Double
    let endTimeEpochMs: Double
    let durationSec: Double
    let environment: EnvironmentInfo
    let device: DeviceInfo
    let capture: CaptureInfo
    let advancedCapture: AdvancedCaptureInfo
    let semanticArtifacts: SemanticArtifactInfo
    let imuMetrics: IMUMetrics
    let videoMetrics: VideoMetrics
    let qcSummary: QCSummary?
    let warnings: [String]
    
    struct EnvironmentInfo: Codable {
        /// "residential" or "commercial"
        let type: String
        /// Sub-category (e.g., "room_tidy_up", "warehouse_logistics")
        let subCategory: String
        /// Country code
        let country: String
        /// Optional high-level task description
        let taskDescription: String?
    }
    
    struct DeviceInfo: Codable {
        let model: String
        let systemVersion: String
        let deviceName: String
    }
    
    struct CaptureInfo: Codable {
        let videoResolutionWidth: Int
        let videoResolutionHeight: Int
        let targetFPS: Int
        let videoCodec: String
        let imuTargetHz: Int
        let videoTimestampsEstimated: Bool
    }
    
    struct AdvancedCaptureInfo: Codable {
        let enabled: Bool
        let headPoseAvailable: Bool
        let headPoseSource: String // "arkit" or "none"
        let cameraCalibrationAvailable: Bool
        let cameraCalibrationSource: String // "arkit", "avfoundation", "none"
        let cameraMountConfigAvailable: Bool
    }
    
    struct SemanticArtifactInfo: Codable {
        let hasHandLandmarks: Bool
        let handLandmarkSource: String // "apple_vision", "mediapipe", "none"
        let hasHandPose: Bool
        let hasFacePresence: Bool
        let hasFrameQcMetrics: Bool
        /// Whether hand landmark z-values are true 3D or relative depth
        let handLandmarksAre3D: Bool
    }
    
    struct IMUMetrics: Codable {
        let totalSamples: Int
        let actualSampleRateHz: Double
        let startupSamplesDiscarded: Int
    }
    
    struct VideoMetrics: Codable {
        let totalFrames: Int
        let actualAvgFPS: Double
        let droppedFrames: Int
    }
    
    /// Create device info from current device
    static func currentDeviceInfo() -> DeviceInfo {
        let device = UIDevice.current
        return DeviceInfo(
            model: device.model,
            systemVersion: device.systemVersion,
            deviceName: device.name
        )
    }
}
