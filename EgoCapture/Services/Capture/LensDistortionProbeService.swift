import Foundation
import AVFoundation
import UIKit
import simd

/// One-shot probe that opens a virtual multi-camera session
/// (`BuiltInDualWideCamera` by preference, `BuiltInTripleCamera` as a
/// fallback), captures a single still photo to harvest
/// `AVCameraCalibrationData`, fits a plumb_bob radial model via
/// `PlumbBobFitter`, scales the intrinsics to the recording resolution and
/// persists the result to `UserDefaults`.
///
/// The probe is opportunistic: on any failure (device missing, delivery
/// unsupported, timeout, fit singular) `ensureCalibration` returns `nil` and
/// the caller should fall back to the existing behaviour (no coefficients).
final class LensDistortionProbeService: NSObject {

    // MARK: - Public top-level API

    /// Returns a device-scoped calibration (resolution-agnostic), running a
    /// probe once on first call. All failure paths return `nil` and the caller
    /// should keep the pipeline running without plumb_bob coefficients.
    ///
    /// **Must be called before the recording `AVCaptureSession` adds its input**
    /// — the probe opens the virtual multi-camera device, which shares its
    /// ultra-wide constituent with the recording path; a second input on that
    /// hardware blocks calibration delivery at the OS level.
    ///
    /// Uses a negative cache: once a device has been determined to not expose
    /// calibration delivery via the public `AVCapturePhotoOutput` API, we skip
    /// the probe entirely on subsequent sessions to avoid the ~200 ms AV session
    /// setup/teardown cost.
    static func ensureCalibration() async -> LensDistortionCalibration? {
        let deviceId = Self.deviceIdentifier()
        if let cached = LensDistortionCalibration.load(deviceIdentifier: deviceId) {
            return cached
        }
        if isMarkedUnsupported(deviceId: deviceId) {
            return nil
        }

        let service = LensDistortionProbeService()
        do {
            let probe = try await service.probe()
            guard let calibration = Self.buildCalibration(probe: probe, deviceId: deviceId) else {
                print("[LensDistortionProbe] probe succeeded but calibration build failed; marking device unsupported")
                markUnsupported(deviceId: deviceId, reason: "buildFailed")
                return nil
            }
            calibration.save()
            print("[LensDistortionProbe] ✓ cached calibration for \(deviceId)")
            return calibration
        } catch {
            print("[LensDistortionProbe] probe failed: \(error) — marking device unsupported")
            markUnsupported(deviceId: deviceId, reason: String(describing: error))
            return nil
        }
    }

