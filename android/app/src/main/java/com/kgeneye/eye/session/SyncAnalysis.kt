package com.kgeneye.eye.session

import kotlin.math.abs
import kotlin.math.sqrt

/**
 * Post-capture IMU↔video sync validation. Mirrors the iOS
 * `SyncAnalysisService` byte-for-byte in field semantics.
 *
 * Both video frame timestamps (CameraX `ImageProxy.imageInfo.timestamp`)
 * and IMU sample timestamps (`SensorEvent.timestamp`) are expressed in the
 * `elapsed_realtime_nanos` clock, so the true offset is **0** by
 * construction. We compute nearest-neighbor deltas as a health check —
 * jitter should be bounded by the IMU sampling interval (~10 ms).
 */
object SyncAnalysis {

    data class Result(
        val estimatedOffsetMs: Double,
        val method: String,
        val confidence: String,
        val observedJitterStdDevMs: Double,
        val observedMaxDeltaMs: Double,
        val samplePairsUsed: Int,
    )

    /**
     * Compute IMU↔video sync metrics. Returns deterministic 0-offset with
     * jitter/max-delta sampled across at most 100 frame pairs (matches iOS
     * stride heuristic).
     */
    fun computeIMUVideoSync(
        videoTimestampsNs: LongArray,
        imuTimestampsNs: LongArray,
    ): Result {
        if (videoTimestampsNs.size <= 10 || imuTimestampsNs.size <= 10) {
            return Result(0.0, "shared_clock", "deterministic", 0.0, 0.0, 0)
        }

        val sortedImu = imuTimestampsNs.copyOf().also { it.sort() }
        val deltasMs = DoubleArray(((videoTimestampsNs.size + 99) / 100).coerceAtLeast(1))
        val stride = (videoTimestampsNs.size / 100).coerceAtLeast(1)

        var written = 0
        var i = 0
        while (i < videoTimestampsNs.size && written < deltasMs.size) {
            val videoNs = videoTimestampsNs[i]
            val nearest = findNearest(videoNs, sortedImu)
            deltasMs[written] = abs(videoNs - nearest).toDouble() / 1_000_000.0
            written += 1
            i += stride
        }

        if (written == 0) return Result(0.0, "shared_clock", "deterministic", 0.0, 0.0, 0)

        var sum = 0.0
        var maxDelta = 0.0
        for (k in 0 until written) {
            sum += deltasMs[k]
            if (deltasMs[k] > maxDelta) maxDelta = deltasMs[k]
        }
        val mean = sum / written

        var sqDiffs = 0.0
        for (k in 0 until written) {
            val d = deltasMs[k] - mean
            sqDiffs += d * d
        }
        val variance = sqDiffs / written
        val stdDev = if (variance > 0) sqrt(variance) else 0.0

        return Result(
            estimatedOffsetMs = 0.0,
            method = "shared_clock",
            confidence = "deterministic",
            observedJitterStdDevMs = stdDev,
            observedMaxDeltaMs = maxDelta,
            samplePairsUsed = written,
        )
    }

    /** Binary search: nearest value in a sorted array (clamped to bounds). */
    private fun findNearest(target: Long, sorted: LongArray): Long {
        if (sorted.isEmpty()) return target
        var lo = 0
        var hi = sorted.size - 1
        while (lo < hi) {
            val mid = (lo + hi) ushr 1
            if (sorted[mid] < target) lo = mid + 1 else hi = mid
        }
        if (lo == 0) return sorted[0]
        val a = sorted[lo - 1]
        val b = sorted[lo]
        return if ((target - a) <= (b - target)) a else b
    }
}
