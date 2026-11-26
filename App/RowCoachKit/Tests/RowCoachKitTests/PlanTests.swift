import XCTest
@testable import RowCoachKit

final class WorkoutPlanDecodingTests: XCTestCase {
    /// Beispiel im Format der Recherche (docs/trainings-recherche.json), mit Stolpersteinen
    private let sample = """
    [
      {"id": "intervalle", "name": "2 × 500 m", "summary": "Kurz", "purpose": "Tempo", "level": "Fortgeschritten",
       "extra": {"egal": true},
       "sources": [{"title": "Concept2", "publisher": "Concept2", "url": "https://www.concept2.com", "published": 2024,
                    "zotero": null}],
       "phases": [
         {"kind": "warmup", "durationS": 300, "spmMin": 18, "spmMax": 22, "hrZone": 2, "label": "Einrudern"},
         {"kind": "work", "distanceM": 500, "spmMin": "26", "spmMax": 30, "paceOffsetMinS": -2, "paceOffsetMaxS": 2,
          "hrZone": "4-5", "label": "Belastung 1/2"},
         {"kind": "rest", "durationS": 60, "activeRest": true, "label": "Pause"},
         {"kind": "work", "durationS": null, "distanceM": 500, "label": "Belastung 2/2"},
         {"kind": "sprint", "durationS": 30, "label": "Unbekannte Art"},
         {"kind": "cooldown", "label": "ohne Länge"},
         {"kind": "cooldown", "durationS": 240}
       ]},
      {"name": "ohne id", "phases": [{"kind": "work", "durationS": 60}]},
      {"id": "leer", "name": "ohne Phasen", "phases": []},
      {"id": "intervalle", "name": "doppelt", "phases": [{"kind": "work", "durationS": 60}]}
    ]
    """

    func testDecodeSample() throws {
        let plans = try WorkoutPlanCatalog.decode(Data(sample.utf8))
        XCTAssertEqual(plans.map(\.id), ["intervalle"])
        let p = try XCTUnwrap(plans.first)
        XCTAssertEqual(p.name, "2 × 500 m")
        XCTAssertEqual(p.level, "Fortgeschritten")
        XCTAssertEqual(p.sources.count, 1)
        XCTAssertEqual(p.sources[0].published, "2024")
        XCTAssertNil(p.sources[0].zotero)
        // Phase ohne Länge fällt weg
        XCTAssertEqual(p.phases.count, 6)
        XCTAssertEqual(p.phases.map(\.kind), [.warmup, .work, .rest, .work, .other, .cooldown])
        XCTAssertEqual(p.phases[0].durationS, 300)
        XCTAssertNil(p.phases[0].distanceM)
        XCTAssertEqual(p.phases[1].distanceM, 500)
        XCTAssertNil(p.phases[1].durationS)
        XCTAssertEqual(p.phases[1].spmRange, 26...30)
        XCTAssertEqual(p.phases[1].hrZone, 4)
        XCTAssertEqual(p.phases[2].activeRest, true)
        XCTAssertTrue(p.phases[2].countsWallTime)
        XCTAssertEqual(p.phases[5].title, "Ausrudern")
        XCTAssertNil(p.totalDuration)
        XCTAssertNil(p.totalDistance)
        XCTAssertEqual(p.workCount, 2)
    }

