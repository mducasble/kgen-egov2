public enum QCResult: String, Codable, Equatable {
    case passed
    case passedWithWarning = "passed_with_warning"
    case blocked
}

public struct LocalQCReport: Codable, Equatable {
    public let recordingId: String
    public let questId: String
    public let durationMs: Int
    public let resolutionWidth: Int
    public let resolutionHeight: Int
    public let fps: Int
    public let orientation: Orientation
    public let audioPresent: Bool
    public let fileSizeBytes: Int64
    public let fileIntegrityPassed: Bool
    public let sampledFrameCount: Int
    public let handPresenceRate: Double
    public let dualHandRate: Double
    public let facePresenceRate: Double
    public let averageHandArea: Double
    public let handCenteringScore: Double
    public let handContinuityScore: Double
    public let blurScore: Double
    public let brightnessScore: Double
    public let contrastScore: Double
    public let stabilityScore: Double
    public let readinessScore: Double
    public let qcResult: QCResult
    public let blockReasons: [String]
    public let warningReasons: [String]
    public let generatedAt: Int64

    public init(
        recordingId: String,
        questId: String,
        durationMs: Int,
        resolutionWidth: Int,
        resolutionHeight: Int,
        fps: Int,
        orientation: Orientation,
        audioPresent: Bool,
        fileSizeBytes: Int64,
        fileIntegrityPassed: Bool,
        sampledFrameCount: Int,
        handPresenceRate: Double,
        dualHandRate: Double,
        facePresenceRate: Double,
        averageHandArea: Double,
        handCenteringScore: Double,
        handContinuityScore: Double,
        blurScore: Double,
        brightnessScore: Double,
        contrastScore: Double,
        stabilityScore: Double,
        readinessScore: Double,
        qcResult: QCResult,
        blockReasons: [String],
        warningReasons: [String],
        generatedAt: Int64
    ) {
        self.recordingId = recordingId
        self.questId = questId
        self.durationMs = durationMs
        self.resolutionWidth = resolutionWidth
        self.resolutionHeight = resolutionHeight
        self.fps = fps
        self.orientation = orientation
        self.audioPresent = audioPresent
        self.fileSizeBytes = fileSizeBytes
        self.fileIntegrityPassed = fileIntegrityPassed
        self.sampledFrameCount = sampledFrameCount
        self.handPresenceRate = handPresenceRate
        self.dualHandRate = dualHandRate
        self.facePresenceRate = facePresenceRate
        self.averageHandArea = averageHandArea
        self.handCenteringScore = handCenteringScore
        self.handContinuityScore = handContinuityScore
        self.blurScore = blurScore
        self.brightnessScore = brightnessScore
        self.contrastScore = contrastScore
        self.stabilityScore = stabilityScore
        self.readinessScore = readinessScore
        self.qcResult = qcResult
        self.blockReasons = blockReasons
        self.warningReasons = warningReasons
        self.generatedAt = generatedAt
    }
}
