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
    let syncMetrics: SyncMetrics
    let captureHealth: CaptureHealth
    let coordinateSystem: CoordinateSystem
    let pipeline: PipelineInfo
    let validation: ValidationResult
    let qcSummary: QCSummary?
    let warnings: [String]
    
    // MARK: - Existing types
    
    struct EnvironmentInfo: Codable {
        let type: String
        let subCategory: String
        let country: String
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
        /// Clock used for all monotonic timestamps
        let timestampClock: String // "mach_absolute_time"
        /// Precision note about epoch↔monotonic conversion
        let epochToMonotonicPrecision: String
    }
    
    struct AdvancedCaptureInfo: Codable {
        let enabled: Bool
        let headPoseAvailable: Bool
        let headPoseSource: String
        let cameraCalibrationAvailable: Bool
        let cameraCalibrationSource: String
        let cameraMountConfigAvailable: Bool
    }
    
    struct SemanticArtifactInfo: Codable {
        let hasHandLandmarks: Bool
        let handLandmarkSource: String
        let hasHandPose: Bool
        let hasFacePresence: Bool
        let hasFrameQcMetrics: Bool
        let handLandmarksAre3D: Bool
    }
    
    // MARK: - Extended sensor metrics (items 10)
    
    struct IMUMetrics: Codable {
        let totalSamples: Int
        let actualSampleRateHz: Double
        let startupSamplesDiscarded: Int
        /// Standard deviation of sample intervals (ms)
        let sampleIntervalStdDevMs: Double
        /// Largest gap between consecutive samples (ms)
        let maxGapMs: Double
    }
    
    struct VideoMetrics: Codable {
        let totalFrames: Int
        let actualAvgFPS: Double
        let droppedFrames: Int
        /// Standard deviation of frame intervals (ms)
        let frameIntervalStdDevMs: Double
    }
    
    // MARK: - New: Sync metrics (item 3)
    
    struct SyncMetrics: Codable {
        /// Average absolute delta between video and head pose timestamps (ms)
        let videoToHeadPoseAvgDeltaMs: Double
        /// Maximum absolute delta between video and head pose timestamps (ms)
        let videoToHeadPoseMaxDeltaMs: Double
        /// Estimated offset between IMU and video clocks (ms). Null if not computable.
        let imuToVideoEstimatedOffsetMs: Double?
        /// Method used to estimate IMU↔video offset
        let imuToVideoSyncMethod: String // "nearest_timestamp" or "not_computed"
    }
    
    // MARK: - New: Capture health (item 8)
    
    struct CaptureHealth: Codable {
        /// Number of times the asset writer wasn't ready for data
        let videoBackpressureEvents: Int
        /// Number of IMU gaps > 50ms
        let imuLagEvents: Int
        /// Number of ARKit frames with trackingState != normal
        let arkitTrackingLossFrames: Int
        /// Total dropped video frames
        let droppedFrames: Int
        /// Whether ARSession was interrupted
        let arkitWasInterrupted: Bool
        /// ARKit session error if any
        let arkitError: String?
    }
    
    // MARK: - New: Coordinate system (item 7)
    
    struct CoordinateSystem: Codable {
        let type: String           // "right-handed"
        let referenceFrame: String // "ARKit world"
        let units: String          // "meters"
        let axisConvention: AxisConvention
        
        struct AxisConvention: Codable {
            let x: String // "right"
            let y: String // "up"
            let z: String // "backward" (ARKit uses -Z forward)
        }
        
        static var arkitDefault: CoordinateSystem {
            CoordinateSystem(
                type: "right-handed",
                referenceFrame: "ARKit world (gravity-aligned)",
                units: "meters",
                axisConvention: AxisConvention(
                    x: "right",
                    y: "up",
                    z: "backward (camera looks toward -Z)"
                )
            )
        }
    }
    
    // MARK: - New: Pipeline versioning (item 9)
    
    struct PipelineInfo: Codable {
        let version: String
        let build: String
        let captureMode: String     // "arkit+assetwriter" or "avfoundation+assetwriter"
        let threadModel: String     // "multi-queue"
        let timestampSource: String // "mach_absolute_time"
    }
    
    // MARK: - New: Validation results (item 13)
    
    struct ValidationResult: Codable {
        let frameCountConsistent: Bool
        let imuCoveragePercent: Double
        let headPoseCoveragePercent: Double
        let timestampsMonotonic: Bool
        let issues: [String]
    }
    
    // MARK: - Factory
    
    static func currentDeviceInfo() -> DeviceInfo {
        let device = UIDevice.current
        return DeviceInfo(
            model: device.model,
            systemVersion: device.systemVersion,
            deviceName: device.name
        )
    }
}
