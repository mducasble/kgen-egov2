package com.kgeneye.eye.ui.sessions

import android.net.Uri
import android.widget.MediaController
import android.widget.VideoView
import androidx.compose.foundation.clickable
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.kgeneye.eye.session.SessionFiles
import com.kgeneye.eye.session.SessionManager
import com.kgeneye.eye.ui.components.AmbientBackdrop
import com.kgeneye.eye.ui.components.GlassCard
import com.kgeneye.eye.ui.components.GlassPane
import com.kgeneye.eye.ui.theme.KETokens
import com.kgeneye.eye.upload.UploadManager
import com.kgeneye.eye.upload.UploadState
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.roundToInt

/**
 * Shows every session currently on disk, with its upload status and retry /
 * kickoff actions. Pulled out of `HomeScreen` so the home pane can keep the
 * iOS-style three-pill layout.
 */
@Composable
fun SessionsScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val uploadManager = remember { UploadManager.get(context) }
    val sessionManager = remember { SessionManager.get(context) }
    val activeUploads by uploadManager.activeUploads.collectAsStateWithLifecycle()
    var expandedSessionId by remember { mutableStateOf<String?>(null) }
    var refreshTick by remember { mutableStateOf(0) }

    val sessions = remember(activeUploads, refreshTick) {
        sessionManager.listSessions().map {
            SessionRow(it, activeUploads[it.id] ?: uploadManager.loadState(it.id))
        }
    }

    Box(Modifier.fillMaxSize()) {
        AmbientBackdrop()

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 20.dp, vertical = 24.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = onBack) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = KETokens.Ink1)
                }
                Spacer(Modifier.fillMaxWidth(0.02f))
                Text(
                    "Local sessions",
                    style = MaterialTheme.typography.titleLarge,
                    color = KETokens.Ink1,
                    modifier = Modifier.weight(1f),
                )
                IconButton(onClick = { uploadManager.resumePendingUploads() }) {
                    Icon(Icons.Default.Refresh, contentDescription = "Retry queue", tint = KETokens.Ink1)
                }
            }
            Spacer(Modifier.height(12.dp))

            GlassPane(
                modifier = Modifier.fillMaxSize(),
                padding = PaddingValues(horizontal = 16.dp, vertical = 18.dp),
            ) {
                if (sessions.isEmpty()) {
                    Column(
                        modifier = Modifier.fillMaxSize(),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center,
                    ) {
                        Text(
                            "No recordings yet.",
                            color = KETokens.Ink2,
                            textAlign = TextAlign.Center,
                        )
                    }
                } else {
                    LazyColumn(
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                        contentPadding = PaddingValues(vertical = 4.dp),
                    ) {
                        items(sessions, key = { it.session.id }) { row ->
                            SessionCard(
                                row = row,
                                expanded = expandedSessionId == row.session.id,
                                onToggle = {
                                    expandedSessionId =
                                        if (expandedSessionId == row.session.id) null else row.session.id
                                },
                                onRetry = {
                                    uploadManager.retryUpload(row.session.id)
                                    refreshTick += 1
                                },
                                onUpload = {
                                    uploadManager.startUpload(row.session.id, row.session.directory)
                                    refreshTick += 1
                                },
                            )
                        }
                    }
                }
            }
        }
    }
}

private data class SessionRow(
    val session: SessionManager.Session,
    val upload: UploadState?,
)

private object SessionTone {
    val Green = Color(0xFF166948)
    val GreenFill = Color(0x2E0C543A)
    val Amber = Color(0xFF965E08)
    val AmberFill = Color(0x29965E08)
    val Red = Color(0xFF912C2C)
    val RedFill = Color(0x24912C2C)
}

