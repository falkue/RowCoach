import XCTest
@testable import RowCoachKit

/// Schwellenprofil, Tests und Zonen (docs/schwelle/SPEC.md, Abschnitt 11: Sollwerte)
final class ThresholdTests: XCTestCase {
    let b = 0.15
    let day: TimeInterval = 86400
    let now = Date(timeIntervalSince1970: 1_795_000_000)

    // MARK: Hilfen

    /// Zeitreihe 1 Hz ab `start` mit Leistung je Sekunde (und optional Puls)
    func samples(start: Double = 0, power: [Double], heartRate: [Int?]? = nil, spm: Int = 24) -> [WorkoutSample] {
        var out: [WorkoutSample] = []
        var d = 0.0
        for (i, p) in power.enumerated() {
            let pace = p > 0 ? ThresholdMath.pace(watts: p) : 0
            d += pace > 0 ? 500 / pace : 0
            out.append(WorkoutSample(time: start + Double(i), distance: d, pace: pace, strokeRate: p > 0 ? spm : 0,
                                     power: Int(p.rounded()), heartRate: heartRate?[i]))
        }
        return out
    }

    func result(_ index: Int, kind: String = "work", start: Double, end: Double, completed: Bool = true) -> PlanPhaseResult {
        PlanPhaseResult(index: index, kind: kind, label: "", startTime: start, endTime: end, startDistance: 0,
                        endDistance: 0, averageStrokeRate: nil, averageHeartRate: nil, completed: completed)
    }

