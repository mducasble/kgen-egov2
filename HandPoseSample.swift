import Foundation

/// Derived hand pose from landmark positions.
/// Joint angles are computed geometrically from 3-point chains.
/// Null values indicate unreliable or uncomputable measurements.
struct HandPoseSample: Codable {
    let timestampEpochMs: Double
    let relativeMs: Double
    let frameIndex: Int
    /// "left", "right", or "unknown"
    let handedness: String
    /// Detection confidence [0.0, 1.0]
    let confidence: Double
    /// Wrist position (normalized image coords or relative 3D)
    let wrist: Point3D
    /// Fingertip positions
    let fingertips: Fingertips
    /// Joint angles in degrees, null if unreliable
    let jointAnglesDeg: JointAngles
    /// Angle between thumb tip and pinky tip planes, null if unreliable
    let thumbOppositionDeg: Double?
    
    struct Point3D: Codable {
        let x: Double
        let y: Double
        let z: Double
    }
    
    struct Fingertips: Codable {
        let thumb: Point3D
        let index: Point3D
        let middle: Point3D
        let ring: Point3D
        let pinky: Point3D
    }
    
    struct JointAngles: Codable {
        let thumb_mcp: Double?
        let thumb_ip: Double?
        let index_mcp: Double?
        let index_pip: Double?
        let index_dip: Double?
        let middle_mcp: Double?
        let middle_pip: Double?
        let middle_dip: Double?
        let ring_mcp: Double?
        let ring_pip: Double?
        let ring_dip: Double?
        let pinky_mcp: Double?
        let pinky_pip: Double?
        let pinky_dip: Double?
    }
}
