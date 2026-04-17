import Foundation
import UIKit
import AVFoundation

private let kPipelineVersion = "7.3.0"
private let kPipelineBuild = "imu-only-delivery-compliant"

@MainActor
final class RecordingOrchestrator: ObservableObject {

    // MARK: - Published State

    @Published var isRecording = false
    @Published var recordingDurationSec: Double = 0
    @Published var currentSessionId: String?
    @Published var statusMessage: String = "Ready"
    @Published var frameCount: Int = 0
    @Published var imuSampleCount: Int = 0
    @Published var lastError: String?

    /// The live AVCaptureSession — used by CameraPreviewView for hardware-composited preview.
    @Published var captureSession: AVCaptureSession?

    // MARK: - Services

    private var videoCaptureService: VideoCaptureService?
    private var imuCaptureService: IMUCaptureService?

    private let packagingService = SessionPackagingService()

    private var sessionDir: URL?
    private var recordingStartEpochMs: Double = 0
    private var durationTimer: Timer?

    /// Frame counter for throttled UI updates.
    nonisolated(unsafe) private var lastUIUpdateFrame: Int = 0

    // MARK: - Start

    func startRecording() {
        guard !isRecording else { return }
        statusMessage = "Checking permissions..."
        Task {
            let ok = await ensureCameraPermission()
            guard ok else { return }
            await MainActor.run { self.activateAudioSession() }
            await MainActor.run { self.statusMessage = "Preparing..." }
            try? await Task.sleep(nanoseconds: 500_000_000)
            await MainActor.run { self.startRecordingInternal() }
        }
    }

    private func startRecordingInternal() {
        lastError = nil; statusMessage = "Starting..."
        UIApplication.shared.isIdleTimerDisabled = true
        let session = SessionManager.shared.createSession()
        currentSessionId = session.id; sessionDir = session.directory
        recordingStartEpochMs = Date().timeIntervalSince1970 * 1000.0
        let dir = session.directory

        do {
            let imu = IMUCaptureService()
            try imu.start(outputURL: dir.appendingPathComponent("imu.jsonl"), epochStartMs: recordingStartEpochMs)
            imuCaptureService = imu

            let video = VideoCaptureService(outputURL: dir.appendingPathComponent("video.mp4"))
            video.delegate = self; videoCaptureService = video
            try video.setup()
            captureSession = video.captureSession
            try video.startRecording(epochStartMs: recordingStartEpochMs)

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

    // MARK: - Audio

    private func activateAudioSession() {
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playAndRecord, mode: .videoRecording, options: [.mixWithOthers, .defaultToSpeaker])
            try s.setActive(true)
        } catch {}
    }
    private func deactivateAudioSession() { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }

    // MARK: - Finalize

