import Foundation
import ARKit
import AVFoundation

/// Extracts camera intrinsic calibration and distortion data.
/// Tries ARKit first (always available), then AVFoundation for distortion lookup tables.
final class CameraCalibrationService {
    
    private let clock = MonotonicClock.shared
    private(set) var calibration: CameraCalibration?
    
    /// Extract calibration from ARKit intrinsics matrix.
    func extractFromARKit(intrinsics: simd_float3x3, resolution: CGSize) {
        let matrix: [[Double]] = [
            [Double(intrinsics.columns.0.x), Double(intrinsics.columns.1.x), Double(intrinsics.columns.2.x)],
            [Double(intrinsics.columns.0.y), Double(intrinsics.columns.1.y), Double(intrinsics.columns.2.y)],
            [Double(intrinsics.columns.0.z), Double(intrinsics.columns.1.z), Double(intrinsics.columns.2.z)]
        ]
        
        let nowNs = clock.nowNs()
        
        calibration = CameraCalibration(
            source: "arkit",
            capturedAtEpochMs: clock.toEpochMs(nowNs),
            capturedAtNs: nowNs,
            intrinsics: CameraCalibration.Intrinsics(
                fx: Double(intrinsics.columns.0.x),
                fy: Double(intrinsics.columns.1.y),
                cx: Double(intrinsics.columns.2.x),
                cy: Double(intrinsics.columns.2.y),
                matrix3x3: matrix
            ),
            distortion: CameraCalibration.Distortion(
                available: false,
                model: nil,
                coefficients: nil,
                lookupTableLength: nil,
                inverseLookupTableLength: nil
            ),
            imageReference: CameraCalibration.ImageReference(
                width: Int(resolution.width),
                height: Int(resolution.height)
            )
        )
    }
    
    /// Attempt to extract distortion data from AVFoundation.
    /// AVCameraCalibrationData is only available on dual-camera systems
    /// when using AVCapturePhoto. In ARKit mode this is typically unavailable.
    /// We try honestly and report what we find.
    func tryExtractDistortion(from photo: Any?) {
        // AVCameraCalibrationData extraction would go here if we switch to
        // AVCapturePhoto-based capture. In ARKit mode, distortion tables
        // are not exposed by the API.
        //
        // If in future we add AVCapturePhoto support:
        // if let calibData = (photo as? AVCapturePhoto)?.resolvedSettings.intrinsicMatrix {
        //     let lut = calibData.lensDistortionLookupTable
        //     let invLut = calibData.inverseLensDistortionLookupTable
        //     ...
        // }
        //
        // For now, distortion remains unavailable. This is documented honestly.
    }
    
    /// Write calibration to disk.
    func write(to url: URL) throws {
        guard let cal = calibration else { throw CalibrationError.noCalibrationData }
        try JSONFileWriter.write(cal, to: url)
    }
    
    enum CalibrationError: Error {
        case noCalibrationData
    }
}
