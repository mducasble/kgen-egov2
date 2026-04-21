import Foundation

/// Swift twin of the Python ``build_intrinsics`` used by the S3 backfill
/// script (``serverless/scripts/s3_backfill_intrinsics.py``). Generated on
/// the device at session finalize so every new recording ships with an
/// ``imu_intrinsics_<sessionId>.json`` next to ``metadata.json``.
///
/// The payload is **factory-nominal**: values come from the device-class
/// sensor datasheet keyed off ``device.hardwareIdentifier`` — no per-device
/// calibration has been performed. ``calibration.quality = "nominal"`` and
/// ``calibration.method = "datasheet_defaults"`` make this explicit so
/// downstream consumers can later upgrade individual sessions to
/// ``"measured"`` by running Allan variance and overwriting the file.
///
/// Keep the schema identical to the Python generator. The offline backfill
/// and this on-device writer must produce the same JSON given the same
/// inputs.
enum ImuIntrinsics {

    static let schemaVersion = "1.0.0"

    static let calibrationNote =
        "Factory-nominal values from sensor datasheet. No per-device measurement " +
        "has been performed. Upgrade to quality='measured' by running Allan " +
        "variance on a static recording and replacing this file."

    static let extrinsicsNote =
        "Nominal extrinsics. IMU and camera share device coordinate frame in " +
        "iOS. Translation is approximate offset from device center to ultra-wide " +
        "camera sensor. For VIO/SLAM use, calibrate with Kalibr or equivalent."

    static let coordinateFrameNotes =
        "Standard iOS device frame per Apple docs. CMMotionManager reports " +
        "accelerometer in G and gyroscope in rad/s."

    /// Default manifest description for the artifact. Used by
    /// ``SessionPackagingService`` when classifying files for
    /// ``session_manifest.json``.
    static let manifestArtifactDescription =
        "IMU intrinsics (factory-nominal bias/noise model + camera↔IMU " +
        "extrinsics). Out-of-MCAP annotation."

    /// Device-class keys. Mirrors ``FACTORY_DEFAULTS`` in the Python script.
    private static let factoryDefaults: [String: String] = [
        "iPhone18,1": "apple_a19_class",   // iPhone 17 Pro
        "iPhone18,2": "apple_a19_class",   // iPhone 17 Pro Max
        "iPhone18,3": "apple_a19_class",   // iPhone 17
        "iPhone18,5": "apple_a19_class",   // iPhone 17e
        "iPhone17,1": "apple_a18_class",
        "iPhone17,2": "apple_a18_class",
        "iPhone17,3": "apple_a18_class",
        "iPhone17,4": "apple_a18_class",
        "iPhone17,5": "apple_a18_class",
        "iPhone16,1": "apple_a17_class",
        "iPhone16,2": "apple_a17_class",
        "iPhone15,4": "apple_a16_class",   // iPhone 15
        "iPhone15,5": "apple_a16_class",   // iPhone 15 Plus
        "iPhone15,2": "apple_a16_class",   // iPhone 14 Pro
        "iPhone15,3": "apple_a16_class",   // iPhone 14 Pro Max
        "iPhone14,2": "apple_a15_class",   // iPhone 13 Pro
        "iPhone14,3": "apple_a15_class",   // iPhone 13 Pro Max
        "iPhone14,4": "apple_a15_class",   // iPhone 13 mini
        "iPhone14,5": "apple_a15_class",   // iPhone 13
        "iPhone14,6": "apple_a15_class",   // iPhone SE (3rd gen)
        "iPhone14,7": "apple_a15_class",   // iPhone 14
        "iPhone14,8": "apple_a15_class",   // iPhone 14 Plus
        "iPhone12,1": "apple_a13_class",   // iPhone 11
        "iPhone12,3": "apple_a13_class",   // iPhone 11 Pro
        "iPhone12,5": "apple_a13_class",   // iPhone 11 Pro Max
        "iPhone12,8": "apple_a13_class",   // iPhone SE (2nd gen)
    ]

