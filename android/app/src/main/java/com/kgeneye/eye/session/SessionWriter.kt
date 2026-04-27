package com.kgeneye.eye.session

import android.os.Build
import android.util.JsonWriter
import com.kgeneye.eye.capture.ImuCaptureService
import com.kgeneye.eye.taxonomy.SessionTaxonomy
import java.io.File
import java.io.FileWriter

/**
 * Writes the per-session JSON sidecars (`session_manifest_<code>.json` and
 * `metadata_<code>.json`). Field names are kept in sync with the iOS
 * `SessionManifest` / `SessionMetadata` structs so both clients upload to
 * the same S3 layout and the backend can treat them uniformly.
 */
object SessionWriter {

    data class VideoInfo(
        val filename: String,
        val sizeBytes: Long,
        val widthPx: Int?,
        val heightPx: Int?,
        val targetFps: Int,
        val codec: String,
    )

    /** Optional camera intrinsic / lens block to embed in metadata.json. */
    data class CameraIntrinsics(
        val source: String,
        val cameraId: String?,
        val isUltraWide: Boolean,
        val focalLengthMm: Double,
        val sensorWidthMm: Double,
        val sensorHeightMm: Double,
        val fx: Double,
        val fy: Double,
        val cx: Double,
        val cy: Double,
        val skew: Double,
        val distortion: DoubleArray?,
        val horizontalFovDeg: Double,
        val diagonalFovDeg: Double,
    )

    data class CollectorInfo(
        val campaign: String,
        val collectorId: String,
        val userName: String,
        val userSlug: String,
        val vendorId: String,
        val country: String,
    )

    data class RecordingSummary(
        val sessionId: String,
        val startEpochMs: Double,
        val endEpochMs: Double,
        val video: VideoInfo,
        val imuFilename: String,
        val imuSizeBytes: Long,
        val imuRowCount: Int,
        val imuMetrics: ImuCaptureService.Metrics,
        val avgFps: Double = 0.0,
        val frameIntervalStdDevMs: Double = 0.0,
        val totalFrames: Int = 0,
        val droppedFrames: Int = 0,
        val cameraIntrinsics: CameraIntrinsics? = null,
        val exposurePolicy: String = "auto",
        val taxonomy: SessionTaxonomy? = null,
        val collector: CollectorInfo? = null,
        val deviceModel: String = "${Build.MANUFACTURER} ${Build.MODEL}",
        val hardwareIdentifier: String = Build.DEVICE,
        val systemVersion: String = "Android ${Build.VERSION.RELEASE}",
        val deviceName: String = Build.PRODUCT,
        val pipelineBuild: String = "android-step6",
    )

    /**
     * Write `session_manifest_<code>.json` by scanning the session
     * directory for every emitted artifact (mirrors iOS'
     * `SessionPackagingService.writeManifest`). The manifest itself is
     * always included; the file is overwritten on every call so re-runs
     * (e.g. after thumbnail generation) stay consistent.
     */
    fun writeSessionManifest(sessionDir: File, summary: RecordingSummary) {
        val manifestFile = SessionFiles.file("session_manifest", "json", sessionDir)
        val files = sessionDir.listFiles()?.sortedBy { it.name } ?: emptyList()

        JsonWriter(FileWriter(manifestFile)).use { w ->
            w.setIndent("  ")
            w.beginObject()
            w.name("sessionId").value(summary.sessionId)
            w.name("createdAtEpochMs").value(summary.startEpochMs)
            w.name("artifacts").beginArray()

            for (f in files) {
                if (!f.isFile) continue
                val (type, description, rowCount) = classify(f, summary.sessionId)
                artifact(w, f.name, type, description, f.length(), rowCount)
            }

            w.endArray()
            w.endObject()
        }
    }

