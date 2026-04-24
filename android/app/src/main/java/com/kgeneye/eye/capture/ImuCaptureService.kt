package com.kgeneye.eye.capture

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.HandlerThread
import android.os.Handler
import java.io.BufferedWriter
import java.io.File
import java.io.FileWriter
import kotlin.math.max
import kotlin.math.sqrt

/**
 * Captures accelerometer + gyroscope data at ~100 Hz using [SensorManager]
 * and streams it to a JSONL file (`imu_<code>.jsonl`). Runs on a dedicated
 * [HandlerThread] so sensor callbacks don't block the UI or CameraX.
 *
 * Two separate sensor streams are fused by caching the most recent
 * gyroscope reading and emitting a sample each time a new accelerometer
 * event arrives — the accelerometer drives the cadence because its
 * nominal rate matches the 100 Hz IMU target used on iOS.
 *
 * Statistics (actual rate, jitter, max gap, lag events) are accumulated
 * and exposed for `metadata.json` at the end of the recording — same
 * fields as `IMUMetrics` on iOS.
 */
class ImuCaptureService(context: Context) : SensorEventListener {

    companion object {
        private const val TARGET_INTERVAL_US = 10_000      // 100 Hz
        private const val STARTUP_DISCARD = 10
        private const val GAP_THRESHOLD_MS = 50.0
        private const val GRAVITY = 9.80665                // 1 G in m/s²
    }

    private val sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val accelSensor = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
    private val gyroSensor = sensorManager.getDefaultSensor(Sensor.TYPE_GYROSCOPE)

    private val clock = MonotonicClock.shared
    private var thread: HandlerThread? = null
    private var handler: Handler? = null
    private var writer: BufferedWriter? = null
    private var outputFile: File? = null

    private var startNs: Long = 0
    private var sampleCount = 0
    private var startupDiscarded = 0
    private var previousSampleNs: Long? = null

    private var continuousDurationSec = 0.0
    private var continuousIntervalCount = 0
    private var intervalSumMs = 0.0
    private var intervalSquaredSumMs = 0.0
    private var maxGapMs = 0.0
    private var lagEventCount = 0

    private var lastGyroX = 0.0
    private var lastGyroY = 0.0
    private var lastGyroZ = 0.0
    private var haveGyro = false

    val totalSamples: Int get() = sampleCount

    val actualSampleRateHz: Double
        get() = if (continuousIntervalCount > 0 && continuousDurationSec > 0)
            continuousIntervalCount.toDouble() / continuousDurationSec else 0.0

    val sampleIntervalStdDevMs: Double
        get() {
            if (continuousIntervalCount <= 1) return 0.0
            val n = continuousIntervalCount.toDouble()
            val mean = intervalSumMs / n
            val variance = (intervalSquaredSumMs / n) - (mean * mean)
            return if (variance > 0) sqrt(variance) else 0.0
        }

    val maxGapMsValue: Double get() = maxGapMs
    val startupDiscardedCount: Int get() = startupDiscarded
    val lagEvents: Int get() = lagEventCount

    /** `true` when the device exposes both sensors that IMU export requires. */
    val isAvailable: Boolean get() = accelSensor != null && gyroSensor != null

    fun start(outputFile: File) {
        require(isAvailable) { "Accelerometer + gyroscope required for IMU capture" }

        val ht = HandlerThread("kgeneye-imu").apply { start() }
        val h = Handler(ht.looper)
        thread = ht
        handler = h

        this.outputFile = outputFile
        writer = BufferedWriter(FileWriter(outputFile, false))

        startNs = clock.nowNs()
        sampleCount = 0
        startupDiscarded = 0
        previousSampleNs = null
        continuousDurationSec = 0.0
        continuousIntervalCount = 0
        intervalSumMs = 0.0
        intervalSquaredSumMs = 0.0
        maxGapMs = 0.0
        lagEventCount = 0
        haveGyro = false

        sensorManager.registerListener(this, accelSensor, TARGET_INTERVAL_US, h)
        sensorManager.registerListener(this, gyroSensor, TARGET_INTERVAL_US, h)
    }

