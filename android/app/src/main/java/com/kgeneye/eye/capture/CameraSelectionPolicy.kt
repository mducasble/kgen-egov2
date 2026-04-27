package com.kgeneye.eye.capture

import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CameraMetadata
import android.util.Log

/**
 * Picks the rear camera with the **widest field-of-view** so the Android
 * recorder behaves like the iOS pipeline (`AVCaptureDevice.DiscoverySession`
 * configured with `[.builtInUltraWideCamera]`).
 *
 * On Android there's no semantic "ultra-wide" enum: every back-facing
 * camera reports its focal length in `LENS_INFO_AVAILABLE_FOCAL_LENGTHS`.
 * The smallest focal length corresponds to the widest field of view, which
 * is what we want for an ego-centric recording.
 */
object CameraSelectionPolicy {

    data class Selected(
        val cameraId: String,
        val focalLengthMm: Double,
        val sensorWidthMm: Double,
        val sensorHeightMm: Double,
        val isUltraWide: Boolean,
    )

    /**
     * Returns the rear camera with the widest FOV (smallest focal length).
     * Falls back to the first available camera ID when no characteristics
     * are readable. Returns `null` only when the device exposes no cameras
     * at all (e.g. emulators without camera support).
     */
    fun pick(context: Context): Selected? {
        val manager = context.getSystemService(Context.CAMERA_SERVICE) as? CameraManager ?: return null
        val ids = try { manager.cameraIdList } catch (_: Throwable) { return null }
        if (ids.isEmpty()) return null

        var best: Selected? = null
        for (id in ids) {
            val chars = try { manager.getCameraCharacteristics(id) } catch (_: Throwable) { continue }
            val facing = chars.get(CameraCharacteristics.LENS_FACING)
            if (facing != CameraMetadata.LENS_FACING_BACK) continue

            val focal = chars.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)?.firstOrNull()
                ?: continue
            val sensorSize = chars.get(CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE)
            val candidate = Selected(
                cameraId = id,
                focalLengthMm = focal.toDouble(),
                sensorWidthMm = sensorSize?.width?.toDouble() ?: 0.0,
                sensorHeightMm = sensorSize?.height?.toDouble() ?: 0.0,
                // Heuristic: an Apple "ultra-wide" lens has hFov ≈ 120°. For the
                // typical ~6 mm sensor the matching focal length is ≤ 2.5 mm.
                isUltraWide = focal.toDouble() <= 2.5,
            )
            if (best == null || candidate.focalLengthMm < best.focalLengthMm) {
                best = candidate
            }
        }

        if (best == null) {
            // No back camera with focal-length metadata. Fall back to the first
            // camera so the pipeline still records something on quirky devices.
            best = Selected(ids.first(), 0.0, 0.0, 0.0, false)
            Log.w(TAG, "No rear camera with focal-length metadata; falling back to ${best.cameraId}")
        } else {
            Log.i(TAG, "Selected rear camera ${best.cameraId} (f=${best.focalLengthMm}mm, ultraWide=${best.isUltraWide})")
        }
        return best
    }

    private const val TAG = "CameraSelectionPolicy"
}