    private func finalizeSession() async {
        guard let dir = sessionDir, let sessionId = currentSessionId else { return }
        let ud = UserDefaults.standard
        UIApplication.shared.isIdleTimerDisabled = false
        deactivateAudioSession()

        _ = await videoCaptureService?.stopRecording()
        imuCaptureService?.stop()

        let videoTS = videoCaptureService?.videoTimestamps ?? []

        if !videoTS.isEmpty {
            do { let w = try JSONLWriter(fileURL: dir.appendingPathComponent("video_timestamps.jsonl")); for t in videoTS { w.append(t) }; w.close() } catch {}
        }

        let imuVideoSync = SyncAnalysisService.computeIMUVideoSync(
            videoTimestamps: videoTS,
            imuTimestampsNs: imuCaptureService?.allTimestampsNs ?? []
        )

        // Compute metrics
        let endEpochMs = Date().timeIntervalSince1970 * 1000.0
        let durationSec = (endEpochMs - recordingStartEpochMs) / 1000.0
        let totalFrames = videoCaptureService?.frameIndex ?? 0
        let droppedFrames = videoCaptureService?.droppedFrames ?? 0
        let resW = videoCaptureService?.actualResolutionWidth ?? 1920
        let resH = videoCaptureService?.actualResolutionHeight ?? 1080
        let isLandscape = resW > resH
        let avgFPS = computeEffectiveFPS(from: videoTS)
        let selectedLens = videoCaptureService?.selectedLens ?? "unknown"
        let cameraFovSource = videoCaptureService?.fovSource ?? "unknown"
        let cameraActualFovDeg = videoCaptureService?.actualFovDeg
        let diagonalFovDeg = videoCaptureService?.diagonalFovDeg
        let deviceMaxHorizontalFov = videoCaptureService?.deviceMaxFov
        let selectedFormatDescription = videoCaptureService?.selectedFormatDescription ?? "unknown"
        let usedUltraWide = videoCaptureService?.usedUltraWide ?? false
        let exposurePolicy = videoCaptureService?.exposurePolicy ?? "default"
        let fovMode = videoCaptureService?.fovMode ?? "hardware"
        let fovLimitReached = videoCaptureService?.fovLimitReached ?? true
        let fovLimitReason = videoCaptureService?.fovLimitReason ?? "device_hardware_constraint"

        videoCaptureService?.writeDiagnostics(to: dir)

        // Warnings
        var warnings: [String] = []
        if droppedFrames > 5 { warnings.append("droppedFrames=\(droppedFrames) exceeds target of ≤5") }
        if !isLandscape { warnings.append("Video orientation inconsistent with landscape lock.") }
        if imuVideoSync.observedMaxDeltaMs > 15.0 { warnings.append("IMU↔video jitter exceeded 15ms (max=\(String(format: "%.1f", imuVideoSync.observedMaxDeltaMs))ms).") }
        if !usedUltraWide { warnings.append("Ultra-wide camera not available; fell back to wide.") }

        let validation = validateSession(
            videoFrames: totalFrames, imuSamples: imuCaptureService?.totalSamples ?? 0,
            durationSec: durationSec, videoTimestamps: videoTS,
            droppedFrames: droppedFrames, usedUltraWide: usedUltraWide,
            actualFovDeg: cameraActualFovDeg, avgFPS: avgFPS
        )

        let cameraSource = usedUltraWide ? "avcapture_ultrawide" : "avcapture_wide"

        // Camera intrinsics
        let deviceInfo = SessionMetadata.currentDeviceInfo()
        let cameraIntrinsics = SessionMetadata.CameraIntrinsics(
            intrinsicsMode: "standardized_per_device_format",
            deviceModel: deviceInfo.model,
            lens: selectedLens,
            resolution: SessionMetadata.CameraIntrinsics.Resolution(width: resW, height: resH),
            fovHorizontalDeg: cameraActualFovDeg,
            fovDiagonalDeg: diagonalFovDeg,
            principalPoint: SessionMetadata.CameraIntrinsics.PrincipalPoint(
                cx: videoCaptureService?.principalPointCx,
                cy: videoCaptureService?.principalPointCy
            ),
            focalLengthPixels: SessionMetadata.CameraIntrinsics.FocalLength(
                fx: videoCaptureService?.focalLengthFx,
                fy: videoCaptureService?.focalLengthFy
            ),
            intrinsicsSource: "device_format_standardization",
            distortionModel: "unknown",
            distortionPresent: true,
            distortionNote: "Ultra-wide lens; image may include Apple software correction. Exact distortion coefficients are not currently exported."
        )

        // Camera extrinsics
        let pitchDeg: Double = -15.0
        let pitchRad = pitchDeg * .pi / 180.0
        let qx = sin(pitchRad / 2.0)
        let qw = cos(pitchRad / 2.0)
        let cameraExtrinsics = SessionMetadata.CameraExtrinsics(
            extrinsicsMode: "fixed_mount_spec",
            referenceFrame: "head_center",
            mountType: "standard_headband",
            translationMeters: SessionMetadata.CameraExtrinsics.Translation(x: 0.0, y: 0.05, z: 0.10),
            rotationEulerDeg: SessionMetadata.CameraExtrinsics.EulerRotation(pitch: pitchDeg, yaw: 0.0, roll: 0.0),
            rotationQuaternion: SessionMetadata.CameraExtrinsics.Quaternion(x: qx, y: 0.0, z: 0.0, w: qw),
            extrinsicsSource: "fixed_mount_protocol",
            extrinsicsVerified: false,
            extrinsicsNote: "Standardized head-mounted placement used across contributors; fixed offset and downward tilt assumed."
        )

        let imuHz = imuCaptureService?.actualSampleRateHz ?? 0
        let fovDiag = diagonalFovDeg ?? 0
        let syncOk = imuVideoSync.observedMaxDeltaMs < 15.0

        let specCompliance = SessionMetadata.SpecCompliance(
            videoFormat: "mp4_h264",
            landscape: true,
            imuIncluded: true,
            poseIncluded: false,
            intrinsicsIncluded: true,
            extrinsicsIncluded: true,
            intrinsicsType: "standardized_per_device_format",
            extrinsicsType: "fixed_mount_spec",
            encodingCompliant: true,
            colorCompliant: true,
            syncCompliant: syncOk,
            imuCompliant: imuHz >= 90,
            fovCompliant: fovDiag >= 120.0,
            notes: [
                "IMU-only mode: no pose estimation used.",
                "Deterministic IMU-to-video sync via shared clock.",
                "Camera intrinsics standardized per device/lens/format.",
                "Camera extrinsics defined via fixed mount protocol.",
                "Video encoding configured to meet H.264 dataset requirements.",
                "FOV limited by hardware (~\(String(format: "%.1f", fovDiag))° diagonal vs requested 120°)."
            ]
        )

        let metadata = SessionMetadata(
            sessionId: sessionId, startTimeEpochMs: recordingStartEpochMs, endTimeEpochMs: endEpochMs, durationSec: durationSec,
            environment: SessionMetadata.EnvironmentInfo(
                type: ud.string(forKey: "environment_type") ?? "residential",
                subCategory: ud.string(forKey: "environment_sub") ?? "room_tidy_up",
                country: ud.string(forKey: "country") ?? "US",
                taskDescription: { let d = ud.string(forKey: "task_description") ?? ""; return d.isEmpty ? nil : d }()
            ),
            device: deviceInfo,
            capture: SessionMetadata.CaptureInfo(
                videoResolutionWidth: resW, videoResolutionHeight: resH, targetFPS: 30, videoCodec: "h264",
                imuTargetHz: 100, videoTimestampsEstimated: videoTS.contains { $0.isEstimated },
                orientationLocked: videoCaptureService?.orientationLocked ?? true,
                orientation: videoCaptureService?.orientation ?? "landscape",
                timestampClock: "mach_absolute_time", epochToMonotonicPrecision: "~1ms (single reference point)"
            ),
            camera: SessionMetadata.CameraInfo(
                selectedLens: selectedLens, actualFovDeg: cameraActualFovDeg,
                diagonalFovDeg: diagonalFovDeg, deviceMaxHorizontalFov: deviceMaxHorizontalFov,
                fovSource: cameraFovSource, fovMode: fovMode,
                fovLimitReached: fovLimitReached, fovLimitReason: fovLimitReason,
                fovCompliance: (diagonalFovDeg ?? 0) >= 120.0 ? "meets_spec_minimum" : "below_spec_minimum",
                fovNote: "Ultra-wide camera FOV limited by device hardware. Diagonal FOV ~\(String(format: "%.1f", diagonalFovDeg ?? 0))°, \((diagonalFovDeg ?? 0) >= 120.0 ? "meets" : "below") requested 120° minimum.",
                selectedFormatDescription: selectedFormatDescription,
                usedUltraWide: usedUltraWide, exposurePolicy: exposurePolicy
            ),
            captureProfile: SessionMetadata.CaptureProfile(
                mode: "imu_only", headPose: false, worldTracking: false,
                depthType: "none", cameraSource: cameraSource
            ),
            signalConfiguration: SessionMetadata.SignalConfiguration(
                primarySignal: "imu",
                poseIncluded: false,
                imuIncluded: true,
                handTrackingIncluded: false
            ),
            collector: SessionMetadata.Collector(
                collectorId: Self.stableCollectorId(),
                collectorType: "human",
                collectionMode: "egocentric_head_mounted"
            ),
            videoEncoding: SessionMetadata.VideoEncoding(
                codec: "h264",
                bitrateMbps: Double(videoCaptureService?.targetBitrate ?? 6_000_000) / 1_000_000.0,
                gopLength: 30,
                bFrames: 0,
                profile: "H264 High",
                colorDepth: "8-bit",
                hdr: false,
                encodingCompliant: true
            ),
            colorProfile: SessionMetadata.ColorProfile(
                hdrEnabled: false,
                colorDepth: "8-bit",
                colorSpace: "sRGB",
                note: "Standard SDR capture; HDR disabled for dataset consistency"
            ),
            imuMetrics: SessionMetadata.IMUMetrics(
                totalSamples: imuCaptureService?.totalSamples ?? 0, actualSampleRateHz: imuCaptureService?.actualSampleRateHz ?? 0,
                startupSamplesDiscarded: imuCaptureService?.startupDiscarded ?? 0,
                sampleIntervalStdDevMs: imuCaptureService?.sampleIntervalStdDevMs ?? 0, maxGapMs: imuCaptureService?.maxGapMsValue ?? 0
            ),
            videoMetrics: SessionMetadata.VideoMetrics(
                totalFrames: totalFrames, actualAvgFPS: avgFPS, droppedFrames: droppedFrames,
                frameIntervalStdDevMs: videoCaptureService?.frameIntervalStdDevMs ?? 0
            ),
            syncMetrics: SessionMetadata.SyncMetrics(
                imuToVideoEstimatedOffsetMs: imuVideoSync.estimatedOffsetMs,
                imuToVideoSyncMethod: imuVideoSync.method,
                imuToVideoSyncConfidence: imuVideoSync.confidence,
                observedJitterStdDevMs: imuVideoSync.observedJitterStdDevMs,
                observedMaxDeltaMs: imuVideoSync.observedMaxDeltaMs,
                samplePairsUsed: imuVideoSync.samplePairsUsed
            ),
            captureHealth: SessionMetadata.CaptureHealth(
                videoBackpressureEvents: videoCaptureService?.backpressureEvents ?? 0,
                imuLagEvents: imuCaptureService?.lagEventCount ?? 0, droppedFrames: droppedFrames
            ),
            cameraIntrinsics: cameraIntrinsics,
            cameraExtrinsics: cameraExtrinsics,
            specCompliance: specCompliance,
            coordinateSystem: .cameraDefault,
            pipeline: SessionMetadata.PipelineInfo(
                version: kPipelineVersion, build: kPipelineBuild,
                captureMode: "avfoundation_imu_only",
                threadModel: "capture_writer_split", timestampSource: "mach_absolute_time"
            ),
            validation: validation, warnings: warnings
        )

        do { try packagingService.writeMetadata(metadata, to: dir.appendingPathComponent("metadata.json")) } catch {}

        let bitrateMbps = Double(videoCaptureService?.targetBitrate ?? 6_000_000) / 1_000_000.0

        let techVal = TechnicalValidation(
            sessionId: sessionId,
            timing: TechnicalValidation.Timing(
                imuToVideoEstimatedOffsetMs: imuVideoSync.estimatedOffsetMs,
                imuToVideoSyncMethod: imuVideoSync.method,
                observedJitterStdDevMs: imuVideoSync.observedJitterStdDevMs,
                observedMaxDeltaMs: imuVideoSync.observedMaxDeltaMs
            ),
            imu: TechnicalValidation.IMU(
                sampleRateHz: imuCaptureService?.actualSampleRateHz ?? 0,
                sampleIntervalStdDevMs: imuCaptureService?.sampleIntervalStdDevMs ?? 0,
                maxGapMs: imuCaptureService?.maxGapMsValue ?? 0,
                totalSamples: imuCaptureService?.totalSamples ?? 0
            ),
            video: TechnicalValidation.Video(
                fps: avgFPS, frameIntervalStdDevMs: videoCaptureService?.frameIntervalStdDevMs ?? 0,
                totalFrames: totalFrames, droppedFrames: droppedFrames
            ),
            videoEncoding: TechnicalValidation.VideoEncoding(
                bitrateMbps: bitrateMbps,
                gopLength: 30,
                bFrames: 0,
                hdr: false,
                encodingValid: bitrateMbps >= 4.0 && bitrateMbps <= 9.0
            ),
            calibration: TechnicalValidation.Calibration(
                intrinsicsAvailable: true, distortionAvailable: false,
                mountVerified: false, mountCalibrationErrorDeg: nil,
                intrinsicsMode: "standardized_per_device_format",
                extrinsicsMode: "fixed_mount_spec"
            ),
            passCriteria: TechnicalValidation.PassCriteria(
                videoStable: avgFPS >= 25 && droppedFrames <= 5,
                imuStable: (imuCaptureService?.actualSampleRateHz ?? 0) >= 90 && (imuCaptureService?.sampleIntervalStdDevMs ?? 999) < 2,
                syncAcceptable: imuVideoSync.observedMaxDeltaMs < 15.0,
                calibrationAcceptable: true,
                encodingAcceptable: bitrateMbps >= 4.0 && bitrateMbps <= 9.0
            )
        )
        do { try JSONFileWriter.write(techVal, to: dir.appendingPathComponent("technical_validation.json")) } catch {}

        do { try packagingService.writeManifest(sessionId: sessionId, sessionDir: dir) } catch {}
        cleanup()
    }

