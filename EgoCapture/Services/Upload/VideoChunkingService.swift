import Foundation
import AVFoundation

/// Splits a video file into ≤2-minute H.264 MP4 segments via re-muxing (no re-encode).
enum VideoChunkingService {

    struct ChunkInfo: Codable {
        let filename: String
        let index: Int
        let startTimeSec: Double
        let endTimeSec: Double
        let durationSec: Double
        let sizeBytes: Int64
    }

    struct ChunkManifest: Codable {
        let originalFilename: String
        let totalDurationSec: Double
        let chunkDurationLimitSec: Double
        let totalChunks: Int
        let chunks: [ChunkInfo]
    }

    static let chunkDurationSec: Double = 120.0

    /// Splits `videoURL` into chunks and writes them + a manifest into `outputDir`.
    /// Returns the manifest. If the video is ≤2min, produces a single chunk.
    static func chunkVideo(at videoURL: URL, outputDir: URL) async throws -> ChunkManifest {
        let asset = AVURLAsset(url: videoURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let duration = try await asset.load(.duration)
        let totalSec = CMTimeGetSeconds(duration)

        guard totalSec > 0 else {
            throw ChunkError.invalidDuration
        }

        let chunkCount = max(1, Int(ceil(totalSec / chunkDurationSec)))
        var chunks: [ChunkInfo] = []

        for i in 0..<chunkCount {
            let startSec = Double(i) * chunkDurationSec
            let endSec = min(startSec + chunkDurationSec, totalSec)
            let filename = String(format: "chunk_%03d.mp4", i + 1)
            let chunkURL = outputDir.appendingPathComponent(filename)

            try? FileManager.default.removeItem(at: chunkURL)

            let startTime = CMTime(seconds: startSec, preferredTimescale: 600)
            let endTime = CMTime(seconds: endSec, preferredTimescale: 600)
            let timeRange = CMTimeRange(start: startTime, end: endTime)

            guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
                throw ChunkError.exportSessionFailed
            }

            exportSession.outputURL = chunkURL
            exportSession.outputFileType = .mp4
            exportSession.timeRange = timeRange

            await exportSession.export()

            guard exportSession.status == .completed else {
                throw ChunkError.exportFailed(exportSession.error?.localizedDescription ?? "unknown")
            }

            let attrs = try FileManager.default.attributesOfItem(atPath: chunkURL.path)
            let size = attrs[.size] as? Int64 ?? 0

            chunks.append(ChunkInfo(
                filename: filename,
                index: i,
                startTimeSec: startSec,
                endTimeSec: endSec,
                durationSec: endSec - startSec,
                sizeBytes: size
            ))
        }

        let manifest = ChunkManifest(
            originalFilename: videoURL.lastPathComponent,
            totalDurationSec: totalSec,
            chunkDurationLimitSec: chunkDurationSec,
            totalChunks: chunks.count,
            chunks: chunks
        )

        let manifestURL = outputDir.appendingPathComponent("chunk_manifest.json")
        let data = try JSONEncoder.prettyEncoder.encode(manifest)
        try data.write(to: manifestURL)

        return manifest
    }

    enum ChunkError: Error, LocalizedError {
        case invalidDuration
        case exportSessionFailed
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidDuration: return "Video has invalid or zero duration"
            case .exportSessionFailed: return "Could not create export session"
            case .exportFailed(let msg): return "Export failed: \(msg)"
            }
        }
    }
}

private extension JSONEncoder {
    static let prettyEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}
