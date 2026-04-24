package com.kgeneye.eye.ui.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.kgeneye.eye.session.SessionManager
import com.kgeneye.eye.settings.AppSettings
import com.kgeneye.eye.upload.UploadManager
import com.kgeneye.eye.upload.UploadState
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(
    onStartRecording: () -> Unit,
    onOpenSettings: () -> Unit,
) {
    val context = LocalContext.current
    val uploadManager = remember { UploadManager.get(context) }
    val appSettings = remember { AppSettings.get(context) }
    val sessionManager = remember { SessionManager.get(context) }

    val settings by appSettings.state.collectAsStateWithLifecycle()
    val activeUploads by uploadManager.activeUploads.collectAsStateWithLifecycle()

    val sessions = remember(activeUploads) {
        sessionManager.listSessions().map { SessionRow(it, activeUploads[it.id]) }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("KGeN Eye") },
                actions = {
                    IconButton(onClick = onOpenSettings) {
                        Icon(Icons.Default.Settings, contentDescription = "Settings")
                    }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(padding).padding(horizontal = 20.dp)
        ) {
            Spacer(Modifier.height(16.dp))
            Text(
                text = "Contributor: ${settings.contributorName.ifBlank { "(not set)" }} · ${settings.campaign}",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(8.dp))
            if (!settings.hasAwsCredentials) {
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp)) {
                        Text("AWS credentials not configured",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold)
                        Text("Uploads are disabled until bucket, region and keys are provided in Settings.",
                            style = MaterialTheme.typography.bodyMedium)
                    }
                }
                Spacer(Modifier.height(16.dp))
            }

            Button(
                onClick = onStartRecording,
                modifier = Modifier.fillMaxWidth().height(64.dp),
            ) {
                Text("New recording", style = MaterialTheme.typography.titleLarge)
            }

            Spacer(Modifier.height(24.dp))
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text("Local sessions", style = MaterialTheme.typography.titleMedium)
                IconButton(onClick = { uploadManager.resumePendingUploads() }) {
                    Icon(Icons.Default.Refresh, contentDescription = "Retry queue")
                }
            }
            Spacer(Modifier.height(8.dp))

            LazyColumn(
                verticalArrangement = Arrangement.spacedBy(12.dp),
                contentPadding = PaddingValues(bottom = 24.dp)
            ) {
                items(sessions, key = { it.session.id }) { row ->
                    SessionCard(
                        row = row,
                        onRetry = { uploadManager.retryUpload(row.session.id) },
                        onUpload = { uploadManager.startUpload(row.session.id, row.session.directory) },
                        hasCredentials = settings.hasAwsCredentials,
                    )
                }
            }
        }
    }
}

private data class SessionRow(
    val session: SessionManager.Session,
    val upload: UploadState?,
)

@Composable
private fun SessionCard(
    row: SessionRow,
    onRetry: () -> Unit,
    onUpload: () -> Unit,
    hasCredentials: Boolean,
) {
    val dateFmt = remember { SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.getDefault()) }
    val sizeBytes = remember(row.session.id) {
        row.session.directory.walkTopDown().filter { it.isFile }.sumOf { it.length() }
    }
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp)) {
            Text(row.session.id, style = MaterialTheme.typography.titleMedium)
            Text(
                "Recorded ${dateFmt.format(Date(row.session.directory.lastModified()))} · ${humanSize(sizeBytes)}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            val upload = row.upload
            if (upload != null) {
                Spacer(Modifier.height(12.dp))
                Text(uploadLabel(upload), style = MaterialTheme.typography.bodyMedium)
                Spacer(Modifier.height(6.dp))
                LinearProgressIndicator(
                    progress = { upload.progress.toFloat() },
                    modifier = Modifier.fillMaxWidth()
                )
            }

            Spacer(Modifier.height(12.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (upload == null || upload.status == UploadState.SessionStatus.failed ||
                    upload.status == UploadState.SessionStatus.partiallyFailed) {
                    OutlinedButton(onClick = if (upload == null) onUpload else onRetry,
                        enabled = hasCredentials) {
                        Text(if (upload == null) "Upload" else "Retry")
                    }
                }
            }
        }
    }
}

private fun uploadLabel(state: UploadState): String =
    "${state.status.name} · ${state.completedFiles}/${state.totalFiles} files" +
        (state.failedFiles.takeIf { it > 0 }?.let { " · $it failed" } ?: "")

private fun humanSize(bytes: Long): String {
    if (bytes <= 0) return "0 B"
    val units = arrayOf("B", "KB", "MB", "GB", "TB")
    var b = bytes.toDouble(); var u = 0
    while (b >= 1024 && u < units.lastIndex) { b /= 1024; u++ }
    return String.format(Locale.US, "%.1f %s", b, units[u])
}
