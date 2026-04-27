package com.kgeneye.eye.session

import com.kgeneye.eye.capture.ImuCaptureService
import org.json.JSONObject
import java.io.File

/**
 * Writes `technical_validation_<code>.json` — the machine-readable quality
 * report consumed by the backend dashboards. Field shape mirrors iOS'
 * `TechnicalValidation` model so a single CSV export covers both
 * platforms.
 */
object TechnicalValidationWriter {

    data class Inputs(
        val sessionId: String,
        val sync: SyncAnalysis.Result,
        val imuMetrics: ImuCaptureService.Metrics,
        val avgFps: Double,
        val frameIntervalStdDevMs: Double,
        val totalFrames: Int,
        val droppedFrames: Int,
        val bitrateMbps: Double,
        val gopLength: Int,
        val intrinsicsAvailable: Boolean,
        val distortionAvailable: Boolean,
    )

    fun write(sessionDir: File, inputs: Inputs) {
        val bitrateOk = inputs.bitrateMbps in 4.0..9.0
        val payload = JSONObject().apply {
            put("sessionId", inputs.sessionId)
            put("timing", JSONObject().apply {
                put("imuToVideoEstimatedOffsetMs", inputs.sync.estimatedOffsetMs)
                put("imuToVideoSyncMethod", inputs.sync.method)
                put("observedJitterStdDevMs", inputs.sync.observedJitterStdDevMs)
                put("observedMaxDeltaMs", inputs.sync.observedMaxDeltaMs)
            })
            put("imu", JSONObject().apply {
                put("sampleRateHz", inputs.imuMetrics.actualSampleRateHz)
                put("sampleIntervalStdDevMs", inputs.imuMetrics.sampleIntervalStdDevMs)
                put("maxGapMs", inputs.imuMetrics.maxGapMs)
                put("totalSamples", inputs.imuMetrics.totalSamples)
            })
            put("video", JSONObject().apply {
                put("fps", inputs.avgFps)
                put("frameIntervalStdDevMs", inputs.frameIntervalStdDevMs)
                put("totalFrames", inputs.totalFrames)
                put("droppedFrames", inputs.droppedFrames)
            })
            put("videoEncoding", JSONObject().apply {
                put("bitrateMbps", inputs.bitrateMbps)
                put("gopLength", inputs.gopLength)
                put("bFrames", 0)
                put("hdr", false)
                put("encodingValid", bitrateOk)
            })
            put("calibration", JSONObject().apply {
                put("intrinsicsAvailable", inputs.intrinsicsAvailable)
                put("distortionAvailable", inputs.distortionAvailable)
                put("mountVerified", false)
                put("intrinsicsMode", "standardized_per_device_format")
                put("extrinsicsMode", "fixed_mount_spec")
            })
            put("passCriteria", JSONObject().apply {
                put("videoStable", inputs.avgFps >= 25 && inputs.droppedFrames <= 5)
                put(
                    "imuStable",
                    inputs.imuMetrics.actualSampleRateHz >= 90 &&
                        inputs.imuMetrics.sampleIntervalStdDevMs < 2.0,
                )
                put("syncAcceptable", inputs.sync.observedMaxDeltaMs < 15.0)
                put("calibrationAcceptable", true)
                put("encodingAcceptable", bitrateOk)
            })
        }
        val file = SessionFiles.file("technical_validation", "json", sessionDir)
        file.writeText(payload.toString(2))
    }
}
