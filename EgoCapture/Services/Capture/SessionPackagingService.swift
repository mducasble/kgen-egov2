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
            case "video.mp4": type = "video"; description = "H.264 encoded egocentric video (ultra-wide, landscape)"
            case "imu.jsonl": type = "jsonl"; description = "Synchronized accelerometer + gyroscope at ~100Hz"; rowCount = countLines(at: fileURL)
            case "video_timestamps.jsonl": type = "jsonl"; description = "Per-frame video timestamps (monotonic + epoch)"; rowCount = countLines(at: fileURL)
            case "camera_format_diagnostics.json": type = "json"; description = "All available camera formats with FOV and resolution details"
            case "metadata.json": type = "json"; description = "Session metadata: IMU-only mode with camera intrinsics/extrinsics, encoding compliance, collector ID, color profile, sync metrics, and spec compliance summary"
            case "technical_validation.json": type = "json"; description = "Machine-readable technical quality report with pass/fail criteria, encoding validation, calibration status, and sync health"
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
