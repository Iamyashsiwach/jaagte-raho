import XCTest
#if canImport(JaagteRahoCore)
@testable import JaagteRahoCore
#else
@testable import JaagteRaho
#endif

final class FatigueEngineTests: XCTestCase {
    func testJourneyRejectsStaleInvalidAndInaccurateLocations() {
        let now = Date(timeIntervalSince1970: 1000)
        var journey = Journey(startedAt: now)
        XCTAssertFalse(journey.append(.init(latitude: 28, longitude: 77, timestamp: now.addingTimeInterval(-20), accuracy: 5), now: now))
        XCTAssertFalse(journey.append(.init(latitude: 91, longitude: 77, timestamp: now, accuracy: 5), now: now))
        XCTAssertFalse(journey.append(.init(latitude: 28, longitude: 77, timestamp: now, accuracy: 150), now: now))
        XCTAssertTrue(journey.points.isEmpty)
    }
    func testJourneyCountsRecordedDistanceAndRejectsGPSJumps() {
        let start = Date(timeIntervalSince1970: 1000)
        var journey = Journey(startedAt: start)
        XCTAssertTrue(journey.append(.init(latitude: 28, longitude: 77, timestamp: start, accuracy: 5), now: start))
        let next = start.addingTimeInterval(10)
        XCTAssertTrue(journey.append(.init(latitude: 28.001, longitude: 77, timestamp: next, accuracy: 5), now: next))
        XCTAssertGreaterThan(journey.distanceMeters, 100)
        XCTAssertLessThan(journey.distanceMeters, 120)
        XCTAssertFalse(journey.append(.init(latitude: 29, longitude: 77, timestamp: next.addingTimeInterval(1), accuracy: 5), now: next.addingTimeInterval(1)))
        XCTAssertEqual(journey.points.count, 2)
    }
    func testJourneyPauseAndLongGPSGapsDoNotInventTravel() {
        let start = Date(timeIntervalSince1970: 1000)
        var journey = Journey(startedAt: start)
        _ = journey.append(.init(latitude: 28, longitude: 77, timestamp: start, accuracy: 5), now: start)
        journey.breakRoute()
        let resumed = start.addingTimeInterval(30)
        _ = journey.append(.init(latitude: 29, longitude: 77, timestamp: resumed, accuracy: 5), now: resumed)
        let gap = resumed.addingTimeInterval(90)
        _ = journey.append(.init(latitude: 30, longitude: 77, timestamp: gap, accuracy: 5), now: gap)
        XCTAssertEqual(journey.distanceMeters, 0)
        XCTAssertEqual(journey.points.map(\.segment), [0, 1, 2])
    }
    func testJourneyRejectsOutOfOrderAndStationaryNoise() {
        let now = Date(timeIntervalSince1970: 1000)
        var journey = Journey(startedAt: now)
        let point = JourneyPoint(latitude: 28, longitude: 77, timestamp: now, accuracy: 5)
        XCTAssertTrue(journey.append(point, now: now))
        XCTAssertFalse(journey.append(point, now: now))
        XCTAssertFalse(journey.append(.init(latitude: 28.00001, longitude: 77, timestamp: now.addingTimeInterval(10), accuracy: 5), now: now.addingTimeInterval(10)))
        XCTAssertEqual(journey.distanceMeters, 0)
    }
    func testLocationSharingIsTimestampedAndExplicitlyASnapshot() {
        let point = JourneyPoint(latitude: 28, longitude: 77, timestamp: Date(), accuracy: 5)
        XCTAssertTrue(point.shareText.contains("snapshot"))
        XCTAssertTrue(point.shareText.contains("Updated"))
        XCTAssertTrue(point.mapsURL.absoluteString.contains("28.0,77.0"))
    }
    func testCompanionSupportsAllLanguagesAndRestResponse() {
        for language in VoiceLanguage.allCases {
            XCTAssertFalse(CompanionContent.story(language).isEmpty)
            XCTAssertFalse(CompanionContent.quiz(language).isEmpty)
            XCTAssertFalse(CompanionContent.greeting(language).isEmpty)
            XCTAssertEqual(CompanionContent.reply("I am sleepy", language: language), language.text(for: "critical"))
        }
        XCTAssertTrue(CompanionContent.quizReply("Mars", language: .english).contains("right"))
        XCTAssertTrue(CompanionContent.quizReply("Venus", language: .english).contains("answer is Mars"))
    }
    private func sample(_ t: Double, closed: Bool = false, jaw: Double = 0, pitch: Double = 0) -> FaceMetrics {
        .init(timestamp: t, leftEAR: closed ? 0.05 : 0.30,
              rightEAR: closed ? 0.05 : 0.30, jawOpen: jaw, pitch: pitch)
    }
    private func feed(_ engine: inout FatigueEngine, from: Double, count: Int, closed: Bool) {
        for i in 0..<count { engine.ingest(sample(from + Double(i) * 0.1, closed: closed)) }
    }
    func testNormalBlinkDoesNotTriggerCheckIn() {
        var engine = FatigueEngine(calibration: .demo)
        feed(&engine, from: 0, count: 10, closed: false)
        feed(&engine, from: 1, count: 3, closed: true)
        feed(&engine, from: 1.3, count: 10, closed: false)
        XCTAssertEqual(engine.snapshot.state, .monitoring)
        XCTAssertEqual(engine.snapshot.closureSeconds, 0)
    }
    func testClosureTriggersVoiceThenImmediateCriticalWithoutPromptCompletion() {
        var engine = FatigueEngine(calibration: .demo)
        feed(&engine, from: 0, count: 17, closed: true)
        XCTAssertEqual(engine.snapshot.state, .checkIn)
        feed(&engine, from: 1.7, count: 16, closed: true)
        XCTAssertEqual(engine.snapshot.state, .critical)
        XCTAssertEqual(engine.snapshot.trigger, .prolongedClosure)
    }
    func testAcknowledgmentCannotClearClosedEyesOrCriticalAlarm() {
        var engine = FatigueEngine(calibration: .demo)
        feed(&engine, from: 0, count: 17, closed: true)
        XCTAssertFalse(engine.acknowledge(at: 1.6))
        feed(&engine, from: 1.7, count: 16, closed: true)
        feed(&engine, from: 3.3, count: 10, closed: false)
        XCTAssertFalse(engine.acknowledge(at: 4.2))
        XCTAssertEqual(engine.snapshot.state, .critical)
    }
    func testMissingFaceCannotClearCriticalAlarm() {
        var engine = FatigueEngine(calibration: .demo)
        feed(&engine, from: 0, count: 33, closed: true)
        engine.ingest(.missing(at: 3.3)); engine.tick(at: 5)
        XCTAssertEqual(engine.snapshot.state, .critical)
    }
    func testDroppedFramesDoNotAccumulateEyeClosure() {
        var engine = FatigueEngine(calibration: .demo)
        feed(&engine, from: 0, count: 10, closed: true)
        feed(&engine, from: 4, count: 10, closed: true)
        XCTAssertLessThan(engine.snapshot.closureSeconds, 1)
        XCTAssertNotEqual(engine.snapshot.state, .critical)
    }
    func testWatchdogMarksStaleCameraUnavailable() {
        var engine = FatigueEngine(calibration: .demo)
        engine.ingest(sample(0)); engine.tick(at: 1)
        XCTAssertEqual(engine.snapshot.state, .trackingUnavailable)
        engine.ingest(sample(1.1))
        XCTAssertEqual(engine.snapshot.state, .monitoring)
    }
    func testNoResponseEscalatesEvenWithoutCameraFrames() {
        var engine = FatigueEngine(calibration: .demo)
        feed(&engine, from: 0, count: 17, closed: true)
        engine.promptFinished(at: 2)
        engine.tick(at: 10.1)
        XCTAssertEqual(engine.snapshot.state, .critical)
        XCTAssertEqual(engine.snapshot.trigger, .noResponse)
    }
    func testAcknowledgmentRequiresFreshOpenEyes() {
        var engine = FatigueEngine(calibration: .demo)
        feed(&engine, from: 0, count: 17, closed: true)
        feed(&engine, from: 1.7, count: 10, closed: false)
        XCTAssertTrue(engine.acknowledge(at: 2.6))
        engine.tick(at: 20)
        XCTAssertNotEqual(engine.snapshot.state, .critical)
    }
    func testOutOfOrderAndInvalidValuesAreRejected() {
        var engine = FatigueEngine(calibration: .demo)
        feed(&engine, from: 5, count: 10, closed: false)
        engine.ingest(sample(1, closed: true))
        XCTAssertEqual(engine.snapshot.state, .monitoring)
        var bad = sample(6); bad.leftEAR = .nan
        engine.ingest(bad)
        XCTAssertEqual(engine.snapshot.state, .trackingUnavailable)
    }
    func testMissingCoverageSuppressesClosureTrend() {
        var engine = FatigueEngine(calibration: .demo)
        feed(&engine, from: 0, count: 10, closed: false)
        engine.tick(at: 60)
        XCTAssertFalse(engine.snapshot.trendReady)
        XCTAssertLessThan(engine.snapshot.trackingCoverage, 0.1)
    }
    func testOneLongYawnIsNotCountedRepeatedly() {
        var engine = FatigueEngine(calibration: .demo)
        for i in 0..<80 { engine.ingest(sample(Double(i) * 0.1, jaw: 0.9)) }
        XCTAssertEqual(engine.snapshot.yawns, 1)
        XCTAssertEqual(engine.snapshot.state, .monitoring)
    }
    func testCalibrationRequiresActualEyeClosure() {
        var collector = CalibrationCollector()
        for i in 0..<100 { collector.ingest(sample(Double(i) * 0.1)) }
        XCTAssertEqual(collector.phase, .closedEyes)
        XCTAssertNil(collector.result)
        for i in 100..<125 { collector.ingest(sample(Double(i) * 0.1, closed: true)) }
        XCTAssertEqual(collector.phase, .complete)
        XCTAssertTrue(collector.result?.valid == true)
    }
    func testInvalidCalibrationCannotMonitor() {
        let bad = DriverCalibration(leftOpen: 0.05, rightOpen: 0.05,
                                    leftClosed: 0.04, rightClosed: 0.04, neutralPitch: 0)
        var engine = FatigueEngine(calibration: bad)
        engine.ingest(sample(0))
        XCTAssertEqual(engine.snapshot.state, .idle)
    }
    func testNoPromptCallbackStillEscalatesAtWatchdogDeadline() {
        var engine = FatigueEngine(calibration: .demo)
        feed(&engine, from: 0, count: 17, closed: true)
        engine.tick(at: 21.6)
        XCTAssertEqual(engine.snapshot.state, .critical)
        XCTAssertEqual(engine.snapshot.trigger, .noResponse)
    }
    func testRepeatedPromptCompletionsCannotExtendResponseDeadline() {
        var engine = FatigueEngine(calibration: .demo)
        feed(&engine, from: 0, count: 17, closed: true)
        engine.promptFinished(at: 2)
        engine.promptFinished(at: 9)
        engine.tick(at: 10)
        XCTAssertEqual(engine.snapshot.state, .critical)
        XCTAssertEqual(engine.snapshot.trigger, .noResponse)
    }
    func testMissingFramesResetYawnAndNodContinuity() {
        var engine = FatigueEngine(calibration: .demo)
        for i in 0..<13 { engine.ingest(sample(Double(i) * 0.1, jaw: 0.9, pitch: 25)) }
        engine.ingest(.missing(at: 1.3))
        for i in 14..<19 { engine.ingest(sample(Double(i) * 0.1, jaw: 0.9, pitch: 25)) }
        engine.ingest(sample(1.9))
        XCTAssertEqual(engine.snapshot.yawns, 0)
        XCTAssertEqual(engine.snapshot.nods, 0)
    }
    func testMissingFaceDuringCheckInRejectsAcknowledgment() {
        var engine = FatigueEngine(calibration: .demo)
        feed(&engine, from: 0, count: 17, closed: true)
        engine.ingest(.missing(at: 1.7))
        XCTAssertFalse(engine.acknowledge(at: 2.3))
        engine.promptFinished(at: 2)
        engine.tick(at: 10)
        XCTAssertEqual(engine.snapshot.state, .critical)
    }
    func testCriticalRemainsLatchedAfterCameraRecovery() {
        var engine = FatigueEngine(calibration: .demo)
        feed(&engine, from: 0, count: 33, closed: true)
        engine.tick(at: 12)
        feed(&engine, from: 12.1, count: 12, closed: false)
        XCTAssertFalse(engine.acknowledge(at: 13.2))
        XCTAssertEqual(engine.snapshot.state, .critical)
        XCTAssertEqual(engine.snapshot.trigger, .prolongedClosure)
    }
    func testEyeClosureCheckInBypassesAcknowledgmentCooldown() {
        var engine = FatigueEngine(calibration: .demo)
        feed(&engine, from: 0, count: 17, closed: true)
        feed(&engine, from: 1.7, count: 10, closed: false)
        XCTAssertTrue(engine.acknowledge(at: 2.6))
        feed(&engine, from: 2.7, count: 17, closed: true)
        XCTAssertEqual(engine.snapshot.state, .checkIn)
        XCTAssertEqual(engine.snapshot.trigger, .prolongedClosure)
    }
    func testClosureTrendRequiresObservedCoverageAndShortClosures() {
        var engine = FatigueEngine(calibration: .demo)
        for i in 0...205 {
            // Each closure lasts 0.5 seconds: never a prolonged closure.
            engine.ingest(sample(Double(i) * 0.1, closed: i % 10 < 6))
        }
        XCTAssertTrue(engine.snapshot.trendReady)
        XCTAssertGreaterThan(engine.snapshot.trackingCoverage, 0.99)
        XCTAssertGreaterThan(engine.snapshot.closureFraction, 0.45)
        XCTAssertEqual(engine.snapshot.state, .checkIn)
        XCTAssertEqual(engine.snapshot.trigger, .closureTrend)
        XCTAssertFalse(engine.acknowledge(at: 20.5))
    }
    func testRepeatedYawnsTriggerOneCheckInAfterThreeDistinctYawns() {
        var engine = FatigueEngine(calibration: .demo)
        for i in 0...80 {
            engine.ingest(sample(Double(i) * 0.1, jaw: i % 30 < 21 ? 0.9 : 0))
        }
        XCTAssertEqual(engine.snapshot.yawns, 3)
        XCTAssertEqual(engine.snapshot.state, .checkIn)
        XCTAssertEqual(engine.snapshot.trigger, .repeatedYawns)
    }
    func testRepeatedNodsRequireReturningToNeutral() {
        var engine = FatigueEngine(calibration: .demo)
        for i in 0..<35 { engine.ingest(sample(Double(i) * 0.1, pitch: i % 12 < 8 ? 25 : 0)) }
        XCTAssertEqual(engine.snapshot.nods, 3)
        XCTAssertEqual(engine.snapshot.state, .checkIn)
        XCTAssertEqual(engine.snapshot.trigger, .repeatedNods)
    }
    func testDimLightingDoesNotBecomeMeasuredEyeClosure() {
        var engine = FatigueEngine(calibration: .demo)
        for i in 0..<100 {
            var frame = sample(Double(i) * 0.1, closed: true)
            frame.illumination = 0.01
            engine.ingest(frame)
        }
        XCTAssertEqual(engine.snapshot.state, .trackingUnavailable)
        XCTAssertEqual(engine.snapshot.closureSeconds, 0)
        XCTAssertFalse(engine.snapshot.trendReady)
    }
    func testNonFiniteTimestampsCannotAdvanceDeadlines() {
        var engine = FatigueEngine(calibration: .demo)
        feed(&engine, from: 0, count: 17, closed: true)
        engine.ingest(sample(.infinity, closed: true))
        engine.tick(at: .nan)
        XCTAssertEqual(engine.snapshot.state, .checkIn)
        engine.promptFinished(at: 2)
        engine.tick(at: 10)
        XCTAssertEqual(engine.snapshot.state, .critical)
    }
    func testCalibrationMissingFramesResetOnlyCurrentPhase() {
        var collector = CalibrationCollector()
        for i in 0..<40 { collector.ingest(sample(Double(i) * 0.1)) }
        XCTAssertEqual(collector.phase, .closedEyes)
        for i in 40..<50 { collector.ingest(sample(Double(i) * 0.1, closed: true)) }
        collector.ingest(.missing(at: 5))
        XCTAssertEqual(collector.phase, .closedEyes)
        XCTAssertEqual(collector.progress, 0)
        for i in 51..<62 { collector.ingest(sample(Double(i) * 0.1, closed: true)) }
        XCTAssertNil(collector.result)
        for i in 62..<80 { collector.ingest(sample(Double(i) * 0.1, closed: true)) }
        XCTAssertTrue(collector.result?.valid == true)
    }
    func testAcknowledgmentRecognizesNaturalSpeechPunctuation() {
        XCTAssertTrue(VoiceLanguage.english.acknowledges("Yes."))
        XCTAssertTrue(VoiceLanguage.english.acknowledges("Okay, I hear you."))
        XCTAssertTrue(VoiceLanguage.hindi.acknowledges("हाँ।"))
        XCTAssertTrue(VoiceLanguage.punjabi.acknowledges("ਹਾਂ।"))
        XCTAssertFalse(VoiceLanguage.english.acknowledges("yesterday"))
        XCTAssertFalse(VoiceLanguage.english.acknowledges("smoke"))
    }
}
