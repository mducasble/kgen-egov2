package com.kgeneye.eye.ui.components

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import com.kgeneye.eye.R
import com.kgeneye.eye.ui.theme.KETokens

/**
 * Full-screen fixed photographic backdrop shared across the app.
 * A subtle dark veil on top keeps the dark ink text on glass panes readable
 * on the brighter photos; matches `AmbientImageBackdrop` in `KGenEyeHomeView.swift`.
 */
@Composable
fun AmbientBackdrop(
    modifier: Modifier = Modifier,
) {
    val image = remember { R.drawable.ambient_bg }

    Box(modifier = modifier.fillMaxSize()) {
        Image(
            painter = painterResource(image),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize(),
        )
        Box(
            Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        0f to KETokens.BackdropVeilTop,
                        1f to KETokens.BackdropVeilBottom,
                    )
                )
        )
    }
}

/** Minimal solid backdrop for preview/Compose tooling. */
@Composable
fun SolidAmbientBackdrop(color: Color = Color(0xFFEFEEE8), modifier: Modifier = Modifier) {
    Box(modifier.fillMaxSize().background(color))
}