    /// Bundle-unabhängiger Pfad zu plans.json
    var plansURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("RowCoach/Resources/plans.json")
    }

    // MARK: ThresholdMath

    func testMathReferenceValues() {
        XCTAssertEqual(ThresholdMath.watts(pace: 120), 202.5, accuracy: 0.05)
        XCTAssertEqual(ThresholdMath.pace(watts: 202.5), 120.0, accuracy: 0.05)
        let t = ThresholdMath.threshold(fromBest2k: 480, b: b)
        XCTAssertEqual(t, 166.1, accuracy: 0.05)
        XCTAssertEqual(ThresholdMath.pace(watts: t), 128.2, accuracy: 0.05)   // 2:08,2/500 m
        XCTAssertEqual(ThresholdMath.equivalentBest2k(threshold: t, b: b), 480.0, accuracy: 0.1)
        XCTAssertEqual(ThresholdMath.equivalentBest2k(threshold: 200, b: b), 449.7, accuracy: 0.1)
        XCTAssertEqual(ThresholdMath.thresholdFactor(duration: 1200, b: b), 0.941, accuracy: 0.0005)
        XCTAssertEqual(ThresholdMath.thresholdFactor(duration: 1800, b: b), 1.000, accuracy: 0.0005)
        XCTAssertEqual(ThresholdMath.thresholdFactor(duration: 3600, b: b), 1.110, accuracy: 0.0005)
        XCTAssertEqual(ThresholdMath.thresholdFactor(duration: 240, b: b), 0.739, accuracy: 0.0005)
        XCTAssertEqual(ThresholdMath.thresholdFactor(duration: 600, b: b), 0.848, accuracy: 0.0005)
        // 2k 6:40 → 0,80 × P2k; 8:00 → 0,82 × P2k
        XCTAssertEqual(ThresholdMath.thresholdFactor(duration: 400, b: b), 0.80, accuracy: 0.005)
        XCTAssertEqual(ThresholdMath.thresholdFactor(duration: 480, b: b), 0.82, accuracy: 0.005)
        XCTAssertEqual(ThresholdMath.exponent(powerA: 300, durationA: 180, powerB: 300 * pow(10, -0.15), durationB: 1800)!,
                       0.15, accuracy: 1e-9)
    }

    // MARK: Zonen

    func testPowerZonesAtReferenceThreshold() {
        let t = ThresholdMath.threshold(fromBest2k: 480, b: b)
        let bands = TrainingZones.bands(threshold: t)
        XCTAssertEqual(bands.count, 5)
        XCTAssertEqual(bands[1].slowPace!, 156.5, accuracy: 0.1)   // Zone 2 ab 2:36,5
        XCTAssertEqual(bands[2].slowPace!, 141.1, accuracy: 0.1)   // Zone 3 ab 2:21,1
        XCTAssertEqual(bands[3].slowPace!, 133.8, accuracy: 0.1)   // Zone 4 ab 2:13,8
        XCTAssertEqual(bands[4].slowPace!, 127.4, accuracy: 0.1)   // Zone 5 ab 2:07,4
        XCTAssertNil(bands[0].slowPace)
        XCTAssertNil(bands[4].fastPace)
        XCTAssertEqual(bands[3].lowerW!, 0.88 * t, accuracy: 1e-9)
        XCTAssertEqual(TrainingZones.zone(power: 0.9 * t, threshold: t), 4)
        XCTAssertEqual(TrainingZones.zone(power: 0.5 * t, threshold: t), 1)
        XCTAssertEqual(TrainingZones.zone(power: 1.2 * t, threshold: t), 5)
    }

    func testHeartRateZoneModels() {
        let lthr = HeartRateZones(lthr: 160)
        XCTAssertEqual(lthr.lowerBound(zone: 1), 112)
        XCTAssertEqual(lthr.lowerBound(zone: 4), 150)
        XCTAssertEqual(lthr.lowerBound(zone: 5), 160)
        XCTAssertEqual(lthr.zone(for: 100), 0)
        let pm = HeartRateZones(percentMax: 190)
        XCTAssertEqual(pm.lowerBound(zone: 3), 133)
        // Karvonen unverändert
        let k = HeartRateZones(maxHR: 185, restHR: 55)
        XCTAssertEqual(k.lowerBound(zone: 4), 159)
        // altes JSON ohne Modell
        let old = try! JSONDecoder().decode(HeartRateZones.self, from: Data(#"{"maxHR":185,"restHR":55}"#.utf8))
        XCTAssertEqual(old, k)
        let rt = try! JSONDecoder().decode(HeartRateZones.self, from: JSONEncoder().encode(lthr))
        XCTAssertEqual(rt, lthr)
        // automatische Wahl
        var h = HeartProfile(maxHR: 190, restHR: 50)
        XCTAssertEqual(TrainingZones.heartZones(h, now: now).source, .reserve)
        h.lthr = 165
        XCTAssertEqual(TrainingZones.heartZones(h, now: now).source, .lthr)
        h.lthrDate = now.addingTimeInterval(-400 * day)
        XCTAssertEqual(TrainingZones.heartZones(h, now: now).source, .reserve, "LTHR älter als 12 Monate")
        XCTAssertEqual(TrainingZones.heartZones(HeartProfile(), now: now).source, .estimated)
        XCTAssertEqual(TrainingZones.heartZones(HeartProfile(maxHR: 180), now: now).source, .percentMax)
    }

    // MARK: Stufentest mit Puls

    func stepPlan(steps: Int) -> WorkoutPlan {
        var phases = [WorkoutPhase(kind: .warmup, durationS: 600, powerPctMin: 35, powerPctMax: 45)]
        for _ in 0..<steps {
            phases.append(WorkoutPhase(kind: .work, durationS: 240, powerPctMin: 50, powerPctMax: 52, testRole: "step"))
        }
        phases.append(WorkoutPhase(kind: .cooldown, durationS: 300))
        return WorkoutPlan(id: "schwelle-stufentest-puls", name: "Stufen", category: "Test", phases: phases,
                           test: PlanTestInfo(kind: "step-submax", requiresHeartRate: true, evaluator: .stepHR))
    }

    func stepRide(powers: [Double], noise: Bool = true) -> ThresholdRideData {
        var pw: [Double] = Array(repeating: 60, count: 600)
        var hr: [Int?] = Array(repeating: 90, count: 600)
        var res: [PlanPhaseResult] = [result(0, kind: "warmup", start: 0, end: 600)]
        for (i, p) in powers.enumerated() {
            let start = Double(600 + i * 240)
            for s in 0..<240 {
                let n = noise ? Double((s * 7 + i * 3) % 3) - 1 : 0
                pw.append(p)
                hr.append(Int((60 + 0.5 * p + n).rounded()))
            }
            res.append(result(i + 1, start: start, end: start + 240))
        }
        return ThresholdRideData(date: now, plan: stepPlan(steps: powers.count),
                                 samples: samples(power: pw, heartRate: hr), phases: res)
    }

    func testStepHRRegressionMeetsTarget() {
        var profile = ThresholdProfile()
        profile.heart = HeartProfile(maxHR: 190, restHR: 55, lthr: 135)
        let ride = stepRide(powers: [80, 94, 108, 122, 136, 150])
        let ev = ThresholdEvaluator.evaluate(ride, profile: profile)!
        let e = try! XCTUnwrap(ev.estimate)
        XCTAssertEqual(e.source, .stepHR)
        XCTAssertEqual(e.powerW, 150, accuracy: 2)
        XCTAssertFalse(e.isHintOnly)
        XCTAssertEqual(ev.heartRateLine!.slope, 0.5, accuracy: 0.05)
        XCTAssertEqual(e.sigmaPct, 9 + 2, accuracy: 0.01, "LTHR bekannt 9 %, erster Test +2 %")
    }

    func testStepHRTooFewSteps() {
        var profile = ThresholdProfile()
        profile.heart = HeartProfile(maxHR: 190, restHR: 55, lthr: 135)
        let ev = ThresholdEvaluator.evaluate(stepRide(powers: [80, 94]), profile: profile)!
        XCTAssertNil(ev.estimate)
        XCTAssertTrue(ev.notes.contains(.notEvaluable))
    }

    func testStepHRExtrapolatedTooFarIsHintOnly() {
        var profile = ThresholdProfile()
        profile.heart = HeartProfile(maxHR: 190, restHR: 55, lthr: 155)   // 20 bpm über der höchsten Stufe (135)
        let ev = ThresholdEvaluator.evaluate(stepRide(powers: [80, 94, 108, 122, 136, 150]), profile: profile)!
        let e = try! XCTUnwrap(ev.estimate)
        XCTAssertTrue(e.isHintOnly)
        XCTAssertTrue(ev.notes.contains(.extrapolatedTooFar))
        XCTAssertEqual(ThresholdSelector.decide(e, profile: profile), .hintOnly)
    }

    func testStepHRWithoutLTHRUsesReserve() {
        var profile = ThresholdProfile()
        profile.heart = HeartProfile(maxHR: 145, restHR: 55)   // HR_T = 55 + 0,85 · 90 = 131,5
        let e = ThresholdEvaluator.evaluate(stepRide(powers: [80, 94, 108, 122, 136, 150]), profile: profile)!.estimate!
        XCTAssertEqual(e.powerW, (131.5 - 60) / 0.5, accuracy: 3)
        XCTAssertEqual(e.sigmaPct, 12 + 2, accuracy: 0.01)
    }

    // MARK: DFA-α1

    struct LCG {
        var state: UInt64
        mutating func uniform() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(UInt64(1) << 53)
        }
        mutating func gaussian() -> Double {
            let u1 = max(uniform(), 1e-12), u2 = uniform()
            return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
        }
    }

    func testDFAAlpha1OnSyntheticNoise() {
        var g = LCG(state: 42)
        let white = (0..<4000).map { _ in g.gaussian() }
        XCTAssertEqual(DFAAlpha1.alpha1(white)!, 0.5, accuracy: 0.1)
        var acc = 0.0
        let brown = white.map { v -> Double in acc += v; return acc }
        XCTAssertEqual(DFAAlpha1.alpha1(brown)!, 1.5, accuracy: 0.1)
        // 1/f-Rauschen durch spektrale Synthese (Amplitude ~ f^(−1/2))
        let n = 2048
        var pink = [Double](repeating: 0, count: n)
        for f in 1...(n / 2) {
            let amp = 1 / sqrt(Double(f)), phase = 2 * .pi * g.uniform()
            let w = 2 * .pi * Double(f) / Double(n)
            for k in 0..<n { pink[k] += amp * cos(w * Double(k) + phase) }
        }
        XCTAssertEqual(DFAAlpha1.alpha1(pink)!, 1.0, accuracy: 0.1)
    }

    func testDFAWindowsDropArtifacts() {
        var g = LCG(state: 7)
        var rr = (0..<450).map { _ in 0.8 + 0.02 * g.gaussian() }
        // in den ersten 150 Schlägen jeder 8. ein Ausreisser (12,5 % Artefakte)
        for i in stride(from: 0, to: 150, by: 8) { rr[i] = 1.6 }
        let w = DFAAlpha1.windows(rr: rr)
        XCTAssertFalse(w.isEmpty)
        XCTAssertTrue(w.allSatisfy { $0.start >= 60 }, "Fenster mit > 5 % Artefakten verworfen")
        XCTAssertTrue(w.contains { $0.start < 150 }, "Fenster mit wenigen Artefakten bleiben")
        let (clean, art) = DFAAlpha1.clean(rr)
        XCTAssertTrue(art[8])
        XCTAssertEqual(clean[8], 0.8, accuracy: 0.1)
    }

    // MARK: Rampe

    func testRampEvaluationAndFailureDetector() {
        let t0 = 162.0
        var phases = [WorkoutPhase(kind: .warmup, durationS: 300)]
        for k in 0..<23 {
            let pct = 50 + 5 * Double(k)
            phases.append(WorkoutPhase(kind: .work, durationS: 60, powerPctMin: pct - 1, powerPctMax: pct + 1,
                                       endOnFailure: true, testRole: "ramp"))
        }
        phases.append(WorkoutPhase(kind: .cooldown, durationS: 600))
        let plan = WorkoutPlan(id: "schwelle-rampentest", name: "Rampe", category: "Test", phases: phases,
                               test: PlanTestInfo(kind: "ramp", allOut: true, evaluator: .ramp))
        var pw: [Double] = Array(repeating: 70, count: 300)
        var detector = RampFailureDetector()
        var failAt: Int?
        var res = [result(0, kind: "warmup", start: 0, end: 300)]
        // Minuten 1–19 (bis 140 %) gehalten, dann 80 % des Ziels
        outer: for k in 0..<23 {
            let target = t0 * (50 + 5 * Double(k)) / 100
            let start = 300 + k * 60
            for s in 0..<60 {
                let p = k < 19 ? target : 0.8 * target
                pw.append(p)
                if detector.update(time: Double(start + s), power: p, target: target, step: k + 1, strokeRate: 24) {
                    failAt = start + s
                    res.append(result(k + 1, start: Double(start), end: Double(start + s), completed: false))
                    break outer
                }
            }
            res.append(result(k + 1, start: Double(start), end: Double(start + 60)))
        }
        let fail = try! XCTUnwrap(failAt)
        // gleitender 15-s-Mittelwert fällt nach etwa 6 s unter 90 % des Ziels, dann 15 s am Stück
        XCTAssertEqual(Double(fail - (300 + 19 * 60)), 21, accuracy: 3, "Abbruch nach 15 s unter 90 %")
        let ride = ThresholdRideData(date: now, plan: plan, samples: samples(power: pw), phases: res)
        let ev = ThresholdEvaluator.evaluate(ride, profile: ThresholdProfile())!
        let e = try! XCTUnwrap(ev.estimate)
        XCTAssertEqual(e.details["map"]!, 1.40 * t0, accuracy: 0.6)
        XCTAssertEqual(e.powerW, 0.75 * e.details["map"]!, accuracy: 1e-6)
        XCTAssertFalse(e.isHintOnly)

        // zu kurze Rampe (5 Minuten) → nur Hinweis, nächste Rampe tiefer
        let short = ThresholdRideData(date: now, plan: plan, samples: samples(power: Array(pw.prefix(600))),
                                      phases: Array(res.prefix(6)))
        let ev2 = ThresholdEvaluator.evaluate(short, profile: ThresholdProfile())!
        XCTAssertTrue(ev2.notes.contains(.rampTooShort))
        XCTAssertTrue(ev2.estimate!.isHintOnly)
        XCTAssertEqual(ev2.rampStartAdjust, -1)
    }

    // MARK: 3 min All-out

    func allOutRide(_ power: (Int) -> Double) -> ThresholdRideData {
        let plan = WorkoutPlan(id: "schwelle-test-3min", name: "3 min", category: "Test",
                               phases: [WorkoutPhase(kind: .warmup, durationS: 60),
                                        WorkoutPhase(kind: .work, durationS: 180, allOut: true, testRole: "allOut3min"),
                                        WorkoutPhase(kind: .cooldown, durationS: 60)],
                               test: PlanTestInfo(kind: "cp-3min", allOut: true, evaluator: .allOut3min))
        let pw = Array(repeating: 100.0, count: 60) + (0..<180).map(power) + Array(repeating: 80.0, count: 60)
        return ThresholdRideData(date: now, plan: plan, samples: samples(power: pw),
                                 phases: [result(0, kind: "warmup", start: 0, end: 60), result(1, start: 60, end: 240),
                                          result(2, kind: "cooldown", start: 240, end: 300)])
    }

    func testAllOut3min() {
        let ep = 250.0
        // Spitze 1,6 × EP, fällt bis 135 s auf das Plateau
        let good = allOutRide { s in s < 30 ? 1.6 * ep : (s < 135 ? ep * (1.6 - 0.6 * Double(s - 30) / 105) : ep) }
        let e = ThresholdEvaluator.evaluate(good, profile: ThresholdProfile())!.estimate!
        XCTAssertEqual(e.powerW, 0.88 * ep, accuracy: 0.5)
        XCTAssertFalse(e.isHintOnly)
        XCTAssertEqual(e.sigmaPct, 8 + 2, accuracy: 0.01)
        // gleichmässig eingeteilt → nicht all-out, nie automatisch aktiv
        let even = ThresholdEvaluator.evaluate(allOutRide { _ in 280 }, profile: ThresholdProfile())!
        XCTAssertTrue(even.notes.contains(.notAllOut))
        XCTAssertTrue(even.estimate!.isHintOnly)
        XCTAssertEqual(ThresholdSelector.decide(even.estimate!, profile: ThresholdProfile.migrated(best2k: 480, maxHR: nil, restHR: nil, now: now)), .hintOnly)
    }

    // MARK: Zeitfahren

    func ttPlan(minutes: Double) -> WorkoutPlan {
        WorkoutPlan(id: "schwelle-test-20min", name: "20", category: "Test",
                    phases: [WorkoutPhase(kind: .warmup, durationS: 60),
                             WorkoutPhase(kind: .work, durationS: minutes * 60, allOut: true, testRole: "timeTrial"),
                             WorkoutPhase(kind: .cooldown, durationS: 60)],
                    test: PlanTestInfo(kind: "tt-20min", allOut: true, evaluator: .timeTrial))
    }

    func testTimeTrial20minAndPacingNote() {
        let len = 1200
        let even = ThresholdRideData(date: now, plan: ttPlan(minutes: 20),
                                     samples: samples(power: Array(repeating: 100.0, count: 60) + Array(repeating: 200.0, count: len)
                                                      + Array(repeating: 90.0, count: 60)),
                                     phases: [result(0, kind: "warmup", start: 0, end: 60), result(1, start: 60, end: 1260),
                                              result(2, kind: "cooldown", start: 1260, end: 1320)])
        let ev = ThresholdEvaluator.evaluate(even, profile: ThresholdProfile())!
        XCTAssertEqual(ev.estimate!.powerW, 200 * 0.941, accuracy: 0.1)
        XCTAssertEqual(ev.estimate!.sigmaPct, 4 + 2, accuracy: 0.01)
        XCTAssertTrue(ev.notes.isEmpty)
        // erste 5 min > 1,08 × Rest
        let fast = (0..<len).map { $0 < 300 ? 230.0 : 195.0 }
        let ride2 = ThresholdRideData(date: now, plan: ttPlan(minutes: 20),
                                      samples: samples(power: Array(repeating: 100.0, count: 60) + fast),
                                      phases: [result(0, kind: "warmup", start: 0, end: 60), result(1, start: 60, end: 1260)])
        let ev2 = ThresholdEvaluator.evaluate(ride2, profile: ThresholdProfile())!
        XCTAssertTrue(ev2.notes.contains(.tooFastStart))
        XCTAssertFalse(ev2.estimate!.isHintOnly)
        // Unterbrechung > 15 s → ungültig
        var broken = Array(repeating: 200.0, count: len)
        for i in 500..<520 { broken[i] = 0 }
        let ride3 = ThresholdRideData(date: now, plan: ttPlan(minutes: 20),
                                      samples: samples(power: Array(repeating: 100.0, count: 60) + broken),
                                      phases: [result(0, kind: "warmup", start: 0, end: 60), result(1, start: 60, end: 1260)])
        let ev3 = ThresholdEvaluator.evaluate(ride3, profile: ThresholdProfile())!
        XCTAssertNil(ev3.estimate)
        XCTAssertEqual(ev3.notes, [.interrupted])
    }

    func testThirtyMinuteTestGivesLTHR() {
        let plan = WorkoutPlan(id: "test-30min", name: "30", category: "Test",
                               phases: [WorkoutPhase(kind: .work, durationS: 1800)],
                               test: PlanTestInfo(kind: "tt-30min", allOut: true, evaluator: .timeTrial))
        let hr: [Int?] = (0..<1800).map { $0 < 600 ? 150 : 165 }
        let ride = ThresholdRideData(date: now, plan: plan, samples: samples(power: Array(repeating: 180, count: 1800), heartRate: hr),
                                     phases: [result(0, start: 0, end: 1800)])
        let ev = ThresholdEvaluator.evaluate(ride, profile: ThresholdProfile())!
        XCTAssertEqual(ev.estimate!.powerW, 180, accuracy: 0.01)
        XCTAssertEqual(ev.lthrSuggestion, 165)
        XCTAssertEqual(ev.estimate!.sigmaPct, 3 + 2, accuracy: 0.01)
    }

    func testShortTestIsBestMarkOnly() {
        let plan = WorkoutPlan(id: "test-500m", name: "500", category: "Test",
                               phases: [WorkoutPhase(kind: .work, distanceM: 500)])
        let ride = ThresholdRideData(date: now, plan: plan, samples: samples(power: Array(repeating: 350, count: 95)),
                                     phases: [result(0, start: 0, end: 95)])
        let ev = ThresholdEvaluator.evaluate(ride, profile: ThresholdProfile())!
        XCTAssertNil(ev.estimate)
        XCTAssertTrue(ev.bestMarkOnly)
    }

    // MARK: Auswahl

    func testSelectorRules() {
        var p = ThresholdProfile()
        let manual = ThresholdEstimate(kind: .manualPower, date: now.addingTimeInterval(-10 * day), powerW: 160, sigmaPct: 4)
        p.insert(manual)
        p.activate(id: manual.id)
        // Eingabe wird nie abgelöst
        let test = ThresholdEstimate(kind: .timeTrial, date: now, powerW: 171, sigmaPct: 3)
        XCTAssertEqual(ThresholdSelector.decide(test, profile: p), .ask(changePct: (171 - 160) / 160 * 100))
        ThresholdSelector.submit(test, to: &p)
        XCTAssertEqual(p.active?.id, manual.id)
        XCTAssertEqual(p.estimate(id: test.id)?.statusValue, .candidate)

        // Test höher als ein Altwert → sofort aktiv
        var q = ThresholdProfile.migrated(best2k: 480, maxHR: 185, restHR: 55, now: now.addingTimeInterval(-30 * day))
        let higher = ThresholdEstimate(kind: .timeTrial, date: now, powerW: 175, sigmaPct: 3)
        if case .adopt = ThresholdSelector.submit(higher, to: &q) {} else { XCTFail("höher → aktiv") }
        XCTAssertEqual(q.active?.id, higher.id)
        XCTAssertEqual(q.estimates.first { $0.source == .legacy2k }?.statusValue, .superseded)
        // Test niedriger um mehr als 3 % → Rückfrage
        let lower = ThresholdEstimate(kind: .timeTrial, date: now, powerW: 160, sigmaPct: 3)
        if case .ask = ThresholdSelector.submit(lower, to: &q) {} else { XCTFail("niedriger → Rückfrage") }
        XCTAssertEqual(q.active?.id, higher.id)
        // Vorschlag bei aktiver Eingabe: Test um ≥ 1 Prozentpunkt sicherer und > 3 % Abweichung
        var r = p
        r.estimates = r.estimates.map { var e = $0; if e.id == test.id { e.status = "superseded" }; return e }
        XCTAssertEqual(ThresholdSelector.proposal(r, now: now)?.estimate.id, test.id)
    }

    func testSigmaAging() {
        let e = ThresholdEstimate(kind: .timeTrial, date: now, powerW: 170, sigmaPct: 3)
        XCTAssertEqual(ThresholdSelector.sigma(e, now: now), 3)
        XCTAssertEqual(ThresholdSelector.sigma(e, now: now.addingTimeInterval(41 * day)), 3)
        XCTAssertEqual(ThresholdSelector.sigma(e, now: now.addingTimeInterval(42 * day)), 3.5)    // Woche 7
        XCTAssertEqual(ThresholdSelector.sigma(e, now: now.addingTimeInterval(56 * day)), 4.5)    // Woche 9
        XCTAssertEqual(ThresholdSelector.sigma(e, now: now.addingTimeInterval(400 * day)), 15)    // Deckel
        XCTAssertEqual(ThresholdSelector.sigma(e, now: now, pauseDays: 14), 6)
        XCTAssertEqual(ThresholdConfidence(sigma: 4), .high)
        XCTAssertEqual(ThresholdConfidence(sigma: 8), .medium)
        XCTAssertEqual(ThresholdConfidence(sigma: 8.5), .low)
    }

    func testExponentCalibration() {
        var p = ThresholdProfile()
        // 2000 m (420 s) und 30 min mit b = 0,12
        let p30 = 200.0, p2k = p30 * pow(420.0 / 1800, -0.12)
        p.insert(ThresholdEstimate(kind: .timeTrial, date: now, powerW: p30, sigmaPct: 3, details: ["p": p30, "t": 1800]))
        p.insert(ThresholdEstimate(kind: .timeTrial, date: now.addingTimeInterval(-20 * day), powerW: 190, sigmaPct: 6,
                                   details: ["p": p2k, "t": 420]))
        XCTAssertEqual(ThresholdSelector.calibratedExponent(p)!, 0.12, accuracy: 1e-6)
        ThresholdSelector.applyCalibration(&p)
        XCTAssertEqual(p.exponentBSource, "calibrated")
        XCTAssertNotNil(ThresholdSelector.enduranceProfile(p))
    }

    // MARK: Fahrten

    func testDetectorTimeTrialCandidate() {
        let ride = ThresholdDetector.Ride(date: now.addingTimeInterval(-2 * day),
                                          samples: samples(power: Array(repeating: 175, count: 1440)), userScore: 8)
        let c = try! XCTUnwrap(ThresholdDetector.candidate(rides: [ride], now: now, b: b))
        XCTAssertEqual(c.estimate.powerW, 175 * pow(1440.0 / 1800, 0.15), accuracy: 0.1)
        XCTAssertEqual(c.estimate.powerW, 169.2, accuracy: 0.1)
        XCTAssertEqual(c.estimate.source, .ridesAuto)
        // ohne Maximalitätsmerkmal kein Kandidat
        let plain = ThresholdDetector.Ride(date: ride.date, samples: ride.samples, userScore: 5)
        XCTAssertNil(ThresholdDetector.candidate(rides: [plain], now: now, b: b))
        // Vorschlag nur, wenn ≥ 3 % und ≥ 5 W über der aktiven Schwelle
        var p = ThresholdProfile.migrated(best2k: 480, maxHR: nil, restHR: nil, now: now)   // T = 166,1
        XCTAssertNil(ThresholdDetector.proposal(c, profile: p, now: now), "169,2 < 166,1 · 1,03")
        p = ThresholdProfile.migrated(best2k: 500, maxHR: nil, restHR: nil, now: now)
        XCTAssertNotNil(ThresholdDetector.proposal(c, profile: p, now: now))
        p.lastRideProposalDate = now.addingTimeInterval(-3 * day)
        XCTAssertNil(ThresholdDetector.proposal(c, profile: p, now: now), "höchstens ein Vorschlag je 7 Tage")
    }

    func testCriticalPowerFromTwoEfforts() {
        let r = try! XCTUnwrap(ThresholdDetector.criticalPower([(180, 300), (720, 230)]))
        XCTAssertEqual(r.cp, 206.7, accuracy: 0.05)
        XCTAssertEqual(r.wPrime / 1000, 16.8, accuracy: 0.05)
        XCTAssertEqual(0.88 * r.cp, 181.9, accuracy: 0.05)
        XCTAssertNil(ThresholdDetector.criticalPower([(180, 300), (720, 290)]), "W′ unplausibel")
    }

    func testMaxMeanPowerTwoPointer() {
        let s = ThresholdSeries(samples: samples(power: Array(repeating: 100, count: 300) + Array(repeating: 200, count: 180)
                                                 + Array(repeating: 100, count: 300)))
        let m = try! XCTUnwrap(s.maxMeanPower(duration: 180))
        XCTAssertEqual(m.power, 200, accuracy: 0.01)
        XCTAssertEqual(m.start, 300, accuracy: 0.01)
        XCTAssertEqual(s.maxMeanPower(duration: 360)!.power, 150, accuracy: 0.01)
    }

    // MARK: Migration und Programme

    func testMigrationMirrorsBest2kExactly() {
        let p = ThresholdProfile.migrated(best2k: 455, maxHR: 190, restHR: 50, now: now)
        XCTAssertEqual(p.mirrorBest2k!, 455.0, accuracy: 0.1)
        XCTAssertEqual(p.active?.source, .legacy2k)
        XCTAssertEqual(p.active?.sigmaPct, 6)
        XCTAssertEqual(p.heart.maxHR, 190)
        let d = ThresholdProfile.migrated(best2k: nil, maxHR: nil, restHR: nil, now: now)
        XCTAssertEqual(d.active?.sigmaPct, 15)
        XCTAssertEqual(d.mirrorBest2k, 480)
        // Rundreise über JSON
        XCTAssertEqual(ThresholdProfile.decode(p.encoded()), p)
        // eine Fremdart aus einer neueren Version bleibt lesbar
        let future = #"{"version":1,"estimates":[{"id":"\#(UUID().uuidString)","kind":"lab","date":1795000000,"powerW":170,"sigmaPct":3,"status":"active"}],"heart":{},"exponentB":0.15,"rampFactor":0.75}"#
        let f = try! XCTUnwrap(ThresholdProfile.decode(Data(future.utf8)))
        XCTAssertNil(f.active?.source)
        XCTAssertEqual(f.thresholdW, 170)
    }

    func testProgramTargetsUnchangedAndNewTestsDecode() throws {
        let plans = try WorkoutPlanCatalog.load(url: plansURL)
        XCTAssertGreaterThanOrEqual(plans.count, 115)
        // alle Programme ohne Phasen in % der Schwelle: Tempo wie bisher 2k-Tempo + Offset
        for best2k in [400.0, 455, 480, 540] {
            let base = best2k / 4
            for plan in plans {
                for ph in plan.phases where ph.powerPctRange == nil {
                    guard let a = ph.paceOffsetMinS ?? ph.paceOffsetMaxS else { XCTAssertNil(ph.paceRange(best2k: best2k)); continue }
                    let c = ph.paceOffsetMaxS ?? a
                    XCTAssertEqual(ph.paceRange(best2k: best2k), (base + min(a, c))...(base + max(a, c)), plan.id)
                }
            }
        }
        for id in ["schwelle-stufentest-puls", "schwelle-test-20min", "schwelle-test-3min", "schwelle-rampentest"] {
            let p = try XCTUnwrap(plans.first { $0.id == id }, id)
            XCTAssertNotNil(p.test, id)
            XCTAssertNotNil(ThresholdEvaluator.evaluator(for: p), id)
        }
        XCTAssertEqual(plans.first { $0.id == "schwelle-rampentest" }?.phases.filter { $0.testRole == "ramp" }.count, 23)
        XCTAssertEqual(plans.first { $0.id == "test-2000m" }?.test?.evaluatorKind, .timeTrial)
        XCTAssertEqual(plans.first { $0.id == "stufentest-7x4" }?.test?.evaluatorKind, .stepHR)
        // Stufen in % der Schwelle: bei 2k 8:00 (T = 166,1 W) ≈ Referenz-Offsets aus der JSON (±1,5 s)
        let step = plans.first { $0.id == "schwelle-stufentest-puls" }!.phases[1]
        let r = try XCTUnwrap(step.paceRange(best2k: 480))
        XCTAssertEqual(r.lowerBound, 120 + step.paceOffsetMinS!, accuracy: 1.5)
        XCTAssertEqual(r.upperBound, 120 + step.paceOffsetMaxS!, accuracy: 1.5)
        // „alte Version“: ohne die neuen Felder bleiben gültige Phasen mit Tempozielen
        var raw = try JSONSerialization.jsonObject(with: Data(contentsOf: plansURL)) as! [[String: Any]]
        raw = raw.filter { ($0["id"] as? String)?.hasPrefix("schwelle-test") == true || $0["id"] as? String == "schwelle-rampentest"
            || $0["id"] as? String == "schwelle-stufentest-puls" }
        for i in raw.indices {
            raw[i]["test"] = nil
            raw[i]["phases"] = (raw[i]["phases"] as! [[String: Any]]).map { ph -> [String: Any] in
                var q = ph
                for k in ["powerPctMin", "powerPctMax", "allOut", "endOnFailure", "testRole"] { q[k] = nil }
                return q
            }
        }
        let old = try WorkoutPlanCatalog.decode(JSONSerialization.data(withJSONObject: raw))
        XCTAssertEqual(old.count, 4)
        for p in old { XCTAssertTrue(p.phases.contains { $0.kind == .work }) }
    }

    func testEstimateBest2kPowerLaw() {
        let w30 = WorkoutPlan(id: "test-30min", name: "30", category: "Test", phases: [WorkoutPhase(kind: .work, durationS: 1800)])
        // 30 min mit 2:10/500 m → 2k ≈ 8:07,1 (Paul's Law ergab 8:04,2)
        let est = TrainingProgramEngine.estimateBest2k(ride: ProgramRide(start: now, workPace: 130), plan: w30, b: 0.15)!
        XCTAssertEqual(est, 487.1, accuracy: 0.15)
        let w2k = WorkoutPlan(id: "test-2000m", name: "2k", category: "Test", phases: [WorkoutPhase(kind: .work, distanceM: 2000)])
        XCTAssertEqual(TrainingProgramEngine.estimateBest2k(ride: ProgramRide(start: now, workPace: 115), plan: w2k), 460)
        let step = stepPlan(steps: 6)
        XCTAssertNil(TrainingProgramEngine.estimateBest2k(ride: ProgramRide(start: now, workPace: 140), plan: step))
    }

    // MARK: Plan und Tagesvorschlag

    func testPlanEngineEndTestPartJumpsToCooldown() {
        var phases = [WorkoutPhase(kind: .warmup, durationS: 60)]
        for _ in 0..<5 { phases.append(WorkoutPhase(kind: .work, durationS: 60, endOnFailure: true, testRole: "ramp")) }
        phases.append(WorkoutPhase(kind: .cooldown, durationS: 120))
        var e = PlanEngine(plan: WorkoutPlan(id: "r", name: "r", phases: phases))
        e.update(activeTime: 0, elapsedTime: 0, distance: 0, speed: 4)
        XCTAssertFalse(e.endTestPart(), "Einrudern ist kein Testteil")
        e.update(activeTime: 150, elapsedTime: 150, distance: 600, speed: 4)
        XCTAssertEqual(e.index, 2)
        XCTAssertTrue(e.endTestPart())
        XCTAssertEqual(e.index, 6)
        XCTAssertEqual(e.status.phase?.kind, .cooldown)
        XCTAssertEqual(e.boundaries.count, 6)
        let st = e.update(activeTime: 280, elapsedTime: 280, distance: 1100, speed: 4)
        XCTAssertTrue(st.finished)
    }

    func testDailySuggestionThresholdTestDue() {
        typealias F = StatsFixture
        let plans = F.plans + [WorkoutPlan(id: "schwelle-test-20min", name: "20", category: "Test",
                                           phases: [WorkoutPhase(kind: .work, durationS: 1200, hrZone: 5)])]
        let regular = stride(from: 2, through: 35, by: 3).map { F.easy(F.ago($0), course: F.courseIds[$0 % 5]) }
        func suggest(_ s: [TrainingSession], _ th: ThresholdRetestInput) -> DailySuggestion {
            DailySuggestion.make(sessions: s, plans: plans, courseIds: F.courseIds, now: F.now, calendar: F.cal,
                                 best2k: 480, threshold: th)
        }
        // Schwelle 9 Wochen alt → bevorzugter Test
        let old = ThresholdRetestInput(activeDate: F.ago(63), sigma: 5, preferredTest: "schwelle-test-20min")
        let s = suggest(regular, old)
        XCTAssertEqual(s.rule, .test)
        XCTAssertEqual(s.planId, "schwelle-test-20min")
        XCTAssertTrue(s.reason.contains("Schwellentest fällig"))
        // frische Schwelle → kein Test
        let fresh = ThresholdRetestInput(activeDate: F.ago(10), sigma: 4, preferredTest: "schwelle-test-20min")
        XCTAssertNotEqual(suggest(regular, fresh).rule, .test)
        // unsicher (σ > 8 %) → Test, aber nicht innerhalb von 21 Tagen nach dem letzten Test
        let unsure = ThresholdRetestInput(activeDate: F.ago(10), sigma: 9, preferredTest: "schwelle-test-20min")
        XCTAssertEqual(suggest(regular, unsure).rule, .test)
        let withTest = regular + [F.session(F.ago(12), plan: "test-2000m", zones: [0, 0, 2, 2, 4, 0])]
        XCTAssertNotEqual(suggest(withTest, unsure).rule, .test)
    }

    func testPreferredTestByProfile() {
        var p = ThresholdProfile()
        XCTAssertEqual(ThresholdRetest.preferredTest(profile: p, hasHeartRateStrap: true, isBeginner: true, tested2k: false, now: now),
                       "schwelle-stufentest-puls")
        XCTAssertEqual(ThresholdRetest.preferredTest(profile: p, hasHeartRateStrap: true, isBeginner: false, tested2k: true, now: now),
                       "test-2000m")
        XCTAssertEqual(ThresholdRetest.preferredTest(profile: p, hasHeartRateStrap: false, isBeginner: false, tested2k: false, now: now),
                       "schwelle-test-20min")
        p.healthScreen = HealthScreen(answeredAt: now, answers: ["heart": true])
        XCTAssertEqual(ThresholdRetest.preferredTest(profile: p, hasHeartRateStrap: false, isBeginner: false, tested2k: true, now: now),
                       "schwelle-stufentest-puls", "Gesundheitsfrage mit Ja: nur submaximal")
        p.healthScreen?.clearanceDate = now
        XCTAssertFalse(p.healthScreen!.blocksMaximalTests)
    }

    func testRetestHints() {
        let d = { (i: Int) in self.now.addingTimeInterval(Double(i) * self.day) }
        XCTAssertEqual(ThresholdRetest.targetHint([ThresholdRetest.Session(date: d(0), redShare: 0.5),
                                                   ThresholdRetest.Session(date: d(2), redShare: 0.1),
                                                   ThresholdRetest.Session(date: d(4), redShare: 0.1, userScore: 9)]), .tooHard)
        let easy = (0..<4).map { ThresholdRetest.Session(date: d($0), redShare: 0, powerVsTargetPct: 108, maxZone: 3) }
        XCTAssertEqual(ThresholdRetest.targetHint(easy), .tooEasy)
        XCTAssertTrue(ThresholdRetest.reentryTestDue(rideDates: [d(0), d(20), d(22), d(24)]))
        XCTAssertFalse(ThresholdRetest.reentryTestDue(rideDates: [d(0), d(20), d(22)]))
    }
}

