package com.kgeneye.eye.capture

import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import kotlin.math.atan
import kotlin.math.hypot

/**
 * Reads the per-device intrinsic / distortion datasheet for a given
 * Camera2 `cameraId`, mirroring the lens calibration block iOS records
 * inside `metadata.json`.
 *
 * Android exposes:
 *   - `LENS_INTRINSIC_CALIBRATION` — `[fx, fy, cx, cy, s]` in pixel units,
 *     factory-calibrated when the device firmware ships it. Many mid-range
 *     phones leave it `null`; we fall back to a pinhole derivation from
 *     focal length + sensor size in that case (matching the iOS
 *     `pinhole_derived_from_fov` path).
 *   - `LENS_DISTORTION` — Brown–Conrady coefficients `[k1, k2, k3, p1, p2]`,
 *     also typically `null` on mid-range hardware.
 */
object CameraIntrinsicsReader {

    data class Result(
        /** Source label embedded in metadata.json. */
        val intrinsicsSource: String,
        val fx: Double,
        val fy: Double,
        val cx: Double,
        val cy: Double,
        val skew: Double,
        val distortion: DoubleArray?,
        val horizontalFovDeg: Double,
        val diagonalFovDeg: Double,
    )

    fun read(context: Context, cameraId: String, frameWidth: Int, frameHeight: Int): Result {
        val manager = context.getSystemService(Context.CAMERA_SERVICE) as? CameraManager
            ?: return Result("unavailable", 0.0, 0.0, 0.0, 0.0, 0.0, null, 0.0, 0.0)
        val chars = try { manager.getCameraCharacteristics(cameraId) }
        catch (_: Throwable) {
            return Result("unavailable", 0.0, 0.0, 0.0, 0.0, 0.0, null, 0.0, 0.0)
        }

        val intrinsicsArray = chars.get(CameraCharacteristics.LENS_INTRINSIC_CALIBRATION)
        val distortionArray = chars.get(CameraCharacteristics.LENS_DISTORTION)
            ?.map { it.toDouble() }
            ?.toDoubleArray()
        val sensorSize = chars.get(CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE)
        val focal = chars.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)?.firstOrNull()
            ?.toDouble() ?: 0.0
        val sensorWmm = sensorSize?.width?.toDouble() ?: 0.0
        val sensorHmm = sensorSize?.height?.toDouble() ?: 0.0

        val (hFov, dFov) = computeFov(sensorWmm, sensorHmm, focal, frameWidth, frameHeight)

        if (intrinsicsArray != null && intrinsicsArray.size >= 5 && frameWidth > 0 && frameHeight > 0) {
            // Camera2 reports [fx, fy, cx, cy, s] in the pixel array's
            // coordinate space. That's directly comparable to the
            // measured intrinsics iOS extracts via
            // `kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix`.
            return Result(
                intrinsicsSource = "camera2_lens_intrinsic_calibration",
                fx = intrinsicsArray[0].toDouble(),
                fy = intrinsicsArray[1].toDouble(),
                cx = intrinsicsArray[2].toDouble(),
                cy = intrinsicsArray[3].toDouble(),
                skew = intrinsicsArray[4].toDouble(),
                distortion = distortionArray,
                horizontalFovDeg = hFov,
                diagonalFovDeg = dFov,
            )
        }

        // Pinhole derivation from focal length + sensor / frame size.
        val (fx, fy, cx, cy) = derivePinholeIntrinsics(
            focalMm = focal,
            sensorWmm = sensorWmm,
            sensorHmm = sensorHmm,
            frameW = frameWidth,
            frameH = frameHeight,
        )
        return Result(
            intrinsicsSource = "pinhole_derived_from_focal_length",
            fx = fx, fy = fy, cx = cx, cy = cy, skew = 0.0,
            distortion = distortionArray,
            horizontalFovDeg = hFov,
            diagonalFovDeg = dFov,
        )
    }

    private fun derivePinholeIntrinsics(
        focalMm: Double, sensorWmm: Double, sensorHmm: Double,
        frameW: Int, frameH: Int,
    ): DoubleArray {
        if (focalMm <= 0.0 || sensorWmm <= 0.0 || sensorHmm <= 0.0 || frameW <= 0 || frameH <= 0) {
            return doubleArrayOf(0.0, 0.0, frameW / 2.0, frameH / 2.0)
        }
        val fx = focalMm / sensorWmm * frameW
        val fy = focalMm / sensorHmm * frameH
        val cx = frameW / 2.0
        val cy = frameH / 2.0
        return doubleArrayOf(fx, fy, cx, cy)
    }

    private fun computeFov(
        sensorWmm: Double, sensorHmm: Double, focalMm: Double,
        width: Int, height: Int,
    ): Pair<Double, Double> {
        if (focalMm <= 0.0 || sensorWmm <= 0.0) return 0.0 to 0.0
        val sensorAspect = sensorWmm / sensorHmm.coerceAtLeast(1e-6)
        val targetAspect = width.toDouble() / height.coerceAtLeast(1).toDouble()
        val activeWmm: Double
        val activeHmm: Double
        if (targetAspect >= sensorAspect) {
            activeWmm = sensorWmm
            activeHmm = sensorWmm / targetAspect
        } else {
            activeHmm = sensorHmm
            activeWmm = sensorHmm * targetAspect
        }
        val hFov = 2.0 * atan(activeWmm / (2.0 * focalMm))
        val diag = hypot(activeWmm, activeHmm)
        val dFov = 2.0 * atan(diag / (2.0 * focalMm))
        return Math.toDegrees(hFov) to Math.toDegrees(dFov)
    }
}

private operator fun DoubleArray.component1(): Double = this[0]
private operator fun DoubleArray.component2(): Double = this[1]
private operator fun DoubleArray.component3(): Double = this[2]
private operator fun DoubleArray.component4(): Double = this[3]
