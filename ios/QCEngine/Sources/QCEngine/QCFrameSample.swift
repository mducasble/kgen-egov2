public struct BoundingBox: Codable, Equatable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct Landmark: Codable, Equatable {
    public let x: Double
    public let y: Double
    public let z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

public struct DetectedHand: Codable, Equatable {
    public let handedness: String
    public let confidence: Double
    public let landmarks: [Landmark]
    public let boundingBox: BoundingBox

    public init(handedness: String, confidence: Double, landmarks: [Landmark], boundingBox: BoundingBox) {
        self.handedness = handedness
        self.confidence = confidence
        self.landmarks = landmarks
        self.boundingBox = boundingBox
    }
}

public struct QCFrameSample: Codable, Equatable {
    public let timestampMs: Double
    public let handDetected: Bool
    public let handCount: Int
    public let handConfidence: Double
    public let handBoundingBoxes: [BoundingBox]
    public let hands: [DetectedHand]
    public let faceDetected: Bool
    public let faceConfidence: Double
    public let brightnessValue: Double
    public let blurValue: Double
    public let contrastValue: Double
    public let motionValue: Double

    public init(
        timestampMs: Double,
        handDetected: Bool,
        handCount: Int,
        handConfidence: Double,
        handBoundingBoxes: [BoundingBox],
        hands: [DetectedHand] = [],
        faceDetected: Bool,
        faceConfidence: Double,
        brightnessValue: Double,
        blurValue: Double,
        contrastValue: Double,
        motionValue: Double
    ) {
        self.timestampMs = timestampMs
        self.handDetected = handDetected
        self.handCount = handCount
        self.handConfidence = handConfidence
        self.handBoundingBoxes = handBoundingBoxes
        self.hands = hands
        self.faceDetected = faceDetected
        self.faceConfidence = faceConfidence
        self.brightnessValue = brightnessValue
        self.blurValue = blurValue
        self.contrastValue = contrastValue
        self.motionValue = motionValue
    }
}
