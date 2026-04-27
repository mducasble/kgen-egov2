package com.kgeneye.eye.session

import java.io.File

/**
 * Filename conventions for artifacts inside a session directory. Mirrors the
 * iOS `SessionFiles` enum — every new-format filename ends with
 * `_<sessionCode>.<ext>` so artifacts are self-identifying when extracted
 * from their parent directory.
 */
object SessionFiles {

    fun name(base: String, ext: String, code: String): String = "${base}_${code}.${ext}"

    fun file(base: String, ext: String, sessionDir: File): File =
        File(sessionDir, name(base, ext, sessionDir.name))

    /**
     * Canonical list of metadata artifacts produced per session (excluding
     * video and chunked payloads). Kept in sync with the iOS list so the
     * backend treats both platforms identically.
     */
    val metadataBases: List<Pair<String, String>> = listOf(
        "imu" to "jsonl",
        "video_timestamps" to "jsonl",
        "metadata" to "json",
        "taxonomy" to "json",
        "technical_validation" to "json",
        "chunk_manifest" to "json",
        "session_manifest" to "json",
        "camera_format_diagnostics" to "json",
        "imu_intrinsics" to "json",
    )
}
