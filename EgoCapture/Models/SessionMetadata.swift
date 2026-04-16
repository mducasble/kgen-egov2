import Foundation
import UIKit

/// Complete session metadata — production audit log.
struct SessionMetadata: Codable {
    let sessionId: String
    let startTimeEpochMs: Double
    let endTimeEpochMs: Double
    let durationSec: Double
    let environment: EnvironmentInfo
    let device: DeviceInfo
    let capture: CaptureInfo
    let camera: CameraInfo
    let advancedCapture: AdvancedCaptureInfo
    let semanticArtifacts: SemanticArtifactInfo
    let imuMetrics: IMUMetrics
    let videoMetrics: VideoMetrics
    let syncMetrics: SyncMetrics
    let imuPoseConsistency: IMUPoseConsistency
    let handTrackingComparison: HandTrackingComparison?
    let fusedArtifacts: FusedArtifacts
    let captureHealth: CaptureHealth
    let calibrationQuality: CalibrationQuality
    let coordinateSystem: CoordinateSystem
    let pipeline: PipelineInfo
    let validation: ValidationResult
    let qcSummary: QCSummary?
    let warnings: [String]
    
    struct EnvironmentInfo: Codable {
        let type: String; let subCategory: String; let country: String; let taskDescription: String?
    }
    struct DeviceInfo: Codable {
        let model: String; let systemVersion: String; let deviceName: String
    }
    struct CaptureInfo: Codable {
        let videoResolutionWidth: Int; let videoResolutionHeight: Int
        let targetFPS: Int; let videoCodec: String; let imuTargetHz: Int
        let videoTimestampsEstimated: Bool
        let orientationLocked: Bool
        let orientation: String
        let timestampClock: String; let epochToMonotonicPrecision: String
    }
    struct CameraInfo: Codable {
        let selectedLens: String
        let actualFovDeg: Double?
        let fovSource: String
        let selectedFormatDescription: String
    }
    struct AdvancedCaptureInfo: Codable {
        let enabled: Bool; let headPoseAvailable: Bool; let headPoseSource: String
        let cameraCalibrationAvailable: Bool; let cameraCalibrationSource: String
        let cameraMountConfigAvailable: Bool
    }
    struct SemanticArtifactInfo: Codable {
        let hasHandLandmarks: Bool; let handLandmarkSource: String
        let hasHandPose: Bool; let hasFacePresence: Bool; let hasFrameQcMetrics: Bool
        let handLandmarksAre3D: Bool
        let handLandmarksZType: String
    }

    struct HandTrackingComparison: Codable {
        let appleVisionCoveragePercent: Double?
        let mediaPipeCoveragePercent: Double?
        let appleVisionFrameCount: Int?
        let mediaPipeFrameCount: Int?
        let appleVisionAverageHandsPerFrame: Double?
        let mediaPipeAverageHandsPerFrame: Double?
        let appleVisionAverageConfidence: Double?
        let mediaPipeAverageConfidence: Double?
        let coverageWinner: String
        let notes: [String]
    }

    struct FusedArtifacts: Codable {
        let hasFusedHandPose: Bool
        let hasFusedHandPoseWorld: Bool
        let fusedDepthType: String
        let fusionMethod: String
        let isMetric3D: Bool
        let worldSpaceAvailable: Bool
    }
    
    struct IMUMetrics: Codable {
        let totalSamples: Int; let actualSampleRateHz: Double; let startupSamplesDiscarded: Int
        let sampleIntervalStdDevMs: Double; let maxGapMs: Double
    }
    struct VideoMetrics: Codable {
        let totalFrames: Int; let actualAvgFPS: Double; let droppedFrames: Int
        let frameIntervalStdDevMs: Double
    }
    
    struct SyncMetrics: Codable {
        let videoToHeadPoseAvgDeltaMs: Double?
        let videoToHeadPoseMaxDeltaMs: Double?
        let videoToHeadPoseP95DeltaMs: Double?
        let videoToHeadPoseMappingMode: String?
        let videoToHeadPoseInterpolatedPercent: Double?
        let videoToHeadPoseFallbackPercent: Double?
        let imuToVideoEstimatedOffsetMs: Double?
        let imuToVideoSyncMethod: String
        let imuToVideoSyncConfidence: String // "high", "medium", "low"
    }
    
    struct IMUPoseConsistency: Codable {
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
    }
    
    struct CaptureHealth: Codable {
        let videoBackpressureEvents: Int; let imuLagEvents: Int
        let arkitTrackingLossFrames: Int; let droppedFrames: Int
        let arkitWasInterrupted: Bool; let arkitError: String?
    }
    
    struct CalibrationQuality: Codable {
        let distortionAvailable: Bool
        let mountCalibrationVerified: Bool
        let mountCalibrationErrorDeg: Double?
    }
    
    struct CoordinateSystem: Codable {
        let type: String; let referenceFrame: String; let units: String
        let axisConvention: AxisConvention
        struct AxisConvention: Codable { let x: String; let y: String; let z: String }
        static var arkitDefault: CoordinateSystem {
            CoordinateSystem(type: "right-handed", referenceFrame: "ARKit world (gravity-aligned)",
                             units: "meters", axisConvention: AxisConvention(x: "right", y: "up", z: "backward (camera looks toward -Z)"))
        }
    }
    struct PipelineInfo: Codable {
        let version: String; let build: String; let captureMode: String
        let threadModel: String; let timestampSource: String
    }
    struct ValidationResult: Codable {
        let frameCountConsistent: Bool; let imuCoveragePercent: Double
        let headPoseCoveragePercent: Double; let timestampsMonotonic: Bool; let issues: [String]
    }
    
    static func currentDeviceInfo() -> DeviceInfo {
        let d = UIDevice.current
        return DeviceInfo(model: d.model, systemVersion: d.systemVersion, deviceName: d.name)
    }
}
