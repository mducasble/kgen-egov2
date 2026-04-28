package com.kgeneye.eye

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.kgeneye.eye.auth.AuthRepository
import com.kgeneye.eye.ui.NavRoutes
import com.kgeneye.eye.ui.home.HomeScreen
import com.kgeneye.eye.ui.login.LoginScreen
import com.kgeneye.eye.ui.recording.RecordingScreen
import com.kgeneye.eye.ui.sessions.SessionsScreen
import com.kgeneye.eye.ui.settings.SettingsScreen
import com.kgeneye.eye.ui.theme.KGenEyeTheme
import com.kgeneye.eye.ui.wizard.TaxonomyWizardScreen
import com.kgeneye.eye.upload.UploadManager

/**
 * Single-activity entry point. All screens are rendered via Jetpack Compose
 * and connected through a single NavHost. On launch we ask [UploadManager]
 * to resume anything mid-flight from previous runs — matching the iOS
 * `resumePendingUploads` behaviour at startup.
 */
class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        UploadManager.get(applicationContext).resumePendingUploads()

        setContent {
            KGenEyeTheme {
                val auth = AuthRepository.get(applicationContext)
                val authState by auth.state.collectAsStateWithLifecycle()
                val navController = rememberNavController()

                LaunchedEffect(Unit) { auth.bootstrap() }
                LaunchedEffect(authState) {
                    when (authState) {
                        is AuthRepository.State.SignedIn -> {
                            navController.navigate(NavRoutes.HOME) {
                                popUpTo(0) { inclusive = true }
                            }
                        }
                        AuthRepository.State.SignedOut -> {
                            navController.navigate(NavRoutes.LOGIN) {
                                popUpTo(0) { inclusive = true }
                            }
                        }
                        AuthRepository.State.Loading -> Unit
                    }
                }

                NavHost(navController = navController, startDestination = NavRoutes.LOGIN) {
                    composable(NavRoutes.LOGIN) {
                        when (authState) {
                            AuthRepository.State.Loading -> CircularProgressIndicator()
                            else -> LoginScreen(auth)
                        }
                    }
                    composable(NavRoutes.HOME) {
                        HomeScreen(
                            onStartRecording = { navController.navigate(NavRoutes.WIZARD) },
                            onViewSessions = { navController.navigate(NavRoutes.SESSIONS) },
                            onOpenSettings = { navController.navigate(NavRoutes.SETTINGS) },
                            onLogout = { auth.logout() },
                        )
                    }
                    composable(NavRoutes.SETTINGS) {
                        SettingsScreen(onBack = { navController.popBackStack() })
                    }
                    composable(NavRoutes.SESSIONS) {
                        SessionsScreen(onBack = { navController.popBackStack() })
                    }
                    composable(NavRoutes.WIZARD) {
                        TaxonomyWizardScreen(
                            onBack = { navController.popBackStack() },
                            onComplete = {
                                navController.navigate(NavRoutes.recording("pending")) {
                                    popUpTo(NavRoutes.HOME)
                                }
                            },
                        )
                    }
                    composable(NavRoutes.RECORDING) {
                        RecordingScreen(onBack = {
                            navController.popBackStack(NavRoutes.HOME, inclusive = false)
                        })
                    }
                }
            }
        }
    }
}
