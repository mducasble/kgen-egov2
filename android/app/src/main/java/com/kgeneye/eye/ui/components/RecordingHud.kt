package com.kgeneye.eye.ui.components

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.kgeneye.eye.ui.theme.KETokens
import com.kgeneye.eye.ui.theme.OrbitronFamily
import kotlin.math.roundToInt

/**
 * Pill at the top of the recording HUD: a pulsing red dot, the "REC" label,
 * a colon separator and the elapsed duration. Mirrors the iOS
 * `EGOCaptureTopPill` used inside `RecordingView`.
 */
@Composable
fun RecPill(
    durationSec: Double,
    title: String? = null,
    modifier: Modifier = Modifier,
) {
    val transition = rememberInfiniteTransition(label = "rec-dot")
    val alpha by transition.animateFloat(
        initialValue = 1f,
        targetValue = 0.3f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 700, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "rec-dot-alpha",
    )

    Row(
        modifier = modifier
            .clip(RoundedCornerShape(22.dp))
            .background(Color.Black.copy(alpha = 0.55f))
            .border(1.dp, KETokens.AccentRed.copy(alpha = 0.7f), RoundedCornerShape(22.dp))
            .padding(horizontal = 14.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(10.dp)
                .clip(CircleShape)
                .background(KETokens.AccentRed)
                .alpha(alpha),
        )
        Spacer(Modifier.width(8.dp))
        Text(
            "REC",
            color = Color.White,
            fontFamily = OrbitronFamily,
            fontWeight = FontWeight.SemiBold,
            fontSize = 14.sp,
        )
        Spacer(Modifier.width(10.dp))
        Text(
            formatDurationLong(durationSec),
            color = Color.White,
            fontFamily = OrbitronFamily,
            fontWeight = FontWeight.Medium,
            fontSize = 16.sp,
        )
        if (!title.isNullOrBlank()) {
            Spacer(Modifier.width(12.dp))
            Box(
                modifier = Modifier
                    .size(width = 1.dp, height = 14.dp)
                    .background(Color.White.copy(alpha = 0.35f)),
            )
            Spacer(Modifier.width(12.dp))
            Text(
                title,
                color = Color.White.copy(alpha = 0.85f),
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium,
            )
        }
    }
}

/**
 * 4-up grid of compact stat cards (`Duration / Frames / IMU / Hz`) anchored
 * to the bottom of the recording HUD. Mirrors `egoStatsGrid` in iOS.
 */
@Composable
fun EgoStatsGrid(
    durationSec: Double,
    frameCount: Int,
    imuSamples: Int,
    imuRateHz: Double,
    sessionId: String?,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        EgoStatCard(
            label = "DURATION",
            value = formatDurationLong(durationSec),
            modifier = Modifier.weight(1f),
        )
        EgoStatCard(
            label = "FRAMES",
            value = frameCount.toString(),
            modifier = Modifier.weight(1f),
        )
        EgoStatCard(
            label = "IMU",
            value = imuSamples.toString(),
            sub = String.format("%.1f Hz", imuRateHz),
            modifier = Modifier.weight(1f),
        )
        EgoStatCard(
            label = "SESSION",
            value = sessionId ?: "—",
            modifier = Modifier.weight(1f),
        )
    }
}

@Composable
private fun EgoStatCard(
    label: String,
    value: String,
    sub: String? = null,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(14.dp))
            .background(Color.Black.copy(alpha = 0.45f))
            .border(1.dp, Color.White.copy(alpha = 0.18f), RoundedCornerShape(14.dp))
            .padding(horizontal = 12.dp, vertical = 8.dp),
    ) {
        Text(
            label,
            color = KETokens.AccentGreen.copy(alpha = 0.95f),
            fontFamily = OrbitronFamily,
            fontWeight = FontWeight.SemiBold,
            fontSize = 10.sp,
        )
        Spacer(Modifier.size(2.dp))
        Text(
            value,
            color = Color.White,
            fontFamily = OrbitronFamily,
            fontWeight = FontWeight.Medium,
            fontSize = 16.sp,
            maxLines = 1,
        )
        if (sub != null) {
            Text(
                sub,
                color = Color.White.copy(alpha = 0.6f),
                fontSize = 10.sp,
                maxLines = 1,
            )
        }
    }
}

/**
 * Faint rule-of-thirds overlay drawn over the camera preview while
 * recording. Mirrors `EGOViewfinderGrid` from the iOS theme.
 */
@Composable
fun EgoViewfinderGrid(modifier: Modifier = Modifier) {
    Canvas(modifier.fillMaxSize()) {
        val color = Color.White.copy(alpha = 0.18f)
        val w = size.width
        val h = size.height
        val strokeWidth = 1f
        for (i in 1..2) {
            val x = w * i / 3f
            drawLine(color, Offset(x, 0f), Offset(x, h), strokeWidth)
        }
        for (i in 1..2) {
            val y = h * i / 3f
            drawLine(color, Offset(0f, y), Offset(w, y), strokeWidth)
        }
    }
}

/**
 * L-shaped framing corners hugging the safe area of the preview.
 * Mirrors `EGOFramingCorners` from the iOS theme.
 */
@Composable
fun EgoFramingCorners(
    modifier: Modifier = Modifier,
    inset: androidx.compose.ui.unit.Dp = 18.dp,
    armLength: androidx.compose.ui.unit.Dp = 26.dp,
    stroke: androidx.compose.ui.unit.Dp = 2.dp,
    color: Color = Color.White.copy(alpha = 0.7f),
) {
    Canvas(modifier.fillMaxSize()) {
        val insetPx = inset.toPx()
        val armPx = armLength.toPx()
        val strokePx = stroke.toPx()
        val w = size.width
        val h = size.height

        // top-left
        drawLine(color, Offset(insetPx, insetPx), Offset(insetPx + armPx, insetPx), strokePx)
        drawLine(color, Offset(insetPx, insetPx), Offset(insetPx, insetPx + armPx), strokePx)
        // top-right
        drawLine(color, Offset(w - insetPx - armPx, insetPx), Offset(w - insetPx, insetPx), strokePx)
        drawLine(color, Offset(w - insetPx, insetPx), Offset(w - insetPx, insetPx + armPx), strokePx)
        // bottom-left
        drawLine(color, Offset(insetPx, h - insetPx), Offset(insetPx + armPx, h - insetPx), strokePx)
        drawLine(color, Offset(insetPx, h - insetPx - armPx), Offset(insetPx, h - insetPx), strokePx)
        // bottom-right
        drawLine(color, Offset(w - insetPx - armPx, h - insetPx), Offset(w - insetPx, h - insetPx), strokePx)
        drawLine(color, Offset(w - insetPx, h - insetPx - armPx), Offset(w - insetPx, h - insetPx), strokePx)
    }
}

/** `MM:SS` if under one hour, otherwise `HH:MM:SS`. */
fun formatDurationLong(seconds: Double): String {
    val total = seconds.coerceAtLeast(0.0).roundToInt()
    val hh = total / 3600
    val mm = (total % 3600) / 60
    val ss = total % 60
    return if (hh > 0) {
        "%02d:%02d:%02d".format(hh, mm, ss)
    } else {
        "%02d:%02d".format(mm, ss)
    }
}

@Suppress("unused")
private val _orbitronFamilyHint: FontFamily = OrbitronFamily
