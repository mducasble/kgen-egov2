import Foundation
import AVFoundation
import UIKit
import CoreVideo

protocol VideoCaptureDelegate: AnyObject {
    func videoCaptureService(_ service: VideoCaptureService, didOutputPixelBuffer pixelBuffer: CVPixelBuffer, relativeMs: Double, timestampNs: UInt64, frameIndex: Int)
}

/// Captures video to H.264 MP4 with monotonic timestamps.
final class VideoCaptureService: NSObject {
    let outputURL: URL
    let targetFPS: Int = 30
    private let targetBitrate: Int = 6_000_000
    private let gopLength: Int = 30
    private let clock = MonotonicClock.shared
    
    private var captureSession: AVCaptureSession?
    private var assetWriter: AVAssetWriter?
    private var assetWriterInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    
    private var isWriting = false
    private var writerSessionStarted = false
    private var sessionStartTime: CMTime?
    private var startNs: UInt64 = 0
    private var recordingStartEpochMs: Double = 0
    
    private let writerQueue = DispatchQueue(label: "com.egocapture.videowriter", qos: .userInteractive)
    
    private(set) var frameIndex: Int = 0
    private(set) var droppedFrames: Int = 0
    private(set) var backpressureEvents: Int = 0
    private(set) var videoTimestamps: [VideoTimestamp] = []
    private(set) var actualResolutionWidth: Int = 1920
    private(set) var actualResolutionHeight: Int = 1080
    private(set) var selectedLens: String = "unknown"
    private(set) var actualFovDeg: Double?
    private(set) var fovSource: String = "unknown"
    private(set) var selectedFormatDescription: String = "unknown"
    private(set) var orientationLocked: Bool = true
    private(set) var orientation: String = "landscape"
    
    // Interval stats
    private var previousFrameNs: UInt64?
    private var intervalSumMs: Double = 0
    private var intervalSquaredSumMs: Double = 0
    private var intervalCount: Int = 0
    
    var frameIntervalStdDevMs: Double {
        guard intervalCount > 1 else { return 0 }
        let mean = intervalSumMs / Double(intervalCount)
        let variance = (intervalSquaredSumMs / Double(intervalCount)) - (mean * mean)
        return variance > 0 ? sqrt(variance) : 0
    }
    
    weak var delegate: VideoCaptureDelegate?
    
    init(outputURL: URL) {
        self.outputURL = outputURL
        super.init()
    }
    
    func setupForARKit(
        width: Int = 1920,
        height: Int = 1080,
        pixelFormat: OSType = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        selectedLens: String = "arkit_back_camera",
        selectedFormatDescription: String = "ARKit selected format"
    ) {
        actualResolutionWidth = width
        actualResolutionHeight = height
        detectedPixelFormat = pixelFormat
        self.selectedLens = selectedLens
        actualFovDeg = nil
        fovSource = "unknown"
        self.selectedFormatDescription = selectedFormatDescription
        orientationLocked = true
        orientation = "landscape"
        do {
            try createAssetWriter(width: width, height: height)
        } catch {
            print("[VideoCaptureService] Pre-create failed: \(error)")
        }
    }
    
    func setupStandalone() throws {
        let session = AVCaptureSession()
        session.sessionPreset = .high
        guard let selection = selectWidestBackCameraFormat(targetFPS: targetFPS) else { throw CaptureError.cameraNotAvailable }
        let camera = selection.device
        try camera.lockForConfiguration()
        camera.activeFormat = selection.format
        let d = CMVideoFormatDescriptionGetDimensions(selection.format.formatDescription)
        actualResolutionWidth = Int(d.width)
        actualResolutionHeight = Int(d.height)
        camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
        camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
        camera.unlockForConfiguration()
        selectedLens = lensName(for: camera.deviceType)
        actualFovDeg = Double(selection.format.videoFieldOfView)
        fovSource = "avcapture_format"
        selectedFormatDescription = selection.formatDescription
        orientationLocked = true
        orientation = "landscape"

        let ranges = selection.format.videoSupportedFrameRateRanges
            .map { String(format: "%.1f-%.1f", $0.minFrameRate, $0.maxFrameRate) }
            .joined(separator: ", ")
        print("[VideoCaptureService] Available camera device types: \(selection.availableDeviceTypes.joined(separator: ", "))")
        print("[VideoCaptureService] Selected camera device: \(camera.deviceType.rawValue)")
        print("[VideoCaptureService] Selected format FOV: \(String(format: "%.2f", Double(selection.format.videoFieldOfView)))")
        print("[VideoCaptureService] Selected format resolution: \(d.width)x\(d.height)")
        print("[VideoCaptureService] Selected format supports 30 FPS: \(selection.supportsTargetFPS)")
        print("[VideoCaptureService] Selected format FPS ranges: \(ranges)")

        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else { throw CaptureError.cannotAddInput }
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = false
        output.setSampleBufferDelegate(self, queue: writerQueue)
        guard session.canAddOutput(output) else { throw CaptureError.cannotAddOutput }
        session.addOutput(output)
        if let c = output.connection(with: .video) {
            if c.isVideoRotationAngleSupported(0) {
                c.videoRotationAngle = 0
            } else if c.isVideoOrientationSupported {
                c.videoOrientation = .landscapeRight
            }
        }
        self.captureSession = session
        detectedPixelFormat = kCVPixelFormatType_32BGRA
        try createAssetWriter(width: actualResolutionWidth, height: actualResolutionHeight)
    }
    