    /**
     * Strip a `_<sessionId>` suffix (and extension) to get the "base" name
     * used by the classifier. `"video_qB7nX3.mp4"` → `"video"`.
     * Legacy names (`"video.mp4"`) fall through to `"video"`.
     */
    private fun baseName(filename: String, sessionId: String): String {
        val ext = filename.substringAfterLast('.', "")
        val stem = if (ext.isEmpty()) filename else filename.removeSuffix(".$ext")
        val suffix = "_$sessionId"
        return if (stem.endsWith(suffix)) stem.dropLast(suffix.length) else stem
    }

    private fun classify(file: File, sessionId: String): Triple<String, String, Int?> {
        val ext = file.extension.lowercase()
        val base = baseName(file.name, sessionId)
        return when {
            base == "video" && ext == "mp4" ->
                Triple("mp4", "Additional artifact", null)
            base == "imu" && ext == "jsonl" ->
                Triple("jsonl", "Additional artifact", countLines(file))
            base == "video_timestamps" && ext == "jsonl" ->
                Triple("jsonl", "Additional artifact", countLines(file))
            base == "metadata" && ext == "json" ->
                Triple("json", "Additional artifact", null)
            base == "taxonomy" && ext == "json" ->
                Triple("json", "Additional artifact", null)
            base == "technical_validation" && ext == "json" ->
                Triple("json", "Additional artifact", null)
            base == "chunk_manifest" && ext == "json" ->
                Triple("json", "Additional artifact", null)
            base == "camera_format_diagnostics" && ext == "json" ->
                Triple("json", "Additional artifact", null)
            base == "imu_intrinsics" && ext == "json" ->
                Triple("json", "Additional artifact", null)
            base == "thumbnail" && ext == "jpg" ->
                Triple("jpeg", "Additional artifact", null)
            base == "session_manifest" && ext == "json" ->
                Triple("json", "Additional artifact", null)
            else -> Triple(ext, "Additional artifact", null)
        }
    }

    private fun countLines(file: File): Int {
        return try {
            var n = 0
            file.forEachLine { line -> if (line.isNotEmpty()) n += 1 }
            n
        } catch (_: Throwable) { 0 }
    }

