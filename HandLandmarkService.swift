import Foundation
import Vision
import CoreVideo
import CoreImage
import UIKit
#if canImport(MediaPipeTasksVision)
import MediaPipeTasksVision
#endif

// MARK: - Protocol for swappable hand landmark backends

/// Abstraction layer allowing the hand landmark backend to be swapped
/// between Apple Vision, MediaPipe native wrapper, or other implementations.
protocol HandTrackingBackend {
    /// Process a pixel buffer and return detected hands.
    func detectHands(in pixelBuffer: CVPixelBuffer, timestampNs: UInt64) -> [HandLandmarkSample.DetectedHand]
    
    /// Human-readable name of the backend for metadata.
    var backendName: String { get }
    
    /// Whether this backend provides true 3D landmarks (metric depth).
    var provides3D: Bool { get }

    /// How to interpret landmark z output.
    var zType: String { get }
}

typealias HandLandmarkBackend = HandTrackingBackend

enum HandTrackingBackendType: String, CaseIterable, Codable {
    case appleVision
    case mediaPipe
    case both
}

// MARK: - Apple Vision Backend (Default)

/// Uses Apple's Vision framework VNDetectHumanHandPoseRequest.
/// Produces 21 landmarks per hand in normalized image coordinates.
/// z-values are relative depth from wrist — NOT metric 3D.
final class AppleVisionHandBackend: HandLandmarkBackend {
    let backendName = "apple_vision"
    let provides3D = false // Vision z-values are relative, not metric
    let zType = "placeholder_zero"
    
    func detectHands(in pixelBuffer: CVPixelBuffer, timestampNs: UInt64) -> [HandLandmarkSample.DetectedHand] {
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
            source: backendName,
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
    let provides3D = false // MediaPipe z is normalized depth, not metric
    let zType = "normalized"
    var onDebugInputFrame: ((UIImage) -> Void)?

    #if canImport(MediaPipeTasksVision)
    private var handLandmarker: HandLandmarker?
    private let queue = DispatchQueue(label: "com.egocapture.mediapipe.init")
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private var didWriteDebugInputFrame = false
    private var didRunStaticValidation = false
    #endif
    
    func detectHands(in pixelBuffer: CVPixelBuffer, timestampNs: UInt64) -> [HandLandmarkSample.DetectedHand] {
        #if canImport(MediaPipeTasksVision)
        if handLandmarker == nil {
            queue.sync {
                if handLandmarker == nil {
                    handLandmarker = buildHandLandmarker()
                    if handLandmarker != nil {
                        print("MediaPipe model loaded")
                    }
                }
            }
        }
        guard let handLandmarker else { return [] }
        let timestampMs = Int(timestampNs / 1_000_000)
        do {
            if !didRunStaticValidation {
                didRunStaticValidation = true
                runStaticValidationIfAvailable()
            }

            let rgbPixelBuffer = try convertToRGBPixelBuffer(pixelBuffer)
            writeDebugInputFrameIfNeeded(from: rgbPixelBuffer)
            let mpImage = try MPImage(pixelBuffer: rgbPixelBuffer, orientation: currentOrientationForBackCamera())
            let result = try handLandmarker.detect(videoFrame: mpImage, timestampInMilliseconds: timestampMs)
            print("MediaPipe inference success")
            let mapped = mapResult(result)
            print("Hands detected: \(mapped.count)")
            return mapped
        } catch {
            print("MediaPipe inference failed: \(error.localizedDescription)")
            return []
        }
        #else
        return []
        #endif
    }

    #if canImport(MediaPipeTasksVision)
    private func buildHandLandmarker() -> HandLandmarker? {
        do {
            let options = HandLandmarkerOptions()
            options.runningMode = .video
            options.numHands = 2
            options.minHandDetectionConfidence = 0.3
            options.minHandPresenceConfidence = 0.3
            options.minTrackingConfidence = 0.3
            options.baseOptions.modelAssetPath = resolveModelPath()
            return try HandLandmarker(options: options)
        } catch {
            print("MediaPipe model load failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func resolveModelPath() -> String {
        let configuredPath = UserDefaults.standard.string(forKey: "mediapipe_model_path") ?? "hand_landmarker.task"
        if configuredPath.hasPrefix("/") {
            return configuredPath
        }
        if let bundled = Bundle.main.path(forResource: "hand_landmarker", ofType: "task") {
            return bundled
        }
        return configuredPath
    }

    private func convertToRGBPixelBuffer(_ source: CVPixelBuffer) throws -> CVPixelBuffer {
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)

        var output: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &output
        )
        guard status == kCVReturnSuccess, let output else {
            throw NSError(domain: "MediaPipeHandBackend", code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "Failed to allocate RGB buffer"
            ])
        }

        let ciImage = CIImage(cvPixelBuffer: source).cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        ciContext.render(ciImage, to: output, bounds: ciImage.extent, colorSpace: CGColorSpaceCreateDeviceRGB())
        return output
    }

