package com.kgeneye.eye.qc

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
enum class QCResult {
    @SerialName("passed")
    PASSED,

    @SerialName("passed_with_warning")
    PASSED_WITH_WARNING,

    @SerialName("blocked")
    BLOCKED,
}

@Serializable
data class LocalQCReport(
    val recordingId: String,
    val questId: String,
    val durationMs: Int,
    val resolutionWidth: Int,
    val resolutionHeight: Int,
    val fps: Int,
    val orientation: Orientation,
    val audioPresent: Boolean,
    val fileSizeBytes: Long,
    val fileIntegrityPassed: Boolean,
    val sampledFrameCount: Int,
    val handPresenceRate: Double,
    val dualHandRate: Double,
    val facePresenceRate: Double,
    val averageHandArea: Double,
    val handCenteringScore: Double,
    val handContinuityScore: Double,
    val blurScore: Double,
    val brightnessScore: Double,
    val contrastScore: Double,
    val stabilityScore: Double,
    val readinessScore: Double,
    val qcResult: QCResult,
    val blockReasons: List<String>,
    val warningReasons: List<String>,
    val generatedAt: Long,
)
