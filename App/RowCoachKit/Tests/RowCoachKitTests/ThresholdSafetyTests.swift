import XCTest
@testable import RowCoachKit

/// Pulsüberwachung, Retest-Karten R3/R4/R5, eine Rückfrage für Tests im Trainingsplan, Wiedereinstieg
/// (docs/schwelle/UMSETZUNG.md „Noch offen“)
final class ThresholdSafetyTests: XCTestCase {
    let day: TimeInterval = 86400
    let now = Date(timeIntervalSince1970: 1_795_000_000)

    // MARK: Pulsgurt prüfen / Puls fehlt

    func testStrapCheckAfterTenSecondsAboveMaxPlusEight() {
        var m = HeartRateSafetyMonitor()
        // 197 bei Maximalpuls 190 ist noch plausibel (+7)
        for t in 0..<30 { m.update(time: Double(t), heartRate: 197, maxHR: 190, watchMissing: false) }
        XCTAssertFalse(m.strapCheck)
        // 199 (+9): erst nach 10 s
        for t in 30..<39 { m.update(time: Double(t), heartRate: 199, maxHR: 190, watchMissing: false) }
        XCTAssertFalse(m.strapCheck)
        m.update(time: 40, heartRate: 199, maxHR: 190, watchMissing: false)
        XCTAssertTrue(m.strapCheck)
        // wieder plausibel: Meldung bleibt 15 s stehen, dann weg
        for t in 41..<55 { m.update(time: Double(t), heartRate: 150, maxHR: 190, watchMissing: false) }
        XCTAssertTrue(m.strapCheck)
        m.update(time: 56, heartRate: 150, maxHR: 190, watchMissing: false)
        XCTAssertFalse(m.strapCheck)
    }

    func testStrapCheckOnJumpAndNotWithoutMaxHR() {
        var m = HeartRateSafetyMonitor()
        m.update(time: 0, heartRate: 120, maxHR: nil, watchMissing: false)
        m.update(time: 1, heartRate: 145, maxHR: nil, watchMissing: false)   // +25/s: noch plausibel
        XCTAssertFalse(m.strapCheck)
        m.update(time: 2, heartRate: 185, maxHR: nil, watchMissing: false)   // +40/s
        XCTAssertTrue(m.strapCheck)
        // nach einer Lücke (Gurt neu angelegt) zählt ein grosser Unterschied nicht als Sprung
        var n = HeartRateSafetyMonitor()
        n.update(time: 0, heartRate: 90, maxHR: 190, watchMissing: false)
        n.update(time: 1, heartRate: nil, maxHR: 190, watchMissing: false)
        n.update(time: 20, heartRate: 160, maxHR: 190, watchMissing: false)
        XCTAssertFalse(n.strapCheck)
        // ohne Maximalpuls nie die Regel „über Maximalpuls + 8“
        var o = HeartRateSafetyMonitor()
        for t in 0..<30 { o.update(time: Double(t), heartRate: 230, maxHR: nil, watchMissing: false) }
        XCTAssertFalse(o.strapCheck)
    }

    func testHeartRateMissingOnlyInStepTestAfterFifteenSeconds() {
        var m = HeartRateSafetyMonitor()
        // ausserhalb des Stufentests nie „Puls fehlt“
        for t in 0..<60 { m.update(time: Double(t), heartRate: nil, maxHR: 190, watchMissing: false) }
        XCTAssertFalse(m.heartRateMissing)
        // Stufentest beginnt ohne Puls: nach > 15 s
        for t in 60...75 { m.update(time: Double(t), heartRate: nil, maxHR: 190, watchMissing: true) }
        XCTAssertFalse(m.heartRateMissing)
        m.update(time: 76, heartRate: nil, maxHR: 190, watchMissing: true)
        XCTAssertTrue(m.heartRateMissing)
        XCTAssertEqual(m.gapCount, 1)
        // Puls zurück: Meldung weg, ein zweiter kurzer Ausfall (10 s) meldet nichts
        m.update(time: 77, heartRate: 120, maxHR: 190, watchMissing: true)
        XCTAssertFalse(m.heartRateMissing)
        for t in 78...87 { m.update(time: Double(t), heartRate: nil, maxHR: 190, watchMissing: true) }
        XCTAssertFalse(m.heartRateMissing)
        for t in 88...95 { m.update(time: Double(t), heartRate: nil, maxHR: 190, watchMissing: true) }
        XCTAssertTrue(m.heartRateMissing)
        XCTAssertEqual(m.gapCount, 2)
        // Test vorbei (Ausrudern): Meldung weg
        m.update(time: 96, heartRate: nil, maxHR: 190, watchMissing: false)
        XCTAssertFalse(m.heartRateMissing)
    }

