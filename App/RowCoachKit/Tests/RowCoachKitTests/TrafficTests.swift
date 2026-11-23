import XCTest
@testable import RowCoachKit

final class TrafficTests: XCTestCase {
    /// Gerade Strecke nach Norden, 2000 m hin und zurück (offenes Wasser)
    private let course = Course.straight(oneWay: 2000)
    private var track: CourseTrack { CourseTrack(course: course) }

    private func wrap(_ a: Double) -> Double { atan2(sin(a), cos(a)) }

    // MARK: - Format

    func testDecodeTrafficField() throws {
        let json = """
        {"id": "t", "title": "T", "region": "", "scene": "", "qualities": [], "one_way_m": 1000, "total_m": 2000,
         "turns": 1, "origin_lv95": [0, 0], "lake_level_m": 0, "path_xz": [[0, 0], [0, -1000]], "attribution": "",
         "traffic": {"vessels": ["kursschiff", "unbekannt"], "density": 0.5,
                     "rower_lanes": [{"out_m": -16, "back_m": 28}],
                     "vessel_lanes": [{"id": "x1", "kind": "cross", "min_dist_m": 0, "shore_m": 30,
                                       "points_xz": [[-300, -500], [300, -500]], "cross": [{"s": 500, "at": 300}]}]}}
        """
        let c = try Course.decode(Data(json.utf8))
        XCTAssertEqual(c.traffic?.density, 0.5)
        XCTAssertEqual(c.traffic?.rowerLanes, [RowerLaneSpec(outM: -16, backM: 28)])
        XCTAssertEqual(c.traffic?.vesselLanes?.first?.kind, .cross)
        XCTAssertEqual(c.traffic?.vesselLanes?.first?.cross?.first?.at, 300)
        // unbekannte Schiffsart wird ignoriert, Fähre/Rheinschiff nicht verlangt
        let v = VesselTraffic(course: c, density: .normal, seed: 1)
        XCTAssertEqual(v.kinds, [.kursschiff])
    }

    func testCourseWithoutTrafficUsesDefaults() throws {
        let data = try JSONEncoder().encode(course)
        let c = try Course.decode(data)
        XCTAssertNil(c.traffic)
        XCTAssertEqual(VirtualRowers(course: c, density: .normal, seed: 1).lanes.count, TrafficDefaults.rowerLanes.count)
        XCTAssertEqual(TrafficDefaults.vessels(for: Course.straight(id: "rhein-basel")), [.rheinschiff, .faehre, .motorboot])
    }

    // MARK: - Bahnen der Ruderer

    func testRowerLaneOnStraights() throws {
        let lane = try XCTUnwrap(RowerLane(spec: RowerLaneSpec(outM: -16, backM: 28), track: track))
        // Hinfahrt nach Norden: Versatz −16 = 16 m rechts (Osten), Richtung Norden
        let p = lane.pose(atW: lane.w(fromU: 800))
        XCTAssertEqual(p.x, 16, accuracy: 1e-6)
        XCTAssertEqual(p.z, -800, accuracy: 1e-6)
        XCTAssertEqual(wrap(p.heading), 0, accuracy: 1e-9)
        // Rückfahrt: 28 m links der Hinfahrt (Westen), Richtung Süden
        let q = lane.pose(atW: lane.w(fromU: 4000 - 800))
        XCTAssertEqual(q.x, -28, accuracy: 1e-6)
        XCTAssertEqual(q.z, -800, accuracy: 1e-6)
        XCTAssertEqual(abs(wrap(q.heading)), Double.pi, accuracy: 1e-9)
    }

