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
 * - AWS credentials + bucket / region (sensitive → EncryptedSharedPreferences)
 * - Contributor name + country (used by [CampaignConfig] to build the S3 prefix)
 * - Campaign tag (defaults to `EgoTeste-Android` so uploads land in a separate
 *   partition from the iOS app by default)
 *
 * Changes are published through [state] so Compose screens observe the settings
 * reactively without re-reading the prefs file on every recomposition.
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
        val awsBucket: String,
        val awsRegion: String,
        val awsAccessKeyId: String,
        val awsSecretAccessKey: String,
        val contributorName: String,
        val contributorCountry: String,
        val campaign: String,
    ) {
        val hasAwsCredentials: Boolean
            get() = awsBucket.isNotBlank() &&
                    awsRegion.isNotBlank() &&
                    awsAccessKeyId.isNotBlank() &&
                    awsSecretAccessKey.isNotBlank()
    }

    private fun read(): Snapshot = Snapshot(
        awsBucket = prefs.getString(KEY_BUCKET, "").orEmpty(),
        awsRegion = prefs.getString(KEY_REGION, "").orEmpty(),
        awsAccessKeyId = prefs.getString(KEY_ACCESS_KEY, "").orEmpty(),
        awsSecretAccessKey = prefs.getString(KEY_SECRET_KEY, "").orEmpty(),
        contributorName = prefs.getString(KEY_NAME, "").orEmpty(),
        contributorCountry = prefs.getString(KEY_COUNTRY, "").orEmpty(),
        campaign = prefs.getString(KEY_CAMPAIGN, DEFAULT_CAMPAIGN).orEmpty(),
    )

    fun update(block: Snapshot.() -> Snapshot) {
        val next = _state.value.block()
        prefs.edit {
            putString(KEY_BUCKET, next.awsBucket.trim())
            putString(KEY_REGION, next.awsRegion.trim())
            putString(KEY_ACCESS_KEY, next.awsAccessKeyId.trim())
            putString(KEY_SECRET_KEY, next.awsSecretAccessKey.trim())
            putString(KEY_NAME, next.contributorName.trim())
            putString(KEY_COUNTRY, next.contributorCountry.trim())
            putString(KEY_CAMPAIGN, next.campaign.trim().ifBlank { DEFAULT_CAMPAIGN })
        }
        _state.value = next
    }

    companion object {
        const val DEFAULT_CAMPAIGN = "EgoTeste-Android"

        private const val KEY_BUCKET = "aws.bucket"
        private const val KEY_REGION = "aws.region"
        private const val KEY_ACCESS_KEY = "aws.accessKey"
        private const val KEY_SECRET_KEY = "aws.secretKey"
        private const val KEY_NAME = "contributor.name"
        private const val KEY_COUNTRY = "contributor.country"
        private const val KEY_CAMPAIGN = "campaign.tag"

        @Volatile private var instance: AppSettings? = null
        fun get(context: Context): AppSettings = instance ?: synchronized(this) {
            instance ?: AppSettings(context.applicationContext).also { instance = it }
        }
    }
}