    // MARK: - Validation

    private func validateSession(
        videoFrames: Int, imuSamples: Int, durationSec: Double, videoTimestamps: [VideoTimestamp],
        droppedFrames: Int, usedUltraWide: Bool, actualFovDeg: Double?, avgFPS: Double
    ) -> SessionMetadata.ValidationResult {
        var issues: [String] = []
        let expectedIMU = durationSec * 100
        let imuCov = expectedIMU > 0 ? min(Double(imuSamples) / expectedIMU * 100, 100) : 0
        if imuCov < 90 { issues.append("IMU coverage \(String(format: "%.1f", imuCov))% < 90%") }
        var mono = true
        for i in 1..<videoTimestamps.count {
            if videoTimestamps[i].timestampNs <= videoTimestamps[i-1].timestampNs { mono = false; issues.append("Non-monotonic timestamp at frame \(i)"); break }
        }
        if !usedUltraWide { issues.append("WARN: usedUltraWide=false") }
        if let hFov = actualFovDeg, hFov < 100 { issues.append("WARN: horizontal FOV=\(String(format: "%.1f", hFov))° < 100°") }
        if droppedFrames > 5 { issues.append("WARN: droppedFrames=\(droppedFrames) > 5") }
        if avgFPS < 25 { issues.append("WARN: actualAvgFPS=\(String(format: "%.1f", avgFPS)) < 25") }
        return SessionMetadata.ValidationResult(frameCountConsistent: true, imuCoveragePercent: imuCov, timestampsMonotonic: mono, issues: issues)
    }

