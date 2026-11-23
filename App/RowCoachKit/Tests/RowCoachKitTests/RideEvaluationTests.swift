import XCTest
@testable import RowCoachKit

final class RideSaveRuleTests: XCTestCase {
    func testMinimumDistanceAndDuration() {
        XCTAssertFalse(RideSaveRule.shouldKeep(distance: 1, activeDuration: 0))
        XCTAssertFalse(RideSaveRule.shouldKeep(distance: 99, activeDuration: 600))
        XCTAssertFalse(RideSaveRule.shouldKeep(distance: 400, activeDuration: 59))
        XCTAssertTrue(RideSaveRule.shouldKeep(distance: 100, activeDuration: 60))
        XCTAssertTrue(RideSaveRule.shouldKeep(distance: 4000, activeDuration: 1100))
        XCTAssertFalse(RideSaveRule.shouldKeep(distance: .nan, activeDuration: 100))
    }
}

final class PhaseIntensityTests: XCTestCase {
    func testIntensityFromZoneAndPace() {
        XCTAssertEqual(WorkoutPhase(kind: .rest, durationS: 60, hrZone: 5).intensity(), .rest)
        XCTAssertEqual(WorkoutPhase(kind: .work, durationS: 600, hrZone: 2).intensity(), .easy)
        XCTAssertEqual(WorkoutPhase(kind: .work, durationS: 600, hrZone: 3).intensity(), .moderate)
        XCTAssertEqual(WorkoutPhase(kind: .work, durationS: 360, hrZone: 4).intensity(), .hard)
        // Zone 3, aber Tempo um das 2000-m-Tempo: hart (die härtere Angabe zählt)
        XCTAssertEqual(WorkoutPhase(kind: .work, durationS: 60, hrZone: 3, paceOffsetMinS: -3,
                                    paceOffsetMaxS: 3).intensity(), .hard)
        XCTAssertEqual(WorkoutPhase(kind: .work, durationS: 60, paceOffsetMinS: 10, paceOffsetMaxS: 15).intensity(),
                       .moderate)
        XCTAssertEqual(WorkoutPhase(kind: .warmup, durationS: 300, paceOffsetMinS: 25, paceOffsetMaxS: 30).intensity(),
                       .easy)
        // ohne Ziele: Intervall mittel, Einrudern leicht
        XCTAssertEqual(WorkoutPhase(kind: .work, durationS: 60).intensity(), .moderate)
        XCTAssertEqual(WorkoutPhase(kind: .warmup, durationS: 60).intensity(), .easy)
    }

    func testWorkNumber() {
        let plan = WorkoutPlan(id: "p", name: "P", phases: [
            WorkoutPhase(kind: .warmup, durationS: 300),
            WorkoutPhase(kind: .work, durationS: 60),
            WorkoutPhase(kind: .rest, durationS: 60),
            WorkoutPhase(kind: .work, durationS: 60),
            WorkoutPhase(kind: .cooldown, durationS: 300),
        ])
        XCTAssertNil(plan.workNumber(at: 0))
        XCTAssertEqual(plan.workNumber(at: 1), 1)
        XCTAssertNil(plan.workNumber(at: 2))
        XCTAssertEqual(plan.workNumber(at: 3), 2)
        XCTAssertNil(plan.workNumber(at: 9))
        XCTAssertEqual(WorkoutPhase.Kind.work.title, "Intervall")
    }
}

final class IntervalEvaluationTests: XCTestCase {
    private let plan = WorkoutPlan(id: "iv", name: "2 × 2 min", phases: [
        WorkoutPhase(kind: .work, durationS: 120, spmMin: 26, spmMax: 28, paceOffsetMinS: 0, paceOffsetMaxS: 2,
                     label: "Intervall 1"),
        WorkoutPhase(kind: .rest, durationS: 60, label: "Pause"),
        WorkoutPhase(kind: .work, durationS: 120, spmMin: 26, spmMax: 28, paceOffsetMinS: 0, paceOffsetMaxS: 2,
                     label: "Intervall 2"),
    ])

