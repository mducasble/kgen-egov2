import Foundation

/// Camera intrinsic calibration extracted from ARKit/AVFoundation.
/// fx, fy = focal length in pixels. cx, cy = principal point in pixels.
struct CameraCalibration: Codable {
    let fx: Double
    let fy: Double
    let cx: Double
    let cy: Double
    /// Full 3x3 intrinsic matrix, row-major
    let matrix3x3: [[Double]]
    /// Image resolution this calibration refers to
    let resolutionWidth: Int
    let resolutionHeight: Int
    /// Lens distortion lookup table from AVFoundation, if available
    let distortionLookupTable: [Float]?
    /// Whether distortion data was available from the device
    let distortionAvailable: Bool
    /// Source of calibration data
    let source: String // "arkit", "avfoundation", "manual"
    /// Timestamp when calibration was captured
    let capturedAtEpochMs: Double
}
