import Foundation
import ARKit
import AVFoundation

/// Extracts camera intrinsic calibration from ARKit or AVFoundation.
/// Writes camera_calibration.json once per session.
final class CameraCalibrationService {
    
    private(set) var calibration: CameraCalibration?
    
    /// Extract calibration from ARKit intrinsics matrix.
    func extractFromARKit(intrinsics: simd_float3x3, resolution: CGSize) {
        let matrix: [[Double]] = [
            [Double(intrinsics.columns.0.x), Double(intrinsics.columns.1.x), Double(intrinsics.columns.2.x)],
            [Double(intrinsics.columns.0.y), Double(intrinsics.columns.1.y), Double(intrinsics.columns.2.y)],
            [Double(intrinsics.columns.0.z), Double(intrinsics.columns.1.z), Double(intrinsics.columns.2.z)]
        ]
        
        calibration = CameraCalibration(
            fx: Double(intrinsics.columns.0.x),
            fy: Double(intrinsics.columns.1.y),
            cx: Double(intrinsics.columns.2.x),
            cy: Double(intrinsics.columns.2.y),
            matrix3x3: matrix,
            resolutionWidth: Int(resolution.width),
            resolutionHeight: Int(resolution.height),
            distortionLookupTable: nil,
            distortionAvailable: false,
            source: "arkit",
            capturedAtEpochMs: Date().timeIntervalSince1970 * 1000.0
        )
    }
    
    /// Attempt to extract from AVFoundation (provides distortion lookup on supported devices).
    func extractFromAVFoundation(device: AVCaptureDevice) {
        guard let formatDescription = device.activeFormat.formatDescription as CMFormatDescription? else { return }
        
        let dims = CMVideoFormatDescriptionGetDimensions(formatDescription)
        
        // Try to get lens distortion lookup table
        var distortionTable: [Float]? = nil
        if #available(iOS 15.0, *) {
            // AVCameraCalibrationData may be available on dual-camera systems
            // For single camera, we note distortion is not available
            distortionTable = nil
        }
        
        // Get intrinsics if available (only on devices with calibration data)
        // For most single-camera setups, ARKit is the better source
        if calibration == nil {
            calibration = CameraCalibration(
                fx: 0, fy: 0, cx: 0, cy: 0,
                matrix3x3: [[1,0,0],[0,1,0],[0,0,1]],
                resolutionWidth: Int(dims.width),
                resolutionHeight: Int(dims.height),
                distortionLookupTable: distortionTable,
                distortionAvailable: distortionTable != nil,
                source: "avfoundation",
                capturedAtEpochMs: Date().timeIntervalSince1970 * 1000.0
            )
        }
    }
    
    /// Write calibration to disk.
    func write(to url: URL) throws {
        guard let cal = calibration else {
            throw CalibrationError.noCalibrationData
        }
        try JSONFileWriter.write(cal, to: url)
    }
    
    enum CalibrationError: Error {
        case noCalibrationData
    }
}
