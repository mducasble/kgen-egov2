import Foundation
import ARKit

/// Captures head pose from ARKit's ARWorldTrackingConfiguration.
///
/// Uses ARCamera.transform as head pose proxy (position + quaternion + tracking state).
/// Also forwards ARFrame pixel buffers to VideoCaptureService for recording.
///
/// Timestamps use MonotonicClock (mach_absolute_time) shared across all sensors.
/// ARKit timestamps are boot-time based, which maps directly to mach_absolute_time.
final class HeadPoseService: NSObject {
    struct TimingSample {
        let frameIndex: Int
        let timestampEpochMs: Double
        let timestampNs: UInt64
        let relativeMs: Double
    }
    
    private let clock = MonotonicClock.shared
    
    private var arSession: ARSession?
    private var writer: JSONLWriter?
    private var startNs: UInt64 = 0
    private var sampleCount: Int = 0
    private var isRecording = false
    private(set) var timingSamples: [TimingSample] = []
    
    private var pixelBufferPool: CVPixelBufferPool?
    
    private(set) var selectedWidth: Int = 1920
    private(set) var selectedHeight: Int = 1080
    private(set) var selectedFPS: Int = 30
    
    private(set) var lastIntrinsics: simd_float3x3?
    private(set) var lastResolution: CGSize?
    
    /// Tracking loss counter (trackingState != .normal)
    private(set) var trackingLossFrames: Int = 0
    
    var onIntrinsicsUpdate: ((simd_float3x3, CGSize) -> Void)?
    var onFrameReceived: ((_ pixelBuffer: CVPixelBuffer, _ timestamp: CMTime, _ frameIndex: Int) -> Void)?
    
    var totalSamples: Int { sampleCount }
    var isAvailable: Bool { ARWorldTrackingConfiguration.isSupported }
    
    private(set) var lastSessionError: Error?
    private(set) var wasInterrupted: Bool = false
    
    // MARK: - Start / Stop
    
    func start(outputURL: URL, epochStartMs: Double) throws {
        guard ARWorldTrackingConfiguration.isSupported else {
            throw HeadPoseError.arNotSupported
        }
        
        writer = try JSONLWriter(fileURL: outputURL)
        startNs = clock.nowNs()
        sampleCount = 0
        isRecording = true
        timingSamples = []
        trackingLossFrames = 0
        lastSessionError = nil
        wasInterrupted = false
        
        let session = ARSession()
        session.delegate = self
        
        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravity
        
        if #available(iOS 16.0, *) {
            let targetPixels = 1920 * 1080
            let candidates = ARWorldTrackingConfiguration.supportedVideoFormats
                .filter { $0.imageResolution.width * $0.imageResolution.height >= 2_000_000 && $0.framesPerSecond == 30 }
                .sorted {
                    abs(Int($0.imageResolution.width * $0.imageResolution.height) - targetPixels) <
                    abs(Int($1.imageResolution.width * $1.imageResolution.height) - targetPixels)
                }
            
            let fallback = ARWorldTrackingConfiguration.supportedVideoFormats
                .filter { $0.imageResolution.width * $0.imageResolution.height >= 2_000_000 }
                .sorted {
                    abs(Int($0.imageResolution.width * $0.imageResolution.height) - targetPixels) <
                    abs(Int($1.imageResolution.width * $1.imageResolution.height) - targetPixels)
                }
            
            if let fmt = candidates.first ?? fallback.first {
                config.videoFormat = fmt
                selectedWidth = Int(fmt.imageResolution.width)
                selectedHeight = Int(fmt.imageResolution.height)
                selectedFPS = fmt.framesPerSecond
                print("[HeadPoseService] Format: \(selectedWidth)x\(selectedHeight) @ \(selectedFPS)fps")
            }
        }
        
        createPixelBufferPool(width: selectedWidth, height: selectedHeight,
                              pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
        
        session.run(config)
        self.arSession = session
        print("[HeadPoseService] ARSession started")
    }
    
    func stop() {
        isRecording = false
        arSession?.pause()
        arSession = nil
        writer?.close()
        pixelBufferPool = nil
        print("[HeadPoseService] Stopped. Frames: \(sampleCount), trackingLoss: \(trackingLossFrames)")
    }
    
    // MARK: - Pixel Buffer Pool
    
