import XCTest
@testable import QCEngine

final class QCEngineTests: XCTestCase {
    func testShortDurationBlocks() {
        let report = run(durationMs: 4_999, frames: happyFrames())

        XCTAssertEqual(report.qcResult, .blocked)
        XCTAssertTrue(report.blockReasons.contains("Recording too short (minimum 5s required)"))
    }

    func testWrongOrientationBlocks() {
        let report = run(orientation: .portrait, frames: happyFrames())

        XCTAssertEqual(report.qcResult, .blocked)
        XCTAssertTrue(report.blockReasons.contains("Wrong orientation — landscape required"))
    }

    func testVeryLowHandPresenceBlocks() {
        let frames = frames(count: 100) { index in index < 25 }
        let report = run(frames: frames)

        XCTAssertEqual(report.qcResult, .blocked)
        XCTAssertTrue(report.blockReasons.contains("Hands not visible enough (25% of frames)"))
    }

    func testPartialHandPresenceWarns() {
        let frames = frames(count: 100) { index in index < 45 }
        let report = run(frames: frames)

        XCTAssertEqual(report.qcResult, .passedWithWarning)
        XCTAssertTrue(report.warningReasons.contains("Hands partially visible (45% of frames)"))
    }

    func testHighFacePresenceBlocksPrivacyIssue() {
        let frames = frames(count: 100, faceDetected: { index in index < 40 }) { _ in true }
        let report = run(frames: frames)

        XCTAssertEqual(report.qcResult, .blocked)
        XCTAssertTrue(report.blockReasons.contains("Face detected in 40% of frames — privacy issue"))
    }

    func testLowReadinessBlocksWhenNoOtherBlocksExist() {
        let visibleIndexes: Set<Int> = [0, 2, 4, 6, 8, 9]
        let lowQualityFrames = frames(count: 10) { index in
            visibleIndexes.contains(index)
        }.enumerated().map { index, frame in
            makeFrame(
                handDetected: frame.handDetected,
                handCount: frame.handCount,
                box: BoundingBox(x: index < 6 ? 0.95 : 0.0, y: index < 6 ? 0.95 : 0.0, width: 0.05, height: 0.05),
                brightness: 35,
                blur: 40,
                contrast: 40
            )
        }

        let report = run(frames: lowQualityFrames, stabilityReadings: Array(repeating: 40, count: 5))

        XCTAssertEqual(report.qcResult, .blocked)
        XCTAssertTrue(report.blockReasons.contains("Overall quality score too low — please re-record"))
    }

    func testHappySamplePasses() {
        let report = run(frames: happyFrames())

        XCTAssertEqual(report.qcResult, .passed)
        XCTAssertGreaterThanOrEqual(report.readinessScore, 85)
        XCTAssertTrue(report.blockReasons.isEmpty)
        XCTAssertTrue(report.warningReasons.isEmpty)
    }

    func testEmptyStabilityReadingsFallbackTo75() {
        let report = run(frames: happyFrames(), stabilityReadings: [])

        XCTAssertEqual(report.stabilityScore, 75)
    }

    private func run(
        durationMs: Int = 10_000,
        orientation: Orientation = .landscape,
        frames: [QCFrameSample],
        stabilityReadings: [Double] = Array(repeating: 95, count: 10)
    ) -> LocalQCReport {
        QCEngine.run(
            frames: frames,
            stabilityReadings: stabilityReadings,
            durationMs: durationMs,
            orientation: orientation,
            recordingId: "rec-1",
            questId: "quest-1",
            fileSizeBytes: 123_456
        )
    }

    private func happyFrames() -> [QCFrameSample] {
        frames(count: 20) { _ in true }
    }

    private func frames(
        count: Int,
        faceDetected: (Int) -> Bool = { _ in false },
        handDetected: (Int) -> Bool
    ) -> [QCFrameSample] {
        (0..<count).map { index in
            let hasHand = handDetected(index)
            return makeFrame(
                timestampMs: Double(index) * 33.333,
                handDetected: hasHand,
                handCount: hasHand ? 2 : 0,
                box: hasHand ? BoundingBox(x: 0.35, y: 0.35, width: 0.3, height: 0.3) : nil,
                faceDetected: faceDetected(index)
            )
        }
    }

    private func makeFrame(
        timestampMs: Double = 0,
        handDetected: Bool,
        handCount: Int,
        box: BoundingBox?,
        faceDetected: Bool = false,
        brightness: Double = 90,
        blur: Double = 90,
        contrast: Double = 90
    ) -> QCFrameSample {
        QCFrameSample(
            timestampMs: timestampMs,
            handDetected: handDetected,
            handCount: handCount,
            handConfidence: handDetected ? 0.95 : 0,
            handBoundingBoxes: box.map { [$0] } ?? [],
            hands: [],
            faceDetected: faceDetected,
            faceConfidence: faceDetected ? 0.85 : 0,
            brightnessValue: brightness,
            blurValue: blur,
            contrastValue: contrast,
            motionValue: 0
        )
    }
}