@Composable
private fun SessionCard(
    row: SessionRow,
    expanded: Boolean,
    onToggle: () -> Unit,
    onRetry: () -> Unit,
    onUpload: () -> Unit,
) {
    val dateFmt = remember { SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.getDefault()) }
    val sizeBytes = remember(row.session.id) {
        row.session.directory.walkTopDown().filter { it.isFile }.sumOf { it.length() }
    }
    GlassCard(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onToggle)
    ) {
        Column {
            Text(row.session.id, style = MaterialTheme.typography.titleMedium, color = KETokens.Ink1)
            Text(
                "Recorded ${dateFmt.format(Date(row.session.directory.lastModified()))} · ${humanSize(sizeBytes)}",
                style = MaterialTheme.typography.bodySmall,
                color = KETokens.Ink2,
            )

            val upload = row.upload
            if (upload != null) {
                Spacer(Modifier.height(12.dp))
                Text(uploadLabel(upload), style = MaterialTheme.typography.bodyMedium, color = KETokens.Ink2)
                Spacer(Modifier.height(6.dp))
                LinearProgressIndicator(
                    progress = { upload.progress.toFloat() },
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            Spacer(Modifier.height(10.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TextButton(onClick = onToggle) {
                    Text(if (expanded) "Hide tests" else "Show tests")
                }
                if (upload == null) {
                    TextButton(onClick = onUpload) {
                        Text("Upload")
                    }
                } else if (upload.status != UploadState.SessionStatus.completed) {
                    TextButton(onClick = onRetry) {
                        Text("Retry")
                    }
                }
            }

            if (expanded) {
                Spacer(Modifier.height(10.dp))
                SessionTestSummary(row)
            }
        }
    }
}

@Composable
private fun SessionTestSummary(row: SessionRow) {
    val summary = remember(row.session.id, row.upload?.lastUpdated) {
        buildSessionTestSummary(row)
    }

    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        SessionVideoHeader(summary)
        SessionScoreCard(summary)
        QualityChecksCard(summary.qualityChecks)
        RecordingStatsCard(summary.recordingStats)
        RecordingStatusCard(row.session.id, summary)
    }
}

@Composable
private fun SessionVideoHeader(summary: SessionTestSummary) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        GlassCard(
            modifier = Modifier.fillMaxWidth(),
            cornerRadius = 24.dp,
            padding = PaddingValues(6.dp),
        ) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .aspectRatio(16f / 9f)
                    .clip(RoundedCornerShape(22.dp))
                    .background(Color.Black.copy(alpha = 0.86f)),
                contentAlignment = Alignment.Center,
            ) {
                val videoFile = summary.videoFile
                if (videoFile != null) {
                    AndroidView(
                        modifier = Modifier.fillMaxSize(),
                        factory = { context ->
                            VideoView(context).apply {
                                setMediaController(MediaController(context).also { it.setAnchorView(this) })
                                setVideoURI(Uri.fromFile(videoFile))
                                setOnPreparedListener { mediaPlayer ->
                                    mediaPlayer.isLooping = false
                                    seekTo(1)
                                }
                            }
                        },
                        update = { view ->
                            view.setVideoURI(Uri.fromFile(videoFile))
                            view.seekTo(1)
                        },
                    )
                } else {
                    Text("Video unavailable", color = Color.White.copy(alpha = 0.72f))
                }
            }
        }

        Text(summary.title, style = MaterialTheme.typography.titleMedium, color = KETokens.Ink1)
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(summary.timestampText, style = MaterialTheme.typography.bodySmall, color = KETokens.Ink2)
            Text("•", color = KETokens.Ink3)
            Text(summary.durationText, style = MaterialTheme.typography.bodySmall, color = KETokens.Ink2)
            Text("•", color = KETokens.Ink3)
            Text(summary.fileSizeText, style = MaterialTheme.typography.bodySmall, color = KETokens.Ink2)
        }
    }
}