    func startRecording(epochStartMs: Double) throws {
        try? FileManager.default.removeItem(at: outputURL)
        recordingStartEpochMs = epochStartMs
        startNs = clock.nowNs()
        frameIndex = 0; droppedFrames = 0; backpressureEvents = 0
        videoTimestamps = []; sessionStartTime = nil; writerSessionStarted = false
        previousFrameNs = nil; intervalSumMs = 0; intervalSquaredSumMs = 0; intervalCount = 0
        if assetWriter == nil || assetWriter?.status == .unknown {
            do { try createAssetWriter(width: actualResolutionWidth, height: actualResolutionHeight) } catch {}
        }
        isWriting = true
        captureSession?.startRunning()
    }
    
    func writePixelBuffer(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime, sourceTimestampNs: UInt64? = nil) {
        guard isWriting else { return }
        writerQueue.async { [weak self] in self?.processPixelBuffer(pixelBuffer, timestamp: timestamp, sourceTimestampNs: sourceTimestampNs) }
    }
    
    func stopRecording() async -> URL {
        isWriting = false
        captureSession?.stopRunning()
        return await withCheckedContinuation { continuation in
            writerQueue.async { [weak self] in
                guard let self = self, let w = self.assetWriter else {
                    continuation.resume(returning: self?.outputURL ?? URL(fileURLWithPath: "/")); return
                }
                self.assetWriterInput?.markAsFinished()
                w.finishWriting { continuation.resume(returning: self.outputURL) }
            }
        }
    }
    
    private func processPixelBuffer(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime, sourceTimestampNs: UInt64? = nil) {
        guard let writer = assetWriter else { droppedFrames += 1; return }
        if !writerSessionStarted {
            sessionStartTime = timestamp
            if writer.status == .unknown { writer.startWriting() }
            if writer.status == .writing { writer.startSession(atSourceTime: timestamp); writerSessionStarted = true }
            else { droppedFrames += 1; return }
        }
        if writer.status != .writing { droppedFrames += 1; return }
        
        let idx = frameIndex; frameIndex += 1
        
        // Monotonic timestamp
        let frameNs = sourceTimestampNs ?? clock.nowNs()
        let relativeMs = clock.toRelativeMs(frameNs, from: startNs)
        let epochMs = clock.toEpochMs(frameNs)
        
        // Interval stats (exclude gaps for stddev)
        if let prevNs = previousFrameNs {
            let ivMs = clock.toRelativeMs(frameNs, from: prevNs)
            if ivMs > 0 && ivMs < 100 {
                intervalSumMs += ivMs; intervalSquaredSumMs += ivMs * ivMs; intervalCount += 1
            }
        }
        previousFrameNs = frameNs
        
        videoTimestamps.append(VideoTimestamp(
            frameIndex: idx, timestampEpochMs: epochMs, relativeMs: relativeMs,
            timestampNs: frameNs, clock: "mach_absolute_time",
            presentationTimeSec: CMTimeGetSeconds(timestamp), isEstimated: false
        ))
        
        if let adaptor = pixelBufferAdaptor, adaptor.assetWriterInput.isReadyForMoreMediaData {
            if !adaptor.append(pixelBuffer, withPresentationTime: timestamp) { droppedFrames += 1 }
        } else {
            droppedFrames += 1; backpressureEvents += 1
        }
        
        delegate?.videoCaptureService(self, didOutputPixelBuffer: pixelBuffer, relativeMs: relativeMs, timestampNs: frameNs, frameIndex: idx)
    }
    
