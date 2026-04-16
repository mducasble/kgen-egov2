import Foundation
import Darwin

/// Provides monotonic nanosecond timestamps from mach_absolute_time.
/// All sensors MUST use this single instance to ensure the same time base.
///
/// mach_absolute_time is the highest-precision monotonic clock on iOS.
/// It does not jump on NTP sync or timezone changes.
///
/// This utility also provides conversion to epoch time (for logging/human reference)
/// by capturing the epoch↔mach offset at initialization.
final class MonotonicClock {
    
    /// Shared instance — all services must use this for timestamp consistency.
    static let shared = MonotonicClock()
    
    /// Timebase info for converting mach ticks to nanoseconds
    private let timebaseInfo: mach_timebase_info_data_t
    
    /// mach_absolute_time captured at init
    private let referenceMonotonicNs: UInt64
    /// Epoch time captured at init (ms)
    private let referenceEpochMs: Double
    
    private init() {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        self.timebaseInfo = info
        
        // Capture reference point: mach time ↔ epoch time
        // These are captured as close together as possible to minimize offset error.
        let machNow = mach_absolute_time()
        let epochNow = Date().timeIntervalSince1970 * 1000.0
        
        self.referenceMonotonicNs = Self.machToNanoseconds(machNow, info: info)
        self.referenceEpochMs = epochNow
    }
    
    /// Current monotonic timestamp in nanoseconds.
    func nowNs() -> UInt64 {
        return Self.machToNanoseconds(mach_absolute_time(), info: timebaseInfo)
    }
    
    /// Convert a monotonic nanosecond timestamp to epoch milliseconds.
    /// Precision: ~1ms (limited by the epoch↔mach reference capture).
    func toEpochMs(_ monotonicNs: UInt64) -> Double {
        let deltaNs = Int64(monotonicNs) - Int64(referenceMonotonicNs)
        let deltaMs = Double(deltaNs) / 1_000_000.0
        return referenceEpochMs + deltaMs
    }
    
    /// Convert a monotonic nanosecond timestamp to relative milliseconds from a start point.
    func toRelativeMs(_ monotonicNs: UInt64, from startNs: UInt64) -> Double {
        let deltaNs = Int64(monotonicNs) - Int64(startNs)
        return Double(deltaNs) / 1_000_000.0
    }
    
    /// Convert mach_absolute_time ticks to nanoseconds.
    private static func machToNanoseconds(_ machTime: UInt64, info: mach_timebase_info_data_t) -> UInt64 {
        return machTime * UInt64(info.numer) / UInt64(info.denom)
    }
    
    /// Convert an ARKit frame timestamp (boot-relative seconds) to our monotonic nanoseconds.
    /// ARKit timestamps use CACurrentMediaTime() which is mach_absolute_time based.
    func fromARKitTimestamp(_ arTimestamp: TimeInterval) -> UInt64 {
        return UInt64(arTimestamp * 1_000_000_000)
    }
    
    /// Convert a CoreMotion timestamp (boot-relative seconds) to our monotonic nanoseconds.
    /// CoreMotion timestamps also use the mach time base.
    func fromCoreMotionTimestamp(_ cmTimestamp: TimeInterval) -> UInt64 {
        return UInt64(cmTimestamp * 1_000_000_000)
    }
}