    private func record(phases: [PlanPhaseResult], samples: [WorkoutSample]) -> WorkoutRecord {
        let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let header = WorkoutHeader(startDate: t0, endDate: t0.addingTimeInterval(300),
                                   device: WorkoutDevice(source: .simulator), workoutPlanId: plan.id)
        let summary = WorkoutSummary(distance: 1100, activeDuration: 300, totalDuration: 300, averagePace: 136,
                                     averageSpeed: 3.6, averageStrokeRate: 24, strokeCount: 120, averagePower: 150,
                                     maxPower: 250, calories: 50, averageHeartRate: nil, maxHeartRate: nil,
                                     heartRateZoneSeconds: nil, completedCourse: true, pauseCount: 0)
        return WorkoutRecord(header: header, summary: summary, samples: samples, splits: [], planPhases: phases)
    }

    func testOneRowPerPhaseWithLights() {
        // best2k 480 s → 2000-m-Tempo 2:00; Ziel 2:00–2:02
        let phases = [
            // 500 m in 120 s → 2:00 /500 m, Schlagzahl 27: grün
            PlanPhaseResult(index: 0, kind: "work", label: "Intervall 1", startTime: 0, endTime: 120, startDistance: 0,
                            endDistance: 500, averageStrokeRate: 27, averageHeartRate: 150, completed: true),
            PlanPhaseResult(index: 1, kind: "rest", label: "Pause", startTime: 120, endTime: 180, startDistance: 500,
                            endDistance: 600, averageStrokeRate: 18, averageHeartRate: 130, completed: true),
            // 400 m in 120 s → 2:30 /500 m (rot), Schlagzahl 24 (gelb, 2 daneben)
            PlanPhaseResult(index: 2, kind: "work", label: "Intervall 2", startTime: 180, endTime: 300,
                            startDistance: 600, endDistance: 1000, averageStrokeRate: 24, averageHeartRate: 160,
                            completed: false),
        ]
        let samples = (0..<300).map { t in
            WorkoutSample(time: Double(t), distance: Double(t) * 3.5, pace: 130, strokeRate: t < 120 ? 27 : 24,
                          power: t < 120 ? 200 : 100, heartRate: nil)
        }
        let rows = IntervalEvaluation.evaluate(record: record(phases: phases, samples: samples), plan: plan, best2k: 480)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].workNumber, 1)
        XCTAssertEqual(rows[0].averagePace ?? 0, 120, accuracy: 1e-9)
        XCTAssertEqual(rows[0].targetPace, 120...122)
        XCTAssertEqual(rows[0].paceLight, .green)
        XCTAssertEqual(rows[0].strokeRateLight, .green)
        XCTAssertEqual(rows[0].overallLight, .green)
        XCTAssertEqual(rows[0].averagePower, 200)
        XCTAssertNil(rows[1].workNumber)
        XCTAssertEqual(rows[1].overallLight, .none, "Pause ohne Ampel")
        XCTAssertEqual(rows[2].workNumber, 2)
        XCTAssertEqual(rows[2].paceLight, .red)
        XCTAssertEqual(rows[2].strokeRateLight, .yellow)
        XCTAssertEqual(rows[2].overallLight, .red)
        XCTAssertEqual(rows[2].averagePower, 100)
        XCTAssertFalse(rows[2].completed)
    }

    func testWithoutPlanNoTargets() {
        let phases = [PlanPhaseResult(index: 0, kind: "work", label: "X", startTime: 0, endTime: 60, startDistance: 0,
                                      endDistance: 250, averageStrokeRate: 30, averageHeartRate: nil, completed: true)]
        let rows = IntervalEvaluation.evaluate(record: record(phases: phases, samples: []), plan: nil, best2k: 480)
        XCTAssertEqual(rows.count, 1)
        XCTAssertNil(rows[0].targetPace)
        XCTAssertEqual(rows[0].overallLight, .none)
        XCTAssertNil(rows[0].averagePower)
    }
}

final class CoachCueDetectorTests: XCTestCase {
    private let work = WorkoutPhase(kind: .work, durationS: 60)
    private let rest = WorkoutPhase(kind: .rest, durationS: 60)

