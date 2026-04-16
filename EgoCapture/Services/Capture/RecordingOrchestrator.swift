import Foundation
import UIKit
import CoreVideo
import AVFoundation
import CoreImage

private let kPipelineVersion = "4.2.0"
private let kPipelineBuild = "context-mode-maxfov"

fileprivate final class VisionCaptureBridge: @unchecked Sendable {
    let visionStride: Int
    weak var handLandmark: HandLandmarkService?
    weak var handPose: HandPoseDerivationService?
    weak var handLandmarkMP: HandLandmarkService?
    weak var handPoseMP: HandPoseDerivationService?
    weak var facePresence: FacePresenceService?
    weak var frameQC: FrameQCService?

    init(
        visionStride: Int,
        handLandmark: HandLandmarkService?,
        handPose: HandPoseDerivationService?,
        handLandmarkMP: HandLandmarkService?,
        handPoseMP: HandPoseDerivationService?,
        facePresence: FacePresenceService?,
        frameQC: FrameQCService?
    ) {
        self.visionStride = visionStride
        self.handLandmark = handLandmark
        self.handPose = handPose
        self.handLandmarkMP = handLandmarkMP
        self.handPoseMP = handPoseMP
        self.facePresence = facePresence
        self.frameQC = frameQC
    }
}

@MainActor
final class RecordingOrchestrator: ObservableObject {

    // MARK: - Fused Hand Pose (camera-space only)

    private struct FusedHandPoseEntry: Codable {
        let frameIndex: Int
        let timestampNs: UInt64
        let hands: [FusedHand]
    }

    private struct FusedHand: Codable {
        let handedness: String
        let confidence: Double
        let coordinateSystem: String
        let depthType: String
        let landmarks3D: [FusedLandmark3D]
    }

    private struct FusedLandmark3D: Codable {
        let id: Int
        let x: Double
        let y: Double
        let z: Double
    }

    private struct HandTrackingComparisonDebug: Codable {
        let sessionId: String
        let backendMode: String
        let appleVisionFrameCount: Int
        let mediaPipeFrameCount: Int
        let appleVisionCoveragePercent: Double
        let mediaPipeCoveragePercent: Double
        let fallbackEnabled: Bool
        let notes: [String]
    }

    /// Best-of selection output row
    private struct BestOfLandmarkEntry: Codable {
        let frameIndex: Int
        let timestampNs: UInt64
        let selectedSource: String
        let hands: [HandLandmarkSample.DetectedHand]
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

    private var handLandmarkService: HandLandmarkService?
    private var handPoseService: HandPoseDerivationService?
    private var handLandmarkMediaPipeService: HandLandmarkService?
    private var handPoseMediaPipeService: HandPoseDerivationService?
    private var facePresenceService: FacePresenceService?
    private var frameQCService: FrameQCService?

    private let packagingService = SessionPackagingService()

    private var sessionDir: URL?
    private var recordingStartEpochMs: Double = 0
    private var durationTimer: Timer?

    private let visionQueue = DispatchQueue(label: "com.egocapture.vision", qos: .userInitiated)
    private let mediaPipeQueue = DispatchQueue(label: "com.egocapture.vision.mediapipe", qos: .utility)
    private let visionStride = 3

    nonisolated(unsafe) private var visionCaptureBridge: VisionCaptureBridge?

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
        lastError = nil; previewImage = nil; statusMessage = "Starting..."
        UIApplication.shared.isIdleTimerDisabled = true
        let session = SessionManager.shared.createSession()
        currentSessionId = session.id; sessionDir = session.directory
        recordingStartEpochMs = Date().timeIntervalSince1970 * 1000.0
        let dir = session.directory

