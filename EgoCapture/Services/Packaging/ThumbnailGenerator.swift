import AVFoundation
import UIKit

/// Extracts the first frame of a session's `video_{code}.mp4` and caches it as
/// `thumbnail_{code}.jpg` inside the session directory. The Sessions screen
/// reads the cached file synchronously — it falls back to a gradient
/// placeholder while the async generation completes (or when the video file
/// is missing / still uploading).
///
/// The generator always writes 128×128 JPEGs (~10–20 KB) via aspect-fill
/// cropping, which keeps the per-session disk cost negligible compared to
/// the original video.
enum ThumbnailGenerator {

    /// Canonical location of the cached JPEG for a given session directory.
    static func cacheURL(in sessionDir: URL) -> URL {
        SessionFiles.url("thumbnail", "jpg", in: sessionDir)
    }

    /// Return the cached thumbnail synchronously if it's already on disk.
    /// Callers use this for the first render, then fire `generateIfNeeded`
    /// to backfill when it returns `nil`.
    static func cachedImage(in sessionDir: URL) -> UIImage? {
        let url = cacheURL(in: sessionDir)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else { return nil }
        return image
    }

    /// Generate the thumbnail for `sessionDir` if it isn't cached yet. Safe to
    /// call repeatedly — subsequent calls short-circuit on the disk cache.
    /// Returns `nil` when the source video is missing or AVFoundation fails
    /// to decode the first sample.
    @discardableResult
    static func generateIfNeeded(in sessionDir: URL) async -> UIImage? {
        if let cached = cachedImage(in: sessionDir) { return cached }

        guard let videoURL = SessionFiles.resolveExisting("video", "mp4", in: sessionDir) else {
            return nil
        }

        return await extract(from: videoURL, cachingAt: cacheURL(in: sessionDir))
    }

    // MARK: - Private

    private static func extract(from videoURL: URL, cachingAt cacheURL: URL) async -> UIImage? {
        let asset = AVURLAsset(
            url: videoURL,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]
        )

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        // Give AVFoundation room to pick the closest keyframe without
        // re-decoding hundreds of frames — we only need a ballpark "first frame".
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.25, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter  = CMTime(seconds: 0.25, preferredTimescale: 600)
        generator.maximumSize = CGSize(width: 256, height: 256)

        // 100 ms into the clip avoids the occasional green / black first frame
        // some encoders emit when the IDR is being assembled.
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)

        let cgImage: CGImage?
        if #available(iOS 16.0, *) {
            cgImage = try? await generator.image(at: time).image
        } else {
            cgImage = try? generator.copyCGImage(at: time, actualTime: nil)
        }

        guard let cg = cgImage else { return nil }

        let rendered = aspectFillResize(
            UIImage(cgImage: cg),
            to: CGSize(width: 128, height: 128)
        )

        if let data = rendered.jpegData(compressionQuality: 0.8) {
            try? data.write(to: cacheURL, options: .atomic)
        }

        return rendered
    }

    /// Center-crop + scale to fit `size` exactly (aspect-fill). Avoids the
    /// letter-boxing that `scaledToFit` would introduce on 16:9 / 4:3 frames.
    private static func aspectFillResize(_ image: UIImage, to size: CGSize) -> UIImage {
        let srcW = image.size.width
        let srcH = image.size.height
        guard srcW > 0, srcH > 0 else { return image }

        let scale = max(size.width / srcW, size.height / srcH)
        let targetW = srcW * scale
        let targetH = srcH * scale
        let origin = CGPoint(
            x: (size.width - targetW) / 2,
            y: (size.height - targetH) / 2
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: origin, size: CGSize(width: targetW, height: targetH)))
        }
    }
}
