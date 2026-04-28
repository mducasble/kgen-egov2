package com.kgeneye.eye.settings

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.edit
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Encrypted key/value store for user-facing settings.
 *
 * AWS credentials are compile-time constants (see [com.kgeneye.eye.upload.EmbeddedAwsCredentials])
 * and are therefore *not* stored here. The snapshot only carries fields that
 * the contributor can actually edit from the Settings screen:
 *
 * - Contributor name + country (feed [CampaignConfig] to build the S3 prefix).
 * The campaign is fixed in [CampaignConfig] for now.
 */
class AppSettings private constructor(context: Context) {

    private val prefs: SharedPreferences = run {
        val key = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        EncryptedSharedPreferences.create(
            context,
            "kgeneye_settings_v1",
            key,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    private val _state = MutableStateFlow(read())

    val state: StateFlow<Snapshot> = _state.asStateFlow()

    data class Snapshot(
        val contributorName: String,
        val contributorCountry: String,
    )

    private fun read(): Snapshot = Snapshot(
        contributorName = prefs.getString(KEY_NAME, "").orEmpty(),
        contributorCountry = prefs.getString(KEY_COUNTRY, "").orEmpty(),
    )

    fun update(block: Snapshot.() -> Snapshot) {
        val next = _state.value.block()
        prefs.edit {
            putString(KEY_NAME, next.contributorName.trim())
            putString(KEY_COUNTRY, next.contributorCountry.trim())
        }
        _state.value = next
    }

    companion object {
        private const val KEY_NAME = "contributor.name"
        private const val KEY_COUNTRY = "contributor.country"

        @Volatile private var instance: AppSettings? = null
        fun get(context: Context): AppSettings = instance ?: synchronized(this) {
            instance ?: AppSettings(context.applicationContext).also { instance = it }
        }
    }
}