/// Sprachcoach in den Schwellentests (docs/schwelle/SPEC.md 10)
final class ThresholdCoachTests: XCTestCase {
    private let bank = CoachTestPhrases.bank

    private func replay(_ plan: WorkoutPlan) -> CoachReplay.Result {
        let samples = RideSim.samples(plan: plan) { RideSim.onTarget($0.phase) }
        return CoachReplay.run(samples: samples, plan: plan, settings: CoachSettings(), phrases: bank, seed: 3)
    }

    private func count(_ r: CoachReplay.Result, _ s: CoachScenario) -> [CoachReplay.Entry] {
        r.entries.filter { $0.utterance.scenario == s }
    }

    func testStepTestCoachIsInformativeOnly() {
        var phases = [WorkoutPhase(kind: .warmup, durationS: 600, spmMin: 18, spmMax: 22, hrZone: 1)]
        for (i, pct) in [50.0, 60, 70, 80, 88, 95].enumerated() {
            phases.append(WorkoutPhase(kind: .work, durationS: 240, spmMin: 18, spmMax: 24, hrZone: i < 4 ? 2 : 4,
                                       powerPctMin: pct - 2, powerPctMax: pct + 2, testRole: "step"))
        }
        phases.append(WorkoutPhase(kind: .cooldown, durationS: 300, spmMin: 16, spmMax: 20, hrZone: 1))
        let plan = WorkoutPlan(id: "schwelle-stufentest-puls", name: "Stufen", category: "Test", phases: phases,
                               test: PlanTestInfo(kind: "step-submax", requiresHeartRate: true, evaluator: .stepHR))
        let r = replay(plan)
        XCTAssertEqual(count(r, .testIntro).map(\.utterance.level), [1])
        XCTAssertEqual(count(r, .testStepNext).count, 6, r.log)
        XCTAssertEqual(count(r, .testTalkCheck).count, 5, r.log)
        XCTAssertEqual(count(r, .testResult).count, 1)
        let motivation: [CoachScenario] = [.fadeEnd, .fadeMid, .paceOnTarget, .go, .lastInterval, .last30s, .prepHard]
        XCTAssertTrue(r.entries.allSatisfy { e in !(e.utterance.scenario.map(motivation.contains) ?? false) }, r.log)
    }

