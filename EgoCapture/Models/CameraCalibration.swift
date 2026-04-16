import Foundation

/// Camera intrinsic calibration with structured distortion metadata.
struct CameraCalibration: Codable {
    let source: String // "arkit", "avfoundation", "manual"
    let capturedAtEpochMs: Double
    let capturedAtNs: UInt64
    
    let intrinsics: Intrinsics
    let distortion: Distortion
    let imageReference: ImageReference
    
    struct Intrinsics: Codable {
        let fx: Double
        let fy: Double
        let cx: Double
        let cy: Double
        let matrix3x3: [[Double]]
    }
    
    struct Distortion: Codable {
        let available: Bool
        /// "lookup_table", "brown-conrady", "unknown", or null
        let model: String?
        /// Parametric coefficients if available (e.g., [k1,k2,p1,p2,k3])
        let coefficients: [Double]?
        /// Length of forward distortion lookup table
        let lookupTableLength: Int?
        /// Length of inverse distortion lookup table
        let inverseLookupTableLength: Int?
    }
    
    struct ImageReference: Codable {
        let width: Int
        let height: Int
    }
}
