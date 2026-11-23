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

    // MARK: - Planer der Ruderer

    private struct RowerRun {
        var maxNear = 0
        var minDistance = Double.infinity
        var overtakes = 0
        var spawnedVisible = 0
        var spawned = 0
        var nearSum = 0
        var steps = 0
        /// mittlere Zahl der Ruderer im Umkreis von 400 m
        var averageNear: Double { steps > 0 ? Double(nearSum) / Double(steps) : 0 }
    }

    private func simulateRowers(seed: UInt64, density: TrafficDensity = .normal, minutes: Double = 60,
                                speed: Double = 4) -> (RowerRun, [VirtualRower]) {
        var planner = VirtualRowers(course: course, density: density, seed: seed)
        let laps = LapTrack(track: track)
        var run = RowerRun()
        var seen = Set<Int>()
        var lastAlong: [Int: Double] = [:]
        var t = 0.0
        while t < minutes * 60 {
            let d = speed * t
            let pose = laps.pose(atDistance: d)
            let own = OwnBoat(u: Laps.split(distance: d, lapLength: laps.lapLength).distanceInLap,
                              x: pose.x, z: pose.z, heading: pose.heading, speed: speed)
            planner.update(time: t, own: own)
            let states = planner.states(at: t, own: own)
            let near = states.filter { $0.distance < 400 }.count
            run.maxNear = max(run.maxNear, near)
            run.nearSum += near
            run.steps += 1
            let fx = -sin(own.heading), fz = -cos(own.heading)
            for s in states {
                run.minDistance = min(run.minDistance, s.distance)
                if !seen.contains(s.id) {
                    seen.insert(s.id)
                    run.spawned += 1
                    // im Blickfeld nur ab 120 m (die Szene blendet dann ein)
                    if !VirtualRowers.isHidden(x: s.x, z: s.z, own: own) && s.distance < VirtualRowers.minVisibleSpawn {
                        run.spawnedVisible += 1
                    }
                }
                // Überholen: gleiche Richtung, seitlich nah, Vorzeichen der Längslage wechselt
                let vx = s.x - own.x, vz = s.z - own.z
                let along = vx * fx + vz * fz
                let lateral = abs(vx * fz - vz * fx)
                let sameDirection = cos(s.heading - own.heading) > 0.5
                if sameDirection, lateral < 80, let prev = lastAlong[s.id], abs(along) < 40, (prev < 0) != (along < 0) {
                    run.overtakes += 1
                }
                lastAlong[s.id] = sameDirection && lateral < 80 ? along : nil
            }
            t += 1
        }
        return (run, planner.rowers)
    }

    func testRowerDensitySpacingAndOvertakes() {
        for seed: UInt64 in [1, 7, 42, 2026] {
            let (run, _) = simulateRowers(seed: seed)
            XCTAssertLessThanOrEqual(run.maxNear, 4, "Seed \(seed)")
            XCTAssertGreaterThanOrEqual(run.minDistance, 8, "Seed \(seed)")
            XCTAssertEqual(run.spawnedVisible, 0, "Seed \(seed)")
            // etwa alle 2–5 Minuten ein Überholen (Spielraum für den Zufall)
            XCTAssertGreaterThanOrEqual(run.overtakes, 8, "Seed \(seed)")
            XCTAssertLessThanOrEqual(run.overtakes, 40, "Seed \(seed)")
        }
    }

    /// „wenig“: höchstens 2 zugleich und seltener neue (Simulation: im Mittel ca. 1,5 statt 2,5 Ruderer in 400 m,
    /// etwa ein Drittel weniger neue); `dense` mindestens so viele wie normal.
    func testLowDensityHasFewerRowers() {
        for seed: UInt64 in [3, 8] {
            let (low, _) = simulateRowers(seed: seed, density: .low)
            let (normal, _) = simulateRowers(seed: seed, density: .normal)
            let (dense, _) = simulateRowers(seed: seed, density: .dense)
            XCTAssertLessThanOrEqual(low.maxNear, 2, "Seed \(seed)")
            XCTAssertLessThan(low.averageNear, normal.averageNear - 0.4, "Seed \(seed)")
            XCTAssertLessThan(low.spawned, normal.spawned, "Seed \(seed)")
            XCTAssertGreaterThanOrEqual(dense.averageNear, normal.averageNear - 0.1, "Seed \(seed)")
        }
    }

    func testRowersAreDeterministic() {
        let a = simulateRowers(seed: 99, minutes: 20).1
        let b = simulateRowers(seed: 99, minutes: 20).1
        let c = simulateRowers(seed: 100, minutes: 20).1
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testRowerSpeedWobbleStaysSmall() {
        let r = VirtualRower(id: 1, lane: 0, speed: 4, w0: 0, t0: 10, wobble: 0.04, wobblePeriod: 60, wobblePhase: 1,
                             strokeRate: 24, strokeOffset: 0.3, colorIndex: 0)
        XCTAssertEqual(r.travelled(at: 10), 0, accuracy: 1e-9)
        // über eine volle Periode genau Grundtempo × Zeit
        XCTAssertEqual(r.travelled(at: 70), 240, accuracy: 1e-6)
        for t in stride(from: 10.0, to: 200, by: 5) {
            XCTAssertEqual(r.speed(at: t), 4, accuracy: 4 * 0.04 + 1e-9)
            XCTAssertGreaterThanOrEqual(r.strokePhase(at: t), 0)
            XCTAssertLessThan(r.strokePhase(at: t), 1)
        }
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
        var minSmall = Double.infinity, minLarge = Double.infinity
        var t = 0.0
        while t < 7200 {
            let o = own(at: t, speed: 4, laps: laps)
            traffic.update(time: t, own: o)
            for s in traffic.states(at: t) {
                ids.insert(s.id)
                let d = hypot(s.x - o.x, s.z - o.z)
                if s.kind.isLarge { minLarge = min(minLarge, d) } else { minSmall = min(minSmall, d) }
            }
            t += 2
        }
        // etwa alle 2–6 Minuten ein Schiff (zwei Stunden)
        XCTAssertGreaterThanOrEqual(ids.count, 15)
        XCTAssertLessThanOrEqual(ids.count, 70)
        XCTAssertGreaterThanOrEqual(minSmall, 40)
        XCTAssertGreaterThanOrEqual(minLarge, 80)
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
                    XCTAssertGreaterThanOrEqual(traffic.paths[trip.lane].spec.minDistM, 80)
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
