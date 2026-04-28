package com.kgeneye.eye.auth

import android.content.Context
import androidx.credentials.CredentialManager
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialException
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.kgeneye.eye.BuildConfig
import com.kgeneye.eye.settings.AppSettings
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class AuthRepository private constructor(private val context: Context) {
    sealed interface State {
        data object Loading : State
        data object SignedOut : State
        data class SignedIn(val session: StoredAuthSession) : State
    }

    private val client = KGenAuthClient()
    private val store = AuthSessionStore.get(context)
    private val appSettings = AppSettings.get(context)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private val _state = MutableStateFlow<State>(State.Loading)
    val state: StateFlow<State> = _state.asStateFlow()

    private val _message = MutableStateFlow<String?>(null)
    val message: StateFlow<String?> = _message.asStateFlow()

    fun bootstrap() {
        scope.launch {
            val stored = store.load()
            if (stored == null) {
                _state.value = State.SignedOut
                return@launch
            }
            if (stored.expiresAtEpochMs - System.currentTimeMillis() > 300_000L) {
                syncContributorProfile(stored.user)
                _state.value = State.SignedIn(stored)
                return@launch
            }
            runCatching { client.refresh(stored.refreshToken) }
                .onSuccess { save(it) }
                .onFailure {
                    store.clear()
                    _state.value = State.SignedOut
                }
        }
    }

    fun login(email: String, password: String) {
        launchAuth { client.login(email, password) }
    }

    fun signup(
        email: String,
        password: String,
        fullName: String?,
        country: String?,
        city: String?,
        referralCode: String?,
    ) {
        launchAuth(displayNameFallback = fullName, countryFallback = country) {
            client.signup(
                email = email,
                password = password,
                fullName = fullName,
                country = country,
                city = city,
                referralCode = referralCode,
            )
        }
    }

    fun forgotPassword(email: String) {
        scope.launch {
            runCatching { client.forgotPassword(email) }
                .onSuccess { _message.value = "Password reset email sent." }
                .onFailure { _message.value = it.message ?: "Could not send reset email." }
        }
    }

    fun signInWithGoogle(activityContext: Context, referralCode: String?) {
        scope.launch {
            runCatching {
                val serverClientId = BuildConfig.GOOGLE_WEB_CLIENT_ID
                if (serverClientId.isBlank() || serverClientId.contains("<")) {
                    error("Missing GOOGLE_WEB_CLIENT_ID in local.properties")
                }
                val credentialManager = CredentialManager.create(activityContext)
                val googleIdOption = GetGoogleIdOption.Builder()
                    .setServerClientId(serverClientId)
                    .setFilterByAuthorizedAccounts(false)
                    .build()
                val request = GetCredentialRequest.Builder()
                    .addCredentialOption(googleIdOption)
                    .build()
                val result = credentialManager.getCredential(activityContext, request)
                val googleCredential = GoogleIdTokenCredential.createFrom(result.credential.data)
                client.google(googleCredential.idToken, referralCode)
            }.onSuccess { save(it) }
                .onFailure { throwable ->
                    _message.value = when (throwable) {
                        is GetCredentialException -> throwable.message ?: "Google Sign-In canceled."
                        else -> throwable.message ?: "Google Sign-In failed."
                    }
                }
        }
    }

    fun logout() {
        store.clear()
        _state.value = State.SignedOut
    }

    fun clearMessage() {
        _message.value = null
    }

    private fun launchAuth(
        displayNameFallback: String? = null,
        countryFallback: String? = null,
        block: suspend () -> AuthSession,
    ) {
        scope.launch {
            _message.value = null
            runCatching { block() }
                .onSuccess { save(it, displayNameFallback, countryFallback) }
                .onFailure { _message.value = it.message ?: "Authentication failed." }
        }
    }

    private fun save(
        session: AuthSession,
        displayNameFallback: String? = null,
        countryFallback: String? = null,
    ) {
        val stored = StoredAuthSession.from(session)
        store.save(stored)
        syncContributorProfile(stored.user, displayNameFallback, countryFallback)
        _state.value = State.SignedIn(stored)
    }

    private fun syncContributorProfile(
        user: AuthUser,
        displayNameFallback: String? = null,
        countryFallback: String? = null,
    ) {
        val resolvedName = user.displayName ?: displayNameFallback?.trim()?.takeIf { it.isNotEmpty() }
        val resolvedCountry = normalizeCountry(user.country ?: countryFallback)
        if (resolvedName.isNullOrBlank() && resolvedCountry == null) return
        appSettings.update {
            copy(
                contributorName = resolvedName ?: contributorName,
                contributorCountry = resolvedCountry ?: contributorCountry,
            )
        }
    }

    private fun normalizeCountry(country: String?): String? {
        val trimmed = country?.trim()?.uppercase()?.takeIf { it.isNotEmpty() } ?: return null
        return trimmed.take(2)
    }

    companion object {
        @Volatile private var instance: AuthRepository? = null
        fun get(context: Context): AuthRepository =
            instance ?: synchronized(this) {
                instance ?: AuthRepository(context.applicationContext).also { instance = it }
            }
    }
}
