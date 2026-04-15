import Foundation
import AVFoundation
import UIKit
import CoreVideo

/// Delegate for receiving per-frame pixel buffers for vision processing.
protocol VideoCaptureDelegate: AnyObject {
    func videoCaptureService(
        _ service: VideoCaptureService,
        didOutputPixelBuffer pixelBuffer: CVPixelBuffer,
        relativeMs: Double,
        frameIndex: Int
    )
}

/// Captures video to H.264 MP4.
///
/// Supports two modes:
///
/// **ARKit mode** (`setupForARKit`):
///   ARKit owns the camera. HeadPoseService calls `writePixelBuffer(_:timestamp:)`
///   for each ARFrame. This avoids two camera sessions fighting for the sensor.
///
/// **Standalone mode** (`setupStandalone`):
///   VideoCaptureService runs its own AVCaptureSession. Used when ARKit is unavailable.
///
/// In both modes, video is written via AVAssetWriter and per-frame timestamps
/// are recorded from actual CMTime presentation times (not estimated).
final class VideoCaptureService: NSObject {
    
    // MARK: - Configuration
    
    let outputURL: URL
    let targetFPS: Int = 30
    private let targetBitrate: Int = 6_000_000  // 6 Mbps (spec: 4-9 Mbps)
    private let gopLength: Int = 30              // spec requirement
    
    // MARK: - State
    
    private var captureSession: AVCaptureSession?  // only used in standalone mode
    private var assetWriter: AVAssetWriter?
    private var assetWriterInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    
    private var isWriting = false
    private var sessionStartTime: CMTime?
    private var recordingStartEpochMs: Double = 0
    
    private let writerQueue = DispatchQueue(label: "com.egocapture.videowriter", qos: .userInteractive)
    
    private(set) var frameIndex: Int = 0
    private(set) var droppedFrames: Int = 0
    private(set) var videoTimestamps: [VideoTimestamp] = []
    private(set) var actualResolutionWidth: Int = 1920
    private(set) var actualResolutionHeight: Int = 1080
    
    weak var delegate: VideoCaptureDelegate?
    
    init(outputURL: URL) {
        self.outputURL = outputURL
        super.init()
    }
    
    // MARK: - ARKit Mode Setup
    
    /// Configure for receiving pixel buffers from ARKit (no AVCaptureSession needed).
    func setupForARKit() {
        // No capture session — ARKit provides the camera feed.
        // Resolution is determined from first received pixel buffer.
    }
    
    // MARK: - Standalone Mode Setup
    
    /// Configure with own AVCaptureSession (when ARKit is not available).
    func setupStandalone() throws {
        let session = AVCaptureSession()
        session.sessionPreset = .high
        
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CaptureError.cameraNotAvailable
        }
        
        // Configure for 30 FPS with best format >= 2MP
        try camera.lockForConfiguration()
        
