package com.kgeneye.eye.capture

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Matrix
import android.media.MediaMetadataRetriever
import android.util.Log
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarker
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker
import com.kgeneye.eye.qc.BoundingBox
import com.kgeneye.eye.qc.QCEngine
import com.kgeneye.eye.qc.QCFrameSample
import com.kgeneye.eye.qc.Orientation
import com.kgeneye.eye.session.SessionFiles
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File
import java.io.FileWriter
import kotlin.math.max
import kotlin.math.min
import org.json.JSONArray
import org.json.JSONObject

/**
 * Runs hand, face and frame-quality analysis after CameraX finishes writing
 * the MP4. This keeps MediaPipe off the live recording path.
 */
object PostCaptureVisionAnalyzer {
    private const val TAG = "PostCaptureVision"
    private const val MAX_DIMENSION = 640

    data class Result(
        val frameQcRows: Int,
        val handRows: Int,
        val faceRows: Int,
        val framesWithHands: Int,
        val totalHandsDetected: Int,
        val handDetectorReady: Boolean,
    )

    fun analyze(
        context: Context,
        videoFile: File,
        sessionDir: File,
        recordingStartEpochMs: Double,
        timestampsNs: LongArray,
    ): Result {
        val retriever = MediaMetadataRetriever()
        val handLandmarker = buildHandLandmarker(context)
        val faceLandmarker = buildFaceLandmarker(context)
        var frameRows = 0
        var handRows = 0
        var faceRows = 0
        var framesWithHands = 0
        var totalHandsDetected = 0
        var previousFrame: Bitmap? = null
        val qcFrames = mutableListOf<QCFrameSample>()
        val stabilityReadings = mutableListOf<Double>()

        return try {
            retriever.setDataSource(videoFile.absolutePath)
            val durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull()
                ?: return Result(0, 0, 0, 0, 0, handLandmarker != null)
            if (durationMs <= 0) return Result(0, 0, 0, 0, 0, handLandmarker != null)

            val sampleCount = min(20, max(3, (durationMs / 1000L).toInt()))
            val intervalMs = durationMs.toDouble() / sampleCount.toDouble()

            FileWriter(SessionFiles.file("hand_landmarks", "jsonl", sessionDir)).use { handWriter ->
                FileWriter(SessionFiles.file("face_presence", "jsonl", sessionDir)).use { faceWriter ->
                    FileWriter(SessionFiles.file("frame_qc_metrics", "jsonl", sessionDir)).use { frameWriter ->
                        for (index in 0 until sampleCount) {
                            val relativeMs = intervalMs * (index.toDouble() + 0.5)
                            val bitmap = retriever.getFrameAtTime(
                                (relativeMs * 1000.0).toLong(),
                                MediaMetadataRetriever.OPTION_CLOSEST,
                            ) ?: continue
                            val softwareBitmap = bitmap.softwareArgb()
                            if (softwareBitmap !== bitmap) bitmap.recycle()
                            val scaled = softwareBitmap.scaledForAnalysis()
                            if (scaled !== softwareBitmap) softwareBitmap.recycle()

                            val hands = detectHands(handLandmarker, scaled)
                            val face = detectFace(faceLandmarker, scaled)
                            val imageMetrics = pixelMetrics(scaled)
                            val visualMotion = previousFrame?.let { computeMotionValue(it, scaled) } ?: 0.0
                            val visualStability = (100.0 - visualMotion).coerceIn(0.0, 100.0)
                            stabilityReadings += visualStability
                            previousFrame?.recycle()
                            previousFrame = scaled.copy(Bitmap.Config.ARGB_8888, false)
                            scaled.recycle()
                            if (hands.isNotEmpty()) framesWithHands += 1
                            totalHandsDetected += hands.size
                            qcFrames += qcFrameSample(
                                relativeMs = relativeMs,
                                hands = hands,
                                face = face,
                                metrics = imageMetrics,
                                motionValue = visualMotion,
                            )

                            val timestampNs = nearestTimestampNs(relativeMs, timestampsNs)
                            val timestampEpochMs = recordingStartEpochMs + relativeMs

                            handWriter.write(handJson(timestampEpochMs, relativeMs, timestampNs, index, hands).toString())
                            handWriter.write("\n")
                            handRows += 1

                            faceWriter.write(faceJson(timestampEpochMs, relativeMs, index, face).toString())
                            faceWriter.write("\n")
                            faceRows += 1

                            frameWriter.write(
                                frameQcJson(
                                    timestampEpochMs = timestampEpochMs,
                                    relativeMs = relativeMs,
                                    frameIndex = index,
                                    hands = hands,
                                    handDetectorReady = handLandmarker != null,
                                    faceDetected = face.detected,
                                    metrics = imageMetrics,
                                    motionValue = visualMotion,
                                    stabilityScore = visualStability,
                                ).toString(),
                            )
                            frameWriter.write("\n")
                            frameRows += 1
                        }
                    }
                }
            }

            writeQCReport(
                sessionDir = sessionDir,
                sessionId = sessionDir.name,
                durationMs = durationMs,
                videoFile = videoFile,
                frames = qcFrames,
                stabilityReadings = stabilityReadings,
            )

            Result(frameRows, handRows, faceRows, framesWithHands, totalHandsDetected, handLandmarker != null)
        } catch (t: Throwable) {
            Log.w(TAG, "post-capture analysis failed: ${t.message}")
            Result(frameRows, handRows, faceRows, framesWithHands, totalHandsDetected, handLandmarker != null)
        } finally {
            try { previousFrame?.recycle() } catch (_: Throwable) {}
            try { retriever.release() } catch (_: Throwable) {}
            try { handLandmarker?.close() } catch (_: Throwable) {}
            try { faceLandmarker?.close() } catch (_: Throwable) {}
        }
    }