    func testHeartRateGapInSeriesAndStepEvaluationMarked() {
        let hr: [Int?] = (0..<100).map { $0 >= 30 && $0 < 50 ? nil : 120 }
        let samples = (0..<100).map { WorkoutSample(time: Double($0), distance: 0, pace: 120, strokeRate: 24, power: 150,
                                                    heartRate: hr[$0]) }
        let series = ThresholdSeries(samples: samples)
        XCTAssertEqual(series.longestHeartRateGap(from: 0, to: 100), 20, accuracy: 0.01)
        XCTAssertEqual(series.longestHeartRateGap(from: 0, to: 30), 0, accuracy: 0.01)
        XCTAssertEqual(series.longestHeartRateGap(from: 40, to: 45), 5, accuracy: 0.01)

        // Stufentest: 20 s Ausfall mitten in Stufe 2 → „Puls fehlt oder ist lückenhaft“, Auswertung bleibt möglich
        var phases = [WorkoutPhase(kind: .warmup, durationS: 600, powerPctMin: 35, powerPctMax: 45)]
        for _ in 0..<6 { phases.append(WorkoutPhase(kind: .work, durationS: 240, powerPctMin: 50, powerPctMax: 52, testRole: "step")) }
        phases.append(WorkoutPhase(kind: .cooldown, durationS: 300))
        let plan = WorkoutPlan(id: "schwelle-stufentest-puls", name: "Stufen", category: "Test", phases: phases,
                               test: PlanTestInfo(kind: "step-submax", requiresHeartRate: true, evaluator: .stepHR))
        var pw: [Double] = Array(repeating: 60, count: 600)
        var hrs: [Int?] = Array(repeating: 90, count: 600)
        var res = [PlanPhaseResult(index: 0, kind: "warmup", label: "", startTime: 0, endTime: 600, startDistance: 0,
                                   endDistance: 0, averageStrokeRate: nil, averageHeartRate: nil, completed: true)]
        for (i, p) in [80.0, 94, 108, 122, 136, 150].enumerated() {
            let start = Double(600 + i * 240)
            for s in 0..<240 {
                pw.append(p)
                hrs.append(i == 1 && s >= 60 && s < 80 ? nil : Int((60 + 0.5 * p).rounded()))
            }
            res.append(PlanPhaseResult(index: i + 1, kind: "work", label: "", startTime: start, endTime: start + 240,
                                       startDistance: 0, endDistance: 0, averageStrokeRate: nil, averageHeartRate: nil,
                                       completed: true))
        }
        let ride = ThresholdRideData(date: now, plan: plan,
                                     samples: pw.enumerated().map { i, p in
                                         WorkoutSample(time: Double(i), distance: 0, pace: ThresholdMath.pace(watts: p),
                                                       strokeRate: 24, power: Int(p), heartRate: hrs[i]) },
                                     phases: res)
        var profile = ThresholdProfile()
        profile.heart = HeartProfile(maxHR: 190, restHR: 55, lthr: 135)
        let ev = ThresholdEvaluator.evaluate(ride, profile: profile)
        XCTAssertTrue(ev?.notes.contains(.heartRateMissing) ?? false)
        XCTAssertEqual(ev?.estimate?.powerW ?? 0, 150, accuracy: 2)
        // ohne Ausfall kein Vermerk
        let full = ThresholdRideData(date: now, plan: plan,
                                     samples: ride.samples.map { var s = $0; s.heartRate = s.heartRate ?? 107; return s },
                                     phases: res)
        XCTAssertFalse(ThresholdEvaluator.evaluate(full, profile: profile)?.notes.contains(.heartRateMissing) ?? true)
    }

    // MARK: R4/R5 aus gespeicherten Fahrten

