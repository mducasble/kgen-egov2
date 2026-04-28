package com.kgeneye.eye.auth

import com.kgeneye.eye.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.Locale

class KGenAuthClient(
    private val http: OkHttpClient = OkHttpClient(),
) {
    private val json = Json { ignoreUnknownKeys = true }
    private val mediaJson = "application/json".toMediaType()
    private val base = BuildConfig.KGEN_AUTH_BASE.ifBlank {
        "https://wvsixcvsfndhoygbkzkj.supabase.co/functions/v1/auth-mobile"
    }
    private val appKey = BuildConfig.KGEN_APP_KEY

    suspend fun login(email: String, password: String): AuthSession =
        decodeSession(call("login", mapOf("email" to normalizeEmail(email), "password" to password)))

    suspend fun signup(
        email: String,
        password: String,
        fullName: String?,
        country: String?,
        city: String?,
        referralCode: String?,
    ): AuthSession = decodeSession(
        call(
            "signup",
            mapOf(
                "email" to normalizeEmail(email),
                "password" to password,
                "full_name" to fullName,
                "country" to country,
                "city" to city,
                "referral_code" to referralCode,
            ),
        ),
    )

    suspend fun google(idToken: String, referralCode: String?): AuthSession =
        decodeSession(call("google", mapOf("id_token" to idToken, "referral_code" to referralCode)))

    suspend fun refresh(refreshToken: String): AuthSession =
        decodeSession(call("refresh", mapOf("refresh_token" to refreshToken)))

    suspend fun forgotPassword(email: String) {
        call("forgot-password", mapOf("email" to normalizeEmail(email)))
    }

    private suspend fun call(action: String, body: Map<String, Any?>, bearer: String? = null): String =
        withContext(Dispatchers.IO) {
            if (appKey.isBlank() || appKey.contains("<")) {
                throw IllegalStateException("Missing KGEN_APP_KEY in local.properties")
            }

            val payload = json.encodeToString(JsonObject.serializer(), body.toJsonObject())
            val requestBuilder = Request.Builder()
                .url("$base?action=$action")
                .post(payload.toRequestBody(mediaJson))
                .header("Content-Type", "application/json")
                .header("x-app-key", appKey)
            bearer?.let { requestBuilder.header("Authorization", "Bearer $it") }

            http.newCall(requestBuilder.build()).execute().use { response ->
                val text = response.body?.string().orEmpty()
                if (!response.isSuccessful) {
                    throw IllegalStateException(parseError(text) ?: "Auth error HTTP ${response.code}")
                }
                text
            }
        }

    private fun decodeSession(text: String): AuthSession =
        try {
            json.decodeFromString(AuthSession.serializer(), text)
        } catch (_: SerializationException) {
            throw IllegalStateException("Could not decode auth response")
        }

    private fun parseError(text: String): String? =
        runCatching {
            val obj = json.parseToJsonElement(text) as? JsonObject
            obj?.get("error")?.let { (it as? JsonPrimitive)?.content }
        }.getOrNull()

    private fun normalizeEmail(email: String): String =
        email.trim().lowercase(Locale.US)

    private fun Map<String, Any?>.toJsonObject(): JsonObject = buildJsonObject {
        for ((key, value) in this@toJsonObject) {
            when (value) {
                null -> Unit
                is String -> put(key, JsonPrimitive(value))
                is Number -> put(key, JsonPrimitive(value))
                is Boolean -> put(key, JsonPrimitive(value))
                is JsonElement -> put(key, value)
                else -> put(key, JsonPrimitive(value.toString()))
            }
        }
    }
}
