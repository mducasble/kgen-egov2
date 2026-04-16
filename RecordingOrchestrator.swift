import Foundation
import UIKit
import CoreVideo
import AVFoundation
import ARKit
import CoreImage

/// Central orchestrator that manages the recording lifecycle.
///
/// Data flow:
///   ARKit session → HeadPoseService → (pixel buffers) → VideoCaptureService → (pixel buffers) → Vision pipeline
///
/// STARTUP SEQUENCE (critical for avoiding background gaps):
///   1. Request camera permission (may show system dialog)
///   2. Activate audio session (tells iOS to keep us in foreground)
///   3. Wait 0.5s for UI to stabilize
///   4. Start IMU
///   5. Start vision services
///   6. Start video writer
///   7. Start ARKit (camera begins)
///
/// The audio session in .playAndRecord mode signals to iOS that this app
/// is actively using AV hardware and should not be interrupted.
@MainActor
final class RecordingOrchestrator: ObservableObject {
    private struct HeadPoseVideoTimestampMapEntry: Codable {
        let frameIndex: Int
        let videoTimestampEpochMs: Double
        let videoTimestampNs: Int64
        let headPoseTimestampEpochMs: Double?
        let headPoseTimestampNs: Int64?
        let mappingMode: String
        let deltaMs: Double
        let interpAlpha: Double?
    }

    private struct HeadPoseInterpolationEntry: Codable {
        let frameIndex: Int
        let videoTimestampEpochMs: Double
        let videoTimestampNs: Int64
        let positionMeters: HeadPoseSample.Position
        let rotationQuaternion: HeadPoseSample.Quaternion
        let source: String
        let interpAlpha: Double?
        let bracketingSamples: BracketingSamples
    }

    private struct BracketingSamples: Codable {
        let t0Ns: Int64?
        let t1Ns: Int64?
    }

    private struct ValidatedHeadPoseSample {
        let timestampNs: Int64
        let timestampEpochMs: Double
        let position: HeadPoseSample.Position
        let rotation: HeadPoseSample.Quaternion
    }

    private struct InterpolationResult {
        let poseTimestampNs: Int64?
        let poseTimestampEpochMs: Double?
        let position: HeadPoseSample.Position
        let rotation: HeadPoseSample.Quaternion
        let mode: String
        let deltaMs: Double
        let alpha: Double?
        let t0Ns: Int64?
        let t1Ns: Int64?
    }
    
    // MARK: - Published State
    
    @Published var isRecording = false
    @Published var recordingDurationSec: Double = 0
    @Published var currentSessionId: String?
    @Published var statusMessage: String = "Ready"
    @Published var frameCount: Int = 0
    @Published var imuSampleCount: Int = 0
    @Published var lastError: String?
    @Published var previewImage: UIImage?
    
    // MARK: - Services
    
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
    
    // MARK: - State
    
    private var sessionDir: URL?
    private var recordingStartEpochMs: Double = 0
    private var durationTimer: Timer?
    private var useARKit: Bool = false
    
    /// Vision processing queue — all frame analysis runs off main thread
    private let visionQueue = DispatchQueue(label: "com.egocapture.vision", qos: .userInitiated)
    
    /// Process every Nth frame for vision (balance quality vs performance)
    private let visionStride = 3  // ~10 FPS vision at 30 FPS video
    
    // MARK: - Recording Lifecycle
    
    func startRecording() {
        guard !isRecording else { return }
        statusMessage = "Checking permissions..."

        Task {
            // 1. Get camera permission FIRST (may show system dialog)
            let granted = await ensureCameraPermission()
            guard granted else { return }
            
            // 2. Activate audio session to prevent iOS from backgrounding us
            await MainActor.run {
                self.activateAudioSession()
            }
            
            // 3. Wait for UI to stabilize after permission dialog dismisses
            //    This prevents the ARKit session from being interrupted by
            //    SwiftUI navigation animations or system dialogs disappearing.
            await MainActor.run {
                self.statusMessage = "Preparing..."
            }
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            
            // 4. Start recording
            await MainActor.run {
                self.startRecordingInternal()
            }
        }
    }

