package com.kgeneye.eye.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.kgeneye.eye.R

/**
 * Design tokens mirroring `EgoCapture/Views/KGenEyeHomeView.swift` (enum `KE`).
 *
 * The iOS app uses a light Ambient Glass chrome with dark ink text on
 * translucent surfaces over a photographic backdrop, so the Android theme
 * flips Material's default dark assumption and uses a light scheme tuned to
 * read on top of the rotating ambient photos.
 */
object KETokens {
    // Accents
    val AccentGreen = Color(red = 127, green = 200, blue = 160)
    val AccentBlue  = Color(red = 140, green = 175, blue = 210)
    val AccentRed   = Color(red = 220, green = 110, blue = 110)
    val GhostTint   = Color(red = 210, green = 222, blue = 240)

    // Ink (on-glass text)
    val Ink1 = Color(red = 25, green = 40, blue = 55).copy(alpha = 0.92f)
    val Ink2 = Color(red = 30, green = 45, blue = 65).copy(alpha = 0.72f)
    val Ink3 = Color(red = 30, green = 45, blue = 65).copy(alpha = 0.55f)

    // Glass edges
    val EdgeBright = Color.White.copy(alpha = 0.55f)
    val EdgeShadow = Color(red = 60, green = 75, blue = 95).copy(alpha = 0.22f)

    // Pane fills
    val PaneFrost    = Color.White.copy(alpha = 0.55f)
    val PaneSheenTop = Color(red = 180, green = 205, blue = 235).copy(alpha = 0.18f)
    val CardFrost    = Color(red = 240, green = 246, blue = 254).copy(alpha = 0.60f)

    // Veil applied on top of the ambient backdrop to keep ink readable.
    val BackdropVeilTop = Color(red = 18, green = 26, blue = 40).copy(alpha = 0.10f)
    val BackdropVeilBottom = Color(red = 18, green = 26, blue = 40).copy(alpha = 0.04f)
}

/** Orbitron family — variable TTF shipped at `res/font/orbitron.ttf`. */
val OrbitronFamily = FontFamily(
    Font(R.font.orbitron, FontWeight.Normal),
    Font(R.font.orbitron, FontWeight.Medium),
    Font(R.font.orbitron, FontWeight.SemiBold),
    Font(R.font.orbitron, FontWeight.Bold),
)

private val KeTypography = Typography(
    displayLarge = TextStyle(fontFamily = OrbitronFamily, fontWeight = FontWeight.Bold, fontSize = 28.sp, letterSpacing = 2.4.sp),
    displayMedium = TextStyle(fontFamily = OrbitronFamily, fontWeight = FontWeight.Bold, fontSize = 23.sp, letterSpacing = 2.4.sp),
    displaySmall = TextStyle(fontFamily = OrbitronFamily, fontWeight = FontWeight.Medium, fontSize = 14.sp, letterSpacing = 2.0.sp),
    titleLarge = TextStyle(fontFamily = FontFamily.Default, fontWeight = FontWeight.SemiBold, fontSize = 20.sp),
    titleMedium = TextStyle(fontFamily = FontFamily.Default, fontWeight = FontWeight.Medium, fontSize = 17.sp),
    bodyLarge = TextStyle(fontFamily = FontFamily.Default, fontWeight = FontWeight.Normal, fontSize = 16.sp),
    bodyMedium = TextStyle(fontFamily = FontFamily.Default, fontWeight = FontWeight.Normal, fontSize = 14.sp),
    bodySmall = TextStyle(fontFamily = FontFamily.Default, fontWeight = FontWeight.Normal, fontSize = 12.sp),
    labelLarge = TextStyle(fontFamily = FontFamily.Default, fontWeight = FontWeight.Medium, fontSize = 14.sp),
)

private val LightScheme = lightColorScheme(
    primary = KETokens.AccentGreen,
    onPrimary = KETokens.Ink1,
    secondary = KETokens.AccentBlue,
    onSecondary = KETokens.Ink1,
    tertiary = KETokens.AccentRed,
    onTertiary = Color.White,
    background = Color(0xFFEFEEE8),
    onBackground = KETokens.Ink1,
    surface = KETokens.PaneFrost,
    onSurface = KETokens.Ink1,
    surfaceVariant = KETokens.CardFrost,
    onSurfaceVariant = KETokens.Ink2,
    error = KETokens.AccentRed,
)

@Composable
fun KGenEyeTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = LightScheme,
        typography = KeTypography,
        content = content,
    )
}
