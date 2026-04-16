import Foundation
import UIKit
import CoreVideo
import AVFoundation
import ARKit
import CoreImage

/// Pipeline version — increment on every significant change.
private let kPipelineVersion = "2.0.0"
private let kPipelineBuild = "phase1-production"

@MainActor
final class RecordingOrchestrator: ObservableObject {
    private struct HeadPoseVideoTimestampMapEntry: Codable {
        let frameIndex: Int
        let videoTimestampEpochMs: Double
        let videoTimestampNs: UInt64
        let headPoseTimestampEpochMs: Double
        let headPoseTimestampNs: UInt64
        let deltaMs: Double
    }
    
    @Published var isRecording = false
    @Published var recordingDurationSec: Double = 0
    @Published var currentSessionId: String?
    @Published var statusMessage: String = "Ready"
    @Published var frameCount: Int = 0
    @Published var imuSampleCount: Int = 0
    @Published var lastError: String?
    @Published var previewImage: UIImage?
    
    private var videoCaptureService: VideoCaptureService?
    private var imuCaptureService: IMUCaptureService?
    private var headPoseService: HeadPoseService?
    private let calibrationService = CameraCalibrationService()
    private var mountService = MountCalibrationService()
    private let packagingService = SessionPackagingService()
    
    private var handLandmarkService: HandLandmarkService?
    private var handPoseService: HandPoseDerivationService?
    private var facePresenceService: FacePresenceService?
    private var frameQCService: FrameQCService?
    
    private var sessionDir: URL?
    private var recordingStartEpochMs: Double = 0
    private var durationTimer: Timer?
    private var useARKit: Bool = false
    
    private let visionQueue = DispatchQueue(label: "com.egocapture.vision", qos: .userInitiated)
    private let visionStride = 3
    
    // MARK: - Recording Lifecycle
    
    func startRecording() {
        guard !isRecording else { return }
        statusMessage = "Checking permissions..."
        Task {
            let granted = await ensureCameraPermission()
            guard granted else { return }
            await MainActor.run { self.activateAudioSession() }
            await MainActor.run { self.statusMessage = "Preparing..." }
            try? await Task.sleep(nanoseconds: 500_000_000)
            await MainActor.run { self.startRecordingInternal() }
        }
    }

