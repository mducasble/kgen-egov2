package com.kgeneye.eye.session

import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CameraMetadata
import android.media.MediaRecorder
import android.os.Build
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlin.math.atan
import kotlin.math.hypot
import kotlin.math.roundToInt

/**
 * One-shot enumeration of every back-facing physical camera + format, for
 * answering "what is the highest diagonal FOV this Android phone can deliver
 * in 30 fps+ video?" Mirrors iOS' `FOVEnumerationDiagnostic` so reports from
 * both platforms can be compared with the same backend tooling.
 *
 * Pure inspection: does not open a `CameraDevice`, does not touch the
 * recording pipeline, safe to call from the UI thread.
 *
 * Output JSON lands in `getExternalFilesDir("FOVDiagnostics")`, so users can
 * pick it up over USB (`adb pull`) or share via Files app.
 */
object FovEnumerationDiagnostic {

    private const val TAG = "FOVDiagnostic"
    private const val SCHEMA = "kgeneye.fov_enumeration.v1"
    private const val SPEC_MIN_DIAGONAL_FOV_DEG = 120.0

    /**
     * Runs the enumeration, writes a JSON artifact to
     * `<external-files>/FOVDiagnostics/`, and returns the file. Returns null
     * if the device has no `CameraManager` (e.g. some emulators).
     */
    fun runAndSave(context: Context): File? {
        val payload = build(context) ?: return null
        val dir = diagnosticsDirectory(context) ?: return null
        val deviceTag = "${Build.MANUFACTURER}_${Build.MODEL}"
            .replace(" ", "_")
            .replace("/", "_")
        val filename = "fov_enumeration_${deviceTag}_${timestampSuffix()}.json"
        val file = File(dir, filename)
        file.writeText(payload.toString(2))
        logSummary(payload, file)
        return file
    }

    /**
     * Builds the full enumeration payload as a JSON object. Runs synchronously
     * (a few ms even on cheap devices).
     */
    fun build(context: Context): JSONObject? {
        val manager = context.getSystemService(Context.CAMERA_SERVICE) as? CameraManager ?: return null
        val ids = try { manager.cameraIdList } catch (_: Throwable) { return null }

        val devices = JSONArray()
        var maxDFov = 0.0
        var maxDFovRecord: JSONObject? = null

        for (id in ids) {
            val chars = try { manager.getCameraCharacteristics(id) } catch (_: Throwable) { continue }
            val facing = chars.get(CameraCharacteristics.LENS_FACING)
            if (facing != CameraMetadata.LENS_FACING_BACK) continue

            val sensorSize = chars.get(CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE)
            val focalLengths = chars.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)
            val pixelArray = chars.get(CameraCharacteristics.SENSOR_INFO_PIXEL_ARRAY_SIZE)
            val configMap = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            val fpsRanges = chars.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES)

            val sensorWmm = sensorSize?.width?.toDouble() ?: 0.0
            val sensorHmm = sensorSize?.height?.toDouble() ?: 0.0
            val focalMm = focalLengths?.firstOrNull()?.toDouble() ?: 0.0
            val supports30 = fpsRanges?.any { it.upper >= 30 } == true
            val maxFps = fpsRanges?.maxOfOrNull { it.upper } ?: 0
            val minFps = fpsRanges?.minOfOrNull { it.lower } ?: 0

            val sizes = configMap?.getOutputSizes(MediaRecorder::class.java) ?: emptyArray()

            val formatEntries = JSONArray()
            for (size in sizes) {
                val w = size.width
                val h = size.height
                if (w <= 0 || h <= 0 || !supports30) continue

                val (hFov, dFov) = computeFov(sensorWmm, sensorHmm, focalMm, w, h)
                val aspectNumeric = w.toDouble() / h.toDouble()
                formatEntries.put(JSONObject().apply {
                    put("width", w)
                    put("height", h)
                    put("aspectRatio", String.format(Locale.US, "%.3f", aspectNumeric))
                    put("horizontalFovDeg", hFov)
                    // Android Camera2 has no GDC equivalent; surface the same key
                    // shape as iOS for backend symmetry.
                    put("geometricDistortionCorrectedFovDeg", hFov)
                    put("gdcReducesFov", false)
                    put("diagonalFovDeg", dFov)
                    put("fpsRanges", JSONArray().apply {
                        fpsRanges?.forEach { range ->
                            put(JSONObject().apply {
                                put("min", range.lower)
                                put("max", range.upper)
                            })
                        }
                    })
                })

                if (dFov > maxDFov) {
                    maxDFov = dFov
                    maxDFovRecord = JSONObject().apply {
                        put("cameraId", id)
                        put("deviceLocalizedName", localizedName(id, focalMm))
                        put("width", w)
                        put("height", h)
                        put("horizontalFovDeg", hFov)
                        put("diagonalFovDeg", dFov)
                    }
                }
            }

