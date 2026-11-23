import XCTest
@testable import RowCoachKit

final class EffortTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let maxHR = 185
    /// 2000 m in 8:00 → Tempo der Bestzeit 2:00 /500 m
    private let best2k: Double = 480

    /// Abschnitte zu 1-Hz-Messpunkten: (Sekunden, Puls oder nil, Tempo s/500 m; 0 = Stillstand)
    private func samples(_ segments: [(Int, Int?, Double)]) -> [WorkoutSample] {
        var out: [WorkoutSample] = []
        var t = 0.0, d = 0.0
        for (secs, hr, pace) in segments {
            for _ in 0..<secs {
                out.append(WorkoutSample(time: t, distance: d, pace: pace, strokeRate: pace > 0 ? 22 : 0,
                                         power: pace > 0 ? 150 : 0, heartRate: hr))
                t += 1
                if pace > 0 { d += 500 / pace }
            }
        }
        return out
    }

    private func record(_ s: [WorkoutSample], effort: WorkoutEffort? = nil) -> WorkoutRecord {
        let header = WorkoutHeader(startDate: t0, endDate: t0.addingTimeInterval(s.last?.time ?? 0),
                                   device: WorkoutDevice(source: .pm5))
        let summary = WorkoutSummary(distance: s.last?.distance ?? 0, activeDuration: 60, totalDuration: 60,
                                     averagePace: 120, averageSpeed: 4, averageStrokeRate: 22, strokeCount: 20,
                                     averagePower: 150, maxPower: 200, calories: 10, averageHeartRate: nil,
                                     maxHeartRate: nil, heartRateZoneSeconds: nil, completedCourse: true, pauseCount: 0)
        return WorkoutRecord(header: header, summary: summary, samples: s, splits: [], effort: effort)
    }

    /// 8 × 500 m hart: 10 min einrudern, je 500 m in 2:03 (Puls 160 → 172), 2 min Pause im Stillstand
    /// (Puls 155 → 140), 5 min ausrudern
    private var intervals8x500: [WorkoutSample] {
        var seg: [(Int, Int?, Double)] = [(600, 125, 145)]
        for _ in 0..<8 { seg += [(40, 160, 123), (70, 172, 123), (60, 155, 0), (60, 140, 0)] }
        seg += [(300, 120, 155)]
        return samples(seg)
    }

    // MARK: Gewichte

    func testEdwardsBands() {
        XCTAssertEqual(EffortEstimator.heartRateWeight(bpm: 90, maxHR: 185), 0)    // 49 %
        XCTAssertEqual(EffortEstimator.heartRateWeight(bpm: 100, maxHR: 185), 1)   // 54 %
        XCTAssertEqual(EffortEstimator.heartRateWeight(bpm: 120, maxHR: 185), 2)   // 65 %
        XCTAssertEqual(EffortEstimator.heartRateWeight(bpm: 140, maxHR: 185), 3)   // 76 %
        XCTAssertEqual(EffortEstimator.heartRateWeight(bpm: 152, maxHR: 185), 4)   // 82 %
        XCTAssertEqual(EffortEstimator.heartRateWeight(bpm: 172, maxHR: 185), 5)   // 93 %
        XCTAssertEqual(EffortEstimator.heartRateWeight(bpm: 150, maxHR: 0), 0)
    }

    func testPaceWeights() {
        XCTAssertEqual(EffortEstimator.paceWeight(pace: 121, best2k: best2k), 5)
        XCTAssertEqual(EffortEstimator.paceWeight(pace: 130, best2k: best2k), 4)
        XCTAssertEqual(EffortEstimator.paceWeight(pace: 142, best2k: best2k), 3)
        XCTAssertEqual(EffortEstimator.paceWeight(pace: 155, best2k: best2k), 2)
        XCTAssertEqual(EffortEstimator.paceWeight(pace: 175, best2k: best2k), 1)
        XCTAssertEqual(EffortEstimator.paceWeight(pace: 0, best2k: best2k), 0)
    }

    // MARK: Beispiele

    func testTwentyMinutesZone2IsEasyToModerate() throws {
        // Zone 2 bei 185/55: 133–145 bpm
        let e = try XCTUnwrap(EffortEstimator.estimate(samples: samples([(1200, 140, 142)]), maxHR: maxHR, best2k: best2k))
        XCTAssertEqual(e.basis, .heartRate)
        XCTAssertTrue((3...4).contains(e.score), "20 min Zone 2 → \(e.score)")
        XCTAssertEqual(e.trimp, 60, accuracy: 0.5)
        XCTAssertEqual(e.intensity, 3, accuracy: 1e-9)
    }

    func testIntervals8x500HardIsHard() throws {
        let e = try XCTUnwrap(EffortEstimator.estimate(samples: intervals8x500, maxHR: maxHR, best2k: best2k))
        XCTAssertEqual(e.basis, .heartRate)
        XCTAssertEqual(e.score, 8)
        XCTAssertEqual(EffortScale.level(e.score), .hard)
    }

    func testLongEasyRowStaysModerate() throws {
        let e = try XCTUnwrap(EffortEstimator.estimate(samples: samples([(3600, 140, 142)]), maxHR: maxHR, best2k: best2k))
        XCTAssertEqual(e.score, 5)
    }

    func testThirtyMinutesZone3() throws {
        let e = try XCTUnwrap(EffortEstimator.estimate(samples: samples([(1800, 152, 135)]), maxHR: maxHR, best2k: best2k))
        XCTAssertEqual(e.score, 6)
    }

    func testTwoKTest() throws {
        let s = samples([(600, 125, 150), (90, 160, 121), (330, 172, 120), (600, 125, 155)])
        let e = try XCTUnwrap(EffortEstimator.estimate(samples: s, maxHR: maxHR, best2k: best2k))
        XCTAssertEqual(e.score, 7)
    }

    func testWithoutHeartRateUsesPace() throws {
        let e = try XCTUnwrap(EffortEstimator.estimate(samples: samples([(1200, nil, 142)]), maxHR: maxHR, best2k: best2k))
        XCTAssertEqual(e.basis, .pace)
        XCTAssertEqual(e.score, 3)
        // Intervalle ohne Puls: nur Tempo
        let noHR = intervals8x500.map { s -> WorkoutSample in var c = s; c.heartRate = nil; return c }
        let p = try XCTUnwrap(EffortEstimator.estimate(samples: noHR, maxHR: maxHR, best2k: best2k))
        XCTAssertEqual(p.basis, .pace)
        XCTAssertEqual(p.score, 8)
    }

    func testPaceIsFloorWhenHeartRateLags() throws {
        // Hart gerudert (Tempo der Bestzeit), aber der Puls bleibt niedrig (z. B. Gurt verrutscht): Tempo − 1 zählt
        let e = try XCTUnwrap(EffortEstimator.estimate(samples: samples([(600, 120, 145), (600, 125, 121)]),
                                                       maxHR: maxHR, best2k: best2k))
        let byPace = try XCTUnwrap(EffortEstimator.paceEstimate(samples: samples([(600, 120, 145), (600, 125, 121)]),
                                                                best2k: best2k))
        XCTAssertEqual(e.basis, .heartRate)
        XCTAssertEqual(e.score, byPace.score - 1)
    }

    func testTooLittleHeartRateFallsBackToPace() throws {
        let s = samples([(300, 140, 142), (900, nil, 142)])
        let e = try XCTUnwrap(EffortEstimator.estimate(samples: s, maxHR: maxHR, best2k: best2k))
        XCTAssertEqual(e.basis, .pace)
    }

    func testPlanOnly() throws {
        var phases = [WorkoutPhase(kind: .warmup, durationS: 600, hrZone: 1)]
        for _ in 0..<8 {
            phases.append(WorkoutPhase(kind: .work, distanceM: 500, paceOffsetMinS: 2, paceOffsetMaxS: 4))
            phases.append(WorkoutPhase(kind: .rest, durationS: 120, activeRest: true))
        }
        phases.append(WorkoutPhase(kind: .cooldown, durationS: 300))
        let plan = WorkoutPlan(id: "8x500", name: "8 × 500 m", phases: phases)
        let e = try XCTUnwrap(EffortEstimator.planEstimate(plan, best2k: best2k))
        XCTAssertEqual(e.basis, .plan)
        XCTAssertEqual(e.score, 8)
        // Ohne Messwerte gilt das Programm
        let fromRecord = try XCTUnwrap(EffortEstimator.estimate(samples: [], maxHR: maxHR, best2k: best2k, plan: plan))
        XCTAssertEqual(fromRecord, e)
    }

    func testNoDataGivesNil() {
        XCTAssertNil(EffortEstimator.estimate(samples: [], maxHR: maxHR, best2k: best2k))
        XCTAssertNil(EffortEstimator.estimate(samples: samples([(60, nil, 0)]), maxHR: maxHR, best2k: best2k))
    }

    func testScoreIsCappedOneToTen() throws {
        let tiny = try XCTUnwrap(EffortEstimator.score(slices: [.init(seconds: 30, weight: 1)], basis: .pace))
        XCTAssertEqual(tiny.score, 1)
        let huge = try XCTUnwrap(EffortEstimator.score(slices: [.init(seconds: 4 * 3600, weight: 5)], basis: .heartRate))
        XCTAssertEqual(huge.score, 10)
    }

    // MARK: Skala und Speichern

    func testScaleLevels() {
        XCTAssertEqual(EffortScale.level(1), .easy)
        XCTAssertEqual(EffortScale.level(3), .easy)
        XCTAssertEqual(EffortScale.level(4), .moderate)
        XCTAssertEqual(EffortScale.level(6), .moderate)
        XCTAssertEqual(EffortScale.level(7), .hard)
        XCTAssertEqual(EffortScale.level(8), .hard)
        XCTAssertEqual(EffortScale.level(9), .allOut)
        XCTAssertEqual(EffortScale.level(10), .allOut)
        XCTAssertEqual(EffortScale.level(12), .allOut)
        XCTAssertEqual(EffortScale.label(7), "7 · hart")
    }

    func testEnsureEstimateKeepsExistingAndUserScore() throws {
        var rec = record(samples([(1200, 140, 142)]))
        XCTAssertNil(rec.effort)
        rec.ensureEffortEstimate(maxHR: maxHR, best2k: best2k)
        XCTAssertEqual(rec.effort?.estimate, 3)
        XCTAssertEqual(rec.effort?.basis, .heartRate)
        rec.setUserEffort(7, at: t0)
        rec.effort?.estimate = 5
        rec.ensureEffortEstimate(maxHR: maxHR, best2k: best2k)
        XCTAssertEqual(rec.effort?.estimate, 5)
        XCTAssertEqual(rec.effort?.userScore, 7)
        rec.setUserEffort(15)
        XCTAssertEqual(rec.effort?.userScore, 10)
    }

    func testRoundTripAndOldJSONWithoutEffort() throws {
        var rec = record(samples([(10, 140, 142)]))
        rec.setUserEffort(6, at: t0)
        let back = try WorkoutRecord(jsonData: rec.jsonData())
        XCTAssertEqual(back, rec)
        XCTAssertEqual(back.effort?.userScore, 6)

        // Älteres JSON ohne Feld „effort“ lädt weiter
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: rec.jsonData()) as? [String: Any])
        obj.removeValue(forKey: "effort")
        let old = try WorkoutRecord(jsonData: JSONSerialization.data(withJSONObject: obj))
        XCTAssertNil(old.effort)

        // Unbekannte Grundlage stört nicht
        let eff = try JSONDecoder().decode(WorkoutEffort.self, from: Data(#"{"estimate":4,"estimateBasis":"neu"}"#.utf8))
        XCTAssertEqual(eff.estimate, 4)
        XCTAssertNil(eff.basis)
    }
}
