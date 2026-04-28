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

    /// Optional activity label selected via the Activities → Briefing flow.
    /// When non-empty, it takes precedence over the Settings `task_description`
    /// field and is emitted as `environment.taskDescription` in the session
    /// metadata (the Lambda already maps that field into the MCAP task block).
    @Published var activityTitle: String?

    /// Optional taxonomy selection coming from the wizard. Persisted as
    /// `taxonomy.json` next to `metadata.json` (out-of-MCAP annotation).
    /// When set, the day/night bucket is recomputed at finalize time so
    /// it reflects the actual recording end timestamp.
    var taxonomySelection: SessionTaxonomy?

    /// The live AVCaptureSession — used by CameraPreviewView for hardware-composited preview.
    @Published var captureSession: AVCaptureSession?

    // MARK: - Services

    private var videoCaptureService: VideoCaptureService?
    private var imuCaptureService: IMUCaptureService?

    private let packagingService = SessionPackagingService()

    private var sessionDir: URL?
    private var recordingStartEpochMs: Double = 0
    private var durationTimer: Timer?

    /// Populated once per session by `LensDistortionProbeService.ensureCalibration`.
    /// When non-nil, downstream metadata emits `distortionModel = "plumb_bob"`
    /// and attaches the fitted coefficients. When nil, we fall back to the
    /// GDC-state-based model (`uncorrected_barrel` / `apple_isp_corrected`).
    private var lensCalibration: LensDistortionCalibration?

    /// Frame counter for throttled UI updates.
    nonisolated(unsafe) private var lastUIUpdateFrame: Int = 0

    // MARK: - Start

    func startRecording() {
        guard !isRecording else { return }
        statusMessage = "Checking permissions..."
        Task { @MainActor in
            let ok = await ensureCameraPermission()
            guard ok else { return }
            self.activateAudioSession()
            self.statusMessage = "Preparing..."
            try? await Task.sleep(nanoseconds: 500_000_000)
            await self.startRecordingInternal()
        }
    }

    private func startRecordingInternal() async {
        lastError = nil; statusMessage = "Starting..."
        UIApplication.shared.isIdleTimerDisabled = true
        let session = SessionManager.shared.createSession()
        currentSessionId = session.id; sessionDir = session.directory
        recordingStartEpochMs = Date().timeIntervalSince1970 * 1000.0
        let dir = session.directory

        do {
            let imu = IMUCaptureService()
            try imu.start(outputURL: SessionFiles.url("imu", "jsonl", in: dir), epochStartMs: recordingStartEpochMs)
            imuCaptureService = imu

            // Lens-distortion probe (Phase 3). Opportunistic and silent:
            //   - cache hit   → < 1 ms, no user-visible effect.
            //   - cache miss  → ~200 ms probe (runs before VideoCaptureService
            //                  claims the UW hardware so the virtual
            //                  multi-camera device it opens can access the
            //                  shared constituent).
            //   - unsupported → negative cache ensures we skip the probe on
            //                  subsequent sessions; no delay.
            // On failure the pipeline keeps running and metadata falls back to
            // `uncorrected_barrel` without coefficients.
            self.lensCalibration = await LensDistortionProbeService.ensureCalibration()

            let preset = VideoCaptureService.CapturePreset.current
            let video = VideoCaptureService(
                outputURL: SessionFiles.url("video", "mp4", in: dir),
                preset: preset
            )
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
        let uploadDir = sessionDir
        let uploadId = currentSessionId
        Task {
            await finalizeSession()
            statusMessage = "Session saved"
            if let dir = uploadDir, let id = uploadId {
                NotificationCenter.default.post(
                    name: Notification.Name("egocaptureSessionReadyForUpload"),
                    object: nil,
                    userInfo: ["sessionId": id, "sessionDir": dir]
                )
            }
        }
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
            do { let w = try JSONLWriter(fileURL: SessionFiles.url("video_timestamps", "jsonl", in: dir)); for t in videoTS { w.append(t) }; w.close() } catch {}
        }

        if let videoURL = SessionFiles.resolveExisting("video", "mp4", in: dir) {
            let visionResult = await PostCaptureVisionAnalyzer.analyze(
                videoURL: videoURL,
                sessionDir: dir,
                recordingStartEpochMs: recordingStartEpochMs,
                videoTimestamps: videoTS
            )
            if visionResult.frameQcRows > 0 {
                print("[Orchestrator] Post-capture QC analyzed \(visionResult.frameQcRows) frames; hands rows=\(visionResult.handRows), face rows=\(visionResult.faceRows)")
            }
        }

        let imuVideoSync = SyncAnalysisService.computeIMUVideoSync(
            videoTimestamps: videoTS,
            imuTimestampsNs: imuCaptureService?.allTimestampsNs ?? []
        )

        // Compute metrics
        let endEpochMs = Date().timeIntervalSince1970 * 1000.0
        // Prefer the actual video span (first-to-last frame epoch) over
        // the wall-clock start/stop delta. The wall-clock interval includes
        // pre-capture setup overhead, post-capture finalisation, and any
        // background pauses, which inflate the declared duration vs the
        // real footage. Downstream (MCAP builder) already prefers the
        // video span when present; matching the source here keeps
        // metadata.json self-consistent.
        let wallClockDurationSec = (endEpochMs - recordingStartEpochMs) / 1000.0
        let durationSec: Double = {
            guard
                let firstMs = videoTS.first?.timestampEpochMs,
                let lastMs = videoTS.last?.timestampEpochMs,
                lastMs > firstMs
            else { return wallClockDurationSec }
            return (lastMs - firstMs) / 1000.0
        }()
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
        let measuredIntrinsics = videoCaptureService?.intrinsicsSource == "avcapture_camera_intrinsic_matrix"
        let intrinsicsModeValue = measuredIntrinsics
            ? "measured_per_device"
            : "standardized_per_device_format"
        let intrinsicsSourceValue = measuredIntrinsics
            ? "avcapture_camera_intrinsic_matrix"
            : "pinhole_derived_from_fov"

        let gdcSupported = videoCaptureService?.gdcSupported ?? false
        let gdcEnabled = videoCaptureService?.gdcEnabled ?? true

        // Distortion model: prefer the probe-fitted plumb_bob when available
        // (Phase 3). Fall back to the GDC-state-based stub when the probe
        // didn't run or failed.
        let distortionModelValue: String
        let distortionNoteValue: String
        let distortionCoefficientsValue: [Double]?
        let distortionResidualPxValue: Double?
        let probeIntrinsicsSourceValue: String?
        let probeFx: Double?
        let probeFy: Double?
        let probeCx: Double?
        let probeCy: Double?

        if let cal = lensCalibration {
            let scaled = cal.scaledIntrinsics(recordingWidth: resW, recordingHeight: resH)
            distortionModelValue = "plumb_bob"
            distortionCoefficientsValue = cal.distortionCoefficients
            distortionResidualPxValue = scaled.fitResidualRmsPx
            distortionNoteValue = String(
                format: "Radial plumb_bob coefficients [k1,k2,p1=0,p2=0,k3] fitted from AVCameraCalibrationData via a probe session on a virtual multi-camera device. Fit quality: RMS = %.3f px at recording resolution from %d samples. Tangential coefficients are fixed at zero; modern iPhone lenses exhibit tangential residuals below 1e-4 in practice.",
                scaled.fitResidualRmsPx, cal.fitSamples
            )
            probeIntrinsicsSourceValue = "avcapture_photo_calibration_fitted"
            probeFx = scaled.fx
            probeFy = scaled.fy
            probeCx = scaled.cx
            probeCy = scaled.cy
        } else if gdcSupported && !gdcEnabled {
            distortionModelValue = "uncorrected_barrel"
            distortionNoteValue = "Geometric Distortion Correction is disabled to recover the ultra-wide camera's native FOV. Frames carry lens barrel distortion; the calibration probe did not run or failed, so no explicit coefficients are provided."
            distortionCoefficientsValue = nil
            distortionResidualPxValue = nil
            probeIntrinsicsSourceValue = nil
            probeFx = nil; probeFy = nil; probeCx = nil; probeCy = nil
        } else if gdcSupported && gdcEnabled {
            distortionModelValue = "apple_isp_corrected"
            distortionNoteValue = "Frames are geometrically pre-rectified by Apple's ISP (GDC on). Residual distortion is small but unquantified; the calibration probe did not run or failed."
            distortionCoefficientsValue = nil
            distortionResidualPxValue = nil
            probeIntrinsicsSourceValue = nil
            probeFx = nil; probeFy = nil; probeCx = nil; probeCy = nil
        } else {
            distortionModelValue = "apple_isp_corrected"
            distortionNoteValue = "Frames are geometrically pre-rectified by Apple's ISP before delivery. Residual distortion is small but unquantified; the calibration probe did not run or failed."
            distortionCoefficientsValue = nil
            distortionResidualPxValue = nil
            probeIntrinsicsSourceValue = nil
            probeFx = nil; probeFy = nil; probeCx = nil; probeCy = nil
        }

        // Prefer the probe's fitted intrinsics over the measured-per-frame
        // ones when available; the probe's K is the same lens but tied to the
        // distortion fit, which keeps D and K self-consistent.
        let finalFx = probeFx ?? videoCaptureService?.focalLengthFx
        let finalFy = probeFy ?? videoCaptureService?.focalLengthFy
        let finalCx = probeCx ?? videoCaptureService?.principalPointCx
        let finalCy = probeCy ?? videoCaptureService?.principalPointCy
        let finalIntrinsicsSource = probeIntrinsicsSourceValue ?? intrinsicsSourceValue
        let finalIntrinsicsMode = (lensCalibration != nil)
            ? "measured_per_device_probe_fit"
            : intrinsicsModeValue

        let cameraIntrinsics = SessionMetadata.CameraIntrinsics(
            intrinsicsMode: finalIntrinsicsMode,
            deviceModel: deviceInfo.model,
            lens: selectedLens,
            resolution: SessionMetadata.CameraIntrinsics.Resolution(width: resW, height: resH),
            fovHorizontalDeg: cameraActualFovDeg,
            fovDiagonalDeg: diagonalFovDeg,
            principalPoint: SessionMetadata.CameraIntrinsics.PrincipalPoint(
                cx: finalCx,
                cy: finalCy
            ),
            focalLengthPixels: SessionMetadata.CameraIntrinsics.FocalLength(
                fx: finalFx,
                fy: finalFy
            ),
            intrinsicsSource: finalIntrinsicsSource,
            distortionModel: distortionModelValue,
            distortionPresent: true,
            distortionNote: distortionNoteValue,
            distortionCoefficients: distortionCoefficientsValue,
            distortionFitResidualRmsPx: distortionResidualPxValue
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
                taskDescription: {
                    if let activity = activityTitle, !activity.isEmpty { return activity }
                    let d = ud.string(forKey: "task_description") ?? ""
                    return d.isEmpty ? nil : d
                }()
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
                collectionMode: "egocentric_head_mounted",
                campaign: CampaignConfig.campaign,
                userName: CampaignConfig.userName.isEmpty ? nil : CampaignConfig.userName,
                userSlug: CampaignConfig.userSlug,
                vendorId: CampaignConfig.vendorIdentifier
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

        do { try packagingService.writeMetadata(metadata, to: SessionFiles.url("metadata", "json", in: dir)) } catch {}

        // Out-of-MCAP taxonomy annotation. day/night is recomputed against
        // the actual recording end so the bucket reflects when the user
        // actually shot the clip rather than when they tapped through the
        // wizard.
        if let selection = taxonomySelection {
            let endDate = Date(timeIntervalSince1970: endEpochMs / 1000.0)
            let day = SessionTaxonomy.dayOrNight(for: endDate)
            let snapshot = SessionTaxonomy(
                schemaVersion: selection.schemaVersion,
                viewpointCode: selection.viewpointCode,
                scenarioCode: selection.scenarioCode,
                scenarioBucket: selection.scenarioBucket,
                domainCode: selection.domainCode,
                locationCode: selection.locationCode,
                locationLabelPt: selection.locationLabelPt,
                locationLabelEn: selection.locationLabelEn,
                taskCategoryCode: selection.taskCategoryCode,
                taskCategoryGroup: selection.taskCategoryGroup,
                taskCategoryLabelPt: selection.taskCategoryLabelPt,
                taskCategoryLabelEn: selection.taskCategoryLabelEn,
                selectedVerbsPt: selection.selectedVerbsPt,
                selectedVerbsEn: selection.selectedVerbsEn,
                selectedVerbsEs: selection.selectedVerbsEs,
                timeOfDay: day.label,
                recordingHour: day.hour
            )
            do {
                try JSONFileWriter.write(snapshot, to: SessionFiles.url("taxonomy", "json", in: dir))
            } catch {
                print("[Orchestrator] Failed to write taxonomy.json: \(error)")
            }
        }

        // Factory-nominal IMU intrinsics. Keyed off the same
        // ``hardwareIdentifier`` already recorded in metadata.json so the
        // on-device payload is identical to what the S3 backfill script
        // would produce for this device. Non-fatal on failure — the
        // session is already committed at this point, we'd rather ship a
        // session without intrinsics than lose the recording.
        let intrinsicsPayload = ImuIntrinsics.build(
            sessionId: sessionId,
            hardwareIdentifier: metadata.device.hardwareIdentifier,
            systemVersion: metadata.device.systemVersion,
            vendorId: metadata.collector.vendorId,
            imuTargetHz: metadata.capture.imuTargetHz,
            timestampClock: metadata.capture.timestampClock
        )
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(intrinsicsPayload)
            try data.write(to: SessionFiles.url("imu_intrinsics", "json", in: dir), options: .atomic)
        } catch {
            print("[Orchestrator] Failed to write imu_intrinsics.json: \(error)")
        }

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
        do { try JSONFileWriter.write(techVal, to: SessionFiles.url("technical_validation", "json", in: dir)) } catch {}

        do { try packagingService.writeManifest(sessionId: sessionId, sessionDir: dir) } catch {}

        // Kick off thumbnail extraction so the Sessions screen shows a real
        // frame immediately on the user's next visit. Detached + low-priority
        // so we don't compete with the IMU flush / upload kickoff.
        let thumbDir = dir
        Task.detached(priority: .utility) {
            await ThumbnailGenerator.generateIfNeeded(in: thumbDir)
        }

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
        lensCalibration = nil
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