    private func createPixelBufferPool(width: Int, height: Int, pixelFormat: OSType) {
        let poolAttrs: [String: Any] = [kCVPixelBufferPoolMinimumBufferCountKey as String: 4]
        let bufAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        var pool: CVPixelBufferPool?
        if CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttrs as CFDictionary, bufAttrs as CFDictionary, &pool) == kCVReturnSuccess {
            self.pixelBufferPool = pool
        }
    }
    
    private func copyPixelBuffer(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        let w = CVPixelBufferGetWidth(source), h = CVPixelBufferGetHeight(source)
        var dest: CVPixelBuffer?
        if let pool = pixelBufferPool {
            if CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &dest) != kCVReturnSuccess { dest = nil }
        }
        if dest == nil {
            CVPixelBufferCreate(kCFAllocatorDefault, w, h, CVPixelBufferGetPixelFormatType(source), nil, &dest)
        }
        guard let d = dest else { return nil }
        
        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(d, [])
        defer { CVPixelBufferUnlockBaseAddress(source, .readOnly); CVPixelBufferUnlockBaseAddress(d, []) }
        
        let planes = CVPixelBufferGetPlaneCount(source)
        if planes > 0 {
            for p in 0..<planes {
                guard let s = CVPixelBufferGetBaseAddressOfPlane(source, p),
                      let dd = CVPixelBufferGetBaseAddressOfPlane(d, p) else { continue }
                let sBPR = CVPixelBufferGetBytesPerRowOfPlane(source, p)
                let dBPR = CVPixelBufferGetBytesPerRowOfPlane(d, p)
                let pH = CVPixelBufferGetHeightOfPlane(source, p)
                if sBPR == dBPR { memcpy(dd, s, sBPR * pH) }
                else { for r in 0..<pH { memcpy(dd.advanced(by: r*dBPR), s.advanced(by: r*sBPR), min(sBPR,dBPR)) } }
            }
        } else {
            guard let s = CVPixelBufferGetBaseAddress(source), let dd = CVPixelBufferGetBaseAddress(d) else { return nil }
            let sBPR = CVPixelBufferGetBytesPerRow(source), dBPR = CVPixelBufferGetBytesPerRow(d)
            if sBPR == dBPR { memcpy(dd, s, sBPR * h) }
            else { for r in 0..<h { memcpy(dd.advanced(by: r*dBPR), s.advanced(by: r*sBPR), min(sBPR,dBPR)) } }
        }
        return d
    }
    
    enum HeadPoseError: Error, LocalizedError {
        case arNotSupported
        var errorDescription: String? { "ARKit world tracking is not supported on this device" }
    }
}

// MARK: - ARSessionDelegate

extension HeadPoseService: ARSessionDelegate {
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard isRecording else { return }
        
        let sampleNs = clock.fromARKitTimestamp(frame.timestamp)
        let relativeMs = clock.toRelativeMs(sampleNs, from: startNs)
        let epochMs = clock.toEpochMs(sampleNs)
        let idx = sampleCount
        sampleCount += 1
        
        let t = frame.camera.transform
        let position = HeadPoseSample.Position(x: Double(t.columns.3.x), y: Double(t.columns.3.y), z: Double(t.columns.3.z))
        let q = simd_quatf(t)
        let rotation = HeadPoseSample.Quaternion(x: Double(q.imag.x), y: Double(q.imag.y), z: Double(q.imag.z), w: Double(q.real))
        
        let trackingState: String
        switch frame.camera.trackingState {
        case .normal: trackingState = "normal"
        case .limited(_): trackingState = "limited"; trackingLossFrames += 1
        case .notAvailable: trackingState = "notAvailable"; trackingLossFrames += 1
        }
        
        writer?.append(HeadPoseSample(
            timestampEpochMs: epochMs, relativeMs: relativeMs,
            timestampNs: sampleNs, clock: "mach_absolute_time",
            frameIndex: idx, positionMeters: position,
            rotationQuaternion: rotation, trackingState: trackingState
        ))
        timingSamples.append(TimingSample(frameIndex: idx, timestampEpochMs: epochMs, timestampNs: sampleNs, relativeMs: relativeMs))
        
        let intrinsics = frame.camera.intrinsics
        let resolution = frame.camera.imageResolution
        if lastIntrinsics == nil || lastResolution != resolution {
            lastIntrinsics = intrinsics; lastResolution = resolution
            onIntrinsicsUpdate?(intrinsics, resolution)
        }
        
        guard let copy = copyPixelBuffer(frame.capturedImage) else { return }
        onFrameReceived?(copy, CMTime(seconds: frame.timestamp, preferredTimescale: 600), idx)
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        lastSessionError = error
        print("[HeadPoseService] FAILED: \(error.localizedDescription)")
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        wasInterrupted = true
        print("[HeadPoseService] INTERRUPTED")
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        print("[HeadPoseService] Interruption ended")
    }
}