    fun stop() {
        sensorManager.unregisterListener(this)
        handler?.post {
            try { writer?.flush(); writer?.close() } catch (_: Throwable) {}
            writer = null
        }
        thread?.quitSafely()
        thread = null
        handler = null
    }

    override fun onSensorChanged(event: SensorEvent) {
        when (event.sensor.type) {
            Sensor.TYPE_GYROSCOPE -> {
                lastGyroX = event.values[0].toDouble()
                lastGyroY = event.values[1].toDouble()
                lastGyroZ = event.values[2].toDouble()
                haveGyro = true
            }
            Sensor.TYPE_ACCELEROMETER -> handleAccel(event)
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) { /* no-op */ }

    private fun handleAccel(event: SensorEvent) {
        if (!haveGyro) return

        val rawCount = sampleCount + startupDiscarded
        if (rawCount < STARTUP_DISCARD) {
            startupDiscarded += 1
            return
        }

        val sampleNs = event.timestamp
        val relativeMs = clock.toRelativeMs(sampleNs, startNs)
        val epochMs = clock.toEpochMs(sampleNs)

        previousSampleNs?.let { prev ->
            val intervalMs = (sampleNs - prev).toDouble() / 1_000_000.0
            if (intervalMs in 0.0..GAP_THRESHOLD_MS) {
                continuousDurationSec += intervalMs / 1000.0
                continuousIntervalCount += 1
                intervalSumMs += intervalMs
                intervalSquaredSumMs += intervalMs * intervalMs
            }
            if (intervalMs > maxGapMs) maxGapMs = intervalMs
            if (intervalMs > GAP_THRESHOLD_MS) lagEventCount += 1
        }
        previousSampleNs = sampleNs

        val axG = event.values[0].toDouble() / GRAVITY
        val ayG = event.values[1].toDouble() / GRAVITY
        val azG = event.values[2].toDouble() / GRAVITY

        writeSample(epochMs, relativeMs, sampleNs, axG, ayG, azG, lastGyroX, lastGyroY, lastGyroZ)
        sampleCount += 1
    }

    private fun writeSample(
        epochMs: Double,
        relativeMs: Double,
        timestampNs: Long,
        ax: Double,
        ay: Double,
        az: Double,
        gx: Double,
        gy: Double,
        gz: Double,
    ) {
        val w = writer ?: return
        val sb = StringBuilder(256)
        sb.append('{')
        appendKV(sb, "\"timestampEpochMs\":", epochMs); sb.append(',')
        appendKV(sb, "\"relativeMs\":", relativeMs); sb.append(',')
        sb.append("\"timestampNs\":").append(timestampNs).append(',')
        sb.append("\"clock\":\"").append(clock.clockName).append("\",")
        sb.append("\"accelerometer\":{")
        appendKV(sb, "\"x\":", ax); sb.append(',')
        appendKV(sb, "\"y\":", ay); sb.append(',')
        appendKV(sb, "\"z\":", az)
        sb.append("},")
        sb.append("\"gyroscope\":{")
        appendKV(sb, "\"x\":", gx); sb.append(',')
        appendKV(sb, "\"y\":", gy); sb.append(',')
        appendKV(sb, "\"z\":", gz)
        sb.append("}}")
        sb.append('\n')
        try { w.append(sb) } catch (_: Throwable) { /* write loss is acceptable; metrics still track counts */ }
    }

    private fun appendKV(sb: StringBuilder, key: String, value: Double) {
        sb.append(key)
        if (value.isNaN() || value.isInfinite()) sb.append("null") else sb.append(value)
    }

    /** Metrics snapshot compatible with `SessionMetadata.IMUMetrics` on iOS. */
    data class Metrics(
        val totalSamples: Int,
        val actualSampleRateHz: Double,
        val startupSamplesDiscarded: Int,
        val sampleIntervalStdDevMs: Double,
        val maxGapMs: Double,
        val lagEvents: Int,
    )

    fun metrics(): Metrics = Metrics(
        totalSamples = max(sampleCount, 0),
        actualSampleRateHz = actualSampleRateHz,
        startupSamplesDiscarded = startupDiscardedCount,
        sampleIntervalStdDevMs = sampleIntervalStdDevMs,
        maxGapMs = maxGapMsValue,
        lagEvents = lagEventCount,
    )
}
