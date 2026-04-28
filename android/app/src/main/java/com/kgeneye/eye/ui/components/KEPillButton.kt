package com.kgeneye.eye.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.kgeneye.eye.ui.theme.KETokens

enum class KEButtonVariant(val tint: Color) {
    Red(KETokens.AccentRed),
    Green(KETokens.AccentGreen),
    Blue(KETokens.AccentBlue),
    Ghost(KETokens.GhostTint),
}

/**
 * Primary pill button — 84dp tall, glass tint matching the variant, ink
 * foreground, chevron trailing edge. Tap target is the full pill.
 */
@Composable
fun KEPillButton(
    label: String,
    icon: ImageVector,
    modifier: Modifier = Modifier,
    variant: KEButtonVariant = KEButtonVariant.Green,
    onClick: () -> Unit,
) {
    val shape = RoundedCornerShape(22.dp)
    Box(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 84.dp)
            .shadow(
                elevation = 16.dp,
                shape = shape,
                spotColor = variant.tint.copy(alpha = 0.45f),
                ambientColor = variant.tint.copy(alpha = 0.35f),
            )
            .clip(shape)
            .background(variant.tint.copy(alpha = 0.55f))
            .background(
                Brush.verticalGradient(
                    0.0f to Color.White.copy(alpha = 0.30f),
                    0.6f to Color.Transparent,
                )
            )
            .border(1.dp, variant.tint.copy(alpha = 0.55f), shape)
            .clickable(onClick = onClick)
            .padding(horizontal = 20.dp),
        contentAlignment = Alignment.CenterStart,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = KETokens.Ink1,
                modifier = Modifier.size(24.dp),
            )
            Spacer(Modifier.width(12.dp))
            Text(
                label,
                color = KETokens.Ink1,
                fontWeight = FontWeight.Medium,
                fontSize = 17.sp,
                modifier = Modifier.weight(1f),
            )
            Icon(
                imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null,
                tint = KETokens.Ink3,
                modifier = Modifier.size(18.dp),
            )
        }
    }
}
