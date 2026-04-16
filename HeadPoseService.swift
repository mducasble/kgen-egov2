import Foundation
import ARKit

/// Captures head pose from ARKit's ARWorldTrackingConfiguration.
///
/// Uses ARCamera.transform as head pose proxy (position + quaternion + tracking state).
/// Also forwards ARFrame pixel buffers to VideoCaptureService for recording,
/// since ARKit exclusively owns the camera when running.
///
/// PERFORMANCE: Uses a pre-allocated CVPixelBufferPool to copy ARKit's buffers
/// without per-frame memory allocation.
///
/// FRAME RATE: Explicitly selects a 30fps ARKit video format per spec.
/// ARKit defaults to 60fps on modern iPhones which wastes CPU/battery
/// and produces double the required data.
final class HeadPoseService: NSObject {
    struct TimingSample {
        let frameIndex: Int
        let timestampNs: Int64
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
    
    /// Pre-allocated buffer pool for fast pixel buffer copies
    private var pixelBufferPool: CVPixelBufferPool?
    
    /// The resolution and FPS of the selected ARKit video format
    private(set) var selectedWidth: Int = 1920
    private(set) var selectedHeight: Int = 1080
    private(set) var selectedFPS: Int = 30
    
    /// Last captured intrinsics from ARKit
    private(set) var lastIntrinsics: simd_float3x3?
    private(set) var lastResolution: CGSize?
    
    /// Called when intrinsics are first captured or change.
    var onIntrinsicsUpdate: ((simd_float3x3, CGSize) -> Void)?
    
    /// Called for each ARFrame with a COPY of the pixel buffer and timestamp.
    var onFrameReceived: ((_ pixelBuffer: CVPixelBuffer, _ timestamp: CMTime, _ timestampNs: Int64, _ frameIndex: Int) -> Void)?
    
    var totalSamples: Int { sampleCount }
    var isAvailable: Bool { ARWorldTrackingConfiguration.isSupported }
    
    /// Diagnostics
    private(set) var lastSessionError: Error?
    private(set) var wasInterrupted: Bool = false
    
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
        lastSessionError = nil
        wasInterrupted = false
        
        let session = ARSession()
        session.delegate = self
        
        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravity
        
        if #available(iOS 16.0, *) {
            // Select a format that is:
            //   1. >= 2MP (spec requirement)
            //   2. 30 FPS (NOT 60 — spec says 30)
            //   3. Closest to 1920x1080
            let targetPixels = 1920 * 1080
            let candidates = ARWorldTrackingConfiguration.supportedVideoFormats
                .filter { fmt in
                    let pixels = Int(fmt.imageResolution.width * fmt.imageResolution.height)
                    return pixels >= 2_000_000 && fmt.framesPerSecond == 30
                }
                .sorted {
                    let a = abs(Int($0.imageResolution.width * $0.imageResolution.height) - targetPixels)
                    let b = abs(Int($1.imageResolution.width * $1.imageResolution.height) - targetPixels)
                    return a < b
                }
            
            // If no 30fps format found, fall back to any format >= 2MP
            // and accept whatever FPS it has
            let fallbackCandidates = ARWorldTrackingConfiguration.supportedVideoFormats
                .filter { Int($0.imageResolution.width * $0.imageResolution.height) >= 2_000_000 }
                .sorted {
                    let a = abs(Int($0.imageResolution.width * $0.imageResolution.height) - targetPixels)
                    let b = abs(Int($1.imageResolution.width * $1.imageResolution.height) - targetPixels)
                    return a < b
                }
            
            if let bestFormat = candidates.first ?? fallbackCandidates.first {
                config.videoFormat = bestFormat
                selectedWidth = Int(bestFormat.imageResolution.width)
                selectedHeight = Int(bestFormat.imageResolution.height)
                selectedFPS = bestFormat.framesPerSecond
                print("[HeadPoseService] Format: \(selectedWidth)x\(selectedHeight) @ \(selectedFPS)fps")
            }
            
            // Log all available formats for debugging
            print("[HeadPoseService] Available formats:")
            for fmt in ARWorldTrackingConfiguration.supportedVideoFormats {
                let w = Int(fmt.imageResolution.width)
                let h = Int(fmt.imageResolution.height)
                let selected = (fmt.imageResolution == config.videoFormat.imageResolution && fmt.framesPerSecond == config.videoFormat.framesPerSecond) ? " ← SELECTED" : ""
                print("  \(w)x\(h) @ \(fmt.framesPerSecond)fps\(selected)")
            }
        }
        
