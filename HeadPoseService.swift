import Foundation
import ARKit

/// Captures head pose from ARKit's ARWorldTrackingConfiguration.
///
/// Uses ARCamera.transform as head pose proxy (position + quaternion + tracking state).
/// Also forwards ARFrame pixel buffers to VideoCaptureService for recording,
/// since ARKit exclusively owns the camera when running.
final class HeadPoseService: NSObject {
    struct TimingSample {
        let frameIndex: Int
        let timestampEpochMs: Double
        let relativeMs: Double
    }
    
    private var arSession: ARSession?
    private var writer: JSONLWriter?
    private var recordingStartEpochMs: Double = 0
    private var firstARTimestamp: TimeInterval?
    private var sampleCount: Int = 0
    private var isRecording = false
    private(set) var timingSamples: [TimingSample] = []
    
    /// Last captured intrinsics from ARKit
    private(set) var lastIntrinsics: simd_float3x3?
    private(set) var lastResolution: CGSize?
    
    /// Called when intrinsics are first captured or change.
    var onIntrinsicsUpdate: ((simd_float3x3, CGSize) -> Void)?
    
    /// Called for each ARFrame with the pixel buffer and timestamp.
    /// Wire this to VideoCaptureService.writePixelBuffer() for video recording.
    var onFrameReceived: ((_ pixelBuffer: CVPixelBuffer, _ timestamp: CMTime, _ frameIndex: Int) -> Void)?
    
    var totalSamples: Int { sampleCount }
    var isAvailable: Bool { ARWorldTrackingConfiguration.isSupported }
    
    // MARK: - Start / Stop
    
    func start(outputURL: URL, epochStartMs: Double) throws {
        guard ARWorldTrackingConfiguration.isSupported else {
            throw HeadPoseError.arNotSupported
        }
        
        writer = try JSONLWriter(fileURL: outputURL)
        recordingStartEpochMs = epochStartMs
        firstARTimestamp = nil
        sampleCount = 0
        isRecording = true
        timingSamples = []
        
        let session = ARSession()
        session.delegate = self
        
        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravity
        
        // Request highest resolution video format for better video quality
        if #available(iOS 16.0, *) {
            if let hiResFormat = ARWorldTrackingConfiguration.supportedVideoFormats
                .sorted(by: { $0.imageResolution.width * $0.imageResolution.height > $1.imageResolution.width * $1.imageResolution.height })
                .first {
                config.videoFormat = hiResFormat
            }
        }
        
        session.run(config)
        self.arSession = session
    }
    
    func stop() {
        isRecording = false
        arSession?.pause()
        arSession = nil
        writer?.close()
    }
    
    // MARK: - Errors
    
    enum HeadPoseError: Error, LocalizedError {
        case arNotSupported
        
        var errorDescription: String? {
            switch self {
            case .arNotSupported: return "ARKit world tracking is not supported on this device"
            }
        }
    }
}

// MARK: - ARSessionDelegate

extension HeadPoseService: ARSessionDelegate {
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard isRecording else { return }
        
        let arTimestamp = frame.timestamp
        
        if firstARTimestamp == nil {
            firstARTimestamp = arTimestamp
        }
        
        let relativeMs = (arTimestamp - (firstARTimestamp ?? arTimestamp)) * 1000.0
        let epochMs = recordingStartEpochMs + relativeMs
        let currentIndex = sampleCount
        
        // Extract head pose from camera transform
        let transform = frame.camera.transform
        
        let position = HeadPoseSample.Position(
            x: Double(transform.columns.3.x),
            y: Double(transform.columns.3.y),
            z: Double(transform.columns.3.z)
        )
        
        let quat = simd_quatf(transform)
        let rotation = HeadPoseSample.Quaternion(
            x: Double(quat.imag.x),
            y: Double(quat.imag.y),
            z: Double(quat.imag.z),
            w: Double(quat.real)
        )
        
        let trackingState: String
        switch frame.camera.trackingState {
        case .normal:
            trackingState = "normal"
        case .limited(_):
            trackingState = "limited"
        case .notAvailable:
            trackingState = "notAvailable"
        }
        
        let sample = HeadPoseSample(
            timestampEpochMs: epochMs,
            relativeMs: relativeMs,
            frameIndex: currentIndex,
            positionMeters: position,
            rotationQuaternion: rotation,
            trackingState: trackingState
        )
        
        writer?.append(sample)
        timingSamples.append(TimingSample(
            frameIndex: currentIndex,
            timestampEpochMs: epochMs,
            relativeMs: relativeMs
        ))
        
        // Update intrinsics on first frame or resolution change
        let intrinsics = frame.camera.intrinsics
        let resolution = frame.camera.imageResolution
        if lastIntrinsics == nil || lastResolution != resolution {
            lastIntrinsics = intrinsics
            lastResolution = resolution
            onIntrinsicsUpdate?(intrinsics, resolution)
        }
        
        // Forward pixel buffer to video capture service.
        // ARFrame.capturedImage is a CVPixelBuffer in YCbCr (420v) format.
        // The asset writer will handle colorspace conversion.
        let pixelBuffer = frame.capturedImage
        let cmTimestamp = CMTime(seconds: arTimestamp, preferredTimescale: 600)
        onFrameReceived?(pixelBuffer, cmTimestamp, currentIndex)
        
        sampleCount += 1
    }
}
