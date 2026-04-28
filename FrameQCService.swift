import Foundation
import CoreVideo
import Accelerate

/// Computes per-frame quality metrics: brightness and blur scores.
/// Also aggregates hand/face detection booleans from other services.
final class FrameQCService {
    
    private var writer: JSONLWriter?
    private var recordingStartEpochMs: Double = 0
    
    // Accumulators for QC summary
    private var brightnessValues: [Double] = []
    private var blurValues: [Double] = []
    private var handDetectedCount: Int = 0
    private var faceDetectedCount: Int = 0
    private var totalFrames: Int = 0
    
    func start(outputURL: URL, epochStartMs: Double) throws {
        writer = try JSONLWriter(fileURL: outputURL)
        recordingStartEpochMs = epochStartMs
        brightnessValues = []
        blurValues = []
        handDetectedCount = 0
        faceDetectedCount = 0
        totalFrames = 0
    }
    
    /// Process a frame and write QC metrics.
    func processFrame(
        pixelBuffer: CVPixelBuffer,
        frameIndex: Int,
        relativeMs: Double,
        handDetected: Bool,
        faceDetected: Bool
    ) {
        let epochMs = recordingStartEpochMs + relativeMs
        
        let brightness = normalizeBrightness(computeBrightness(pixelBuffer: pixelBuffer))
        let blur = normalizeBlur(computeBlurScore(pixelBuffer: pixelBuffer))
        
        let sample = FrameQCMetricsSample(
            timestampEpochMs: epochMs,
            relativeMs: relativeMs,
            frameIndex: frameIndex,
            brightnessScore: brightness,
            blurScore: blur,
            handDetected: handDetected,
            faceDetected: faceDetected
        )
        
        writer?.append(sample)
        
        // Accumulate for summary
        brightnessValues.append(brightness)
        blurValues.append(blur)
        if handDetected { handDetectedCount += 1 }
        if faceDetected { faceDetectedCount += 1 }
        totalFrames += 1
    }
    
    func stop() {
        writer?.close()
    }
    
    var rowCount: Int { writer?.rowCount ?? 0 }
    
    /// Compute aggregate QC summary after recording.
    func computeSummary() -> QCSummary {
        let n = Double(max(totalFrames, 1))
        
        let brightMean = brightnessValues.reduce(0, +) / n
        let brightStd = standardDeviation(brightnessValues, mean: brightMean)
        
        let blurMean = blurValues.reduce(0, +) / n
        let blurStd = standardDeviation(blurValues, mean: blurMean)
        
        let darkFrameRate = Double(brightnessValues.filter { $0 < 35.0 }.count) / n
        let blurryFrameRate = Double(blurValues.filter { $0 < 40.0 }.count) / n
        
        return QCSummary(
            totalFrames: totalFrames,
            handPresenceRate: Double(handDetectedCount) / n,
            facePresenceRate: Double(faceDetectedCount) / n,
            brightnessMean: brightMean,
            brightnessStdDev: brightStd,
            blurMean: blurMean,
            blurStdDev: blurStd,
            darkFrameRate: darkFrameRate,
            blurryFrameRate: blurryFrameRate
        )
    }
    
    // MARK: - Image Analysis
    
    /// Average luminance [0,1]. Handles both BGRA and YCbCr (420v/420f) pixel formats.
    private func computeBrightness(pixelBuffer: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        let sampleStride = 8
        var sum: Double = 0
        var count = 0
        
        if pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
           pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange {
            // YCbCr: Use the Y plane directly (luminance)
            guard let yPlane = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return 0 }
            let yBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            let yPtr = yPlane.assumingMemoryBound(to: UInt8.self)
            
            for y in Swift.stride(from: 0, to: height, by: sampleStride) {
                for x in Swift.stride(from: 0, to: width, by: sampleStride) {
                    let luma = Double(yPtr[y * yBytesPerRow + x])
                    sum += luma / 255.0
                    count += 1
                }
            }
        } else {
            // BGRA or other interleaved: compute luminance from RGB
            guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return 0 }
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let ptr = baseAddress.assumingMemoryBound(to: UInt8.self)
            
            for y in Swift.stride(from: 0, to: height, by: sampleStride) {
                for x in Swift.stride(from: 0, to: width, by: sampleStride) {
                    let offset = y * bytesPerRow + x * 4
                    let b = Double(ptr[offset])
                    let g = Double(ptr[offset + 1])
                    let r = Double(ptr[offset + 2])
                    sum += (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
                    count += 1
                }
            }
        }
        
        return count > 0 ? sum / Double(count) : 0
    }

    private func normalizeBrightness(_ value: Double) -> Double {
        min(100.0, max(0.0, pow(value, 1.0 / 2.2) * 100.0))
    }

    private func normalizeBlur(_ variance: Double) -> Double {
        min(100.0, max(10.0, (variance / 2500.0) * 100.0))
    }
    
    /// Blur score via Laplacian variance. Higher = sharper image.
    /// Downsamples to ~120x68 grayscale for performance. Handles YCbCr and BGRA.
    private func computeBlurScore(pixelBuffer: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        
        let ds = 16
        let dsW = width / ds
        let dsH = height / ds
        guard dsW > 2 && dsH > 2 else { return 0 }
        
        // Build downsampled grayscale array
        var gray = [Float](repeating: 0, count: dsW * dsH)
        
        if pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
           pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange {
            // Use Y plane directly
            guard let yPlane = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return 0 }
            let yBPR = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            let yPtr = yPlane.assumingMemoryBound(to: UInt8.self)
            
            for dy in 0..<dsH {
                for dx in 0..<dsW {
                    gray[dy * dsW + dx] = Float(yPtr[dy * ds * yBPR + dx * ds])
                }
            }
        } else {
            // BGRA
            guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return 0 }
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let ptr = baseAddress.assumingMemoryBound(to: UInt8.self)
            
            for dy in 0..<dsH {
                for dx in 0..<dsW {
                    let offset = dy * ds * bytesPerRow + dx * ds * 4
                    let b = Float(ptr[offset])
                    let g = Float(ptr[offset + 1])
                    let r = Float(ptr[offset + 2])
                    gray[dy * dsW + dx] = 0.299 * r + 0.587 * g + 0.114 * b
                }
            }
        }
        
        // Compute Laplacian variance
        // Laplacian kernel: [0,1,0; 1,-4,1; 0,1,0]
        var laplacianSum: Double = 0
        var laplacianSqSum: Double = 0
        var count = 0
        
        for y in 1..<(dsH - 1) {
            for x in 1..<(dsW - 1) {
                let center = gray[y * dsW + x]
                let top = gray[(y - 1) * dsW + x]
                let bottom = gray[(y + 1) * dsW + x]
                let left = gray[y * dsW + (x - 1)]
                let right = gray[y * dsW + (x + 1)]
                let lap = Double(top + bottom + left + right - 4 * center)
                laplacianSum += lap
                laplacianSqSum += lap * lap
                count += 1
            }
        }
        
        let n = Double(max(count, 1))
        let mean = laplacianSum / n
        let variance = (laplacianSqSum / n) - (mean * mean)
        
        return max(0, variance)
    }
    
    // MARK: - Stats Helpers
    
    private func standardDeviation(_ values: [Double], mean: Double) -> Double {
        guard values.count > 1 else { return 0 }
        let sumSq = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
        return sqrt(sumSq / Double(values.count - 1))
    }
}
