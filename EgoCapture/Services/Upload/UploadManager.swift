import Foundation
import Combine

/// Orchestrates the full upload pipeline: chunk → upload → cleanup.
/// Singleton; manages concurrent uploads across sessions.
@MainActor
final class UploadManager: ObservableObject {

    static let shared = UploadManager()

    @Published var activeUploads: [String: UploadState] = [:]

    private var uploadTasks: [String: Task<Void, Never>] = [:]
    private var sessionReadyObserver: NSObjectProtocol?

    private let metadataFiles = [
        "imu.jsonl",
        "video_timestamps.jsonl",
        "metadata.json",
        "technical_validation.json",
        "session_manifest.json",
        "camera_format_diagnostics.json"
    ]

    private init() {
        resumePendingUploads()
        sessionReadyObserver = NotificationCenter.default.addObserver(
            forName: .egocaptureSessionReadyForUpload,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let sessionId = notification.userInfo?["sessionId"] as? String,
                  let sessionDir = notification.userInfo?["sessionDir"] as? URL else { return }
            Task { @MainActor in
                self?.startUpload(sessionId: sessionId, sessionDir: sessionDir)
            }
        }
    }

    // MARK: - Public API

    /// Start upload for a newly finished session.
    func startUpload(sessionId: String, sessionDir: URL) {
        guard uploadTasks[sessionId] == nil else { return }

        let config = S3Config.embedded()
        guard config.isValid else {
            print("[UploadManager] S3 credentials not configured — skipping upload for \(sessionId.prefix(8))")
            return
        }

        let collectorId = UserDefaults.standard.string(forKey: "egocapture_collector_id") ?? "unknown"

        let task = Task {
            await runUploadPipeline(sessionId: sessionId, sessionDir: sessionDir, collectorId: collectorId, config: config)
        }
        uploadTasks[sessionId] = task
    }

    /// Retry failed uploads for a session.
    func retryUpload(sessionId: String) {
        guard uploadTasks[sessionId] == nil else { return }

        let sessionsRoot = SessionManager.shared.sessionsRoot
        let sessionDir = sessionsRoot.appendingPathComponent(sessionId)

        guard var state = UploadStateManager.load(sessionDir: sessionDir) else { return }

        let config = S3Config.embedded()
        guard config.isValid else { return }

        for i in state.files.indices where state.files[i].status == .failed {
            state.files[i].status = .pending
            state.files[i].attempts = 0
            state.files[i].lastError = nil
        }
        state.status = .uploading
        UploadStateManager.save(state, sessionDir: sessionDir)
        activeUploads[sessionId] = state

        let task = Task {
            await uploadFiles(sessionId: sessionId, sessionDir: sessionDir, config: config)
        }
        uploadTasks[sessionId] = task
    }

    /// Load upload state for display purposes.
    func loadState(sessionId: String) -> UploadState? {
        let sessionsRoot = SessionManager.shared.sessionsRoot
        let sessionDir = sessionsRoot.appendingPathComponent(sessionId)
        return UploadStateManager.load(sessionDir: sessionDir)
    }

    // MARK: - Pipeline

    private func runUploadPipeline(sessionId: String, sessionDir: URL, collectorId: String, config: S3Config) async {
        let videoURL = sessionDir.appendingPathComponent("video.mp4")

        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            print("[UploadManager] No video.mp4 found in \(sessionId.prefix(8))")
            uploadTasks[sessionId] = nil
            return
        }

        var state = UploadState(
            sessionId: sessionId,
            collectorId: collectorId,
            status: .chunking,
            files: [],
            createdAt: Date().timeIntervalSince1970 * 1000.0,
            lastUpdated: Date().timeIntervalSince1970 * 1000.0
        )
        UploadStateManager.save(state, sessionDir: sessionDir)
        activeUploads[sessionId] = state

