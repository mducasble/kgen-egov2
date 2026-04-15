import Foundation

/// Per-frame hand landmark detection result.
/// Landmarks use normalized image-space coordinates [0,1] for x,y.
/// z is depth relative to wrist if available from the detector, otherwise 0.0.
///
/// Landmark IDs follow MediaPipe convention (21 landmarks per hand):
///   0: WRIST, 1-4: THUMB (CMC, MCP, IP, TIP), 5-8: INDEX (MCP, PIP, DIP, TIP),
///   9-12: MIDDLE, 13-16: RING, 17-20: PINKY
struct HandLandmarkSample: Codable {
    let timestampEpochMs: Double
    let relativeMs: Double
    let frameIndex: Int
    let hands: [DetectedHand]
    
    struct DetectedHand: Codable {
        /// "left", "right", or "unknown"
        let handedness: String
        /// Detection confidence [0.0, 1.0]
        let confidence: Double
        /// 21 landmarks per hand
        let landmarks: [Landmark]
    }
    
    struct Landmark: Codable {
        /// Landmark ID (0-20, MediaPipe convention)
        let id: Int
        /// Normalized x coordinate [0, 1] in image space
        let x: Double
        /// Normalized y coordinate [0, 1] in image space
        let y: Double
        /// Relative depth. Set to 0.0 if true 3D is not available.
        /// NOTE: When using Apple Vision framework, z values are NOT metric 3D.
        /// They represent relative depth from the wrist landmark only.
        let z: Double
    }
}

/// MediaPipe-compatible landmark indices for reference
enum HandLandmarkIndex: Int, CaseIterable {
    case wrist = 0
    case thumbCMC = 1, thumbMCP = 2, thumbIP = 3, thumbTIP = 4
    case indexMCP = 5, indexPIP = 6, indexDIP = 7, indexTIP = 8
    case middleMCP = 9, middlePIP = 10, middleDIP = 11, middleTIP = 12
    case ringMCP = 13, ringPIP = 14, ringDIP = 15, ringTIP = 16
    case pinkyMCP = 17, pinkyPIP = 18, pinkyDIP = 19, pinkyTIP = 20
}
