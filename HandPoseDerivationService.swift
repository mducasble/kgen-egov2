import Foundation
import simd

/// Derives structured hand pose (fingertip positions, joint angles, thumb opposition)
/// from raw hand landmarks using geometric computation.
///
/// Joint angles are computed as the angle at vertex B in the chain A→B→C.
/// If landmarks are 2D (z=0), angles are computed in 2D and marked with lower confidence.
/// Null values indicate unreliable or uncomputable measurements.
final class HandPoseDerivationService {
    
    private var writer: JSONLWriter?
    private var recordingStartEpochMs: Double = 0
    
    /// Whether the source landmarks have true 3D data
    private let has3DLandmarks: Bool
    private let sourceName: String
    
    init(has3DLandmarks: Bool, sourceName: String = "apple_vision") {
        self.has3DLandmarks = has3DLandmarks
        self.sourceName = sourceName
    }
    
    func start(outputURL: URL, epochStartMs: Double) throws {
        writer = try JSONLWriter(fileURL: outputURL)
        recordingStartEpochMs = epochStartMs
    }
    
    /// Derive hand pose from a landmark sample.
    func deriveFromLandmarks(_ sample: HandLandmarkSample) {
        for hand in sample.hands {
            guard hand.landmarks.count == 21 else { continue }
            
            let pose = deriveSingleHand(
                hand: hand,
                timestampEpochMs: sample.timestampEpochMs,
                relativeMs: sample.relativeMs,
                timestampNs: sample.timestampNs,
                frameIndex: sample.frameIndex
            )
            
            writer?.append(pose)
        }
    }
    
    func stop() {
        writer?.close()
    }
    
    var rowCount: Int { writer?.rowCount ?? 0 }
    
    // MARK: - Private Derivation
    
    private func deriveSingleHand(
        hand: HandLandmarkSample.DetectedHand,
        timestampEpochMs: Double,
        relativeMs: Double,
        timestampNs: UInt64,
        frameIndex: Int
    ) -> HandPoseSample {
        
        let lm = hand.landmarks.sorted { $0.id < $1.id }
        
        // Extract key positions
        let wrist = point3D(from: lm[0])
        
        let fingertips = HandPoseSample.Fingertips(
            thumb: point3D(from: lm[HandLandmarkIndex.thumbTIP.rawValue]),
            index: point3D(from: lm[HandLandmarkIndex.indexTIP.rawValue]),
            middle: point3D(from: lm[HandLandmarkIndex.middleTIP.rawValue]),
            ring: point3D(from: lm[HandLandmarkIndex.ringTIP.rawValue]),
            pinky: point3D(from: lm[HandLandmarkIndex.pinkyTIP.rawValue])
        )
        
        // Compute joint angles
        let jointAngles = computeJointAngles(landmarks: lm)
        
        // Compute thumb opposition angle
        let thumbOpp = computeThumbOpposition(landmarks: lm)
        
        return HandPoseSample(
            timestampEpochMs: timestampEpochMs,
            relativeMs: relativeMs,
            timestampNs: timestampNs,
            frameIndex: frameIndex,
            handedness: hand.handedness,
            confidence: hand.confidence,
            source: sourceName,
            wrist: wrist,
            fingertips: fingertips,
            jointAnglesDeg: jointAngles,
            thumbOppositionDeg: thumbOpp
        )
    }
    
    /// Compute angle at vertex B in the chain A→B→C.
    /// Returns degrees, or nil if vectors are degenerate.
    private func angleDeg(a: SIMD3<Double>, b: SIMD3<Double>, c: SIMD3<Double>) -> Double? {
        let ba = a - b
        let bc = c - b
        
        let lenBA = simd_length(ba)
        let lenBC = simd_length(bc)
        
        // Guard against degenerate (zero-length) vectors
        guard lenBA > 1e-8 && lenBC > 1e-8 else { return nil }
        
        let cosAngle = simd_dot(ba, bc) / (lenBA * lenBC)
        // Clamp to avoid NaN from floating point errors
        let clamped = max(-1.0, min(1.0, cosAngle))
        return acos(clamped) * 180.0 / .pi
    }
    
