import Foundation

/// Handles finalization of session artifacts: metadata.json and session_manifest.json.
final class SessionPackagingService {

    func writeMetadata(_ metadata: SessionMetadata, to url: URL) throws {
        try JSONFileWriter.write(metadata, to: url)
    }

    func writeManifest(sessionId: String, sessionDir: URL) throws {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(at: sessionDir, includingPropertiesForKeys: [.fileSizeKey])

        let manifestURL = SessionFiles.url("session_manifest", "json", in: sessionDir)
        let legacyManifest = sessionDir.appendingPathComponent("session_manifest.json")

        var artifacts: [SessionManifest.Artifact] = []

        for fileURL in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let filename = fileURL.lastPathComponent
            if fileURL == manifestURL || fileURL == legacyManifest { continue }

            let size = Int64((try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)

            let (type, description, rowCount) = classify(filename: filename, url: fileURL, sessionId: sessionId)
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
        try JSONFileWriter.write(manifest, to: manifestURL)
    }

    /// Strip a known session-id suffix (and extension) to get the "base" name used in the switch.
    /// `"video_qB7nX3_mL9Vz.mp4"` → `"video"`.
    /// Legacy names (`"video.mp4"`) fall through unchanged → `"video"`.
    private func baseName(of filename: String, sessionId: String) -> String {
        let ext = (filename as NSString).pathExtension
        let stem = (filename as NSString).deletingPathExtension
        let suffix = "_\(sessionId)"
        if stem.hasSuffix(suffix) {
            return String(stem.dropLast(suffix.count))
        }
        _ = ext
        return stem
    }

    private func classify(filename: String, url: URL, sessionId: String) -> (type: String, description: String, rowCount: Int?) {
        let base = baseName(of: filename, sessionId: sessionId)
        let ext = (filename as NSString).pathExtension.lowercased()

        switch base {
        case "video" where ext == "mp4":
            return ("video", "H.264 encoded egocentric video (ultra-wide, landscape)", nil)
        case "imu" where ext == "jsonl":
            return ("jsonl", "Synchronized accelerometer + gyroscope at ~100Hz", countLines(at: url))
        case "video_timestamps" where ext == "jsonl":
            return ("jsonl", "Per-frame video timestamps (monotonic + epoch)", countLines(at: url))
        case "camera_format_diagnostics" where ext == "json":
            return ("json", "All available camera formats with FOV and resolution details", nil)
        case "metadata" where ext == "json":
            return ("json", "Session metadata: IMU-only mode with camera intrinsics/extrinsics, encoding compliance, collector ID, color profile, sync metrics, and spec compliance summary", nil)
        case "technical_validation" where ext == "json":
            return ("json", "Machine-readable technical quality report with pass/fail criteria, encoding validation, calibration status, and sync health", nil)
        case "taxonomy" where ext == "json":
            return ("json", "Taxonomy selection (viewpoint, scenario, location, task) plus auto-detected day/night. Out-of-MCAP annotation.", nil)
        case "imu_intrinsics" where ext == "json":
            return ("json", ImuIntrinsics.manifestArtifactDescription, nil)
        default:
            return (ext, "Additional artifact", nil)
        }
    }

    private func countLines(at url: URL) -> Int {
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else { return 0 }
        return text.components(separatedBy: "\n").filter { !$0.isEmpty }.count
    }
}
