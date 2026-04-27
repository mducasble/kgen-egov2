package com.kgeneye.eye.qc

import kotlinx.serialization.Serializable

@Serializable
data class BoundingBox(
    val x: Double,
    val y: Double,
    val width: Double,
    val height: Double,
)

@Serializable
data class Landmark(
    val x: Double,
    val y: Double,
    val z: Double,
)

@Serializable
data class DetectedHand(
    val handedness: String,
    val confidence: Double,
    val landmarks: List<Landmark>,
    val boundingBox: BoundingBox,
)

@Serializable
data class QCFrameSample(
    val timestampMs: Double,
    val handDetected: Boolean,
    val handCount: Int,
    val handConfidence: Double,
    val handBoundingBoxes: List<BoundingBox>,
    val hands: List<DetectedHand> = emptyList(),
    val faceDetected: Boolean,
    val faceConfidence: Double,
    val brightnessValue: Double,
    val blurValue: Double,
    val contrastValue: Double,
    val motionValue: Double,
)