    func testAllOutAndRampCoach() {
        let allOut = WorkoutPlan(id: "schwelle-test-3min", name: "3", category: "Test",
                                 phases: [WorkoutPhase(kind: .warmup, durationS: 120, spmMin: 18, spmMax: 24, hrZone: 2),
                                          WorkoutPhase(kind: .work, durationS: 180, spmMin: 28, spmMax: 40, hrZone: 5,
                                                       allOut: true, testRole: "allOut3min"),
                                          WorkoutPhase(kind: .cooldown, durationS: 300, hrZone: 1)],
                                 test: PlanTestInfo(kind: "cp-3min", allOut: true, evaluator: .allOut3min))
        let r = replay(allOut)
        XCTAssertEqual(count(r, .testAllOutGo).count, 1, r.log)
        XCTAssertEqual(count(r, .go).count, 0)
        let enc = count(r, .testAllOutEncourage)
        XCTAssertGreaterThanOrEqual(enc.count, 5, r.log)
        for (a, b) in zip(enc, enc.dropFirst()) { XCTAssertGreaterThanOrEqual(b.utterance.time - a.utterance.time, 20) }
        XCTAssertEqual(enc.last?.utterance.level, 2)
        XCTAssertEqual(count(r, .testIntro).first?.utterance.level, 2)

        var phases = [WorkoutPhase(kind: .warmup, durationS: 120)]
        for k in 0..<8 {
            let pct = 50 + 5 * Double(k)
            phases.append(WorkoutPhase(kind: .work, durationS: 60, spmMin: 20, spmMax: 28, hrZone: 2,
                                       powerPctMin: pct - 1, powerPctMax: pct + 1, endOnFailure: true, testRole: "ramp"))
        }
        phases.append(WorkoutPhase(kind: .cooldown, durationS: 300, hrZone: 1))
        let ramp = WorkoutPlan(id: "schwelle-rampentest", name: "R", category: "Test", phases: phases,
                               test: PlanTestInfo(kind: "ramp", allOut: true, evaluator: .ramp))
        let rr = replay(ramp)
        XCTAssertEqual(count(rr, .testRampNext).count, 8, rr.log)
        XCTAssertEqual(count(rr, .testRampEnd).count, 1, rr.log)
    }
}