    private fun buildHandLandmarker(context: Context): HandLandmarker? {
        return try {
            val options = HandLandmarker.HandLandmarkerOptions.builder()
                .setBaseOptions(BaseOptions.builder().setModelAssetPath("hand_landmarker.task").build())
                .setRunningMode(RunningMode.IMAGE)
                .setNumHands(2)
                .setMinHandDetectionConfidence(0.3f)
                .setMinHandPresenceConfidence(0.3f)
                .setMinTrackingConfidence(0.3f)
                .build()
            HandLandmarker.createFromOptions(context, options)
        } catch (t: Throwable) {
            Log.w(TAG, "hand landmarker unavailable: ${t.message}")
            null
        }
    }

    private fun buildFaceLandmarker(context: Context): FaceLandmarker? {
        return try {
            val options = FaceLandmarker.FaceLandmarkerOptions.builder()
                .setBaseOptions(BaseOptions.builder().setModelAssetPath("face_landmarker.task").build())
                .setRunningMode(RunningMode.IMAGE)
                .setNumFaces(1)
                .setMinFaceDetectionConfidence(0.4f)
                .setMinFacePresenceConfidence(0.4f)
                .setMinTrackingConfidence(0.4f)
                .build()
            FaceLandmarker.createFromOptions(context, options)
        } catch (t: Throwable) {
            Log.w(TAG, "face landmarker unavailable: ${t.message}")
            null
        }
    }

    private fun detectHands(landmarker: HandLandmarker?, bitmap: Bitmap): List<DetectedHand> {
        if (landmarker == null) return emptyList()
        var bestHands: List<DetectedHand> = emptyList()
        var bestScore = -1.0
        for (rotation in listOf(0, 90, -90, 180)) {
            val candidateBitmap = if (rotation == 0) bitmap else bitmap.rotated(rotation.toFloat())
            val hands = detectHandsSingleOrientation(landmarker, candidateBitmap, rotation)
            if (candidateBitmap !== bitmap) candidateBitmap.recycle()
            val score = hands.size.toDouble() + hands.sumOf { it.confidence }
            if (score > bestScore) {
                bestScore = score
                bestHands = hands
            }
            if (hands.size >= 2) break
        }
        return bestHands
    }

