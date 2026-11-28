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
                // Auf den Geraden gilt w = s. Im Übergang zum Wendeversatz (7 m auf 80 m, Smoothstep, grösste
                // Steigung 1,5 · 7 / 80 = 0,131) ist die Bahn um den Faktor √(1 + 0,131²) = 1,0086 länger:
                // 0,5 m in w sind dort bis 0,5043 m Weg. Das ist Streckung, kein Sprung.
                XCTAssertLessThan(hypot(p.x - prev.x, p.z - prev.z), 0.5 * 1.01, "Sprung bei w = \(w), \(spec)")
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
        /// Sekunden mit einem Ruderer 8–30 m vor der Kamera (4,5 m hinter dem Boot) bei ≤ 32° Peilung
        var bandSeconds = 0
        /// Ruderer (keine Gäste), die im Blickfeld und näher als 450 m auftauchten bzw. verschwanden
        var visiblePops = 0
        /// alle, die einmal Gast waren (Hasen sind keine Gäste)
        var guests = Set<Int>()
        var bandFraction: Double { steps > 0 ? Double(bandSeconds) / Double(steps) : 0 }
    }

    /// ausser Sicht: mehr als 100° von der Blickrichtung der Kamera (4,5 m hinter dem Boot; Bildfeld quer ±37°) oder
    /// weiter als 450 m
    private static func hidden(_ x: Double, _ z: Double, own: OwnBoat) -> Bool {
        VirtualRowers.isHidden(x: x, z: z, own: own, minDistance: 0, cosMax: -0.17)
    }

    /// `on`/`lanes`: andere Strecke bzw. Bahnen (Standard: gerade Teststrecke mit den Standardbahnen). `bandFar`: Ende
    /// des Sichtbands (m vor der Kamera; 45 auf Strecken, deren Linien nur den Hasen gehören). Mit `on`: Auftauchen
    /// und Verschwinden beim Rundenwechsel einer one_way-Strecke zählt nicht (die ganze Szene springt), und wer beim
    /// letzten Schritt schon fast 450 m weg war, verschwindet nicht im Bild (dort wird er ohnehin geparkt).
    private func simulateRowers(seed: UInt64, density: TrafficDensity = .normal, minutes: Double = 60,
                                speed: Double = 4, docks: [RowerDockSpec]? = nil, on other: Course? = nil,
                                lanes: [RowerLaneSpec]? = nil, bandFar: Double = 30) -> (RowerRun, VirtualRowers) {
        let base = other ?? self.course
        let laps = LapTrack(track: CourseTrack(course: base))
        // wie in der App (RowingView.trafficCourse): Verkehr auf derselben Runde wie das Boot (Einweg mit Kehre:
        // hin und zurück)
        let course = laps.track.course
        var planner = VirtualRowers(course: course, density: density, seed: seed,
                                    lanes: lanes ?? (other == nil ? TrafficDefaults.rowerLanes : nil), docks: docks)
        let jumps = other != nil && course.turns == 0 && !course.isLoop
        var lastLap = 0
        var run = RowerRun()
        var lastAlong: [Int: Double] = [:]
        var wasNear = false
        var previous: [Int: (x: Double, z: Double, own: OwnBoat)] = [:]
        var guestIdsEver = Set<Int>()
        var t = 0.0
        while t < minutes * 60 {
            let d = speed * t
            let pose = laps.pose(atDistance: d)
            let split = Laps.split(distance: d, lapLength: laps.lapLength)
            let own = OwnBoat(u: split.distanceInLap, x: pose.x, z: pose.z, heading: pose.heading, speed: speed)
            let restart = jumps && split.lap != lastLap
            lastLap = split.lap
            planner.update(time: t, own: own)
            let states = planner.states(at: t, own: own)
            if t == 0 { run.nearAtStart = states.filter { $0.distance <= 150 }.count }
            let fx = -sin(own.heading), fz = -cos(own.heading)
            var near = false
            var inBand = false
            let guestIds = Set(planner.rowers.filter(\.isGuest).map(\.id))
            for (i, s) in states.enumerated() {
                run.ids.insert(s.id)
                if run.firstPositions[s.id] == nil {
                    run.firstPositions[s.id] = (s.x, s.z)
                    if t > 0, !restart, !guestIds.contains(s.id), !Self.hidden(s.x, s.z, own: own) { run.visiblePops += 1 }
                }
                previous[s.id] = (s.x, s.z, own)
                run.lastPositions[s.id] = (s.x, s.z)
                run.minOwnDistance = min(run.minOwnDistance, s.distance)
                if s.distance <= 60 { near = true }
                for o in states[(i + 1)...] {
                    run.minPairDistance = min(run.minPairDistance, hypot(o.x - s.x, o.z - s.z))
                }
                let vx = s.x - own.x, vz = s.z - own.z
                let along = vx * fx + vz * fz
                let lateral = abs(vx * fz - vz * fx)
                // Sichtband: 8–30 m vor der Kamera (4,5 m hinter dem Boot), Peilung von der Kamera ≤ 32°
                if along + 4.5 >= 8, along + 4.5 <= bandFar, atan2(lateral, along + 4.5) <= 32 * Double.pi / 180 { inBand = true }
                let sameDirection = cos(s.heading - own.heading) > 0.5
                if sameDirection, lateral < 80, let prev = lastAlong[s.id], abs(along) < 40, (prev < 0) != (along < 0) {
                    run.overtakes += 1
                }
                lastAlong[s.id] = sameDirection && lateral < 80 ? along : nil
            }
            if near { run.nearSeconds += 1 }
            if inBand { run.bandSeconds += 1 }
            // verschwundene (keine Gäste): zuletzt ausser Sicht?
            let now = Set(states.map(\.id))
            for (id, p) in previous where !now.contains(id) {
                let parked = other != nil && hypot(p.x - p.own.x, p.z - p.own.z) >= VirtualRowers.visibleRange - 10
                if !restart, !parked, !Self.hidden(p.x, p.z, own: p.own), !guestIdsEver.contains(id) {
                    run.visiblePops += 1
                }
                previous[id] = nil
            }
            guestIdsEver.formUnion(guestIds)
            if near && !wasNear { run.nearEpisodes += 1 }
            wasNear = near
            run.steps += 1
            t += 1
        }
        run.guests = guestIdsEver
        return (run, planner)
    }

    /// Ruderer sind von Anfang an da, bleiben die ganze Fahrt, halten ≥ 8 m Abstand zum eigenen Boot und zueinander,
    /// und begegnen einem regelmässig in der Nähe. Hasen tauchen nur ausser Sicht auf und verschwinden ausser Sicht.
    func testResidentRowersStayAndMeetOften() {
        var overtakes = 0
        for seed: UInt64 in [1, 7, 42, 2026] {
            let (run, planner) = simulateRowers(seed: seed)
            XCTAssertEqual(planner.residentCount, 6, "Seed \(seed)")
            let residents = Set(1...6)
            XCTAssertTrue(residents.isSubset(of: Set(planner.rowers.map(\.id))), "Seed \(seed): Ruderer fehlen")
            XCTAssertTrue(run.ids.subtracting(residents).allSatisfy { id in
                !planner.rowers.contains { $0.id == id && $0.hare == nil }
            }, "Seed \(seed): ausser Hasen kommt niemand dazu")
            XCTAssertEqual(run.visiblePops, 0, "Seed \(seed): niemand taucht im Bild auf oder verschwindet")
            XCTAssertGreaterThanOrEqual(run.minOwnDistance, 8, "Seed \(seed)")
            XCTAssertGreaterThanOrEqual(run.minPairDistance, 7.99, "Seed \(seed)")  // Nachbarbahnen genau 8 m
            XCTAssertGreaterThanOrEqual(run.nearAtStart, 1, "Seed \(seed): beim Start jemand in 150 m")
            // jemand innerhalb von 60 m: Simulation normal 80–94 % der Zeit
            XCTAssertGreaterThanOrEqual(Double(run.nearSeconds) / Double(run.steps), 0.3, "Seed \(seed)")
            overtakes += run.overtakes
        }
        XCTAssertGreaterThanOrEqual(overtakes, 4, "über alle Startwerte wird überholt")
    }

    /// Sichtband (Falk): ein Ruderer 8–30 m vor der Kamera bei ≤ 32° Peilung – normal ≥ 35 % der Zeit, dense ≥ 45 %
    /// (Mittel über 4 Startwerte; Python-Nachbau tools/traffic_sim: 25 / 56 / 62 %), wenig weniger.
    func testRowerOftenInViewBandAhead() {
        var low = 0.0, normal = 0.0, dense = 0.0
        let seeds: [UInt64] = [1, 2, 3, 4]
        for seed in seeds {
            low += simulateRowers(seed: seed, density: .low).0.bandFraction
            normal += simulateRowers(seed: seed, density: .normal).0.bandFraction
            dense += simulateRowers(seed: seed, density: .dense).0.bandFraction
        }
        let n = Double(seeds.count)
        XCTAssertGreaterThanOrEqual(normal / n, 0.35)
        XCTAssertGreaterThanOrEqual(dense / n, 0.45)
        XCTAssertLessThan(low / n, normal / n)
    }

    func testDensityChangesNumberOfRowers() {
        XCTAssertEqual(VirtualRowers(course: course, density: .low, seed: 1).residentCount, 4)
        XCTAssertEqual(VirtualRowers(course: course, density: .normal, seed: 1).residentCount, 6)
        XCTAssertEqual(VirtualRowers(course: course, density: .dense, seed: 1).residentCount, 9)
        // 3,1 km (Basel): anteilig
        XCTAssertEqual(VirtualRowers(course: .straight(oneWay: 1550), density: .normal, seed: 1).residentCount, 5)
        // Nähe über mehrere Startwerte gemittelt: Ein einzelner Lauf hängt stark davon ab, ob ein Ruderer der Bahn mit
        // Faktor ≈ 1 lange neben einem herfährt (bei Startwert 3 und 30 min hatte „wenig“ zufällig mehr Nähe).
        var lowNear = 0, denseNear = 0
        for seed: UInt64 in [1, 2, 3, 4, 5, 6] {
            let (low, _) = simulateRowers(seed: seed, density: .low, minutes: 60)
            let (dense, _) = simulateRowers(seed: seed, density: .dense, minutes: 60)
            lowNear += low.nearSeconds
            denseNear += dense.nearSeconds
            XCTAssertGreaterThanOrEqual(dense.minPairDistance, 7.99, "Seed \(seed)")
        }
        XCTAssertLessThan(lowNear, denseNear)
    }

    /// Bahnen haben unterschiedliche, feste Tempofaktoren; auf derselben Bahn fahren alle gleich schnell.
    func testLaneFactorsAreSpread() {
        let p = VirtualRowers(course: course, density: .normal, seed: 5)
        XCTAssertEqual(p.laneFactors.count, 3)
        XCTAssertEqual(p.innerLane, 0, "innerste Standardbahn ist die erste (9 m)")
        XCTAssertTrue((0.90...0.96).contains(p.laneFactors[0]))
        XCTAssertTrue((1.08...1.16).contains(p.laneFactors[1]))
        XCTAssertTrue((0.80...0.86).contains(p.laneFactors[2]))
    }

    /// Gäste steigen am Steg ein und wieder aus: erste und letzte Lage am Steg, kein Auftauchen aus dem Nichts.
    func testGuestsEnterAndLeaveAtDock() {
        // Bahn 2 (auf der Geraden −27/40): Hinfahrt 27 m östlich, die äusserste Bahn zum Ostufer (x = 80) hin, wie
        // lanes.py wählt.
        let dock = RowerDockSpec(id: "steg", name: "Bootshaus", lane: 2, joinU: 1050,
                                 enterXZ: Self.bezier([80, -1000], [27, -1010], [27, -1050]),
                                 exitXZ: Self.bezier([27, -1050], [27, -1090], [80, -1110]))
        let (run, planner) = simulateRowers(seed: 4, density: .dense, minutes: 120, docks: [dock])
        let guests = run.guests
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

    /// Nur eine Bahn (z. B. Luzern, Stein am Rhein): keine Bahnruderer, die Bahn gehört den Hasen; bei grossem
    /// Seitenabstand (hier 18 m wie in Luzern) fährt der Hase so weit vorn, dass er ca. 25° von der Kamera aus liegt
    /// (≤ 45 m).
    func testSingleLaneBelongsToHares() {
        var p = VirtualRowers(course: course, density: .normal, seed: 5,
                              lanes: [RowerLaneSpec(outM: -18, backM: -9, turnOutM: -32, turnBackM: -16)])
        XCTAssertEqual(p.residentCount, 0)
        let own = OwnBoat(u: 200, x: 0, z: -200, heading: 0, speed: 4)
        p.update(time: 0, own: own)
        XCTAssertEqual(p.rowers.count, 1)
        let hare = p.rowers[0]
        XCTAssertNotNil(hare.hare)
        XCTAssertEqual(p.lanes[0].u(fromW: hare.w) - 200, 34.1, accuracy: 0.2)
        // Peilung von der Kamera ca. 25°, Abstand von der Kamera ≤ 45 m
        let s = p.states(at: 0, own: own)[0]
        let alongCam = -(s.z - own.z) + 4.5
        XCTAssertEqual(atan2(abs(s.x - own.x), alongCam) * 180 / .pi, 25, accuracy: 1.5)
        XCTAssertLessThanOrEqual(hypot(s.x - own.x, alongCam), 45.5)
    }

    /// Ausweichstellen (Basel: an Brückenpfeilern weich nach aussen), stetig und mit Abstand zur eigenen Bahn.
    func testLaneBumpsShiftSmoothly() throws {
        let spec = RowerLaneSpec(outM: -9, backM: 22, turnOutM: -16, turnBackM: 28,
                                 outBumps: [LaneBump(s: 1000, d: -10, w: 80)], backBumps: [LaneBump(s: 500, d: 10, w: 90)])
        let lane = try XCTUnwrap(RowerLane(spec: spec, track: track))
        XCTAssertEqual(lane.lateral(s: 1000, out: true), -19, accuracy: 1e-9)
        XCTAssertEqual(lane.lateral(s: 1040, out: true), -14, accuracy: 1e-9)
        XCTAssertEqual(lane.lateral(s: 1080, out: true), -9, accuracy: 1e-9)
        XCTAssertEqual(lane.lateral(s: 500, out: false), 32, accuracy: 1e-9)
        XCTAssertEqual(lane.lateral(s: 700, out: false), 22, accuracy: 1e-9)
        var prev = lane.pose(atW: 0)
        var w = 0.5
        while w <= lane.loopLength {
            let p = lane.pose(atW: w)
            XCTAssertLessThan(hypot(p.x - prev.x, p.z - prev.z), 0.5 * 1.03, "Sprung bei w = \(w)")
            prev = p
            w += 0.5
        }
        let json = #"{"out_m": -9, "back_m": 22, "out_bumps": [{"s": 477.5, "d": -9, "w": 87.5}]}"#
        let decoded = try JSONDecoder().decode(RowerLaneSpec.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.outBumps, [LaneBump(s: 477.5, d: -9, w: 87.5)])
        XCTAssertNil(decoded.backBumps)
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

    // MARK: - Strecken ohne Wende und schmale Strecken (offene Linien, Ringe)

    /// Gerade one_way-Strecke nach Norden
    private func oneWayCourse(_ length: Double = 3000) -> Course {
        var c = Course.straight(id: "one-way", oneWay: length)
        c.turns = 0
        c.totalM = length
        return c
    }

    /// Kreisförmiger Rundkurs (Ende = Start), Umfang ca. 2400 m, gegen den Uhrzeigersinn von oben gesehen
    private func ringCourse() -> Course {
        let r = 2400 / (2 * Double.pi)
        let pts = (0...1200).map { i -> [Double] in
            let a = 2 * Double.pi * Double(i) / 1200
            return [r * sin(a), -r + r * cos(a)]
        }
        var c = Course(id: "ring", title: "Ring", oneWayM: 2400, totalM: 2400, turns: 0, pathXZ: pts)
        c.loop = true
        return c
    }

    private static let oneWayLanes: [RowerLaneSpec] = [.line(-9), .line(14, reverse: true), .line(-30)]

    func testDecodeOpenLaneFields() throws {
        let json = #"{"out_m": 14, "back_m": 14, "open": true, "reverse": true, "out_bumps": [{"s": 500, "d": 5, "w": 80}]}"#
        let spec = try JSONDecoder().decode(RowerLaneSpec.self, from: Data(json.utf8))
        XCTAssertEqual(spec, .line(14, reverse: true, bumps: [LaneBump(s: 500, d: 5, w: 80)]))
        // ältere Angaben ohne die Felder bleiben geschlossene Bahnen
        let closed = try JSONDecoder().decode(RowerLaneSpec.self, from: Data(#"{"out_m": -9, "back_m": 22}"#.utf8))
        XCTAssertNil(closed.open)
        XCTAssertNotNil(RowerLane(spec: closed, track: track))
        XCTAssertEqual(RowerLane(spec: closed, track: track)?.form, .closed)
    }

    /// one_way: offene Linien vorwärts und in Gegenrichtung, gerade über Start und Ziel hinaus verlängert, stetig
    func testOpenLaneGeometryOnOneWay() throws {
        let c = oneWayCourse()
        let t = CourseTrack(course: c)
        let fwd = try XCTUnwrap(RowerLane(spec: .line(-9), track: t))
        let rev = try XCTUnwrap(RowerLane(spec: .line(14, reverse: true), track: t))
        XCTAssertEqual(fwd.form, .open)
        XCTAssertEqual(fwd.loopLength, 3000 + 2 * RowerLane.openExtension, accuracy: 1e-9)
        let p = fwd.pose(atW: fwd.w(atS: 800))
        XCTAssertEqual(p.x, 9, accuracy: 1e-6)
        XCTAssertEqual(p.z, -800, accuracy: 1e-6)
        XCTAssertEqual(wrap(p.heading), 0, accuracy: 1e-9)
        let q = rev.pose(atW: rev.w(atS: 800))
        XCTAssertEqual(q.x, -14, accuracy: 1e-6)
        XCTAssertEqual(q.z, -800, accuracy: 1e-6)
        XCTAssertEqual(abs(wrap(q.heading)), Double.pi, accuracy: 1e-9)
        // über das Ziel hinaus gerade weiter; u wie auf einer Strecke mit Wende (Gegenrichtung u = 2L − s)
        XCTAssertEqual(fwd.pose(atW: fwd.w(atS: 3200)).z, -3200, accuracy: 1e-6)
        XCTAssertEqual(fwd.u(fromW: fwd.w(atS: 1234)), 1234, accuracy: 1e-9)
        XCTAssertEqual(rev.u(fromW: rev.w(atS: 1234)), 6000 - 1234, accuracy: 1e-9)
        for lane in [fwd, rev] {
            for u in stride(from: -300.0, through: 6300, by: 37) where lane.reverse ? u > 2600 : u < 3400 {
                XCTAssertEqual(lane.u(fromW: lane.w(fromU: u)), u, accuracy: 1e-6)
            }
            // stetig bis auf den Sprung weit draussen (w = 0 ↔ loopLength, beide ≥ 500 m von der Strecke)
            var prev = lane.pose(atW: 0.5)
            var w = 1.0
            while w < lane.loopLength {
                let pp = lane.pose(atW: w)
                XCTAssertLessThan(hypot(pp.x - prev.x, pp.z - prev.z), 0.5 + 1e-6, "Sprung bei w = \(w)")
                prev = pp
                w += 0.5
            }
            let a = lane.pose(atW: 0), b = lane.pose(atW: lane.loopLength - 1e-6)
            for e in [a, b] { XCTAssertGreaterThanOrEqual(min(abs(e.z), abs(e.z + 3000)), 499) }
        }
    }

    /// Rundkurs: Ringe schliessen nahtlos, auch Ausweichstellen über die Naht bei s = 0 hinweg
    func testRingLaneIsSeamless() throws {
        let c = ringCourse()
        let t = CourseTrack(course: c)
        let lane = try XCTUnwrap(RowerLane(spec: .line(-9, bumps: [LaneBump(s: 20, d: -6, w: 80)]), track: t))
        let rev = try XCTUnwrap(RowerLane(spec: .line(15, reverse: true), track: t))
        XCTAssertEqual(lane.form, .ring)
        XCTAssertEqual(lane.loopLength, 2400, accuracy: 1e-9)
        XCTAssertEqual(lane.lateral(s: 2390, out: true), lane.lateral(s: -10, out: true), accuracy: 1e-9)
        XCTAssertLessThan(lane.lateral(s: 2390, out: true), -9.5, "Ausweichstelle wirkt über die Naht")
        for l in [lane, rev] {
            var prev = l.pose(atW: 0)
            var w = 0.5
            while w <= 2 * l.loopLength {
                let pp = l.pose(atW: w)
                XCTAssertLessThan(hypot(pp.x - prev.x, pp.z - prev.z), 0.6, "Sprung bei w = \(w)")
                XCTAssertLessThan(abs(wrap(pp.heading - prev.heading)), 0.05)
                prev = pp
                w += 0.5
            }
            for u in stride(from: 0.0, to: 4800, by: 41) where l.reverse ? u >= 2400 : u < 2400 {
                XCTAssertEqual(l.u(fromW: l.w(fromU: u)), u, accuracy: 1e-6)
            }
        }
        XCTAssertEqual(lane.along(2390, from: 10), -20, accuracy: 1e-9, "Abstand über die Naht")
    }

    /// one_way mit Ausblenden (fade): Hasen auf der nächsten Linie gleicher Richtung, Bahnruderer auf Gegenverkehr
    /// und weiterer Linie; Sichtband ≥ 40 % (Nachbau: 3 km, 4 Startwerte, normal ca. 60 %), Abstände, niemand taucht
    /// im Bild auf oder verschwindet (ausser beim Rundenwechsel, wo die Szene an den Start springt), nach dem Sprung
    /// neu besetzt.
    func testOneWayRowersOftenInViewAndRestartAtStart() {
        var c = oneWayCourse()
        c.endBehavior = .fade
        var band = 0.0
        for seed: UInt64 in [1, 2, 3, 4] {
            let (run, planner) = simulateRowers(seed: seed, minutes: 30, on: c, lanes: Self.oneWayLanes)
            XCTAssertEqual(planner.innerLane, 0, "Hasen auf der Linie 9 m rechts")
            XCTAssertNil(planner.backHareLane)
            XCTAssertEqual(planner.residentCount, 6, "6 je 4 km Linienlänge (3 km + 2 × 500 m)")
            XCTAssertEqual(run.visiblePops, 0, "Seed \(seed)")
            XCTAssertGreaterThanOrEqual(run.minOwnDistance, 8, "Seed \(seed)")
            XCTAssertGreaterThanOrEqual(run.minPairDistance, 7.99, "Seed \(seed)")
            XCTAssertGreaterThanOrEqual(run.nearAtStart, 1, "Seed \(seed)")
            band += run.bandFraction
        }
        XCTAssertGreaterThanOrEqual(band / 4, 0.4)
        // Rundenwechsel: kurz vor dem Ziel, dann wieder am Start – neu besetzt, ein Hase fährt gleich vorn mit
        var p = VirtualRowers(course: c, density: .normal, seed: 9, lanes: Self.oneWayLanes)
        p.update(time: 0, own: OwnBoat(u: 2990, x: 0, z: -2990, heading: 0, speed: 4))
        p.update(time: 1, own: OwnBoat(u: 2, x: 0, z: -2, heading: 0, speed: 4))
        XCTAssertEqual(p.rowers.filter { $0.hare == nil }.count, 6)
        let hare = p.rowers.first { $0.hare != nil }
        XCTAssertNotNil(hare)
        if let h = hare { XCTAssertEqual(p.lanes[h.lane].u(fromW: h.w) - 2, 22.5, accuracy: 2.6) }
    }

    /// one_way mit Kehre (Standard): Verkehr auf der Runde hin und zurück; die Hasen wechseln mit der Kehre auf die
    /// Gegenverkehrslinie, niemand taucht im Bild auf, Abstände bleiben (Rückfahrt auf derselben Linie wie im Kanal)
    func testOneWayWithTurnKeepsRowersAcrossTurns() {
        var c = oneWayCourse()
        c.returnOffsetM = 0
        c.turnRadiusM = 4.5
        for seed: UInt64 in [1, 2, 3, 4] {
            let (run, planner) = simulateRowers(seed: seed, minutes: 40, on: c, lanes: Self.oneWayLanes)
            XCTAssertEqual(planner.innerLane, 0, "Hasen der Hinfahrt auf der Linie 9 m rechts")
            XCTAssertNotNil(planner.backHareLane, "Hasen der Rückfahrt auf der Gegenverkehrslinie")
            XCTAssertEqual(run.visiblePops, 0, "Seed \(seed)")
            XCTAssertGreaterThanOrEqual(run.minOwnDistance, 5, "Seed \(seed)")
        }
    }

    /// Rundkurs: die Lagen laufen über die Rundengrenze weiter (kein Neubesetzen), Sichtband ≥ 40 %
    func testLoopCourseRowersContinueOverLaps() {
        let c = ringCourse()
        var band = 0.0
        for seed: UInt64 in [1, 2, 3, 4] {
            let (run, planner) = simulateRowers(seed: seed, minutes: 30, on: c,
                                                lanes: [.line(-9), .line(15, reverse: true), .line(-25)])
            XCTAssertEqual(run.visiblePops, 0, "Seed \(seed)")
            XCTAssertGreaterThanOrEqual(run.minOwnDistance, 8, "Seed \(seed)")
            XCTAssertGreaterThanOrEqual(run.minPairDistance, 7.99, "Seed \(seed)")
            let residents = Set(1...planner.residentCount)
            XCTAssertTrue(residents.isSubset(of: Set(planner.rowers.map(\.id))), "Seed \(seed): Bahnruderer bleiben")
            band += run.bandFraction
        }
        XCTAssertGreaterThanOrEqual(band / 4, 0.4)
    }

    /// Schmale Strecke mit Wende (Berlin Spree): offene Linien je Richtung, die Hasen wechseln mit der Wende auf die
    /// Linie der Rückfahrt; keine Bahnruderer, Sichtband 8–45 m ≥ 40 %.
    func testNarrowOutAndBackUsesOpenLinesPerDirection() {
        let lanes: [RowerLaneSpec] = [.line(-8), .line(19, reverse: true)]
        let p0 = VirtualRowers(course: course, density: .normal, seed: 3, lanes: lanes)
        XCTAssertEqual(p0.residentCount, 0)
        XCTAssertEqual(p0.innerLane, 0)
        XCTAssertEqual(p0.backHareLane, 1)
        XCTAssertEqual(p0.hareLane(at: 500), 0)
        XCTAssertEqual(p0.hareLane(at: 2500), 1)
        var band = 0.0
        for seed: UInt64 in [1, 2, 3, 4] {
            let (run, planner) = simulateRowers(seed: seed, minutes: 40, on: course, lanes: lanes, bandFar: 45)
            XCTAssertEqual(run.visiblePops, 0, "Seed \(seed)")
            XCTAssertGreaterThanOrEqual(run.minOwnDistance, 5, "Seed \(seed)")
            XCTAssertTrue(planner.rowers.allSatisfy { $0.hare != nil })
            band += run.bandFraction
        }
        XCTAssertGreaterThanOrEqual(band / 4, 0.4)
    }

    /// Strecken ohne Angabe: auf one_way die offenen Standardlinien, Stege nur für geschlossene Bahnen
    func testOneWayDefaultsAndNoDocksOnOpenLines() {
        let c = oneWayCourse()
        let p = VirtualRowers(course: c, density: .normal, seed: 1)
        XCTAssertEqual(p.lanes.map(\.form), [.open, .open])
        XCTAssertEqual(p.lanes.map(\.reverse), [false, true])
        let dock = RowerDockSpec(id: "d", lane: 0, joinU: 500, enterXZ: [[30, -400], [9, -460]], exitXZ: [[9, -540], [30, -600]])
        XCTAssertTrue(VirtualRowers(course: c, density: .normal, seed: 1, lanes: Self.oneWayLanes, docks: [dock]).docks.isEmpty)
    }

    private func loadCourse(_ id: String) throws -> Course {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("courses/\(id)/course.json")
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("Kartenpaket fehlt: \(url.path)") }
        return try Course.decode(Data(contentsOf: url))
    }

    /// Echte Strecken mit offenen Linien (lanes.py): Frankfurt Main (one_way mit Kehre, Hasen, Gegenverkehr, dritte
    /// Linie; Sichtband 8–30 m, ≥ 33 %) und Berlin Spree-Mitte (schmal mit Wende, nur Hasen; 8–45 m, ≥ 40 %).
    func testRealOpenLaneCoursesKeepRowersInView() throws {
        // Frankfurt fährt seit end_behavior "turn" (Versatz 0) im Training hin und zurück; auf der Rückfahrt liegen
        // nur Hasen der Gegenverkehrslinie im Band (Nachbau 4 Startwerte: ca. 35 % statt 62 % mit Sprung zum Start)
        for (id, far, minBand) in [("frankfurt-main", 30.0, 0.33), ("berlin-spree-mitte", 45.0, 0.4)] {
            let c = try loadCourse(id)
            guard let lanes = c.traffic?.rowerLanes, !lanes.isEmpty else { throw XCTSkip("\(id): keine Ruderer-Bahnen") }
            XCTAssertTrue(lanes.allSatisfy { $0.open == true }, id)
            var band = 0.0
            for seed: UInt64 in [2026, 1, 2, 3] {
                let (run, _) = simulateRowers(seed: seed, minutes: 30, on: c, bandFar: far)
                XCTAssertEqual(run.visiblePops, 0, "\(id) Seed \(seed)")
                XCTAssertGreaterThanOrEqual(run.minOwnDistance, 5, "\(id) Seed \(seed)")
                band += run.bandFraction
            }
            XCTAssertGreaterThanOrEqual(band / 4, minBand, id)
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

    /// Außenalster: Segelrevier und eigene Abstände je Art – regelmässig 2–4 Segelboote zugleich, Alsterdampfer selten.
    func testSailingAreaKeepsSeveralSailboats() {
        var c = Course.straight(id: "hamburg-aussenalster", oneWay: 2000)
        var lanes: [VesselLaneSpec] = [150.0, 220, 290, 360, 430].enumerated().map { i, x in
            VesselLaneSpec(id: "s\(i)", kind: .sail, minDistM: x - 12, pointsXZ: [[x, -100], [x, -1900]])
        }
        lanes.append(VesselLaneSpec(id: "s5", kind: .sail, minDistM: 100, pointsXZ: [[120, -300], [460, -1700]]))
        lanes.append(VesselLaneSpec(id: "p1", kind: .parallel, minDistM: 52, pointsXZ: [[64, 300], [64, -2300]]))
        c.traffic = CourseTraffic(vessels: ["alsterdampfer", "segelboot", "motorboot", "tretboot"], vesselLanes: lanes,
                                  vesselIntervals: ["segelboot": [45, 120], "alsterdampfer": [600, 900]])
        var traffic = VesselTraffic(course: c, density: .normal, seed: 3)
        XCTAssertEqual(traffic.kinds, [.alsterdampfer, .segelboot, .motorboot, .tretboot])
        XCTAssertEqual(traffic.interval(of: .segelboot), 45...120)
        let laps = LapTrack(track: CourseTrack(course: c))
        var sailSum = 0, samples = 0, maxSail = 0, minPair = Double.infinity, steamers = Set<Int>()
        var t = 0.0
        while t < 1200 {
            let o = own(at: t, speed: 4, laps: laps)
            traffic.update(time: t, own: o)
            let st = traffic.states(at: t)
            let sail = st.filter { $0.kind == .segelboot }.count
            if t.truncatingRemainder(dividingBy: 10) == 0 { sailSum += sail; samples += 1 }
            maxSail = max(maxSail, sail)
            for s in st where s.kind == .alsterdampfer { steamers.insert(s.id) }
            for (i, a) in st.enumerated() {
                XCTAssertGreaterThanOrEqual(hypot(a.x - o.x, a.z - o.z), a.kind.minDistance, "\(a.kind) zu nah")
                for b in st[(i + 1)...] { minPair = min(minPair, hypot(a.x - b.x, a.z - b.z)) }
            }
            t += 2
        }
        XCTAssertGreaterThanOrEqual(Double(sailSum) / Double(samples), 2, "im Mittel mindestens 2 Segelboote")
        XCTAssertLessThanOrEqual(maxSail, 8)
        XCTAssertLessThanOrEqual(steamers.count, 3, "Alsterdampfer etwa alle 10–15 min")
        XCTAssertGreaterThanOrEqual(minPair, 15)
        // Segelrevier nur für Segel- und Tretboote
        let sailLane = lanes[0]
        XCTAssertTrue(VesselKind.segelboot.allows(sailLane))
        XCTAssertTrue(VesselKind.tretboot.allows(sailLane))
        XCTAssertFalse(VesselKind.motorboot.allows(sailLane))
        XCTAssertFalse(VesselKind.alsterdampfer.allows(sailLane))
        XCTAssertEqual(TrafficDefaults.vessels(for: Course.straight(id: "hamburg-aussenalster")),
                       [.alsterdampfer, .segelboot, .motorboot, .tretboot])
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
