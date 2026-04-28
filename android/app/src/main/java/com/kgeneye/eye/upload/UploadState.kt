package com.kgeneye.eye.upload

import com.kgeneye.eye.session.SessionFiles
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File

/**
 * Persistent upload state for a single session — stored as
 * `upload_state_<code>.json` in the session dir. Semantics mirror the iOS
 * `UploadState`.
 */
@Serializable
data class UploadState(
    val sessionId: String,
    val collectorId: String,
    var status: SessionStatus,
    var files: MutableList<FileEntry>,
    val createdAt: Double,
    var lastUpdated: Double,
) {

    enum class SessionStatus { uploading, completed, failed, partiallyFailed }

    @Serializable
    data class FileEntry(
        val filename: String,
        val s3Key: String,
        val sizeBytes: Long,
        var status: FileStatus,
        var attempts: Int,
        var lastError: String? = null,
        var completedAt: Double? = null,
    ) {
        enum class FileStatus { pending, uploading, done, failed }
    }

    val totalFiles: Int get() = files.size
    val completedFiles: Int get() = files.count { it.status == FileEntry.FileStatus.done }
    val failedFiles: Int get() = files.count { it.status == FileEntry.FileStatus.failed }
    val pendingFiles: Int
        get() = files.count { it.status == FileEntry.FileStatus.pending || it.status == FileEntry.FileStatus.uploading }
    val isFullyUploaded: Boolean get() = files.all { it.status == FileEntry.FileStatus.done }
    val hasFailures: Boolean get() = files.any { it.status == FileEntry.FileStatus.failed }
    val progress: Double get() = if (totalFiles > 0) completedFiles.toDouble() / totalFiles else 0.0
}

@OptIn(ExperimentalSerializationApi::class)
object UploadStateStore {
    private val json = Json { prettyPrint = true; prettyPrintIndent = "  " }

    fun load(sessionDir: File): UploadState? {
        val file = SessionFiles.file("upload_state", "json", sessionDir)
        if (!file.exists()) return null
        return try {
            json.decodeFromString(UploadState.serializer(), file.readText())
        } catch (_: Throwable) { null }
    }

    fun save(state: UploadState, sessionDir: File) {
        state.lastUpdated = System.currentTimeMillis().toDouble()
        val file = SessionFiles.file("upload_state", "json", sessionDir)
        file.writeText(json.encodeToString(UploadState.serializer(), state))
    }

    fun initialState(
        sessionId: String,
        collectorId: String,
        sessionDir: File,
    ): UploadState {
        val now = System.currentTimeMillis().toDouble()
        val s3Base = "$collectorId/$sessionId"
        val entries = mutableListOf<UploadState.FileEntry>()

        val uploadableBases = SessionFiles.metadataBases + listOf("video" to "mp4")
        for ((base, ext) in uploadableBases) {
            val f = SessionFiles.file(base, ext, sessionDir)
            if (!f.exists()) continue
            entries += UploadState.FileEntry(
                filename = f.name,
                s3Key = "$s3Base/${f.name}",
                sizeBytes = f.length(),
                status = UploadState.FileEntry.FileStatus.pending,
                attempts = 0,
            )
        }

        return UploadState(
            sessionId = sessionId,
            collectorId = collectorId,
            status = UploadState.SessionStatus.uploading,
            files = entries,
            createdAt = now,
            lastUpdated = now,
        )
    }
}