        // Pre-allocate pixel buffer pool
        createPixelBufferPool(
            width: selectedWidth,
            height: selectedHeight,
            pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        )
        
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
        print("[HeadPoseService] Stopped. Total frames: \(sampleCount)")
    }
    
    // MARK: - Pixel Buffer Pool
    
    private func createPixelBufferPool(width: Int, height: Int, pixelFormat: OSType) {
        let poolAttrs: [String: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: 4
        ]
        let bufferAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        
        var pool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            poolAttrs as CFDictionary,
            bufferAttrs as CFDictionary,
            &pool
        )
        
        if status == kCVReturnSuccess {
            self.pixelBufferPool = pool
            print("[HeadPoseService] Buffer pool created (\(width)x\(height))")
        } else {
            print("[HeadPoseService] Buffer pool failed: \(status)")
        }
    }
    
    /// Fast pixel buffer copy using pre-allocated pool.
    private func copyPixelBuffer(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        
        var destination: CVPixelBuffer?
        if let pool = pixelBufferPool {
            let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &destination)
            if status != kCVReturnSuccess { destination = nil }
        }
        
        if destination == nil {
            let pf = CVPixelBufferGetPixelFormatType(source)
            CVPixelBufferCreate(kCFAllocatorDefault, width, height, pf, nil, &destination)
        }
        
        guard let dest = destination else { return nil }
        
        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(dest, [])
        defer {
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
            CVPixelBufferUnlockBaseAddress(dest, [])
        }
        
        let planeCount = CVPixelBufferGetPlaneCount(source)
        
        if planeCount > 0 {
            for plane in 0..<planeCount {
                guard let srcAddr = CVPixelBufferGetBaseAddressOfPlane(source, plane),
                      let dstAddr = CVPixelBufferGetBaseAddressOfPlane(dest, plane) else { continue }
                let srcBPR = CVPixelBufferGetBytesPerRowOfPlane(source, plane)
                let dstBPR = CVPixelBufferGetBytesPerRowOfPlane(dest, plane)
                let planeH = CVPixelBufferGetHeightOfPlane(source, plane)
                
                if srcBPR == dstBPR {
                    memcpy(dstAddr, srcAddr, srcBPR * planeH)
                } else {
                    let copyBPR = min(srcBPR, dstBPR)
                    for row in 0..<planeH {
                        memcpy(dstAddr.advanced(by: row * dstBPR),
                               srcAddr.advanced(by: row * srcBPR),
                               copyBPR)
                    }
                }
            }
        } else {
            guard let srcAddr = CVPixelBufferGetBaseAddress(source),
                  let dstAddr = CVPixelBufferGetBaseAddress(dest) else { return nil }
            let srcBPR = CVPixelBufferGetBytesPerRow(source)
            let dstBPR = CVPixelBufferGetBytesPerRow(dest)
            if srcBPR == dstBPR {
                memcpy(dstAddr, srcAddr, srcBPR * height)
            } else {
                let copyBPR = min(srcBPR, dstBPR)
                for row in 0..<height {
                    memcpy(dstAddr.advanced(by: row * dstBPR),
                           srcAddr.advanced(by: row * srcBPR),
                           copyBPR)
                }
            }
        }
        
        return dest
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
            print("[HeadPoseService] First AR frame")
        }
        
        let relativeMs = (arTimestamp - (firstARTimestamp ?? arTimestamp)) * 1000.0
        let epochMs = recordingStartEpochMs + relativeMs
        let timestampNs = Int64(DispatchTime.now().uptimeNanoseconds)
        let currentIndex = sampleCount
        sampleCount += 1
        
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
        case .normal: trackingState = "normal"
        case .limited(_): trackingState = "limited"
        case .notAvailable: trackingState = "notAvailable"
        }
        
        writer?.append(HeadPoseSample(
            timestampNs: timestampNs,
            timestampEpochMs: epochMs,
            relativeMs: relativeMs,
            frameIndex: currentIndex,
            positionMeters: position,
            rotationQuaternion: rotation,
            trackingState: trackingState
        ))
        timingSamples.append(TimingSample(
            frameIndex: currentIndex,
            timestampNs: timestampNs,
            timestampEpochMs: epochMs,
            relativeMs: relativeMs
        ))
        
        let intrinsics = frame.camera.intrinsics
        let resolution = frame.camera.imageResolution
        if lastIntrinsics == nil || lastResolution != resolution {
            lastIntrinsics = intrinsics
            lastResolution = resolution
            onIntrinsicsUpdate?(intrinsics, resolution)
        }
        
        guard let bufferCopy = copyPixelBuffer(frame.capturedImage) else {
            if currentIndex < 5 { print("[HeadPoseService] Copy failed frame \(currentIndex)") }
            return
        }
        
        let cmTimestamp = CMTime(seconds: arTimestamp, preferredTimescale: 600)
        onFrameReceived?(bufferCopy, cmTimestamp, timestampNs, currentIndex)
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        lastSessionError = error
        print("[HeadPoseService] ARSession FAILED: \(error.localizedDescription)")
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        wasInterrupted = true
        print("[HeadPoseService] ARSession INTERRUPTED")
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        print("[HeadPoseService] Interruption ended")
    }
}
