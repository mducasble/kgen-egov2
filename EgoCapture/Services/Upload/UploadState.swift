import Foundation

/// Persistent upload state for a single session — stored as upload_state.json in the session dir.
struct UploadState: Codable {
    let sessionId: String
    let collectorId: String
    var status: SessionUploadStatus
    var files: [FileUploadEntry]
    var createdAt: Double
    var lastUpdated: Double

    enum SessionUploadStatus: String, Codable {
        case chunking
        case uploading
        case completed
        case failed
        case partiallyFailed
    }

    struct FileUploadEntry: Codable {
        let filename: String
        let s3Key: String
        let sizeBytes: Int64
        var status: FileStatus
        var attempts: Int
        var lastError: String?
        var completedAt: Double?

        enum FileStatus: String, Codable {
            case pending
            case uploading
            case done
            case failed
        }
    }

    var totalFiles: Int { files.count }
    var completedFiles: Int { files.filter { $0.status == .done }.count }
    var failedFiles: Int { files.filter { $0.status == .failed }.count }
    var pendingFiles: Int { files.filter { $0.status == .pending || $0.status == .uploading }.count }
    var isFullyUploaded: Bool { files.allSatisfy { $0.status == .done } }
    var hasFailures: Bool { files.contains { $0.status == .failed } }
    var progress: Double { totalFiles > 0 ? Double(completedFiles) / Double(totalFiles) : 0 }
}

/// Reads/writes UploadState to disk in the session directory.
enum UploadStateManager {

    /// Resolves the on-disk URL for the upload_state file, preferring the new
    /// sessioncode-suffixed name and falling back to the legacy `upload_state.json`.
    private static func resolveURL(sessionDir: URL) -> URL {
        SessionFiles.resolveExisting("upload_state", "json", in: sessionDir)
            ?? SessionFiles.url("upload_state", "json", in: sessionDir)
    }

    static func load(sessionDir: URL) -> UploadState? {
        guard let url = SessionFiles.resolveExisting("upload_state", "json", in: sessionDir),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(UploadState.self, from: data)
    }

    static func save(_ state: UploadState, sessionDir: URL) {
        let url = resolveURL(sessionDir: sessionDir)
        var updated = state
        updated.lastUpdated = Date().timeIntervalSince1970 * 1000.0
        guard let data = try? JSONEncoder.prettyEncoder.encode(updated) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Build initial state from session files + chunk manifest.
    static func createInitialState(
        sessionId: String,
        collectorId: String,
        sessionDir: URL,
        chunkManifest: VideoChunkingService.ChunkManifest,
        metadataFiles: [String]
    ) -> UploadState {
        let now = Date().timeIntervalSince1970 * 1000.0
        let s3Base = "\(collectorId)/\(sessionId)"

        var entries: [UploadState.FileUploadEntry] = []

        for chunk in chunkManifest.chunks {
            entries.append(UploadState.FileUploadEntry(
                filename: chunk.filename,
                s3Key: "\(s3Base)/\(chunk.filename)",
                sizeBytes: chunk.sizeBytes,
                status: .pending,
                attempts: 0
            ))
        }

        if let chunkManifestURL = SessionFiles.resolveExisting("chunk_manifest", "json", in: sessionDir) {
            let manifestName = chunkManifestURL.lastPathComponent
            entries.append(UploadState.FileUploadEntry(
                filename: manifestName,
                s3Key: "\(s3Base)/\(manifestName)",
                sizeBytes: fileSize(chunkManifestURL),
                status: .pending,
                attempts: 0
            ))
        }

        for name in metadataFiles {
            let url = sessionDir.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            entries.append(UploadState.FileUploadEntry(
                filename: name,
                s3Key: "\(s3Base)/\(name)",
                sizeBytes: fileSize(url),
                status: .pending,
                attempts: 0
            ))
        }

        return UploadState(
            sessionId: sessionId,
            collectorId: collectorId,
            status: .uploading,
            files: entries,
            createdAt: now,
            lastUpdated: now
        )
    }

    private static func fileSize(_ url: URL) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.size] as? Int64 ?? 0
    }
}

private extension JSONEncoder {
    static let prettyEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}
