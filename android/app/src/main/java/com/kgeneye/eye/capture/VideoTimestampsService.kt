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

    val frameCount: Int get() = frameIndex

    fun start(outputFile: File) {
        writer = BufferedWriter(FileWriter(outputFile, false))
        startNs = clock.nowNs()
        frameIndex = 0
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
        try {
            w.append(
                """{"frameIndex":$frameIndex,"timestampNs":$ts,"timestampEpochMs":$epochMs,"relativeMs":$relMs}""" + "\n"
            )
        } catch (t: Throwable) {
            Log.w(TAG, "video timestamp write failed: ${t.message}")
        }
        frameIndex += 1
    }

    companion object {
        private const val TAG = "VideoTimestampsService"
    }
}