    private fun detectHandsSingleOrientation(
        landmarker: HandLandmarker,
        bitmap: Bitmap,
        rotationDegrees: Int,
    ): List<DetectedHand> {
        return try {
            val result = landmarker.detect(BitmapImageBuilder(bitmap).build())
            result.landmarks().mapIndexed { handIndex, landmarks ->
                val handedness = result.handedness().getOrNull(handIndex)?.firstOrNull()
                val points = landmarks.mapIndexed { idx, lm ->
                    mapLandmarkToOriginal(
                        idx = idx,
                        x = lm.x().toDouble(),
                        y = lm.y().toDouble(),
                        z = lm.z().toDouble(),
                        rotationDegrees = rotationDegrees,
                    )
                }
                DetectedHand(
                    handedness = handedness?.categoryName() ?: "Unknown",
                    confidence = handedness?.score()?.toDouble() ?: 0.0,
                    landmarks = points,
                    detectionRotationDegrees = rotationDegrees,
                )
            }
        } catch (t: Throwable) {
            Log.w(TAG, "hand detection failed: ${t.message}")
            emptyList()
        }
    }

    private fun detectFace(landmarker: FaceLandmarker?, bitmap: Bitmap): FaceResult {
        if (landmarker == null) return FaceResult(false, 0.0)
        return try {
            val result = landmarker.detect(BitmapImageBuilder(bitmap).build())
            val detected = result.faceLandmarks().isNotEmpty()
            FaceResult(detected, if (detected) 0.6 else 0.0)
        } catch (t: Throwable) {
            Log.w(TAG, "face detection failed: ${t.message}")
            FaceResult(false, 0.0)
        }
    }

    private fun handJson(
        timestampEpochMs: Double,
        relativeMs: Double,
        timestampNs: Long,
        frameIndex: Int,
        hands: List<DetectedHand>,
    ): JSONObject = JSONObject()
        .put("timestampEpochMs", timestampEpochMs)
        .put("relativeMs", relativeMs)
        .put("timestampNs", timestampNs)
        .put("frameIndex", frameIndex)
        .put("hands", JSONArray().also { array ->
            hands.forEach { hand ->
                array.put(
                    JSONObject()
                        .put("handedness", hand.handedness)
                        .put("confidence", hand.confidence)
                        .put("source", "mediapipe")
                        .put("detectionRotationDegrees", hand.detectionRotationDegrees)
                        .put("landmarks", JSONArray().also { landmarks ->
                            hand.landmarks.forEach { lm ->
                                landmarks.put(
                                    JSONObject()
                                        .put("id", lm.id)
                                        .put("x", lm.x)
                                        .put("y", lm.y)
                                        .put("z", lm.z),
                                )
                            }
                        }),
                )
            }
        })

    private fun faceJson(
        timestampEpochMs: Double,
        relativeMs: Double,
        frameIndex: Int,
        face: FaceResult,
    ): JSONObject = JSONObject()
        .put("timestampEpochMs", timestampEpochMs)
        .put("relativeMs", relativeMs)
        .put("frameIndex", frameIndex)
        .put("faceDetected", face.detected)
        .put("confidence", face.confidence)

    private fun frameQcJson(
        timestampEpochMs: Double,
        relativeMs: Double,
        frameIndex: Int,
        hands: List<DetectedHand>,
        handDetectorReady: Boolean,
        faceDetected: Boolean,
        metrics: ImageMetrics,
        motionValue: Double,
        stabilityScore: Double,
    ): JSONObject = JSONObject()
        .put("timestampEpochMs", timestampEpochMs)
        .put("relativeMs", relativeMs)
        .put("frameIndex", frameIndex)
        .put("brightnessScore", metrics.brightness)
        .put("blurScore", metrics.blur)
        .put("contrastScore", metrics.contrast)
        .put("motionValue", motionValue)
        .put("stabilityScore", stabilityScore)
        .put("handDetected", hands.isNotEmpty())
        .put("handCount", hands.size)
        .put("handConfidence", hands.firstOrNull()?.confidence ?: 0.0)
        .put("handDetectorReady", handDetectorReady)
        .put("handDetectionRotationDegrees", hands.firstOrNull()?.detectionRotationDegrees ?: 0)
        .put("faceDetected", faceDetected)

