package com.kgeneye.eye.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.ImageLoader
import coil.compose.AsyncImage
import coil.decode.SvgDecoder
import coil.request.ImageRequest
import com.kgeneye.eye.R
import com.kgeneye.eye.ui.theme.KETokens
import com.kgeneye.eye.ui.theme.OrbitronFamily

/** KGeN Eye wordmark rendered from the same SVG used by the iOS app. */
@Composable
fun KGenEyeLogo(width: Dp = 240.dp) {
    val context = LocalContext.current
    val loader = remember(context) {
        ImageLoader.Builder(context)
            .components { add(SvgDecoder.Factory()) }
            .build()
    }
    val request = remember(context) {
        ImageRequest.Builder(context)
            .data(R.raw.kgen_eye_logo)
            .decoderFactory(SvgDecoder.Factory())
            .build()
    }
    AsyncImage(
        model = request,
        imageLoader = loader,
        contentDescription = "KGeN Eye",
        modifier = Modifier
            .width(width)
            .height(width * (966.05f / 1106.57f))
            .shadow(8.dp, clip = false),
    )
}

/** Text portion of the brand lockup — Orbitron, tracked, dark ink. */
@Composable
fun BrandLockup(modifier: Modifier = Modifier) {
    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(
            "KGeN© EYE",
            fontFamily = OrbitronFamily,
            fontWeight = FontWeight.Bold,
            fontSize = 23.sp,
            letterSpacing = 2.4.sp,
            color = KETokens.Ink1,
        )
        Text(
            "EGOCENTRIC YIELD ENGINE",
            fontFamily = OrbitronFamily,
            fontWeight = FontWeight.Medium,
            fontSize = 14.sp,
            letterSpacing = 2.0.sp,
            color = KETokens.Ink2,
        )
    }
}

@Composable
fun GlassLogoBadge(modifier: Modifier = Modifier) {
    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        KGenEyeLogo(width = 240.dp)
        Spacer(Modifier.height(4.dp))
        BrandLockup()
    }
}