    /// Unknown devices fall back to this profile. Matches
    /// ``FALLBACK_PROFILE`` in the Python script.
    static let fallbackProfile = "apple_a16_class"

    struct SensorProfile {
        let accelNoiseDensity: Double
        let accelRandomWalk: Double
        let gyroNoiseDensity: Double
        let gyroRandomWalk: Double

        // Saturation ranges are the same for every Apple IMU class in the
        // datasheet so we keep them as shared constants.
        static let accelSaturationRange: [Double] = [-8.0, 8.0]
        static let gyroSaturationRange: [Double] = [-34.906585, 34.906585]
    }

    private static let sensorProfiles: [String: SensorProfile] = [
        "apple_a19_class": SensorProfile(
            accelNoiseDensity: 0.0020, accelRandomWalk: 3e-05,
            gyroNoiseDensity: 0.00017, gyroRandomWalk: 2e-06
        ),
        "apple_a18_class": SensorProfile(
            accelNoiseDensity: 0.0023, accelRandomWalk: 3e-05,
            gyroNoiseDensity: 0.00019, gyroRandomWalk: 2e-06
        ),
        "apple_a17_class": SensorProfile(
            accelNoiseDensity: 0.0025, accelRandomWalk: 4e-05,
            gyroNoiseDensity: 0.00022, gyroRandomWalk: 3e-06
        ),
        "apple_a16_class": SensorProfile(
            accelNoiseDensity: 0.0028, accelRandomWalk: 5e-05,
            gyroNoiseDensity: 0.00025, gyroRandomWalk: 4e-06
        ),
        "apple_a15_class": SensorProfile(
            accelNoiseDensity: 0.0030, accelRandomWalk: 5e-05,
            gyroNoiseDensity: 0.00028, gyroRandomWalk: 5e-06
        ),
        "apple_a13_class": SensorProfile(
            accelNoiseDensity: 0.0035, accelRandomWalk: 7e-05,
            gyroNoiseDensity: 0.00035, gyroRandomWalk: 7e-06
        ),
    ]

    /// Returns `(profileKey, deviceKnown)` for the given hardware identifier.
    /// Unknown devices always resolve to ``fallbackProfile`` with
    /// `deviceKnown = false`.
    static func resolveProfile(forHardwareIdentifier id: String) -> (key: String, known: Bool) {
        if let mapped = factoryDefaults[id] { return (mapped, true) }
        return (fallbackProfile, false)
    }