    func testRowerLaneIsContinuousAndMappingRoundTrips() throws {
        for spec in TrafficDefaults.rowerLanes + [RowerLaneSpec(outM: -48, backM: -16), RowerLaneSpec(outM: 30, backM: 50)] {
            let lane = try XCTUnwrap(RowerLane(spec: spec, track: track))
            var prev = lane.pose(atW: 0)
            var w = 0.5
            while w <= lane.loopLength + 0.5 {
                let p = lane.pose(atW: w)
                XCTAssertLessThan(hypot(p.x - prev.x, p.z - prev.z), 0.5 + 1e-6, "Sprung bei w = \(w), \(spec)")
                XCTAssertLessThan(abs(wrap(p.heading - prev.heading)), 0.1, "Knick bei w = \(w), \(spec)")
                prev = p
                w += 0.5
            }
            for u in stride(from: 0.0, to: 4000, by: 37) {
                XCTAssertEqual(lane.u(fromW: lane.w(fromU: u)), u, accuracy: 1e-6)
            }
        }
    }

    /// Bahnen halten überall mindestens 8 m Abstand zur eigenen Bahn (mit Wende und Startwende).
    func testRowerLanesKeepClearOfOwnTrack() throws {
        let laps = LapTrack(track: track)
        let own = stride(from: 0.0, to: laps.lapLength, by: 1).map { laps.pose(atDistance: $0) }
        for spec in TrafficDefaults.rowerLanes + [RowerLaneSpec(outM: -48, backM: -16), RowerLaneSpec(outM: 32, backM: 48)] {
            let lane = try XCTUnwrap(RowerLane(spec: spec, track: track))
            var minD = Double.infinity
            for w in stride(from: 0.0, to: lane.loopLength, by: 2) {
                let p = lane.pose(atW: w)
                for o in own where abs(o.z - p.z) < 60 { minD = min(minD, hypot(o.x - p.x, o.z - p.z)) }
            }
            XCTAssertGreaterThanOrEqual(minD, 8, "\(spec)")
        }
    }

    // MARK: - Ruderer (dauerhaft auf der Strecke)

    private struct RowerRun {
        var ids = Set<Int>()
        var minOwnDistance = Double.infinity
        var minPairDistance = Double.infinity
        var nearAtStart = 0
        var nearSeconds = 0
        var nearEpisodes = 0
        var steps = 0
        var overtakes = 0
        var firstPositions: [Int: (x: Double, z: Double)] = [:]
        var lastPositions: [Int: (x: Double, z: Double)] = [:]
    }

    private func simulateRowers(seed: UInt64, density: TrafficDensity = .normal, minutes: Double = 60,
                                speed: Double = 4, docks: [RowerDockSpec]? = nil) -> (RowerRun, VirtualRowers) {
        var planner = VirtualRowers(course: course, density: density, seed: seed, lanes: TrafficDefaults.rowerLanes,
                                    docks: docks)
        let laps = LapTrack(track: track)
        var run = RowerRun()
        var lastAlong: [Int: Double] = [:]
        var wasNear = false
        var t = 0.0
        while t < minutes * 60 {
            let d = speed * t
            let pose = laps.pose(atDistance: d)
            let own = OwnBoat(u: Laps.split(distance: d, lapLength: laps.lapLength).distanceInLap,
                              x: pose.x, z: pose.z, heading: pose.heading, speed: speed)
            planner.update(time: t, own: own)
            let states = planner.states(at: t, own: own)
            if t == 0 { run.nearAtStart = states.filter { $0.distance <= 150 }.count }
            let fx = -sin(own.heading), fz = -cos(own.heading)
            var near = false
            for (i, s) in states.enumerated() {
                run.ids.insert(s.id)
                if run.firstPositions[s.id] == nil { run.firstPositions[s.id] = (s.x, s.z) }
                run.lastPositions[s.id] = (s.x, s.z)
                run.minOwnDistance = min(run.minOwnDistance, s.distance)
                if s.distance <= 60 { near = true }
                for o in states[(i + 1)...] {
                    run.minPairDistance = min(run.minPairDistance, hypot(o.x - s.x, o.z - s.z))
                }
                let vx = s.x - own.x, vz = s.z - own.z
                let along = vx * fx + vz * fz
                let lateral = abs(vx * fz - vz * fx)
                let sameDirection = cos(s.heading - own.heading) > 0.5
                if sameDirection, lateral < 80, let prev = lastAlong[s.id], abs(along) < 40, (prev < 0) != (along < 0) {
                    run.overtakes += 1
                }
                lastAlong[s.id] = sameDirection && lateral < 80 ? along : nil
            }
            if near { run.nearSeconds += 1 }
            if near && !wasNear { run.nearEpisodes += 1 }
            wasNear = near
            run.steps += 1
            t += 1
        }
        return (run, planner)
    }

