import simd
import Foundation

/// Manages camera mount calibration (extrinsics relative to head).
/// NOT automatically inferred — represents physical mount configuration.
final class MountCalibrationService {
    
    private(set) var config: CameraMountConfig
    
    init(config: CameraMountConfig = .defaultForeheadMount) {
        self.config = config
    }
    
    /// Update mount configuration from UI settings.
    func updateConfig(
        mountType: String,
        translationX: Double, translationY: Double, translationZ: Double,
        downwardTiltDeg: Double,
        notes: String
    ) {
        let tiltRad = -downwardTiltDeg * .pi / 180.0
        let halfAngle = tiltRad / 2.0
        let quat = CameraMountConfig.Quaternion(
            x: sin(halfAngle), y: 0, z: 0, w: cos(halfAngle)
        )
        
        config = CameraMountConfig(
            mountType: mountType,
            translationMeters: CameraMountConfig.Translation(x: translationX, y: translationY, z: translationZ),
            rotationQuaternion: quat,
            downwardTiltDeg: downwardTiltDeg,
            notes: notes,
            manuallyVerified: false,
            calibrationMethod: "manual_alignment",
            calibrationErrorDeg: nil
        )
    }
    
    /// Assisted calibration: compare configured mount rotation to a measured neutral pose.
    /// User should be standing still, facing forward. The ARKit camera transform
    /// represents the actual camera orientation. We compute the angular difference
    /// between the configured mount rotation and the measured rotation.
    ///
    /// Returns the angular error in degrees, or nil if measurement is invalid.
    func runAssistedCalibration(measuredCameraQuaternion: simd_quatf) -> Double? {
        // Expected camera orientation from mount config
        let configQ = simd_quatf(
            ix: Float(config.rotationQuaternion.x),
            iy: Float(config.rotationQuaternion.y),
            iz: Float(config.rotationQuaternion.z),
            r: Float(config.rotationQuaternion.w)
        )
        
        // Compute relative rotation: delta = measured * inverse(configured)
        let deltaQ = measuredCameraQuaternion * configQ.inverse
        
        // Angular error = 2 * acos(|w|) in radians
        let angle = 2.0 * acos(min(abs(deltaQ.real), 1.0))
        let angleDeg = Double(angle) * 180.0 / .pi
        
        // Update config with calibration result
        config = CameraMountConfig(
            mountType: config.mountType,
            translationMeters: config.translationMeters,
            rotationQuaternion: config.rotationQuaternion,
            downwardTiltDeg: config.downwardTiltDeg,
            notes: config.notes,
            manuallyVerified: true,
            calibrationMethod: "assisted_calibration",
            calibrationErrorDeg: angleDeg
        )
        
        return angleDeg
    }
    
    func write(to url: URL) throws {
        try JSONFileWriter.write(config, to: url)
    }
}
