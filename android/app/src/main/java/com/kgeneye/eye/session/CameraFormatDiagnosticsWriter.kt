package com.kgeneye.eye.session

import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CameraMetadata
import android.media.MediaRecorder
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.Locale
import kotlin.math.atan
import kotlin.math.hypot
import kotlin.math.roundToInt

/**
 * Writes `camera_format_diagnostics_<code>.json` for the rear camera that
 * CameraX selected. Mirrors iOS' `VideoCaptureService.writeDiagnostics`:
 *
 * ```
 * {
 *   "deviceType": "...",
 *   "selectedFormat": { width, height, horizontalFovDeg, diagonalFovDeg, ... },
 *   "allFormats": [ { width, height, horizontalFovDeg, diagonalFovDeg, ... }, ... ]
 * }
 * ```
 *
 * Field semantics match iOS so a single backend report covers both
 * platforms. FOV is computed from `LENS_INFO_AVAILABLE_FOCAL_LENGTHS` and
 * `SENSOR_INFO_PHYSICAL_SIZE`, which are the Android-equivalent of iOS'
 * `videoFieldOfView` on `AVCaptureDeviceFormat`.
 */
object CameraFormatDiagnosticsWriter {

    /**
     * Snapshot the active rear-facing camera's diagnostics. When
     * [cameraId] is non-null we report against that exact physical
     * camera (the one CameraX bound), so the dump matches what the
     * recorder actually used. Falls back to the first back camera
     * otherwise.
     */
    fun write(
        context: Context,
        sessionDir: File,
        selectedWidth: Int?,
        selectedHeight: Int?,
        cameraId: String? = null,
    ) {
        try {
            val manager = context.getSystemService(Context.CAMERA_SERVICE) as? CameraManager ?: return
            val targetId = cameraId ?: pickRearCameraId(manager) ?: return
            val chars = manager.getCameraCharacteristics(targetId)
            writeReport(sessionDir, chars, selectedWidth, selectedHeight)
        } catch (t: Throwable) {
            Log.w(TAG, "camera format diagnostics failed: ${t.message}")
        }
    }

    private fun pickRearCameraId(manager: CameraManager): String? {
        val ids = try { manager.cameraIdList } catch (_: Throwable) { return null }
        for (id in ids) {
            try {
                val chars = manager.getCameraCharacteristics(id)
                val facing = chars.get(CameraCharacteristics.LENS_FACING)
                if (facing == CameraMetadata.LENS_FACING_BACK) return id
            } catch (_: Throwable) {}
        }
        return ids.firstOrNull()
    }

