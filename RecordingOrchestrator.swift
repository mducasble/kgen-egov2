import Foundation
import UIKit
import CoreVideo
import AVFoundation
import ARKit

/// Central orchestrator that manages the recording lifecycle.
///
/// Data flow:
///   ARKit session → HeadPoseService → (pixel buffers) → VideoCaptureService → (pixel buffers) → Vision pipeline
///
/// When ARKit is available:
///   - ARKit owns the camera exclusively
///   - HeadPoseService receives ARFrames, writes head_pose.jsonl
///   - HeadPoseService feeds pixel buffers to VideoCaptureService
///   - VideoCaptureService writes video.mp4 and forwards buffers to vision
///
/// When ARKit is NOT available:
///   - VideoCaptureService runs its own AVCaptureSession
///   - No head pose data is recorded
@MainActor
final class RecordingOrchestrator: ObservableObject {
    private struct HeadPoseVideoTimestampMapEntry: Codable {
        let headPoseFrameIndex: Int
        let headPoseTimestampEpochMs: Double
        let headPoseRelativeMs: Double
        let videoFrameIndex: Int
        let videoTimestampEpochMs: Double
        let videoRelativeMs: Double
        let absoluteDeltaMs: Double
    }
    
    // MARK: - Published State
    
    @Published var isRecording = false
    @Published var recordingDurationSec: Double = 0
    @Published var currentSessionId: String?
    @Published var statusMessage: String = "Ready"
    @Published var frameCount: Int = 0
    @Published var imuSampleCount: Int = 0
    @Published var lastError: String?
    
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
        
        lastError = nil
        statusMessage = "Starting..."
        
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
            
            // 3. Video capture service
            let video = VideoCaptureService(outputURL: dir.appendingPathComponent("video.mp4"))
            video.delegate = self
            videoCaptureService = video
            
            if useARKit {
                // ARKit mode: ARKit owns camera, feeds pixel buffers to video writer
                video.setupForARKit()
                try video.startRecording(epochStartMs: recordingStartEpochMs)
                
                // 4. Start ARKit (this starts the camera)
                let hp = HeadPoseService()
                try hp.start(
                    outputURL: dir.appendingPathComponent("head_pose.jsonl"),
                    epochStartMs: recordingStartEpochMs
                )
                
                // Wire intrinsics callback
                hp.onIntrinsicsUpdate = { [weak self] intrinsics, resolution in
                    self?.calibrationService.extractFromARKit(intrinsics: intrinsics, resolution: resolution)
                }
                
                // Wire frame callback: ARKit → VideoCaptureService
                hp.onFrameReceived = { [weak video] pixelBuffer, timestamp, _ in
                    video?.writePixelBuffer(pixelBuffer, timestamp: timestamp)
                }
                
                headPoseService = hp
            } else {
                // Standalone mode: video capture runs its own camera session
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
    
    // MARK: - Finalization
    
    private func finalizeSession() async {
        guard let dir = sessionDir, let sessionId = currentSessionId else { return }
        let ud = UserDefaults.standard
        
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
        
        // Write nearest-timestamp mapping between head pose and video frames
        if useARKit,
           let headPoseSamples = headPoseService?.timingSamples,
           !headPoseSamples.isEmpty,
           let videoTimestamps = videoCaptureService?.videoTimestamps,
           !videoTimestamps.isEmpty {
            do {
                let mapWriter = try JSONLWriter(fileURL: dir.appendingPathComponent("head_pose_video_map.jsonl"))
                for sample in headPoseSamples {
                    let nearest = nearestVideoTimestamp(
                        forEpochMs: sample.timestampEpochMs,
                        in: videoTimestamps
                    )
                    let mapped = HeadPoseVideoTimestampMapEntry(
                        headPoseFrameIndex: sample.frameIndex,
                        headPoseTimestampEpochMs: sample.timestampEpochMs,
                        headPoseRelativeMs: sample.relativeMs,
                        videoFrameIndex: nearest.frameIndex,
                        videoTimestampEpochMs: nearest.timestampEpochMs,
                        videoRelativeMs: nearest.relativeMs,
                        absoluteDeltaMs: abs(nearest.timestampEpochMs - sample.timestampEpochMs)
                    )
                    mapWriter.append(mapped)
                }
                mapWriter.close()
            } catch {
                print("[Orchestrator] Failed to write head_pose_video_map.jsonl: \(error)")
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
        let avgFPS = durationSec > 0 ? Double(totalFrames) / durationSec : 0
        let resW = videoCaptureService?.actualResolutionWidth ?? 1920
        let resH = videoCaptureService?.actualResolutionHeight ?? 1080
        
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
    
    private func cleanup() {
        videoCaptureService = nil
        imuCaptureService = nil
        headPoseService = nil
        handLandmarkService = nil
        handPoseService = nil
        facePresenceService = nil
        frameQCService = nil
    }
    
    private func nearestVideoTimestamp(
        forEpochMs targetEpochMs: Double,
        in timestamps: [VideoTimestamp]
    ) -> VideoTimestamp {
        var low = 0
        var high = timestamps.count - 1
        
        while low < high {
            let mid = (low + high) / 2
            if timestamps[mid].timestampEpochMs < targetEpochMs {
                low = mid + 1
            } else {
                high = mid
            }
        }
        
        let candidate = timestamps[low]
        if low == 0 { return candidate }
        
        let previous = timestamps[low - 1]
        let candidateDelta = abs(candidate.timestampEpochMs - targetEpochMs)
        let previousDelta = abs(previous.timestampEpochMs - targetEpochMs)
        return previousDelta <= candidateDelta ? previous : candidate
    }
}

// MARK: - VideoCaptureDelegate

extension RecordingOrchestrator: VideoCaptureDelegate {
    /// Called from video capture queue (not main thread).
    nonisolated func videoCaptureService(
        _ service: VideoCaptureService,
        didOutputPixelBuffer pixelBuffer: CVPixelBuffer,
        relativeMs: Double,
        frameIndex: Int
    ) {
        // Update UI on main thread
        Task { @MainActor [weak self] in
            self?.frameCount = frameIndex
        }
        
        // Throttle vision processing
        guard frameIndex % visionStride == 0 else { return }
        
        // Run vision pipeline off main thread
        visionQueue.async { [weak self] in
            guard let self = self else { return }
            
            // 1. Hand landmarks
            self.handLandmarkService?.processFrame(
                pixelBuffer: pixelBuffer,
                frameIndex: frameIndex,
                relativeMs: relativeMs
            )
            
            // 2. Derive hand pose
            if let landmarkResult = self.handLandmarkService?.lastResult {
                self.handPoseService?.deriveFromLandmarks(landmarkResult)
            }
            
            // 3. Face presence
            self.facePresenceService?.processFrame(
                pixelBuffer: pixelBuffer,
                frameIndex: frameIndex,
                relativeMs: relativeMs
            )
            
            // 4. Frame QC metrics
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