    private func startRecordingInternal() {
        lastError = nil
        previewImage = nil
        statusMessage = "Starting..."

        // Prevent screen from locking
        UIApplication.shared.isIdleTimerDisabled = true

        // Create session directory
        let session = SessionManager.shared.createSession()
        currentSessionId = session.id
        sessionDir = session.directory
        recordingStartEpochMs = Date().timeIntervalSince1970 * 1000.0
        
        let dir = session.directory
        useARKit = ARWorldTrackingConfiguration.isSupported
        
        // Read mount config from user settings
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
            // 1. IMU — start first (fastest to stabilize)
            let imu = IMUCaptureService()
            try imu.start(
                outputURL: dir.appendingPathComponent("imu.jsonl"),
                epochStartMs: recordingStartEpochMs
            )
            imuCaptureService = imu
            
            // 2. Vision services (must be ready before frames arrive)
            let handLandmarks = HandLandmarkService(backend: AppleVisionHandBackend())
            try handLandmarks.start(
                outputURL: dir.appendingPathComponent("hand_landmarks.jsonl"),
                epochStartMs: recordingStartEpochMs
            )
            handLandmarkService = handLandmarks
            
            let handPose = HandPoseDerivationService(has3DLandmarks: handLandmarks.provides3D)
            try handPose.start(
                outputURL: dir.appendingPathComponent("hand_pose.jsonl"),
                epochStartMs: recordingStartEpochMs
            )
            handPoseService = handPose
            
            let facePresence = FacePresenceService()
            try facePresence.start(
                outputURL: dir.appendingPathComponent("face_presence.jsonl"),
                epochStartMs: recordingStartEpochMs
            )
            facePresenceService = facePresence
            
            let frameQC = FrameQCService()
            try frameQC.start(
                outputURL: dir.appendingPathComponent("frame_qc_metrics.jsonl"),
                epochStartMs: recordingStartEpochMs
            )
            frameQCService = frameQC
            
            // 3. Video capture service — set up writer BEFORE ARKit starts
            let video = VideoCaptureService(outputURL: dir.appendingPathComponent("video.mp4"))
            video.delegate = self
            videoCaptureService = video
            
            if useARKit {
                // Start HeadPoseService to get format info, then configure video
                let hp = HeadPoseService()
                try hp.start(
                    outputURL: dir.appendingPathComponent("head_pose.jsonl"),
                    epochStartMs: recordingStartEpochMs
                )
                
                let arWidth = hp.selectedWidth
                let arHeight = hp.selectedHeight
                
                video.setupForARKit(
                    width: arWidth,
                    height: arHeight,
                    pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                )
                try video.startRecording(epochStartMs: recordingStartEpochMs)
                
                hp.onIntrinsicsUpdate = { [weak self] intrinsics, resolution in
                    self?.calibrationService.extractFromARKit(intrinsics: intrinsics, resolution: resolution)
                }
                
                hp.onFrameReceived = { [weak video] pixelBuffer, timestamp, timestampNs, _ in
                    video?.writePixelBuffer(pixelBuffer, timestamp: timestamp, sourceTimestampNs: timestampNs)
                }
                
                headPoseService = hp
            } else {
                try video.setupStandalone()
                try video.startRecording(epochStartMs: recordingStartEpochMs)
            }
            
            isRecording = true
            statusMessage = "Recording"
            
            // Duration update timer
            durationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self = self else { return }
                    let now = Date().timeIntervalSince1970 * 1000.0
                    self.recordingDurationSec = (now - self.recordingStartEpochMs) / 1000.0
                    self.imuSampleCount = self.imuCaptureService?.totalSamples ?? 0
                }
            }
            
        } catch {
            lastError = "Start failed: \(error.localizedDescription)"
            statusMessage = "Error"
            cleanup()
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        isRecording = false
        statusMessage = "Finalizing..."
        durationTimer?.invalidate()
        durationTimer = nil
        
        Task {
            await finalizeSession()
            statusMessage = "Session saved"
        }
    }
    
    // MARK: - Audio Session (foreground keep-alive)
    
    /// Activate an audio session to signal iOS that we're using AV hardware.
    /// This prevents iOS from interrupting the ARKit camera session when
    /// SwiftUI animations or system overlays briefly appear.
    private func activateAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .videoRecording, options: [.mixWithOthers, .defaultToSpeaker])
            try audioSession.setActive(true)
            print("[Orchestrator] Audio session activated (foreground keep-alive)")
        } catch {
            print("[Orchestrator] Audio session activation failed: \(error) — recording may be interrupted")
        }
    }
    
    private func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Not critical
        }
    }
    
    // MARK: - Finalization
    
    private func finalizeSession() async {
        guard let dir = sessionDir, let sessionId = currentSessionId else { return }
        let ud = UserDefaults.standard
        
        // Re-enable screen lock and release audio session
        UIApplication.shared.isIdleTimerDisabled = false
        deactivateAudioSession()
        
        // Stop services in reverse order
        headPoseService?.stop()
        _ = await videoCaptureService?.stopRecording()
        imuCaptureService?.stop()
        handLandmarkService?.stop()
        handPoseService?.stop()
        facePresenceService?.stop()
        frameQCService?.stop()
        
        // Write video timestamps
        if let timestamps = videoCaptureService?.videoTimestamps, !timestamps.isEmpty {
            do {
                let tsWriter = try JSONLWriter(fileURL: dir.appendingPathComponent("video_timestamps.jsonl"))
                for ts in timestamps {
                    tsWriter.append(ts)
                }
                tsWriter.close()
            } catch {
                print("[Orchestrator] Failed to write video timestamps: \(error)")
            }
        }
        
        var syncMetrics: SessionMetadata.SyncMetrics?
        var interpolationWarnings: [String] = []
        if useARKit,
           let videoTimestamps = videoCaptureService?.videoTimestamps,
           !videoTimestamps.isEmpty {
            do {
                let headPoseURL = dir.appendingPathComponent("head_pose.jsonl")
                let rawHeadPoses = try loadHeadPoseSamples(from: headPoseURL)
                let validatedHeadPoses = sanitizeHeadPoseSamples(rawHeadPoses)

                let mapWriter = try JSONLWriter(fileURL: dir.appendingPathComponent("head_pose_video_map.jsonl"))
                let interpolatedWriter = try JSONLWriter(fileURL: dir.appendingPathComponent("head_pose_interpolated.jsonl"))

                var deltasMs: [Double] = []
                var interpolatedCount = 0
                var fallbackCount = 0

                for videoFrame in videoTimestamps.sorted(by: { $0.timestampNs < $1.timestampNs }) {
                    if let result = interpolateHeadPose(for: videoFrame.timestampNs, samples: validatedHeadPoses) {
                        if result.mode == "interpolated" { interpolatedCount += 1 } else { fallbackCount += 1 }
                        deltasMs.append(result.deltaMs)

                        mapWriter.append(HeadPoseVideoTimestampMapEntry(
                            frameIndex: videoFrame.frameIndex,
                            videoTimestampEpochMs: videoFrame.timestampEpochMs,
                            videoTimestampNs: videoFrame.timestampNs,
                            headPoseTimestampEpochMs: result.poseTimestampEpochMs,
                            headPoseTimestampNs: result.poseTimestampNs,
                            mappingMode: result.mode,
                            deltaMs: result.deltaMs,
                            interpAlpha: result.alpha
                        ))

                        interpolatedWriter.append(HeadPoseInterpolationEntry(
                            frameIndex: videoFrame.frameIndex,
                            videoTimestampEpochMs: videoFrame.timestampEpochMs,
                            videoTimestampNs: videoFrame.timestampNs,
                            positionMeters: result.position,
                            rotationQuaternion: result.rotation,
                            source: result.mode,
                            interpAlpha: result.alpha,
                            bracketingSamples: BracketingSamples(t0Ns: result.t0Ns, t1Ns: result.t1Ns)
                        ))
                    } else {
                        fallbackCount += 1
                        mapWriter.append(HeadPoseVideoTimestampMapEntry(
                            frameIndex: videoFrame.frameIndex,
                            videoTimestampEpochMs: videoFrame.timestampEpochMs,
                            videoTimestampNs: videoFrame.timestampNs,
                            headPoseTimestampEpochMs: nil,
                            headPoseTimestampNs: nil,
                            mappingMode: "nearest_fallback",
                            deltaMs: 0,
                            interpAlpha: nil
                        ))
                    }
                }

                mapWriter.close()
                interpolatedWriter.close()

                if !deltasMs.isEmpty {
                    let sortedDeltas = deltasMs.sorted()
                    let avg = sortedDeltas.reduce(0, +) / Double(sortedDeltas.count)
                    let maxDelta = sortedDeltas.last ?? 0
                    let p95 = percentile(sortedDeltas, p: 0.95)
                    let total = max(1, interpolatedCount + fallbackCount)
                    let interpolatedPercent = (Double(interpolatedCount) / Double(total)) * 100.0
                    let fallbackPercent = (Double(fallbackCount) / Double(total)) * 100.0

                    syncMetrics = SessionMetadata.SyncMetrics(
                        videoToHeadPoseAvgDeltaMs: avg,
                        videoToHeadPoseMaxDeltaMs: maxDelta,
                        videoToHeadPoseP95DeltaMs: p95,
                        videoToHeadPoseMappingMode: "interpolated_with_fallbacks",
                        videoToHeadPoseInterpolatedPercent: interpolatedPercent,
                        videoToHeadPoseFallbackPercent: fallbackPercent
                    )

                    if fallbackPercent > 20 {
                        interpolationWarnings.append("High fallback rate in head pose interpolation")
                    }
                    if p95 > 33 {
                        interpolationWarnings.append("Head pose sample spacing too sparse for low-latency interpolation")
                    }
                }
            } catch {
                print("[Orchestrator] Failed to write interpolated head pose mapping: \(error)")
            }
        }
        
        // Write camera calibration
        do {
            try calibrationService.write(to: dir.appendingPathComponent("camera_calibration.json"))
        } catch {
            print("[Orchestrator] No calibration data available: \(error)")
        }
        
        // Write camera mount config
        do {
            try mountService.write(to: dir.appendingPathComponent("camera_mount.json"))
        } catch {
            print("[Orchestrator] Mount config write failed: \(error)")
        }
        
        // Compute QC summary
        let qcSummary = frameQCService?.computeSummary()
        
        // Build metadata
        let endEpochMs = Date().timeIntervalSince1970 * 1000.0
        let durationSec = (endEpochMs - recordingStartEpochMs) / 1000.0
        let totalFrames = videoCaptureService?.frameIndex ?? 0
        let droppedFrames = videoCaptureService?.droppedFrames ?? 0
        let resW = videoCaptureService?.actualResolutionWidth ?? 1920
        let resH = videoCaptureService?.actualResolutionHeight ?? 1080
        
        // FPS excluding gaps
        let avgFPS = computeEffectiveFPS(from: videoCaptureService?.videoTimestamps ?? [])
        
        var warnings: [String] = []
        if !useARKit {
            warnings.append("ARKit head pose was not available on this device")
        }
        if calibrationService.calibration == nil {
            warnings.append("Camera calibration was not captured")
        }
        if droppedFrames > 0 {
            warnings.append("Dropped \(droppedFrames) video frames during recording")
        }
        if !(handLandmarkService?.provides3D ?? false) {
            warnings.append("Hand landmarks are 2D normalized image coords. z=0 is a placeholder, NOT metric depth.")
        }
        if useARKit {
            warnings.append("Video frames sourced from ARKit capturedImage (YCbCr → H.264). Resolution may differ from native camera resolution.")
        }
        if headPoseService?.wasInterrupted == true {
            warnings.append("ARSession was interrupted during recording (app may have gone to background)")
        }
        if let arError = headPoseService?.lastSessionError {
            warnings.append("ARSession error during recording: \(arError.localizedDescription)")
        }
        warnings.append(contentsOf: interpolationWarnings)
        
        let hasEstimatedTS = videoCaptureService?.videoTimestamps.contains { $0.isEstimated } ?? false
        if hasEstimatedTS {
            warnings.append("Some video timestamps are estimated (not from actual frame presentation time)")
        }
        
        let metadata = SessionMetadata(
            sessionId: sessionId,
            startTimeEpochMs: recordingStartEpochMs,
            endTimeEpochMs: endEpochMs,
            durationSec: durationSec,
            environment: SessionMetadata.EnvironmentInfo(
                type: ud.string(forKey: "environment_type") ?? "residential",
                subCategory: ud.string(forKey: "environment_sub") ?? "room_tidy_up",
                country: ud.string(forKey: "country") ?? "US",
                taskDescription: {
                    let desc = ud.string(forKey: "task_description") ?? ""
                    return desc.isEmpty ? nil : desc
                }()
            ),
            device: SessionMetadata.currentDeviceInfo(),
            capture: SessionMetadata.CaptureInfo(
                videoResolutionWidth: resW,
                videoResolutionHeight: resH,
                targetFPS: 30,
                videoCodec: "h264",
                imuTargetHz: 100,
                videoTimestampsEstimated: hasEstimatedTS
            ),
            advancedCapture: SessionMetadata.AdvancedCaptureInfo(
                enabled: true,
                headPoseAvailable: useARKit,
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
                startupSamplesDiscarded: imuCaptureService?.startupDiscarded ?? 0
            ),
            videoMetrics: SessionMetadata.VideoMetrics(
                totalFrames: totalFrames,
                actualAvgFPS: avgFPS,
                droppedFrames: droppedFrames
            ),
            syncMetrics: syncMetrics,
            qcSummary: qcSummary,
            warnings: warnings
        )
        
        do {
            try packagingService.writeMetadata(metadata, to: dir.appendingPathComponent("metadata.json"))
            try packagingService.writeManifest(sessionId: sessionId, sessionDir: dir)
        } catch {
            print("[Orchestrator] Failed to write metadata/manifest: \(error)")
        }
        
        cleanup()
    }
    
    // MARK: - FPS Calculation
    
    private func computeEffectiveFPS(from timestamps: [VideoTimestamp]) -> Double {
        guard timestamps.count > 1 else { return 0 }
        
        let gapThresholdMs: Double = 100.0
        var continuousDurationMs: Double = 0
        var continuousIntervals: Int = 0
        
        for i in 0..<(timestamps.count - 1) {
            let intervalMs = timestamps[i + 1].relativeMs - timestamps[i].relativeMs
            if intervalMs > 0 && intervalMs < gapThresholdMs {
                continuousDurationMs += intervalMs
                continuousIntervals += 1
            }
        }
        
        guard continuousDurationMs > 0 else { return 0 }
        return Double(continuousIntervals) / (continuousDurationMs / 1000.0)
    }
    
    // MARK: - Helpers
    
    private func cleanup() {
        videoCaptureService = nil
        imuCaptureService = nil
        headPoseService = nil
        handLandmarkService = nil
        handPoseService = nil
        facePresenceService = nil
        frameQCService = nil
        previewImage = nil
    }
    
    private func loadHeadPoseSamples(from url: URL) throws -> [HeadPoseSample] {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        return text
            .split(separator: "\n")
            .compactMap { line in
                guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                return try? decoder.decode(HeadPoseSample.self, from: Data(line.utf8))
            }
    }

    private func sanitizeHeadPoseSamples(_ samples: [HeadPoseSample]) -> [ValidatedHeadPoseSample] {
        let cleaned = samples.compactMap { sample -> ValidatedHeadPoseSample? in
            guard sample.timestampNs > 0 else { return nil }
            guard sample.timestampEpochMs.isFinite else { return nil }
            let p = sample.positionMeters
            let q = sample.rotationQuaternion
            guard p.x.isFinite, p.y.isFinite, p.z.isFinite else { return nil }
            guard q.x.isFinite, q.y.isFinite, q.z.isFinite, q.w.isFinite else { return nil }
            return ValidatedHeadPoseSample(
                timestampNs: sample.timestampNs,
                timestampEpochMs: sample.timestampEpochMs,
                position: p,
                rotation: q
            )
        }
        let sorted = cleaned.sorted { $0.timestampNs < $1.timestampNs }
        var monotonic: [ValidatedHeadPoseSample] = []
        var lastNs: Int64?
        for sample in sorted {
            if let previous = lastNs, sample.timestampNs <= previous {
                continue
            }
            monotonic.append(sample)
            lastNs = sample.timestampNs
        }
        return monotonic
    }

    private func interpolateHeadPose(for videoTimestampNs: Int64, samples: [ValidatedHeadPoseSample]) -> InterpolationResult? {
        guard !samples.isEmpty else { return nil }
        if samples.count == 1 {
            let only = samples[0]
            return InterpolationResult(
                poseTimestampNs: only.timestampNs,
                poseTimestampEpochMs: only.timestampEpochMs,
                position: only.position,
                rotation: normalizeQuaternion(only.rotation),
                mode: "nearest_fallback",
                deltaMs: abs(Double(videoTimestampNs - only.timestampNs)) / 1_000_000.0,
                alpha: nil,
                t0Ns: only.timestampNs,
                t1Ns: nil
            )
        }

        if videoTimestampNs <= samples[0].timestampNs {
            let nearest = samples[0]
            return InterpolationResult(
                poseTimestampNs: nearest.timestampNs,
                poseTimestampEpochMs: nearest.timestampEpochMs,
                position: nearest.position,
                rotation: normalizeQuaternion(nearest.rotation),
                mode: "nearest_fallback",
                deltaMs: abs(Double(videoTimestampNs - nearest.timestampNs)) / 1_000_000.0,
                alpha: nil,
                t0Ns: nil,
                t1Ns: nearest.timestampNs
            )
        }
        if videoTimestampNs >= samples[samples.count - 1].timestampNs {
            let nearest = samples[samples.count - 1]
            return InterpolationResult(
                poseTimestampNs: nearest.timestampNs,
                poseTimestampEpochMs: nearest.timestampEpochMs,
                position: nearest.position,
                rotation: normalizeQuaternion(nearest.rotation),
                mode: "nearest_fallback",
                deltaMs: abs(Double(videoTimestampNs - nearest.timestampNs)) / 1_000_000.0,
                alpha: nil,
                t0Ns: nearest.timestampNs,
                t1Ns: nil
            )
        }

        var low = 0
        var high = samples.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let t = samples[mid].timestampNs
            if t == videoTimestampNs {
                let exact = samples[mid]
                return InterpolationResult(
                    poseTimestampNs: exact.timestampNs,
                    poseTimestampEpochMs: exact.timestampEpochMs,
                    position: exact.position,
                    rotation: normalizeQuaternion(exact.rotation),
                    mode: "interpolated",
                    deltaMs: 0,
                    alpha: 0,
                    t0Ns: exact.timestampNs,
                    t1Ns: exact.timestampNs
                )
            } else if t < videoTimestampNs {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        let rightIndex = min(max(low, 1), samples.count - 1)
        let leftIndex = rightIndex - 1
        let left = samples[leftIndex]
        let right = samples[rightIndex]
        guard right.timestampNs > left.timestampNs else { return nil }

        let alpha = Double(videoTimestampNs - left.timestampNs) / Double(right.timestampNs - left.timestampNs)
        let clampedAlpha = min(max(alpha, 0), 1)
        let interpPosition = lerpPosition(left.position, right.position, alpha: clampedAlpha)
        let interpRotation = slerp(left.rotation, right.rotation, alpha: clampedAlpha)
        let interpEpochMs = left.timestampEpochMs + (right.timestampEpochMs - left.timestampEpochMs) * clampedAlpha

        return InterpolationResult(
            poseTimestampNs: videoTimestampNs,
            poseTimestampEpochMs: interpEpochMs,
            position: interpPosition,
            rotation: interpRotation,
            mode: "interpolated",
            deltaMs: 0,
            alpha: clampedAlpha,
            t0Ns: left.timestampNs,
            t1Ns: right.timestampNs
        )
    }

    private func lerpPosition(_ a: HeadPoseSample.Position, _ b: HeadPoseSample.Position, alpha: Double) -> HeadPoseSample.Position {
        HeadPoseSample.Position(
            x: a.x + (b.x - a.x) * alpha,
            y: a.y + (b.y - a.y) * alpha,
            z: a.z + (b.z - a.z) * alpha
        )
    }

    private func normalizeQuaternion(_ q: HeadPoseSample.Quaternion) -> HeadPoseSample.Quaternion {
        let len = sqrt(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w)
        guard len > 0 else { return HeadPoseSample.Quaternion(x: 0, y: 0, z: 0, w: 1) }
        return HeadPoseSample.Quaternion(x: q.x / len, y: q.y / len, z: q.z / len, w: q.w / len)
    }

    private func slerp(_ q0In: HeadPoseSample.Quaternion, _ q1In: HeadPoseSample.Quaternion, alpha: Double) -> HeadPoseSample.Quaternion {
        var q0 = normalizeQuaternion(q0In)
        var q1 = normalizeQuaternion(q1In)
        var dot = q0.x * q1.x + q0.y * q1.y + q0.z * q1.z + q0.w * q1.w

        if dot < 0 {
            q1 = HeadPoseSample.Quaternion(x: -q1.x, y: -q1.y, z: -q1.z, w: -q1.w)
            dot = -dot
        }

        if dot > 0.9995 {
            let nlerp = HeadPoseSample.Quaternion(
                x: q0.x + (q1.x - q0.x) * alpha,
                y: q0.y + (q1.y - q0.y) * alpha,
                z: q0.z + (q1.z - q0.z) * alpha,
                w: q0.w + (q1.w - q0.w) * alpha
            )
            return normalizeQuaternion(nlerp)
        }

        let theta0 = acos(max(-1, min(1, dot)))
        let theta = theta0 * alpha
        let sinTheta = sin(theta)
        let sinTheta0 = sin(theta0)
        guard sinTheta0 != 0 else { return normalizeQuaternion(q0) }

        let s0 = cos(theta) - dot * sinTheta / sinTheta0
        let s1 = sinTheta / sinTheta0
        return normalizeQuaternion(
            HeadPoseSample.Quaternion(
                x: s0 * q0.x + s1 * q1.x,
                y: s0 * q0.y + s1 * q1.y,
                z: s0 * q0.z + s1 * q1.z,
                w: s0 * q0.w + s1 * q1.w
            )
        )
    }

    private func percentile(_ sorted: [Double], p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let clamped = min(max(p, 0), 1)
        let idx = Int(Double(sorted.count - 1) * clamped)
        return sorted[idx]
    }

    private func ensureCameraPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted {
                await MainActor.run {
                    self.lastError = "Camera permission denied. Enable camera access in Settings > Privacy > Camera."
                    self.statusMessage = "Camera permission required"
                }
            }
            return granted
        case .denied, .restricted:
            await MainActor.run {
                self.lastError = "Camera permission denied. Enable camera access in Settings > Privacy > Camera."
                self.statusMessage = "Camera permission required"
            }
            return false
        @unknown default:
            await MainActor.run {
                self.lastError = "Unable to determine camera permission state."
                self.statusMessage = "Permission error"
            }
            return false
        }
    }

    nonisolated private static func previewImage(from pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let rect = CGRect(
            x: 0,
            y: 0,
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(ciImage, from: rect) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - VideoCaptureDelegate

extension RecordingOrchestrator: VideoCaptureDelegate {
    nonisolated func videoCaptureService(
        _ service: VideoCaptureService,
        didOutputPixelBuffer pixelBuffer: CVPixelBuffer,
        relativeMs: Double,
        frameIndex: Int
    ) {
        Task { @MainActor [weak self] in
            self?.frameCount = frameIndex
        }

        if frameIndex % 5 == 0 {
            let preview = Self.previewImage(from: pixelBuffer)
            Task { @MainActor [weak self] in
                self?.previewImage = preview
            }
        }
        
        guard frameIndex % visionStride == 0 else { return }
        
        visionQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.handLandmarkService?.processFrame(
                pixelBuffer: pixelBuffer,
                frameIndex: frameIndex,
                relativeMs: relativeMs
            )
            
            if let landmarkResult = self.handLandmarkService?.lastResult {
                self.handPoseService?.deriveFromLandmarks(landmarkResult)
            }
            
            self.facePresenceService?.processFrame(
                pixelBuffer: pixelBuffer,
                frameIndex: frameIndex,
                relativeMs: relativeMs
            )
            
            let handDetected = !(self.handLandmarkService?.lastResult?.hands.isEmpty ?? true)
            let faceDetected = self.facePresenceService?.lastFaceDetected ?? false
            
            self.frameQCService?.processFrame(
                pixelBuffer: pixelBuffer,
                frameIndex: frameIndex,
                relativeMs: relativeMs,
                handDetected: handDetected,
                faceDetected: faceDetected
            )
        }
    }
}
