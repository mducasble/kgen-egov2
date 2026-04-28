import Foundation

/// Per-frame quality control metrics for downstream filtering.
struct FrameQCMetricsSample: Codable {
    let timestampEpochMs: Double
    let relativeMs: Double
    let frameIndex: Int
    /// Perceptual brightness score [0.0, 100.0]
    let brightnessScore: Double
    /// Sharpness score [0.0, 100.0]. Higher = sharper.
    let blurScore: Double
    /// Whether any hand was detected in this frame
    let handDetected: Bool
    /// Whether any face was detected in this frame
    let faceDetected: Bool
}

/// Aggregate QC summary computed after session ends.
struct QCSummary: Codable {
    let totalFrames: Int
    let handPresenceRate: Double
    let facePresenceRate: Double
    let brightnessMean: Double
    let brightnessStdDev: Double
    let blurMean: Double
    let blurStdDev: Double
    /// Fraction of frames below minimum brightness threshold
    let darkFrameRate: Double
    /// Fraction of frames below minimum sharpness threshold
    let blurryFrameRate: Double
}
