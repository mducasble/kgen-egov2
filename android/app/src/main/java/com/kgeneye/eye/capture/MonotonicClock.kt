package com.kgeneye.eye.capture

import android.os.SystemClock

/**
 * Shared monotonic clock for the capture pipeline.
 *
 * On Android we key off [SystemClock.elapsedRealtimeNanos] because every
 * [android.hardware.SensorEvent.timestamp] and CameraX video frame
 * timestamp are expressed in the same reference. This mirrors the role of
 * `mach_absolute_time` on iOS inside `MonotonicClock`.
 *
 * Wall-clock conversion is done once, at the start of a recording, by
 * snapshotting the offset between `System.currentTimeMillis()` and the
 * current monotonic reading.
 */
class MonotonicClock private constructor() {

    val clockName: String = "elapsed_realtime_nanos"

    private val epochAtBootMs: Double = run {
        val epochNowMs = System.currentTimeMillis().toDouble()
        val monotonicNowMs = SystemClock.elapsedRealtimeNanos().toDouble() / 1_000_000.0
        epochNowMs - monotonicNowMs
    }

    fun nowNs(): Long = SystemClock.elapsedRealtimeNanos()

    fun toEpochMs(timestampNs: Long): Double =
        epochAtBootMs + (timestampNs.toDouble() / 1_000_000.0)

    fun toRelativeMs(timestampNs: Long, startNs: Long): Double =
        (timestampNs - startNs).toDouble() / 1_000_000.0

    companion object {
        val shared = MonotonicClock()
    }
}
