package com.kgeneye.eye.settings

import android.content.Context
import android.provider.Settings
import java.text.Normalizer
import java.util.Locale

/**
 * Builds the S3 key prefix for the current contributor — mirrors the iOS
 * `CampaignConfig` so uploads from both apps end up inside a consistent
 * campaign/country/contributor folder layout.
 *
 * The Android client defaults to `EgoTeste-Android` to keep its first uploads
 * separate from the iOS testing campaign; the operator can override this in
 * Settings.
 */
object CampaignConfig {

    /** Two-letter ISO region uppercased; falls back to device locale then `XX`. */
    fun countryCode(settings: AppSettings.Snapshot): String {
        val explicit = settings.contributorCountry.trim().uppercase()
        if (explicit.length >= 2) return explicit.take(2)
        val locale = Locale.getDefault().country
        if (locale.length >= 2) return locale.take(2).uppercase()
        return "XX"
    }

    /** URL-safe slug for the contributor name; `anon-<tail>` when blank. */
    fun userSlug(settings: AppSettings.Snapshot, context: Context): String {
        val slug = slugify(settings.contributorName)
        if (slug.isNotEmpty()) return slug
        val androidId = try {
            Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID).orEmpty()
        } catch (_: Throwable) { "" }
        val tail = androidId.lowercase().replace("-", "").takeLast(6).ifEmpty { "000000" }
        return "anon-$tail"
    }

    /** Example: `EgoTeste-Android/BR/marcos-d`. */
    fun s3Prefix(settings: AppSettings.Snapshot, context: Context): String =
        "${settings.campaign}/${countryCode(settings)}/${userSlug(settings, context)}"

    /** Lower-cases, strips diacritics, collapses non-alphanumerics to single hyphens (cap 40). */
    fun slugify(input: String): String {
        val normalized = Normalizer.normalize(input, Normalizer.Form.NFD)
        val ascii = normalized.filter { it.code in 0..127 }.lowercase()
        val out = StringBuilder()
        var pendingHyphen = false
        for (c in ascii) {
            if (c.isLetterOrDigit()) {
                if (pendingHyphen && out.isNotEmpty()) out.append('-')
                out.append(c)
                pendingHyphen = false
            } else {
                pendingHyphen = true
            }
        }
        var result = out.toString()
        if (result.length > 40) result = result.take(40)
        while (result.endsWith("-")) result = result.dropLast(1)
        return result
    }
}