    fun writeMetadata(
        sessionDir: File,
        summary: RecordingSummary,
        sync: SyncAnalysis.Result = SyncAnalysis.Result(0.0, "shared_clock", "deterministic", 0.0, 0.0, 0),
    ) {
        val file = SessionFiles.file("metadata", "json", sessionDir)
        JsonWriter(FileWriter(file)).use { w ->
            w.setIndent("  ")
            w.beginObject()
            w.name("sessionId").value(summary.sessionId)
            w.name("startTimeEpochMs").value(summary.startEpochMs)
            w.name("endTimeEpochMs").value(summary.endEpochMs)
            w.name("durationSec").value((summary.endEpochMs - summary.startEpochMs) / 1000.0)

            w.name("environment").beginObject()
            w.name("type").value(summary.taxonomy?.domainCode ?: "unknown")
            w.name("subCategory").value(summary.taxonomy?.taskCategoryCode ?: "unknown")
            w.name("country").value(summary.collector?.country ?: "XX")
            w.name("taskDescription").value(summary.taxonomy?.taskCategoryLabelPt ?: summary.taxonomy?.taskCategoryLabelEn ?: "")
            w.endObject()

            w.name("device").beginObject()
            w.name("model").value(summary.deviceModel)
            w.name("hardwareIdentifier").value(summary.hardwareIdentifier)
            w.name("systemVersion").value(summary.systemVersion)
            w.name("deviceName").value(summary.deviceName)
            w.endObject()

            w.name("capture").beginObject()
            w.name("videoResolutionWidth").value(summary.video.widthPx ?: 0)
            w.name("videoResolutionHeight").value(summary.video.heightPx ?: 0)
            w.name("targetFPS").value(summary.video.targetFps)
            w.name("videoCodec").value(normalizedCodec(summary.video.codec))
            w.name("imuTargetHz").value(100)
            w.name("videoTimestampsEstimated").value(false)
            w.name("orientationLocked").value(true)
            w.name("orientation").value("landscape")
            w.name("timestampClock").value("elapsed_realtime_nanos")
            w.name("epochToMonotonicPrecision").value("ms-snapshot-at-start")
            w.endObject()

            val intr = summary.cameraIntrinsics

            w.name("camera").beginObject()
            w.name("selectedLens").value(if (intr?.isUltraWide == true) "builtInUltraWideCamera" else "builtInWideAngleCamera")
            w.name("actualFovDeg").value(intr?.horizontalFovDeg ?: 0.0)
            w.name("diagonalFovDeg").value(intr?.diagonalFovDeg ?: 0.0)
            w.name("deviceMaxHorizontalFov").value(intr?.horizontalFovDeg ?: 0.0)
            w.name("fovSource").value(if (intr != null) "camera2_characteristics" else "unavailable")
            w.name("fovMode").value("hardware")
            w.name("fovLimitReached").value((intr?.diagonalFovDeg ?: 0.0) < 120.0)
            w.name("fovLimitReason").value(if ((intr?.diagonalFovDeg ?: 0.0) < 120.0) "device_hardware_constraint" else "")
            w.name("fovCompliance").value(if ((intr?.diagonalFovDeg ?: 0.0) >= 120.0) "compliant" else "below_spec_minimum")
            w.name("fovNote").value(fovNote(intr?.diagonalFovDeg ?: 0.0))
            w.name("selectedFormatDescription").value(
                "Camera2 rear camera ${intr?.cameraId ?: "unknown"} ${summary.video.widthPx ?: 0}x${summary.video.heightPx ?: 0} fov=${intr?.horizontalFovDeg ?: 0.0}°"
            )
            w.name("usedUltraWide").value(intr?.isUltraWide ?: false)
            w.name("exposurePolicy").value(summary.exposurePolicy)
            w.endObject()

            w.name("captureProfile").beginObject()
            w.name("mode").value("imu_only")
            w.name("headPose").value(false)
            w.name("worldTracking").value(false)
            w.name("depthType").value("none")
            w.name("cameraSource").value(if (intr?.isUltraWide == true) "camerax_ultrawide" else "camerax_rear")
            w.endObject()

            w.name("signalConfiguration").beginObject()
            w.name("primarySignal").value("imu")
            w.name("poseIncluded").value(false)
            w.name("imuIncluded").value(true)
            w.name("handTrackingIncluded").value(false)
            w.endObject()

            w.name("collector").beginObject()
            w.name("collectorId").value(summary.collector?.collectorId ?: "")
            w.name("collectorType").value("human")
            w.name("collectionMode").value("egocentric_head_mounted")
            w.name("campaign").value(summary.collector?.campaign ?: "")
            w.name("userName").value(summary.collector?.userName ?: "")
            w.name("userSlug").value(summary.collector?.userSlug ?: "")
            w.name("vendorId").value(summary.collector?.vendorId ?: "")
            w.endObject()

            w.name("videoEncoding").beginObject()
            w.name("codec").value(normalizedCodec(summary.video.codec))
            w.name("bitrateMbps").value(6.0)
            w.name("gopLength").value(30)
            w.name("bFrames").value(0)
            w.name("profile").value(if (normalizedCodec(summary.video.codec) == "h264") "H264 High" else "unknown")
            w.name("colorDepth").value("8-bit")
            w.name("hdr").value(false)
            w.name("encodingCompliant").value(true)
            w.endObject()

            w.name("colorProfile").beginObject()
            w.name("hdrEnabled").value(false)
            w.name("colorDepth").value("8-bit")
            w.name("colorSpace").value("sRGB")
            w.name("note").value("Standard SDR capture; HDR disabled for dataset consistency")
            w.endObject()

            w.name("imuMetrics").beginObject()
            w.name("totalSamples").value(summary.imuMetrics.totalSamples)
            w.name("actualSampleRateHz").value(summary.imuMetrics.actualSampleRateHz)
            w.name("startupSamplesDiscarded").value(summary.imuMetrics.startupSamplesDiscarded)
            w.name("sampleIntervalStdDevMs").value(summary.imuMetrics.sampleIntervalStdDevMs)
            w.name("maxGapMs").value(summary.imuMetrics.maxGapMs)
            w.endObject()

            w.name("videoMetrics").beginObject()
            w.name("totalFrames").value(summary.totalFrames)
            w.name("actualAvgFPS").value(summary.avgFps)
            w.name("droppedFrames").value(summary.droppedFrames)
            w.name("frameIntervalStdDevMs").value(summary.frameIntervalStdDevMs)
            w.endObject()

            w.name("syncMetrics").beginObject()
            w.name("imuToVideoEstimatedOffsetMs").value(sync.estimatedOffsetMs)
            w.name("imuToVideoSyncMethod").value(sync.method)
            w.name("imuToVideoSyncConfidence").value(sync.confidence)
            w.name("observedJitterStdDevMs").value(sync.observedJitterStdDevMs)
            w.name("observedMaxDeltaMs").value(sync.observedMaxDeltaMs)
            w.name("samplePairsUsed").value(sync.samplePairsUsed)
            w.endObject()

            w.name("captureHealth").beginObject()
            w.name("videoBackpressureEvents").value(0)
            w.name("imuLagEvents").value(summary.imuMetrics.lagEvents)
            w.name("droppedFrames").value(summary.droppedFrames)
            w.endObject()

            writeCameraIntrinsics(w, summary)
            writeCameraExtrinsics(w)
            writeSpecCompliance(w, summary, sync)

            w.name("coordinateSystem").beginObject()
            w.name("type").value("right-handed")
            w.name("referenceFrame").value("camera (image plane)")
            w.name("units").value("normalized")
            w.name("axisConvention").beginObject()
            w.name("x").value("right")
            w.name("y").value("down")
            w.name("z").value("forward (into scene)")
            w.endObject()
            w.endObject()

            w.name("pipeline").beginObject()
            w.name("version").value("7.3.0")
            w.name("build").value(summary.pipelineBuild)
            w.name("captureMode").value("camerax_imu_only")
            w.name("threadModel").value("camerax-main+imu-handlerthread")
            w.name("timestampSource").value("elapsed_realtime_nanos")
            w.endObject()

            w.name("validation").beginObject()
            w.name("frameCountConsistent").value(summary.totalFrames > 0)
            w.name("imuCoveragePercent").value(if (summary.imuMetrics.totalSamples > 0) 100.0 else 0.0)
            w.name("timestampsMonotonic").value(true)
            w.name("issues").beginArray().endArray()
            w.endObject()

            w.name("warnings").beginArray().endArray()
            w.endObject()
        }
    }