    func testDecodeWrapperAndRoundTrip() throws {
        let json = """
        {"note": "vorläufig", "plans": [{"id": "a", "name": "A", "phases": [{"kind": "work", "durationS": 1200}]}]}
        """
        let plans = try WorkoutPlanCatalog.decode(Data(json.utf8))
        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans[0].totalDuration, 1200)
        let again = try WorkoutPlanCatalog.decode(JSONEncoder().encode(plans))
        XCTAssertEqual(again, plans)
    }

    func testPaceRangeFromBest2k() {
        let ph = WorkoutPhase(kind: .work, durationS: 60, paceOffsetMinS: 15, paceOffsetMaxS: 10)
        // 8:00 → 2:00/500 m; Bereich 2:10–2:15 (schnell…langsam)
        let r = ph.paceRange(best2k: 480)
        XCTAssertEqual(r?.lowerBound ?? 0, 130, accuracy: 1e-9)
        XCTAssertEqual(r?.upperBound ?? 0, 135, accuracy: 1e-9)
        XCTAssertNil(WorkoutPhase(kind: .work, durationS: 60).paceRange(best2k: 480))
        XCTAssertEqual(PlanFormat.paceRange(r!), "2:10–2:15")
        XCTAssertEqual(PlanFormat.duration(1200), "20 min")
        XCTAssertEqual(PlanFormat.duration(90), "1:30 min")
        XCTAssertEqual(PlanFormat.duration(45), "45 s")
    }

    func testTargetLights() {
        XCTAssertEqual(TargetLight.strokeRate(20, target: 18...22), .green)
        XCTAssertEqual(TargetLight.strokeRate(24, target: 18...22), .yellow)
        XCTAssertEqual(TargetLight.strokeRate(26, target: 18...22), .red)
        XCTAssertEqual(TargetLight.strokeRate(0, target: 18...22), .none)
        XCTAssertEqual(TargetLight.strokeRate(20, target: nil), .none)
        XCTAssertEqual(TargetLight.pace(132, target: 130...135), .green)
        XCTAssertEqual(TargetLight.pace(128, target: 130...135), .yellow)
        XCTAssertEqual(TargetLight.pace(140, target: 130...135), .red)
        XCTAssertEqual(TargetLight.heartRate(zone: 3, target: 2), .yellow)
        XCTAssertEqual(TargetLight.heartRate(zone: nil, target: 2), .none)
    }

    /// Die mitgelieferte plans.json (Kopie von docs/trainings-recherche.json) muss vollständig lesbar sein.
    func testBundledPlansFileDecodes() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("RowCoach/Resources/plans.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("plans.json nicht gefunden: \(url.path)")
        }
        let data = try Data(contentsOf: url)
        let plans = try WorkoutPlanCatalog.decode(data)
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [Any])
        XCTAssertEqual(plans.count, raw.count, "kein Programm darf beim Dekodieren wegfallen")
        XCTAssertEqual(Set(plans.map(\.id)).count, plans.count, "ids eindeutig")
        for p in plans where !p.tags.isEmpty {
            XCTAssertTrue(Set(p.tags).isSubset(of: PlanTag.all), "\(p.id): unbekannter Tag \(Set(p.tags).subtracting(PlanTag.all))")
            XCTAssertEqual(p.tags.filter { PlanTag.intensities.contains($0) }.count, 1, "\(p.id): genau eine Intensität")
        }
        for p in plans {
            XCTAssertFalse(p.phases.isEmpty, p.id)
            XCTAssertFalse(p.sources.isEmpty, "\(p.id) ohne Quellen")
            XCTAssertFalse(p.phases.contains { $0.kind == .other }, "\(p.id): unbekannte Phasenart")
        }
    }
}

final class PlanEngineTests: XCTestCase {
    /// 60 s Einrudern, 500 m Belastung, 60 s Pause im Stillstand, 100 m Ausrudern
    private let plan = WorkoutPlan(id: "t", name: "Test", phases: [
        WorkoutPhase(kind: .warmup, durationS: 60),
        WorkoutPhase(kind: .work, distanceM: 500),
        WorkoutPhase(kind: .rest, durationS: 60, activeRest: false),
        WorkoutPhase(kind: .cooldown, distanceM: 100),
    ])

