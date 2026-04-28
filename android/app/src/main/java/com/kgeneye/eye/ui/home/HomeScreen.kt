package com.kgeneye.eye.ui.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.kgeneye.eye.settings.AppSettings
import com.kgeneye.eye.settings.CampaignConfig
import com.kgeneye.eye.ui.components.AmbientBackdrop
import com.kgeneye.eye.ui.components.GlassLogoBadge
import com.kgeneye.eye.ui.components.GlassPane
import com.kgeneye.eye.ui.components.KEButtonVariant
import com.kgeneye.eye.ui.components.KEPillButton
import com.kgeneye.eye.ui.theme.KETokens

/**
 * Ambient-glass Home: rotating photographic backdrop + central glass pane with
 * brand lockup and three pill actions. Mirrors `KGenEyeHomeView` from iOS.
 */
@Composable
fun HomeScreen(
    onStartRecording: () -> Unit,
    onViewSessions: () -> Unit,
    onOpenSettings: () -> Unit,
    onLogout: () -> Unit,
) {
    val context = LocalContext.current
    val appSettings = remember { AppSettings.get(context) }
    val settings by appSettings.state.collectAsStateWithLifecycle()

    Box(Modifier.fillMaxSize()) {
        AmbientBackdrop()

        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 22.dp, vertical = 24.dp),
            contentAlignment = Alignment.Center,
        ) {
            GlassPane(
                modifier = Modifier
                    .fillMaxSize()
                    .widthIn(max = 520.dp),
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .verticalScroll(rememberScrollState())
                        .padding(horizontal = 20.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Spacer(Modifier.height(28.dp))
                    GlassLogoBadge()
                    Spacer(Modifier.height(18.dp))

                    val contributor = settings.contributorName.ifBlank { "unnamed contributor" }
                    Text(
                        "$contributor · ${CampaignConfig.CAMPAIGN}",
                        color = KETokens.Ink3,
                        textAlign = TextAlign.Center,
                    )
                    Spacer(Modifier.height(24.dp))

                    Column(
                        modifier = Modifier.fillMaxWidth(),
                        verticalArrangement = Arrangement.spacedBy(14.dp),
                    ) {
                        KEPillButton(
                            label = "Start Recording",
                            icon = Icons.Filled.PlayArrow,
                            variant = KEButtonVariant.Red,
                            onClick = onStartRecording,
                        )
                        KEPillButton(
                            label = "View Sessions",
                            icon = Icons.Filled.Folder,
                            variant = KEButtonVariant.Blue,
                            onClick = onViewSessions,
                        )
                        KEPillButton(
                            label = "Settings",
                            icon = Icons.Filled.Settings,
                            variant = KEButtonVariant.Ghost,
                            onClick = onOpenSettings,
                        )
                        KEPillButton(
                            label = "Sign Out",
                            icon = Icons.AutoMirrored.Filled.Logout,
                            variant = KEButtonVariant.Ghost,
                            onClick = onLogout,
                        )
                    }
                    Spacer(Modifier.height(28.dp))
                }
            }
        }
    }
}
