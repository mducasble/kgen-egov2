import Foundation
import CoreVideo

/// Lightweight struct describing a frame to be processed by ML inference.
struct ProcessingFrame {
    let pixelBuffer: CVPixelBuffer
    let frameIndex: Int
    let relativeMs: Double
    let timestampNs: UInt64
}

/// Time-based rate limiter for ML processing.
/// Determines whether a given frame should be submitted for inference
/// based on a target processing FPS (e.g. 12 fps out of 30 fps video).
final class ProcessingRateLimiter {
    let targetProcessingFPS: Double
    private let minIntervalNs: UInt64
    private var lastProcessedTimestampNs: UInt64 = 0
    private let lock = NSLock()

    init(targetProcessingFPS: Double = 12.0) {
        self.targetProcessingFPS = targetProcessingFPS
        self.minIntervalNs = UInt64(1_000_000_000.0 / targetProcessingFPS)
    }

    func shouldProcessFrame(timestampNs: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard timestampNs >= lastProcessedTimestampNs + minIntervalNs else { return false }
        lastProcessedTimestampNs = timestampNs
        return true
    }

    func reset() {
        lock.lock()
        lastProcessedTimestampNs = 0
        lock.unlock()
    }
}

/// Latest-frame-wins scheduler that prevents processing backlog.
///
/// At most one frame is being processed at any time.
/// If a new frame arrives while processing is active, it **replaces**
/// the previous pending frame (not appended to a growing queue).
/// This guarantees: backlog depth = 0 or 1, never deeper.
final class LatestFrameScheduler {
    typealias ProcessBlock = (ProcessingFrame) -> Void

    private let queue: DispatchQueue
    private let lock = NSLock()
    private var pendingFrame: ProcessingFrame?
    private var isProcessing = false

    private(set) var framesSubmitted: Int = 0
    private(set) var framesSkipped: Int = 0
    private(set) var framesProcessed: Int = 0

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    /// Submit a frame for processing. If the processor is busy, the frame
    /// replaces any previously queued frame (latest-frame-wins).
    /// `processBlock` runs on the scheduler's dispatch queue.
    func submit(_ frame: ProcessingFrame, processBlock: @escaping ProcessBlock) {
        lock.lock()
        framesSubmitted += 1
        if isProcessing {
            if pendingFrame != nil { framesSkipped += 1 }
            pendingFrame = frame
            lock.unlock()
            return
        }
        isProcessing = true
        lock.unlock()

        processNext(frame, processBlock: processBlock)
    }

    private func processNext(_ frame: ProcessingFrame, processBlock: @escaping ProcessBlock) {
        queue.async { [self] in
            processBlock(frame)

            lock.lock()
            framesProcessed += 1
            if let next = pendingFrame {
                pendingFrame = nil
                lock.unlock()
                processNext(next, processBlock: processBlock)
            } else {
                isProcessing = false
                lock.unlock()
            }
        }
    }

    func reset() {
        lock.lock()
        pendingFrame = nil
        isProcessing = false
        framesSubmitted = 0
        framesSkipped = 0
        framesProcessed = 0
        lock.unlock()
    }

    var stats: (submitted: Int, skipped: Int, processed: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (framesSubmitted, framesSkipped, framesProcessed)
    }
}

/// Holds the most recent valid hand tracking result for temporal reuse.
/// When a frame is skipped by the rate limiter, downstream consumers
/// can use the cached result instead of running inference.
final class CachedHandResult {
    private let lock = NSLock()
    private var cachedTimestampNs: UInt64 = 0
    private var _hasHands: Bool = false
    private var _reusedCount: Int = 0

    /// Maximum age (ns) before the cached result is considered stale.
    let maxAgeNs: UInt64

    init(maxAgeMs: Double = 200) {
        self.maxAgeNs = UInt64(maxAgeMs * 1_000_000)
    }

    func update(timestampNs: UInt64, hasHands: Bool) {
        lock.lock()
        cachedTimestampNs = timestampNs
        _hasHands = hasHands
        lock.unlock()
    }

    func isValid(at timestampNs: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard cachedTimestampNs > 0 else { return false }
        return timestampNs - cachedTimestampNs <= maxAgeNs
    }

    var hasHands: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _hasHands
    }

    var reusedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _reusedCount
    }

    func markReused() {
        lock.lock()
        _reusedCount += 1
        lock.unlock()
    }

    func reset() {
        lock.lock()
        cachedTimestampNs = 0
        _hasHands = false
        _reusedCount = 0
        lock.unlock()
    }
}