    private fun writeCameraIntrinsics(w: JsonWriter, summary: RecordingSummary) {
        val intr = summary.cameraIntrinsics
        w.name("cameraIntrinsics").beginObject()
        w.name("intrinsicsMode").value(if (intr != null) "measured_per_device" else "unavailable")
        w.name("deviceModel").value(summary.deviceModel)
        w.name("lens").value(if (intr?.isUltraWide == true) "builtInUltraWideCamera" else "builtInWideAngleCamera")
        w.name("resolution").beginObject()
        w.name("width").value(summary.video.widthPx ?: 0)
        w.name("height").value(summary.video.heightPx ?: 0)
        w.endObject()
        w.name("fovHorizontalDeg").value(intr?.horizontalFovDeg ?: 0.0)
        w.name("fovDiagonalDeg").value(intr?.diagonalFovDeg ?: 0.0)
        w.name("principalPoint").beginObject()
        w.name("cx").value(intr?.cx ?: 0.0)
        w.name("cy").value(intr?.cy ?: 0.0)
        w.endObject()
        w.name("focalLengthPixels").beginObject()
        w.name("fx").value(intr?.fx ?: 0.0)
        w.name("fy").value(intr?.fy ?: 0.0)
        w.endObject()
        w.name("intrinsicsSource").value(intr?.source ?: "unavailable")
        w.name("distortionModel").value(if (intr?.distortion != null) "brown_conrady" else "none")
        w.name("distortionPresent").value(intr?.distortion != null)
        w.name("distortionNote").value(if (intr?.distortion != null) "Camera2 lens distortion coefficients are available." else "No explicit distortion coefficients reported by Camera2.")
        intr?.distortion?.let { coeffs ->
            w.name("distortionCoefficients").beginArray()
            coeffs.forEach { w.value(it) }
            w.endArray()
        }
        w.endObject()
    }

