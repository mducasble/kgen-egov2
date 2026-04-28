package com.kgeneye.eye.ui.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import android.widget.Toast
import com.kgeneye.eye.session.FovEnumerationDiagnostic
import com.kgeneye.eye.settings.AppSettings
import com.kgeneye.eye.settings.CampaignConfig
import com.kgeneye.eye.ui.components.AmbientBackdrop
import com.kgeneye.eye.ui.components.GlassCard
import com.kgeneye.eye.ui.components.GlassPane
import com.kgeneye.eye.ui.theme.KETokens
import com.kgeneye.eye.upload.EmbeddedAwsCredentials
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun SettingsScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val appSettings = remember { AppSettings.get(context) }
    val snapshot by appSettings.state.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()

    var name by remember { mutableStateOf(snapshot.contributorName) }
    var country by remember { mutableStateOf(snapshot.contributorCountry) }
    var fovDiagnosticBusy by remember { mutableStateOf(false) }

    Box(Modifier.fillMaxSize()) {
        AmbientBackdrop()

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 20.dp, vertical = 24.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = onBack) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = KETokens.Ink1)
                }
                Text(
                    "Settings",
                    style = MaterialTheme.typography.titleLarge,
                    color = KETokens.Ink1,
                    modifier = Modifier.padding(start = 4.dp).weight(1f),
                )
            }
            Spacer(Modifier.height(12.dp))

            GlassPane(
                modifier = Modifier
                    .fillMaxSize(),
                padding = PaddingValues(horizontal = 18.dp, vertical = 18.dp),
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    SectionHeader("Contributor")
                    KEField(
                        value = name, onChange = { name = it },
                        label = "Name",
                    )
                    KEField(
                        value = country, onChange = { country = it },
                        label = "Country (ISO, e.g. BR)",
                    )

                    GlassCard(Modifier.fillMaxWidth()) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                "Campaign",
                                style = MaterialTheme.typography.bodyMedium,
                                color = KETokens.Ink2,
                                modifier = Modifier.weight(1f),
                            )
                            Text(
                                CampaignConfig.CAMPAIGN,
                                style = MaterialTheme.typography.bodyMedium,
                                color = KETokens.Ink1,
                            )
                        }
                    }

                    SectionHeader("AWS S3 (embedded)")
                    GlassCard(Modifier.fillMaxWidth()) {
                        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(
                                "Bucket: ${EmbeddedAwsCredentials.BUCKET}",
                                style = MaterialTheme.typography.bodyMedium,
                                color = KETokens.Ink1,
                            )
                            Text(
                                "Region: ${EmbeddedAwsCredentials.REGION}",
                                style = MaterialTheme.typography.bodyMedium,
                                color = KETokens.Ink1,
                            )
                            Text(
                                "Credentials are compiled into the app. Update " +
                                        "EmbeddedAwsSecrets.kt (gitignored) to change them.",
                                style = MaterialTheme.typography.bodySmall,
                                color = KETokens.Ink2,
                            )
                        }
                    }

                    Spacer(Modifier.height(4.dp))
                    Button(
                        onClick = {
                            appSettings.update {
                                copy(
                                    contributorName = name,
                                    contributorCountry = country,
                                )
                            }
                            onBack()
                        },
                        modifier = Modifier.fillMaxWidth().height(52.dp),
                        shape = RoundedCornerShape(22.dp),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = KETokens.AccentGreen.copy(alpha = 0.85f),
                            contentColor = KETokens.Ink1,
                        ),
                    ) { Text("Save") }

                    SectionHeader("Diagnostics")
                    GlassCard(Modifier.fillMaxWidth()) {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(
                                "Camera FOV enumeration",
                                style = MaterialTheme.typography.titleSmall,
                                color = KETokens.Ink1,
                            )
                            Text(
                                "Lists every back-facing camera + 30 fps format with " +
                                        "horizontal/diagonal FOV. JSON is saved to the app's " +
                                        "external files directory under FOVDiagnostics/.",
                                style = MaterialTheme.typography.bodySmall,
                                color = KETokens.Ink2,
                            )
                            OutlinedButton(
                                onClick = {
                                    if (fovDiagnosticBusy) return@OutlinedButton
                                    fovDiagnosticBusy = true
                                    scope.launch {
                                        val file = withContext(Dispatchers.IO) {
                                            FovEnumerationDiagnostic.runAndSave(context)
                                        }
                                        fovDiagnosticBusy = false
                                        val msg = if (file != null) {
                                            "FOV report saved: ${file.name}"
                                        } else {
                                            "FOV diagnostic failed (no camera service?)"
                                        }
                                        Toast.makeText(context, msg, Toast.LENGTH_LONG).show()
                                    }
                                },
                                enabled = !fovDiagnosticBusy,
                                modifier = Modifier.fillMaxWidth(),
                                shape = RoundedCornerShape(14.dp),
                            ) {
                                Text(if (fovDiagnosticBusy) "Running…" else "Run FOV diagnostic")
                            }
                        }
                    }
                    Spacer(Modifier.height(12.dp))
                }
            }
        }
    }
}

@Composable
private fun SectionHeader(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.titleMedium,
        color = KETokens.Ink1,
    )
}

@Composable
private fun KEField(
    value: String,
    onChange: (String) -> Unit,
    label: String,
    keyboardType: KeyboardType = KeyboardType.Text,
) {
    OutlinedTextField(
        value = value,
        onValueChange = onChange,
        label = { Text(label) },
        modifier = Modifier.fillMaxWidth(),
        singleLine = true,
        keyboardOptions = KeyboardOptions(keyboardType = keyboardType),
        shape = RoundedCornerShape(14.dp),
        colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = KETokens.AccentBlue,
            unfocusedBorderColor = KETokens.Ink3,
            focusedLabelColor = KETokens.Ink1,
            unfocusedLabelColor = KETokens.Ink2,
            focusedTextColor = KETokens.Ink1,
            unfocusedTextColor = KETokens.Ink1,
            cursorColor = KETokens.Ink1,
            focusedContainerColor = Color.White.copy(alpha = 0.55f),
            unfocusedContainerColor = Color.White.copy(alpha = 0.35f),
        ),
    )
}
