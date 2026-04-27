package com.kgeneye.eye.capture

import android.util.Log
import androidx.camera.core.ImageProxy
import java.io.BufferedWriter
import java.io.File
import java.io.FileWriter
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Logs per-frame timestamps delivered through CameraX `ImageAnalysis` while
 * the recorder is active. Writes `video_timestamps_<code>.jsonl` — one JSON
 * record per frame with the same keys the iOS pipeline consumes:
 *   { frameIndex, timestampNs, timestampEpochMs, relativeMs }
 *
 * The timestamp clock here is `elapsed_realtime_nanos` (matches
 * [MonotonicClock]) so downstream IMU↔video sync can run identically to iOS.
 */
class VideoTimestampsService {

    private val clock = MonotonicClock.shared
    private var writer: BufferedWriter? = null
    private var startNs: Long = 0
    private var frameIndex: Int = 0
    private val active = AtomicBoolean(false)

    /**
     * In-memory mirror of every recorded frame timestamp (ns). Kept so
     * `SyncAnalysis` can run a nearest-neighbor sync check against the IMU
     * stream at finalize time, mirroring the iOS pipeline.
     */
    private val timestampsNs = ArrayList<Long>(4 * 1024)

    val frameCount: Int get() = frameIndex

    /** Snapshot of every recorded frame timestamp (monotonic ns). */
    fun allTimestampsNs(): LongArray {
        synchronized(timestampsNs) { return timestampsNs.toLongArray() }
    }

    fun start(outputFile: File) {
        writer = BufferedWriter(FileWriter(outputFile, false))
        startNs = clock.nowNs()
        frameIndex = 0
        synchronized(timestampsNs) { timestampsNs.clear() }
        active.set(true)
    }

    fun stop() {
        if (!active.compareAndSet(true, false)) return
        try { writer?.flush(); writer?.close() } catch (_: Throwable) {}
        writer = null
    }

    /**
     * Record the frame provided by the analyzer.
     *
     * NOTE: `image.imageInfo.timestamp` on Android is typically in the
     * `SystemClock.elapsedRealtimeNanos` domain, same reference as
     * [MonotonicClock.nowNs] — so IMU and video timestamps align without
     * an additional offset.
     */
    fun record(image: ImageProxy) {
        val w = writer
        if (!active.get() || w == null) return
        val ts = image.imageInfo.timestamp
        val epochMs = clock.toEpochMs(ts)
        val relMs = clock.toRelativeMs(ts, startNs)
        val presentationTimeSec = ts.toDouble() / 1_000_000_000.0
        try {
            w.append(
                """{"clock":"${clock.clockName}","frameIndex":$frameIndex,"isEstimated":false,"presentationTimeSec":$presentationTimeSec,"relativeMs":$relMs,"timestampEpochMs":$epochMs,"timestampNs":$ts}""" + "\n"
            )
        } catch (t: Throwable) {
            Log.w(TAG, "video timestamp write failed: ${t.message}")
        }
        synchronized(timestampsNs) { timestampsNs.add(ts) }
        frameIndex += 1
    }

    companion object {
        private const val TAG = "VideoTimestampsService"
    }
}