@Composable
private fun SessionScoreCard(summary: SessionTestSummary) {
    val scoreColor = when {
        summary.score >= 85 -> SessionTone.Green
        summary.score >= 65 -> SessionTone.Amber
        else -> SessionTone.Red
    }
    GlassCard(modifier = Modifier.fillMaxWidth(), cornerRadius = 22.dp, padding = PaddingValues(18.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    modifier = Modifier
                        .size(42.dp)
                        .clip(CircleShape)
                        .background(scoreColor.copy(alpha = 0.22f)),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Default.CheckCircle, contentDescription = null, tint = scoreColor)
                }
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text(summary.scoreLabel, style = MaterialTheme.typography.titleMedium, color = scoreColor)
                    Text(summary.scoreDetail, style = MaterialTheme.typography.bodySmall, color = KETokens.Ink2)
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Session Score", style = MaterialTheme.typography.bodySmall, color = KETokens.Ink2, modifier = Modifier.weight(1f))
                Text("${summary.score}", style = MaterialTheme.typography.titleLarge, color = scoreColor)
            }
            LinearProgressIndicator(
                progress = { summary.score / 100f },
                modifier = Modifier.fillMaxWidth(),
                color = scoreColor,
                trackColor = KETokens.Ink1.copy(alpha = 0.10f),
            )
        }
    }
}

@Composable
private fun QualityChecksCard(checks: List<SessionCheck>) {
    GlassCard(modifier = Modifier.fillMaxWidth(), cornerRadius = 22.dp, padding = PaddingValues(18.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            SectionHeader("Quality Checks")
            checks.forEach { check ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        modifier = Modifier
                            .size(40.dp)
                            .clip(RoundedCornerShape(12.dp))
                            .background(if (check.passed) SessionTone.GreenFill else SessionTone.RedFill),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(check.icon, color = if (check.passed) SessionTone.Green else SessionTone.Red)
                    }
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(check.title, style = MaterialTheme.typography.bodyMedium, color = KETokens.Ink1)
                        Text(check.value, style = MaterialTheme.typography.bodySmall, color = KETokens.Ink2)
                    }
                    Text(
                        if (check.passed) "Good" else "Review",
                        style = MaterialTheme.typography.bodySmall,
                        color = if (check.passed) SessionTone.Green else SessionTone.Red,
                        modifier = Modifier
                            .clip(RoundedCornerShape(999.dp))
                            .background(if (check.passed) SessionTone.GreenFill else SessionTone.RedFill)
                            .padding(horizontal = 9.dp, vertical = 5.dp),
                    )
                }
            }
        }
    }
}

@Composable
private fun RecordingStatsCard(stats: List<RecordingStat>) {
    GlassCard(modifier = Modifier.fillMaxWidth(), cornerRadius = 22.dp, padding = PaddingValues(18.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            SectionHeader("Recording Stats")
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                stats.chunked(2).forEach { row ->
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        row.forEach { stat ->
                            StatTile(stat = stat, modifier = Modifier.weight(1f))
                        }
                        if (row.size == 1) Spacer(Modifier.weight(1f))
                    }
                }
            }
        }
    }
}

@Composable
private fun StatTile(stat: RecordingStat, modifier: Modifier = Modifier) {
    Row(
        modifier = modifier
            .clip(RoundedCornerShape(14.dp))
            .background(KETokens.GhostTint.copy(alpha = 0.20f))
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(stat.icon, color = SessionTone.Green)
        Spacer(Modifier.width(8.dp))
        Column {
            Text(stat.label, style = MaterialTheme.typography.bodySmall, color = KETokens.Ink3)
            Text(stat.value, style = MaterialTheme.typography.bodyMedium, color = KETokens.Ink1)
        }
    }
}

@Composable
private fun RecordingStatusCard(sessionId: String, summary: SessionTestSummary) {
    GlassCard(modifier = Modifier.fillMaxWidth(), cornerRadius = 22.dp, padding = PaddingValues(18.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            SectionHeader("Recording Status")
            Text(
                if (summary.s3Prefix == null) "Local session" else "Upload path ready",
                style = MaterialTheme.typography.bodyMedium,
                color = KETokens.Ink1,
            )
            Text(
                summary.s3Prefix ?: "Session $sessionId is saved locally and ready for analysis/upload.",
                style = MaterialTheme.typography.bodySmall,
                color = KETokens.Ink2,
            )
        }
    }
}

