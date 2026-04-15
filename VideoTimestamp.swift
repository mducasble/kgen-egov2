import Foundation

/// Per-frame video timestamp for synchronization.
struct VideoTimestamp: Codable {
    let frameIndex: Int
    let timestampEpochMs: Double
    let relativeMs: Double
    /// Presentation timestamp from AVFoundation
    let presentationTimeSec: Double
    /// Whether this timestamp is estimated (e.g., from frame rate) vs exact from CMSampleBuffer
    let isEstimated: Bool
}