    /// Ruderer sind von Anfang an da, bleiben die ganze Fahrt, halten ≥ 8 m Abstand zum eigenen Boot und zueinander,
    /// und begegnen einem regelmässig in der Nähe.
    func testResidentRowersStayAndMeetOften() {
        var overtakes = 0
        for seed: UInt64 in [1, 7, 42, 2026] {
            let (run, planner) = simulateRowers(seed: seed)
            XCTAssertEqual(planner.residentCount, 6, "Seed \(seed)")
            XCTAssertEqual(run.ids.count, 6, "Seed \(seed): niemand taucht auf oder verschwindet")
            XCTAssertEqual(planner.rowers.count, 6, "Seed \(seed)")
            XCTAssertGreaterThanOrEqual(run.minOwnDistance, 8, "Seed \(seed)")
            XCTAssertGreaterThanOrEqual(run.minPairDistance, 7.99, "Seed \(seed)")  // Nachbarbahnen genau 8 m
            XCTAssertGreaterThanOrEqual(run.nearAtStart, 1, "Seed \(seed): beim Start jemand in 150 m")
            // jemand innerhalb von 60 m: im Mittel alle 1–2 min (Simulation: Median 45–75 s), mind. alle 4 min
            XCTAssertGreaterThanOrEqual(run.nearEpisodes, 15, "Seed \(seed)")
            overtakes += run.overtakes
        }
        XCTAssertGreaterThanOrEqual(overtakes, 4, "über alle Startwerte wird überholt")
    }

    func testDensityChangesNumberOfRowers() {
        XCTAssertEqual(VirtualRowers(course: course, density: .low, seed: 1).residentCount, 4)
        XCTAssertEqual(VirtualRowers(course: course, density: .normal, seed: 1).residentCount, 6)
        XCTAssertEqual(VirtualRowers(course: course, density: .dense, seed: 1).residentCount, 9)
        // 3,1 km (Basel): anteilig
        XCTAssertEqual(VirtualRowers(course: .straight(oneWay: 1550), density: .normal, seed: 1).residentCount, 5)
        let (low, _) = simulateRowers(seed: 3, density: .low, minutes: 30)
        let (dense, _) = simulateRowers(seed: 3, density: .dense, minutes: 30)
        XCTAssertLessThan(low.nearSeconds, dense.nearSeconds)
        XCTAssertGreaterThanOrEqual(dense.minPairDistance, 7.99)
    }

    /// Bahnen haben unterschiedliche, feste Tempofaktoren; auf derselben Bahn fahren alle gleich schnell.
    func testLaneFactorsAreSpread() {
        let p = VirtualRowers(course: course, density: .normal, seed: 5)
        let f = p.laneFactors.sorted()
        XCTAssertEqual(f.count, 3)
        XCTAssertTrue((0.78...0.86).contains(f[0]))
        XCTAssertTrue((0.96...1.04).contains(f[1]))
        XCTAssertTrue((1.14...1.24).contains(f[2]))
    }

    /// Gäste steigen am Steg ein und wieder aus: erste und letzte Lage am Steg, kein Auftauchen aus dem Nichts.
    func testGuestsEnterAndLeaveAtDock() {
        // Bahn 2 (−32/44): Hinfahrt 32 m östlich, die äusserste Bahn zum Ostufer (x = 80) hin, wie lanes.py wählt.
        let dock = RowerDockSpec(id: "steg", name: "Bootshaus", lane: 2, joinU: 1050,
                                 enterXZ: Self.bezier([80, -1000], [32, -1010], [32, -1050]),
                                 exitXZ: Self.bezier([32, -1050], [32, -1090], [80, -1110]))
        let (run, planner) = simulateRowers(seed: 4, density: .dense, minutes: 120, docks: [dock])
        let guests = run.ids.subtracting(1...planner.residentCount)
        XCTAssertGreaterThan(guests.count, 0, "kein Gast eingestiegen")
        var left = 0
        for id in guests {
            guard let first = run.firstPositions[id] else { continue }
            XCTAssertLessThan(hypot(first.x - 80, first.z + 1000), 8, "Gast \(id) startet nicht am Steg")
            if !planner.rowers.contains(where: { $0.id == id }), let last = run.lastPositions[id] {
                left += 1
                XCTAssertLessThan(hypot(last.x - 80, last.z + 1110), 12, "Gast \(id) endet nicht am Steg")
            }
        }
        XCTAssertGreaterThan(left, 0, "kein Gast ausgestiegen")
        XCTAssertGreaterThanOrEqual(run.minOwnDistance, 8)
        XCTAssertGreaterThanOrEqual(run.minPairDistance, 7.99)
    }

