import Foundation

/// Handles finalization of session artifacts: metadata.json and session_manifest.json.
final class SessionPackagingService {
    
    func writeMetadata(_ metadata: SessionMetadata, to url: URL) throws {
        try JSONFileWriter.write(metadata, to: url)
    }
    
    func writeManifest(sessionId: String, sessionDir: URL) throws {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(at: sessionDir, includingPropertiesForKeys: [.fileSizeKey])
        
        var artifacts: [SessionManifest.Artifact] = []
        
        for fileURL in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let filename = fileURL.lastPathComponent
            if filename == "session_manifest.json" { continue }
            
            let size = Int64((try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            
            let type: String
            let description: String
            var rowCount: Int? = nil
            
            switch filename {
            case "video.mp4": type = "video"; description = "H.264 encoded egocentric video"
            case "imu.jsonl": type = "jsonl"; description = "Synchronized accelerometer + gyroscope at ~100Hz"; rowCount = countLines(at: fileURL)
            case "head_pose.jsonl": type = "jsonl"; description = "Head pose from ARKit (position + quaternion + tracking state)"; rowCount = countLines(at: fileURL)
            case "video_timestamps.jsonl": type = "jsonl"; description = "Per-frame video timestamps (monotonic + epoch)"; rowCount = countLines(at: fileURL)
            case "camera_calibration.json": type = "json"; description = "Camera intrinsics + distortion metadata"
            case "camera_mount.json": type = "json"; description = "Camera extrinsic mount configuration with calibration quality"
            case "hand_landmarks.jsonl": type = "jsonl"; description = "Per-frame hand landmark detections (21 landmarks)"; rowCount = countLines(at: fileURL)
            case "hand_pose.jsonl": type = "jsonl"; description = "Derived hand pose (fingertips, joint angles)"; rowCount = countLines(at: fileURL)
            case "face_presence.jsonl": type = "jsonl"; description = "Per-frame face presence detection"; rowCount = countLines(at: fileURL)
            case "frame_qc_metrics.jsonl": type = "jsonl"; description = "Per-frame QC metrics (brightness, blur)"; rowCount = countLines(at: fileURL)
            case "head_pose_video_map.jsonl": type = "jsonl"; description = "Head pose ↔ video frame timestamp mapping with sync delta"; rowCount = countLines(at: fileURL)
            case "metadata.json": type = "json"; description = "Session metadata, capture config, sync metrics, and validation"
            case "technical_validation.json": type = "json"; description = "Machine-readable technical quality report with pass/fail criteria"
            default: type = fileURL.pathExtension; description = "Additional artifact"
            }
            
            artifacts.append(SessionManifest.Artifact(filename: filename, type: type, description: description, sizeBytes: size, rowCount: rowCount))
        }
        
        let manifest = SessionManifest(sessionId: sessionId, createdAtEpochMs: Date().timeIntervalSince1970 * 1000.0, artifacts: artifacts)
        try JSONFileWriter.write(manifest, to: sessionDir.appendingPathComponent("session_manifest.json"))
    }
    
    private func countLines(at url: URL) -> Int {
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else { return 0 }
        return text.components(separatedBy: "\n").filter { !$0.isEmpty }.count
    }
}