        if let bestFormat = camera.formats.filter({ format in
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let pixels = Int(dims.width) * Int(dims.height)
            let has30fps = format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 30 }
            return pixels >= 2_000_000 && has30fps
        }).first {
            camera.activeFormat = bestFormat
            let dims = CMVideoFormatDescriptionGetDimensions(bestFormat.formatDescription)
            actualResolutionWidth = Int(dims.width)
            actualResolutionHeight = Int(dims.height)
        }
        
        camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
        camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
        camera.unlockForConfiguration()
        
        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else { throw CaptureError.cannotAddInput }
        session.addInput(input)
        
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = false
        output.setSampleBufferDelegate(self, queue: writerQueue)
        
        guard session.canAddOutput(output) else { throw CaptureError.cannotAddOutput }
        session.addOutput(output)
        
        // Landscape orientation
        if let connection = output.connection(with: .video),
           connection.isVideoRotationAngleSupported(0) {
            connection.videoRotationAngle = 0
        }
        
        self.captureSession = session
    }
    
    // MARK: - Recording
    
    func startRecording(epochStartMs: Double) throws {
        try? FileManager.default.removeItem(at: outputURL)
        
        recordingStartEpochMs = epochStartMs
        frameIndex = 0
        droppedFrames = 0
        videoTimestamps = []
        sessionStartTime = nil
        
        // Asset writer created lazily on first frame (need resolution)
        isWriting = true
        
        // Start standalone capture session if present
        captureSession?.startRunning()
    }
    
    /// Called by HeadPoseService in ARKit mode to feed pixel buffers.
    func writePixelBuffer(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        guard isWriting else { return }
        
        writerQueue.async { [weak self] in
            self?.processPixelBuffer(pixelBuffer, timestamp: timestamp)
        }
    }
    
    func stopRecording() async -> URL {
        isWriting = false
        captureSession?.stopRunning()
        
        return await withCheckedContinuation { continuation in
            writerQueue.async { [weak self] in
                guard let self = self, let writer = self.assetWriter else {
                    continuation.resume(returning: self?.outputURL ?? URL(fileURLWithPath: "/"))
                    return
                }
                self.assetWriterInput?.markAsFinished()
                writer.finishWriting {
                    continuation.resume(returning: self.outputURL)
                }
            }
        }
    }
    
    // MARK: - Internal Frame Processing
    
    private func processPixelBuffer(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        // Lazily create asset writer on first frame
        if assetWriter == nil {
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            actualResolutionWidth = width
            actualResolutionHeight = height
            detectedPixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
            
            do {
                try createAssetWriter(width: width, height: height)
            } catch {
                print("[VideoCaptureService] Asset writer creation failed: \(error)")
                return
            }
        }
        
        // Initialize session on first frame
        if sessionStartTime == nil {
            sessionStartTime = timestamp
            assetWriter?.startWriting()
            assetWriter?.startSession(atSourceTime: timestamp)
        }
        
        let currentIndex = frameIndex
        frameIndex += 1
        
        // Compute timestamps
        let relativeSec = CMTimeGetSeconds(timestamp) - CMTimeGetSeconds(sessionStartTime!)
        let relativeMs = relativeSec * 1000.0
        let epochMs = recordingStartEpochMs + relativeMs
        
        // Record timestamp (from actual CMTime, not estimated)
        videoTimestamps.append(VideoTimestamp(
            frameIndex: currentIndex,
            timestampEpochMs: epochMs,
            relativeMs: relativeMs,
            presentationTimeSec: CMTimeGetSeconds(timestamp),
            isEstimated: false
        ))
        
        // Write frame to MP4
        if let adaptor = pixelBufferAdaptor, adaptor.assetWriterInput.isReadyForMoreMediaData {
            adaptor.append(pixelBuffer, withPresentationTime: timestamp)
        } else {
            droppedFrames += 1
        }
        
        // Forward to vision pipeline
        delegate?.videoCaptureService(
            self,
            didOutputPixelBuffer: pixelBuffer,
            relativeMs: relativeMs,
            frameIndex: currentIndex
        )
    }
    
    private var detectedPixelFormat: OSType = kCVPixelFormatType_32BGRA
    
    private func createAssetWriter(width: Int, height: Int) throws {
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: targetBitrate,
                AVVideoMaxKeyFrameIntervalKey: gopLength,
                AVVideoAllowFrameReorderingKey: false  // No B-frames
            ]
        ]
        
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = true
        
        // Use the actual pixel format from the source (BGRA from standalone, 420v from ARKit)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: detectedPixelFormat,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )
        
        guard writer.canAdd(writerInput) else { throw CaptureError.cannotAddWriterInput }
        writer.add(writerInput)
        
        self.assetWriter = writer
        self.assetWriterInput = writerInput
        self.pixelBufferAdaptor = adaptor
    }
    
    // MARK: - Errors
    
    enum CaptureError: Error, LocalizedError {
        case cameraNotAvailable
        case cannotAddInput
        case cannotAddOutput
        case cannotAddWriterInput
        
        var errorDescription: String? {
            switch self {
            case .cameraNotAvailable: return "Back camera not available"
            case .cannotAddInput: return "Cannot add camera input to capture session"
            case .cannotAddOutput: return "Cannot add video output to capture session"
            case .cannotAddWriterInput: return "Cannot add input to asset writer"
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate (Standalone mode)

extension VideoCaptureService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        processPixelBuffer(pixelBuffer, timestamp: timestamp)
    }
    
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        droppedFrames += 1
    }
}