    private static func bezier(_ a: [Double], _ c: [Double], _ b: [Double]) -> [[Double]] {
        (0...12).map { i in
            let t = Double(i) / 12
            let u = 1 - t
            return [u * u * a[0] + 2 * u * t * c[0] + t * t * b[0], u * u * a[1] + 2 * u * t * c[1] + t * t * b[1]]
        }
    }

    func testRowersAreDeterministic() {
        let a = simulateRowers(seed: 99, minutes: 20).1.rowers
        let b = simulateRowers(seed: 99, minutes: 20).1.rowers
        let c = simulateRowers(seed: 100, minutes: 20).1.rowers
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testRowerSpeedWobbleStaysSmall() {
        let r = VirtualRower(id: 1, lane: 0, factor: 1.1, wobble: 0.03, wobblePeriod: 60, wobblePhase: 1, colorIndex: 0,
                             plannedMeters: nil, phase: .lane, w: 0, strokePhase: 0.3)
        for t in stride(from: 0.0, to: 200, by: 5) {
            XCTAssertEqual(r.speedFactor(at: t), 1.1, accuracy: 1.1 * 0.03 + 1e-9)
        }
        XCTAssertEqual(r.strokeRate(speed: 4), 24)
        XCTAssertEqual(r.strokeRate(speed: 9), 32)
    }

    // MARK: - Schiffe

    private func own(at t: Double, speed: Double, laps: LapTrack) -> OwnBoat {
        let d = speed * t
        let p = laps.pose(atDistance: d)
        return OwnBoat(u: Laps.split(distance: d, lapLength: laps.lapLength).distanceInLap, x: p.x, z: p.z,
                       heading: p.heading, speed: speed)
    }

    func testVesselsKeepDistanceAndSpacing() {
        var traffic = VesselTraffic(course: course, density: .normal, seed: 5,
                                    kinds: [.motorboot, .segelboot, .kursschiff])
        let laps = LapTrack(track: track)
        var ids = Set<Int>()
        var minMargin = Double.infinity
        var t = 0.0
        while t < 7200 {
            let o = own(at: t, speed: 4, laps: laps)
            traffic.update(time: t, own: o)
            for s in traffic.states(at: t) {
                ids.insert(s.id)
                // Abstand zum eigenen Boot minus Mindestabstand der Art (klein 20, Kursschiff 40, Rheinschiff 50)
                minMargin = min(minMargin, hypot(s.x - o.x, s.z - o.z) - s.kind.minDistance)
            }
            t += 2
        }
        // etwa alle 2–6 Minuten ein Schiff (zwei Stunden)
        XCTAssertGreaterThanOrEqual(ids.count, 15)
        XCTAssertLessThanOrEqual(ids.count, 70)
        XCTAssertGreaterThanOrEqual(minMargin, 0)
    }

    func testOneVesselPerLaneAndKindRules() {
        let lanes = TrafficDefaults.vesselLanes(for: course) + [
            VesselLaneSpec(id: "x1", kind: .cross, minDistM: 0, pointsXZ: [[-400, -1000], [400, -1000]],
                           cross: [.init(s: 1000, at: 400)]),
        ]
        var traffic = VesselTraffic(course: course, density: .dense, seed: 11,
                                    kinds: [.rheinschiff, .faehre, .motorboot], lanes: lanes)
        let laps = LapTrack(track: track)
        var t = 0.0
        while t < 3600 {
            traffic.update(time: t, own: own(at: t, speed: 4, laps: laps))
            let active = traffic.trips
            XCTAssertEqual(Set(active.map(\.lane)).count, active.count)
            for trip in active {
                let kind = traffic.paths[trip.lane].spec.kind
                if trip.kind == .faehre { XCTAssertEqual(kind, .cross) }
                if trip.kind == .rheinschiff {
                    XCTAssertNotEqual(kind, .cross)
                    XCTAssertGreaterThanOrEqual(traffic.paths[trip.lane].spec.minDistM, 50)
                }
            }
            t += 2
        }
    }

    /// Querlinie über die Strecke: das Schiff kreuzt nie näher als ca. 300 m vor dem eigenen Boot (dahinter ≥ 100 m).
    func testCrossingKeepsClearOfOwnBoat() {
        let cross = VesselLaneSpec(id: "x1", kind: .cross, minDistM: 0, pointsXZ: [[-150, -1000], [150, -1000]],
                                   cross: [.init(s: 1000, at: 150)])
        for seed: UInt64 in [1, 2, 3, 4] {
            var traffic = VesselTraffic(course: course, density: .dense, seed: seed, kinds: [.faehre, .motorboot],
                                        lanes: [cross])
            let laps = LapTrack(track: track)
            var crossings = 0
            var t = 0.0
            while t < 5400 {
                let o = own(at: t, speed: 4, laps: laps)
                traffic.update(time: t, own: o)
                let fx = -sin(o.heading), fz = -cos(o.heading)
                for s in traffic.states(at: t) where abs(s.x) < 45 {
                    crossings += 1
                    let d = hypot(s.x - o.x, s.z - o.z)
                    let ahead = (s.x - o.x) * fx + (s.z - o.z) * fz > 0
                    XCTAssertGreaterThanOrEqual(d, ahead ? 250 : 100, "Seed \(seed), t = \(t)")
                }
                t += 1
            }
            XCTAssertGreaterThan(crossings, 0, "Seed \(seed): nie gekreuzt")
        }
    }

    func testVesselsAreDeterministic() {
        func run(_ seed: UInt64) -> [VesselTrip] {
            var traffic = VesselTraffic(course: course, density: .normal, seed: seed)
            let laps = LapTrack(track: track)
            var all: [VesselTrip] = []
            var t = 0.0
            while t < 3600 {
                traffic.update(time: t, own: own(at: t, speed: 3.8, laps: laps))
                for trip in traffic.trips where !all.contains(trip) { all.append(trip) }
                t += 1
            }
            return all
        }
        XCTAssertEqual(run(8), run(8))
        XCTAssertNotEqual(run(8), run(9))
    }

    func testRandomIsDeterministicAndInRange() {
        var a = TrafficRandom(seed: 123), b = TrafficRandom(seed: 123)
        for _ in 0..<1000 {
            let x = a.unit()
            XCTAssertEqual(x, b.unit())
            XCTAssertGreaterThanOrEqual(x, 0)
            XCTAssertLessThan(x, 1)
        }
        XCTAssertLessThan(a.int(5), 5)
    }
}

final class TrafficDefaultsBerlinTests: XCTestCase {
    /// Voreinstellungen der Strecken in Berlin und Potsdam (ohne Feld `traffic` in course.json)
    func testBerlinPotsdamVessels() {
        XCTAssertEqual(TrafficDefaults.vessels(for: Course.straight(id: "berlin-spree-mitte")), [.kursschiff, .motorboot])
        XCTAssertEqual(TrafficDefaults.vessels(for: Course.straight(id: "berlin-wannsee")),
                       [.kursschiff, .segelboot, .motorboot])
        XCTAssertEqual(TrafficDefaults.vessels(for: Course.straight(id: "potsdam-jungfernsee")),
                       [.kursschiff, .segelboot, .motorboot])
        XCTAssertEqual(TrafficDefaults.vessels(for: Course.straight(id: "berlin-gruenau")), [.motorboot, .segelboot])
    }
}
