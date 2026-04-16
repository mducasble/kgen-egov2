import Foundation
import UIKit
import CoreVideo
import AVFoundation
import ARKit
import CoreImage
import simd

private let kPipelineVersion = "3.0.0"
private let kPipelineBuild = "phase2-precision"

/// Holds weak refs for the video callback path (`VideoCaptureDelegate` is `nonisolated` and runs off the main actor).
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
    private struct HeadPoseVideoMapEntry: Codable {
        let frameIndex: Int
        let videoTimestampEpochMs: Double
        let videoTimestampNs: UInt64
        let headPoseTimestampEpochMs: Double?
        let headPoseTimestampNs: UInt64?
        let mappingMode: String
        let deltaMs: Double
        let interpAlpha: Double?
    }

    private struct HeadPoseInterpolatedEntry: Codable {
        let frameIndex: Int
        let videoTimestampEpochMs: Double
        let videoTimestampNs: UInt64
        let positionMeters: HeadPoseSample.Position
        let rotationQuaternion: HeadPoseSample.Quaternion
        let source: String
        let interpAlpha: Double?
        let bracketingSamples: BracketingSamples
    }

    private struct BracketingSamples: Codable {
        let t0Ns: UInt64?
        let t1Ns: UInt64?
    }

    private struct PosePoint {
        let timestampNs: UInt64
        let timestampEpochMs: Double
        let position: HeadPoseSample.Position
        let rotation: HeadPoseSample.Quaternion
    }

    private struct PoseAtVideoFrame {
        let poseTimestampNs: UInt64?
        let poseTimestampEpochMs: Double?
        let position: HeadPoseSample.Position
        let rotation: HeadPoseSample.Quaternion
        let mode: String
        let deltaMs: Double
        let alpha: Double?
        let t0Ns: UInt64?
        let t1Ns: UInt64?
    }

    private struct HandTrackingComparisonDebug: Codable {
        let sessionId: String
        let backendMode: String
        let appleVisionFrameCount: Int
        let mediaPipeFrameCount: Int
        let appleVisionCoveragePercent: Double
        let mediaPipeCoveragePercent: Double
        let notes: [String]
    }

    private struct FusedHandPoseEntry: Codable {
        let frameIndex: Int
        let timestampNs: UInt64
        let hands: [FusedHand]
        let cameraToWorldTransform: CameraToWorldTransform?
        let headPose: FusedHeadPose?
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

    private struct FusedHeadPose: Codable {
        let timestampNs: UInt64
        let positionMeters: HeadPoseSample.Position
        let rotationQuaternion: HeadPoseSample.Quaternion
        let source: String
    }

    private struct CameraToWorldTransform: Codable {
        let translationMeters: CameraMountConfig.Translation
        let rotationQuaternion: CameraMountConfig.Quaternion
        let source: String
    }

    private struct FusedHandPoseWorldEntry: Codable {
        let frameIndex: Int
        let timestampNs: UInt64
        let coordinateSystem: String
        let depthType: String
        let hands: [WorldHand]
    }

    private struct WorldHand: Codable {
        let handedness: String
        let confidence: Double
        let landmarksWorld: [FusedLandmark3D]
    }

    private struct WorldFusionValidation: Codable {
        let sessionId: String
        let selectedLens: String
        let orientation: String
        let actualFovDeg: Double?
        let resolution: Resolution
        let fpsTarget: Int
        let fpsAchieved: Double
        let worldFusionFrameCount: Int
        let invalidTransformRows: Int
        let notes: [String]

        struct Resolution: Codable {
            let width: Int
            let height: Int
        }
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
    private var handLandmarkMediaPipeService: HandLandmarkService?
    private var handPoseMediaPipeService: HandPoseDerivationService?
    private var facePresenceService: FacePresenceService?
    private var frameQCService: FrameQCService?
    
    private var sessionDir: URL?
    private var recordingStartEpochMs: Double = 0
    private var durationTimer: Timer?
    private var useARKit: Bool = false
    
    private let visionQueue = DispatchQueue(label: "com.egocapture.vision", qos: .userInitiated)
    private let mediaPipeQueue = DispatchQueue(label: "com.egocapture.vision.mediapipe", qos: .utility)
    private let visionStride = 3

    /// Set while recording; read from `nonisolated` video delegate — must not be MainActor-isolated.
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
            
            // Force both backends so MediaPipe always runs alongside Apple Vision.
            var backendMode = HandTrackingBackendType(rawValue: ud.string(forKey: "selected_hand_tracking_backend") ?? "") ?? .appleVision
            backendMode = .both
            if backendMode == .appleVision || backendMode == .both {
                let hl = HandLandmarkService(backend: AppleVisionHandBackend())
                try hl.start(outputURL: dir.appendingPathComponent("hand_landmarks.jsonl"), epochStartMs: recordingStartEpochMs)
                handLandmarkService = hl
                let hp = HandPoseDerivationService(has3DLandmarks: hl.provides3D, sourceName: hl.backendName)
                try hp.start(outputURL: dir.appendingPathComponent("hand_pose.jsonl"), epochStartMs: recordingStartEpochMs)
                handPoseService = hp
            }
            if backendMode == .mediaPipe || backendMode == .both {
                let mediaPipeBackend = MediaPipeHandBackend()
                mediaPipeBackend.onDebugInputFrame = { [weak self] image in
                    Task { @MainActor [weak self] in
                        self?.previewImage = image
                    }
                }
                let hlMP = HandLandmarkService(backend: mediaPipeBackend)
                try hlMP.start(outputURL: dir.appendingPathComponent("hand_landmarks_mediapipe.jsonl"), epochStartMs: recordingStartEpochMs)
                handLandmarkMediaPipeService = hlMP
                let hpMP = HandPoseDerivationService(has3DLandmarks: hlMP.provides3D, sourceName: hlMP.backendName)
                try hpMP.start(outputURL: dir.appendingPathComponent("hand_pose_mediapipe.jsonl"), epochStartMs: recordingStartEpochMs)
                handPoseMediaPipeService = hpMP
            }
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

            let video = VideoCaptureService(outputURL: dir.appendingPathComponent("video.mp4"))
            video.delegate = self; videoCaptureService = video
            
            if useARKit {
                let hps = HeadPoseService()
                try hps.start(outputURL: dir.appendingPathComponent("head_pose.jsonl"), epochStartMs: recordingStartEpochMs)
                video.setupForARKit(width: hps.selectedWidth, height: hps.selectedHeight, pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
                try video.startRecording(epochStartMs: recordingStartEpochMs)
                hps.onIntrinsicsUpdate = { [weak self] i, r in self?.calibrationService.extractFromARKit(intrinsics: i, resolution: r) }
                hps.onFrameReceived = { [weak video] pb, ts, tsNs, _ in
                    video?.writePixelBuffer(pb, timestamp: ts, sourceTimestampNs: tsNs)
                }
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
        
        headPoseService?.stop()
        _ = await videoCaptureService?.stopRecording()
        imuCaptureService?.stop()
        handLandmarkService?.stop(); handPoseService?.stop()
        handLandmarkMediaPipeService?.stop(); handPoseMediaPipeService?.stop()
        facePresenceService?.stop(); frameQCService?.stop()
        
        let videoTS = videoCaptureService?.videoTimestamps ?? []
        let hpSamples = headPoseService?.timingSamples ?? []
        
        // 1. Write video_timestamps.jsonl
        if !videoTS.isEmpty {
            do { let w = try JSONLWriter(fileURL: dir.appendingPathComponent("video_timestamps.jsonl")); for t in videoTS { w.append(t) }; w.close() } catch {}
        }
        
        // 2. Build frame-aligned mapping using interpolation in monotonic domain.
        var interpolationWarnings: [String] = []
        var interpolatedPercent: Double = 0
        var fallbackPercent: Double = 0
        var vpDeltas: [Double] = []

        var parsedHeadPoseSamples: [HeadPoseSample] = []
        if useARKit && !videoTS.isEmpty {
            do {
                let headPoseSamples = try loadHeadPoseSamples(from: dir.appendingPathComponent("head_pose.jsonl"))
                parsedHeadPoseSamples = headPoseSamples
                let validatedPoses = sanitizeHeadPoseSamples(headPoseSamples)

                let mapWriter = try JSONLWriter(fileURL: dir.appendingPathComponent("head_pose_video_map.jsonl"))
                let interpWriter = try JSONLWriter(fileURL: dir.appendingPathComponent("head_pose_interpolated.jsonl"))

                var interpolatedCount = 0
                var fallbackCount = 0

                for frame in videoTS.sorted(by: { $0.timestampNs < $1.timestampNs }) {
                    guard let aligned = interpolatePose(for: frame.timestampNs, using: validatedPoses) else {
                        fallbackCount += 1
                        mapWriter.append(HeadPoseVideoMapEntry(
                            frameIndex: frame.frameIndex,
                            videoTimestampEpochMs: frame.timestampEpochMs,
                            videoTimestampNs: frame.timestampNs,
                            headPoseTimestampEpochMs: nil,
                            headPoseTimestampNs: nil,
                            mappingMode: "nearest_fallback",
                            deltaMs: 0,
                            interpAlpha: nil
                        ))
                        continue
                    }

                    if aligned.mode == "interpolated" { interpolatedCount += 1 } else { fallbackCount += 1 }
                    vpDeltas.append(aligned.deltaMs)

                    mapWriter.append(HeadPoseVideoMapEntry(
                        frameIndex: frame.frameIndex,
                        videoTimestampEpochMs: frame.timestampEpochMs,
                        videoTimestampNs: frame.timestampNs,
                        headPoseTimestampEpochMs: aligned.poseTimestampEpochMs,
                        headPoseTimestampNs: aligned.poseTimestampNs,
                        mappingMode: aligned.mode,
                        deltaMs: aligned.deltaMs,
                        interpAlpha: aligned.alpha
                    ))

                    interpWriter.append(HeadPoseInterpolatedEntry(
                        frameIndex: frame.frameIndex,
                        videoTimestampEpochMs: frame.timestampEpochMs,
                        videoTimestampNs: frame.timestampNs,
                        positionMeters: aligned.position,
                        rotationQuaternion: aligned.rotation,
                        source: aligned.mode,
                        interpAlpha: aligned.alpha,
                        bracketingSamples: BracketingSamples(t0Ns: aligned.t0Ns, t1Ns: aligned.t1Ns)
                    ))
                }

                mapWriter.close()
                interpWriter.close()

                let totalMapped = max(1, interpolatedCount + fallbackCount)
                interpolatedPercent = Double(interpolatedCount) * 100.0 / Double(totalMapped)
                fallbackPercent = Double(fallbackCount) * 100.0 / Double(totalMapped)
                if fallbackPercent > 20 {
                    interpolationWarnings.append("High fallback rate in head pose interpolation")
                }
            } catch {
                interpolationWarnings.append("Head pose interpolation failed: \(error.localizedDescription)")
            }
        }
        
        // 4. Compute IMU↔video sync (Phase 2 item 2)
        let imuVideoSync = SyncAnalysisService.computeIMUVideoSync(
            videoTimestamps: videoTS,
            imuTimestampsNs: imuCaptureService?.allTimestampsNs ?? []
        )
        
        // 5. Compute IMU↔head pose consistency (Phase 2 item 3)
        var consistencyWarnings: [String] = []
        let imuPoseConsistency = SyncAnalysisService.computeIMUPoseConsistency(
            headPoseSamples: parsedHeadPoseSamples,
            imuSamples: imuCaptureService?.gyroSamples ?? []
        )

        if !imuPoseConsistency.debugRows.isEmpty {
            do {
                let debugWriter = try JSONLWriter(fileURL: dir.appendingPathComponent("imu_pose_consistency_debug.jsonl"))
                for row in imuPoseConsistency.debugRows {
                    debugWriter.append(row)
                }
                debugWriter.close()
            } catch {
                consistencyWarnings.append("Failed to write imu_pose_consistency_debug.jsonl: \(error.localizedDescription)")
            }
        }
        
        // 6. Write calibration & mount
        do { try calibrationService.write(to: dir.appendingPathComponent("camera_calibration.json")) } catch {}
        do { try mountService.write(to: dir.appendingPathComponent("camera_mount.json")) } catch {}

        // 6.5 Build fused hand pose artifacts:
        // - camera-relative pseudo-3D (non-metric depth)
        // - world-space transformed coordinates
        var fusionWarnings: [String] = []
        var fusedHandPoseWritten = false
        var fusedHandPoseWorldWritten = false
        var worldFusionFrameCount = 0
        var invalidWorldTransformRows = 0
        do {
            let mediapipeURL = dir.appendingPathComponent("hand_landmarks_mediapipe.jsonl")
            let headPoseInterpolatedURL = dir.appendingPathComponent("head_pose_interpolated.jsonl")

            let mediaPipeRows = try loadHandLandmarkSamples(from: mediapipeURL)
            let mediaPipeByFrame = Dictionary(mediaPipeRows.map { ($0.frameIndex, $0) }, uniquingKeysWith: { _, new in new })
            let headPoseRows = (try? loadHeadPoseInterpolatedSamples(from: headPoseInterpolatedURL)) ?? []
            let headPoseByFrame = Dictionary(headPoseRows.map { ($0.frameIndex, $0) }, uniquingKeysWith: { _, new in new })

            guard let intrinsics = calibrationService.calibration?.intrinsics else {
                fusionWarnings.append("Skipped fused hand pose generation: camera intrinsics unavailable.")
                throw NSError(domain: "Fusion", code: 1)
            }

            let imageWidth = Double(max(1, calibrationService.calibration?.imageReference.width ?? videoCaptureService?.actualResolutionWidth ?? 1920))
            let imageHeight = Double(max(1, calibrationService.calibration?.imageReference.height ?? videoCaptureService?.actualResolutionHeight ?? 1080))
            let depthScale = (ud.object(forKey: "fused_hand_depth_scale") != nil) ? max(0.05, ud.double(forKey: "fused_hand_depth_scale")) : 0.5

            let mount = mountService.config
            let cameraToWorld = CameraToWorldTransform(
                translationMeters: mount.translationMeters,
                rotationQuaternion: mount.rotationQuaternion,
                source: "camera_mount.json (camera-to-head reference; world transform not yet applied)"
            )

            var fusedFrameCount = 0
            var fusedFramesWithHands = 0
            var badValueCount = 0
            var timestampMismatchCount = 0
            var headPoseTimestampMismatchCount = 0
            let fusedWriter = try JSONLWriter(fileURL: dir.appendingPathComponent("fused_hand_pose.jsonl"))
            let worldWriter = try JSONLWriter(fileURL: dir.appendingPathComponent("fused_hand_pose_world.jsonl"))
            for frame in videoTS.sorted(by: { $0.frameIndex < $1.frameIndex }) {
                let mpRow = mediaPipeByFrame[frame.frameIndex]
                if let mpRow, abs(Int64(mpRow.timestampNs) - Int64(frame.timestampNs)) > 5_000_000 {
                    timestampMismatchCount += 1
                }

                var fusedHands: [FusedHand] = []
                let sourceHands = mpRow?.hands ?? []
                for hand in sourceHands {
                    var fusedLandmarks: [FusedLandmark3D] = []
                    for lm in hand.landmarks {
                        let px = lm.x * imageWidth
                        let py = lm.y * imageHeight
                        let nx = (px - intrinsics.cx) / intrinsics.fx
                        let ny = (py - intrinsics.cy) / intrinsics.fy

                        let primaryDepth = depthScale * (-lm.z)
                        let fallbackDepth = depthScale * abs(lm.z)
                        let depth = max(0.01, primaryDepth.isFinite && primaryDepth > 0 ? primaryDepth : fallbackDepth)

                        let x = nx * depth
                        let y = ny * depth
                        let z = depth
                        guard x.isFinite, y.isFinite, z.isFinite else {
                            badValueCount += 1
                            continue
                        }

                        fusedLandmarks.append(FusedLandmark3D(id: lm.id, x: x, y: y, z: z))
                    }

                    fusedHands.append(FusedHand(
                        handedness: hand.handedness,
                        confidence: hand.confidence,
                        coordinateSystem: "camera_relative",
                        depthType: "relative_normalized",
                        landmarks3D: fusedLandmarks
                    ))
                }

                let headPoseRef: FusedHeadPose?
                var worldHands: [WorldHand] = []
                if let hp = headPoseByFrame[frame.frameIndex] {
                    if hp.videoTimestampNs != frame.timestampNs {
                        headPoseTimestampMismatchCount += 1
                    }
                    headPoseRef = FusedHeadPose(
                        timestampNs: hp.videoTimestampNs,
                        positionMeters: hp.positionMeters,
                        rotationQuaternion: hp.rotationQuaternion,
                        source: hp.source
                    )
                    // ARKit frame.camera.transform represents camera pose in world.
                    // Therefore camera-relative fused points should be transformed directly by this pose;
                    // camera_mount is NOT applied here to avoid double-transforming.
                    let cameraPoseWorld = transformMatrix(
                        position: hp.positionMeters,
                        rotation: hp.rotationQuaternion
                    )
                    for hand in fusedHands {
                        var worldLandmarks: [FusedLandmark3D] = []
                        for lm in hand.landmarks3D {
                            let p = simd_float4(Float(lm.x), Float(lm.y), Float(lm.z), 1)
                            let wp = cameraPoseWorld * p
                            let wx = Double(wp.x), wy = Double(wp.y), wz = Double(wp.z)
                            guard wx.isFinite, wy.isFinite, wz.isFinite else {
                                invalidWorldTransformRows += 1
                                continue
                            }
                            worldLandmarks.append(FusedLandmark3D(id: lm.id, x: wx, y: wy, z: wz))
                        }
                        worldHands.append(WorldHand(
                            handedness: hand.handedness,
                            confidence: hand.confidence,
                            landmarksWorld: worldLandmarks
                        ))
                    }
                } else {
                    headPoseRef = nil
                    if !fusedHands.isEmpty {
                        invalidWorldTransformRows += 1
                    }
                }

                let fusedEntry = FusedHandPoseEntry(
                    frameIndex: frame.frameIndex,
                    timestampNs: frame.timestampNs,
                    hands: fusedHands,
                    cameraToWorldTransform: cameraToWorld,
                    headPose: headPoseRef
                )
                fusedWriter.append(fusedEntry)
                worldWriter.append(FusedHandPoseWorldEntry(
                    frameIndex: frame.frameIndex,
                    timestampNs: frame.timestampNs,
                    coordinateSystem: "arkit_world",
                    depthType: "relative_normalized_transformed",
                    hands: worldHands
                ))
                fusedFrameCount += 1
                if !fusedHands.isEmpty {
                    fusedFramesWithHands += 1
                }
                worldFusionFrameCount += 1
            }
            fusedWriter.close()
            worldWriter.close()
            fusedHandPoseWritten = fusedFrameCount > 0
            fusedHandPoseWorldWritten = worldFusionFrameCount > 0

            if badValueCount > 0 {
                fusionWarnings.append("Fused hand pose skipped \(badValueCount) invalid landmark values (NaN/Inf).")
            }
            if timestampMismatchCount > 0 {
                fusionWarnings.append("Fused hand pose found \(timestampMismatchCount) frame timestamp mismatches between video and MediaPipe rows.")
            }
            if headPoseTimestampMismatchCount > 0 {
                fusionWarnings.append("Fused hand pose found \(headPoseTimestampMismatchCount) frame timestamp mismatches between video and head_pose_interpolated rows.")
            }
            if fusedFrameCount != videoTS.count {
                fusionWarnings.append("Fused hand pose frame count mismatch: fused=\(fusedFrameCount) video=\(videoTS.count).")
            }
            if fusedFramesWithHands == 0 && !videoTS.isEmpty {
                fusionWarnings.append("Fused hand pose contains no detected hands; check MediaPipe input quality/model.")
            }
            if worldFusionFrameCount != fusedFrameCount {
                fusionWarnings.append("World fusion frame count mismatch: world=\(worldFusionFrameCount) fused=\(fusedFrameCount).")
            }
            fusionWarnings.append("World-space hand coordinates use relative normalized depth, not metric depth.")
            fusionWarnings.append("World transform uses ARKit camera pose directly; camera_mount is retained for head-centered extensions, not applied in this transform.")
        } catch {
            if (error as NSError).domain != "Fusion" {
                fusionWarnings.append("Failed to write fused_hand_pose.jsonl: \(error.localizedDescription)")
            }
        }
        
        // 7. Compute all metrics
        let qcSummary = frameQCService?.computeSummary()
        let endEpochMs = Date().timeIntervalSince1970 * 1000.0
        let durationSec = (endEpochMs - recordingStartEpochMs) / 1000.0
        let totalFrames = videoCaptureService?.frameIndex ?? 0
        let droppedFrames = videoCaptureService?.droppedFrames ?? 0
        let resW = videoCaptureService?.actualResolutionWidth ?? 1920
        let resH = videoCaptureService?.actualResolutionHeight ?? 1080
        let isLandscape = resW > resH
        let avgFPS = computeEffectiveFPS(from: videoTS)
        let sortedVpDeltas = vpDeltas.sorted()
        let vpAvgDelta = sortedVpDeltas.isEmpty ? 0 : sortedVpDeltas.reduce(0, +) / Double(sortedVpDeltas.count)
        let vpMaxDelta = sortedVpDeltas.last ?? 0
        let vpP95Delta = percentile(sortedVpDeltas, p: 0.95)
        if vpP95Delta > 33 {
            interpolationWarnings.append("Head pose sample spacing too sparse for low-latency interpolation")
        }
        
        let syncMetrics = SessionMetadata.SyncMetrics(
            videoToHeadPoseAvgDeltaMs: vpAvgDelta,
            videoToHeadPoseMaxDeltaMs: vpMaxDelta,
            videoToHeadPoseP95DeltaMs: vpP95Delta,
            videoToHeadPoseMappingMode: "interpolated_with_fallbacks",
            videoToHeadPoseInterpolatedPercent: interpolatedPercent,
            videoToHeadPoseFallbackPercent: fallbackPercent,
            imuToVideoEstimatedOffsetMs: imuVideoSync.estimatedOffsetMs,
            imuToVideoSyncMethod: imuVideoSync.method,
            imuToVideoSyncConfidence: imuVideoSync.confidence
        )
        
        let imuPoseMeta = SessionMetadata.IMUPoseConsistency(
            angularErrorMeanDeg: imuPoseConsistency.angularErrorMeanDeg,
            angularErrorMedianDeg: imuPoseConsistency.angularErrorMedianDeg,
            angularErrorP95Deg: imuPoseConsistency.angularErrorP95Deg,
            angularErrorMaxDeg: imuPoseConsistency.angularErrorMaxDeg,
            angularErrorMeanRadPerSec: imuPoseConsistency.angularErrorMeanRadPerSec,
            sampleCount: imuPoseConsistency.sampleCount,
            outlierCount: imuPoseConsistency.outlierCount,
            skippedTrackingLossSamples: imuPoseConsistency.skippedTrackingLossSamples,
            method: imuPoseConsistency.method,
            confidence: imuPoseConsistency.confidence
        )
        
        let captureHealth = SessionMetadata.CaptureHealth(
            videoBackpressureEvents: videoCaptureService?.backpressureEvents ?? 0,
            imuLagEvents: imuCaptureService?.lagEventCount ?? 0,
            arkitTrackingLossFrames: headPoseService?.trackingLossFrames ?? 0,
            droppedFrames: droppedFrames,
            arkitWasInterrupted: headPoseService?.wasInterrupted ?? false,
            arkitError: headPoseService?.lastSessionError?.localizedDescription
        )
        
        let calibQuality = SessionMetadata.CalibrationQuality(
            distortionAvailable: calibrationService.calibration?.distortion.available ?? false,
            mountCalibrationVerified: mountService.config.manuallyVerified,
            mountCalibrationErrorDeg: mountService.config.calibrationErrorDeg
        )
        
        let validation = validateSession(videoFrames: totalFrames, headPoseFrames: hpSamples.count,
                                         imuSamples: imuCaptureService?.totalSamples ?? 0,
                                         durationSec: durationSec, videoTimestamps: videoTS)

        var cameraFovSource = videoCaptureService?.fovSource ?? "unknown"
        var cameraActualFovDeg = videoCaptureService?.actualFovDeg
        let selectedLens = videoCaptureService?.selectedLens ?? "unknown"
        let selectedFormatDescription = videoCaptureService?.selectedFormatDescription ?? "unknown"
        if cameraActualFovDeg == nil,
           let cal = calibrationService.calibration,
           cal.intrinsics.fx > 0,
           cal.imageReference.width > 0 {
            let estimated = 2.0 * atan(Double(cal.imageReference.width) / (2.0 * cal.intrinsics.fx)) * 180.0 / .pi
            if estimated.isFinite && estimated > 0 {
                cameraActualFovDeg = estimated
                cameraFovSource = "estimated"
            }
        }

        // Force metadata/reporting to reflect that both backends are active.
        var backendMode = HandTrackingBackendType(rawValue: ud.string(forKey: "selected_hand_tracking_backend") ?? "") ?? .appleVision
        backendMode = .both
        let appleProcessed = handLandmarkService?.processedFrameCount ?? 0
        let mediaPipeProcessed = handLandmarkMediaPipeService?.processedFrameCount ?? 0

        // Warnings
        var warnings = validation.issues
        if !useARKit { warnings.append("ARKit head pose not available") }
        if calibrationService.calibration == nil { warnings.append("Camera calibration not captured") }
        if droppedFrames > 0 { warnings.append("Dropped \(droppedFrames) video frames") }
        if !isLandscape { warnings.append("Video orientation inconsistent with landscape lock (width <= height).") }
        let usingMediaPipe = handLandmarkMediaPipeService != nil
        if usingMediaPipe {
            warnings.append("MediaPipe hand landmark z-values are normalized depth, not metric 3D world coordinates.")
        } else if !(handLandmarkService?.provides3D ?? false) {
            warnings.append("Hand landmarks are 2D only. z=0 is placeholder.")
        }
        if useARKit { warnings.append("Video from ARKit capturedImage (YCbCr → H.264).") }
        if headPoseService?.wasInterrupted == true { warnings.append("ARSession interrupted during recording.") }
        if let e = headPoseService?.lastSessionError { warnings.append("ARSession error: \(e.localizedDescription)") }
        if !(calibrationService.calibration?.distortion.available ?? false) { warnings.append("Camera distortion data not available (ARKit mode does not expose lens distortion).") }
        if !mountService.config.manuallyVerified { warnings.append("Camera mount extrinsics not verified by assisted calibration.") }
        if imuVideoSync.confidence == "low" { warnings.append("IMU↔video sync confidence is low. Offset estimate may be unreliable.") }
        if imuPoseConsistency.sampleCount == 0 { warnings.append("IMU↔head pose consistency not computed (insufficient data).") }
        if imuPoseConsistency.confidence == "low" { warnings.append("IMU↔head pose consistency confidence is low.") }
        if backendMode != .appleVision && mediaPipeProcessed > 0 && (handLandmarkMediaPipeService?.framesWithHands ?? 0) == 0 {
            warnings.append("MediaPipe backend produced no hand detections. Verify MediaPipe model asset and SDK integration.")
        }
        warnings.append(contentsOf: consistencyWarnings)
        warnings.append(contentsOf: interpolationWarnings)
        warnings.append(contentsOf: fusionWarnings)

        let appleCoverage = appleProcessed > 0 ? (Double(handLandmarkService?.framesWithHands ?? 0) * 100.0 / Double(appleProcessed)) : 0
        let mediaPipeCoverage = mediaPipeProcessed > 0 ? (Double(handLandmarkMediaPipeService?.framesWithHands ?? 0) * 100.0 / Double(mediaPipeProcessed)) : 0
        let appleAvgHands = appleProcessed > 0 ? Double(handLandmarkService?.totalHandsDetected ?? 0) / Double(appleProcessed) : 0
        let mediaPipeAvgHands = mediaPipeProcessed > 0 ? Double(handLandmarkMediaPipeService?.totalHandsDetected ?? 0) / Double(mediaPipeProcessed) : 0
        let appleAvgConfidence = {
            let values = handLandmarkService?.confidenceSamples ?? []
            return values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        }()
        let mediaPipeAvgConfidence = {
            let values = handLandmarkMediaPipeService?.confidenceSamples ?? []
            return values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        }()

        let handSource = "both"
        let zType = "normalized"

        var comparisonNotes: [String] = []
        let coverageWinner: String
        if backendMode != .both || (appleProcessed == 0 && mediaPipeProcessed == 0) {
            coverageWinner = "unknown"
        } else if abs(appleCoverage - mediaPipeCoverage) < 1.0 {
            coverageWinner = "tie"
        } else if appleCoverage > mediaPipeCoverage {
            coverageWinner = "apple_vision"
            comparisonNotes.append("Apple Vision produced denser hand coverage on this session.")
        } else {
            coverageWinner = "mediapipe"
            comparisonNotes.append("MediaPipe produced denser hand coverage on this session.")
        }

        let handTrackingComparison = SessionMetadata.HandTrackingComparison(
            appleVisionCoveragePercent: backendMode == .mediaPipe ? nil : appleCoverage,
            mediaPipeCoveragePercent: backendMode == .appleVision ? nil : mediaPipeCoverage,
            appleVisionFrameCount: backendMode == .mediaPipe ? nil : appleProcessed,
            mediaPipeFrameCount: backendMode == .appleVision ? nil : mediaPipeProcessed,
            appleVisionAverageHandsPerFrame: backendMode == .mediaPipe ? nil : appleAvgHands,
            mediaPipeAverageHandsPerFrame: backendMode == .appleVision ? nil : mediaPipeAvgHands,
            appleVisionAverageConfidence: backendMode == .mediaPipe ? nil : appleAvgConfidence,
            mediaPipeAverageConfidence: backendMode == .appleVision ? nil : mediaPipeAvgConfidence,
            coverageWinner: coverageWinner,
            notes: comparisonNotes
        )
        
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
                selectedLens: selectedLens,
                actualFovDeg: cameraActualFovDeg,
                fovSource: cameraFovSource,
                selectedFormatDescription: selectedFormatDescription
            ),
            advancedCapture: SessionMetadata.AdvancedCaptureInfo(
                enabled: true, headPoseAvailable: useARKit, headPoseSource: useARKit ? "arkit" : "none",
                cameraCalibrationAvailable: calibrationService.calibration != nil,
                cameraCalibrationSource: calibrationService.calibration?.source ?? "none", cameraMountConfigAvailable: true
            ),
            semanticArtifacts: SessionMetadata.SemanticArtifactInfo(
                hasHandLandmarks: ((handLandmarkService?.rowCount ?? 0) + (handLandmarkMediaPipeService?.rowCount ?? 0)) > 0,
                handLandmarkSource: handSource,
                hasHandPose: ((handPoseService?.rowCount ?? 0) + (handPoseMediaPipeService?.rowCount ?? 0)) > 0,
                hasFacePresence: (facePresenceService?.rowCount ?? 0) > 0,
                hasFrameQcMetrics: (frameQCService?.rowCount ?? 0) > 0,
                handLandmarksAre3D: backendMode == .mediaPipe,
                handLandmarksZType: zType
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
            syncMetrics: syncMetrics, imuPoseConsistency: imuPoseMeta, handTrackingComparison: handTrackingComparison,
            fusedArtifacts: SessionMetadata.FusedArtifacts(
                hasFusedHandPose: fusedHandPoseWritten,
                hasFusedHandPoseWorld: fusedHandPoseWorldWritten,
                fusedDepthType: "relative_normalized",
                fusionMethod: "intrinsics_projection + normalized_depth + world_transform",
                isMetric3D: false,
                worldSpaceAvailable: fusedHandPoseWorldWritten
            ),
            captureHealth: captureHealth, calibrationQuality: calibQuality,
            coordinateSystem: .arkitDefault,
            pipeline: SessionMetadata.PipelineInfo(
                version: kPipelineVersion, build: kPipelineBuild,
                captureMode: useARKit ? "arkit+assetwriter" : "avfoundation+assetwriter",
                threadModel: "multi-queue", timestampSource: "mach_absolute_time"
            ),
            validation: validation, qcSummary: qcSummary, warnings: warnings
        )
        
        // Write metadata
        do { try packagingService.writeMetadata(metadata, to: dir.appendingPathComponent("metadata.json")) } catch {}
        
        // 8. Write technical_validation.json (item 7)
        let techVal = TechnicalValidation(
            sessionId: sessionId,
            timing: TechnicalValidation.Timing(
                videoToHeadPoseAvgDeltaMs: vpAvgDelta, videoToHeadPoseMaxDeltaMs: vpMaxDelta,
                videoToHeadPoseP95DeltaMs: vpP95Delta, imuToVideoEstimatedOffsetMs: imuVideoSync.estimatedOffsetMs
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
                headPoseCoveragePercent: validation.headPoseCoveragePercent,
                imuPoseAngularErrorMeanDeg: imuPoseConsistency.angularErrorMeanDeg,
                imuPoseAngularErrorMedianDeg: imuPoseConsistency.angularErrorMedianDeg,
                imuPoseAngularErrorP95Deg: imuPoseConsistency.angularErrorP95Deg,
                imuPoseAngularErrorMaxDeg: imuPoseConsistency.angularErrorMaxDeg,
                skippedTrackingLossSamples: imuPoseConsistency.skippedTrackingLossSamples,
                consistencyConfidence: imuPoseConsistency.confidence,
                trackingLossFrames: headPoseService?.trackingLossFrames ?? 0
            ),
            calibration: TechnicalValidation.Calibration(
                intrinsicsAvailable: calibrationService.calibration != nil,
                distortionAvailable: calibrationService.calibration?.distortion.available ?? false,
                mountVerified: mountService.config.manuallyVerified,
                mountCalibrationErrorDeg: mountService.config.calibrationErrorDeg
            ),
            passCriteria: TechnicalValidation.PassCriteria(
                videoStable: avgFPS >= 19.8 && (videoCaptureService?.frameIntervalStdDevMs ?? 999) < 10,
                imuStable: (imuCaptureService?.actualSampleRateHz ?? 0) >= 90 && (imuCaptureService?.sampleIntervalStdDevMs ?? 999) < 2,
                syncAcceptable: vpAvgDelta < 5.0,
                calibrationAcceptable: calibrationService.calibration != nil
            )
        )
        do { try JSONFileWriter.write(techVal, to: dir.appendingPathComponent("technical_validation.json")) } catch {}

        let comparisonDebug = HandTrackingComparisonDebug(
            sessionId: sessionId,
            backendMode: backendMode.rawValue,
            appleVisionFrameCount: appleProcessed,
            mediaPipeFrameCount: mediaPipeProcessed,
            appleVisionCoveragePercent: appleCoverage,
            mediaPipeCoveragePercent: mediaPipeCoverage,
            notes: comparisonNotes
        )
        do { try JSONFileWriter.write(comparisonDebug, to: dir.appendingPathComponent("hand_tracking_comparison.json")) } catch {}

        let worldValidation = WorldFusionValidation(
            sessionId: sessionId,
            selectedLens: selectedLens,
            orientation: videoCaptureService?.orientation ?? "landscape",
            actualFovDeg: cameraActualFovDeg,
            resolution: .init(width: resW, height: resH),
            fpsTarget: 30,
            fpsAchieved: avgFPS,
            worldFusionFrameCount: worldFusionFrameCount,
            invalidTransformRows: invalidWorldTransformRows,
            notes: fusionWarnings
        )
        do { try JSONFileWriter.write(worldValidation, to: dir.appendingPathComponent("world_fusion_validation.json")) } catch {}
        
        // Write manifest (includes technical_validation.json)
        do { try packagingService.writeManifest(sessionId: sessionId, sessionDir: dir) } catch {}
        
        cleanup()
    }
    
    // MARK: - Validation
    
    private func validateSession(videoFrames: Int, headPoseFrames: Int, imuSamples: Int, durationSec: Double, videoTimestamps: [VideoTimestamp]) -> SessionMetadata.ValidationResult {
        var issues: [String] = []
        let fcOk = !useARKit || videoFrames == headPoseFrames
        if !fcOk { issues.append("Frame count mismatch: video=\(videoFrames) headPose=\(headPoseFrames)") }
        let expectedIMU = durationSec * 100
        let imuCov = expectedIMU > 0 ? min(Double(imuSamples) / expectedIMU * 100, 100) : 0
        if imuCov < 90 { issues.append("IMU coverage \(String(format: "%.1f", imuCov))% < 90%") }
        let expectedHP = durationSec * 30
        let hpCov = expectedHP > 0 ? min(Double(headPoseFrames) / expectedHP * 100, 100) : 0
        if useARKit && hpCov < 90 { issues.append("Head pose coverage \(String(format: "%.1f", hpCov))% < 90%") }
        var mono = true
        for i in 1..<videoTimestamps.count {
            if videoTimestamps[i].timestampNs <= videoTimestamps[i-1].timestampNs { mono = false; issues.append("Non-monotonic timestamp at frame \(i)"); break }
        }
        return SessionMetadata.ValidationResult(frameCountConsistent: fcOk, imuCoveragePercent: imuCov, headPoseCoveragePercent: hpCov, timestampsMonotonic: mono, issues: issues)
    }
    
    // MARK: - Helpers
    
    private func computeEffectiveFPS(from ts: [VideoTimestamp]) -> Double {
        guard ts.count > 1 else { return 0 }
        var d: Double = 0; var n = 0
        for i in 0..<(ts.count-1) { let iv = ts[i+1].relativeMs - ts[i].relativeMs; if iv > 0 && iv < 100 { d += iv; n += 1 } }
        return d > 0 ? Double(n) / (d / 1000.0) : 0
    }
    
    private func loadHeadPoseSamples(from url: URL) throws -> [HeadPoseSample] {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        return text.split(separator: "\n").compactMap { line in
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return try? decoder.decode(HeadPoseSample.self, from: Data(line.utf8))
        }
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

    private func loadHeadPoseInterpolatedSamples(from url: URL) throws -> [HeadPoseInterpolatedEntry] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        return text.split(separator: "\n").compactMap { line in
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return try? decoder.decode(HeadPoseInterpolatedEntry.self, from: Data(line.utf8))
        }
    }

    private func sanitizeHeadPoseSamples(_ samples: [HeadPoseSample]) -> [PosePoint] {
        let cleaned = samples.compactMap { s -> PosePoint? in
            guard s.timestampNs > 0 else { return nil }
            guard s.timestampEpochMs.isFinite else { return nil }
            let p = s.positionMeters
            let q = s.rotationQuaternion
            guard p.x.isFinite, p.y.isFinite, p.z.isFinite else { return nil }
            guard q.x.isFinite, q.y.isFinite, q.z.isFinite, q.w.isFinite else { return nil }
            return PosePoint(timestampNs: s.timestampNs, timestampEpochMs: s.timestampEpochMs, position: p, rotation: q)
        }.sorted { $0.timestampNs < $1.timestampNs }

        var monotonic: [PosePoint] = []
        var previous: UInt64?
        for sample in cleaned {
            if let prev = previous, sample.timestampNs <= prev { continue }
            monotonic.append(sample)
            previous = sample.timestampNs
        }
        return monotonic
    }

    private func interpolatePose(for frameNs: UInt64, using samples: [PosePoint]) -> PoseAtVideoFrame? {
        guard !samples.isEmpty else { return nil }
        if samples.count == 1 {
            let s = samples[0]
            return PoseAtVideoFrame(
                poseTimestampNs: s.timestampNs,
                poseTimestampEpochMs: s.timestampEpochMs,
                position: s.position,
                rotation: normalizeQuaternion(s.rotation),
                mode: "nearest_fallback",
                deltaMs: abs(Double(Int64(frameNs) - Int64(s.timestampNs))) / 1_000_000.0,
                alpha: nil,
                t0Ns: s.timestampNs,
                t1Ns: nil
            )
        }

        if frameNs <= samples[0].timestampNs {
            let s = samples[0]
            return PoseAtVideoFrame(
                poseTimestampNs: s.timestampNs,
                poseTimestampEpochMs: s.timestampEpochMs,
                position: s.position,
                rotation: normalizeQuaternion(s.rotation),
                mode: "nearest_fallback",
                deltaMs: abs(Double(Int64(frameNs) - Int64(s.timestampNs))) / 1_000_000.0,
                alpha: nil,
                t0Ns: nil,
                t1Ns: s.timestampNs
            )
        }
        if frameNs >= samples[samples.count - 1].timestampNs {
            let s = samples[samples.count - 1]
            return PoseAtVideoFrame(
                poseTimestampNs: s.timestampNs,
                poseTimestampEpochMs: s.timestampEpochMs,
                position: s.position,
                rotation: normalizeQuaternion(s.rotation),
                mode: "nearest_fallback",
                deltaMs: abs(Double(Int64(frameNs) - Int64(s.timestampNs))) / 1_000_000.0,
                alpha: nil,
                t0Ns: s.timestampNs,
                t1Ns: nil
            )
        }

        var lo = 0
        var hi = samples.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let t = samples[mid].timestampNs
            if t == frameNs {
                let exact = samples[mid]
                return PoseAtVideoFrame(
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
            } else if t < frameNs {
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }

        let rightIndex = min(max(lo, 1), samples.count - 1)
        let leftIndex = rightIndex - 1
        let s0 = samples[leftIndex]
        let s1 = samples[rightIndex]
        guard s1.timestampNs > s0.timestampNs else { return nil }

        let alpha = Double(frameNs - s0.timestampNs) / Double(s1.timestampNs - s0.timestampNs)
        let a = min(max(alpha, 0), 1)
        let p = HeadPoseSample.Position(
            x: s0.position.x + (s1.position.x - s0.position.x) * a,
            y: s0.position.y + (s1.position.y - s0.position.y) * a,
            z: s0.position.z + (s1.position.z - s0.position.z) * a
        )
        let q = slerp(s0.rotation, s1.rotation, alpha: a)
        let epochMs = s0.timestampEpochMs + (s1.timestampEpochMs - s0.timestampEpochMs) * a

        return PoseAtVideoFrame(
            poseTimestampNs: frameNs,
            poseTimestampEpochMs: epochMs,
            position: p,
            rotation: q,
            mode: "interpolated",
            deltaMs: 0,
            alpha: a,
            t0Ns: s0.timestampNs,
            t1Ns: s1.timestampNs
        )
    }

    private func normalizeQuaternion(_ q: HeadPoseSample.Quaternion) -> HeadPoseSample.Quaternion {
        let norm = sqrt(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w)
        guard norm > 0 else { return HeadPoseSample.Quaternion(x: 0, y: 0, z: 0, w: 1) }
        return HeadPoseSample.Quaternion(x: q.x / norm, y: q.y / norm, z: q.z / norm, w: q.w / norm)
    }

    private func slerp(_ q0In: HeadPoseSample.Quaternion, _ q1In: HeadPoseSample.Quaternion, alpha: Double) -> HeadPoseSample.Quaternion {
        let q0 = normalizeQuaternion(q0In)
        var q1 = normalizeQuaternion(q1In)
        var dot = q0.x * q1.x + q0.y * q1.y + q0.z * q1.z + q0.w * q1.w

        if dot < 0 {
            q1 = HeadPoseSample.Quaternion(x: -q1.x, y: -q1.y, z: -q1.z, w: -q1.w)
            dot = -dot
        }

        if dot > 0.9995 {
            return normalizeQuaternion(HeadPoseSample.Quaternion(
                x: q0.x + (q1.x - q0.x) * alpha,
                y: q0.y + (q1.y - q0.y) * alpha,
                z: q0.z + (q1.z - q0.z) * alpha,
                w: q0.w + (q1.w - q0.w) * alpha
            ))
        }

        let theta0 = acos(max(-1, min(1, dot)))
        let theta = theta0 * alpha
        let sinTheta = sin(theta)
        let sinTheta0 = sin(theta0)
        guard sinTheta0 != 0 else { return q0 }
        let s0 = cos(theta) - dot * sinTheta / sinTheta0
        let s1 = sinTheta / sinTheta0
        return normalizeQuaternion(HeadPoseSample.Quaternion(
            x: s0 * q0.x + s1 * q1.x,
            y: s0 * q0.y + s1 * q1.y,
            z: s0 * q0.z + s1 * q1.z,
            w: s0 * q0.w + s1 * q1.w
        ))
    }

    private func percentile(_ sorted: [Double], p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let idx = Int(Double(sorted.count - 1) * min(max(p, 0), 1))
        return sorted[idx]
    }

    private func transformMatrix(position: HeadPoseSample.Position, rotation: HeadPoseSample.Quaternion) -> simd_float4x4 {
        let q = simd_quatf(
            ix: Float(rotation.x),
            iy: Float(rotation.y),
            iz: Float(rotation.z),
            r: Float(rotation.w)
        )
        let rotationM = simd_float4x4(q)
        var translationM = matrix_identity_float4x4
        translationM.columns.3 = simd_float4(Float(position.x), Float(position.y), Float(position.z), 1)
        return simd_mul(translationM, rotationM)
    }
    
    private func cleanup() {
        visionCaptureBridge = nil
        videoCaptureService = nil; imuCaptureService = nil; headPoseService = nil
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

extension RecordingOrchestrator: VideoCaptureDelegate {
    nonisolated func videoCaptureService(_ service: VideoCaptureService, didOutputPixelBuffer pixelBuffer: CVPixelBuffer, relativeMs: Double, timestampNs: UInt64, frameIndex: Int) {
        Task { @MainActor [weak self] in self?.frameCount = frameIndex }
        if frameIndex % 5 == 0 { let p = Self.previewImage(from: pixelBuffer); Task { @MainActor [weak self] in self?.previewImage = p } }
        guard let bridge = visionCaptureBridge else { return }

        if bridge.handLandmarkMP != nil {
            mediaPipeQueue.async {
                print("MediaPipe processing frame \(frameIndex)")
                bridge.handLandmarkMP?.processFrame(pixelBuffer: pixelBuffer, frameIndex: frameIndex, relativeMs: relativeMs, timestampNs: timestampNs)
                if let r = bridge.handLandmarkMP?.lastResult {
                    bridge.handPoseMP?.deriveFromLandmarks(r)
                    if r.hands.isEmpty {
                        print("MediaPipe returned nil")
                    } else {
                        print("MediaPipe returned result")
                    }
                } else {
                    print("MediaPipe returned nil")
                }
            }
        }

        guard frameIndex % bridge.visionStride == 0 else { return }
        visionQueue.async {
            bridge.handLandmark?.processFrame(pixelBuffer: pixelBuffer, frameIndex: frameIndex, relativeMs: relativeMs, timestampNs: timestampNs)
            if let r = bridge.handLandmark?.lastResult { bridge.handPose?.deriveFromLandmarks(r) }
            bridge.facePresence?.processFrame(pixelBuffer: pixelBuffer, frameIndex: frameIndex, relativeMs: relativeMs)
            let appleDetected = !(bridge.handLandmark?.lastResult?.hands.isEmpty ?? true)
            let mpDetected = !(bridge.handLandmarkMP?.lastResult?.hands.isEmpty ?? true)
            let hd = appleDetected || mpDetected
            bridge.frameQC?.processFrame(pixelBuffer: pixelBuffer, frameIndex: frameIndex, relativeMs: relativeMs,
                                          handDetected: hd, faceDetected: bridge.facePresence?.lastFaceDetected ?? false)
        }
    }
}
