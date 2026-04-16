import Foundation
import AVFoundation
import UIKit
import CoreVideo

protocol VideoCaptureDelegate: AnyObject {
    func videoCaptureService(_ service: VideoCaptureService, didOutputPixelBuffer pixelBuffer: CVPixelBuffer, relativeMs: Double, timestampNs: UInt64, frameIndex: Int)
}

/// Captures video to H.264 MP4 via AVCaptureSession with monotonic timestamps.
/// Context Mode: FOV-first selection — maximizes field of view, accepts lower
/// resolution to avoid cropped formats that reduce the sensor's native FOV.
final class VideoCaptureService: NSObject {
    let outputURL: URL
    let targetFPS: Int = 30
    private let targetBitrate: Int = 6_000_000
    private let gopLength: Int = 30
    private let clock = MonotonicClock.shared

    private var captureSession: AVCaptureSession?
    private var captureDevice: AVCaptureDevice?
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
    private(set) var fovMode: String = "hardware"
    private(set) var fovTargetAchieved: Bool = false
    private(set) var diagonalFovDeg: Double?
    private(set) var deviceMaxFov: Double?
    private(set) var formatDiagnostics: [[String: Any]] = []
    private(set) var selectedFormatDescription: String = "unknown"
    private(set) var orientationLocked: Bool = true
    private(set) var orientation: String = "landscape"
    private(set) var usedUltraWide: Bool = false
    private(set) var exposurePolicy: String = "default"

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
        session.sessionPreset = .inputPriority

        guard let selection = selectMaxFovCamera(targetFPS: targetFPS) else {
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

        applyLowBlurExposure(camera)
        camera.unlockForConfiguration()
        captureDevice = camera

        selectedLens = lensName(for: camera.deviceType)
        let hFov = Double(selection.format.videoFieldOfView)
        usedUltraWide = camera.deviceType == .builtInUltraWideCamera || hFov > 100
        actualFovDeg = hFov
        let dFov = Self.computeDiagonalFov(horizontalDeg: hFov, width: Int(d.width), height: Int(d.height))
        diagonalFovDeg = dFov
        fovSource = "avcapture_format"
        fovMode = "hardware"
        fovTargetAchieved = dFov >= 120 || hFov >= 120
        selectedFormatDescription = selection.formatDescription
        orientationLocked = true
        orientation = "landscape"

        // Full format dump (for diagnostics)
        formatDiagnostics = Self.dumpAllFormats(device: camera, targetFPS: targetFPS)
        deviceMaxFov = formatDiagnostics.compactMap { $0["horizontalFovDeg"] as? Double }.max()

        let fovStatus = fovTargetAchieved ? "TARGET ACHIEVED" : (hFov >= 105 ? "STABLE" : "BELOW TARGET")
        print("[VideoCaptureService] === FOV-First Selection ===")
        print("[VideoCaptureService] Device: \(camera.deviceType.rawValue)")
        print("[VideoCaptureService] Ultra-wide: \(usedUltraWide)")
        print("[VideoCaptureService] Horizontal FOV: \(String(format: "%.1f", hFov))°")
        print("[VideoCaptureService] Diagonal FOV:   \(String(format: "%.1f", dFov))°  [\(fovStatus)]")
        print("[VideoCaptureService] Device max horizontal FOV: \(String(format: "%.1f", deviceMaxFov ?? 0))°")
        print("[VideoCaptureService] Resolution: \(d.width)x\(d.height)")
        print("[VideoCaptureService] Exposure: \(exposurePolicy)")
        print("[VideoCaptureService] Total formats on device: \(camera.formats.count)")
        print("[VideoCaptureService] Formats dumped: \(formatDiagnostics.count)")
        if hFov < 110 {
            print("[VideoCaptureService] NOTE: ~106° horizontal = ~\(String(format: "%.0f", dFov))° diagonal. Apple reports 120° as diagonal FOV.")
        }

        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else { throw CaptureError.cannotAddInput }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
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

    private func applyLowBlurExposure(_ camera: AVCaptureDevice) {
        if camera.isExposureModeSupported(.continuousAutoExposure) {
            camera.exposureMode = .continuousAutoExposure
        }
        let maxDuration = CMTime(value: 1, timescale: 60)
        if camera.activeFormat.maxExposureDuration > maxDuration {
            camera.setExposureTargetBias(-0.5) { _ in }
            exposurePolicy = "bias_negative_0.5_maxdur_1_60"
        } else {
            exposurePolicy = "auto"
        }
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
    }

    /// FOV-first camera selection for Context Mode.
    ///
    /// Strategy:
    /// 1. Target the builtInUltraWideCamera specifically
    /// 2. Enumerate ALL its formats that support 30fps
    /// 3. Find the absolute maximum FOV across all formats
    /// 4. Among formats at that max FOV (±1°), prefer a stable resolution
    ///    (1920x1080 > 1280x720 > anything ≤ 1920x1080)
    /// 5. Fallback: if no ultra-wide device, scan all back cameras for max FOV
    private func selectMaxFovCamera(targetFPS: Int) -> CameraFormatSelection? {

        // Step 1: try dedicated ultra-wide device
        let uwDiscovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInUltraWideCamera],
            mediaType: .video, position: .back
        )

