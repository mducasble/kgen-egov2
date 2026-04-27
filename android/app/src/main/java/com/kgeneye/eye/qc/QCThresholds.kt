package com.kgeneye.eye.qc

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
enum class Orientation {
    @SerialName("portrait")
    PORTRAIT,

    @SerialName("landscape")
    LANDSCAPE,

    @SerialName("any")
    ANY,
}

@Serializable
data class QCThresholds(
    val minDurationMs: Int = 5_000,
    val maxDurationMs: Int = 600_000,
    val requiredOrientation: Orientation = Orientation.LANDSCAPE,
    val minHandPresenceRate: Double = 0.6,
    val maxFacePresenceRate: Double = 0.15,
    val minReadinessScore: Double = 65.0,
    val warnReadinessScore: Double = 85.0,
    val minStabilityScore: Double = 40.0,
    val minBrightnessScore: Double = 35.0,
    val minBlurScore: Double = 40.0,
)
