package com.kgeneye.eye.auth

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class AuthUser(
    val id: String,
    val email: String? = null,
    @SerialName("full_name") val fullName: String? = null,
    @SerialName("first_name") val firstName: String? = null,
    @SerialName("last_name") val lastName: String? = null,
    val nickname: String? = null,
    val country: String? = null,
    val city: String? = null,
    @SerialName("email_contact") val emailContact: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
    @SerialName("referral_code") val referralCode: String? = null,
) {
    val displayName: String?
        get() {
            fullName?.trim()?.takeIf { it.isNotEmpty() }?.let { return it }
            val combined = listOfNotNull(
                firstName?.trim()?.takeIf { it.isNotEmpty() },
                lastName?.trim()?.takeIf { it.isNotEmpty() },
            ).joinToString(" ").trim()
            if (combined.isNotEmpty()) return combined
            return nickname?.trim()?.takeIf { it.isNotEmpty() }
        }
}

@Serializable
data class AuthSession(
    @SerialName("access_token") val accessToken: String,
    @SerialName("refresh_token") val refreshToken: String,
    @SerialName("expires_in") val expiresIn: Int,
    val user: AuthUser,
)

@Serializable
data class StoredAuthSession(
    val accessToken: String,
    val refreshToken: String,
    val expiresAtEpochMs: Long,
    val user: AuthUser,
) {
    companion object {
        fun from(session: AuthSession, nowMs: Long = System.currentTimeMillis()): StoredAuthSession =
            StoredAuthSession(
                accessToken = session.accessToken,
                refreshToken = session.refreshToken,
                expiresAtEpochMs = nowMs + session.expiresIn * 1000L,
                user = session.user,
            )
    }
}
