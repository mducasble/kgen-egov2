package com.kgeneye.eye.capture

/**
 * Synchronized accelerometer + gyroscope sample.
 *
 * Axis convention mirrors the device reference frame reported by
 * [android.hardware.SensorManager] (right-hand rule, +Z out of the screen).
 * Accelerometer values are stored in **G's** (1 G ≈ 9.80665 m/s²) so the
 * payload is comparable to the iOS `IMUSample` captured via CoreMotion.
 */
data class ImuSample(
    /** Epoch wall-clock in milliseconds (logging/debug only). */
    val timestampEpochMs: Double,
    /** Milliseconds elapsed since recording start. */
    val relativeMs: Double,
    /** Monotonic nanoseconds ([android.os.SystemClock.elapsedRealtimeNanos]). */
    val timestampNs: Long,
    /** Clock source identifier. */
    val clock: String,
    val accelerometer: XYZ,
    val gyroscope: XYZ,
) {
    data class XYZ(val x: Double, val y: Double, val z: Double)
}
