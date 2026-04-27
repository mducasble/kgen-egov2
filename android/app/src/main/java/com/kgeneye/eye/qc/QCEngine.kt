package com.kgeneye.eye.qc

import java.util.Locale
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sqrt

object QCEngine {
    fun run(
        frames: List<QCFrameSample>,
        stabilityReadings: List<Double>,
        durationMs: Int,
        orientation: Orientation,
        thresholds: QCThresholds = QCThresholds(),
        recordingId: String,
        questId: String,
        fileSizeBytes: Long,
    ): LocalQCReport {
        val handPresenceRate = frames.rate { it.handDetected }
        val dualHandRate = frames.rate { it.handCount >= 2 }
        val facePresenceRate = frames.rate { it.faceDetected }
        val blurScore = mean(frames.map { it.blurValue }).clamp(0.0, 100.0)
        val brightnessScore = mean(frames.map { it.brightnessValue }).clamp(0.0, 100.0)
        val contrastScore = mean(frames.map { it.contrastValue }).clamp(0.0, 100.0)
        val stabilityScore = if (stabilityReadings.isEmpty()) {
            75.0
        } else {
            mean(stabilityReadings).clamp(0.0, 100.0)
        }
        val handContinuityScore = computeHandContinuityScore(frames)
        val handCenteringScore = computeHandCenteringScore(frames)
        val averageHandArea = computeAverageHandArea(frames)

        val durationScore = when {
            durationMs < thresholds.minDurationMs -> 0.0
            durationMs > thresholds.maxDurationMs -> 50.0
            else -> 100.0
        }
        val orientationScore =
            if (thresholds.requiredOrientation == Orientation.ANY || orientation == thresholds.requiredOrientation) 100.0 else 0.0
        val handPresenceScore = (handPresenceRate * 100).clamp(0.0, 100.0)
        val facePrivacyScore = (100 - facePresenceRate * 100).clamp(0.0, 100.0)
        val framingScore = handCenteringScore

        val readinessScore = (
            handPresenceScore * 0.20 +
                durationScore * 0.15 +
                orientationScore * 0.12 +
                facePrivacyScore * 0.12 +
                handContinuityScore * 0.10 +
                blurScore * 0.10 +
                framingScore * 0.08 +
                brightnessScore * 0.07 +
                stabilityScore * 0.06
            ).clamp(0.0, 100.0)

        val blockReasons = mutableListOf<String>()
        val warningReasons = mutableListOf<String>()

        if (durationMs < thresholds.minDurationMs) {
            blockReasons += "Recording too short (minimum ${thresholds.minDurationMs / 1000}s required)"
        }
        if (thresholds.requiredOrientation != Orientation.ANY && orientation != thresholds.requiredOrientation) {
            blockReasons += "Wrong orientation — ${thresholds.requiredOrientation.rawValue()} required"
        }
        if (handPresenceRate < thresholds.minHandPresenceRate * 0.5) {
            blockReasons += "Hands not visible enough (${formatPercent(handPresenceRate)}% of frames)"
        } else if (handPresenceRate < thresholds.minHandPresenceRate) {
            warningReasons += "Hands partially visible (${formatPercent(handPresenceRate)}% of frames)"
        }
        if (facePresenceRate > thresholds.maxFacePresenceRate * 2) {
            blockReasons += "Face detected in ${formatPercent(facePresenceRate)}% of frames — privacy issue"
        } else if (facePresenceRate > thresholds.maxFacePresenceRate) {
            warningReasons += "Face briefly detected (${formatPercent(facePresenceRate)}% of frames)"
        }
        if (brightnessScore < thresholds.minBrightnessScore) {
            warningReasons += "Video appears dark — consider better lighting"
        }
        if (blurScore < thresholds.minBlurScore) {
            warningReasons += "Video appears blurry — hold camera steady"
        }
        if (stabilityScore < thresholds.minStabilityScore) {
            warningReasons += "Excessive camera movement detected"
        }

        val qcResult = if (blockReasons.isNotEmpty() || readinessScore < thresholds.minReadinessScore) {
            if (readinessScore < thresholds.minReadinessScore && blockReasons.isEmpty()) {
                blockReasons += "Overall quality score too low — please re-record"
            }
            QCResult.BLOCKED
        } else if (warningReasons.isNotEmpty() || readinessScore < thresholds.warnReadinessScore) {
            QCResult.PASSED_WITH_WARNING
        } else {
            QCResult.PASSED
        }

        return LocalQCReport(
            recordingId = recordingId,
            questId = questId,
            durationMs = durationMs,
            resolutionWidth = 1080,
            resolutionHeight = 1920,
            fps = 30,
            orientation = orientation,
            audioPresent = true,
            fileSizeBytes = fileSizeBytes,
            fileIntegrityPassed = true,
            sampledFrameCount = frames.size,
            handPresenceRate = handPresenceRate,
            dualHandRate = dualHandRate,
            facePresenceRate = facePresenceRate,
            averageHandArea = averageHandArea,
            handCenteringScore = handCenteringScore,
            handContinuityScore = handContinuityScore,
            blurScore = blurScore,
            brightnessScore = brightnessScore,
            contrastScore = contrastScore,
            stabilityScore = stabilityScore,
            readinessScore = readinessScore,
            qcResult = qcResult,
            blockReasons = blockReasons,
            warningReasons = warningReasons,
            generatedAt = System.currentTimeMillis(),
        )
    }

    internal fun computeHandContinuityScore(frames: List<QCFrameSample>): Double {
        if (frames.size < 2) return 100.0
        val transitions = frames.zipWithNext().count { (previous, current) ->
            current.handDetected != previous.handDetected
        }
        val maxTransitions = frames.size - 1
        return (100 - (transitions.toDouble() / maxTransitions.toDouble()) * 100).clamp(0.0, 100.0)
    }

    internal fun computeHandCenteringScore(frames: List<QCFrameSample>): Double {
        val scores = frames.mapNotNull { frame ->
            val box = frame.handBoundingBoxes.firstOrNull()
            if (!frame.handDetected || box == null) return@mapNotNull null
            val cx = box.x + box.width / 2
            val cy = box.y + box.height / 2
            val distance = sqrt((cx - 0.5).pow(2) + (cy - 0.5).pow(2))
            (100 - distance * 150).clamp(0.0, 100.0)
        }
        return if (scores.isEmpty()) 50.0 else mean(scores)
    }

    internal fun computeAverageHandArea(frames: List<QCFrameSample>): Double {
        val areas = frames.mapNotNull { frame ->
            val box = frame.handBoundingBoxes.firstOrNull()
            if (!frame.handDetected || box == null) return@mapNotNull null
            box.width * box.height
        }
        return if (areas.isEmpty()) 0.0 else mean(areas)
    }

    private fun List<QCFrameSample>.rate(predicate: (QCFrameSample) -> Boolean): Double =
        if (isEmpty()) 0.0 else count(predicate).toDouble() / size.toDouble()

    private fun mean(values: List<Double>): Double =
        if (values.isEmpty()) 0.0 else values.sum() / values.size.toDouble()

    private fun Double.clamp(minValue: Double, maxValue: Double): Double =
        min(max(this, minValue), maxValue)

    private fun Orientation.rawValue(): String = when (this) {
        Orientation.PORTRAIT -> "portrait"
        Orientation.LANDSCAPE -> "landscape"
        Orientation.ANY -> "any"
    }

    private fun formatPercent(rate: Double): String {
        val percent = rate * 100
        if (percent == percent.toLong().toDouble()) return percent.toLong().toString()
        return String.format(Locale.US, "%.15f", percent).trimEnd('0').trimEnd('.')
    }
}
