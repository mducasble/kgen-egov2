package com.kgeneye.eye.session

import android.os.Build
import android.util.JsonWriter
import com.kgeneye.eye.capture.ImuCaptureService
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

    data class RecordingSummary(
        val sessionId: String,
        val startEpochMs: Double,
        val endEpochMs: Double,
        val video: VideoInfo,
        val imuFilename: String,
        val imuSizeBytes: Long,
        val imuRowCount: Int,
        val imuMetrics: ImuCaptureService.Metrics,
        val deviceModel: String = "${Build.MANUFACTURER} ${Build.MODEL}",
        val hardwareIdentifier: String = Build.DEVICE,
        val systemVersion: String = "Android ${Build.VERSION.RELEASE}",
        val deviceName: String = Build.PRODUCT,
        val pipelineBuild: String = "android-step3",
    )

    fun writeSessionManifest(sessionDir: File, summary: RecordingSummary) {
        val file = SessionFiles.file("session_manifest", "json", sessionDir)
        JsonWriter(FileWriter(file)).use { w ->
            w.setIndent("  ")
            w.beginObject()
            w.name("sessionId").value(summary.sessionId)
            w.name("createdAtEpochMs").value(summary.startEpochMs)
            w.name("artifacts").beginArray()
            artifact(w, summary.video.filename, "video",
                "Primary recording (MP4, H.264/HEVC as provided by CameraX).",
                summary.video.sizeBytes, null)
            artifact(w, summary.imuFilename, "jsonl",
                "Accelerometer + gyroscope samples (~100 Hz, G's / rad·s⁻¹).",
                summary.imuSizeBytes, summary.imuRowCount)
            artifact(w, SessionFiles.name("metadata", "json", summary.sessionId),
                "json", "Session-level metadata (device, capture, metrics).", 0, null)
            artifact(w, SessionFiles.name("session_manifest", "json", summary.sessionId),
                "json", "This manifest.", 0, null)
            w.endArray()
            w.endObject()
        }
    }

    fun writeMetadata(sessionDir: File, summary: RecordingSummary) {
        val file = SessionFiles.file("metadata", "json", sessionDir)
        JsonWriter(FileWriter(file)).use { w ->
            w.setIndent("  ")
            w.beginObject()
            w.name("sessionId").value(summary.sessionId)
            w.name("startTimeEpochMs").value(summary.startEpochMs)
            w.name("endTimeEpochMs").value(summary.endEpochMs)
            w.name("durationSec").value((summary.endEpochMs - summary.startEpochMs) / 1000.0)

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
            w.name("videoCodec").value(summary.video.codec)
            w.name("imuTargetHz").value(100)
            w.name("videoTimestampsEstimated").value(true)
            w.name("orientationLocked").value(true)
            w.name("orientation").value("portrait")
            w.name("timestampClock").value("elapsed_realtime_nanos")
            w.name("epochToMonotonicPrecision").value("ms-snapshot-at-start")
            w.endObject()

            w.name("imuMetrics").beginObject()
            w.name("totalSamples").value(summary.imuMetrics.totalSamples)
            w.name("actualSampleRateHz").value(summary.imuMetrics.actualSampleRateHz)
            w.name("startupSamplesDiscarded").value(summary.imuMetrics.startupSamplesDiscarded)
            w.name("sampleIntervalStdDevMs").value(summary.imuMetrics.sampleIntervalStdDevMs)
            w.name("maxGapMs").value(summary.imuMetrics.maxGapMs)
            w.endObject()

            w.name("captureHealth").beginObject()
            w.name("videoBackpressureEvents").value(0)
            w.name("imuLagEvents").value(summary.imuMetrics.lagEvents)
            w.name("droppedFrames").value(0)
            w.endObject()

            w.name("coordinateSystem").beginObject()
            w.name("type").value("right-handed")
            w.name("referenceFrame").value("device (Android sensor frame)")
            w.name("units").value("G and rad/s")
            w.name("axisConvention").beginObject()
            w.name("x").value("right")
            w.name("y").value("up")
            w.name("z").value("out of screen")
            w.endObject()
            w.endObject()

            w.name("pipeline").beginObject()
            w.name("version").value("0.1.0")
            w.name("build").value(summary.pipelineBuild)
            w.name("captureMode").value("imu+video")
            w.name("threadModel").value("camerax-main+imu-handlerthread")
            w.name("timestampSource").value("elapsed_realtime_nanos")
            w.endObject()

            w.name("warnings").beginArray().endArray()
            w.endObject()
        }
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
        if (rowCount != null) w.name("rowCount").value(rowCount) else w.name("rowCount").nullValue()
        w.endObject()
    }
}
