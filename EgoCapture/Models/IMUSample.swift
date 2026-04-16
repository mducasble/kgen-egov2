import Foundation

/// Represents a single synchronized accelerometer + gyroscope sample from CoreMotion.
/// Coordinates follow Apple's device coordinate system (right-hand rule, Z out of screen).
struct IMUSample: Codable {
    /// Epoch timestamp in milliseconds (wall clock — for logging only)
    let timestampEpochMs: Double
    /// Milliseconds elapsed since recording start
    let relativeMs: Double
    /// Monotonic timestamp in nanoseconds (mach_absolute_time based)
    let timestampNs: UInt64
    /// Clock source identifier
    let clock: String // "mach_absolute_time"
    /// Accelerometer reading in G's (gravity-included via CMDeviceMotion)
    let accelerometer: XYZ
    /// Gyroscope reading in radians/second
    let gyroscope: XYZ
    
    struct XYZ: Codable {
        let x: Double
        let y: Double
        let z: Double
    }
}