    /// Fährt mit konstanter Geschwindigkeit; Ruderzeit und Uhrzeit laufen gleich
    private struct Ride {
        var active = 0.0, elapsed = 0.0, distance = 0.0
        mutating func row(_ engine: inout PlanEngine, seconds: Double, speed: Double, step: Double = 0.5) -> PlanStatus {
            var s = engine.status
            var t = 0.0
            while t < seconds - 1e-9 {
                active += step; elapsed += step; distance += speed * step; t += step
                s = engine.update(activeTime: active, elapsedTime: elapsed, distance: distance, speed: speed)
            }
            return s
        }
        /// Stillstand: nur die Uhr läuft
        mutating func stand(_ engine: inout PlanEngine, seconds: Double, step: Double = 0.5) -> PlanStatus {
            var s = engine.status
            var t = 0.0
            while t < seconds - 1e-9 {
                elapsed += step; t += step
                s = engine.update(activeTime: active, elapsedTime: elapsed, distance: distance, speed: 0)
            }
            return s
        }
    }

    func testTimePhaseChangeAndCountdown() {
        var e = PlanEngine(plan: plan)
        var ride = Ride()
        var s = ride.row(&e, seconds: 30, speed: 4)
        XCTAssertEqual(s.phaseIndex, 0)
        XCTAssertEqual(s.phaseProgress, 0.5, accuracy: 1e-9)
        XCTAssertEqual(s.remainingTime ?? -1, 30, accuracy: 1e-9)
        XCTAssertFalse(s.countdownActive)
        XCTAssertEqual(s.nextPhase?.kind, .work)
        // Tor vorausberechnet: 120 m + 30 s × 4 m/s
        XCTAssertEqual(s.nextChangeDistance ?? 0, 240, accuracy: 1e-6)
        XCTAssertFalse(s.nextChangeIsExact)
        s = ride.row(&e, seconds: 21, speed: 4)
        XCTAssertTrue(s.countdownActive)
        XCTAssertEqual(s.secondsToChange ?? 0, 9, accuracy: 1e-9)
        s = ride.row(&e, seconds: 9, speed: 4)
        XCTAssertEqual(s.phaseIndex, 1)
        XCTAssertFalse(s.countdownActive)
        XCTAssertEqual(e.phaseStartDistance, 240, accuracy: 1e-6)
        XCTAssertEqual(e.boundaries.count, 1)
    }

    func testDistancePhaseGateAndCountdown() {
        var e = PlanEngine(plan: plan)
        var ride = Ride()
        _ = ride.row(&e, seconds: 60, speed: 4)            // Einrudern vorbei, 240 m
        var s = ride.row(&e, seconds: 100, speed: 4)        // 640 m
        XCTAssertEqual(s.phaseIndex, 1)
        XCTAssertEqual(s.remainingDistance ?? 0, 100, accuracy: 1e-6)
        XCTAssertEqual(s.nextChangeDistance ?? 0, 740, accuracy: 1e-6)
        XCTAssertTrue(s.nextChangeIsExact)
        XCTAssertFalse(s.countdownActive)
        s = ride.row(&e, seconds: 16, speed: 4)             // 704 m: noch 36 m = 9 s
        XCTAssertTrue(s.countdownActive)
        XCTAssertEqual(s.secondsToChange ?? 0, 9, accuracy: 1e-6)
        s = ride.row(&e, seconds: 9, speed: 4)              // 740 m
        XCTAssertEqual(s.phaseIndex, 2)
        XCTAssertEqual(e.phaseStartDistance, 740, accuracy: 1e-6)
    }

