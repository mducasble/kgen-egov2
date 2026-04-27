package com.kgeneye.eye.session

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Rect
import android.media.MediaMetadataRetriever
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import kotlin.math.max

/**
 * Extracts the first frame of a session's `video_<code>.mp4` and caches it
 * as `thumbnail_<code>.jpg` (128×128 aspect-fill JPEG, q=0.8) inside the
 * session directory. Mirrors `ThumbnailGenerator` on iOS so the Sessions
 * screen shows a real frame as soon as the recording finishes.
 *
 * Safe to call repeatedly — subsequent calls short-circuit on the disk
 * cache. Returns `null` if the source video is missing or
 * `MediaMetadataRetriever` fails to decode the early sample.
 */
object ThumbnailGenerator {

    private const val THUMB_SIZE = 128
    private const val JPEG_QUALITY = 80

    fun cacheFile(sessionDir: File): File =
        SessionFiles.file("thumbnail", "jpg", sessionDir)

    fun cachedBitmap(sessionDir: File): Bitmap? {
        val f = cacheFile(sessionDir)
        if (!f.exists()) return null
        return try { BitmapFactory.decodeFile(f.absolutePath) } catch (_: Throwable) { null }
    }

    /**
     * Generate the thumbnail if it isn't cached yet. Looks up the canonical
     * `video_<code>.mp4` in [sessionDir] and writes
     * `thumbnail_<code>.jpg` next to it.
     */
    fun generateIfNeeded(sessionDir: File): Bitmap? {
        val cache = cacheFile(sessionDir)
        if (cache.exists()) {
            return try { BitmapFactory.decodeFile(cache.absolutePath) } catch (_: Throwable) { null }
        }
        val video = SessionFiles.file("video", "mp4", sessionDir)
        if (!video.exists()) return null

        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(video.absolutePath)
            // 100 ms in to avoid the occasional black/green opening frame.
            val frame = retriever.getFrameAtTime(
                100_000L,
                MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
            ) ?: return null
            val resized = aspectFillResize(frame, THUMB_SIZE, THUMB_SIZE)
            FileOutputStream(cache).use { out ->
                resized.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, out)
            }
            if (resized !== frame) frame.recycle()
            resized
        } catch (t: Throwable) {
            Log.w(TAG, "thumbnail generation failed: ${t.message}")
            null
        } finally {
            try { retriever.release() } catch (_: Throwable) {}
        }
    }

    /**
     * Center-crop + scale so the source covers the entire `target × target`
     * canvas (aspect-fill). Avoids the letter-boxing `Bitmap.createScaledBitmap`
     * would introduce for 16:9 / 4:3 frames.
     */
    private fun aspectFillResize(src: Bitmap, targetW: Int, targetH: Int): Bitmap {
        val srcW = src.width
        val srcH = src.height
        if (srcW <= 0 || srcH <= 0) return src
        val scale = max(targetW.toDouble() / srcW, targetH.toDouble() / srcH)
        val drawW = (srcW * scale).toInt().coerceAtLeast(1)
        val drawH = (srcH * scale).toInt().coerceAtLeast(1)
        val dx = (targetW - drawW) / 2
        val dy = (targetH - drawH) / 2

        val out = Bitmap.createBitmap(targetW, targetH, Bitmap.Config.ARGB_8888)
        Canvas(out).apply {
            drawColor(0xFF000000.toInt())
            drawBitmap(
                src,
                Rect(0, 0, srcW, srcH),
                Rect(dx, dy, dx + drawW, dy + drawH),
                Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG),
            )
        }
        return out
    }

    private const val TAG = "ThumbnailGenerator"
}