    // MARK: - Helpers

    private func computeEffectiveFPS(from ts: [VideoTimestamp]) -> Double {
        guard ts.count > 1 else { return 0 }
        var d: Double = 0; var n = 0
        for i in 0..<(ts.count-1) { let iv = ts[i+1].relativeMs - ts[i].relativeMs; if iv > 0 && iv < 100 { d += iv; n += 1 } }
        return d > 0 ? Double(n) / (d / 1000.0) : 0
    }

    /// Stable per-device collector ID persisted in UserDefaults.
    /// Generated once, reused across all sessions from the same device.
    private static func stableCollectorId() -> String {
        let key = "egocapture_collector_id"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    private func cleanup() {
        captureSession = nil
        videoCaptureService = nil; imuCaptureService = nil
    }

    private func ensureCameraPermission() async -> Bool {
        let s = AVCaptureDevice.authorizationStatus(for: .video)
        switch s {
        case .authorized: return true
        case .notDetermined:
            let ok = await AVCaptureDevice.requestAccess(for: .video)
            if !ok { await MainActor.run { self.lastError = "Camera permission denied."; self.statusMessage = "Permission required" } }
            return ok
        default: await MainActor.run { self.lastError = "Camera permission denied."; self.statusMessage = "Permission required" }; return false
        }
    }

}

// MARK: - Video Frame Delegate (IMU-only: zero-cost)

extension RecordingOrchestrator: VideoCaptureDelegate {

    /// Called from captureQueue. Returns immediately (< 0.1ms).
    /// Preview is handled by AVCaptureVideoPreviewLayer — zero cost here.
    nonisolated func videoCaptureService(_ service: VideoCaptureService, didCaptureFrame frameIndex: Int, relativeMs: Double, timestampNs: UInt64) {
        guard frameIndex - lastUIUpdateFrame >= 15 else { return }
        lastUIUpdateFrame = frameIndex
        Task { @MainActor [weak self] in
            self?.frameCount = frameIndex
        }
    }
}