@Composable
private fun SectionHeader(title: String) {
    Text(title, style = MaterialTheme.typography.titleMedium, color = KETokens.Ink1)
}

@Composable
private fun TestSummaryRow(item: TestSummaryItem) {
    val statusColor = when (item.passed) {
        true -> SessionTone.Green
        false -> SessionTone.Red
        null -> KETokens.Ink2
    }
    Column {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                item.title,
                style = MaterialTheme.typography.bodySmall,
                color = KETokens.Ink1,
                modifier = Modifier.weight(1f),
            )
            Text(
                item.status,
                style = MaterialTheme.typography.bodySmall,
                color = statusColor,
            )
        }
        Text(
            item.detail,
            style = MaterialTheme.typography.bodySmall,
            color = KETokens.Ink2,
        )
    }
}

private data class SessionTestSummary(
    val title: String,
    val timestampText: String,
    val durationText: String,
    val fileSizeText: String,
    val score: Int,
    val scoreLabel: String,
    val scoreDetail: String,
    val videoFile: File?,
    val s3Prefix: String?,
    val qualityChecks: List<SessionCheck>,
    val recordingStats: List<RecordingStat>,
)

private data class SessionCheck(
    val icon: String,
    val title: String,
    val value: String,
    val passed: Boolean,
)

private data class RecordingStat(
    val icon: String,
    val label: String,
    val value: String,
)

private data class TestSummaryItem(
    val title: String,
    val status: String,
    val detail: String,
    val passed: Boolean?,
)

