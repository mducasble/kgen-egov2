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
        let model: String
        let hardwareIdentifier: String
        let systemVersion: String
        let deviceName: String
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
        /// Campaign tag the session was recorded under (e.g. `"EgoTeste-iOS"`).
        let campaign: String?
        /// Raw contributor name as typed by the user in Settings.
        let userName: String?
        /// URL-safe slug used as part of the S3 key prefix.
        let userSlug: String?
        /// Per-device opaque vendor identifier; used to deduplicate two contributors
        /// that type the same name, without exposing any Apple ID / PII.
        let vendorId: String?
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
        /// plumb_bob coefficients `[k1, k2, p1, p2, k3]` when available from
        /// the lens-distortion probe; omitted when the probe did not run or
        /// failed (in which case `distortionModel` stays `"uncorrected_barrel"`
        /// or `"apple_isp_corrected"`).
        let distortionCoefficients: [Double]?
        /// Diagnostic confidence for the fit (pixels at recording resolution).
        let distortionFitResidualRmsPx: Double?

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
        let hwId = DeviceIdentifier.hardwareIdentifier()
        let friendly = DeviceIdentifier.friendlyName(forIdentifier: hwId)
        return DeviceInfo(
            model: friendly,
            hardwareIdentifier: hwId,
            systemVersion: d.systemVersion,
            deviceName: d.name
        )
    }
}

/// Resolves the raw hardware identifier (e.g. "iPhone15,3") and maps it to a
/// commercial name (e.g. "iPhone 14 Pro Max"). Falls back to the raw identifier
/// when the model is unknown (new device not yet in the table).
enum DeviceIdentifier {

    /// Raw sysctl identifier like "iPhone15,3" or "arm64" on a Simulator.
    static func hardwareIdentifier() -> String {
        #if targetEnvironment(simulator)
        if let id = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"], !id.isEmpty {
            return id
        }
        return "Simulator"
        #else
        var sys = utsname()
        uname(&sys)
        let mirror = Mirror(reflecting: sys.machine)
        let bytes = mirror.children
            .compactMap { $0.value as? Int8 }
            .filter { $0 != 0 }
            .map { UInt8(bitPattern: $0) }
        return String(bytes: bytes, encoding: .utf8) ?? "Unknown"
        #endif
    }

    /// Returns the commercial name for a given hardware identifier.
    /// Covers iPhone 11 through iPhone 16 and common iPads.
    /// Unknown identifiers are returned as-is.
    static func friendlyName(forIdentifier id: String) -> String {
        if let mapped = iPhoneMap[id] ?? iPadMap[id] { return mapped }
        return id
    }

    private static let iPhoneMap: [String: String] = [
        // iPhone 11
        "iPhone12,1": "iPhone 11",
        "iPhone12,3": "iPhone 11 Pro",
        "iPhone12,5": "iPhone 11 Pro Max",
        "iPhone12,8": "iPhone SE (2nd gen)",
        // iPhone 12
        "iPhone13,1": "iPhone 12 mini",
        "iPhone13,2": "iPhone 12",
        "iPhone13,3": "iPhone 12 Pro",
        "iPhone13,4": "iPhone 12 Pro Max",
        // iPhone 13
        "iPhone14,4": "iPhone 13 mini",
        "iPhone14,5": "iPhone 13",
        "iPhone14,2": "iPhone 13 Pro",
        "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,6": "iPhone SE (3rd gen)",
        // iPhone 14
        "iPhone14,7": "iPhone 14",
        "iPhone14,8": "iPhone 14 Plus",
        "iPhone15,2": "iPhone 14 Pro",
        "iPhone15,3": "iPhone 14 Pro Max",
        // iPhone 15
        "iPhone15,4": "iPhone 15",
        "iPhone15,5": "iPhone 15 Plus",
        "iPhone16,1": "iPhone 15 Pro",
        "iPhone16,2": "iPhone 15 Pro Max",
        // iPhone 16
        "iPhone17,3": "iPhone 16",
        "iPhone17,4": "iPhone 16 Plus",
        "iPhone17,1": "iPhone 16 Pro",
        "iPhone17,2": "iPhone 16 Pro Max",
    ]

    private static let iPadMap: [String: String] = [
        "iPad13,1": "iPad Air (4th gen)",
        "iPad13,2": "iPad Air (4th gen)",
        "iPad13,4": "iPad Pro 11-inch (3rd gen)",
        "iPad13,5": "iPad Pro 11-inch (3rd gen)",
        "iPad13,6": "iPad Pro 11-inch (3rd gen)",
        "iPad13,7": "iPad Pro 11-inch (3rd gen)",
        "iPad13,8": "iPad Pro 12.9-inch (5th gen)",
        "iPad13,9": "iPad Pro 12.9-inch (5th gen)",
        "iPad13,10": "iPad Pro 12.9-inch (5th gen)",
        "iPad13,11": "iPad Pro 12.9-inch (5th gen)",
        "iPad13,16": "iPad Air (5th gen)",
        "iPad13,17": "iPad Air (5th gen)",
        "iPad14,3": "iPad Pro 11-inch (4th gen)",
        "iPad14,4": "iPad Pro 11-inch (4th gen)",
        "iPad14,5": "iPad Pro 12.9-inch (6th gen)",
        "iPad14,6": "iPad Pro 12.9-inch (6th gen)",
        "iPad14,8": "iPad Air 11-inch (M2)",
        "iPad14,9": "iPad Air 11-inch (M2)",
        "iPad14,10": "iPad Air 13-inch (M2)",
        "iPad14,11": "iPad Air 13-inch (M2)",
        "iPad16,3": "iPad Pro 11-inch (M4)",
        "iPad16,4": "iPad Pro 11-inch (M4)",
        "iPad16,5": "iPad Pro 13-inch (M4)",
        "iPad16,6": "iPad Pro 13-inch (M4)",
    ]
}