    private func startRecordingInternal() {
        lastError = nil; previewImage = nil; statusMessage = "Starting..."
        UIApplication.shared.isIdleTimerDisabled = true

        let session = SessionManager.shared.createSession()
        currentSessionId = session.id; sessionDir = session.directory
        recordingStartEpochMs = Date().timeIntervalSince1970 * 1000.0
        let dir = session.directory
        useARKit = ARWorldTrackingConfiguration.isSupported
        
        let ud = UserDefaults.standard
        mountService.updateConfig(
            mountType: ud.string(forKey: "mount_type") ?? "forehead",
            translationX: ud.double(forKey: "mount_tx"),
            translationY: ud.object(forKey: "mount_ty") != nil ? ud.double(forKey: "mount_ty") : 0.03,
            translationZ: ud.object(forKey: "mount_tz") != nil ? ud.double(forKey: "mount_tz") : 0.08,
            downwardTiltDeg: ud.object(forKey: "mount_tilt") != nil ? ud.double(forKey: "mount_tilt") : 30.0,
            notes: "Configured via Settings UI"
        )
        
        do {
            let imu = IMUCaptureService()
            try imu.start(outputURL: dir.appendingPathComponent("imu.jsonl"), epochStartMs: recordingStartEpochMs)
            imuCaptureService = imu
            
            let hl = HandLandmarkService(backend: AppleVisionHandBackend())
            try hl.start(outputURL: dir.appendingPathComponent("hand_landmarks.jsonl"), epochStartMs: recordingStartEpochMs)
            handLandmarkService = hl
            
            let hp = HandPoseDerivationService(has3DLandmarks: hl.provides3D)
            try hp.start(outputURL: dir.appendingPathComponent("hand_pose.jsonl"), epochStartMs: recordingStartEpochMs)
            handPoseService = hp
            
            let fp = FacePresenceService()
            try fp.start(outputURL: dir.appendingPathComponent("face_presence.jsonl"), epochStartMs: recordingStartEpochMs)
            facePresenceService = fp
            
            let qc = FrameQCService()
            try qc.start(outputURL: dir.appendingPathComponent("frame_qc_metrics.jsonl"), epochStartMs: recordingStartEpochMs)
            frameQCService = qc
            
            let video = VideoCaptureService(outputURL: dir.appendingPathComponent("video.mp4"))
            video.delegate = self; videoCaptureService = video
            
            if useARKit {
                let hps = HeadPoseService()
                try hps.start(outputURL: dir.appendingPathComponent("head_pose.jsonl"), epochStartMs: recordingStartEpochMs)
                video.setupForARKit(width: hps.selectedWidth, height: hps.selectedHeight, pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
                try video.startRecording(epochStartMs: recordingStartEpochMs)
                hps.onIntrinsicsUpdate = { [weak self] i, r in self?.calibrationService.extractFromARKit(intrinsics: i, resolution: r) }
                hps.onFrameReceived = { [weak video] pb, ts, _ in video?.writePixelBuffer(pb, timestamp: ts) }
                headPoseService = hps
            } else {
                try video.setupStandalone(); try video.startRecording(epochStartMs: recordingStartEpochMs)
            }
            
            isRecording = true; statusMessage = "Recording"
            durationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.recordingDurationSec = (Date().timeIntervalSince1970 * 1000.0 - self.recordingStartEpochMs) / 1000.0
                    self.imuSampleCount = self.imuCaptureService?.totalSamples ?? 0
                }
            }
        } catch {
            lastError = "Start failed: \(error.localizedDescription)"; statusMessage = "Error"; cleanup()
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        isRecording = false; statusMessage = "Finalizing..."
        durationTimer?.invalidate(); durationTimer = nil
        Task { await finalizeSession(); statusMessage = "Session saved" }
    }
    
    // MARK: - Audio Session
    