    private fun writeReport(
        sessionDir: File,
        chars: CameraCharacteristics,
        selectedWidth: Int?,
        selectedHeight: Int?,
    ) {
        val sensorSize = chars.get(CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE)
        val focalLengths = chars.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)
        val configMap = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
        val fpsRanges = chars.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES)

        val sensorWmm = sensorSize?.width?.toDouble() ?: 0.0
        val sensorHmm = sensorSize?.height?.toDouble() ?: 0.0
        val focalMm = focalLengths?.firstOrNull()?.toDouble() ?: 0.0

        val sizes = configMap?.getOutputSizes(MediaRecorder::class.java) ?: emptyArray()

        val supports30 = fpsRanges?.any { it.upper >= 30 } == true

        val all = JSONArray()
        for ((index, size) in sizes.withIndex()) {
            val w = size.width
            val h = size.height
            val (hFov, dFov) = computeFov(sensorWmm, sensorHmm, focalMm, w, h)
            val isSelected = (selectedWidth == w && selectedHeight == h)
            all.put(JSONObject().apply {
                put("index", index)
                put("width", w)
                put("height", h)
                put("aspectRatio", classifyAspect(w, h))
                put("aspectRatioNumeric", if (h > 0) w.toDouble() / h.toDouble() else 0.0)
                put("horizontalFovDeg", hFov)
                // Android Camera2 doesn't expose a "GDC corrected FOV"; keep
                // the same key shape as iOS but populate with the raw FOV.
                put("gdcCorrectedHorizontalFovDeg", hFov)
                put("gdcReducesFov", false)
                put("diagonalFovDeg", dFov)
                put("minFPS", fpsRanges?.minOfOrNull { it.lower } ?: 0)
                put("maxFPS", fpsRanges?.maxOfOrNull { it.upper } ?: 0)
                put("supports30fps", supports30)
                put("isSelected", isSelected)
            })
        }

        val (selH, selD) = if (selectedWidth != null && selectedHeight != null) {
            computeFov(sensorWmm, sensorHmm, focalMm, selectedWidth, selectedHeight)
        } else 0.0 to 0.0

        val report = JSONObject().apply {
            put("deviceType", if (focalMm in 0.01..2.5) "builtInUltraWideCamera" else "builtInWideAngleCamera")
            put("selectedFormat", JSONObject().apply {
                put("width", selectedWidth ?: 0)
                put("height", selectedHeight ?: 0)
                put("horizontalFovDeg", selH)
                put("diagonalFovDeg", selD)
                put("fovMode", "hardware")
                put("fovLimitReached", selD in 0.01..119.999)
                if (selD in 0.01..119.999) {
                    put("fovLimitReason", "device_hardware_constraint")
                } else {
                    put("fovLimitReason", JSONObject.NULL)
                }
                put("deviceMaxHorizontalFov", maxFovFromArray(sensorWmm, focalMm))
            })
            put("allFormats", all)
        }
        val file = SessionFiles.file("camera_format_diagnostics", "json", sessionDir)
        file.writeText(report.toString(2))
    }

    /**
     * Pinhole approximation: hFov = 2·atan(sensorWmm / 2·focalMm),
     * dFov  = 2·atan(diag/2·focalMm). Same identity AVFoundation reports
     * via `videoFieldOfView`. Returns degrees. When focal length or sensor
     * size are missing (some emulators / cheap devices), returns (0, 0).
     */
    private fun computeFov(
        sensorWmm: Double, sensorHmm: Double, focalMm: Double,
        width: Int, height: Int,
    ): Pair<Double, Double> {
        if (focalMm <= 0.0 || sensorWmm <= 0.0) return 0.0 to 0.0
        // Approximate the active sensor area used for the requested aspect ratio.
        val sensorAspect = sensorWmm / sensorHmm.coerceAtLeast(1e-6)
        val targetAspect = width.toDouble() / height.coerceAtLeast(1).toDouble()
        val activeWmm: Double
        val activeHmm: Double
        if (targetAspect >= sensorAspect) {
            activeWmm = sensorWmm
            activeHmm = sensorWmm / targetAspect
        } else {
            activeHmm = sensorHmm
            activeWmm = sensorHmm * targetAspect
        }
        val hFov = 2.0 * atan(activeWmm / (2.0 * focalMm))
        val diag = hypot(activeWmm, activeHmm)
        val dFov = 2.0 * atan(diag / (2.0 * focalMm))
        return Math.toDegrees(hFov).round1() to Math.toDegrees(dFov).round1()
    }

    private fun maxFovFromArray(sensorWmm: Double, focalMm: Double): Double {
        if (focalMm <= 0.0 || sensorWmm <= 0.0) return 0.0
        return Math.toDegrees(2.0 * atan(sensorWmm / (2.0 * focalMm))).round1()
    }

    private fun Double.round1(): Double = (this * 10.0).roundToInt() / 10.0

    private fun classifyAspect(width: Int, height: Int): String {
        if (width <= 0 || height <= 0) return "unknown"
        val ratio = width.toDouble() / height.toDouble()
        val candidates = listOf(
            "16:9" to 16.0 / 9.0,
            "4:3" to 4.0 / 3.0,
            "3:2" to 3.0 / 2.0,
            "1:1" to 1.0,
            "21:9" to 21.0 / 9.0,
            "5:4" to 5.0 / 4.0,
        )
        var best = "other" to Double.MAX_VALUE
        for ((label, r) in candidates) {
            val delta = kotlin.math.abs(ratio - r)
            if (delta < best.second) best = label to delta
        }
        return if (best.second < 0.02) best.first else String.format(Locale.US, "%.3f:1", ratio)
    }

    private const val TAG = "CameraFormatDiag"
}