    private fun nearestTimestampNs(relativeMs: Double, timestampsNs: LongArray): Long {
        if (timestampsNs.isEmpty()) return 0L
        val targetOffsetNs = (relativeMs * 1_000_000.0).toLong()
        val first = timestampsNs.first()
        return timestampsNs.minBy { kotlin.math.abs((it - first) - targetOffsetNs) }
    }

    private fun Bitmap.scaledForAnalysis(): Bitmap {
        val maxDim = max(width, height)
        if (maxDim <= MAX_DIMENSION) return this
        val scale = MAX_DIMENSION.toDouble() / maxDim.toDouble()
        val targetW = max(1, (width * scale).toInt())
        val targetH = max(1, (height * scale).toInt())
        return Bitmap.createScaledBitmap(this, targetW, targetH, true)
    }

    private fun Bitmap.softwareArgb(): Bitmap =
        if (config == Bitmap.Config.ARGB_8888 && !isRecycled) this else copy(Bitmap.Config.ARGB_8888, false)

    private fun Bitmap.rotated(degrees: Float): Bitmap {
        val matrix = Matrix().apply { postRotate(degrees) }
        return Bitmap.createBitmap(this, 0, 0, width, height, matrix, true)
    }

    private fun mapLandmarkToOriginal(
        idx: Int,
        x: Double,
        y: Double,
        z: Double,
        rotationDegrees: Int,
    ): Landmark {
        val mapped = when (rotationDegrees) {
            90 -> Landmark(idx, y, 1.0 - x, z)
            -90 -> Landmark(idx, 1.0 - y, x, z)
            180, -180 -> Landmark(idx, 1.0 - x, 1.0 - y, z)
            else -> Landmark(idx, x, y, z)
        }
        return Landmark(
            id = mapped.id,
            x = mapped.x.coerceIn(0.0, 1.0),
            y = mapped.y.coerceIn(0.0, 1.0),
            z = mapped.z,
        )
    }

    private fun pixelMetrics(bitmap: Bitmap): ImageMetrics {
        val width = bitmap.width
        val height = bitmap.height
        val total = width * height
        if (total <= 0) return ImageMetrics(0.0, 0.0, 0.0)

        val step = max(1, total / 2000)
        var count = 0
        var sum = 0.0
        var sumSq = 0.0
        var idx = 0
        while (idx < total) {
            val x = idx % width
            val y = idx / width
            val pixel = bitmap.getPixel(x, y)
            val r = (pixel shr 16) and 0xff
            val g = (pixel shr 8) and 0xff
            val b = pixel and 0xff
            val luminance = 0.299 * r + 0.587 * g + 0.114 * b
            sum += luminance
            sumSq += luminance * luminance
            count += 1
            idx += step
        }
        if (count == 0) return ImageMetrics(0.0, 0.0, 0.0)

        val mean = sum / count.toDouble()
        val variance = max(0.0, (sumSq / count.toDouble()) - (mean * mean))
        val brightness = min(100.0, Math.pow(mean / 255.0, 1.0 / 2.2) * 100.0)
        val blur = min(100.0, max(10.0, (variance / 2500.0) * 100.0))
        val contrast = min(100.0, variance / 30.0)
        return ImageMetrics(brightness, blur, contrast)
    }