    private func activateAudioSession() {
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playAndRecord, mode: .videoRecording, options: [.mixWithOthers, .defaultToSpeaker])
            try s.setActive(true)
        } catch {}
    }
    
    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    
    // MARK: - Finalization
    
    private func finalizeSession() async {
        guard let dir = sessionDir, let sessionId = currentSessionId else { return }
        let ud = UserDefaults.standard
        UIApplication.shared.isIdleTimerDisabled = false
        deactivateAudioSession()
        
        headPoseService?.stop()
        _ = await videoCaptureService?.stopRecording()
        imuCaptureService?.stop()
        handLandmarkService?.stop(); handPoseService?.stop()
        facePresenceService?.stop(); frameQCService?.stop()
        
        let videoTimestamps = videoCaptureService?.videoTimestamps ?? []
        let headPoseSamples = headPoseService?.timingSamples ?? []
        
        // Write video timestamps
        if !videoTimestamps.isEmpty {
            do {
                let w = try JSONLWriter(fileURL: dir.appendingPathComponent("video_timestamps.jsonl"))
                for ts in videoTimestamps { w.append(ts) }
                w.close()
            } catch {}
        }
        
        // Write head_pose_video_map with simplified, consistent format (item 12)
        var mapDeltas: [Double] = []
        if useARKit && !headPoseSamples.isEmpty && !videoTimestamps.isEmpty {
            do {
                let w = try JSONLWriter(fileURL: dir.appendingPathComponent("head_pose_video_map.jsonl"))
                for sample in headPoseSamples {
                    let nearest = nearestVideoTimestamp(forNs: sample.timestampNs, in: videoTimestamps)
                    let deltaMs = abs(Double(Int64(nearest.timestampNs) - Int64(sample.timestampNs))) / 1_000_000.0
                    mapDeltas.append(deltaMs)
                    w.append(HeadPoseVideoTimestampMapEntry(
                        frameIndex: nearest.frameIndex,
                        videoTimestampEpochMs: nearest.timestampEpochMs,
                        videoTimestampNs: nearest.timestampNs,
                        headPoseTimestampEpochMs: sample.timestampEpochMs,
                        headPoseTimestampNs: sample.timestampNs,
                        deltaMs: deltaMs
                    ))
                }
                w.close()
            } catch {}
        }
        
        // Write calibration and mount
        do { try calibrationService.write(to: dir.appendingPathComponent("camera_calibration.json")) } catch {}
        do { try mountService.write(to: dir.appendingPathComponent("camera_mount.json")) } catch {}
        
        // Compute metrics
        let qcSummary = frameQCService?.computeSummary()
        let endEpochMs = Date().timeIntervalSince1970 * 1000.0
        let durationSec = (endEpochMs - recordingStartEpochMs) / 1000.0
        let totalFrames = videoCaptureService?.frameIndex ?? 0
        let droppedFrames = videoCaptureService?.droppedFrames ?? 0
        let resW = videoCaptureService?.actualResolutionWidth ?? 1920
        let resH = videoCaptureService?.actualResolutionHeight ?? 1080
        let avgFPS = computeEffectiveFPS(from: videoTimestamps)
        
        // Sync metrics (item 3)
        let syncMetrics = SessionMetadata.SyncMetrics(
            videoToHeadPoseAvgDeltaMs: mapDeltas.isEmpty ? 0 : mapDeltas.reduce(0, +) / Double(mapDeltas.count),
            videoToHeadPoseMaxDeltaMs: mapDeltas.max() ?? 0,
            imuToVideoEstimatedOffsetMs: nil, // Requires motion correlation — Phase 2
            imuToVideoSyncMethod: "not_computed"
        )
        
        // Capture health (item 8)
        let captureHealth = SessionMetadata.CaptureHealth(
            videoBackpressureEvents: videoCaptureService?.backpressureEvents ?? 0,
            imuLagEvents: imuCaptureService?.lagEventCount ?? 0,
            arkitTrackingLossFrames: headPoseService?.trackingLossFrames ?? 0,
            droppedFrames: droppedFrames,
            arkitWasInterrupted: headPoseService?.wasInterrupted ?? false,
            arkitError: headPoseService?.lastSessionError?.localizedDescription
        )
        
        // Validation (item 13)
        let validation = validateSession(
            videoFrames: totalFrames,
            headPoseFrames: headPoseSamples.count,
            imuSamples: imuCaptureService?.totalSamples ?? 0,
            durationSec: durationSec,
            videoTimestamps: videoTimestamps
        )
        
        // Warnings
        var warnings = validation.issues
        if !useARKit { warnings.append("ARKit head pose was not available") }
        if calibrationService.calibration == nil { warnings.append("Camera calibration not captured") }
        if droppedFrames > 0 { warnings.append("Dropped \(droppedFrames) video frames") }
        if !(handLandmarkService?.provides3D ?? false) { warnings.append("Hand landmarks are 2D normalized image coords. z=0 is placeholder, NOT metric depth.") }
        if useARKit { warnings.append("Video frames from ARKit capturedImage (YCbCr → H.264).") }
        if headPoseService?.wasInterrupted == true { warnings.append("ARSession was interrupted during recording") }
        if let e = headPoseService?.lastSessionError { warnings.append("ARSession error: \(e.localizedDescription)") }
        
        let metadata = SessionMetadata(
            sessionId: sessionId,
            startTimeEpochMs: recordingStartEpochMs,
            endTimeEpochMs: endEpochMs,
            durationSec: durationSec,
            environment: SessionMetadata.EnvironmentInfo(
                type: ud.string(forKey: "environment_type") ?? "residential",
                subCategory: ud.string(forKey: "environment_sub") ?? "room_tidy_up",
                country: ud.string(forKey: "country") ?? "US",
                taskDescription: { let d = ud.string(forKey: "task_description") ?? ""; return d.isEmpty ? nil : d }()
            ),
            device: SessionMetadata.currentDeviceInfo(),
            capture: SessionMetadata.CaptureInfo(
                videoResolutionWidth: resW, videoResolutionHeight: resH,
                targetFPS: 30, videoCodec: "h264", imuTargetHz: 100,
                videoTimestampsEstimated: videoTimestamps.contains { $0.isEstimated },
                timestampClock: "mach_absolute_time",
                epochToMonotonicPrecision: "~1ms (single reference point at init)"
            ),
            advancedCapture: SessionMetadata.AdvancedCaptureInfo(
                enabled: true, headPoseAvailable: useARKit,
                headPoseSource: useARKit ? "arkit" : "none",
                cameraCalibrationAvailable: calibrationService.calibration != nil,
                cameraCalibrationSource: calibrationService.calibration?.source ?? "none",
                cameraMountConfigAvailable: true
            ),
            semanticArtifacts: SessionMetadata.SemanticArtifactInfo(
                hasHandLandmarks: (handLandmarkService?.rowCount ?? 0) > 0,
                handLandmarkSource: handLandmarkService?.backendName ?? "none",
                hasHandPose: (handPoseService?.rowCount ?? 0) > 0,
                hasFacePresence: (facePresenceService?.rowCount ?? 0) > 0,
                hasFrameQcMetrics: (frameQCService?.rowCount ?? 0) > 0,
                handLandmarksAre3D: handLandmarkService?.provides3D ?? false
            ),
            imuMetrics: SessionMetadata.IMUMetrics(
                totalSamples: imuCaptureService?.totalSamples ?? 0,
                actualSampleRateHz: imuCaptureService?.actualSampleRateHz ?? 0,
                startupSamplesDiscarded: imuCaptureService?.startupDiscarded ?? 0,
                sampleIntervalStdDevMs: imuCaptureService?.sampleIntervalStdDevMs ?? 0,
                maxGapMs: imuCaptureService?.maxGapMsValue ?? 0
            ),
            videoMetrics: SessionMetadata.VideoMetrics(
                totalFrames: totalFrames, actualAvgFPS: avgFPS, droppedFrames: droppedFrames,
                frameIntervalStdDevMs: videoCaptureService?.frameIntervalStdDevMs ?? 0
            ),
            syncMetrics: syncMetrics,
            captureHealth: captureHealth,
            coordinateSystem: .arkitDefault,
            pipeline: SessionMetadata.PipelineInfo(
                version: kPipelineVersion, build: kPipelineBuild,
                captureMode: useARKit ? "arkit+assetwriter" : "avfoundation+assetwriter",
                threadModel: "multi-queue",
                timestampSource: "mach_absolute_time"
            ),
            validation: validation,
            qcSummary: qcSummary,
            warnings: warnings
        )
        
        do {
            try packagingService.writeMetadata(metadata, to: dir.appendingPathComponent("metadata.json"))
            try packagingService.writeManifest(sessionId: sessionId, sessionDir: dir)
        } catch {}
        
        cleanup()
    }
    
    // MARK: - Validation (item 13)
    
    private func validateSession(
        videoFrames: Int, headPoseFrames: Int, imuSamples: Int,
        durationSec: Double, videoTimestamps: [VideoTimestamp]
    ) -> SessionMetadata.ValidationResult {
        var issues: [String] = []
        
        // Frame count consistency
        let frameCountConsistent = !useARKit || videoFrames == headPoseFrames
        if !frameCountConsistent {
            issues.append("Frame count mismatch: video=\(videoFrames), headPose=\(headPoseFrames)")
        }
        
        // Coverage
        let expectedIMU = durationSec * 100
        let imuCoverage = expectedIMU > 0 ? Double(imuSamples) / expectedIMU * 100.0 : 0
        if imuCoverage < 90 { issues.append("IMU coverage is \(String(format: "%.1f", imuCoverage))% (< 90%)") }
        
        let expectedHeadPose = durationSec * 30
        let headPoseCoverage = expectedHeadPose > 0 ? Double(headPoseFrames) / expectedHeadPose * 100.0 : 0
        if useARKit && headPoseCoverage < 90 { issues.append("Head pose coverage is \(String(format: "%.1f", headPoseCoverage))% (< 90%)") }
        
        // Timestamp monotonicity
        var monotonic = true
        for i in 1..<videoTimestamps.count {
            if videoTimestamps[i].timestampNs <= videoTimestamps[i-1].timestampNs {
                monotonic = false
                issues.append("Non-monotonic video timestamp at frame \(i)")
                break
            }
        }
        
        return SessionMetadata.ValidationResult(
            frameCountConsistent: frameCountConsistent,
            imuCoveragePercent: min(imuCoverage, 100),
            headPoseCoveragePercent: min(headPoseCoverage, 100),
            timestampsMonotonic: monotonic,
            issues: issues
        )
    }
    
    // MARK: - FPS Calculation
    
    private func computeEffectiveFPS(from timestamps: [VideoTimestamp]) -> Double {
        guard timestamps.count > 1 else { return 0 }
        var durMs: Double = 0; var n = 0
        for i in 0..<(timestamps.count - 1) {
            let iv = timestamps[i+1].relativeMs - timestamps[i].relativeMs
            if iv > 0 && iv < 100 { durMs += iv; n += 1 }
        }
        return durMs > 0 ? Double(n) / (durMs / 1000.0) : 0
    }
    
    private func nearestVideoTimestamp(forNs targetNs: UInt64, in timestamps: [VideoTimestamp]) -> VideoTimestamp {
        var lo = 0, hi = timestamps.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if timestamps[mid].timestampNs < targetNs { lo = mid + 1 } else { hi = mid }
        }
        if lo == 0 { return timestamps[0] }
        let a = timestamps[lo-1], b = timestamps[lo]
        let da = targetNs > a.timestampNs ? targetNs - a.timestampNs : a.timestampNs - targetNs
        let db = targetNs > b.timestampNs ? targetNs - b.timestampNs : b.timestampNs - targetNs
        return da <= db ? a : b
    }
    
    private func cleanup() {
        videoCaptureService = nil; imuCaptureService = nil; headPoseService = nil
        handLandmarkService = nil; handPoseService = nil; facePresenceService = nil; frameQCService = nil
        previewImage = nil
    }
    
    private func ensureCameraPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized: return true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted { await MainActor.run { self.lastError = "Camera permission denied."; self.statusMessage = "Permission required" } }
            return granted
        default:
            await MainActor.run { self.lastError = "Camera permission denied."; self.statusMessage = "Permission required" }
            return false
        }
    }

    nonisolated private static func previewImage(from pb: CVPixelBuffer) -> UIImage? {
        let ci = CIImage(cvPixelBuffer: pb)
        let r = CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(pb), height: CVPixelBufferGetHeight(pb))
        guard let cg = CIContext().createCGImage(ci, from: r) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - VideoCaptureDelegate

