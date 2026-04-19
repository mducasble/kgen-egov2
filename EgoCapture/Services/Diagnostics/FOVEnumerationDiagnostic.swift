import Foundation
import AVFoundation
import CoreMedia
import UIKit

/// One-shot enumeration of every back-facing capture device + format, including
/// virtual (multi-camera) composites, for the purpose of answering the question
/// "what is the highest diagonal FOV this iPhone can deliver in video mode?".
///
/// Pure inspection: does not touch the recording pipeline, does not start
/// `AVCaptureSession`, and can be called at any time on the main thread.
enum FOVEnumerationDiagnostic {

    /// Runs the enumeration, writes a JSON artifact to `Documents/FOVDiagnostics/`,
    /// and returns the file URL. The URL is suitable for a `UIActivityViewController`
    /// share sheet or for out-of-band uploads.
    @discardableResult
    static func runAndSave() throws -> URL {
        let payload = build()
        let dir = try diagnosticsDirectory()
        let filename = "fov_enumeration_\(UIDevice.current.model.replacingOccurrences(of: " ", with: "_"))_\(timestampSuffix()).json"
        let url = dir.appendingPathComponent(filename)
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: url, options: .atomic)
        logSummary(payload: payload, fileURL: url)
        return url
    }

    // MARK: - Payload builder

    /// Builds the full enumeration payload as a JSON-serializable dictionary.
    /// Runs synchronously — enumeration is cheap (a few ms).
    static func build() -> [String: Any] {
        let virtualTypes: [AVCaptureDevice.DeviceType] = [
            .builtInDualWideCamera,
            .builtInTripleCamera,
            .builtInDualCamera
        ]
        let physicalTypes: [AVCaptureDevice.DeviceType] = [
            .builtInUltraWideCamera,
            .builtInWideAngleCamera
        ]
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: virtualTypes + physicalTypes,
            mediaType: .video,
            position: .back
        )

        var deviceEntries: [[String: Any]] = []
        var maxDFov: Double = 0
        var maxDFovRecord: [String: Any]? = nil

        for device in discovery.devices {
            var formatEntries: [[String: Any]] = []
            for format in device.formats {
                let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                let maxFPS = format.videoSupportedFrameRateRanges.map { $0.maxFrameRate }.max() ?? 0
                guard maxFPS >= 30, dims.width > 0, dims.height > 0 else { continue }

                let hFov = Double(format.videoFieldOfView)
                let gdcFov = Double(format.geometricDistortionCorrectedVideoFieldOfView)
                let dFov = diagonalFov(horizontalDeg: hFov, width: Int(dims.width), height: Int(dims.height))
                let aspectNumeric = Double(dims.width) / Double(dims.height)
                let fpsRanges = format.videoSupportedFrameRateRanges.map {
                    ["min": $0.minFrameRate, "max": $0.maxFrameRate]
                }

                let entry: [String: Any] = [
                    "width": Int(dims.width),
                    "height": Int(dims.height),
                    "aspectRatio": String(format: "%.3f", aspectNumeric),
                    "horizontalFovDeg": hFov,
                    "geometricDistortionCorrectedFovDeg": gdcFov,
                    "gdcReducesFov": gdcFov > 0 && gdcFov < hFov - 0.01,
                    "diagonalFovDeg": dFov,
                    "fpsRanges": fpsRanges
                ]
                formatEntries.append(entry)

                if dFov > maxDFov {
                    maxDFov = dFov
                    maxDFovRecord = [
                        "deviceType": device.deviceType.rawValue,
                        "deviceLocalizedName": device.localizedName,
                        "width": Int(dims.width),
                        "height": Int(dims.height),
                        "horizontalFovDeg": hFov,
                        "diagonalFovDeg": dFov
                    ]
                }
            }

            formatEntries.sort { lhs, rhs in
                let ld = (lhs["diagonalFovDeg"] as? Double) ?? 0
                let rd = (rhs["diagonalFovDeg"] as? Double) ?? 0
                return ld > rd
            }

            var deviceInfo: [String: Any] = [
                "deviceType": device.deviceType.rawValue,
                "localizedName": device.localizedName,
                "isVirtualDevice": device.isVirtualDevice,
                "gdcSupported": device.isGeometricDistortionCorrectionSupported,
                "gdcEnabled": device.isGeometricDistortionCorrectionEnabled,
                "formats30fpsPlus": formatEntries,
                "formatCount": formatEntries.count
            ]
            if device.isVirtualDevice {
                deviceInfo["constituentDevices"] = device.constituentDevices.map {
                    [
                        "deviceType": $0.deviceType.rawValue,
                        "localizedName": $0.localizedName
                    ]
                }
            }
            deviceEntries.append(deviceInfo)
        }

        var payload: [String: Any] = [
            "schema": "kgeneye.fov_enumeration.v1",
            "capturedAtEpochMs": Date().timeIntervalSince1970 * 1000.0,
            "deviceModel": UIDevice.current.model,
            "systemName": UIDevice.current.systemName,
            "systemVersion": UIDevice.current.systemVersion,
            "idfvIdentifier": UIDevice.current.identifierForVendor?.uuidString ?? "unknown",
            "summary": [
                "backDeviceCount": deviceEntries.count,
                "maxDiagonalFovDeg": maxDFov,
                "specMinimumDiagonalFovDeg": 120.0,
                "meetsSpecMinimum": maxDFov >= 120.0,
                "maxDiagonalFovFormat": maxDFovRecord as Any
            ],
            "devices": deviceEntries
        ]

        // Strip NSNull that `as Any` may introduce when the record is missing.
        if maxDFovRecord == nil {
            var summary = payload["summary"] as! [String: Any]
            summary.removeValue(forKey: "maxDiagonalFovFormat")
            payload["summary"] = summary
        }

        return payload
    }

    // MARK: - Helpers

    private static func diagonalFov(horizontalDeg: Double, width: Int, height: Int) -> Double {
        guard horizontalDeg > 0, width > 0, height > 0 else { return 0 }
        let hRad = horizontalDeg * .pi / 180.0
        let aspect = Double(height) / Double(width)
        let diag = 2.0 * atan(sqrt(1.0 + aspect * aspect) * tan(hRad / 2.0))
        return diag * 180.0 / .pi
    }

    private static func diagnosticsDirectory() throws -> URL {
        let fm = FileManager.default
        let docs = try fm.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = docs.appendingPathComponent("FOVDiagnostics", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func timestampSuffix() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: Date()) + "Z"
    }

    private static func logSummary(payload: [String: Any], fileURL: URL) {
        let summary = payload["summary"] as? [String: Any] ?? [:]
        let devices = payload["devices"] as? [[String: Any]] ?? []
        let maxD = (summary["maxDiagonalFovDeg"] as? Double) ?? 0
        let meets = (summary["meetsSpecMinimum"] as? Bool) ?? false
        print("[FOVDiagnostic] === FOV ENUMERATION ===")
        print("[FOVDiagnostic] Back devices: \(devices.count)")
        for d in devices {
            let type = d["deviceType"] as? String ?? "?"
            let virtual = (d["isVirtualDevice"] as? Bool) == true ? "virtual" : "physical"
            let count = d["formatCount"] as? Int ?? 0
            let top = (d["formats30fpsPlus"] as? [[String: Any]])?.first
            let topFov = (top?["diagonalFovDeg"] as? Double) ?? 0
            let topW = top?["width"] as? Int ?? 0
            let topH = top?["height"] as? Int ?? 0
            print("[FOVDiagnostic]   \(type) (\(virtual)) — \(count) fmts, top=\(topW)x\(topH) dFov=\(String(format: "%.1f°", topFov))")
        }
        print("[FOVDiagnostic] maxDiagonalFovDeg=\(String(format: "%.2f°", maxD)) | meetsSpec120=\(meets)")
        print("[FOVDiagnostic] Saved: \(fileURL.path)")
    }
}
