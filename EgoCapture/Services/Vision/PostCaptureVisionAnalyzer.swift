import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import UIKit

/// Runs hand, face and frame-quality analysis after the recording is fully
/// written. Keeping this post-capture avoids competing with the live camera
/// callback and AVAssetWriter path.
enum PostCaptureVisionAnalyzer {
    struct Result {
        let qcSummary: QCSummary?
        let handRows: Int
        let faceRows: Int
        let frameQcRows: Int
    }

    static func analyze(
        videoURL: URL,
        sessionDir: URL,
        recordingStartEpochMs: Double,
        videoTimestamps: [VideoTimestamp]
    ) async -> Result {
        await Task.detached(priority: .utility) {
            analyzeSync(
                videoURL: videoURL,
                sessionDir: sessionDir,
                recordingStartEpochMs: recordingStartEpochMs,
                videoTimestamps: videoTimestamps
            )
        }.value
    }

    private static func analyzeSync(
        videoURL: URL,
        sessionDir: URL,
        recordingStartEpochMs: Double,
        videoTimestamps: [VideoTimestamp]
    ) -> Result {
        let asset = AVURLAsset(url: videoURL)
        let durationSec = CMTimeGetSeconds(asset.duration)
        guard durationSec.isFinite, durationSec > 0 else {
            return Result(qcSummary: nil, handRows: 0, faceRows: 0, frameQcRows: 0)
        }

        let sampleCount = min(20, max(3, Int(durationSec.rounded(.down))))
        let interval = durationSec / Double(sampleCount)

        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 480, height: 480)
        imageGenerator.requestedTimeToleranceBefore = CMTime(seconds: 0.05, preferredTimescale: 600)
        imageGenerator.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)

        let handService = HandLandmarkService(backend: AppleVisionHandBackend())
        let faceService = FacePresenceService()
        let frameQCService = FrameQCService()

        do {
            try handService.start(
                outputURL: SessionFiles.url("hand_landmarks", "jsonl", in: sessionDir),
                epochStartMs: recordingStartEpochMs
            )
            try faceService.start(
                outputURL: SessionFiles.url("face_presence", "jsonl", in: sessionDir),
                epochStartMs: recordingStartEpochMs
            )
            try frameQCService.start(
                outputURL: SessionFiles.url("frame_qc_metrics", "jsonl", in: sessionDir),
                epochStartMs: recordingStartEpochMs
            )
        } catch {
            print("[PostCaptureVisionAnalyzer] failed to start writers: \(error)")
            return Result(qcSummary: nil, handRows: 0, faceRows: 0, frameQcRows: 0)
        }

        defer {
            handService.stop()
            faceService.stop()
            frameQCService.stop()
        }

        for index in 0..<sampleCount {
            let relativeSec = interval * (Double(index) + 0.5)
            let time = CMTime(seconds: relativeSec, preferredTimescale: 600)
            guard
                let cgImage = try? imageGenerator.copyCGImage(at: time, actualTime: nil),
                let pixelBuffer = makePixelBuffer(from: cgImage)
            else {
                continue
            }

            let relativeMs = relativeSec * 1000.0
            let timestampNs = nearestTimestampNs(relativeMs: relativeMs, videoTimestamps: videoTimestamps)
            handService.processFrame(
                pixelBuffer: pixelBuffer,
                frameIndex: index,
                relativeMs: relativeMs,
                timestampNs: timestampNs
            )
            faceService.processFrame(
                pixelBuffer: pixelBuffer,
                frameIndex: index,
                relativeMs: relativeMs
            )
            frameQCService.processFrame(
                pixelBuffer: pixelBuffer,
                frameIndex: index,
                relativeMs: relativeMs,
                handDetected: !(handService.lastResult?.hands.isEmpty ?? true),
                faceDetected: faceService.lastFaceDetected
            )
        }

        return Result(
            qcSummary: frameQCService.rowCount > 0 ? frameQCService.computeSummary() : nil,
            handRows: handService.rowCount,
            faceRows: faceService.rowCount,
            frameQcRows: frameQCService.rowCount
        )
    }

    private static func nearestTimestampNs(relativeMs: Double, videoTimestamps: [VideoTimestamp]) -> UInt64 {
        guard !videoTimestamps.isEmpty else { return 0 }
        return videoTimestamps.min {
            abs($0.relativeMs - relativeMs) < abs($1.relativeMs - relativeMs)
        }?.timestampNs ?? 0
    }

    private static func makePixelBuffer(from image: CGImage) -> CVPixelBuffer? {
        let width = image.width
        let height = image.height
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixelBuffer
    }
}