    /// Build the payload from the session's resolved metadata. Pure and
    /// side-effect free; anything that involves the clock is injected via
    /// ``now`` so tests can stabilise the timestamp.
    static func build(
        sessionId: String,
        hardwareIdentifier: String,
        systemVersion: String,
        vendorId: String?,
        imuTargetHz: Int,
        timestampClock: String,
        now: Date = Date()
    ) -> Payload {
        let (profileKey, known) = resolveProfile(forHardwareIdentifier: hardwareIdentifier)
        // Unknown devices still produce a payload so every session ships
        // with intrinsics. The flag is the signal, not the presence of the
        // file.
        guard let profile = sensorProfiles[profileKey] ?? sensorProfiles[fallbackProfile] else {
            // Unreachable: ``fallbackProfile`` is always present. Defensive
            // fallback to avoid crashing at session finalize.
            return Payload.empty(sessionId: sessionId, hardwareIdentifier: hardwareIdentifier)
        }

        let timestamp = intrinsicsTimestampFormatter.string(from: now)

        return Payload(
            schemaVersion: schemaVersion,
            sessionId: sessionId,
            deviceId: Payload.DeviceId(
                vendorId: vendorId ?? "",
                hardwareIdentifier: hardwareIdentifier,
                systemVersion: systemVersion
            ),
            calibration: Payload.Calibration(
                method: "datasheet_defaults",
                timestamp: timestamp,
                quality: "nominal",
                profileKey: profileKey,
                deviceKnown: known,
                note: calibrationNote
            ),
            sensor: Payload.Sensor(
                source: "CMMotionManager.deviceMotion",
                clock: timestampClock,
                nominalSampleRateHz: imuTargetHz,
                coordinateFrame: Payload.CoordinateFrame(
                    convention: "right_handed",
                    axes: Payload.CoordinateFrame.Axes(
                        x: "right (device landscape, from home button to volume buttons)",
                        y: "up (along device long edge)",
                        z: "out of screen (toward user)"
                    ),
                    notes: coordinateFrameNotes
                )
            ),
            accelerometer: Payload.Accelerometer(
                units: "g",
                bias: [0.0, 0.0, 0.0],
                scaleMisalignment: Self.identityMatrix,
                noiseDensity: profile.accelNoiseDensity,
                randomWalk: profile.accelRandomWalk,
                saturationRange: SensorProfile.accelSaturationRange
            ),
            gyroscope: Payload.Gyroscope(
                units: "rad/s",
                bias: [0.0, 0.0, 0.0],
                scaleMisalignment: Self.identityMatrix,
                noiseDensity: profile.gyroNoiseDensity,
                randomWalk: profile.gyroRandomWalk,
                saturationRange: SensorProfile.gyroSaturationRange
            ),
            cameraImuExtrinsics: Payload.CameraImuExtrinsics(
                T_cam_imu: Payload.TCamImu(
                    translation: [0.0, 0.0, -0.07],
                    rotation: Payload.Rotation(
                        quaternion: Payload.Quaternion(w: 1.0, x: 0.0, y: 0.0, z: 0.0),
                        matrix: Self.identityMatrix
                    )
                ),
                timeOffsetSec: 0.0,
                source: "device_spec",
                note: extrinsicsNote
            )
        )
    }

    private static let identityMatrix: [[Double]] = [
        [1, 0, 0],
        [0, 1, 0],
        [0, 0, 1],
    ]

    /// On-disk payload. Shape matches the Python generator byte-for-byte
    /// (sorted keys, pretty-printed, with ``perSessionRefinement: null``).
    struct Payload: Encodable {
        let schemaVersion: String
        let sessionId: String
        let deviceId: DeviceId
        let calibration: Calibration
        let sensor: Sensor
        let accelerometer: Accelerometer
        let gyroscope: Gyroscope
        let cameraImuExtrinsics: CameraImuExtrinsics

        // Encoded as a literal JSON null to match the Python generator.
        // ``Encodable``'s default behaviour would omit a nil optional, so we
        // hand-roll the container and call ``encodeNil`` for this key.
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(schemaVersion, forKey: .schemaVersion)
            try c.encode(sessionId, forKey: .sessionId)
            try c.encode(deviceId, forKey: .deviceId)
            try c.encode(calibration, forKey: .calibration)
            try c.encode(sensor, forKey: .sensor)
            try c.encode(accelerometer, forKey: .accelerometer)
            try c.encode(gyroscope, forKey: .gyroscope)
            try c.encode(cameraImuExtrinsics, forKey: .cameraImuExtrinsics)
            try c.encodeNil(forKey: .perSessionRefinement)
        }

        enum CodingKeys: String, CodingKey {
            case schemaVersion, sessionId, deviceId, calibration, sensor
            case accelerometer, gyroscope, cameraImuExtrinsics
            case perSessionRefinement
        }

        struct DeviceId: Codable {
            let vendorId: String
            let hardwareIdentifier: String
            let systemVersion: String
        }

        struct Calibration: Codable {
            let method: String
            let timestamp: String
            let quality: String
            let profileKey: String
            let deviceKnown: Bool
            let note: String
        }

        struct Sensor: Codable {
            let source: String
            let clock: String
            let nominalSampleRateHz: Int
            let coordinateFrame: CoordinateFrame
        }