    /// 4 × 6 min Schwelle (2k +5..+8 s), Fahrt mit konstantem Tempo und Puls
    func thresholdRecord(pace: Double, heartRate: Int, score: Int? = nil, category: String = "Schwelle",
                         date: Date) -> (WorkoutRecord, WorkoutPlan) {
        var phases = [WorkoutPhase(kind: .warmup, durationS: 300)]
        for _ in 0..<4 {
            phases.append(WorkoutPhase(kind: .work, durationS: 360, paceOffsetMinS: 5, paceOffsetMaxS: 8))
            phases.append(WorkoutPhase(kind: .rest, durationS: 120))
        }
        phases.append(WorkoutPhase(kind: .cooldown, durationS: 300))
        let plan = WorkoutPlan(id: "schwelle-test-plan", name: "4 × 6", category: category, phases: phases)
        var samples: [WorkoutSample] = []
        var results: [PlanPhaseResult] = []
        var t = 0.0
        for (i, p) in phases.enumerated() {
            let d = p.durationS ?? 0
            let ph = p.kind == .work ? pace : 150
            for s in 0..<Int(d) {
                samples.append(WorkoutSample(time: t + Double(s), distance: 0, pace: ph, strokeRate: 22,
                                             power: Int(ThresholdMath.watts(pace: ph).rounded()),
                                             heartRate: p.kind == .work ? heartRate : 110))
            }
            results.append(PlanPhaseResult(index: i, kind: p.kind.rawValue, label: "", startTime: t, endTime: t + d,
                                           startDistance: 0, endDistance: 0, averageStrokeRate: 22,
                                           averageHeartRate: nil, completed: true))
            t += d
        }
        let header = WorkoutHeader(startDate: date, endDate: date.addingTimeInterval(t),
                                   device: WorkoutDevice(source: .pm5), workoutPlanId: plan.id)
        let summary = WorkoutSummary(distance: 6000, activeDuration: t, totalDuration: t, averagePace: pace,
                                     averageSpeed: 4, averageStrokeRate: 22, strokeCount: 500, averagePower: 180,
                                     maxPower: 250, calories: 300, averageHeartRate: nil, maxHeartRate: nil,
                                     heartRateZoneSeconds: nil, completedCourse: true, pauseCount: 0)
        let rec = WorkoutRecord(header: header, summary: summary, samples: samples, splits: [], planPhases: results,
                                effort: score.map { WorkoutEffort(userScore: $0) })
        return (rec, plan)
    }

    func testRetestRideRedShareAndPowerVsTarget() throws {
        let zones = HeartRateZones(percentMax: 190)
        // 2k 8:00 → 2:00 Basis, Ziel 2:05–2:08; gerudert 2:12 → zu langsam (> 2:08 + 3 s), rot
        let (slow, plan) = thresholdRecord(pace: 132, heartRate: 175, date: now)
        let s1 = try XCTUnwrap(RetestRide.make(record: slow, plan: plan)).session(best2k: 480, zones: zones)
        XCTAssertEqual(s1.redShare, 1, accuracy: 0.001)
        XCTAssertTrue(s1.isThreshold)
        // gleiche Fahrt, aber mit einer langsameren Referenz (8:20 → Basis 2:05, Ziel bis 2:13 + 3) nicht rot
        let s2 = try XCTUnwrap(RetestRide.make(record: slow, plan: plan)).session(best2k: 500, zones: zones)
        XCTAssertEqual(s2.redShare, 0, accuracy: 0.001)
        // schneller als das Ziel bei niedrigem Puls: Leistung > 105 %, Zone ≤ 3
        let (fast, _) = thresholdRecord(pace: 122, heartRate: 140, date: now)
        let s3 = try XCTUnwrap(RetestRide.make(record: fast, plan: plan)).session(best2k: 480, zones: zones)
        XCTAssertEqual(s3.redShare, 0, accuracy: 0.001)
        XCTAssertGreaterThan(s3.powerVsTargetPct ?? 0, 105)
        XCTAssertLessThanOrEqual(s3.maxZone ?? 9, 3)
        // andere Kategorien zählen nicht; Intervalle zählen, aber nicht als Schwelle
        let (g, gp) = thresholdRecord(pace: 132, heartRate: 150, category: "Grundlage", date: now)
        XCTAssertNil(RetestRide.make(record: g, plan: gp))
        let (iv, ip) = thresholdRecord(pace: 132, heartRate: 150, category: "Intervalle", date: now)
        XCTAssertEqual(RetestRide.make(record: iv, plan: ip)?.isThreshold, false)
        // Quantile: höchstens 100 Werte je Phase
        XCTAssertLessThanOrEqual(RetestRide.make(record: slow, plan: plan)?.phases.first?.slowExcess.count ?? 0, 100)
    }

    // MARK: Karten R3/R4/R5

    func d(_ i: Double) -> Date { now.addingTimeInterval(i * day) }

    func testReentryCardAfterPause() {
        let rides = [d(-40), d(-38), d(-6), d(-4), d(-2)]   // Pause 32 Tage, danach 3 Fahrten
        var input = ThresholdRetestCard.Input(rideDates: rides, sessions: [], activeDate: d(-60), lastTestDate: d(-60),
                                              planActive: false)
        XCTAssertEqual(ThresholdRetestCard.make(input, now: now),
                       ThresholdRetestCard(kind: .reentry, offerTest: true, testId: ThresholdRetest.submaxTest))
        // geschlossen → 14 Tage weg
        input.dismissed[.reentry] = d(-1)
        XCTAssertNil(ThresholdRetestCard.make(input, now: now))
        input.dismissed = [:]
        // mit Trainingsplan (eigener Wiedereinstieg) nie
        input.planActive = true
        XCTAssertNil(ThresholdRetestCard.make(input, now: now))
        input.planActive = false
        // Test vor weniger als 21 Tagen: kein Testvorschlag
        input.lastTestDate = d(-10)
        XCTAssertNil(ThresholdRetestCard.make(input, now: now))
        // 4. Fahrt nach der Pause: vorbei
        input.lastTestDate = nil
        input.rideDates.append(d(-1))
        XCTAssertNil(ThresholdRetestCard.make(input, now: now))
    }