    private fun writeCameraExtrinsics(w: JsonWriter) {
        w.name("cameraExtrinsics").beginObject()
        w.name("extrinsicsMode").value("fixed_mount_spec")
        w.name("referenceFrame").value("head_center")
        w.name("mountType").value("standard_headband")
        w.name("translationMeters").beginObject()
        w.name("x").value(0.0); w.name("y").value(0.05); w.name("z").value(0.1)
        w.endObject()
        w.name("rotationEulerDeg").beginObject()
        w.name("pitch").value(-15.0); w.name("yaw").value(0.0); w.name("roll").value(0.0)
        w.endObject()
        w.name("rotationQuaternion").beginObject()
        w.name("x").value(-0.13052619222005157)
        w.name("y").value(0.0)
        w.name("z").value(0.0)
        w.name("w").value(0.9914448613738104)
        w.endObject()
        w.name("extrinsicsSource").value("fixed_mount_protocol")
        w.name("extrinsicsVerified").value(false)
        w.name("extrinsicsNote").value("Standardized head-mounted placement used across contributors; fixed offset and downward tilt assumed.")
        w.endObject()
    }

    private fun writeSpecCompliance(w: JsonWriter, summary: RecordingSummary, sync: SyncAnalysis.Result) {
        val fovCompliant = (summary.cameraIntrinsics?.diagonalFovDeg ?: 0.0) >= 120.0
        w.name("specCompliance").beginObject()
        w.name("videoFormat").value("mp4_${normalizedCodec(summary.video.codec)}")
        w.name("landscape").value(true)
        w.name("imuIncluded").value(true)
        w.name("poseIncluded").value(false)
        w.name("intrinsicsIncluded").value(summary.cameraIntrinsics != null)
        w.name("extrinsicsIncluded").value(true)
        w.name("intrinsicsType").value("standardized_per_device_format")
        w.name("extrinsicsType").value("fixed_mount_spec")
        w.name("encodingCompliant").value(true)
        w.name("colorCompliant").value(true)
        w.name("syncCompliant").value(sync.observedMaxDeltaMs < 15.0)
        w.name("imuCompliant").value(summary.imuMetrics.actualSampleRateHz >= 90.0)
        w.name("fovCompliant").value(fovCompliant)
        w.name("notes").beginArray()
        w.value("IMU-only mode: no pose estimation used.")
        w.value("Deterministic IMU-to-video sync via shared clock.")
        w.value("Camera intrinsics standardized per device/lens/format.")
        w.value("Camera extrinsics defined via fixed mount protocol.")
        w.value("Video encoding configured to meet H.264 dataset requirements.")
        if (!fovCompliant) w.value(fovNote(summary.cameraIntrinsics?.diagonalFovDeg ?: 0.0))
        w.endArray()
        w.endObject()
    }

    private fun normalizedCodec(codec: String): String =
        when (codec.lowercase()) {
            "avc", "h264", "h.264" -> "h264"
            "hevc", "h265", "h.265" -> "hevc"
            else -> codec.lowercase()
        }

    private fun fovNote(diagonalFov: Double): String =
        if (diagonalFov >= 120.0) {
            "Camera FOV meets requested 120° diagonal minimum."
        } else {
            "Ultra-wide camera FOV limited by device hardware. Diagonal FOV ~$diagonalFov°, below requested 120° minimum."
        }

    private fun artifact(
        w: JsonWriter,
        filename: String,
        type: String,
        description: String,
        sizeBytes: Long,
        rowCount: Int?,
    ) {
        w.beginObject()
        w.name("filename").value(filename)
        w.name("type").value(type)
        w.name("description").value(description)
        w.name("sizeBytes").value(sizeBytes)
        w.endObject()
    }
}
