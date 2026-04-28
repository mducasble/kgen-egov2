package com.kgeneye.eye.auth

import android.content.Context
import androidx.core.content.edit
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import kotlinx.serialization.json.Json

class AuthSessionStore private constructor(context: Context) {
    private val json = Json { ignoreUnknownKeys = true }
    private val prefs = EncryptedSharedPreferences.create(
        context,
        "kgen_auth",
        MasterKey.Builder(context).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build(),
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )

    fun load(): StoredAuthSession? {
        val raw = prefs.getString(KEY_SESSION, null) ?: return null
        return runCatching { json.decodeFromString(StoredAuthSession.serializer(), raw) }.getOrNull()
    }

    fun save(session: StoredAuthSession) {
        prefs.edit {
            putString(KEY_SESSION, json.encodeToString(StoredAuthSession.serializer(), session))
        }
    }

    fun clear() {
        prefs.edit { remove(KEY_SESSION) }
    }

    companion object {
        private const val KEY_SESSION = "auth.session"

        @Volatile private var instance: AuthSessionStore? = null
        fun get(context: Context): AuthSessionStore =
            instance ?: synchronized(this) {
                instance ?: AuthSessionStore(context.applicationContext).also { instance = it }
            }
    }
}
