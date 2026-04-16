import Foundation

/// Camera extrinsic configuration relative to the wearer's head.
/// NOT automatically inferred — manually configured based on physical mount.
struct CameraMountConfig: Codable {
    let mountType: String
    let translationMeters: Translation
    let rotationQuaternion: Quaternion
    let downwardTiltDeg: Double
    let notes: String
    let manuallyVerified: Bool
    /// "manual_alignment", "assisted_calibration", or "unknown"
    let calibrationMethod: String
    /// Angular error from assisted calibration in degrees, null if not measured
    let calibrationErrorDeg: Double?
    
    struct Translation: Codable {
        let x: Double
        let y: Double
        let z: Double
    }
    
    struct Quaternion: Codable {
        let x: Double
        let y: Double
        let z: Double
        let w: Double
    }
    
    static var defaultForeheadMount: CameraMountConfig {
        CameraMountConfig(
            mountType: "forehead",
            translationMeters: Translation(x: 0.0, y: 0.03, z: 0.08),
            rotationQuaternion: Quaternion(x: -0.2588, y: 0.0, z: 0.0, w: 0.9659),
            downwardTiltDeg: 30.0,
            notes: "Default forehead mount. Adjust for your hardware.",
            manuallyVerified: false,
            calibrationMethod: "manual_alignment",
            calibrationErrorDeg: nil
        )
    }
}