    private func status(index: Int, toChange: Double?, overall: Double, finished: Bool = false) -> PlanStatus {
        PlanStatus(phaseIndex: index, phaseCount: 3, phase: index == 1 ? rest : work,
                   nextPhase: index < 2 ? (index == 0 ? rest : work) : nil, phaseProgress: 0,
                   remainingTime: toChange, remainingDistance: nil, secondsToChange: toChange,
                   countdownActive: (toChange ?? 99) <= 10, nextChangeDistance: nil, nextChangeIsExact: false,
                   overallProgress: overall, estimatedRemaining: 0, finished: finished)
    }

    func testTrainingCuesOncePerPhase() {
        var d = CoachCueDetector()
        XCTAssertEqual(d.update(status: status(index: 0, toChange: 30, overall: 0.1)), [])
        XCTAssertEqual(d.update(status: status(index: 0, toChange: 10, overall: 0.2)),
                       [.countdown(seconds: 10, next: rest, nextIndex: 1)])
        XCTAssertEqual(d.update(status: status(index: 0, toChange: 9, overall: 0.2)), [], "Countdown nur einmal")
        XCTAssertEqual(d.update(status: status(index: 1, toChange: 60, overall: 0.34)),
                       [.phaseStarted(phase: rest, index: 1)])
        // Hälfte: im selben Schritt wie ein Wechsel nicht, danach schon
        XCTAssertEqual(d.update(status: status(index: 2, toChange: 60, overall: 0.67)),
                       [.phaseStarted(phase: work, index: 2)])
        XCTAssertEqual(d.update(status: status(index: 2, toChange: 2, overall: 0.9)), [],
                       "zu spät für einen Countdown, Hälfte schon verbraucht")
        XCTAssertEqual(d.update(status: status(index: 2, toChange: nil, overall: 1, finished: true)), [.finished])
        XCTAssertEqual(d.update(status: status(index: 2, toChange: nil, overall: 1, finished: true)), [])
    }

    func testHalfwayDuringPhase() {
        var d = CoachCueDetector()
        _ = d.update(status: status(index: 0, toChange: 50, overall: 0.4))
        XCTAssertEqual(d.update(status: status(index: 0, toChange: 40, overall: 0.5)), [.halfway])
    }

    func testFreeRowingHalfwayAndRemaining() {
        var d = CoachCueDetector()
        XCTAssertEqual(d.update(distance: 0, total: 4000), [])
        XCTAssertEqual(d.update(distance: 1990, total: 4000), [])
        XCTAssertEqual(d.update(distance: 2004, total: 4000), [.halfway])
        XCTAssertEqual(d.update(distance: 3490, total: 4000), [])
        XCTAssertEqual(d.update(distance: 3502, total: 4000), [.remaining(meters: 500)])
        XCTAssertEqual(d.update(distance: 3600, total: 4000), [])
        // kurze Strecke: kein „noch 500 m“
        var short = CoachCueDetector()
        _ = short.update(distance: 0, total: 800)
        XCTAssertEqual(short.update(distance: 450, total: 800), [.halfway])
        XCTAssertEqual(short.update(distance: 790, total: 800), [])
    }
}

final class AttributionListTests: XCTestCase {
    func testMergeWithoutDuplicates() {
        let merged = AttributionList.merge([
            "© swisstopo (swissALTI3D), Open Government Data",
            "© swisstopo (swissALTI3D), Open Government Data; Wasserflächen © OpenStreetMap contributors (ODbL)",
            " ; Copernicus DEM GLO-30",
        ])
        XCTAssertEqual(merged, ["© swisstopo (swissALTI3D), Open Government Data",
                                "Wasserflächen © OpenStreetMap contributors (ODbL)", "Copernicus DEM GLO-30"])
    }
}