    private fun qcFrameSample(
        relativeMs: Double,
        hands: List<DetectedHand>,
        face: FaceResult,
        metrics: ImageMetrics,
        motionValue: Double,
    ): QCFrameSample {
        val boxes = hands.map { boundingBox(it.landmarks) }
        return QCFrameSample(
            timestampMs = relativeMs,
            handDetected = hands.isNotEmpty(),
            handCount = hands.size,
            handConfidence = hands.firstOrNull()?.confidence ?: 0.0,
            handBoundingBoxes = boxes,
            hands = hands.mapIndexed { index, hand ->
                com.kgeneye.eye.qc.DetectedHand(
                    handedness = hand.handedness,
                    confidence = hand.confidence,
                    landmarks = hand.landmarks.map { com.kgeneye.eye.qc.Landmark(it.x, it.y, it.z) },
                    boundingBox = boxes.getOrElse(index) { BoundingBox(0.0, 0.0, 0.0, 0.0) },
                )
            },
            faceDetected = face.detected,
            faceConfidence = face.confidence,
            brightnessValue = metrics.brightness,
            blurValue = metrics.blur,
            contrastValue = metrics.contrast,
            motionValue = motionValue,
        )
    }

    private fun boundingBox(landmarks: List<Landmark>): BoundingBox {
        if (landmarks.isEmpty()) return BoundingBox(0.0, 0.0, 0.0, 0.0)
        val minX = landmarks.minOf { it.x }.coerceIn(0.0, 1.0)
        val maxX = landmarks.maxOf { it.x }.coerceIn(0.0, 1.0)
        val minY = landmarks.minOf { it.y }.coerceIn(0.0, 1.0)
        val maxY = landmarks.maxOf { it.y }.coerceIn(0.0, 1.0)
        return BoundingBox(minX, minY, (maxX - minX).coerceAtLeast(0.0), (maxY - minY).coerceAtLeast(0.0))
    }

    private fun writeQCReport(
        sessionDir: File,
        sessionId: String,
        durationMs: Long,
        videoFile: File,
        frames: List<QCFrameSample>,
        stabilityReadings: List<Double>,
    ) {
        if (frames.isEmpty()) return
        runCatching {
            val report = QCEngine.run(
                frames = frames,
                stabilityReadings = stabilityReadings,
                durationMs = durationMs.coerceAtMost(Int.MAX_VALUE.toLong()).toInt(),
                orientation = Orientation.LANDSCAPE,
                recordingId = sessionId,
                questId = sessionId,
                fileSizeBytes = videoFile.length(),
            )
            val json = Json { prettyPrint = true; encodeDefaults = true }
            SessionFiles.file("qc_report", "json", sessionDir).writeText(json.encodeToString(report))
        }.onFailure { error ->
            Log.w(TAG, "qc_report write failed: ${error.message}")
        }
    }

    private fun computeMotionValue(previous: Bitmap, current: Bitmap): Double {
        val width = min(previous.width, current.width)
        val height = min(previous.height, current.height)
        val total = width * height
        if (total <= 0) return 0.0

        val step = max(1, total / 2000)
        var count = 0
        var diffSum = 0.0
        var idx = 0
        while (idx < total) {
            val x = idx % width
            val y = idx / width
            diffSum += kotlin.math.abs(luminance(previous.getPixel(x, y)) - luminance(current.getPixel(x, y)))
            count += 1
            idx += step
        }
        if (count == 0) return 0.0
        val averageDiff = diffSum / count.toDouble()
        return ((averageDiff / 60.0) * 100.0).coerceIn(0.0, 100.0)
    }

    private fun luminance(pixel: Int): Double {
        val r = (pixel shr 16) and 0xff
        val g = (pixel shr 8) and 0xff
        val b = pixel and 0xff
        return 0.299 * r + 0.587 * g + 0.114 * b
    }

    private data class Landmark(val id: Int, val x: Double, val y: Double, val z: Double)
    private data class DetectedHand(
        val handedness: String,
        val confidence: Double,
        val landmarks: List<Landmark>,
        val detectionRotationDegrees: Int,
    )
    private data class FaceResult(val detected: Boolean, val confidence: Double)
    private data class ImageMetrics(val brightness: Double, val blur: Double, val contrast: Double)
}