        do {
            print("[UploadManager] Chunking video for session \(sessionId.prefix(8))...")
            let manifest = try await VideoChunkingService.chunkVideo(at: videoURL, outputDir: sessionDir)
            print("[UploadManager] Created \(manifest.totalChunks) chunks (\(String(format: "%.1f", manifest.totalDurationSec))s total)")

            state = UploadStateManager.createInitialState(
                sessionId: sessionId,
                collectorId: collectorId,
                sessionDir: sessionDir,
                chunkManifest: manifest,
                metadataFiles: metadataFiles
            )
            UploadStateManager.save(state, sessionDir: sessionDir)
            activeUploads[sessionId] = state

        } catch {
            print("[UploadManager] Chunking failed: \(error.localizedDescription)")
            state.status = .failed
            UploadStateManager.save(state, sessionDir: sessionDir)
            activeUploads[sessionId] = state
            uploadTasks[sessionId] = nil
            return
        }

        await uploadFiles(sessionId: sessionId, sessionDir: sessionDir, config: config)
    }

    private func uploadFiles(sessionId: String, sessionDir: URL, config: S3Config) async {
        guard var state = UploadStateManager.load(sessionDir: sessionDir) else {
            uploadTasks[sessionId] = nil
            return
        }

        let uploader = S3UploadService(config: config)

        for i in state.files.indices {
            guard state.files[i].status == .pending else { continue }

            let entry = state.files[i]
            let fileURL = sessionDir.appendingPathComponent(entry.filename)

            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                state.files[i].status = .failed
                state.files[i].lastError = "File not found on disk"
                UploadStateManager.save(state, sessionDir: sessionDir)
                activeUploads[sessionId] = state
                continue
            }

            state.files[i].status = .uploading
            UploadStateManager.save(state, sessionDir: sessionDir)
            activeUploads[sessionId] = state

            print("[UploadManager] Uploading \(entry.filename) → s3://\(config.bucket)/\(entry.s3Key)")

            let result = await uploader.uploadFile(localURL: fileURL, s3Key: entry.s3Key)

            switch result {
            case .success(let attempt):
                state.files[i].status = .done
                state.files[i].attempts = attempt
                state.files[i].completedAt = Date().timeIntervalSince1970 * 1000.0
                print("[UploadManager] ✓ \(entry.filename) uploaded (attempt \(attempt))")

            case .failure(let attempt, let error):
                state.files[i].status = .failed
                state.files[i].attempts = attempt
                state.files[i].lastError = error
                print("[UploadManager] ✗ \(entry.filename) failed: \(error)")
            }

            UploadStateManager.save(state, sessionDir: sessionDir)
            activeUploads[sessionId] = state
        }

        if state.isFullyUploaded {
            state.status = .completed
            print("[UploadManager] Session \(sessionId.prefix(8)) fully uploaded — cleaning up local files")
            cleanupLocalFiles(sessionDir: sessionDir, state: state)
        } else if state.hasFailures {
            state.status = .partiallyFailed
        }

        UploadStateManager.save(state, sessionDir: sessionDir)
        activeUploads[sessionId] = state
        uploadTasks[sessionId] = nil
    }

    // MARK: - Cleanup

    private func cleanupLocalFiles(sessionDir: URL, state: UploadState) {
        let fm = FileManager.default

        if let videoURL = Optional(sessionDir.appendingPathComponent("video.mp4")),
           fm.fileExists(atPath: videoURL.path) {
            try? fm.removeItem(at: videoURL)
            print("[UploadManager] Deleted local video.mp4")
        }

        for chunk in state.files where chunk.filename.hasPrefix("chunk_") && chunk.filename.hasSuffix(".mp4") {
            let chunkURL = sessionDir.appendingPathComponent(chunk.filename)
            if fm.fileExists(atPath: chunkURL.path) {
                try? fm.removeItem(at: chunkURL)
            }
        }
        print("[UploadManager] Deleted local video chunks")
    }

    // MARK: - Resume on App Launch

    private func resumePendingUploads() {
        let config = S3Config.embedded()
        guard config.isValid else { return }

        let sessions = SessionManager.shared.listSessions()
        for session in sessions {
            guard let state = UploadStateManager.load(sessionDir: session.directory) else { continue }

            if state.status == .uploading || state.status == .partiallyFailed {
                activeUploads[session.id] = state

                if state.pendingFiles > 0 || state.hasFailures {
                    retryUpload(sessionId: session.id)
                }
            } else if state.status == .completed {
                activeUploads[session.id] = state
            }
        }
    }
}