    func testTargetCardsTooHardAndTooEasy() {
        let hard = [ThresholdRetest.Session(date: d(-6), redShare: 0.5),
                    ThresholdRetest.Session(date: d(-4), redShare: 0.1),
                    ThresholdRetest.Session(date: d(-2), redShare: 0.6)]
        var input = ThresholdRetestCard.Input(rideDates: hard.map(\.date), sessions: hard, activeDate: d(-30),
                                              lastTestDate: d(-30), planActive: false, preferredTest: "test-2000m")
        XCTAssertEqual(ThresholdRetestCard.make(input, now: now),
                       ThresholdRetestCard(kind: .tooHard, offerTest: true, testId: "test-2000m"))
        // Test vor 10 Tagen: R4 bleibt, aber nur mit „Schwelle −3 %“
        input.lastTestDate = d(-10)
        XCTAssertEqual(ThresholdRetestCard.make(input, now: now)?.offerTest, false)
        // neue Schwelle (z. B. −3 % übernommen) nach den Einheiten: nichts mehr
        input.activeDate = d(-1)
        XCTAssertNil(ThresholdRetestCard.make(input, now: now))
        input.activeDate = d(-30)
        // geschlossen: erst neue Einheiten zählen
        input.dismissed[.tooHard] = d(-1)
        XCTAssertNil(ThresholdRetestCard.make(input, now: now))
        // mit Trainingsplan nicht (der Plan verlangsamt die Ziele selbst)
        input.dismissed = [:]
        input.planActive = true
        XCTAssertNil(ThresholdRetestCard.make(input, now: now))

        let easy = (0..<4).map { ThresholdRetest.Session(date: d(Double(-8 + 2 * $0)), redShare: 0,
                                                          powerVsTargetPct: 108, maxZone: 3) }
        var e = ThresholdRetestCard.Input(rideDates: easy.map(\.date), sessions: easy, activeDate: d(-40),
                                          lastTestDate: d(-40), planActive: false)
        XCTAssertEqual(ThresholdRetestCard.make(e, now: now)?.kind, .tooEasy)
        // R5 ist ein reiner Testvorschlag: nicht innerhalb von 21 Tagen nach einem Test
        e.lastTestDate = d(-5)
        XCTAssertNil(ThresholdRetestCard.make(e, now: now))
    }

    // MARK: eine Rückfrage für Tests im Trainingsplan

    func testProgramReferenceLinkAsksOnlyOnce() {
        let w = UUID()
        func est(_ s: ThresholdEstimate.Status, notes: [EvaluationNote] = []) -> ThresholdEstimate {
            ThresholdEstimate(kind: .timeTrial, date: now, powerW: 160, sigmaPct: 5, workoutId: w, status: s, notes: notes)
        }
        XCTAssertEqual(ProgramReferenceLink.action(isWorse: true, linked: []), .askInPlan)
        XCTAssertEqual(ProgramReferenceLink.action(isWorse: false, linked: []), .apply)
        // Ergebniskarte fragt („übernehmen oder behalten?“): der Plan schweigt
        XCTAssertEqual(ProgramReferenceLink.action(isWorse: true, linked: [est(.candidate)]), .waitForProfile)
        // beantwortet: übernommen oder behalten → Rückfrage im Plan erledigt
        XCTAssertEqual(ProgramReferenceLink.action(isWorse: true, linked: [est(.active)]), .resolve)
        XCTAssertEqual(ProgramReferenceLink.action(isWorse: true, linked: [est(.rejected)]), .resolve)
        // nur Hinweis (z. B. unterbrochen): nicht übernehmen, nicht fragen
        XCTAssertEqual(ProgramReferenceLink.action(isWorse: true, linked: [est(.candidate, notes: [.interrupted])]), .resolve)
        XCTAssertEqual(ProgramReferenceLink.action(isWorse: false, linked: [est(.candidate, notes: [.interrupted])]), .resolve)
    }

    // MARK: Wiedereinstieg

    func testReentryUsesFifteenMinuteSteadyState() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("RowCoach/Resources/plans.json")
        let plans = try WorkoutPlanCatalog.load(url: url)
        XCTAssertEqual(ReentryRule.shortPlan(plans: plans), "grundlage-locker-15")
        let p = try XCTUnwrap(plans.first { $0.id == "grundlage-locker-15" })
        XCTAssertEqual(ReentryRule.minutes(of: p), 15)
        XCTAssertEqual(p.categoryID, "Grundlage")
        XCTAssertTrue(p.phases.allSatisfy { ($0.hrZone ?? 0) <= 2 })
    }
}