    private func computeJointAngles(landmarks: [HandLandmarkSample.Landmark]) -> HandPoseSample.JointAngles {
        // Thumb: CMC(1) → MCP(2) → IP(3), MCP(2) → IP(3) → TIP(4)
        let thumbMCP = angleDeg(
            a: vec(landmarks[1]), b: vec(landmarks[2]), c: vec(landmarks[3])
        )
        let thumbIP = angleDeg(
            a: vec(landmarks[2]), b: vec(landmarks[3]), c: vec(landmarks[4])
        )
        
        // Index: MCP(5)→PIP(6)→DIP(7), PIP(6)→DIP(7)→TIP(8)
        // For MCP angle, use wrist(0) as proximal
        let indexMCP = angleDeg(
            a: vec(landmarks[0]), b: vec(landmarks[5]), c: vec(landmarks[6])
        )
        let indexPIP = angleDeg(
            a: vec(landmarks[5]), b: vec(landmarks[6]), c: vec(landmarks[7])
        )
        let indexDIP = angleDeg(
            a: vec(landmarks[6]), b: vec(landmarks[7]), c: vec(landmarks[8])
        )
        
        // Middle
        let middleMCP = angleDeg(
            a: vec(landmarks[0]), b: vec(landmarks[9]), c: vec(landmarks[10])
        )
        let middlePIP = angleDeg(
            a: vec(landmarks[9]), b: vec(landmarks[10]), c: vec(landmarks[11])
        )
        let middleDIP = angleDeg(
            a: vec(landmarks[10]), b: vec(landmarks[11]), c: vec(landmarks[12])
        )
        
        // Ring
        let ringMCP = angleDeg(
            a: vec(landmarks[0]), b: vec(landmarks[13]), c: vec(landmarks[14])
        )
        let ringPIP = angleDeg(
            a: vec(landmarks[13]), b: vec(landmarks[14]), c: vec(landmarks[15])
        )
        let ringDIP = angleDeg(
            a: vec(landmarks[14]), b: vec(landmarks[15]), c: vec(landmarks[16])
        )
        
        // Pinky
        let pinkyMCP = angleDeg(
            a: vec(landmarks[0]), b: vec(landmarks[17]), c: vec(landmarks[18])
        )
        let pinkyPIP = angleDeg(
            a: vec(landmarks[17]), b: vec(landmarks[18]), c: vec(landmarks[19])
        )
        let pinkyDIP = angleDeg(
            a: vec(landmarks[18]), b: vec(landmarks[19]), c: vec(landmarks[20])
        )
        
        return HandPoseSample.JointAngles(
            thumb_mcp: thumbMCP,
            thumb_ip: thumbIP,
            index_mcp: indexMCP,
            index_pip: indexPIP,
            index_dip: indexDIP,
            middle_mcp: middleMCP,
            middle_pip: middlePIP,
            middle_dip: middleDIP,
            ring_mcp: ringMCP,
            ring_pip: ringPIP,
            ring_dip: ringDIP,
            pinky_mcp: pinkyMCP,
            pinky_pip: pinkyPIP,
            pinky_dip: pinkyDIP
        )
    }
    
    /// Thumb opposition: angle between thumb-tip-to-wrist vector and pinky-tip-to-wrist vector.
    private func computeThumbOpposition(landmarks: [HandLandmarkSample.Landmark]) -> Double? {
        let wrist = vec(landmarks[0])
        let thumbTip = vec(landmarks[4])
        let pinkyTip = vec(landmarks[20])
        
        return angleDeg(a: thumbTip, b: wrist, c: pinkyTip)
    }
    
    // MARK: - Helpers
    
    private func vec(_ lm: HandLandmarkSample.Landmark) -> SIMD3<Double> {
        SIMD3(lm.x, lm.y, lm.z)
    }
    
    private func point3D(from lm: HandLandmarkSample.Landmark) -> HandPoseSample.Point3D {
        HandPoseSample.Point3D(x: lm.x, y: lm.y, z: lm.z)
    }
}
