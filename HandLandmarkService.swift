import Foundation
import Vision
import CoreVideo

// MARK: - Protocol for swappable hand landmark backends

/// Abstraction layer allowing the hand landmark backend to be swapped
/// between Apple Vision, MediaPipe native wrapper, or other implementations.
protocol HandLandmarkBackend {
    /// Process a pixel buffer and return detected hands.
    func detectHands(in pixelBuffer: CVPixelBuffer) -> [HandLandmarkSample.DetectedHand]
    
    /// Human-readable name of the backend for metadata.
    var backendName: String { get }
    
    /// Whether this backend provides true 3D landmarks (metric depth).
    var provides3D: Bool { get }
}

// MARK: - Apple Vision Backend (Default)

/// Uses Apple's Vision framework VNDetectHumanHandPoseRequest.
/// Produces 21 landmarks per hand in normalized image coordinates.
/// z-values are relative depth from wrist — NOT metric 3D.
final class AppleVisionHandBackend: HandLandmarkBackend {
    let backendName = "apple_vision"
    let provides3D = false // Vision z-values are relative, not metric
    
    func detectHands(in pixelBuffer: CVPixelBuffer) -> [HandLandmarkSample.DetectedHand] {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 2
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        
        guard let results = request.results else { return [] }
        
        return results.compactMap { observation in
            convertObservation(observation)
        }
    }
    
    private func convertObservation(_ observation: VNHumanHandPoseObservation) -> HandLandmarkSample.DetectedHand? {
        // Determine handedness (chirality)
        let handedness: String
        switch observation.chirality {
        case .left: handedness = "left"
        case .right: handedness = "right"
        default: handedness = "unknown"
        }
        
        // Extract all 21 landmarks in MediaPipe order
        let landmarks = extractLandmarks(from: observation)
        guard !landmarks.isEmpty else { return nil }
        
        // Overall confidence from the observation
        let confidence = Double(observation.confidence)
        
        return HandLandmarkSample.DetectedHand(
            handedness: handedness,
            confidence: confidence,
            landmarks: landmarks
        )
    }
    
    /// Maps Apple Vision joint names to MediaPipe landmark indices.
    private func extractLandmarks(from observation: VNHumanHandPoseObservation) -> [HandLandmarkSample.Landmark] {
        // Mapping from MediaPipe index to Vision joint name
        let jointMapping: [(Int, VNHumanHandPoseObservation.JointName)] = [
            (0,  .wrist),
            (1,  .thumbCMC),
            (2,  .thumbMP),
            (3,  .thumbIP),
            (4,  .thumbTip),
            (5,  .indexMCP),
            (6,  .indexPIP),
            (7,  .indexDIP),
            (8,  .indexTip),
            (9,  .middleMCP),
            (10, .middlePIP),
            (11, .middleDIP),
            (12, .middleTip),
            (13, .ringMCP),
            (14, .ringPIP),
            (15, .ringDIP),
            (16, .ringTip),
            (17, .littleMCP),
            (18, .littlePIP),
            (19, .littleDIP),
            (20, .littleTip)
        ]
        
        var landmarks: [HandLandmarkSample.Landmark] = []
        
        for (id, jointName) in jointMapping {
            guard let point = try? observation.recognizedPoint(jointName) else { continue }
            
            // Vision coordinates: origin at bottom-left, normalized [0,1]
            // Convert to top-left origin to match image convention
            landmarks.append(HandLandmarkSample.Landmark(
                id: id,
                x: Double(point.location.x),
                y: 1.0 - Double(point.location.y), // flip Y to top-left origin
                z: 0.0 // Apple Vision does not provide metric 3D z
                // NOTE: We explicitly set z=0 because Vision's z is not reliable metric depth.
                // Do NOT fake 3D from 2D landmarks.
            ))
        }
        
        return landmarks
    }
}

// MARK: - Placeholder MediaPipe Backend

/// Placeholder for future MediaPipe iOS integration.
/// When MediaPipe iOS SDK is integrated, replace this with actual implementation.
/// See: https://developers.google.com/mediapipe/solutions/vision/hand_landmarker/ios
final class MediaPipeHandBackend: HandLandmarkBackend {
    let backendName = "mediapipe"
    let provides3D = true // MediaPipe provides relative 3D
    
    func detectHands(in pixelBuffer: CVPixelBuffer) -> [HandLandmarkSample.DetectedHand] {
        // TODO: Integrate MediaPipe iOS SDK
        // 1. Add MediaPipeTasksVision via SPM or CocoaPods
        // 2. Initialize HandLandmarker with model options
        // 3. Convert CVPixelBuffer to MPImage
        // 4. Call handLandmarker.detect(image:)
        // 5. Map results to our DetectedHand format
        return []
    }
}

// MARK: - Hand Landmark Service

/// Orchestrates hand landmark detection on video frames.
/// Writes results to hand_landmarks.jsonl.
final class HandLandmarkService {
    
    private let backend: HandLandmarkBackend
    private var writer: JSONLWriter?
    private var recordingStartEpochMs: Double = 0
    
    /// The latest detection result (for QC aggregation)
    private(set) var lastResult: HandLandmarkSample?
    
    init(backend: HandLandmarkBackend = AppleVisionHandBackend()) {
        self.backend = backend
    }
    
    var backendName: String { backend.backendName }
    var provides3D: Bool { backend.provides3D }
    
    func start(outputURL: URL, epochStartMs: Double) throws {
        writer = try JSONLWriter(fileURL: outputURL)
        recordingStartEpochMs = epochStartMs
    }
    
    /// Process a frame and write landmarks.
    func processFrame(pixelBuffer: CVPixelBuffer, frameIndex: Int, relativeMs: Double) {
        let epochMs = recordingStartEpochMs + relativeMs
        
        let hands = backend.detectHands(in: pixelBuffer)
        
        let sample = HandLandmarkSample(
            timestampEpochMs: epochMs,
            relativeMs: relativeMs,
            frameIndex: frameIndex,
            hands: hands
        )
        
        lastResult = sample
        writer?.append(sample)
    }
    
    func stop() {
        writer?.close()
    }
    
    var rowCount: Int { writer?.rowCount ?? 0 }
}