    /// Wipes both positive and negative caches. Call when the capture pipeline
    /// changes in a way that could invalidate previously-fit coefficients, or
    /// to force a re-probe (e.g. after iOS upgrade).
    static func clearCache() {
        LensDistortionCalibration.clearAll()
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(negativeCachePrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Negative cache (devices that don't expose calibration)

    private static let negativeCachePrefix = "kgeneye.lensDistortion.unsupported.v2."

    private static func negativeCacheKey(deviceId: String) -> String {
        "\(negativeCachePrefix)\(deviceId)"
    }

    private static func isMarkedUnsupported(deviceId: String) -> Bool {
        UserDefaults.standard.object(forKey: negativeCacheKey(deviceId: deviceId)) != nil
    }

    private static func markUnsupported(deviceId: String, reason: String) {
        let payload: [String: Any] = [
            "reason": reason,
            "markedAtEpochMs": Date().timeIntervalSince1970 * 1000.0
        ]
        UserDefaults.standard.set(payload, forKey: negativeCacheKey(deviceId: deviceId))
    }

    /// Public so Settings UI can expose hardware model without duplicating code.
    static func deviceIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let chars: [CChar] = mirror.children.compactMap { $0.value as? CChar }
        let raw = String(cString: chars + [0])
        return raw.isEmpty ? UIDevice.current.model : raw
    }

    // MARK: - Probe types

    struct ProbeResult {
        let intrinsicMatrix: matrix_float3x3
        let referenceDimensions: CGSize
        let distortionCenter: CGPoint
        let lookupTable: Data
        let inverseLookupTable: Data
        let sourceDeviceType: String
    }

    enum ProbeError: Error {
        case noVirtualDevice
        case calibrationDeliveryUnsupported
        case authorizationDenied
        case sessionSetupFailed(String)
        case captureFailed(String)
        case missingCalibrationData
        case timeout
    }

    // MARK: - Probe implementation

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var continuation: CheckedContinuation<ProbeResult, Error>?
    private let probeQueue = DispatchQueue(label: "kgeneye.lensProbe", qos: .userInitiated)

    /// Runs the probe and returns the raw calibration data. Caller is
    /// responsible for converting / caching.
    func probe() async throws -> ProbeResult {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else { throw ProbeError.authorizationDenied }
        default:
            throw ProbeError.authorizationDenied
        }

        guard let device = Self.bestVirtualDevice() else {
            throw ProbeError.noVirtualDevice
        }

        let uwConstituent = device.constituentDevices.first(where: {
            $0.deviceType == .builtInUltraWideCamera
        })

        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            probeQueue.async { [weak self] in
                guard let self else { return }
                do {
                    try self.configureSession(for: device)
                } catch {
                    self.finish(.failure(error))
                    return
                }
                self.session.startRunning()

                // At this point the session has been committed, so the output's
                // support flags reflect the final connection state. Now decide
                // whether we can actually request calibration data.
                guard self.photoOutput.isCameraCalibrationDataDeliverySupported else {
                    self.finish(.failure(ProbeError.calibrationDeliveryUnsupported))
                    return
                }
                let settings = AVCapturePhotoSettings()
                settings.isCameraCalibrationDataDeliveryEnabled = true

                // On iOS versions where plain calibration delivery isn't
                // exposed on virtual devices, Apple routes it through the
                // constituent-photo-delivery path. We restrict delivery to
                // the ultra-wide constituent so we get exactly one photo
                // (with UW calibration) instead of one-per-constituent.
                if self.photoOutput.isVirtualDeviceConstituentPhotoDeliveryEnabled,
                   let uw = uwConstituent {
                    settings.virtualDeviceConstituentPhotoDeliveryEnabledDevices = [uw]
                }

                // Safety net: if the delegate never fires within 5s, abort.
                self.probeQueue.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                    self?.finish(.failure(ProbeError.timeout))
                }
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    private func configureSession(for device: AVCaptureDevice) throws {
        session.beginConfiguration()

        session.sessionPreset = .photo

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            session.commitConfiguration()
            throw ProbeError.sessionSetupFailed("deviceInput: \(error.localizedDescription)")
        }
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw ProbeError.sessionSetupFailed("cannot add device input")
        }
        session.addInput(input)

        guard session.canAddOutput(photoOutput) else {
            session.commitConfiguration()
            throw ProbeError.sessionSetupFailed("cannot add photo output")
        }
        session.addOutput(photoOutput)

        // On modern iOS (26+), calibration data for virtual multi-camera
        // devices is only surfaced through the constituent-photo-delivery
        // pipeline. Enabling the toggle before commit is what flips
        // `isCameraCalibrationDataDeliverySupported` to true.
        if photoOutput.isVirtualDeviceConstituentPhotoDeliverySupported {
            photoOutput.isVirtualDeviceConstituentPhotoDeliveryEnabled = true
        }

        session.commitConfiguration()

        print("[LensDistortionProbe] post-commit: calibrationSupported=\(photoOutput.isCameraCalibrationDataDeliverySupported) virtualConstituentEnabled=\(photoOutput.isVirtualDeviceConstituentPhotoDeliveryEnabled) device=\(device.deviceType.rawValue) constituents=\(device.constituentDevices.map { $0.deviceType.rawValue })")

        // Pick a video zoom factor that biases the virtual device to the
        // ultra-wide constituent (zoom factor 1.0 is the UW on DualWide/Triple).
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = 1.0
            device.unlockForConfiguration()
        } catch {
            // Non-fatal — we continue with the default zoom.
            print("[LensDistortionProbe] zoom lock failed: \(error)")
        }
    }

    private func finish(_ result: Result<ProbeResult, Error>) {
        // Guard against multiple invocations (e.g. photo success after timeout).
        guard let cont = continuation else { return }
        continuation = nil
        if session.isRunning { session.stopRunning() }
        switch result {
        case .success(let r): cont.resume(returning: r)
        case .failure(let e): cont.resume(throwing: e)
        }
    }

    // MARK: - Virtual device selection

    private static func bestVirtualDevice() -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = [
            .builtInDualWideCamera,
            .builtInTripleCamera
        ]
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: types,
            mediaType: .video,
            position: .back
        )
        // Prefer the device that actually exposes an ultra-wide constituent.
        return discovery.devices.first { device in
            device.constituentDevices.contains { $0.deviceType == .builtInUltraWideCamera }
        } ?? discovery.devices.first
    }

    // MARK: - Calibration build (fit only; scaling is deferred)

    private static func buildCalibration(
        probe: ProbeResult,
        deviceId: String
    ) -> LensDistortionCalibration? {
        let probeW = Double(probe.referenceDimensions.width)
        let probeH = Double(probe.referenceDimensions.height)
        guard probeW > 0, probeH > 0 else { return nil }

        let fit: PlumbBobFitter.FitResult
        do {
            fit = try PlumbBobFitter.fit(.init(
                inverseLookupTable: probe.inverseLookupTable,
                intrinsicMatrix: probe.intrinsicMatrix,
                intrinsicReferenceDimensions: probe.referenceDimensions,
                lensDistortionCenter: probe.distortionCenter
            ))
        } catch {
            print("[LensDistortionProbe] fit failed: \(error)")
            return nil
        }

        let m = probe.intrinsicMatrix
        let kRowMajor: [Double] = [
            Double(m.columns.0.x), Double(m.columns.1.x), Double(m.columns.2.x),
            Double(m.columns.0.y), Double(m.columns.1.y), Double(m.columns.2.y),
            Double(m.columns.0.z), Double(m.columns.1.z), Double(m.columns.2.z)
        ]

        print(String(
            format: "[LensDistortionProbe] fit: k1=%.6f k2=%.6f k3=%.6f rmsNorm=%.5f samples=%d (probe %dx%d, K at probe ref: fx=%.2f fy=%.2f cx=%.2f cy=%.2f)",
            fit.k1, fit.k2, fit.k3, fit.residualRmsNormalized, fit.samples,
            Int(probeW), Int(probeH),
            kRowMajor[0], kRowMajor[4], kRowMajor[2], kRowMajor[5]
        ))

        return LensDistortionCalibration(
            schemaVersion: LensDistortionCalibration.schemaVersion,
            deviceIdentifier: deviceId,
            probeWidth: Int(probeW),
            probeHeight: Int(probeH),
            intrinsicMatrixRowMajor: kRowMajor,
            distortionCenterX: Double(probe.distortionCenter.x),
            distortionCenterY: Double(probe.distortionCenter.y),
            distortionCoefficients: fit.coefficients,
            fitResidualRmsNormalized: fit.residualRmsNormalized,
            fitSamples: fit.samples,
            capturedAtEpochMs: Date().timeIntervalSince1970 * 1000.0
        )
    }
}

// MARK: - Photo delegate

extension LensDistortionProbeService: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            finish(.failure(ProbeError.captureFailed(error.localizedDescription)))
            return
        }
        guard let cal = photo.cameraCalibrationData else {
            finish(.failure(ProbeError.missingCalibrationData))
            return
        }
        let result = ProbeResult(
            intrinsicMatrix: cal.intrinsicMatrix,
            referenceDimensions: cal.intrinsicMatrixReferenceDimensions,
            distortionCenter: cal.lensDistortionCenter,
            lookupTable: cal.lensDistortionLookupTable ?? Data(),
            inverseLookupTable: cal.inverseLensDistortionLookupTable ?? Data(),
            sourceDeviceType: (output.connections.first?.inputPorts.first?.sourceDeviceType?.rawValue) ?? "unknown"
        )
        if result.inverseLookupTable.isEmpty {
            finish(.failure(ProbeError.missingCalibrationData))
            return
        }
        finish(.success(result))
    }
}