private fun buildSessionTestSummary(row: SessionRow): SessionTestSummary {
    val sessionDir = row.session.directory
    val metadata = readJson(SessionFiles.file("metadata", "json", sessionDir))
    val technical = readJson(SessionFiles.file("technical_validation", "json", sessionDir))
    val qcReport = readJson(SessionFiles.file("qc_report", "json", sessionDir))
    val frameQCMetrics = readJsonLines(SessionFiles.file("frame_qc_metrics", "jsonl", sessionDir))

    val upload = row.upload
    val videoFile = SessionFiles.file("video", "mp4", sessionDir).takeIf { it.exists() }
    val title = metadata?.optJSONObject("environment")
        ?.optString("taskDescription", "")
        ?.takeIf { it.isNotBlank() }
        ?: "Session ${row.session.id}"
    val startMs = metadata?.optDoubleOrNull("startTimeEpochMs")
    val timestampMs = startMs?.toLong() ?: sessionDir.lastModified()
    val timestampText = SimpleDateFormat("dd/MM/yyyy · HH:mm", Locale.getDefault()).format(Date(timestampMs))
    val durationSec = metadata?.optDoubleOrNull("durationSec") ?: 0.0
    val durationText = formatDuration(durationSec)
    val fileSizeText = humanSize(videoFile?.length() ?: 0L)

    val video = metadata?.optJSONObject("videoMetrics") ?: technical?.optJSONObject("video")
    val imu = metadata?.optJSONObject("imuMetrics") ?: technical?.optJSONObject("imu")
    val sync = metadata?.optJSONObject("syncMetrics") ?: technical?.optJSONObject("timing")
    val capture = metadata?.optJSONObject("capture")
    val fps = video?.optDoubleOrNull("actualAvgFPS") ?: video?.optDoubleOrNull("fps")
    val dropped = video?.optIntOrNull("droppedFrames") ?: 0
    val imuSamples = imu?.optIntOrNull("totalSamples")
    val imuRate = imu?.optDoubleOrNull("actualSampleRateHz") ?: imu?.optDoubleOrNull("sampleRateHz")
    val maxDelta = sync?.optDoubleOrNull("observedMaxDeltaMs")

    var handRate = 0.0
    var faceRate = 0.0
    var brightness: Double? = null
    var blur: Double? = null
    var visualStability: Double? = null
    var handDetectorReady = true
    if (frameQCMetrics.isNotEmpty()) {
        val total = frameQCMetrics.size.toDouble()
        val handCount = frameQCMetrics.count { it.optBoolean("handDetected", false) }
        val faceCount = frameQCMetrics.count { it.optBoolean("faceDetected", false) }
        handDetectorReady = frameQCMetrics.any { it.optBoolean("handDetectorReady", true) }
        brightness = normalizeBrightness(frameQCMetrics.mapNotNull { it.optDoubleOrNull("brightnessScore") }.averageOrNull())
        blur = normalizeSharpness(frameQCMetrics.mapNotNull { it.optDoubleOrNull("blurScore") }.averageOrNull())
        visualStability = frameQCMetrics.mapNotNull { it.optDoubleOrNull("stabilityScore") }.averageOrNull()
        handRate = handCount.toDouble() / total * 100.0
        faceRate = faceCount.toDouble() / total * 100.0
    }

    val landscape = capture?.optString("orientation", "landscape")?.lowercase(Locale.US)?.contains("landscape") ?: true
    val durationOk = durationSec >= 3.0
    val lightingOk = (brightness ?: 70.0) >= 35.0
    val technicalStable = (fps ?: 0.0) >= 25.0 && dropped <= 5 && (maxDelta ?: 0.0) < 15.0
    val stabilityOk = technicalStable && (visualStability ?: 75.0) >= 40.0
    val sharpnessOk = (blur ?: 60.0) >= 40.0

    val qualityChecks = listOf(
        SessionCheck(
            "✋",
            "Hands Visible",
            when {
                !handDetectorReady -> "Detector unavailable"
                handRate > 0 -> "${handRate.format0()}% of frames"
                else -> "No hand detected"
            },
            handDetectorReady && handRate > 0,
        ),
        SessionCheck("🛡", "Face Privacy", if (faceRate == 0.0) "No face detected" else "${faceRate.format0()}% with face", faceRate == 0.0),
        SessionCheck("▭", "Orientation", if (landscape) "Landscape" else "Not landscape", landscape),
        SessionCheck("◷", "Duration", "$durationText recorded", durationOk),
        SessionCheck("☼", "Lighting", brightness?.let { "${it.format0()}/100" } ?: "Not analyzed", lightingOk),
        SessionCheck("▰", "Stability", visualStability?.let { "${it.format0()}/100" } ?: if (stabilityOk) "Steady" else "Review motion/timing", stabilityOk),
        SessionCheck("◉", "Sharpness", blur?.let { "${it.format0()}/100" } ?: "Not analyzed", sharpnessOk),
    )
    val recordingStats = listOf(
        RecordingStat("◷", "Duration", durationText),
        RecordingStat("✋", "Hand Visibility", "${handRate.format0()}%"),
        RecordingStat("▦", "Frames Analyzed", "${frameQCMetrics.size}"),
        RecordingStat("⌁", "Stability", visualStability?.let { "${it.format0()}/100" } ?: if (stabilityOk) "Good" else "Review"),
        RecordingStat("⌁", "IMU Samples", imuSamples?.toString() ?: "n/a"),
        RecordingStat("≋", "IMU Rate", "${imuRate.format0()}Hz"),
    )
    val scoreFromReport = qcReport?.optDoubleOrNull("readinessScore")?.toInt()?.coerceIn(0, 100)
    val score = scoreFromReport ?: computeReadinessFallback(
        handRate = handRate,
        faceRate = faceRate,
        durationOk = durationOk,
        landscape = landscape,
        brightness = brightness,
        blur = blur,
        stability = visualStability,
        technicalStable = technicalStable,
    )
    val scoreLabel = when {
        score >= 85 -> "Upload Ready"
        score >= 65 -> "Needs Review"
        else -> "Blocked"
    }
    val scoreDetail = when {
        scoreFromReport != null && score >= 85 -> "Recording passed QC engine checks."
        scoreFromReport != null -> "QC engine reported checks to review."
        else -> "Derived from available local metrics; QC report missing."
    }

    return SessionTestSummary(
        title = title,
        timestampText = timestampText,
        durationText = durationText,
        fileSizeText = fileSizeText,
        score = score,
        scoreLabel = scoreLabel,
        scoreDetail = scoreDetail,
        videoFile = videoFile,
        s3Prefix = upload?.let { "s3://kaivideo/${it.collectorId}/${it.sessionId}" },
        qualityChecks = qualityChecks,
        recordingStats = recordingStats,
    )
}

