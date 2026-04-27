package com.kgeneye.eye.qc

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class QCEngineTest {
    @Test
    fun shortDurationBlocks() {
        val report = run(durationMs = 4_999, frames = happyFrames())

        assertEquals(QCResult.BLOCKED, report.qcResult)
        assertTrue(report.blockReasons.contains("Recording too short (minimum 5s required)"))
    }

    @Test
    fun wrongOrientationBlocks() {
        val report = run(orientation = Orientation.PORTRAIT, frames = happyFrames())

        assertEquals(QCResult.BLOCKED, report.qcResult)
        assertTrue(report.blockReasons.contains("Wrong orientation — landscape required"))
    }

    @Test
    fun veryLowHandPresenceBlocks() {
        val report = run(frames = frames(count = 100) { index -> index < 25 })

        assertEquals(QCResult.BLOCKED, report.qcResult)
        assertTrue(report.blockReasons.contains("Hands not visible enough (25% of frames)"))
    }

    @Test
    fun partialHandPresenceWarns() {
        val report = run(frames = frames(count = 100) { index -> index < 45 })

        assertEquals(QCResult.PASSED_WITH_WARNING, report.qcResult)
        assertTrue(report.warningReasons.contains("Hands partially visible (45% of frames)"))
    }

    @Test
    fun highFacePresenceBlocksPrivacyIssue() {
        val report = run(
            frames = frames(
                count = 100,
                faceDetected = { index -> index < 40 },
                handDetected = { true },
            )
        )

        assertEquals(QCResult.BLOCKED, report.qcResult)
        assertTrue(report.blockReasons.contains("Face detected in 40% of frames — privacy issue"))
    }

    @Test
    fun lowReadinessBlocksWhenNoOtherBlocksExist() {
        val visibleIndexes = setOf(0, 2, 4, 6, 8, 9)
        val lowQualityFrames = frames(count = 10) { index ->
            visibleIndexes.contains(index)
        }.mapIndexed { index, frame ->
            makeFrame(
                handDetected = frame.handDetected,
                handCount = frame.handCount,
                box = BoundingBox(
                    x = if (index in visibleIndexes) 0.95 else 0.0,
                    y = if (index in visibleIndexes) 0.95 else 0.0,
                    width = 0.05,
                    height = 0.05,
                ),
                brightness = 35.0,
                blur = 40.0,
                contrast = 40.0,
            )
        }

        val report = run(
            frames = lowQualityFrames,
            stabilityReadings = List(5) { 40.0 },
        )

        assertEquals(QCResult.BLOCKED, report.qcResult)
        assertTrue(report.blockReasons.contains("Overall quality score too low — please re-record"))
    }

    @Test
    fun happySamplePasses() {
        val report = run(frames = happyFrames())

        assertEquals(QCResult.PASSED, report.qcResult)
        assertTrue(report.readinessScore >= 85)
        assertTrue(report.blockReasons.isEmpty())
        assertTrue(report.warningReasons.isEmpty())
    }

    @Test
    fun emptyStabilityReadingsFallbackTo75() {
        val report = run(frames = happyFrames(), stabilityReadings = emptyList())

        assertEquals(75.0, report.stabilityScore, 0.0)
    }

    private fun run(
        durationMs: Int = 10_000,
        orientation: Orientation = Orientation.LANDSCAPE,
        frames: List<QCFrameSample>,
        stabilityReadings: List<Double> = List(10) { 95.0 },
    ): LocalQCReport =
        QCEngine.run(
            frames = frames,
            stabilityReadings = stabilityReadings,
            durationMs = durationMs,
            orientation = orientation,
            recordingId = "rec-1",
            questId = "quest-1",
            fileSizeBytes = 123_456,
        )

    private fun happyFrames(): List<QCFrameSample> = frames(count = 20) { true }

    private fun frames(
        count: Int,
        faceDetected: (Int) -> Boolean = { false },
        handDetected: (Int) -> Boolean,
    ): List<QCFrameSample> =
        (0 until count).map { index ->
            val hasHand = handDetected(index)
            makeFrame(
                timestampMs = index * 33.333,
                handDetected = hasHand,
                handCount = if (hasHand) 2 else 0,
                box = if (hasHand) BoundingBox(x = 0.35, y = 0.35, width = 0.3, height = 0.3) else null,
                faceDetected = faceDetected(index),
            )
        }

    private fun makeFrame(
        timestampMs: Double = 0.0,
        handDetected: Boolean,
        handCount: Int,
        box: BoundingBox?,
        faceDetected: Boolean = false,
        brightness: Double = 90.0,
        blur: Double = 90.0,
        contrast: Double = 90.0,
    ): QCFrameSample =
        QCFrameSample(
            timestampMs = timestampMs,
            handDetected = handDetected,
            handCount = handCount,
            handConfidence = if (handDetected) 0.95 else 0.0,
            handBoundingBoxes = listOfNotNull(box),
            hands = emptyList(),
            faceDetected = faceDetected,
            faceConfidence = if (faceDetected) 0.85 else 0.0,
            brightnessValue = brightness,
            blurValue = blur,
            contrastValue = contrast,
            motionValue = 0.0,
        )
}
