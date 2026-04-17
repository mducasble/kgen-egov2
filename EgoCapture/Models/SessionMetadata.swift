import Foundation
import UIKit

/// Complete session metadata — production audit log (IMU-only mode).
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
    let signalConfiguration: SignalConfiguration
    let collector: Collector
    let videoEncoding: VideoEncoding
    let colorProfile: ColorProfile
    let imuMetrics: IMUMetrics
    let videoMetrics: VideoMetrics
    let syncMetrics: SyncMetrics
    let captureHealth: CaptureHealth
    let cameraIntrinsics: CameraIntrinsics?
    let cameraExtrinsics: CameraExtrinsics?
    let specCompliance: SpecCompliance?
    let coordinateSystem: CoordinateSystem
    let pipeline: PipelineInfo
    let validation: ValidationResult
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
        let diagonalFovDeg: Double?
        let deviceMaxHorizontalFov: Double?
        let fovSource: String
        let fovMode: String?
        let fovLimitReached: Bool?
        let fovLimitReason: String?
        let fovCompliance: String?
        let fovNote: String?
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

    struct SignalConfiguration: Codable {
        let primarySignal: String
        let poseIncluded: Bool
        let imuIncluded: Bool
        let handTrackingIncluded: Bool
    }

    struct Collector: Codable {
        let collectorId: String
        let collectorType: String
        let collectionMode: String
    }

    struct VideoEncoding: Codable {
        let codec: String
        let bitrateMbps: Double
        let gopLength: Int
        let bFrames: Int
        let profile: String
        let colorDepth: String
        let hdr: Bool
        let encodingCompliant: Bool
    }

    struct ColorProfile: Codable {
        let hdrEnabled: Bool
        let colorDepth: String
        let colorSpace: String
        let note: String
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
        let imuToVideoEstimatedOffsetMs: Double
        let imuToVideoSyncMethod: String
        let imuToVideoSyncConfidence: String
        let observedJitterStdDevMs: Double
        let observedMaxDeltaMs: Double
        let samplePairsUsed: Int
    }

    struct CaptureHealth: Codable {
        let videoBackpressureEvents: Int; let imuLagEvents: Int
        let droppedFrames: Int
    }

    struct CameraIntrinsics: Codable {
        let intrinsicsMode: String
        let deviceModel: String
        let lens: String
        let resolution: Resolution
        let fovHorizontalDeg: Double?
        let fovDiagonalDeg: Double?
        let principalPoint: PrincipalPoint
        let focalLengthPixels: FocalLength
        let intrinsicsSource: String
        let distortionModel: String
        let distortionPresent: Bool
        let distortionNote: String

        struct Resolution: Codable { let width: Int; let height: Int }
        struct PrincipalPoint: Codable { let cx: Double?; let cy: Double? }
        struct FocalLength: Codable { let fx: Double?; let fy: Double? }
    }

    struct CameraExtrinsics: Codable {
        let extrinsicsMode: String
        let referenceFrame: String
        let mountType: String
        let translationMeters: Translation
        let rotationEulerDeg: EulerRotation
        let rotationQuaternion: Quaternion
        let extrinsicsSource: String
        let extrinsicsVerified: Bool
        let extrinsicsNote: String

        struct Translation: Codable { let x: Double; let y: Double; let z: Double }
        struct EulerRotation: Codable { let pitch: Double; let yaw: Double; let roll: Double }
        struct Quaternion: Codable { let x: Double?; let y: Double?; let z: Double?; let w: Double? }
    }

    struct SpecCompliance: Codable {
        let videoFormat: String
        let landscape: Bool
        let imuIncluded: Bool
        let poseIncluded: Bool
        let intrinsicsIncluded: Bool
        let extrinsicsIncluded: Bool
        let intrinsicsType: String
        let extrinsicsType: String
        let encodingCompliant: Bool
        let colorCompliant: Bool
        let syncCompliant: Bool
        let imuCompliant: Bool
        let fovCompliant: Bool
        let notes: [String]
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