        struct CoordinateFrame: Codable {
            let convention: String
            let axes: Axes
            let notes: String
            struct Axes: Codable { let x: String; let y: String; let z: String }
        }

        struct Accelerometer: Codable {
            let units: String
            let bias: [Double]
            let scaleMisalignment: [[Double]]
            let noiseDensity: Double
            let randomWalk: Double
            let saturationRange: [Double]
        }

        struct Gyroscope: Codable {
            let units: String
            let bias: [Double]
            let scaleMisalignment: [[Double]]
            let noiseDensity: Double
            let randomWalk: Double
            let saturationRange: [Double]
        }

        struct CameraImuExtrinsics: Codable {
            let T_cam_imu: TCamImu
            let timeOffsetSec: Double
            let source: String
            let note: String
        }

        struct TCamImu: Codable {
            let translation: [Double]
            let rotation: Rotation
        }

        struct Rotation: Codable {
            let quaternion: Quaternion
            let matrix: [[Double]]
        }

        struct Quaternion: Codable {
            let w: Double
            let x: Double
            let y: Double
            let z: Double
        }

        /// Defensive fallback when no sensor profile can be resolved.
        /// Shouldn't happen in practice — ``fallbackProfile`` is always in
        /// the table — but we avoid crashing at session finalize.
        static func empty(sessionId: String, hardwareIdentifier: String) -> Payload {
            Payload(
                schemaVersion: ImuIntrinsics.schemaVersion,
                sessionId: sessionId,
                deviceId: DeviceId(vendorId: "", hardwareIdentifier: hardwareIdentifier, systemVersion: ""),
                calibration: Calibration(
                    method: "datasheet_defaults",
                    timestamp: intrinsicsTimestampFormatter.string(from: Date()),
                    quality: "nominal",
                    profileKey: ImuIntrinsics.fallbackProfile,
                    deviceKnown: false,
                    note: ImuIntrinsics.calibrationNote
                ),
                sensor: Sensor(
                    source: "CMMotionManager.deviceMotion",
                    clock: "mach_absolute_time",
                    nominalSampleRateHz: 100,
                    coordinateFrame: CoordinateFrame(
                        convention: "right_handed",
                        axes: CoordinateFrame.Axes(x: "", y: "", z: ""),
                        notes: ImuIntrinsics.coordinateFrameNotes
                    )
                ),
                accelerometer: Accelerometer(
                    units: "g", bias: [0, 0, 0], scaleMisalignment: ImuIntrinsics.identityMatrix,
                    noiseDensity: 0, randomWalk: 0,
                    saturationRange: SensorProfile.accelSaturationRange
                ),
                gyroscope: Gyroscope(
                    units: "rad/s", bias: [0, 0, 0], scaleMisalignment: ImuIntrinsics.identityMatrix,
                    noiseDensity: 0, randomWalk: 0,
                    saturationRange: SensorProfile.gyroSaturationRange
                ),
                cameraImuExtrinsics: CameraImuExtrinsics(
                    T_cam_imu: TCamImu(
                        translation: [0, 0, -0.07],
                        rotation: Rotation(
                            quaternion: Quaternion(w: 1, x: 0, y: 0, z: 0),
                            matrix: ImuIntrinsics.identityMatrix
                        )
                    ),
                    timeOffsetSec: 0, source: "device_spec", note: ImuIntrinsics.extrinsicsNote
                )
            )
        }
    }
}

/// Matches Python's ``datetime.isoformat()`` output with microsecond
/// precision: ``2026-04-21T02:27:03.019176+00:00``. Swift's built-in
/// ``ISO8601DateFormatter`` maxes out at milliseconds, so we use
/// ``DateFormatter`` with an explicit POSIX locale and UTC timezone.
private let intrinsicsTimestampFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(secondsFromGMT: 0)
    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX"
    return f
}()
