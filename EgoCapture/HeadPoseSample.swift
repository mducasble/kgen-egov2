import Foundation

/// Head pose derived from ARKit's ARCamera.transform.
/// Position is in meters relative to the ARKit world origin.
/// Rotation is a unit quaternion (Hamilton convention: x, y, z, w).
struct HeadPoseSample: Codable {
    let timestampEpochMs: Double
    let relativeMs: Double
    /// Monotonic timestamp in nanoseconds (mach_absolute_time based)
    let timestampNs: UInt64
    /// Clock source identifier
    let clock: String // "mach_absolute_time"
    /// Frame index linkage to video timeline, null if not synchronized to a video frame
    let frameIndex: Int?
    let positionMeters: Position
    let rotationQuaternion: Quaternion
    /// ARKit tracking state for this sample
    let trackingState: String // "normal", "limited", "notAvailable"
    
    struct Position: Codable {
        let x: Double
        let y: Double
        let z: Double
    }
    
    struct Quaternion: Codable {
        let x: Double
        let y: Double
        let z: Double
        let w: Double
    }
}