        if let uwDevice = uwDiscovery.devices.first {
            if let sel = selectMaxFovFormat(device: uwDevice, targetFPS: targetFPS, label: "ultra-wide") {
                return sel
            }
        }

        // Step 2: fallback — scan all back-facing cameras
        let allDiscovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInWideAngleCamera,
                .builtInDualWideCamera,
                .builtInTripleCamera,
                .builtInDualCamera
            ],
            mediaType: .video, position: .back
        )

        var bestSel: CameraFormatSelection?
        var bestFov: Float = -1
        for device in allDiscovery.devices {
            if let sel = selectMaxFovFormat(device: device, targetFPS: targetFPS, label: lensName(for: device.deviceType)) {
                let fov = sel.format.videoFieldOfView
                if fov > bestFov {
                    bestFov = fov
                    bestSel = sel
                }
            }
        }
        return bestSel
    }

    /// For a given device, find the format with the absolute highest FOV that
    /// supports the target FPS. Among tied-FOV formats, prefer a resolution
    /// that balances stability and clarity.
    private func selectMaxFovFormat(device: AVCaptureDevice, targetFPS: Int, label: String) -> CameraFormatSelection? {

        struct Candidate {
            let format: AVCaptureDevice.Format
            let fov: Float
            let w: Int32
            let h: Int32
            var pixels: Int32 { w * h }
        }

        let minPixels: Int32 = 1280 * 720

        var candidates: [Candidate] = []
        for format in device.formats {
            let ok = format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= Double(targetFPS) }
            guard ok else { continue }
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard dims.width * dims.height >= minPixels else { continue }
            candidates.append(Candidate(format: format, fov: format.videoFieldOfView, w: dims.width, h: dims.height))
        }

        guard !candidates.isEmpty else { return nil }

        let maxFov = candidates.map(\.fov).max()!

        // All formats within 1° of the absolute max FOV
        let topTier = candidates.filter { maxFov - $0.fov < 1.0 }

        print("[VideoCaptureService] [\(label)] \(candidates.count) formats, maxFov=\(String(format: "%.1f", maxFov))°, \(topTier.count) in top tier")
        for c in topTier.sorted(by: { $0.pixels < $1.pixels }) {
            print("[VideoCaptureService]   \(c.w)x\(c.h) fov=\(String(format: "%.1f", c.fov))°")
        }

        // Among top-tier, prefer a resolution that's stable for real-time processing.
        // Preference order: 1920x1080 > 1280x720 > smallest available ≤ 1920x1080 > smallest overall
        let preferredSizes: [(Int32, Int32)] = [(1920, 1080), (1280, 720)]
        for (pw, ph) in preferredSizes {
            if let match = topTier.first(where: { $0.w == pw && $0.h == ph }) {
                return makeSelection(device, match.format)
            }
        }

        let stableOptions = topTier.filter { $0.pixels <= 1920 * 1080 }
        if let best = stableOptions.max(by: { $0.pixels < $1.pixels }) {
            return makeSelection(device, best.format)
        }

        // All top-tier formats are high-res — pick the smallest to minimize load
        if let smallest = topTier.min(by: { $0.pixels < $1.pixels }) {
            return makeSelection(device, smallest.format)
        }
        return nil
    }

    private func makeSelection(_ device: AVCaptureDevice, _ format: AVCaptureDevice.Format) -> CameraFormatSelection {
        let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let fov = format.videoFieldOfView
        let desc = "\(device.deviceType.rawValue) \(dims.width)x\(dims.height) fov=\(String(format: "%.1f", Double(fov)))°"
        return CameraFormatSelection(device: device, format: format, formatDescription: desc)
    }

    // MARK: - FOV Helpers

    /// Compute diagonal FOV from horizontal FOV and aspect ratio.
    /// Ultra-wide lenses are not perfectly rectilinear, so this is an approximation.
    static func computeDiagonalFov(horizontalDeg: Double, width: Int, height: Int) -> Double {
        guard width > 0, height > 0, horizontalDeg > 0 else { return horizontalDeg }
        let hRad = horizontalDeg * .pi / 180.0
        let aspect = Double(height) / Double(width)
        let diag = 2.0 * atan(sqrt(1.0 + aspect * aspect) * tan(hRad / 2.0))
        return diag * 180.0 / .pi
    }

    /// Dump ALL formats on a device with no filtering — for diagnostics.
    static func dumpAllFormats(device: AVCaptureDevice, targetFPS: Int) -> [[String: Any]] {
        var results: [[String: Any]] = []
        for (i, format) in device.formats.enumerated() {
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let fov = format.videoFieldOfView
            let fpsRanges = format.videoSupportedFrameRateRanges
            let maxFPS = fpsRanges.map(\.maxFrameRate).max() ?? 0
            let minFPS = fpsRanges.map(\.minFrameRate).min() ?? 0
            let supports30 = fpsRanges.contains { $0.maxFrameRate >= Double(targetFPS) }
            let dFov = computeDiagonalFov(horizontalDeg: Double(fov), width: Int(dims.width), height: Int(dims.height))
            let mediaSubType = CMFormatDescriptionGetMediaSubType(format.formatDescription)
            let fourCC = String(format: "%c%c%c%c",
                                (mediaSubType >> 24) & 0xFF,
                                (mediaSubType >> 16) & 0xFF,
                                (mediaSubType >> 8) & 0xFF,
                                mediaSubType & 0xFF)

            let entry: [String: Any] = [
                "index": i,
                "width": Int(dims.width),
                "height": Int(dims.height),
                "horizontalFovDeg": Double(fov),
                "diagonalFovDeg": dFov,
                "minFPS": minFPS,
                "maxFPS": maxFPS,
                "supports30fps": supports30,
                "pixelFormat": fourCC,
                "isSelected": false
            ]
            results.append(entry)

            print("[FormatDump] #\(i) \(dims.width)x\(dims.height) hFOV=\(String(format: "%.1f", fov))° dFOV=\(String(format: "%.1f", dFov))° fps=\(String(format: "%.0f", minFPS))-\(String(format: "%.0f", maxFPS)) \(fourCC) \(supports30 ? "✓30" : "✗30")")
        }
        return results
    }

    /// Write format diagnostics to a JSON file in the session directory.
    func writeDiagnostics(to directory: URL) {
        guard !formatDiagnostics.isEmpty else { return }
        var diag = formatDiagnostics
        for i in diag.indices {
            if let w = diag[i]["width"] as? Int, let h = diag[i]["height"] as? Int,
               let fov = diag[i]["horizontalFovDeg"] as? Double,
               w == actualResolutionWidth && h == actualResolutionHeight && abs(fov - (actualFovDeg ?? 0)) < 0.1 {
                diag[i]["isSelected"] = true
            }
        }

        let report: [String: Any] = [
            "deviceType": selectedLens,
            "selectedFormat": [
                "width": actualResolutionWidth,
                "height": actualResolutionHeight,
                "horizontalFovDeg": actualFovDeg ?? 0,
                "diagonalFovDeg": diagonalFovDeg ?? 0,
                "fovMode": fovMode,
                "fovTargetAchieved": fovTargetAchieved,
                "deviceMaxHorizontalFov": deviceMaxFov ?? 0,
            ] as [String: Any],
            "allFormats": diag,
            "note": "videoFieldOfView reports horizontal FOV. Apple's '120° ultra-wide' spec is diagonal. ~106° horizontal ≈ ~120° diagonal at 16:9."
        ]

        let url = directory.appendingPathComponent("camera_format_diagnostics.json")
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url)
            print("[VideoCaptureService] Format diagnostics written to \(url.lastPathComponent)")
        }
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
