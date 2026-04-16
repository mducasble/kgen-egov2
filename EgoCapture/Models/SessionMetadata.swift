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
    let captureProfile: CaptureProfile
    let contextTracking: ContextTracking?
    let semanticArtifacts: SemanticArtifactInfo
    let imuMetrics: IMUMetrics
    let videoMetrics: VideoMetrics
    let syncMetrics: SyncMetrics
    let handTrackingComparison: HandTrackingComparison?
    let fusedArtifacts: FusedArtifacts
    let captureHealth: CaptureHealth
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
        let fovMode: String?
        let fovTargetAchieved: Bool?
        let selectedFormatDescription: String
        let usedUltraWide: Bool?
        let exposurePolicy: String?
    }
    struct CaptureProfile: Codable {
        let mode: String
        let headPose: Bool
        let worldTracking: Bool
        let depthType: String
        let cameraSource: String
    }
    struct ContextTracking: Codable {
        let primaryHandTracker: String
        let trackingPriority: String
        let fallbackEnabled: Bool
        let fallbackTracker: String?
        let bestOfSelectionEnabled: Bool
        let mediaPipeMinDetectionConfidence: Double
        let mediaPipeMinTrackingConfidence: Double
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
        let fallbackEnabled: Bool
        let bestOfFrames: BestOfStats?
        let notes: [String]
    }

    struct BestOfStats: Codable {
        let totalFrames: Int
        let mediaPipeSelected: Int
        let appleVisionSelected: Int
        let noneSelected: Int
    }

    struct FusedArtifacts: Codable {
        let hasFusedHandPose: Bool
        let fusedDepthType: String
        let fusionMethod: String
        let isMetric3D: Bool
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
        let imuToVideoEstimatedOffsetMs: Double?
        let imuToVideoSyncMethod: String
        let imuToVideoSyncConfidence: String
    }

    struct CaptureHealth: Codable {
        let videoBackpressureEvents: Int; let imuLagEvents: Int
        let droppedFrames: Int
    }

    struct CoordinateSystem: Codable {
        let type: String; let referenceFrame: String; let units: String
        let axisConvention: AxisConvention
        struct AxisConvention: Codable { let x: String; let y: String; let z: String }
        static var cameraDefault: CoordinateSystem {
            CoordinateSystem(type: "right-handed", referenceFrame: "camera (image plane)",
                             units: "normalized", axisConvention: AxisConvention(x: "right", y: "down", z: "forward (into scene)"))
        }
    }
    struct PipelineInfo: Codable {
        let version: String; let build: String; let captureMode: String
        let threadModel: String; let timestampSource: String
    }
    struct ValidationResult: Codable {
        let frameCountConsistent: Bool; let imuCoveragePercent: Double
        let timestampsMonotonic: Bool; let issues: [String]
    }

    static func currentDeviceInfo() -> DeviceInfo {
        let d = UIDevice.current
        return DeviceInfo(model: d.model, systemVersion: d.systemVersion, deviceName: d.name)
    }
}
