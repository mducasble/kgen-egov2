package com.kgeneye.eye.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val KEInk0 = Color(0xFF0B1220)
private val KEInk1 = Color(0xFF111A2C)
private val KEInk2 = Color(0xFF1B2741)
private val KEInk3 = Color(0xFFB5C1DA)
private val KEBrand = Color(0xFF7C9CFF)
private val KEAccent = Color(0xFF65E3A9)
private val KEDanger = Color(0xFFF07178)

private val DarkColors = darkColorScheme(
    primary = KEBrand,
    onPrimary = Color.White,
    secondary = KEAccent,
    onSecondary = KEInk0,
    background = KEInk0,
    onBackground = Color.White,
    surface = KEInk1,
    onSurface = Color.White,
    surfaceVariant = KEInk2,
    onSurfaceVariant = KEInk3,
    error = KEDanger,
    onError = Color.White,
)

private val LightColors = lightColorScheme(
    primary = KEBrand,
    secondary = KEAccent,
)

@Composable
fun KGenEyeTheme(
    useDarkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val colors = if (useDarkTheme) DarkColors else LightColors
    MaterialTheme(colorScheme = colors, content = content)
}
