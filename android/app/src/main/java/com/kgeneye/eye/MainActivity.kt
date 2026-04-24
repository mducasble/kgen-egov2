package com.kgeneye.eye

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.kgeneye.eye.ui.NavRoutes
import com.kgeneye.eye.ui.home.HomeScreen
import com.kgeneye.eye.ui.recording.RecordingScreen
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
                val navController = rememberNavController()
                NavHost(navController = navController, startDestination = NavRoutes.HOME) {
                    composable(NavRoutes.HOME) {
                        HomeScreen(
                            onStartRecording = { navController.navigate(NavRoutes.WIZARD) },
                            onOpenSettings = { navController.navigate(NavRoutes.SETTINGS) },
                        )
                    }
                    composable(NavRoutes.SETTINGS) {
                        SettingsScreen(onBack = { navController.popBackStack() })
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
