import Foundation

/// Per-frame face presence detection for privacy/QC purposes.
struct FacePresenceSample: Codable {
    let timestampEpochMs: Double
    let relativeMs: Double
    let frameIndex: Int
    let faceDetected: Bool
    /// Detection confidence [0.0, 1.0], null if detector does not provide confidence
    let confidence: Double?
}
