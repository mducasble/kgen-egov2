package com.kgeneye.eye.ui.recording

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.view.WindowManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.view.PreviewView
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.kgeneye.eye.capture.SessionRecorder
import com.kgeneye.eye.ui.SessionDraft
import com.kgeneye.eye.ui.components.EgoFramingCorners
import com.kgeneye.eye.ui.components.EgoStatsGrid
import com.kgeneye.eye.ui.components.EgoViewfinderGrid
import com.kgeneye.eye.ui.components.RecPill
import com.kgeneye.eye.ui.theme.KETokens

private val REQUIRED_PERMISSIONS = arrayOf(
    Manifest.permission.CAMERA,
)

@Composable
fun RecordingScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val recorder = remember { SessionRecorder(context) }
    val state by recorder.state.collectAsStateWithLifecycle()

    var hasPermissions by remember {
        mutableStateOf(REQUIRED_PERMISSIONS.all {
            ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED
        })
    }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { results -> hasPermissions = results.all { it.value } }

    LaunchedEffect(Unit) {
        recorder.setPendingTaxonomy(SessionDraft.pendingTaxonomy)
        if (!hasPermissions) permissionLauncher.launch(REQUIRED_PERMISSIONS)
    }

    LockLandscape()
    KeepScreenOn(state.isRecording)

    DisposableEffect(Unit) {
        onDispose {
            recorder.shutdown()
            SessionDraft.pendingTaxonomy = null
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black),
    ) {
        if (hasPermissions) {
            AndroidView(
                modifier = Modifier.fillMaxSize(),
                factory = { ctx ->
                    PreviewView(ctx).also { view ->
                        recorder.bindToLifecycle(lifecycleOwner, view)
                    }
                },
            )

            EgoViewfinderGrid(Modifier.fillMaxSize())
            EgoFramingCorners(Modifier.fillMaxSize())
        } else {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(24.dp),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(
                    "Camera permission is required.",
                    color = Color.White,
                    style = MaterialTheme.typography.bodyLarge,
                )
                Spacer(Modifier.height(16.dp))
                Button(
                    onClick = { permissionLauncher.launch(REQUIRED_PERMISSIONS) },
                    colors = ButtonDefaults.buttonColors(
                        containerColor = KETokens.AccentGreen.copy(alpha = 0.85f),
                        contentColor = KETokens.Ink1,
                    ),
                ) { Text("Grant permissions") }
            }
        }

        // Top chrome: back button + REC pill (timer + title) when recording
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 14.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(22.dp))
                    .background(Color.Black.copy(alpha = 0.45f)),
            ) {
                IconButton(onClick = onBack) {
                    Icon(
                        Icons.AutoMirrored.Filled.ArrowBack,
                        contentDescription = "Back",
                        tint = Color.White,
                    )
                }
            }
            Spacer(Modifier.weight(1f))
            if (state.isRecording) {
                RecPill(
                    durationSec = state.recordingDurationSec,
                    title = state.taxonomyTitle,
                )
            }
        }

        // Bottom HUD: stats grid + status + record button
        Column(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .padding(horizontal = 14.dp, vertical = 14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            if (state.isRecording) {
                EgoStatsGrid(
                    durationSec = state.recordingDurationSec,
                    frameCount = state.frameCount,
                    imuSamples = state.imuSamples,
                    imuRateHz = state.imuRateHz,
                    sessionId = state.sessionId,
                )
            } else {
                Text(
                    state.status,
                    color = Color.White,
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier
                        .align(Alignment.CenterHorizontally)
                        .clip(RoundedCornerShape(14.dp))
                        .background(Color.Black.copy(alpha = 0.45f))
                        .padding(horizontal = 14.dp, vertical = 8.dp),
                )
            }

            RecordButton(
                isRecording = state.isRecording,
                enabled = state.isReady,
                onClick = { recorder.toggleRecording() },
            )
        }
    }
}

@Composable
private fun RecordButton(isRecording: Boolean, enabled: Boolean, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            modifier = Modifier
                .size(76.dp)
                .clip(CircleShape)
                .background(Color.White.copy(alpha = 0.25f))
                .padding(6.dp),
            contentAlignment = Alignment.Center,
        ) {
            Button(
                onClick = onClick,
                enabled = enabled,
                modifier = Modifier
                    .fillMaxSize()
                    .clip(if (isRecording) RoundedCornerShape(16.dp) else CircleShape),
                shape = if (isRecording) RoundedCornerShape(16.dp) else CircleShape,
                colors = ButtonDefaults.buttonColors(
                    containerColor = KETokens.AccentRed,
                    contentColor = Color.White,
                    disabledContainerColor = KETokens.AccentRed.copy(alpha = 0.4f),
                    disabledContentColor = Color.White.copy(alpha = 0.5f),
                ),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(0.dp),
            ) {}
        }
    }
}

/**
 * Forces the host activity into landscape while the recording screen is on
 * top. Releases the lock back to the previous (or system-managed) value
 * when the composable leaves the composition. Mirrors `OrientationLock` on
 * iOS.
 */
@Composable
private fun LockLandscape() {
    val context = LocalContext.current
    DisposableEffect(Unit) {
        val activity = context.findActivity()
        val previous = activity?.requestedOrientation
        activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        onDispose {
            activity?.requestedOrientation =
                previous ?: ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        }
    }
}

/**
 * Toggles `FLAG_KEEP_SCREEN_ON` on the host window so the device doesn't
 * dim or sleep mid-recording. Mirrors `isIdleTimerDisabled = true` on iOS.
 */
@Composable
private fun KeepScreenOn(active: Boolean) {
    val context = LocalContext.current
    DisposableEffect(active) {
        val window = context.findActivity()?.window
        if (active) {
            window?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
        onDispose {
            window?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }
}

private fun Context.findActivity(): Activity? {
    var ctx: Context? = this
    while (ctx is ContextWrapper) {
        if (ctx is Activity) return ctx
        ctx = ctx.baseContext
    }
    return null
}