    func testRestRunsOnWallClockAndWorkWaitsWhenPaused() {
        var e = PlanEngine(plan: plan)
        var ride = Ride()
        _ = ride.row(&e, seconds: 30, speed: 4)
        // Anhalten im Einrudern: Phase wartet
        var s = ride.stand(&e, seconds: 20)
        XCTAssertEqual(s.phaseIndex, 0)
        XCTAssertEqual(s.remainingTime ?? 0, 30, accuracy: 1e-9)
        _ = ride.row(&e, seconds: 30, speed: 4)             // Ende Einrudern
        _ = ride.row(&e, seconds: 125, speed: 4)            // 500 m Belastung
        s = e.status
        XCTAssertEqual(s.phaseIndex, 2)
        // Pause im Stillstand läuft nach der Uhr ab
        s = ride.stand(&e, seconds: 59.5)
        XCTAssertEqual(s.phaseIndex, 2)
        s = ride.stand(&e, seconds: 0.5)
        XCTAssertEqual(s.phaseIndex, 3)
        // Ausrudern 100 m, dann fertig
        s = ride.row(&e, seconds: 25, speed: 4)
        XCTAssertTrue(s.finished)
        XCTAssertFalse(s.countdownActive)
        XCTAssertNil(s.nextChangeDistance)
        XCTAssertEqual(s.overallProgress, 1, accuracy: 1e-9)
        XCTAssertEqual(e.boundaries.count, 4)
    }

    func testPhaseResults() {
        let samples = (0...120).map { t in
            WorkoutSample(time: Double(t), distance: Double(t) * 4, pace: 125, strokeRate: t < 60 ? 20 : 30,
                          power: 180, heartRate: t < 60 ? 120 : 150)
        }
        let marks = [PlanPhaseMark(index: 0, startTime: 0, startDistance: 0),
                     PlanPhaseMark(index: 1, startTime: 60, startDistance: 240)]
        let r = PlanPhaseResult.compute(plan: plan, marks: marks, samples: samples, endTime: 120, endDistance: 480,
                                        planFinished: false)
        XCTAssertEqual(r.count, 2)
        XCTAssertEqual(r[0].duration, 60, accuracy: 1e-9)
        XCTAssertEqual(r[0].distance, 240, accuracy: 1e-9)
        XCTAssertEqual(r[0].averageStrokeRate ?? 0, 20, accuracy: 1e-9)
        XCTAssertEqual(r[0].averageHeartRate, 120)
        XCTAssertTrue(r[0].completed)
        XCTAssertEqual(r[1].averageStrokeRate ?? 0, 30, accuracy: 1e-9)
        XCTAssertFalse(r[1].completed)
        XCTAssertEqual(r[1].phaseKind, .work)
        XCTAssertEqual(r[1].averagePace ?? 0, 125, accuracy: 1e-9)
    }

    func testOverallProgressGrows() {
        var e = PlanEngine(plan: plan)
        var ride = Ride()
        var last = -1.0
        for _ in 0..<40 {
            let s = ride.row(&e, seconds: 5, speed: 4)
            XCTAssertGreaterThanOrEqual(s.overallProgress, last)
            last = s.overallProgress
        }
        XCTAssertEqual(e.phaseShares.reduce(0, +), 1, accuracy: 1e-9)
    }

    func testSeveralPhasesInOneUpdate() {
        var e = PlanEngine(plan: WorkoutPlan(id: "k", name: "kurz", phases: [
            WorkoutPhase(kind: .work, durationS: 1), WorkoutPhase(kind: .work, durationS: 1),
            WorkoutPhase(kind: .work, durationS: 10),
        ]))
        let s = e.update(activeTime: 3, elapsedTime: 3, distance: 12, speed: 4)
        XCTAssertEqual(s.phaseIndex, 2)
        XCTAssertEqual(s.remainingTime ?? 0, 9, accuracy: 1e-9)
        XCTAssertEqual(e.boundaries.count, 2)
        XCTAssertEqual(e.boundaries[0].endDistance, 4, accuracy: 1e-9)
        XCTAssertEqual(e.boundaries[1].endDistance, 8, accuracy: 1e-9)
    }
}

final class LapTests: XCTestCase {
    private let track = CourseTrack(course: .straight(oneWay: 1000))

