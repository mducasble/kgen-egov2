import Foundation

public enum QCEngine {
    public static func run(
        frames: [QCFrameSample],
        stabilityReadings: [Double],
        durationMs: Int,
        orientation: Orientation,
        thresholds: QCThresholds = .default,
        recordingId: String,
        questId: String,
        fileSizeBytes: Int64
    ) -> LocalQCReport {
        let frameCount = frames.count
        let handPresenceRate = rate(frames) { $0.handDetected }
        let dualHandRate = rate(frames) { $0.handCount >= 2 }
        let facePresenceRate = rate(frames) { $0.faceDetected }
        let blurScore = clamp(mean(frames.map(\.blurValue)), 0, 100)
        let brightnessScore = clamp(mean(frames.map(\.brightnessValue)), 0, 100)
        let contrastScore = clamp(mean(frames.map(\.contrastValue)), 0, 100)
        let stabilityScore = stabilityReadings.isEmpty ? 75 : clamp(mean(stabilityReadings), 0, 100)
        let handContinuityScore = computeHandContinuityScore(frames)
        let handCenteringScore = computeHandCenteringScore(frames)
        let averageHandArea = computeAverageHandArea(frames)

        let durationScore: Double
        if durationMs < thresholds.minDurationMs {
            durationScore = 0
        } else if durationMs > thresholds.maxDurationMs {
            durationScore = 50
        } else {
            durationScore = 100
        }

        let orientationScore: Double =
            thresholds.requiredOrientation == .any || orientation == thresholds.requiredOrientation ? 100 : 0
        let handPresenceScore = clamp(handPresenceRate * 100, 0, 100)
        let facePrivacyScore = clamp(100 - facePresenceRate * 100, 0, 100)
        let framingScore = handCenteringScore

        let readinessScore = clamp(
            handPresenceScore * 0.20 +
                durationScore * 0.15 +
                orientationScore * 0.12 +
                facePrivacyScore * 0.12 +
                handContinuityScore * 0.10 +
                blurScore * 0.10 +
                framingScore * 0.08 +
                brightnessScore * 0.07 +
                stabilityScore * 0.06,
            0,
            100
        )

        var blockReasons: [String] = []
        var warningReasons: [String] = []

        if durationMs < thresholds.minDurationMs {
            blockReasons.append("Recording too short (minimum \(thresholds.minDurationMs / 1000)s required)")
        }
        if thresholds.requiredOrientation != .any && orientation != thresholds.requiredOrientation {
            blockReasons.append("Wrong orientation — \(thresholds.requiredOrientation.rawValue) required")
        }
        if handPresenceRate < thresholds.minHandPresenceRate * 0.5 {
            blockReasons.append("Hands not visible enough (\(formatPercent(handPresenceRate))% of frames)")
        } else if handPresenceRate < thresholds.minHandPresenceRate {
            warningReasons.append("Hands partially visible (\(formatPercent(handPresenceRate))% of frames)")
        }
        if facePresenceRate > thresholds.maxFacePresenceRate * 2 {
            blockReasons.append("Face detected in \(formatPercent(facePresenceRate))% of frames — privacy issue")
        } else if facePresenceRate > thresholds.maxFacePresenceRate {
            warningReasons.append("Face briefly detected (\(formatPercent(facePresenceRate))% of frames)")
        }
        if brightnessScore < thresholds.minBrightnessScore {
            warningReasons.append("Video appears dark — consider better lighting")
        }
        if blurScore < thresholds.minBlurScore {
            warningReasons.append("Video appears blurry — hold camera steady")
        }
        if stabilityScore < thresholds.minStabilityScore {
            warningReasons.append("Excessive camera movement detected")
        }

        let qcResult: QCResult
        if !blockReasons.isEmpty || readinessScore < thresholds.minReadinessScore {
            if readinessScore < thresholds.minReadinessScore && blockReasons.isEmpty {
                blockReasons.append("Overall quality score too low — please re-record")
            }
            qcResult = .blocked
        } else if !warningReasons.isEmpty || readinessScore < thresholds.warnReadinessScore {
            qcResult = .passedWithWarning
        } else {
            qcResult = .passed
        }

        return LocalQCReport(
            recordingId: recordingId,
            questId: questId,
            durationMs: durationMs,
            resolutionWidth: 1080,
            resolutionHeight: 1920,
            fps: 30,
            orientation: orientation,
            audioPresent: true,
            fileSizeBytes: fileSizeBytes,
            fileIntegrityPassed: true,
            sampledFrameCount: frameCount,
            handPresenceRate: handPresenceRate,
            dualHandRate: dualHandRate,
            facePresenceRate: facePresenceRate,
            averageHandArea: averageHandArea,
            handCenteringScore: handCenteringScore,
            handContinuityScore: handContinuityScore,
            blurScore: blurScore,
            brightnessScore: brightnessScore,
            contrastScore: contrastScore,
            stabilityScore: stabilityScore,
            readinessScore: readinessScore,
            qcResult: qcResult,
            blockReasons: blockReasons,
            warningReasons: warningReasons,
            generatedAt: Int64(Date().timeIntervalSince1970 * 1000)
        )
    }

    static func computeHandContinuityScore(_ frames: [QCFrameSample]) -> Double {
        guard frames.count >= 2 else { return 100 }
        let transitions = zip(frames.dropFirst(), frames).filter { current, previous in
            current.handDetected != previous.handDetected
        }.count
        let maxTransitions = frames.count - 1
        return clamp(100 - (Double(transitions) / Double(maxTransitions)) * 100, 0, 100)
    }

    static func computeHandCenteringScore(_ frames: [QCFrameSample]) -> Double {
        let scores = frames.compactMap { frame -> Double? in
            guard frame.handDetected, let box = frame.handBoundingBoxes.first else { return nil }
            let cx = box.x + box.width / 2
            let cy = box.y + box.height / 2
            let distance = sqrt(pow(cx - 0.5, 2) + pow(cy - 0.5, 2))
            return clamp(100 - distance * 150, 0, 100)
        }
        return scores.isEmpty ? 50 : mean(scores)
    }

    static func computeAverageHandArea(_ frames: [QCFrameSample]) -> Double {
        let areas = frames.compactMap { frame -> Double? in
            guard frame.handDetected, let box = frame.handBoundingBoxes.first else { return nil }
            return box.width * box.height
        }
        return areas.isEmpty ? 0 : mean(areas)
    }

    static func clamp(_ value: Double, _ minValue: Double, _ maxValue: Double) -> Double {
        min(max(value, minValue), maxValue)
    }

    private static func rate(_ frames: [QCFrameSample], matching predicate: (QCFrameSample) -> Bool) -> Double {
        guard !frames.isEmpty else { return 0 }
        return Double(frames.filter(predicate).count) / Double(frames.count)
    }

    private static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func formatPercent(_ rate: Double) -> String {
        let percent = rate * 100
        if percent.rounded() == percent {
            return String(Int(percent))
        }
        var formatted = String(format: "%.15f", percent)
        while formatted.last == "0" { formatted.removeLast() }
        if formatted.last == "." { formatted.removeLast() }
        return formatted
    }
}
