import Foundation

/// Handles finalization of session artifacts: metadata.json and session_manifest.json.
final class SessionPackagingService {
    
    /// Write metadata.json to session directory.
    func writeMetadata(_ metadata: SessionMetadata, to url: URL) throws {
        try JSONFileWriter.write(metadata, to: url)
    }
    
    /// Build and write session_manifest.json by scanning the session directory.
    func writeManifest(sessionId: String, sessionDir: URL) throws {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(at: sessionDir, includingPropertiesForKeys: [.fileSizeKey])
        
        var artifacts: [SessionManifest.Artifact] = []
        
        for fileURL in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let filename = fileURL.lastPathComponent
            
            // Skip manifest itself
            if filename == "session_manifest.json" { continue }
            
            let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
            let size = Int64(resourceValues.fileSize ?? 0)
            
            let type: String
            let description: String
            var rowCount: Int? = nil
            
            switch filename {
            case "video.mp4":
                type = "video"
                description = "H.264 encoded egocentric video"
            case "imu.jsonl":
                type = "jsonl"
                description = "Synchronized accelerometer + gyroscope samples at ~100Hz"
                rowCount = countLines(at: fileURL)
            case "head_pose.jsonl":
                type = "jsonl"
                description = "Head pose from ARKit (position + quaternion + tracking state)"
                rowCount = countLines(at: fileURL)
            case "video_timestamps.jsonl":
                type = "jsonl"
                description = "Per-frame video timestamps from CMSampleBuffer"
                rowCount = countLines(at: fileURL)
            case "head_pose_video_map.jsonl":
                type = "jsonl"
                description = "Frame-aligned head pose mapping for each video frame (interpolation with fallbacks)"
                rowCount = countLines(at: fileURL)
            case "head_pose_interpolated.jsonl":
                type = "jsonl"
                description = "Interpolated head pose estimates at exact video frame timestamps"
                rowCount = countLines(at: fileURL)
            case "imu_pose_consistency_debug.jsonl":
                type = "jsonl"
                description = "Debug rows for IMU versus interpolated head pose consistency validation"
                rowCount = countLines(at: fileURL)
            case "camera_calibration.json":
                type = "json"
                description = "Camera intrinsic calibration (fx, fy, cx, cy, distortion)"
            case "camera_mount.json":
                type = "json"
                description = "Camera extrinsic mount configuration relative to head"
            case "hand_landmarks.jsonl":
                type = "jsonl"
                description = "Per-frame hand landmark detections (21 landmarks per hand)"
                rowCount = countLines(at: fileURL)
            case "hand_landmarks_mediapipe.jsonl":
                type = "jsonl"
                description = "Per-frame hand landmarks from MediaPipe Hand Landmarker"
                rowCount = countLines(at: fileURL)
            case "hand_pose.jsonl":
                type = "jsonl"
                description = "Derived hand pose (fingertips, joint angles, thumb opposition)"
                rowCount = countLines(at: fileURL)
            case "hand_pose_mediapipe.jsonl":
                type = "jsonl"
                description = "Derived hand pose from MediaPipe landmarks"
                rowCount = countLines(at: fileURL)
            case "fused_hand_pose.jsonl":
                type = "jsonl"
                description = "Fused hand pose in camera-relative coordinates from intrinsics projection + normalized depth"
                rowCount = countLines(at: fileURL)
            case "fused_hand_pose_world.jsonl":
                type = "jsonl"
                description = "World-space fused hand pose transformed from camera-relative coordinates"
                rowCount = countLines(at: fileURL)
            case "world_fusion_validation.json":
                type = "json"
                description = "Validation summary for world-space hand fusion"
            case "face_presence.jsonl":
                type = "jsonl"
                description = "Per-frame face presence detection for privacy/QC"
                rowCount = countLines(at: fileURL)
            case "frame_qc_metrics.jsonl":
                type = "jsonl"
                description = "Per-frame QC metrics (brightness, blur, detection flags)"
                rowCount = countLines(at: fileURL)
            case "metadata.json":
                type = "json"
                description = "Session metadata, device info, capture config, and QC summary"
            case "taxonomy.json":
                type = "json"
                description = "Taxonomy selection (viewpoint, scenario, location, task) plus auto-detected day/night. Out-of-MCAP annotation."
            case "imu_intrinsics.json":
                type = "json"
                description = ImuIntrinsics.manifestArtifactDescription
            case "hand_tracking_comparison.json":
                type = "json"
                description = "Comparison summary between Apple Vision and MediaPipe hand tracking"
            default:
                type = fileURL.pathExtension
                description = "Additional artifact"
            }
            
            artifacts.append(SessionManifest.Artifact(
                filename: filename,
                type: type,
                description: description,
                sizeBytes: size,
                rowCount: rowCount
            ))
        }
        
        let manifest = SessionManifest(
            sessionId: sessionId,
            createdAtEpochMs: Date().timeIntervalSince1970 * 1000.0,
            artifacts: artifacts
        )
        
        let manifestURL = sessionDir.appendingPathComponent("session_manifest.json")
        try JSONFileWriter.write(manifest, to: manifestURL)
    }
    
    /// Count lines in a JSONL file (each line = one record).
    private func countLines(at url: URL) -> Int {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return 0 }
        return text.components(separatedBy: "\n").filter { !$0.isEmpty }.count
    }
}
