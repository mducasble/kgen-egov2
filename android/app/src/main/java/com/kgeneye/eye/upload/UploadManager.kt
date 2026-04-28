package com.kgeneye.eye.upload

import android.content.Context
import android.util.Log
import com.kgeneye.eye.session.SessionFiles
import com.kgeneye.eye.session.SessionManager
import com.kgeneye.eye.settings.AppSettings
import com.kgeneye.eye.settings.CampaignConfig
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.io.File

/**
 * Orchestrates uploads for all locally-stored sessions. Mirrors the behaviour
 * of the iOS `UploadManager` (singleton; persists per-session state; retries
 * the queue on app launch; writes a sentinel after the last file).
 *
 * Differences from iOS:
 * - no chunking — we upload `video_<code>.mp4` as a single object (aligns with
 *   the "keep the original MP4" direction from the last product iteration).
 * - uses the AWS SDK for Kotlin, which handles SigV4 and retries at the
 *   transport layer. We keep an outer retry loop for surfacing failures and
 *   resumability across app restarts.
 */
class UploadManager private constructor(private val context: Context) {

    private val appSettings = AppSettings.get(context)
    private val sessionManager = SessionManager.get(context)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val tasks = mutableMapOf<String, Job>()
    private val tasksMutex = Mutex()

    private val _activeUploads = MutableStateFlow<Map<String, UploadState>>(emptyMap())
    val activeUploads: StateFlow<Map<String, UploadState>> = _activeUploads.asStateFlow()

    /**
     * Kick off upload for a session that just finished recording. Does nothing
     * when AWS credentials are missing (the session stays on disk for later).
     */
    fun startUpload(sessionId: String, sessionDir: File) {
        scope.launch {
            tasksMutex.withLock {
                if (tasks[sessionId] != null) return@launch
                val config = S3Config.embedded()
                if (!config.isValid) {
                    Log.w(TAG, "Embedded S3 credentials are blank — refusing to upload $sessionId")
                    return@launch
                }
                val settings = appSettings.state.value
                val collectorId = CampaignConfig.s3Prefix(settings, context)
                val job = scope.launch { runPipeline(sessionId, sessionDir, collectorId, config) }
                tasks[sessionId] = job
                job.invokeOnCompletion {
                    scope.launch { tasksMutex.withLock { tasks.remove(sessionId) } }
                }
            }
        }
    }

    /** Mark failed entries as pending and re-upload. */
    fun retryUpload(sessionId: String) {
        scope.launch {
            tasksMutex.withLock {
                if (tasks[sessionId] != null) return@launch
                val sessionDir = File(sessionManager.sessionsRoot, sessionId)
                val state = UploadStateStore.load(sessionDir) ?: return@launch
                val config = S3Config.embedded()
                if (!config.isValid) return@launch

                state.files.forEach { entry ->
                    if (entry.status == UploadState.FileEntry.FileStatus.failed ||
                        entry.status == UploadState.FileEntry.FileStatus.uploading
                    ) {
                        entry.status = UploadState.FileEntry.FileStatus.pending
                        entry.attempts = 0
                        entry.lastError = null
                    }
                }
                state.status = UploadState.SessionStatus.uploading
                UploadStateStore.save(state, sessionDir)
                publish(state)

                val job = scope.launch { uploadFiles(sessionId, sessionDir, config) }
                tasks[sessionId] = job
                job.invokeOnCompletion {
                    scope.launch { tasksMutex.withLock { tasks.remove(sessionId) } }
                }
            }
        }
    }

    /** Scan disk on launch and resume any session that was mid-upload. */
    fun resumePendingUploads() {
        scope.launch {
            val config = S3Config.embedded()
            if (!config.isValid) return@launch
            delay(500)
            for (session in sessionManager.listSessions()) {
                val state = UploadStateStore.load(session.directory) ?: continue
                publish(state)
                val needsWork = state.status == UploadState.SessionStatus.uploading ||
                        state.status == UploadState.SessionStatus.partiallyFailed
                if (needsWork) retryUpload(session.id)
                delay(200)
            }
        }
    }

    fun loadState(sessionId: String): UploadState? {
        val dir = File(sessionManager.sessionsRoot, sessionId)
        return UploadStateStore.load(dir)
    }

    // region pipeline

