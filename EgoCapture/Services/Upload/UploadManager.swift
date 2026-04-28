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

    private init() {
        // Register the observer synchronously so new sessions are picked up immediately;
        // resuming pending uploads is deferred to keep app launch responsive (the previous
        // behaviour blocked the main actor when the user had many unfinished sessions).
        sessionReadyObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("egocaptureSessionReadyForUpload"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let sessionId = notification.userInfo?["sessionId"] as? String,
                  let sessionDir = notification.userInfo?["sessionDir"] as? URL else { return }
            Task { @MainActor in
                self?.startUpload(sessionId: sessionId, sessionDir: sessionDir)
            }
        }
        Task { @MainActor [weak self] in
            // 1s breathing room — gives SwiftUI time to render first frame before we touch
            // the sessions folder + start uploads.
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            self?.resumePendingUploads()
        }
    }

    // MARK: - Public API

    /// Start upload for a newly finished session.
    func startUpload(sessionId: String, sessionDir: URL) {
        guard uploadTasks[sessionId] == nil else { return }

        let config = S3Config.embedded()
        guard config.isValid else {
            print("[UploadManager] S3 credentials not configured — skipping upload for \(sessionId)")
            return
        }

        // `collectorId` here is the S3 key prefix that groups sessions together.
        // It now resolves to "<campaign>/<user-slug>" (e.g. "EgoTeste-iOS/marcos"),
        // instead of the legacy per-device UUID. The field is kept on UploadState for
        // backward compatibility with resume-in-progress data written by older builds.
        let collectorId = CampaignConfig.s3Prefix

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

    /// Enqueues upload of local taxonomy JSON (`taxonomy_<session>.json` or legacy `taxonomy.json`) for sessions
    /// that already finished the pipeline before taxonomy was included in the upload manifest.
    ///
    /// Uses the session's saved `collectorId` from `upload_state.json` so keys match the original upload prefix.
    ///
    /// - Parameters:
    ///   - sessionId: If non-nil, only that session; otherwise all session folders are scanned.
    ///   - force: If true, re-uploads even when the file is already marked `.done` in state (overwrites S3).
    /// - Returns: Number of sessions for which an upload task was started.
    @discardableResult
    func backfillTaxonomyArtifacts(sessionId: String? = nil, force: Bool = false) -> Int {
        let config = S3Config.embedded()
        guard config.isValid else {
            print("[UploadManager] backfill taxonomy: S3 not configured")
            return 0
        }

        var started = 0
        for session in SessionManager.shared.listSessions() {
            if let only = sessionId, only != session.id { continue }
            guard uploadTasks[session.id] == nil else { continue }
            let sessionDir = session.directory
            guard var state = UploadStateManager.load(sessionDir: sessionDir) else { continue }
            guard let taxURL = SessionFiles.resolveExisting("taxonomy", "json", in: sessionDir) else { continue }

            let filename = taxURL.lastPathComponent
            let s3Key = "\(state.collectorId)/\(state.sessionId)/\(filename)"
            let sizeBytes = Self.localFileSize(at: taxURL)

            var shouldRun = false
            if let idx = state.files.firstIndex(where: { $0.filename == filename }) {
                switch state.files[idx].status {
                case .done:
                    if force {
                        state.files[idx].status = .pending
                        state.files[idx].attempts = 0
                        state.files[idx].lastError = nil
                        state.files[idx].completedAt = nil
                        shouldRun = true
                    }
                case .failed:
                    state.files[idx].status = .pending
                    state.files[idx].attempts = 0
                    state.files[idx].lastError = nil
                    shouldRun = true
                case .pending, .uploading:
                    break
                }
            } else {
                state.files.append(
                    UploadState.FileUploadEntry(
                        filename: filename,
                        s3Key: s3Key,
                        sizeBytes: sizeBytes,
                        status: .pending,
                        attempts: 0,
                        lastError: nil,
                        completedAt: nil
                    )
                )
                shouldRun = true
            }

            guard shouldRun else { continue }

            state.status = .uploading
            UploadStateManager.save(state, sessionDir: sessionDir)
            activeUploads[session.id] = state

            let sid = session.id
            let dir = sessionDir
            let task = Task {
                await uploadFiles(sessionId: sid, sessionDir: dir, config: config)
            }
            uploadTasks[sid] = task
            started += 1
            print("[UploadManager] backfill taxonomy: started upload for \(sid) → \(filename)")
        }
        return started
    }

    private static func localFileSize(at url: URL) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.size] as? Int64 ?? 0
    }

    /// Load upload state for display purposes.
    func loadState(sessionId: String) -> UploadState? {
        let sessionsRoot = SessionManager.shared.sessionsRoot
        let sessionDir = sessionsRoot.appendingPathComponent(sessionId)
        return UploadStateManager.load(sessionDir: sessionDir)
    }

    // MARK: - Pipeline

    private func runUploadPipeline(sessionId: String, sessionDir: URL, collectorId: String, config: S3Config) async {
        guard let videoURL = SessionFiles.resolveExisting("video", "mp4", in: sessionDir) else {
            print("[UploadManager] No video.mp4 found in \(sessionId)")
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
            print("[UploadManager] Chunking video for session \(sessionId)...")
            let manifest = try await VideoChunkingService.chunkVideo(at: videoURL, outputDir: sessionDir)
            print("[UploadManager] Created \(manifest.totalChunks) chunks (\(String(format: "%.1f", manifest.totalDurationSec))s total)")

            state = UploadStateManager.createInitialState(
                sessionId: sessionId,
                collectorId: collectorId,
                sessionDir: sessionDir,
                chunkManifest: manifest,
                metadataFiles: SessionFiles.metadataFilenames(in: sessionDir)
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
            print("[UploadManager] Session \(sessionId) fully uploaded — writing sentinel")
            await uploadSentinel(sessionId: sessionId, sessionDir: sessionDir, state: state, uploader: uploader)
            print("[UploadManager] Removing intermediate chunks")
            cleanupChunks(sessionDir: sessionDir, state: state)
        } else if state.hasFailures {
            state.status = .partiallyFailed
        }

        UploadStateManager.save(state, sessionDir: sessionDir)
        activeUploads[sessionId] = state
        uploadTasks[sessionId] = nil
    }

    // MARK: - Sentinel

    /// Uploads a tiny `upload_complete_{sessionId}.json` as the LAST object so the
    /// server-side MCAP builder (S3 event → Lambda) has a reliable trigger indicating
    /// that every other artifact is already in place.
    ///
    /// Failure to upload the sentinel is non-fatal for the session itself, but it
    /// does mean no MCAP will be built for this session until a manual re-run.
    private func uploadSentinel(
        sessionId: String,
        sessionDir: URL,
        state: UploadState,
        uploader: S3UploadService
    ) async {
        let filename = "upload_complete_\(sessionId).json"
        let localURL = sessionDir.appendingPathComponent(filename)
        let s3Key = "\(state.collectorId)/\(sessionId)/\(filename)"

        let payload: [String: Any] = [
            "sessionId":     sessionId,
            "collectorId":   state.collectorId,
            "completedAt":   Date().timeIntervalSince1970 * 1000.0,
            "uploadedFiles": state.completedFiles,
            "version":       1,
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else {
            print("[UploadManager] ✗ sentinel: could not encode payload")
            return
        }

        do {
            try data.write(to: localURL, options: .atomic)
        } catch {
            print("[UploadManager] ✗ sentinel: write failed — \(error.localizedDescription)")
            return
        }

        let result = await uploader.uploadFile(localURL: localURL, s3Key: s3Key)
        switch result {
        case .success(let attempt):
            print("[UploadManager] ✓ sentinel uploaded (attempt \(attempt)) → s3://\(s3Key)")
        case .failure(let attempt, let error):
            print("[UploadManager] ✗ sentinel upload failed after \(attempt) attempt(s): \(error)")
        }
    }

    // MARK: - Cleanup

    /// Remove only the intermediate `chunk_*.mp4` files after a successful upload.
    /// The original video (`video_{code}.mp4`) is always preserved locally.
    private func cleanupChunks(sessionDir: URL, state: UploadState) {
        let fm = FileManager.default
        var removed = 0
        for chunk in state.files where chunk.filename.hasPrefix("chunk_") && chunk.filename.hasSuffix(".mp4") {
            let chunkURL = sessionDir.appendingPathComponent(chunk.filename)
            if fm.fileExists(atPath: chunkURL.path) {
                try? fm.removeItem(at: chunkURL)
                removed += 1
            }
        }
        print("[UploadManager] Deleted \(removed) local chunk file(s); video preserved")
    }

    // MARK: - Resume on App Launch

    private func resumePendingUploads() {
        let config = S3Config.embedded()
        guard config.isValid else { return }

        // Disk enumeration + state parsing happens off the main actor so the UI thread
        // stays free during the scan, even if there are dozens of sessions on disk.
        Task.detached(priority: .utility) { [weak self] in
            let snapshots: [(id: String, state: UploadState, shouldRetry: Bool)] =
                SessionManager.shared.listSessions().compactMap { session in
                    guard let state = UploadStateManager.load(sessionDir: session.directory) else { return nil }
                    switch state.status {
                    case .uploading, .partiallyFailed:
                        return (session.id, state, state.pendingFiles > 0 || state.hasFailures)
                    case .completed:
                        return (session.id, state, false)
                    default:
                        return nil
                    }
                }

            guard let self else { return }
            await MainActor.run {
                for snap in snapshots {
                    self.activeUploads[snap.id] = snap.state
                }
            }

            // Serialise retries with a small gap so we do not flood the network or the
            // main actor. Each retryUpload call itself spawns a detached Task, so this
            // loop only paces the scheduling, not the actual upload work.
            for snap in snapshots where snap.shouldRetry {
                await MainActor.run { self.retryUpload(sessionId: snap.id) }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }
}
