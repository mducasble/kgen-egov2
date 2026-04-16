import Foundation
import AVFoundation
import UIKit
import CoreVideo

protocol VideoCaptureDelegate: AnyObject {
    func videoCaptureService(_ service: VideoCaptureService, didOutputPixelBuffer pixelBuffer: CVPixelBuffer, relativeMs: Double, timestampNs: UInt64, frameIndex: Int)
}

/// Captures video to H.264 MP4 via AVCaptureSession with monotonic timestamps.
/// Prefers ultra-wide camera when available, falls back to wide-angle.
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
    private(set) var usedUltraWide: Bool = false

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

    func setup() throws {
        let session = AVCaptureSession()
        session.sessionPreset = .high

        guard let selection = selectPreferredCamera(targetFPS: targetFPS) else {
            throw CaptureError.cameraNotAvailable
        }

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
        usedUltraWide = camera.deviceType == .builtInUltraWideCamera
        actualFovDeg = Double(selection.format.videoFieldOfView)
        fovSource = "avcapture_format"
        selectedFormatDescription = selection.formatDescription
        orientationLocked = true
        orientation = "landscape"

        let ranges = selection.format.videoSupportedFrameRateRanges
            .map { String(format: "%.1f-%.1f", $0.minFrameRate, $0.maxFrameRate) }
            .joined(separator: ", ")
        print("[VideoCaptureService] Selected camera: \(camera.deviceType.rawValue)")
        print("[VideoCaptureService] Ultra-wide: \(usedUltraWide)")
        print("[VideoCaptureService] FOV: \(String(format: "%.2f", Double(selection.format.videoFieldOfView)))°")
        print("[VideoCaptureService] Resolution: \(d.width)x\(d.height)")
        print("[VideoCaptureService] FPS ranges: \(ranges)")

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

    // MARK: - Frame Processing

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
        let frameNs = sourceTimestampNs ?? clock.nowNs()
        let relativeMs = clock.toRelativeMs(frameNs, from: startNs)
        let epochMs = clock.toEpochMs(frameNs)

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

    // MARK: - Asset Writer

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

    // MARK: - Camera Selection

    enum CaptureError: Error, LocalizedError {
        case cameraNotAvailable, cannotAddInput, cannotAddOutput, cannotAddWriterInput
        var errorDescription: String? {
            switch self {
            case .cameraNotAvailable: return "No suitable back camera available"
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
        let supportsTargetFPS: Bool
    }

    /// Select best camera: prefer ultra-wide, then wide-angle, then any back camera.
    private func selectPreferredCamera(targetFPS: Int) -> CameraFormatSelection? {
        if let uw = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back),
           let sel = bestFormat(on: uw, targetFPS: targetFPS) {
            return sel
        }
        if let wide = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let sel = bestFormat(on: wide, targetFPS: targetFPS) {
            return sel
        }
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInDualWideCamera, .builtInDualCamera, .builtInTripleCamera],
            mediaType: .video, position: .back
        )
        for device in discovery.devices {
            if let sel = bestFormat(on: device, targetFPS: targetFPS) { return sel }
        }
        return nil
    }

    private func bestFormat(on device: AVCaptureDevice, targetFPS: Int) -> CameraFormatSelection? {
        var best: AVCaptureDevice.Format?
        var bestFov: Float = -1
        var bestPixels: Int32 = -1

        for format in device.formats {
            let supportsFPS = format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= Double(targetFPS) }
            guard supportsFPS else { continue }
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let pixels = dims.width * dims.height
            guard pixels >= 1920 * 1080 else { continue }

            let fov = format.videoFieldOfView
            if fov > bestFov + 0.01 || (abs(fov - bestFov) < 0.01 && pixels > bestPixels) {
                best = format; bestFov = fov; bestPixels = pixels
            }
        }

        guard let best else { return nil }
        let dims = CMVideoFormatDescriptionGetDimensions(best.formatDescription)
        let desc = "\(device.deviceType.rawValue) \(dims.width)x\(dims.height) fov=\(String(format: "%.2f", Double(best.videoFieldOfView)))"
        return CameraFormatSelection(device: device, format: best, formatDescription: desc, supportsTargetFPS: true)
    }

    private func lensName(for deviceType: AVCaptureDevice.DeviceType) -> String {
        switch deviceType {
        case .builtInUltraWideCamera: return "builtInUltraWideCamera"
        case .builtInWideAngleCamera: return "builtInWideAngleCamera"
        case .builtInDualWideCamera: return "builtInDualWideCamera"
        case .builtInDualCamera: return "builtInDualCamera"
        case .builtInTripleCamera: return "builtInTripleCamera"
        case .builtInTelephotoCamera: return "builtInTelephotoCamera"
        default: return deviceType.rawValue
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