    private suspend fun runPipeline(
        sessionId: String,
        sessionDir: File,
        collectorId: String,
        config: S3Config,
    ) {
        val state = UploadStateStore.load(sessionDir)
            ?: UploadStateStore.initialState(sessionId, collectorId, sessionDir).also {
                UploadStateStore.save(it, sessionDir)
            }
        publish(state)
        uploadFiles(sessionId, sessionDir, config)
    }

    private suspend fun uploadFiles(sessionId: String, sessionDir: File, config: S3Config) {
        val state = UploadStateStore.load(sessionDir) ?: return
        val uploader = S3UploadService(config)

        // A process can die while a large file (usually video) is marked as
        // `uploading`. On the next run there is no active network request, so
        // that persisted state must be treated as resumable work.
        var resetStaleUploading = false
        state.files.forEach { entry ->
            if (entry.status == UploadState.FileEntry.FileStatus.uploading) {
                entry.status = UploadState.FileEntry.FileStatus.pending
                resetStaleUploading = true
            }
        }
        if (resetStaleUploading) {
            UploadStateStore.save(state, sessionDir)
            publish(state)
        }

        for (entry in state.files) {
            if (entry.status != UploadState.FileEntry.FileStatus.pending) continue
            val local = File(sessionDir, entry.filename)
            if (!local.exists()) {
                entry.status = UploadState.FileEntry.FileStatus.failed
                entry.lastError = "File not found on disk"
                UploadStateStore.save(state, sessionDir); publish(state)
                continue
            }

            entry.status = UploadState.FileEntry.FileStatus.uploading
            UploadStateStore.save(state, sessionDir); publish(state)

            Log.i(TAG, "Uploading ${entry.filename} → s3://${config.bucket}/${entry.s3Key}")
            when (val res = uploader.uploadFile(local, entry.s3Key)) {
                is S3UploadService.Result.Success -> {
                    entry.status = UploadState.FileEntry.FileStatus.done
                    entry.attempts = res.attempt
                    entry.completedAt = System.currentTimeMillis().toDouble()
                }
                is S3UploadService.Result.Failure -> {
                    entry.status = UploadState.FileEntry.FileStatus.failed
                    entry.attempts = res.attempt
                    entry.lastError = res.error
                }
            }
            UploadStateStore.save(state, sessionDir); publish(state)
        }

        when {
            state.isFullyUploaded -> {
                state.status = UploadState.SessionStatus.completed
                writeSentinel(sessionId, sessionDir, state, uploader)
            }
            state.hasFailures -> state.status = UploadState.SessionStatus.partiallyFailed
        }
        UploadStateStore.save(state, sessionDir); publish(state)
    }

    @OptIn(ExperimentalSerializationApi::class)
    private suspend fun writeSentinel(
        sessionId: String,
        sessionDir: File,
        state: UploadState,
        uploader: S3UploadService,
    ) {
        val filename = "upload_complete_$sessionId.json"
        val localFile = File(sessionDir, filename)
        val s3Key = "${state.collectorId}/$sessionId/$filename"

        val payload = buildJsonObject {
            put("sessionId", sessionId)
            put("collectorId", state.collectorId)
            put("completedAt", System.currentTimeMillis().toDouble())
            put("uploadedFiles", state.completedFiles)
            put("version", 1)
        }
        val json = Json { prettyPrint = true; prettyPrintIndent = "  " }
        localFile.writeText(json.encodeToString(kotlinx.serialization.json.JsonObject.serializer(), payload))

        when (val res = uploader.uploadFile(localFile, s3Key)) {
            is S3UploadService.Result.Success -> Log.i(TAG, "Sentinel uploaded for $sessionId (attempt ${res.attempt})")
            is S3UploadService.Result.Failure -> Log.w(TAG, "Sentinel upload failed for $sessionId: ${res.error}")
        }
    }

    private fun publish(state: UploadState) {
        _activeUploads.value = _activeUploads.value.toMutableMap().apply {
            this[state.sessionId] = state
        }
    }

    // endregion

    companion object {
        private const val TAG = "UploadManager"

        @Volatile private var instance: UploadManager? = null
        fun get(context: Context): UploadManager = instance ?: synchronized(this) {
            instance ?: UploadManager(context.applicationContext).also { instance = it }
        }
    }
}