extension RecordingOrchestrator: VideoCaptureDelegate {
    nonisolated func videoCaptureService(_ service: VideoCaptureService, didOutputPixelBuffer pixelBuffer: CVPixelBuffer, relativeMs: Double, frameIndex: Int) {
        Task { @MainActor [weak self] in self?.frameCount = frameIndex }
        if frameIndex % 5 == 0 {
            let preview = Self.previewImage(from: pixelBuffer)
            Task { @MainActor [weak self] in self?.previewImage = preview }
        }
        guard frameIndex % visionStride == 0 else { return }
        visionQueue.async { [weak self] in
            guard let self = self else { return }
            self.handLandmarkService?.processFrame(pixelBuffer: pixelBuffer, frameIndex: frameIndex, relativeMs: relativeMs)
            if let r = self.handLandmarkService?.lastResult { self.handPoseService?.deriveFromLandmarks(r) }
            self.facePresenceService?.processFrame(pixelBuffer: pixelBuffer, frameIndex: frameIndex, relativeMs: relativeMs)
            let hd = !(self.handLandmarkService?.lastResult?.hands.isEmpty ?? true)
            let fd = self.facePresenceService?.lastFaceDetected ?? false
            self.frameQCService?.processFrame(pixelBuffer: pixelBuffer, frameIndex: frameIndex, relativeMs: relativeMs, handDetected: hd, faceDetected: fd)
        }
    }
}
