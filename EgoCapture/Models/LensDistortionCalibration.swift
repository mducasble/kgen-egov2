import Foundation

/// Persisted lens-distortion calibration for a device. Stored **at the probe's
/// reference resolution**; callers scale to their own recording resolution via
/// `scaledIntrinsics(recordingWidth:recordingHeight:)`.
///
/// The fit is obtained from `AVCameraCalibrationData` harvested during a
/// one-shot probe on a virtual multi-camera device (`BuiltInDualWideCamera`
/// preferred) with constituent-photo delivery restricted to the ultra-wide
/// camera. Coefficients follow the OpenCV / ROS plumb_bob convention with
/// tangential terms pinned to zero (`[k1, k2, 0, 0, k3]`).
struct LensDistortionCalibration: Codable, Equatable {

    /// Bump when the on-disk layout changes so stale caches are discarded.
    static let schemaVersion: Int = 2

    let schemaVersion: Int

    /// Hardware model string (e.g. `"iPhone15,3"`) — the cache key.
    let deviceIdentifier: String

    /// Reference resolution reported by `AVCameraCalibrationData.intrinsicMatrixReferenceDimensions`.
    let probeWidth: Int
    let probeHeight: Int

    /// Intrinsic matrix at probe reference resolution, row-major (9 entries).
    /// Stored as doubles to survive a round-trip through JSON.
    let intrinsicMatrixRowMajor: [Double]

    /// `AVCameraCalibrationData.lensDistortionCenter`, in probe-reference pixels.
    let distortionCenterX: Double
    let distortionCenterY: Double

    /// plumb_bob coefficients in the order `[k1, k2, p1, p2, k3]`. Tangential
    /// terms (`p1`, `p2`) are fixed at zero by the MVP fitter.
    let distortionCoefficients: [Double]

    /// Normalized-radius RMS of the fit (resolution-independent).
    let fitResidualRmsNormalized: Double

    /// Number of sample points used to build the linear system.
    let fitSamples: Int

    /// UNIX epoch milliseconds when the probe ran.
    let capturedAtEpochMs: Double

    // MARK: - Derived accessors

    /// Focal-length / principal-point at the probe's native reference.
    var probeFx: Double { intrinsicMatrixRowMajor[0] }
    var probeFy: Double { intrinsicMatrixRowMajor[4] }
    var probeCx: Double { intrinsicMatrixRowMajor[2] }
    var probeCy: Double { intrinsicMatrixRowMajor[5] }

    struct ScaledIntrinsics {
        let fx: Double
        let fy: Double
        let cx: Double
        let cy: Double
        /// RMS residual in pixels at the scaled resolution (proxy).
        let fitResidualRmsPx: Double
    }

    /// Scales the stored intrinsics to the caller's recording resolution.
    ///
    /// Handles the two common iOS cases:
    ///   - pure resample (probe and recording share aspect ratio),
    ///   - symmetric center-crop on the longer axis (e.g. probe 4:3 → record 16:9).
    func scaledIntrinsics(recordingWidth: Int, recordingHeight: Int) -> ScaledIntrinsics {
        let probeW = Double(probeWidth)
        let probeH = Double(probeHeight)
        let recW = Double(recordingWidth)
        let recH = Double(recordingHeight)
        guard probeW > 0, probeH > 0, recW > 0, recH > 0 else {
            return ScaledIntrinsics(fx: probeFx, fy: probeFy, cx: probeCx, cy: probeCy, fitResidualRmsPx: 0)
        }
        let sx = recW / probeW
        let sy = recH / probeH
        let s = min(sx, sy)
        let fxRec = probeFx * s
        let fyRec = probeFy * s
        let cropLeft = (probeW * s - recW) * 0.5
        let cropTop = (probeH * s - recH) * 0.5
        let cxRec = probeCx * s - cropLeft
        let cyRec = probeCy * s - cropTop
        // Proxy for pixel-space residual at the scaled resolution.
        let meanFocal = 0.5 * (probeFx + probeFy)
        let rmsPxRec = fitResidualRmsNormalized * meanFocal * s
        return ScaledIntrinsics(fx: fxRec, fy: fyRec, cx: cxRec, cy: cyRec, fitResidualRmsPx: rmsPxRec)
    }

    // MARK: - Cache access

    private static let userDefaultsPrefix = "kgeneye.lensDistortion.v2"

    static func cacheKey(deviceIdentifier: String) -> String {
        "\(userDefaultsPrefix).\(deviceIdentifier)"
    }

    static func load(
        deviceIdentifier: String,
        defaults: UserDefaults = .standard
    ) -> LensDistortionCalibration? {
        let key = cacheKey(deviceIdentifier: deviceIdentifier)
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            let decoded = try JSONDecoder().decode(LensDistortionCalibration.self, from: data)
            guard decoded.schemaVersion == LensDistortionCalibration.schemaVersion else {
                defaults.removeObject(forKey: key)
                return nil
            }
            return decoded
        } catch {
            defaults.removeObject(forKey: key)
            return nil
        }
    }

    func save(defaults: UserDefaults = .standard) {
        let key = LensDistortionCalibration.cacheKey(deviceIdentifier: deviceIdentifier)
        do {
            let data = try JSONEncoder().encode(self)
            defaults.set(data, forKey: key)
        } catch {
            print("[LensDistortionCalibration] failed to persist: \(error)")
        }
    }

    static func clearAll(defaults: UserDefaults = .standard) {
        // v1 + v2 keys, in case older records linger.
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("kgeneye.lensDistortion.") {
            defaults.removeObject(forKey: key)
        }
    }
}