    private func currentOrientationForBackCamera() -> UIImage.Orientation {
        switch UIDevice.current.orientation {
        case .portrait:
            return .right
        case .portraitUpsideDown:
            return .left
        case .landscapeLeft:
            return .up
        case .landscapeRight:
            return .down
        default:
            return .right
        }
    }

    private func writeDebugInputFrameIfNeeded(from pixelBuffer: CVPixelBuffer) {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        let uiImage = UIImage(cgImage: cgImage)
        onDebugInputFrame?(uiImage)

        guard !didWriteDebugInputFrame else { return }
        guard let jpegData = uiImage.jpegData(compressionQuality: 0.85) else { return }

        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mediapipe_input_debug.jpg")
        do {
            try jpegData.write(to: outputURL, options: .atomic)
            didWriteDebugInputFrame = true
            print("MediaPipe input debug frame saved at \(outputURL.path)")
        } catch {
            print("MediaPipe input debug frame save failed: \(error.localizedDescription)")
        }
    }

    private func runStaticValidationIfAvailable() {
        guard let imagePath = Bundle.main.path(forResource: "mediapipe_static_hand", ofType: "jpg") ??
                              Bundle.main.path(forResource: "mediapipe_static_hand", ofType: "png"),
              let uiImage = UIImage(contentsOfFile: imagePath) else {
            print("MediaPipe static validation skipped: no mediapipe_static_hand image bundled")
            return
        }

        do {
            let options = HandLandmarkerOptions()
            options.runningMode = .image
            options.numHands = 2
            options.minHandDetectionConfidence = 0.3
            options.minHandPresenceConfidence = 0.3
            options.minTrackingConfidence = 0.3
            options.baseOptions.modelAssetPath = resolveModelPath()
            let imageLandmarker = try HandLandmarker(options: options)
            let mpImage = try MPImage(uiImage: uiImage, orientation: .up)
            let result = try imageLandmarker.detect(image: mpImage)
            let detected = min(result.landmarks.count, result.handedness.count)
            print("MediaPipe static validation hands detected: \(detected)")
        } catch {
            print("MediaPipe static validation failed: \(error.localizedDescription)")
        }
    }

    private func mapResult(_ result: HandLandmarkerResult) -> [HandLandmarkSample.DetectedHand] {
        var hands: [HandLandmarkSample.DetectedHand] = []
        let count = min(result.landmarks.count, result.handedness.count)
        for i in 0..<count {
            let handednessCategory = result.handedness[i].first
            let handednessRaw = handednessCategory?.categoryName?.lowercased() ?? "unknown"
            let handedness: String
            if handednessRaw.contains("left") {
                handedness = "left"
            } else if handednessRaw.contains("right") {
                handedness = "right"
            } else {
                handedness = "unknown"
            }
            let confidence = handednessCategory?.score ?? 0
            let landmarks: [HandLandmarkSample.Landmark] = result.landmarks[i].enumerated().map { idx, lm in
                HandLandmarkSample.Landmark(
                    id: idx,
                    x: Double(lm.x),
                    y: Double(lm.y),
                    z: Double(lm.z)
                )
            }
            hands.append(
                HandLandmarkSample.DetectedHand(
                    handedness: handedness,
                    confidence: Double(confidence),
                    source: backendName,
                    landmarks: landmarks
                )
            )
        }
        return hands
    }
    #endif
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
    private(set) var processedFrameCount: Int = 0
    private(set) var framesWithHands: Int = 0
    private(set) var totalHandsDetected: Int = 0
    private(set) var confidenceSamples: [Double] = []
    
    init(backend: HandLandmarkBackend = AppleVisionHandBackend()) {
        self.backend = backend
    }
    
    var backendName: String { backend.backendName }
    var provides3D: Bool { backend.provides3D }
    var zType: String { backend.zType }
    
    func start(outputURL: URL, epochStartMs: Double) throws {
        writer = try JSONLWriter(fileURL: outputURL)
        recordingStartEpochMs = epochStartMs
        processedFrameCount = 0
        framesWithHands = 0
        totalHandsDetected = 0
        confidenceSamples = []
    }
    
    /// Process a frame and write landmarks.
    func processFrame(pixelBuffer: CVPixelBuffer, frameIndex: Int, relativeMs: Double, timestampNs: UInt64) {
        let epochMs = recordingStartEpochMs + relativeMs
        
        let hands = backend.detectHands(in: pixelBuffer, timestampNs: timestampNs)
        processedFrameCount += 1
        if !hands.isEmpty { framesWithHands += 1 }
        totalHandsDetected += hands.count
        confidenceSamples.append(contentsOf: hands.map(\.confidence))
        
        let sample = HandLandmarkSample(
            timestampEpochMs: epochMs,
            relativeMs: relativeMs,
            timestampNs: timestampNs,
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