        do {
            // IMU
            let imu = IMUCaptureService()
            try imu.start(outputURL: dir.appendingPathComponent("imu.jsonl"), epochStartMs: recordingStartEpochMs)
            imuCaptureService = imu

            // Context Mode: always run both backends
            // MediaPipe = primary, Apple Vision = fallback
            let hl = HandLandmarkService(backend: AppleVisionHandBackend())
            try hl.start(outputURL: dir.appendingPathComponent("hand_landmarks.jsonl"), epochStartMs: recordingStartEpochMs)
            handLandmarkService = hl
            let hp = HandPoseDerivationService(has3DLandmarks: hl.provides3D, sourceName: hl.backendName)
            try hp.start(outputURL: dir.appendingPathComponent("hand_pose.jsonl"), epochStartMs: recordingStartEpochMs)
            handPoseService = hp

            let mediaPipeBackend = MediaPipeHandBackend()
            mediaPipeBackend.onDebugInputFrame = { [weak self] image in
                Task { @MainActor [weak self] in self?.previewImage = image }
            }
            let hlMP = HandLandmarkService(backend: mediaPipeBackend)
            try hlMP.start(outputURL: dir.appendingPathComponent("hand_landmarks_mediapipe.jsonl"), epochStartMs: recordingStartEpochMs)
            handLandmarkMediaPipeService = hlMP
            let hpMP = HandPoseDerivationService(has3DLandmarks: hlMP.provides3D, sourceName: hlMP.backendName)
            try hpMP.start(outputURL: dir.appendingPathComponent("hand_pose_mediapipe.jsonl"), epochStartMs: recordingStartEpochMs)
            handPoseMediaPipeService = hpMP

            let fp = FacePresenceService()
            try fp.start(outputURL: dir.appendingPathComponent("face_presence.jsonl"), epochStartMs: recordingStartEpochMs)
            facePresenceService = fp
            let qc = FrameQCService()
            try qc.start(outputURL: dir.appendingPathComponent("frame_qc_metrics.jsonl"), epochStartMs: recordingStartEpochMs)
            frameQCService = qc

            visionCaptureBridge = VisionCaptureBridge(
                visionStride: visionStride,
                handLandmark: handLandmarkService,
                handPose: handPoseService,
                handLandmarkMP: handLandmarkMediaPipeService,
                handPoseMP: handPoseMediaPipeService,
                facePresence: facePresenceService,
                frameQC: frameQCService
            )

            // Video — AVCaptureSession, ultra-wide preferred, stability-optimized resolution
            let video = VideoCaptureService(outputURL: dir.appendingPathComponent("video.mp4"))
            video.delegate = self; videoCaptureService = video
            try video.setup()
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
        handLandmarkService?.stop(); handPoseService?.stop()
        handLandmarkMediaPipeService?.stop(); handPoseMediaPipeService?.stop()
        facePresenceService?.stop(); frameQCService?.stop()

        let videoTS = videoCaptureService?.videoTimestamps ?? []

        // 1. Write video_timestamps.jsonl
        if !videoTS.isEmpty {
            do { let w = try JSONLWriter(fileURL: dir.appendingPathComponent("video_timestamps.jsonl")); for t in videoTS { w.append(t) }; w.close() } catch {}
        }

        // 2. IMU↔video sync
        let imuVideoSync = SyncAnalysisService.computeIMUVideoSync(
            videoTimestamps: videoTS,
            imuTimestampsNs: imuCaptureService?.allTimestampsNs ?? []
        )

        // 3. Build fused hand pose (camera-space only) + best-of selection
        var fusionWarnings: [String] = []
        var fusedHandPoseWritten = false
        var bestOfStats = SessionMetadata.BestOfStats(totalFrames: 0, mediaPipeSelected: 0, appleVisionSelected: 0, noneSelected: 0)

        do {
            let mediapipeURL = dir.appendingPathComponent("hand_landmarks_mediapipe.jsonl")
            let appleURL = dir.appendingPathComponent("hand_landmarks.jsonl")
            let mediaPipeRows = try loadHandLandmarkSamples(from: mediapipeURL)
            let appleRows = try loadHandLandmarkSamples(from: appleURL)
            let mediaPipeByFrame = Dictionary(mediaPipeRows.map { ($0.frameIndex, $0) }, uniquingKeysWith: { _, new in new })
            let appleByFrame = Dictionary(appleRows.map { ($0.frameIndex, $0) }, uniquingKeysWith: { _, new in new })

            let imageWidth = Double(max(1, videoCaptureService?.actualResolutionWidth ?? 1920))
            let imageHeight = Double(max(1, videoCaptureService?.actualResolutionHeight ?? 1080))
            let depthScale = (ud.object(forKey: "fused_hand_depth_scale") != nil) ? max(0.05, ud.double(forKey: "fused_hand_depth_scale")) : 0.5

            var fusedFrameCount = 0
            var fusedFramesWithHands = 0
            var badValueCount = 0
            var timestampMismatchCount = 0
            let fusedWriter = try JSONLWriter(fileURL: dir.appendingPathComponent("fused_hand_pose.jsonl"))
            let bestOfWriter = try JSONLWriter(fileURL: dir.appendingPathComponent("hand_landmarks_best.jsonl"))

            var boTotal = 0, boMP = 0, boAV = 0, boNone = 0
            let mpConfidenceThreshold = 0.3

            for frame in videoTS.sorted(by: { $0.frameIndex < $1.frameIndex }) {
                let mpRow = mediaPipeByFrame[frame.frameIndex]
                let avRow = appleByFrame[frame.frameIndex]

                if let mpRow, abs(Int64(mpRow.timestampNs) - Int64(frame.timestampNs)) > 5_000_000 {
                    timestampMismatchCount += 1
                }

                // --- Best-of selection ---
                let mpHasHands = mpRow.map { !$0.hands.isEmpty && $0.hands.contains { $0.confidence >= mpConfidenceThreshold } } ?? false
                let avHasHands = avRow.map { !$0.hands.isEmpty } ?? false

                let selectedSource: String
                let selectedHands: [HandLandmarkSample.DetectedHand]
                if mpHasHands {
                    selectedSource = "mediapipe"
                    selectedHands = mpRow!.hands
                    boMP += 1
                } else if avHasHands {
                    selectedSource = "apple_vision"
                    selectedHands = avRow!.hands
                    boAV += 1
                } else {
                    selectedSource = "none"
                    selectedHands = []
                    boNone += 1
                }
                boTotal += 1

                bestOfWriter.append(BestOfLandmarkEntry(
                    frameIndex: frame.frameIndex,
                    timestampNs: frame.timestampNs,
                    selectedSource: selectedSource,
                    hands: selectedHands
                ))

                // --- Fused hand pose from best source ---
                let sourceHands = selectedHands
                var fusedHands: [FusedHand] = []
                for hand in sourceHands {
                    var landmarks: [FusedLandmark3D] = []
                    for lm in hand.landmarks {
                        let px = lm.x * imageWidth
                        let py = lm.y * imageHeight
                        let nx = px / imageWidth
                        let ny = py / imageHeight
                        let depth = max(0.01, depthScale * abs(lm.z))

                        let x = nx * depth
                        let y = ny * depth
                        let z = depth
                        guard x.isFinite, y.isFinite, z.isFinite else { badValueCount += 1; continue }
                        landmarks.append(FusedLandmark3D(id: lm.id, x: x, y: y, z: z))
                    }
                    fusedHands.append(FusedHand(
                        handedness: hand.handedness, confidence: hand.confidence,
                        coordinateSystem: "camera_relative", depthType: "relative_normalized",
                        landmarks3D: landmarks
                    ))
                }

                fusedWriter.append(FusedHandPoseEntry(frameIndex: frame.frameIndex, timestampNs: frame.timestampNs, hands: fusedHands))
                fusedFrameCount += 1
                if !fusedHands.isEmpty { fusedFramesWithHands += 1 }
            }
            fusedWriter.close()
            bestOfWriter.close()
            fusedHandPoseWritten = fusedFrameCount > 0
            bestOfStats = SessionMetadata.BestOfStats(totalFrames: boTotal, mediaPipeSelected: boMP, appleVisionSelected: boAV, noneSelected: boNone)

            if badValueCount > 0 { fusionWarnings.append("Fused hand pose skipped \(badValueCount) invalid landmark values.") }
            if timestampMismatchCount > 0 { fusionWarnings.append("Found \(timestampMismatchCount) timestamp mismatches between video and MediaPipe rows.") }
            if fusedFramesWithHands == 0 && !videoTS.isEmpty { fusionWarnings.append("No hands detected; check MediaPipe model.") }
        } catch {
            fusionWarnings.append("Failed to write fused/best-of files: \(error.localizedDescription)")
        }

        // 4. Compute metrics
        let qcSummary = frameQCService?.computeSummary()
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
        let selectedFormatDescription = videoCaptureService?.selectedFormatDescription ?? "unknown"
        let usedUltraWide = videoCaptureService?.usedUltraWide ?? false
        let exposurePolicy = videoCaptureService?.exposurePolicy ?? "default"
        let fovMode = videoCaptureService?.fovMode ?? "hardware"
        let fovTargetAchieved = videoCaptureService?.fovTargetAchieved ?? false
        let diagonalFovDeg = videoCaptureService?.diagonalFovDeg
        let deviceMaxHorizontalFov = videoCaptureService?.deviceMaxFov

        // Write full format diagnostics for inspection
        videoCaptureService?.writeDiagnostics(to: dir)

        let appleProcessed = handLandmarkService?.processedFrameCount ?? 0
        let mediaPipeProcessed = handLandmarkMediaPipeService?.processedFrameCount ?? 0

        // Context Mode validation warnings
        var warnings: [String] = []
        if droppedFrames > 5 { warnings.append("droppedFrames=\(droppedFrames) exceeds context-mode target of ≤5") }
        if !isLandscape { warnings.append("Video orientation inconsistent with landscape lock.") }
        if !(handLandmarkMediaPipeService?.provides3D ?? false) {
            warnings.append("MediaPipe z-values are normalized depth, not metric 3D.")
        }
        if mediaPipeProcessed > 0 && (handLandmarkMediaPipeService?.framesWithHands ?? 0) == 0 {
            warnings.append("MediaPipe produced no hand detections. Verify model asset.")
        }
        if imuVideoSync.confidence == "low" { warnings.append("IMU↔video sync confidence is low.") }
        if !usedUltraWide { warnings.append("Ultra-wide camera not available; fell back to wide.") }
        if let hFov = cameraActualFovDeg {
            if fovTargetAchieved {
                warnings.append("wide_fov_target_achieved: diagonal ≈\(String(format: "%.0f", diagonalFovDeg ?? 0))° (horizontal=\(String(format: "%.1f", hFov))°)")
            } else if hFov >= 105 {
                warnings.append("FOV stable: horizontal=\(String(format: "%.1f", hFov))°, diagonal≈\(String(format: "%.0f", diagonalFovDeg ?? 0))°. Device max horizontal=\(String(format: "%.1f", deviceMaxHorizontalFov ?? hFov))°")
            } else {
                warnings.append("actualFovDeg=\(String(format: "%.1f", hFov))° is below 105° minimum for context mode.")
            }
        }
        if appleProcessed == 0 {
            warnings.append("Apple Vision fallback processed 0 frames; fallback coverage is 0.")
        }
        warnings.append(contentsOf: fusionWarnings)

        // Hand tracking comparison
        let appleCoverage = appleProcessed > 0 ? (Double(handLandmarkService?.framesWithHands ?? 0) * 100.0 / Double(appleProcessed)) : 0
        let mediaPipeCoverage = mediaPipeProcessed > 0 ? (Double(handLandmarkMediaPipeService?.framesWithHands ?? 0) * 100.0 / Double(mediaPipeProcessed)) : 0
        let appleAvgHands = appleProcessed > 0 ? Double(handLandmarkService?.totalHandsDetected ?? 0) / Double(appleProcessed) : 0
        let mediaPipeAvgHands = mediaPipeProcessed > 0 ? Double(handLandmarkMediaPipeService?.totalHandsDetected ?? 0) / Double(mediaPipeProcessed) : 0
        let appleAvgConfidence = { let v = handLandmarkService?.confidenceSamples ?? []; return v.isEmpty ? 0 : v.reduce(0, +) / Double(v.count) }()
        let mediaPipeAvgConfidence = { let v = handLandmarkMediaPipeService?.confidenceSamples ?? []; return v.isEmpty ? 0 : v.reduce(0, +) / Double(v.count) }()

        var comparisonNotes: [String] = []
        let coverageWinner: String
        if appleProcessed == 0 && mediaPipeProcessed == 0 { coverageWinner = "unknown" }
        else if abs(appleCoverage - mediaPipeCoverage) < 1.0 { coverageWinner = "tie" }
        else if appleCoverage > mediaPipeCoverage { coverageWinner = "apple_vision"; comparisonNotes.append("Apple Vision produced denser coverage.") }
        else { coverageWinner = "mediapipe"; comparisonNotes.append("MediaPipe produced denser coverage.") }

        let handTrackingComparison = SessionMetadata.HandTrackingComparison(
            appleVisionCoveragePercent: appleCoverage, mediaPipeCoveragePercent: mediaPipeCoverage,
            appleVisionFrameCount: appleProcessed, mediaPipeFrameCount: mediaPipeProcessed,
            appleVisionAverageHandsPerFrame: appleAvgHands, mediaPipeAverageHandsPerFrame: mediaPipeAvgHands,
            appleVisionAverageConfidence: appleAvgConfidence, mediaPipeAverageConfidence: mediaPipeAvgConfidence,
            coverageWinner: coverageWinner,
            fallbackEnabled: true,
            bestOfFrames: bestOfStats,
            notes: comparisonNotes
        )

        let syncMetrics = SessionMetadata.SyncMetrics(
            imuToVideoEstimatedOffsetMs: imuVideoSync.estimatedOffsetMs,
            imuToVideoSyncMethod: imuVideoSync.method,
            imuToVideoSyncConfidence: imuVideoSync.confidence
        )

        let validation = validateSession(videoFrames: totalFrames, imuSamples: imuCaptureService?.totalSamples ?? 0,
                                         durationSec: durationSec, videoTimestamps: videoTS,
                                         droppedFrames: droppedFrames, usedUltraWide: usedUltraWide,
                                         actualFovDeg: cameraActualFovDeg, diagonalFovDeg: diagonalFovDeg,
                                         avgFPS: avgFPS,
                                         mediaPipeCoverage: mediaPipeCoverage, appleCoverage: appleCoverage)

        let cameraSource = usedUltraWide ? "avcapture_ultrawide" : "avcapture_wide"

        let metadata = SessionMetadata(
            sessionId: sessionId, startTimeEpochMs: recordingStartEpochMs, endTimeEpochMs: endEpochMs, durationSec: durationSec,
            environment: SessionMetadata.EnvironmentInfo(
                type: ud.string(forKey: "environment_type") ?? "residential",
                subCategory: ud.string(forKey: "environment_sub") ?? "room_tidy_up",
                country: ud.string(forKey: "country") ?? "US",
                taskDescription: { let d = ud.string(forKey: "task_description") ?? ""; return d.isEmpty ? nil : d }()
            ),
            device: SessionMetadata.currentDeviceInfo(),
            capture: SessionMetadata.CaptureInfo(
                videoResolutionWidth: resW, videoResolutionHeight: resH, targetFPS: 30, videoCodec: "h264",
                imuTargetHz: 100, videoTimestampsEstimated: videoTS.contains { $0.isEstimated },
                orientationLocked: videoCaptureService?.orientationLocked ?? true,
                orientation: videoCaptureService?.orientation ?? "landscape",
                timestampClock: "mach_absolute_time", epochToMonotonicPrecision: "~1ms (single reference point)"
            ),
            camera: SessionMetadata.CameraInfo(
                selectedLens: selectedLens, actualFovDeg: cameraActualFovDeg,
                diagonalFovDeg: diagonalFovDeg,
                deviceMaxHorizontalFov: deviceMaxHorizontalFov,
                fovSource: cameraFovSource, fovMode: fovMode,
                fovTargetAchieved: fovTargetAchieved,
                fovNote: (cameraActualFovDeg ?? 0) < 115
                    ? "videoFieldOfView reports horizontal FOV. Apple's 120° ultra-wide spec is diagonal. ~106° horizontal ≈ ~\(String(format: "%.0f", diagonalFovDeg ?? 0))° diagonal."
                    : nil,
                selectedFormatDescription: selectedFormatDescription,
                usedUltraWide: usedUltraWide, exposurePolicy: exposurePolicy
            ),
            captureProfile: SessionMetadata.CaptureProfile(
                mode: "context", headPose: false, worldTracking: false,
                depthType: "none", cameraSource: cameraSource
            ),
            contextTracking: SessionMetadata.ContextTracking(
                primaryHandTracker: "mediapipe",
                trackingPriority: "recall",
                fallbackEnabled: true,
                fallbackTracker: "apple_vision",
                bestOfSelectionEnabled: true,
                mediaPipeMinDetectionConfidence: 0.3,
                mediaPipeMinTrackingConfidence: 0.3
            ),
            semanticArtifacts: SessionMetadata.SemanticArtifactInfo(
                hasHandLandmarks: ((handLandmarkService?.rowCount ?? 0) + (handLandmarkMediaPipeService?.rowCount ?? 0)) > 0,
                handLandmarkSource: "both",
                hasHandPose: ((handPoseService?.rowCount ?? 0) + (handPoseMediaPipeService?.rowCount ?? 0)) > 0,
                hasFacePresence: (facePresenceService?.rowCount ?? 0) > 0,
                hasFrameQcMetrics: (frameQCService?.rowCount ?? 0) > 0,
                handLandmarksAre3D: false,
                handLandmarksZType: "normalized"
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
            syncMetrics: syncMetrics, handTrackingComparison: handTrackingComparison,
            fusedArtifacts: SessionMetadata.FusedArtifacts(
                hasFusedHandPose: fusedHandPoseWritten,
                fusedDepthType: "relative_normalized",
                fusionMethod: "best_of_normalized_depth",
                isMetric3D: false
            ),
            captureHealth: SessionMetadata.CaptureHealth(
                videoBackpressureEvents: videoCaptureService?.backpressureEvents ?? 0,
                imuLagEvents: imuCaptureService?.lagEventCount ?? 0,
                droppedFrames: droppedFrames
            ),
            coordinateSystem: .cameraDefault,
            pipeline: SessionMetadata.PipelineInfo(
                version: kPipelineVersion, build: kPipelineBuild,
                captureMode: "avfoundation_context",
                threadModel: "multi-queue", timestampSource: "mach_absolute_time"
            ),
            validation: validation, qcSummary: qcSummary, warnings: warnings
        )

        do { try packagingService.writeMetadata(metadata, to: dir.appendingPathComponent("metadata.json")) } catch {}

        // Technical validation
        let techVal = TechnicalValidation(
            sessionId: sessionId,
            timing: TechnicalValidation.Timing(
                videoToHeadPoseAvgDeltaMs: nil, videoToHeadPoseMaxDeltaMs: nil,
                videoToHeadPoseP95DeltaMs: nil, imuToVideoEstimatedOffsetMs: imuVideoSync.estimatedOffsetMs
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
            pose: TechnicalValidation.Pose(
                headPoseCoveragePercent: 0,
                imuPoseAngularErrorMeanDeg: nil, imuPoseAngularErrorMedianDeg: nil,
                imuPoseAngularErrorP95Deg: nil, imuPoseAngularErrorMaxDeg: nil,
                skippedTrackingLossSamples: 0, consistencyConfidence: "n/a", trackingLossFrames: 0
            ),
            calibration: TechnicalValidation.Calibration(
                intrinsicsAvailable: false, distortionAvailable: false,
                mountVerified: false, mountCalibrationErrorDeg: nil
            ),
            passCriteria: TechnicalValidation.PassCriteria(
                videoStable: avgFPS >= 19.8 && (videoCaptureService?.frameIntervalStdDevMs ?? 999) < 10,
                imuStable: (imuCaptureService?.actualSampleRateHz ?? 0) >= 90 && (imuCaptureService?.sampleIntervalStdDevMs ?? 999) < 2,
                syncAcceptable: true,
                calibrationAcceptable: true
            )
        )
        do { try JSONFileWriter.write(techVal, to: dir.appendingPathComponent("technical_validation.json")) } catch {}

        let comparisonDebug = HandTrackingComparisonDebug(
            sessionId: sessionId, backendMode: "both",
            appleVisionFrameCount: appleProcessed, mediaPipeFrameCount: mediaPipeProcessed,
            appleVisionCoveragePercent: appleCoverage, mediaPipeCoveragePercent: mediaPipeCoverage,
            fallbackEnabled: true,
            notes: comparisonNotes
        )
        do { try JSONFileWriter.write(comparisonDebug, to: dir.appendingPathComponent("hand_tracking_comparison.json")) } catch {}

        do { try packagingService.writeManifest(sessionId: sessionId, sessionDir: dir) } catch {}

        cleanup()
    }

    // MARK: - Validation

    private func validateSession(
        videoFrames: Int, imuSamples: Int, durationSec: Double, videoTimestamps: [VideoTimestamp],
        droppedFrames: Int, usedUltraWide: Bool, actualFovDeg: Double?, diagonalFovDeg: Double?,
        avgFPS: Double, mediaPipeCoverage: Double, appleCoverage: Double
    ) -> SessionMetadata.ValidationResult {
        var issues: [String] = []
        let expectedIMU = durationSec * 100
        let imuCov = expectedIMU > 0 ? min(Double(imuSamples) / expectedIMU * 100, 100) : 0
        if imuCov < 90 { issues.append("IMU coverage \(String(format: "%.1f", imuCov))% < 90%") }
        var mono = true
        for i in 1..<videoTimestamps.count {
            if videoTimestamps[i].timestampNs <= videoTimestamps[i-1].timestampNs { mono = false; issues.append("Non-monotonic timestamp at frame \(i)"); break }
        }

        // Context Mode validation: use diagonal FOV for the 120° target
        if !usedUltraWide { issues.append("WARN: usedUltraWide=false") }
        if let hFov = actualFovDeg {
            let dFov = diagonalFovDeg ?? hFov
            if hFov < 100 { issues.append("WARN: horizontal FOV=\(String(format: "%.1f", hFov))° < 100°") }
            if dFov >= 120 { issues.append("OK: diagonal_fov_target_achieved (\(String(format: "%.1f", dFov))°)") }
            else if dFov >= 110 { issues.append("INFO: diagonal FOV=\(String(format: "%.1f", dFov))° approaching 120° target") }
        }
        if droppedFrames > 5 { issues.append("WARN: droppedFrames=\(droppedFrames) > 5") }
        if avgFPS < 25 { issues.append("WARN: actualAvgFPS=\(String(format: "%.1f", avgFPS)) < 25") }
        if mediaPipeCoverage < 85 { issues.append("WARN: mediaPipeCoverage=\(String(format: "%.1f", mediaPipeCoverage))% < 85%") }
        if appleCoverage == 0 { issues.append("WARN: appleCoverage=0% (fallback inactive)") }

        return SessionMetadata.ValidationResult(frameCountConsistent: true, imuCoveragePercent: imuCov, timestampsMonotonic: mono, issues: issues)
    }

    // MARK: - Helpers

    private func computeEffectiveFPS(from ts: [VideoTimestamp]) -> Double {
        guard ts.count > 1 else { return 0 }
        var d: Double = 0; var n = 0
        for i in 0..<(ts.count-1) { let iv = ts[i+1].relativeMs - ts[i].relativeMs; if iv > 0 && iv < 100 { d += iv; n += 1 } }
        return d > 0 ? Double(n) / (d / 1000.0) : 0
    }

    private func loadHandLandmarkSamples(from url: URL) throws -> [HandLandmarkSample] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        return text.split(separator: "\n").compactMap { line in
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return try? decoder.decode(HandLandmarkSample.self, from: Data(line.utf8))
        }
    }

    private func cleanup() {
        visionCaptureBridge = nil
        videoCaptureService = nil; imuCaptureService = nil
        handLandmarkService = nil; handPoseService = nil
        handLandmarkMediaPipeService = nil; handPoseMediaPipeService = nil
        facePresenceService = nil; frameQCService = nil; previewImage = nil
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

    nonisolated private static let sharedCIContext = CIContext(options: [.cacheIntermediates: false])

    nonisolated private static func previewImage(from pb: CVPixelBuffer) -> UIImage? {
        let ci = CIImage(cvPixelBuffer: pb)
        let rect = CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(pb), height: CVPixelBufferGetHeight(pb))
        guard let cg = sharedCIContext.createCGImage(ci, from: rect) else { return nil }
        return UIImage(cgImage: cg, scale: 1.0, orientation: .up)
    }
}

// MARK: - Video Frame Dispatch

extension RecordingOrchestrator: VideoCaptureDelegate {
    nonisolated func videoCaptureService(_ service: VideoCaptureService, didOutputPixelBuffer pixelBuffer: CVPixelBuffer, relativeMs: Double, timestampNs: UInt64, frameIndex: Int) {
        Task { @MainActor [weak self] in self?.frameCount = frameIndex }
        if frameIndex % 5 == 0 { let p = Self.previewImage(from: pixelBuffer); Task { @MainActor [weak self] in self?.previewImage = p } }
        guard let bridge = visionCaptureBridge else { return }

        // MediaPipe: primary tracker — runs on every frame
        if bridge.handLandmarkMP != nil {
            mediaPipeQueue.async {
                bridge.handLandmarkMP?.processFrame(pixelBuffer: pixelBuffer, frameIndex: frameIndex, relativeMs: relativeMs, timestampNs: timestampNs)
                if let r = bridge.handLandmarkMP?.lastResult { bridge.handPoseMP?.deriveFromLandmarks(r) }
            }
        }

        // Apple Vision: fallback — runs when MediaPipe's latest result had no hands,
        // and also on strided frames for baseline comparison
        let mpHadNoHands = bridge.handLandmarkMP?.lastResult?.hands.isEmpty ?? true
        let isFallbackFrame = mpHadNoHands
        let isStridedFrame = frameIndex % bridge.visionStride == 0

        guard isFallbackFrame || isStridedFrame else { return }
        visionQueue.async {
            bridge.handLandmark?.processFrame(pixelBuffer: pixelBuffer, frameIndex: frameIndex, relativeMs: relativeMs, timestampNs: timestampNs)
            if let r = bridge.handLandmark?.lastResult { bridge.handPose?.deriveFromLandmarks(r) }
            bridge.facePresence?.processFrame(pixelBuffer: pixelBuffer, frameIndex: frameIndex, relativeMs: relativeMs)
            let appleDetected = !(bridge.handLandmark?.lastResult?.hands.isEmpty ?? true)
            let mpDetected = !(bridge.handLandmarkMP?.lastResult?.hands.isEmpty ?? true)
            bridge.frameQC?.processFrame(pixelBuffer: pixelBuffer, frameIndex: frameIndex, relativeMs: relativeMs,
                                          handDetected: appleDetected || mpDetected, faceDetected: bridge.facePresence?.lastFaceDetected ?? false)
        }
    }
}