    private var detectedPixelFormat: OSType = kCVPixelFormatType_32BGRA
    
    private func createAssetWriter(width: Int, height: Int) throws {
        assetWriter = nil; assetWriterInput = nil; pixelBufferAdaptor = nil
        try? FileManager.default.removeItem(at: outputURL)
        let w = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: targetBitrate, AVVideoMaxKeyFrameIntervalKey: gopLength, AVVideoAllowFrameReorderingKey: false]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        input.transform = CGAffineTransform.identity
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: detectedPixelFormat, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height
        ])
        guard w.canAdd(input) else { throw CaptureError.cannotAddWriterInput }
        w.add(input)
        assetWriter = w; assetWriterInput = input; pixelBufferAdaptor = adaptor
    }
    
    enum CaptureError: Error, LocalizedError {
        case cameraNotAvailable, cannotAddInput, cannotAddOutput, cannotAddWriterInput
        var errorDescription: String? {
            switch self {
            case .cameraNotAvailable: return "Back camera not available"
            case .cannotAddInput: return "Cannot add camera input"
            case .cannotAddOutput: return "Cannot add video output"
            case .cannotAddWriterInput: return "Cannot add writer input"
            }
        }
    }

    private struct CameraFormatSelection {
        let device: AVCaptureDevice
        let format: AVCaptureDevice.Format
        let formatDescription: String
        let availableDeviceTypes: [String]
        let supportsTargetFPS: Bool
    }

    private func selectWidestBackCameraFormat(targetFPS: Int) -> CameraFormatSelection? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInWideAngleCamera,
                .builtInDualWideCamera,
                .builtInDualCamera,
                .builtInTripleCamera,
                .builtInTelephotoCamera
            ],
            mediaType: .video,
            position: .back
        )

        let availableTypes = discovery.devices.map { $0.deviceType.rawValue }
        for device in discovery.devices {
            if let selection = bestFormat(on: device, targetFPS: targetFPS, availableDeviceTypes: availableTypes) {
                return selection
            }
        }
        return nil
    }

    private func bestFormat(
        on device: AVCaptureDevice,
        targetFPS: Int,
        availableDeviceTypes: [String]
    ) -> CameraFormatSelection? {
        var bestFormat: AVCaptureDevice.Format?
        var bestFov: Float = -1
        var bestPixels: Int32 = -1
        var bestSupportsTargetFPS = false

        for format in device.formats {
            let supportsFPS = format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= Double(targetFPS) }
            guard supportsFPS else { continue }
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let pixels = dims.width * dims.height
            guard pixels >= 1920 * 1080 else { continue }

            let fov = format.videoFieldOfView
            let improvesFov = fov > bestFov + 0.01
            let tiesFovHigherRes = abs(fov - bestFov) < 0.01 && pixels > bestPixels
            if improvesFov || tiesFovHigherRes {
                bestFormat = format
                bestFov = fov
                bestPixels = pixels
                bestSupportsTargetFPS = supportsFPS
            }
        }

        guard let bestFormat else { return nil }
        let dims = CMVideoFormatDescriptionGetDimensions(bestFormat.formatDescription)
        let description = "\(device.deviceType.rawValue) \(dims.width)x\(dims.height) fov=\(String(format: "%.2f", Double(bestFormat.videoFieldOfView)))"
        return CameraFormatSelection(
            device: device,
            format: bestFormat,
            formatDescription: description,
            availableDeviceTypes: availableDeviceTypes,
            supportsTargetFPS: bestSupportsTargetFPS
        )
    }

    private func lensName(for deviceType: AVCaptureDevice.DeviceType) -> String {
        switch deviceType {
        case .builtInDualWideCamera:
            return "builtInDualWideCamera"
        case .builtInWideAngleCamera:
            return "builtInWideAngleCamera"
        case .builtInDualCamera:
            return "builtInDualCamera"
        case .builtInTripleCamera:
            return "builtInTripleCamera"
        case .builtInTelephotoCamera:
            return "builtInTelephotoCamera"
        default:
            return deviceType.rawValue
        }
    }
}

extension VideoCaptureService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        processPixelBuffer(pb, timestamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    }
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) { droppedFrames += 1 }
}
