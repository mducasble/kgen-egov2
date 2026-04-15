import Foundation

/// Manages camera mount calibration (extrinsics relative to head).
/// This is NOT automatically inferred — it represents the physical
/// position/orientation of the camera on the head mount.
final class MountCalibrationService {
    
    private(set) var config: CameraMountConfig
    
    init(config: CameraMountConfig = .defaultForeheadMount) {
        self.config = config
    }
    
    /// Update mount configuration (e.g., from UI settings).
    func updateConfig(
        mountType: String,
        translationX: Double, translationY: Double, translationZ: Double,
        downwardTiltDeg: Double,
        notes: String
    ) {
        // Convert tilt angle to quaternion (rotation about X axis)
        let tiltRad = -downwardTiltDeg * .pi / 180.0 // negative = downward
        let halfAngle = tiltRad / 2.0
        let quat = CameraMountConfig.Quaternion(
            x: sin(halfAngle),
            y: 0,
            z: 0,
            w: cos(halfAngle)
        )
        
        config = CameraMountConfig(
            mountType: mountType,
            translationMeters: CameraMountConfig.Translation(
                x: translationX,
                y: translationY,
                z: translationZ
            ),
            rotationQuaternion: quat,
            downwardTiltDeg: downwardTiltDeg,
            notes: notes,
            manuallyVerified: false
        )
    }
    
    /// Write mount config to disk.
    func write(to url: URL) throws {
        try JSONFileWriter.write(config, to: url)
    }
}
