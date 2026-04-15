import Foundation
import Vision
import CoreVideo

/// Detects face presence in frames for privacy/QC purposes.
/// Uses Apple Vision's VNDetectFaceRectanglesRequest.
final class FacePresenceService {
    
    private var writer: JSONLWriter?
    private var recordingStartEpochMs: Double = 0
    
    /// Latest result for QC aggregation
    private(set) var lastFaceDetected: Bool = false
    private(set) var lastConfidence: Double? = nil
    
    func start(outputURL: URL, epochStartMs: Double) throws {
        writer = try JSONLWriter(fileURL: outputURL)
        recordingStartEpochMs = epochStartMs
    }
    
    /// Process a frame for face detection.
    func processFrame(pixelBuffer: CVPixelBuffer, frameIndex: Int, relativeMs: Double) {
        let epochMs = recordingStartEpochMs + relativeMs
        
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        
        var faceDetected = false
        var confidence: Double? = nil
        
        do {
            try handler.perform([request])
            if let results = request.results, !results.isEmpty {
                faceDetected = true
                confidence = Double(results.first?.confidence ?? 0)
            }
        } catch {
            // Detection failed — report no face
        }
        
        lastFaceDetected = faceDetected
        lastConfidence = confidence
        
        let sample = FacePresenceSample(
            timestampEpochMs: epochMs,
            relativeMs: relativeMs,
            frameIndex: frameIndex,
            faceDetected: faceDetected,
            confidence: confidence
        )
        
        writer?.append(sample)
    }
    
    func stop() {
        writer?.close()
    }
    
    var rowCount: Int { writer?.rowCount ?? 0 }
}
