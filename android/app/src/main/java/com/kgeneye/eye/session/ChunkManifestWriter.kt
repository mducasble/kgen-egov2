package com.kgeneye.eye.session

import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Android currently uploads the original MP4 as a single object, but the MCAP
 * builder expects the iOS chunk-manifest contract to exist. Emit the same JSON
 * shape with an empty `chunks` array to make "no chunking" explicit.
 */
object ChunkManifestWriter {
    private const val CHUNK_DURATION_LIMIT_SEC = 120

    fun write(sessionDir: File, sessionId: String, originalFilename: String, totalDurationSec: Double) {
        val payload = JSONObject().apply {
            put("chunkDurationLimitSec", CHUNK_DURATION_LIMIT_SEC)
            put("chunks", JSONArray())
            put("originalFilename", originalFilename)
            put("totalChunks", 0)
            put("totalDurationSec", totalDurationSec)
        }
        SessionFiles.file("chunk_manifest", "json", sessionDir).writeText(payload.toString(2))
    }
}
