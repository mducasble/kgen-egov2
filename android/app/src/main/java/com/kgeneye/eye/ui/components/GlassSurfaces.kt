package com.kgeneye.eye.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.kgeneye.eye.ui.theme.KETokens

/**
 * Main inset pane — translucent frost + cool sheen on top + hand-drawn rim.
 * Mirrors `GlassPane` from `KGenEyeHomeView.swift` (iOS 17/18 fallback path;
 * we don't have a Liquid Glass equivalent on Android so the legacy recipe
 * is the default).
 */
@Composable
fun GlassPane(
    modifier: Modifier = Modifier,
    cornerRadius: Dp = 36.dp,
    padding: PaddingValues = PaddingValues(top = 24.dp, start = 22.dp, end = 22.dp, bottom = 28.dp),
    content: @Composable () -> Unit,
) {
    val shape = RoundedCornerShape(cornerRadius)
    Box(
        modifier = modifier
            .shadow(
                elevation = 20.dp,
                shape = shape,
                spotColor = Color(red = 30, green = 40, blue = 55).copy(alpha = 0.22f),
                ambientColor = Color(red = 30, green = 40, blue = 55).copy(alpha = 0.22f),
            )
            .clip(shape)
            .background(KETokens.PaneFrost)
            .background(
                Brush.verticalGradient(
                    0.0f to KETokens.PaneSheenTop,
                    0.35f to KETokens.PaneSheenTop.copy(alpha = 0.04f),
                    0.65f to Color.Transparent,
                )
            )
            .border(1.dp, KETokens.EdgeBright, shape)
            .padding(padding),
    ) { content() }
}

/**
 * Denser surface used for list rows, setting groups and detail tiles.
 * Matches `GlassCard` in `KGenEyeHomeView.swift`.
 */
@Composable
fun GlassCard(
    modifier: Modifier = Modifier,
    cornerRadius: Dp = 22.dp,
    padding: PaddingValues = PaddingValues(16.dp),
    content: @Composable () -> Unit,
) {
    val shape = RoundedCornerShape(cornerRadius)
    Box(
        modifier = modifier
            .shadow(
                elevation = 10.dp,
                shape = shape,
                spotColor = Color.Black.copy(alpha = 0.12f),
                ambientColor = Color.Black.copy(alpha = 0.12f),
            )
            .clip(shape)
            .background(KETokens.CardFrost)
            .background(
                Brush.verticalGradient(
                    0.0f to KETokens.PaneSheenTop.copy(alpha = 0.14f),
                    0.55f to Color.Transparent,
                )
            )
            .border(1.dp, KETokens.EdgeBright.copy(alpha = 0.45f), shape)
            .padding(padding),
    ) { content() }
}

/** Edge-to-edge placeholder used by screens that want to fill an empty pane. */
@Composable
fun FillingGlassPane(content: @Composable () -> Unit) {
    GlassPane(modifier = Modifier.fillMaxSize()) { content() }
}
