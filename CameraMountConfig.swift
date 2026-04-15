import Foundation

/// Camera extrinsic configuration relative to the wearer's head.
/// This is NOT automatically inferred — it must be manually configured
/// based on the physical mounting position of the camera.
///
/// Translation: offset from head center to camera in meters (x=right, y=up, z=forward).
/// Rotation: quaternion representing camera orientation relative to head frame.
struct CameraMountConfig: Codable {
    /// Descriptive name of the mount type
    let mountType: String // e.g., "forehead", "temple", "hat_brim"
    /// Translation from head center to camera position in meters
    let translationMeters: Translation
    /// Rotation of camera relative to head frame (quaternion)
    let rotationQuaternion: Quaternion
    /// Downward tilt angle in degrees (positive = tilted down toward hands)
    let downwardTiltDeg: Double
    /// Notes about the mount configuration
    let notes: String
    /// Whether this config was manually verified by the operator
    let manuallyVerified: Bool
    
    struct Translation: Codable {
        let x: Double // right (+) / left (-)
        let y: Double // up (+) / down (-)
        let z: Double // forward (+) / backward (-)
    }
    
    struct Quaternion: Codable {
        let x: Double
        let y: Double
        let z: Double
        let w: Double
    }
    
    /// Default forehead mount configuration.
    /// Camera positioned ~3cm above and ~8cm forward from head center,
    /// tilted ~30° downward to maximize hand visibility.
    static var defaultForeheadMount: CameraMountConfig {
        CameraMountConfig(
            mountType: "forehead",
            translationMeters: Translation(x: 0.0, y: 0.03, z: 0.08),
            rotationQuaternion: Quaternion(x: -0.2588, y: 0.0, z: 0.0, w: 0.9659), // ~30° down
            downwardTiltDeg: 30.0,
            notes: "Default forehead mount. Adjust translation and tilt for your specific hardware.",
            manuallyVerified: false
        )
    }
}
