package com.kgeneye.eye.session

import android.util.Base64
import java.security.SecureRandom

/**
 * Short, URL-safe, filesystem-safe session identifiers.
 *
 * 9 random bytes encode to exactly 12 Base64url characters — matches the iOS
 * `SessionCodeGenerator` so sessions produced on either platform share the
 * same namespace and collision guarantees (≈ 72 bits of entropy).
 */
object SessionCode {

    const val LENGTH = 12
    private const val RAW_BYTES = 9

    private val rng = SecureRandom()

    fun generate(): String {
        val bytes = ByteArray(RAW_BYTES)
        rng.nextBytes(bytes)
        val flags = Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP
        return Base64.encodeToString(bytes, flags)
    }

    /** True when [id] matches the new-style 12-char Base64url code. */
    fun isShortCode(id: String): Boolean {
        if (id.length != LENGTH) return false
        return id.all { c ->
            c in 'A'..'Z' || c in 'a'..'z' || c in '0'..'9' || c == '-' || c == '_'
        }
    }
}