    func testSplit() {
        XCTAssertEqual(Laps.split(distance: 0, lapLength: 2000).lap, 0)
        XCTAssertEqual(Laps.split(distance: 1999, lapLength: 2000).lap, 0)
        let b = Laps.split(distance: 2000, lapLength: 2000)
        XCTAssertEqual(b.lap, 1)
        XCTAssertEqual(b.distanceInLap, 0, accuracy: 1e-9)
        let c = Laps.split(distance: 4500, lapLength: 2000)
        XCTAssertEqual(c.lap, 2)
        XCTAssertEqual(c.distanceInLap, 500, accuracy: 1e-9)
        XCTAssertEqual(Laps.split(distance: 300, lapLength: 0).distanceInLap, 300)
    }

    func testFirstLapMatchesTrackAndLaterLapsRepeat() {
        let laps = LapTrack(track: track)
        for d in [0.0, 100, 999, 1500, 1900] {
            let a = laps.pose(atDistance: d), b = track.pose(atDistance: d)
            XCTAssertEqual(a.x, b.x, accuracy: 1e-9)
            XCTAssertEqual(a.z, b.z, accuracy: 1e-9)
        }
        let p = laps.lapPose(atDistance: 2500)
        XCTAssertEqual(p.lap, 1)
        XCTAssertEqual(p.pose.x, track.pose(atDistance: 500).x, accuracy: 1e-9)
        XCTAssertEqual(p.pose.z, track.pose(atDistance: 500).z, accuracy: 1e-9)
        XCTAssertFalse(p.pose.finished)
    }

    /// Über drei Runden keine Sprünge in Position und Richtung (auch an den Rundengrenzen)
    func testContinuousAcrossLaps() {
        let laps = LapTrack(track: track)
        var prev = laps.pose(atDistance: 0)
        var d = 0.25
        while d <= 3 * track.totalLength {
            let p = laps.pose(atDistance: d)
            XCTAssertLessThanOrEqual(hypot(p.x - prev.x, p.z - prev.z), 0.26, "Sprung bei \(d) m")
            let dh = atan2(sin(p.heading - prev.heading), cos(p.heading - prev.heading))
            XCTAssertLessThan(abs(dh), 0.05, "Richtungssprung bei \(d) m")
            prev = p
            d += 0.25
        }
    }

    /// Nach der Startwende wieder auf der Hinfahrtlinie und in Hinfahrtrichtung
    func testStartTurnEndsOnOutboundLine() {
        let laps = LapTrack(track: track)
        let p = laps.pose(atDistance: track.totalLength + laps.turnHalf)
        let q = track.pose(atDistance: laps.turnHalf)
        XCTAssertEqual(p.x, q.x, accuracy: 1e-6)
        XCTAssertEqual(p.z, q.z, accuracy: 1e-6)
        XCTAssertEqual(atan2(sin(p.heading - q.heading), cos(p.heading - q.heading)), 0, accuracy: 1e-6)
        XCTAssertGreaterThan(laps.turnHalf, 0)
    }

    /// Endet das Training in dieser Runde, geht es ohne Startwende gerade ins Ziel
    func testNoStartTurnInLastLap() {
        let laps = LapTrack(track: track, endDistance: 2000)
        let a = laps.pose(atDistance: 1990), b = track.pose(atDistance: 1990)
        XCTAssertEqual(a.x, b.x, accuracy: 1e-9)
        XCTAssertEqual(a.z, b.z, accuracy: 1e-9)
        let turning = LapTrack(track: track, endDistance: 3000).pose(atDistance: 1990)
        XCTAssertGreaterThan(hypot(turning.x - b.x, turning.z - b.z), 0.5)
    }

    /// Tor: Position zu einer Distanz der Fahrt in Runde 2
    func testGatePositionInSecondLap() {
        let laps = LapTrack(track: track)
        let gate = laps.pose(atDistance: 2000 + 740)
        XCTAssertEqual(gate.x, 0, accuracy: 1e-9)
        XCTAssertEqual(gate.z, -740, accuracy: 1e-9)
    }
}