            // Sort descending by diagonal FOV.
            val sorted = JSONArray()
            (0 until formatEntries.length())
                .map { formatEntries.getJSONObject(it) }
                .sortedByDescending { it.optDouble("diagonalFovDeg", 0.0) }
                .forEach { sorted.put(it) }

            val deviceInfo = JSONObject().apply {
                put("cameraId", id)
                put("localizedName", localizedName(id, focalMm))
                // Camera2 has no virtual/composite device concept; always physical.
                put("isVirtualDevice", false)
                // Lens distortion correction support varies; report explicitly when known.
                put("lensDistortionCorrectionAvailable", chars.get(CameraCharacteristics.LENS_DISTORTION) != null)
                put("focalLengthMm", focalMm)
                put("sensorPhysicalSizeMm", JSONArray(listOf(sensorWmm, sensorHmm)))
                put(
                    "pixelArraySize",
                    if (pixelArray != null) JSONArray(listOf(pixelArray.width, pixelArray.height))
                    else JSONArray(),
                )
                put("minFPS", minFps)
                put("maxFPS", maxFps)
                put("formats30fpsPlus", sorted)
                put("formatCount", sorted.length())
            }
            devices.put(deviceInfo)
        }

        val summary = JSONObject().apply {
            put("backDeviceCount", devices.length())
            put("maxDiagonalFovDeg", maxDFov.round1())
            put("specMinimumDiagonalFovDeg", SPEC_MIN_DIAGONAL_FOV_DEG)
            put("meetsSpecMinimum", maxDFov >= SPEC_MIN_DIAGONAL_FOV_DEG)
            if (maxDFovRecord != null) put("maxDiagonalFovFormat", maxDFovRecord)
        }

        return JSONObject().apply {
            put("schema", SCHEMA)
            put("capturedAtEpochMs", System.currentTimeMillis())
            put("deviceManufacturer", Build.MANUFACTURER)
            put("deviceModel", Build.MODEL)
            put("deviceProduct", Build.PRODUCT)
            put("systemName", "Android")
            put("systemVersion", Build.VERSION.RELEASE)
            put("sdkInt", Build.VERSION.SDK_INT)
            put("summary", summary)
            put("devices", devices)
        }
    }

    private fun localizedName(cameraId: String, focalMm: Double): String {
        val role = when {
            focalMm in 0.01..2.5 -> "Ultra Wide"
            focalMm in 2.5..5.0 -> "Wide"
            focalMm > 5.0 -> "Telephoto"
            else -> "Rear"
        }
        return "$role (id=$cameraId)"
    }

    private fun computeFov(
        sensorWmm: Double, sensorHmm: Double, focalMm: Double,
        width: Int, height: Int,
    ): Pair<Double, Double> {
        if (focalMm <= 0.0 || sensorWmm <= 0.0) return 0.0 to 0.0
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

    private fun Double.round1(): Double = (this * 10.0).roundToInt() / 10.0

    private fun diagnosticsDirectory(context: Context): File? {
        val base = context.getExternalFilesDir(null) ?: context.filesDir
        val dir = File(base, "FOVDiagnostics")
        if (!dir.exists() && !dir.mkdirs()) {
            Log.w(TAG, "could not create ${dir.absolutePath}")
            return null
        }
        return dir
    }

    private fun timestampSuffix(): String {
        val fmt = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }
        return fmt.format(Date()) + "Z"
    }

    private fun logSummary(payload: JSONObject, file: File) {
        val summary = payload.optJSONObject("summary")
        val devices = payload.optJSONArray("devices") ?: JSONArray()
        val maxD = summary?.optDouble("maxDiagonalFovDeg", 0.0) ?: 0.0
        val meets = summary?.optBoolean("meetsSpecMinimum", false) ?: false
        Log.i(TAG, "=== FOV ENUMERATION ===")
        Log.i(TAG, "Back devices: ${devices.length()}")
        for (i in 0 until devices.length()) {
            val d = devices.getJSONObject(i)
            val name = d.optString("localizedName", "?")
            val count = d.optInt("formatCount", 0)
            val formats = d.optJSONArray("formats30fpsPlus")
            val top = if (formats != null && formats.length() > 0) formats.getJSONObject(0) else null
            val topFov = top?.optDouble("diagonalFovDeg", 0.0) ?: 0.0
            val topW = top?.optInt("width", 0) ?: 0
            val topH = top?.optInt("height", 0) ?: 0
            Log.i(TAG, "  $name — $count fmts, top=${topW}x$topH dFov=${"%.1f°".format(topFov)}")
        }
        Log.i(TAG, "maxDiagonalFovDeg=${"%.2f°".format(maxD)} | meetsSpec120=$meets")
        Log.i(TAG, "Saved: ${file.absolutePath}")
    }
}