private fun readJson(file: java.io.File): JSONObject? =
    runCatching {
        if (file.exists()) JSONObject(file.readText()) else null
    }.getOrNull()

private fun readJsonLines(file: java.io.File): List<JSONObject> =
    runCatching {
        if (!file.exists()) return@runCatching emptyList()
        file.readLines()
            .filter { it.isNotBlank() }
            .mapNotNull { line -> runCatching { JSONObject(line) }.getOrNull() }
    }.getOrDefault(emptyList())

private fun computeReadinessFallback(
    handRate: Double,
    faceRate: Double,
    durationOk: Boolean,
    landscape: Boolean,
    brightness: Double?,
    blur: Double?,
    stability: Double?,
    technicalStable: Boolean,
): Int {
    val durationScore = if (durationOk) 100.0 else 0.0
    val orientationScore = if (landscape) 100.0 else 0.0
    val facePrivacyScore = (100.0 - faceRate).coerceIn(0.0, 100.0)
    val stabilityScore = stability ?: if (technicalStable) 75.0 else 0.0
    val readiness = handRate * 0.20 +
        durationScore * 0.15 +
        orientationScore * 0.12 +
        facePrivacyScore * 0.12 +
        (blur ?: 0.0) * 0.10 +
        (brightness ?: 0.0) * 0.07 +
        stabilityScore * 0.06
    return readiness.roundToInt().coerceIn(0, 100)
}

private fun passCriteriaItem(
    items: MutableList<TestSummaryItem>,
    title: String,
    passed: Boolean,
    detail: String,
) {
    items += TestSummaryItem(title, if (passed) "PASS" else "FAIL", detail, passed)
}

private fun JSONObject.optDoubleOrNull(name: String): Double? =
    if (has(name) && !isNull(name)) optDouble(name) else null

private fun JSONObject.optIntOrNull(name: String): Int? =
    if (has(name) && !isNull(name)) optInt(name) else null

private fun JSONObject.optArrayCount(name: String): Int =
    optJSONArray(name)?.length() ?: 0

private fun Double?.format1(): String =
    this?.let { String.format(Locale.US, "%.1f", it) } ?: "n/a"

private fun Double?.format0(): String =
    this?.let { String.format(Locale.US, "%.0f", it) } ?: "n/a"

private fun Double.format0(): String =
    String.format(Locale.US, "%.0f", this)

private fun formatDuration(seconds: Double): String {
    if (!seconds.isFinite() || seconds <= 0.0) return "n/a"
    val total = seconds.toInt()
    return "${total / 60}:${String.format(Locale.US, "%02d", total % 60)}"
}

private fun normalizeBrightness(value: Double?): Double? =
    value?.let { (if (it <= 1.0) it * 100.0 else it).coerceIn(0.0, 100.0) }

private fun normalizeSharpness(value: Double?): Double? =
    value?.let {
        val normalized = if (it > 100.0) minOf(100.0, maxOf(10.0, (it / 2500.0) * 100.0)) else it
        normalized.coerceIn(0.0, 100.0)
    }

private fun List<Double>.averageOrNull(): Double? =
    if (isEmpty()) null else average()

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
