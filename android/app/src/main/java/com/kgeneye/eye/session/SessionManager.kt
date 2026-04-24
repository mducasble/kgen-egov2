package com.kgeneye.eye.session

import android.content.Context
import java.io.File

/**
 * Manages per-session directories under app-specific external storage
 * (`/storage/emulated/0/Android/data/<pkg>/files/sessions/`). Keeps parity
 * with the iOS SessionManager: each directory is named after the 12-char
 * Base64url session code and all artifacts live next to each other.
 */
class SessionManager private constructor(context: Context) {

    val sessionsRoot: File = File(context.getExternalFilesDir(null), "sessions").apply {
        if (!exists()) mkdirs()
    }

    data class Session(val id: String, val directory: File)

    fun createSession(): Session {
        repeat(4) {
            val id = SessionCode.generate()
            val dir = File(sessionsRoot, id)
            if (!dir.exists() && dir.mkdirs()) return Session(id, dir)
        }
        val id = SessionCode.generate()
        val dir = File(sessionsRoot, id).apply { mkdirs() }
        return Session(id, dir)
    }

    fun listSessions(): List<Session> =
        sessionsRoot.listFiles()
            ?.filter { it.isDirectory }
            ?.sortedByDescending { it.lastModified() }
            ?.map { Session(it.name, it) }
            .orEmpty()

    fun deleteSession(id: String): Boolean =
        File(sessionsRoot, id).deleteRecursively()

    fun sessionSizeBytes(id: String): Long {
        val dir = File(sessionsRoot, id)
        if (!dir.exists()) return 0L
        return dir.walkTopDown().filter { it.isFile }.sumOf { it.length() }
    }

    companion object {
        @Volatile private var instance: SessionManager? = null
        fun get(context: Context): SessionManager =
            instance ?: synchronized(this) {
                instance ?: SessionManager(context.applicationContext).also { instance = it }
            }
    }
}
