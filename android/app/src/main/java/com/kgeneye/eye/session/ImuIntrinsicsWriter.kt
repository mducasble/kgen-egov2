package com.kgeneye.eye.session

import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Writes `imu_intrinsics_<sessionId>.json` with factory-nominal sensor
 * intrinsics for the IMU. Mirrors the iOS `ImuIntrinsics` model:
 * same schema version, same key set, same wording for the calibration /
 * extrinsics notes — so downstream pipelines treat both platforms the same.
 *
 * Android has thousands of distinct devices, so we always resolve to a
 * single fallback profile (`android_default_class`) and flag
 * `device_known = false`. To upgrade an individual session to
 * `quality = "measured"` later, run Allan variance on a static recording
 * and overwrite this file in S3.
 */
object ImuIntrinsicsWriter {

    private const val SCHEMA_VERSION = "1.0.0"

    private const val CALIBRATION_NOTE =
        "Factory-nominal values from sensor datasheet. No per-device " +
        "measurement has been performed. Upgrade to quality='measured' by " +
        "running Allan variance on a static recording and replacing this " +
        "file."

    private const val EXTRINSICS_NOTE =
        "Nominal extrinsics. IMU and camera share device coordinate frame on " +
        "Android (sensor frame, per Android Sensor docs). Translation is an " +
        "approximate offset from device center to the rear camera sensor. " +
        "For VIO/SLAM use, calibrate with Kalibr or equivalent."

    private const val COORDINATE_FRAME_NOTES =
        "Android sensor coordinate frame: x=right, y=up, z=out of screen " +
        "(toward user). Accelerometer reported in g, gyroscope in rad/s."

    /**
     * Default profile applied to every Android session. Conservative
     * mid-range Apple-A17-class numbers — modern Pixel/Galaxy IMUs are at
     * least this good in practice; they overstate jitter on flagships and
     * understate it on budget devices, which is fine for a "nominal" tag.
     */
    private const val PROFILE_KEY = "android_default_class"
    private const val ACCEL_NOISE_DENSITY = 0.0028
    private const val ACCEL_RANDOM_WALK = 5e-05
    private const val GYRO_NOISE_DENSITY = 0.00025
    private const val GYRO_RANDOM_WALK = 4e-06

    private val ACCEL_SATURATION_RANGE = doubleArrayOf(-8.0, 8.0)
    private val GYRO_SATURATION_RANGE = doubleArrayOf(-34.906585, 34.906585)

    fun write(sessionDir: File, sessionId: String, imuTargetHz: Int, timestampClock: String) {
        val payload = JSONObject().apply {
            put("schemaVersion", SCHEMA_VERSION)
            put("sessionId", sessionId)
            put("deviceId", JSONObject().apply {
                put("vendorId", "")
                put("hardwareIdentifier", Build.DEVICE ?: "")
                put("systemVersion", "Android ${Build.VERSION.RELEASE}")
                put("manufacturer", Build.MANUFACTURER ?: "")
                put("model", Build.MODEL ?: "")
            })
            put("calibration", JSONObject().apply {
                put("method", "datasheet_defaults")
                put("timestamp", isoTimestamp())
                put("quality", "nominal")
                put("profileKey", PROFILE_KEY)
                put("deviceKnown", false)
                put("note", CALIBRATION_NOTE)
            })
            put("sensor", JSONObject().apply {
                put("source", "android.hardware.SensorManager (TYPE_ACCELEROMETER + TYPE_GYROSCOPE)")
                put("clock", timestampClock)
                put("nominalSampleRateHz", imuTargetHz)
                put("coordinateFrame", JSONObject().apply {
                    put("convention", "right_handed")
                    put("axes", JSONObject().apply {
                        put("x", "right")
                        put("y", "up (along device long edge)")
                        put("z", "out of screen (toward user)")
                    })
                    put("notes", COORDINATE_FRAME_NOTES)
                })
            })
            put("accelerometer", JSONObject().apply {
                put("units", "g")
                put("bias", JSONArray(doubleArrayOf(0.0, 0.0, 0.0).toList()))
                put("scaleMisalignment", identityMatrix())
                put("noiseDensity", ACCEL_NOISE_DENSITY)
                put("randomWalk", ACCEL_RANDOM_WALK)
                put("saturationRange", JSONArray(ACCEL_SATURATION_RANGE.toList()))
            })
            put("gyroscope", JSONObject().apply {
                put("units", "rad/s")
                put("bias", JSONArray(doubleArrayOf(0.0, 0.0, 0.0).toList()))
                put("scaleMisalignment", identityMatrix())
                put("noiseDensity", GYRO_NOISE_DENSITY)
                put("randomWalk", GYRO_RANDOM_WALK)
                put("saturationRange", JSONArray(GYRO_SATURATION_RANGE.toList()))
            })
            put("cameraImuExtrinsics", JSONObject().apply {
                put("T_cam_imu", JSONObject().apply {
                    put("translation", JSONArray(doubleArrayOf(0.0, 0.0, -0.07).toList()))
                    put("rotation", JSONObject().apply {
                        put("quaternion", JSONObject().apply {
                            put("w", 1.0)
                            put("x", 0.0)
                            put("y", 0.0)
                            put("z", 0.0)
                        })
                        put("matrix", identityMatrix())
                    })
                })
                put("timeOffsetSec", 0.0)
                put("source", "device_spec")
                put("note", EXTRINSICS_NOTE)
            })
            put("perSessionRefinement", JSONObject.NULL)
        }

        val file = SessionFiles.file("imu_intrinsics", "json", sessionDir)
        file.writeText(payload.toString(2))
    }

    private fun identityMatrix(): JSONArray = JSONArray().apply {
        put(JSONArray(doubleArrayOf(1.0, 0.0, 0.0).toList()))
        put(JSONArray(doubleArrayOf(0.0, 1.0, 0.0).toList()))
        put(JSONArray(doubleArrayOf(0.0, 0.0, 1.0).toList()))
    }

    private fun isoTimestamp(): String {
        val fmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXX", Locale.US)
        fmt.timeZone = TimeZone.getTimeZone("UTC")
        return fmt.format(Date())
    }
}
