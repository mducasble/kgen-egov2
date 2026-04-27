public enum Orientation: String, Codable, Equatable {
    case portrait
    case landscape
    case any
}

public struct QCThresholds: Equatable {
    public let minDurationMs: Int
    public let maxDurationMs: Int
    public let requiredOrientation: Orientation
    public let minHandPresenceRate: Double
    public let maxFacePresenceRate: Double
    public let minReadinessScore: Double
    public let warnReadinessScore: Double
    public let minStabilityScore: Double
    public let minBrightnessScore: Double
    public let minBlurScore: Double

    public init(
        minDurationMs: Int = 5_000,
        maxDurationMs: Int = 600_000,
        requiredOrientation: Orientation = .landscape,
        minHandPresenceRate: Double = 0.6,
        maxFacePresenceRate: Double = 0.15,
        minReadinessScore: Double = 65,
        warnReadinessScore: Double = 85,
        minStabilityScore: Double = 40,
        minBrightnessScore: Double = 35,
        minBlurScore: Double = 40
    ) {
        self.minDurationMs = minDurationMs
        self.maxDurationMs = maxDurationMs
        self.requiredOrientation = requiredOrientation
        self.minHandPresenceRate = minHandPresenceRate
        self.maxFacePresenceRate = maxFacePresenceRate
        self.minReadinessScore = minReadinessScore
        self.warnReadinessScore = warnReadinessScore
        self.minStabilityScore = minStabilityScore
        self.minBrightnessScore = minBrightnessScore
        self.minBlurScore = minBlurScore
    }

    public static let `default` = QCThresholds()
}