final class SessionHoldTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func snap(_ d: Double, _ strokes: Int) -> RowingSnapshot {
        var s = RowingSnapshot()
        s.distance = d
        s.strokeCount = strokes
        s.strokeRate = 24
        s.pace = 125
        return s
    }

    func testHoldStopsTimeAndResumeNeedsStroke() {
        var s = RowingSession(track: CourseTrack(course: .straight(oneWay: 1000)), pauseAfter: 6)
        var raw = 0.0, strokes = 0, t = 0.0
        s.update(snap(raw, strokes), at: t0)
        for i in 1...40 {   // 20 s rudern
            t += 0.5; raw += 2
            if i % 5 == 0 { strokes += 1 }
            s.update(snap(raw, strokes), at: t0.addingTimeInterval(t))
        }
        XCTAssertEqual(s.state, .rowing)
        let active = s.activeTime
        let dist = s.distance
        XCTAssertEqual(s.hold(at: t0.addingTimeInterval(t)), [.paused])
        XCTAssertTrue(s.isHeld)
        // Dialog 30 s offen; der PM5 zählt weiter (jemand rudert noch) – zählt nicht
        for _ in 1...60 {
            t += 0.5; raw += 2; strokes += 1
            XCTAssertEqual(s.update(snap(raw, strokes), at: t0.addingTimeInterval(t)), [])
        }
        XCTAssertEqual(s.activeTime, active, accuracy: 1e-9)
        XCTAssertEqual(s.distance, dist, accuracy: 1e-9)
        XCTAssertEqual(s.trainingTime(at: t0.addingTimeInterval(t)), s.totalTime(at: t0.addingTimeInterval(t)) - 30,
                       accuracy: 1e-6)
        s.resume(at: t0.addingTimeInterval(t))
        XCTAssertFalse(s.isHeld)
        XCTAssertEqual(s.heldDuration, 30, accuracy: 1e-9)
        XCTAssertEqual(s.state, .paused)
        // erstes Update nach dem Halten: nur Grundlinie
        t += 0.5
        XCTAssertEqual(s.update(snap(raw, strokes), at: t0.addingTimeInterval(t)), [])
        XCTAssertEqual(s.distance, dist, accuracy: 1e-9)
        // nächster Schlag: weiter
        t += 0.5; raw += 2; strokes += 1
        XCTAssertEqual(s.update(snap(raw, strokes), at: t0.addingTimeInterval(t)), [.resumed])
        XCTAssertEqual(s.distance, dist + 2, accuracy: 1e-9)
    }

    func testHoldBeforeStartBlocksStart() {
        var s = RowingSession(track: CourseTrack(course: .straight(oneWay: 1000)))
        s.update(snap(0, 0), at: t0)
        XCTAssertEqual(s.hold(at: t0), [])
        XCTAssertEqual(s.update(snap(5, 2), at: t0.addingTimeInterval(1)), [])
        XCTAssertEqual(s.state, .ready)
        s.resume(at: t0.addingTimeInterval(2))
        s.update(snap(5, 2), at: t0.addingTimeInterval(2.5))
        XCTAssertEqual(s.state, .ready)
        XCTAssertEqual(s.update(snap(7, 3), at: t0.addingTimeInterval(3)), [.started])
    }
}

final class BilingualPlanTests: XCTestCase {
    /// Zweisprachige Felder ({"de", "en"}) und einsprachige Felder (Text) werden beide gelesen; Regeln nutzen den
    /// deutschen Quellwert von Niveau und Art, unabhängig von der Anzeigesprache.
    func testBilingualFieldsDecode() throws {
        let json = """
        [{"id": "p", "name": {"de": "Schwelle 4 x 6 Minuten", "en": "Threshold 4 x 6 minutes"},
          "summary": "nur deutsch",
          "level": {"de": "Fortgeschritten", "en": "Advanced"}, "category": {"de": "Schwelle", "en": "Threshold"},
          "phases": [{"kind": "work", "durationS": 360, "hrZone": 4, "label": {"de": "Block (1/4)", "en": "Block (1/4)"}}]}]
        """
        let plans = try WorkoutPlanCatalog.decode(Data(json.utf8))
        XCTAssertEqual(plans.count, 1)
        let p = plans[0]
        XCTAssertTrue(["Schwelle 4 x 6 Minuten", "Threshold 4 x 6 minutes"].contains(p.name))
        XCTAssertTrue(["Schwelle 4 × 6 min", "Threshold 4 × 6 min"].contains(p.shortName))
        XCTAssertEqual(p.summary, "nur deutsch")
        XCTAssertEqual(p.levelID, "Fortgeschritten")
        XCTAssertEqual(p.categoryID, "Schwelle")
        XCTAssertEqual(IntensityRules.level(plan: p), .moderate)
        XCTAssertEqual(p.phases[0].title, "Block (1/4)")
    }
}
