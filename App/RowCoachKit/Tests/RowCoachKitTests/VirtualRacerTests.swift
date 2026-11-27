import Foundation
import XCTest
@testable import RowCoachKit

/// Virtuelle Teilnehmende (docs/MULTIPLAYER.md „Virtuelle Teilnehmende“): Pool, Mindestfeld, Auffüllen, Zeitzonen,
/// Rotation, Niveau, deterministische Rennen, Ranglisten.
final class VirtualRacerTests: XCTestCase {
    /// Pool-Datei im App-Bundle (App/RowCoach/Resources)
    static let poolURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("RowCoach/Resources/\(VirtualRowerPool.fileName())")

    static let pool: VirtualRowerPool = {
        if let data = try? Data(contentsOf: poolURL), let p = try? VirtualRowerPool.decode(data) { return p }
        return VirtualRowerPool.generate()
    }()

    /// UTC-Zeitpunkt aus Datum und Uhrzeit
    static func utc(_ y: Int, _ m: Int, _ d: Int, _ h: Double) -> TimeInterval {
        Double(DetMath.days(year: y, month: m, day: d)) * 86400 + h * 3600
    }

    // MARK: Rechenhilfen

    func testDeterministicMathMatchesFoundation() {
        for x in [1e-6, 0.01, 0.37, 1, 1.5, 2.718, 10, 123.4, 1e6] {
            XCTAssertEqual(DetMath.ln(x), Foundation.log(x), accuracy: 1e-13 * max(1, abs(Foundation.log(x))))
            XCTAssertEqual(DetMath.cbrt(x), Foundation.cbrt(x), accuracy: 1e-13 * Foundation.cbrt(x))
        }
        for x in [-20.0, -3.3, -0.5, 0, 0.1, 1, 5.5, 30] {
            XCTAssertEqual(DetMath.exp(x), Foundation.exp(x), accuracy: 1e-13 * Foundation.exp(x))
            XCTAssertEqual(DetMath.sin(x), Foundation.sin(x), accuracy: 1e-13)
        }
        XCTAssertEqual(DetMath.pow(2, 10), 1024, accuracy: 1e-10)
        // Kalender
        XCTAssertEqual(DetMath.days(year: 1970, month: 1, day: 1), 0)
        let d = DetMath.days(year: 2026, month: 11, day: 27)
        XCTAssertTrue(DetMath.civil(days: d) == (2026, 11, 27))
        XCTAssertEqual(DetMath.weekday(days: d), 5)  // Freitag
    }

    func testDaylightSavingRules() {
        let eu = VirtualDSTRule.eu
        XCTAssertFalse(eu.isActive(days: DetMath.days(year: 2026, month: 3, day: 28)))
        XCTAssertTrue(eu.isActive(days: DetMath.days(year: 2026, month: 3, day: 29)))
        XCTAssertTrue(eu.isActive(days: DetMath.days(year: 2026, month: 10, day: 24)))
        XCTAssertFalse(eu.isActive(days: DetMath.days(year: 2026, month: 10, day: 25)))
        XCTAssertTrue(VirtualDSTRule.us.isActive(days: DetMath.days(year: 2026, month: 3, day: 8)))
        XCTAssertFalse(VirtualDSTRule.us.isActive(days: DetMath.days(year: 2026, month: 11, day: 1)))
        XCTAssertTrue(VirtualDSTRule.nz.isActive(days: DetMath.days(year: 2026, month: 11, day: 27)))
        XCTAssertFalse(VirtualDSTRule.nz.isActive(days: DetMath.days(year: 2026, month: 6, day: 1)))
        // Zürich im Sommer: 17:00 UTC = 19:00 Ortszeit
        XCTAssertEqual(VirtualRowerCountries.localHour(at: Self.utc(2026, 6, 15, 17), offsetMinutes: 60, dst: .eu), 19,
                       accuracy: 1e-9)
    }

    // MARK: Pool

    func testPoolFileMatchesGeneratorAndIsCompact() throws {
        if ProcessInfo.processInfo.environment["ROWCOACH_WRITE_POOL"] == "1" {
            try VirtualRowerPool.generate().encoded().write(to: Self.poolURL)
        }
        let data = try Data(contentsOf: Self.poolURL)
        let pool = try VirtualRowerPool.decode(data)
        XCTAssertEqual(pool.version, 1)
        XCTAssertEqual(pool.rowers.count, 5000)
        XCTAssertEqual(pool, VirtualRowerPool.generate(), "Pool v1 darf sich nie ändern – neue Version anlegen")
        XCTAssertEqual(pool.encoded(), data)
        XCTAssertLessThan(data.count, 120_000)
        print("Pool v1: \(data.count) Byte, \(String(format: "%.1f", Double(data.count) / 5000)) Byte je Person")
        XCTAssertEqual(Set(pool.rowers.map(\.id)).count, 5000)
        XCTAssertEqual(pool.rower(id: "v1-0042")?.number, 42)
        XCTAssertTrue(VirtualRowerPool.isVirtualId("v1-0042"))
        XCTAssertFalse(VirtualRowerPool.isVirtualId("bot-001"))
        // beschädigte Datei
        var bad = data
        bad[100] ^= 0xFF
        XCTAssertThrowsError(try VirtualRowerPool.decode(bad))
    }

    func testPoolDistributions() {
        let rowers = Self.pool.rowers
        var byCountry: [String: Int] = [:]
        for r in rowers { byCountry[r.country, default: 0] += 1 }
        XCTAssertGreaterThanOrEqual(byCountry.count, 50, "viele Länder")
        let share = { (codes: [String]) in Double(codes.map { byCountry[$0] ?? 0 }.reduce(0, +)) / Double(rowers.count) }
        XCTAssertEqual(share(["US"]), 0.20, accuracy: 0.03)
        let europe = share(VirtualRowerCountries.all.prefix(39).map(\.code))
        let northAmerica = share(["US", "CA", "MX", "PR"])
        let oceania = share(["AU", "NZ"])
        XCTAssertGreaterThan(europe + northAmerica + oceania, 0.85)
        XCTAssertGreaterThan(1 - europe - northAmerica - oceania, 0.05, "aber global")
        print("Länder: Europa \(europe), Nordamerika \(northAmerica), Ozeanien \(oceania), US \(share(["US"])), "
              + "GB \(share(["GB"])), DE \(share(["DE"])), CA \(share(["CA"])), AU \(share(["AU"])), \(byCountry.count) Länder")
        // Leistung: Median der Männer ≈ 7:49, Frauen ≈ 8:51 (Concept2-Rangliste 2025)
        func median(_ xs: [Double]) -> Double { let s = xs.sorted(); return s[s.count / 2] }
        XCTAssertEqual(median(rowers.filter { $0.group == .m }.map(\.best2k)), 469, accuracy: 8)
        XCTAssertEqual(median(rowers.filter { $0.group == .w }.map(\.best2k)), 531, accuracy: 12)
        XCTAssertEqual(Double(rowers.filter { $0.group == .w }.count) / 5000, 0.25, accuracy: 0.03)
        // Stile, Zuverlässigkeit, Stunden
        for s in VirtualRacer.Style.allCases { XCTAssertGreaterThan(rowers.filter { $0.style == s }.count, 300) }
        XCTAssertTrue(rowers.allSatisfy { (0.15...1).contains($0.reliability) && (6...21).contains($0.preferredHour) })
        XCTAssertGreaterThan(rowers.filter { $0.reliability < 0.4 }.count, 100, "manche fahren selten")
        // Schwelle plausibel (2k 7:49 → ≈ 200 W Schwelle)
        let t = rowers.first { abs($0.best2k - 469) < 2 }!.threshold
        XCTAssertTrue((150...260).contains(t), "\(t)")
    }

    func testNamesMatchCountry() {
        for r in Self.pool.rowers {
            guard let n = VirtualRowerNames.names(r.country) else { return XCTFail("keine Namen für \(r.country)") }
            XCTAssertTrue((r.group == .w ? n.female : n.male).contains(r.firstName), "\(r.firstName) \(r.country)")
        }
        let p = Self.pool.rowers[0].participant(lane: 5)
        XCTAssertEqual(p.source, .virtual)
        XCTAssertTrue(p.isVirtual)
        XCTAssertEqual(p.appearance?.nationality, Self.pool.rowers[0].country)
        XCTAssertTrue(p.appearance?.flagOnBoat ?? false)
        XCTAssertEqual(p.nameWithCountry, "\(Self.pool.rowers[0].firstName) · \(Self.pool.rowers[0].country)")
    }

    func testSourceDecodesBackwardCompatible() throws {
        func decode(_ source: String) throws -> RaceParticipant {
            let json = "{\"id\":\"x\",\"displayName\":\"X\",\"lane\":1,\"source\":\"\(source)\"}"
            return try JSONDecoder().decode(RaceParticipant.self, from: Data(json.utf8))
        }
        XCTAssertEqual(try decode("human").source, .human)
        XCTAssertEqual(try decode("virtual").source, .virtual)
        XCTAssertEqual(try decode("something-new").source, .bot)
        let p = RaceParticipant(id: "v1-0001", displayName: "Lea", lane: 2, source: .virtual)
        let back = try JSONDecoder().decode(RaceParticipant.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back, p)
    }

    // MARK: Mindestfeld und Auffüllen

    func testMinimumFieldUniformAndDeterministic() {
        var counts = [Int](repeating: 0, count: 388)
        let n = 343 * 200
        for i in 0..<n {
            let k = TournamentFieldFiller.minimumField(tournamentId: "t-\(i)", seed: 7)
            XCTAssertTrue((45...387).contains(k))
            counts[k] += 1
        }
        let used = counts[45...387]
        XCTAssertGreaterThan(used.min()!, 140)
        XCTAssertLessThan(used.max()!, 260)
        // Chi-Quadrat (342 Freiheitsgrade, 99,9 %-Schranke ≈ 431)
        var chi = 0.0
        for c in used { chi += Double((c - 200) * (c - 200)) / 200 }
        XCTAssertLessThan(chi, 431)
        XCTAssertEqual(TournamentFieldFiller.minimumField(tournamentId: "abc", seed: 1),
                       TournamentFieldFiller.minimumField(tournamentId: "abc", seed: 1))
    }

    func real(_ n: Int) -> [RaceParticipant] {
        (0..<n).map { RaceParticipant(id: "u\($0)", displayName: "U\($0)", lane: $0 + 1) }
    }

    func testFillExactlyToMinimum() {
        let t = Self.utc(2026, 11, 27, 18)
        for i in 0..<20 {
            let reals = real(i % 4)
            let f = TournamentFieldFiller.fill(tournamentId: "t\(i)", raceId: "r", seed: 3, real: reals,
                                               pool: Self.pool, startsAt: t)
            XCTAssertEqual(f.total, f.minimumField)
            XCTAssertEqual(f.realCount, reals.count)
            XCTAssertEqual(Array(f.participants.prefix(reals.count)), reals)
            XCTAssertTrue(f.participants.dropFirst(reals.count).allSatisfy(\.isVirtual))
            XCTAssertEqual(Set(f.participants.map(\.id)).count, f.total)
            XCTAssertEqual(Set(f.participants.map(\.lane)).count, f.total)
        }
        // deterministisch
        let a = TournamentFieldFiller.fill(tournamentId: "x", raceId: "r", seed: 3, real: real(2), pool: Self.pool, startsAt: t)
        let b = TournamentFieldFiller.fill(tournamentId: "x", raceId: "r", seed: 3, real: real(2), pool: Self.pool, startsAt: t)
        XCTAssertEqual(a, b)
    }

    func testNoFillWithManyRealParticipants() {
        let reals = real(400)
        let f = TournamentFieldFiller.fill(tournamentId: "big", raceId: "r", seed: 1, real: reals, pool: Self.pool,
                                           startsAt: Self.utc(2026, 11, 27, 18))
        XCTAssertEqual(f.virtualCount, 0)
        XCTAssertEqual(f.total, 400)
        // genau am Mindestfeld: keine virtuellen
        let k = TournamentFieldFiller.minimumField(tournamentId: "edge", seed: 1)
        let g = TournamentFieldFiller.fill(tournamentId: "edge", raceId: "r", seed: 1, real: real(k), pool: Self.pool,
                                           startsAt: Self.utc(2026, 11, 27, 18))
        XCTAssertEqual(g.virtualCount, 0)
    }

    // MARK: Zeitzonen

    func countries(at t: TimeInterval, count: Int = 380, runs: Int = 5) -> [String: Int] {
        var c: [String: Int] = [:]
        for i in 0..<runs {
            let picked = TournamentFieldFiller.select(count: count, raceKey: "tz\(i)", seed: 9, realLevels: [],
                                                      pool: Self.pool, startsAt: t, history: VirtualRowerHistory())
            XCTAssertEqual(picked.count, count)
            for r in picked {
                let h = r.localHour(at: t)
                XCTAssertTrue(h >= 6 && h < 22, "\(r.country) \(h)")
                c[r.country, default: 0] += 1
            }
        }
        return c
    }

    func testTimeWindowEveningInEurope() {
        // 19:00 in Zürich (Sommer, MESZ): Japan 02:00, Neuseeland 05:00, Sydney 03:00
        let summer = countries(at: Self.utc(2026, 6, 15, 17))
        for code in ["JP", "NZ", "AU", "KR", "CN", "TW", "PH"] { XCTAssertNil(summer[code], code) }
        XCTAssertGreaterThan(summer["US"] ?? 0, 0)
        XCTAssertGreaterThan(summer["DE"] ?? 0, 0)
        // 19:00 MEZ im November: Japan 03:00 (nie); Neuseeland hat Sommerzeit, dort ist es 07:00 – erlaubt
        let winter = countries(at: Self.utc(2026, 11, 27, 18))
        for code in ["JP", "AU", "KR", "CN", "TW"] { XCTAssertNil(winter[code], code) }
    }

    func testTimeWindowMorningInEurope() {
        // 08:00 MEZ (07:00 UTC): Sydney 18:00, Auckland 20:00, Tokio 16:00 – Ozeanien und Asien möglich; New York 02:00
        let c = countries(at: Self.utc(2026, 11, 27, 7))
        XCTAssertGreaterThan((c["AU"] ?? 0) + (c["NZ"] ?? 0), 20)
        XCTAssertGreaterThan((c["JP"] ?? 0) + (c["CN"] ?? 0) + (c["KR"] ?? 0), 0)
        XCTAssertNil(c["US"])
        XCTAssertNil(c["CA"])
    }

    // MARK: Rotation und Niveau

    func testRotationLimitsRepeats() {
        var history = VirtualRowerHistory()
        var lastDay: [String: Int] = [:]
        var picks = 0, repeatsWithinWeek = 0, nextDay = 0
        var total: [String: Int] = [:]
        var days: [String: [Int]] = [:]
        for day in 0..<30 {
            let t = Self.utc(2026, 11, 1, 18) + Double(day) * 86400
            let picked = TournamentFieldFiller.select(count: 300, raceKey: "rot\(day)", seed: 5, realLevels: [],
                                                      pool: Self.pool, startsAt: t, history: history)
            for r in picked {
                picks += 1
                if let d = lastDay[r.id], day - d <= 7 { repeatsWithinWeek += 1 }
                if let d = lastDay[r.id], day - d == 1 { nextDay += 1 }
                days[r.id, default: []].append(day)
                lastDay[r.id] = day
                total[r.id, default: 0] += 1
            }
            history.record(picked.map(\.id), at: t)
        }
        let rate = Double(repeatsWithinWeek) / Double(picks)
        let nextDayRate = Double(nextDay) / Double(picks)
        // meiste Rennen einer Person in irgendeinem 7-Tage-Fenster
        var maxWeek = 0
        for list in days.values {
            for (i, d) in list.enumerated() { maxWeek = max(maxWeek, list[i...].prefix { $0 - d < 7 }.count) }
        }
        print("Rotation: \(picks) Plätze, Wiederholung binnen 7 Tagen \(String(format: "%.1f", rate * 100)) %, "
              + "am Folgetag \(String(format: "%.1f", nextDayRate * 100)) %, verschiedene Personen \(total.count), "
              + "höchstens \(total.values.max() ?? 0) Rennen je Person in 30 Tagen, \(maxWeek) in 7 Tagen")
        // 300 Plätze täglich zur selben Uhrzeit bei ≈ 2800 erreichbaren Personen: Wiederholungen binnen einer Woche
        // sind unvermeidlich; begrenzt werden Folgetage und Häufung
        XCTAssertLessThan(nextDayRate, 0.03)
        XCTAssertLessThanOrEqual(maxWeek, 3)
        XCTAssertLessThan(rate, 0.5)
        XCTAssertLessThanOrEqual(total.values.max() ?? 0, 15)
        XCTAssertGreaterThan(total.count, 1500)
        // nie zweimal am selben Ortstag
        let t = Self.utc(2026, 12, 5, 17)
        let first = TournamentFieldFiller.select(count: 300, raceKey: "a", seed: 5, realLevels: [], pool: Self.pool,
                                                 startsAt: t, history: VirtualRowerHistory())
        var h = VirtualRowerHistory()
        h.record(first.map(\.id), at: t)
        let second = TournamentFieldFiller.select(count: 300, raceKey: "b", seed: 5, realLevels: [], pool: Self.pool,
                                                  startsAt: t + 2 * 3600, history: h)
        XCTAssertTrue(Set(first.map(\.id)).isDisjoint(with: second.map(\.id)))
    }

    func testLevelFollowsRealParticipants() {
        let t = Self.utc(2026, 11, 27, 18)
        func median(_ levels: [Double]) -> Double {
            let p = TournamentFieldFiller.select(count: 200, raceKey: "lvl\(levels.first ?? 0)", seed: 2,
                                                 realLevels: levels, pool: Self.pool, startsAt: t,
                                                 history: VirtualRowerHistory())
            return TournamentFieldFiller.median(p.map(\.best2k))
        }
        let fast = median([385, 390, 395, 400])
        let slow = median([560, 570, 580])
        XCTAssertEqual(fast, 392, accuracy: 25)
        XCTAssertEqual(slow, 570, accuracy: 30)
        // Leistungsklasse hart
        var cfg = TournamentFieldFiller.Config()
        cfg.levelClass = 420...450
        let cls = TournamentFieldFiller.select(count: 100, raceKey: "cls", seed: 2, realLevels: [], pool: Self.pool,
                                               startsAt: t, history: VirtualRowerHistory(), config: cfg)
        XCTAssertTrue(cls.allSatisfy { (420...450).contains($0.best2k) })
    }

    // MARK: Rennen

    func testRaceSimulationIsDeterministicAndPlausible() {
        let ctx = VirtualRaceContext(raceId: "race-1", startsAt: Self.utc(2026, 11, 27, 18), target: .distance(2000))
        var errors: [Double] = []
        for r in Self.pool.rowers.prefix(400) {
            let a = VirtualRaceSimulator.run(r, context: ctx)
            let b = VirtualRaceSimulator.run(r, context: ctx)
            XCTAssertEqual(a, b)
            guard let ft = a.finishTime else { return XCTFail("nicht im Ziel") }
            XCTAssertEqual(ft, (ft * 1000).rounded() / 1000)
            // Ziel nahe der erwarteten Zeit an diesem Tag (Anlauf ausgeglichen, Stil normiert)
            let expected = VirtualRaceSimulator.expectedTime(r, distance: 2000, form: a.formFactor)
            errors.append(abs(ft - expected) / expected)
            // Form 1 → 2k-Zeit des Profils
            XCTAssertEqual(VirtualRaceSimulator.expectedTime(r, distance: 2000), r.best2k, accuracy: 0.01)
            XCTAssertTrue((0.75...1.2).contains(a.formFactor))
        }
        errors.sort()
        XCTAssertLessThan(errors[errors.count / 2], 0.01)
        XCTAssertLessThan(errors.last!, 0.03)
        // anderes Rennen → andere Tagesform
        let other = VirtualRaceContext(raceId: "race-2", startsAt: ctx.startsAt, target: .distance(2000))
        let r0 = Self.pool.rowers[0]
        XCTAssertNotEqual(VirtualRaceSimulator.run(r0, context: ctx).finishTime,
                          VirtualRaceSimulator.run(r0, context: other).finishTime)
        // Winter stärker als Sommer (Nordhalbkugel)
        let n = Self.pool.rowers.first { $0.hemisphere == .north && $0.season > 0.03 }!
        XCTAssertGreaterThan(VirtualRaceSimulator.seasonPhase(days: DetMath.days(year: 2026, month: 2, day: 14), hemisphere: .north), 0.9)
        XCTAssertLessThan(VirtualRaceSimulator.seasonPhase(days: DetMath.days(year: 2026, month: 8, day: 15), hemisphere: .north), -0.9)
        XCTAssertGreaterThan(VirtualRaceSimulator.seasonPhase(days: DetMath.days(year: 2026, month: 8, day: 15), hemisphere: .south), 0.9)
        XCTAssertGreaterThan(n.season, 0.03)
        // Zeitrennen
        let tr = VirtualRaceSimulator.run(r0, context: VirtualRaceContext(raceId: "t", startsAt: ctx.startsAt, target: .time(600)))
        XCTAssertNil(tr.finishTime)
        XCTAssertEqual(tr.track.count, 601)
        XCTAssertGreaterThan(tr.finalDistance, 1500)
    }

    func testTournamentRaceFieldAndResults() async {
        let t = Self.utc(2026, 11, 27, 18)
        let race = Race(id: "tr-1", tournamentId: "tour-1", courseId: "rhein-basel", target: .distance(2000), lanes: 400)
        let me = RaceParticipant(id: "me", displayName: "Ich", lane: 1)
        let field = TournamentFieldFiller.fill(tournamentId: "tour-1", raceId: race.id, seed: 1, real: [me],
                                               pool: Self.pool, startsAt: t)
        let tr = VirtualTournamentRace(race: race, startsAt: t, field: field)
        XCTAssertEqual(tr.runs.count, field.virtualCount)
        let botField = tr.botField
        XCTAssertEqual(botField.bots.count, field.virtualCount)
        // Positionen des Feldes folgen den Läufen
        for (i, run) in tr.runs.enumerated().prefix(20) {
            let p = botField.position(of: i, at: 60)
            XCTAssertEqual(p.distance, run.track[60], accuracy: 1e-9)
            let f = botField.position(of: i, at: 10_000)
            XCTAssertTrue(f.finished)
            XCTAssertEqual(f.finishTime, run.finishTime)
        }
        XCTAssertTrue(botField.members(at: 30).allSatisfy { $0.source == .virtual })
        // Ergebnisse mit mir
        let mine = RaceResult(participantId: "me", place: 0, distance: 2000, time: 420, finished: true)
        let results = tr.results(real: [mine])
        XCTAssertEqual(results.count, field.total)
        XCTAssertEqual(results.map(\.place), Array(1...field.total))
        let times = results.compactMap(\.time)
        XCTAssertEqual(times, times.sorted())
        // Transport spielt das Feld ab
        let transport = RaceBotTransport(field: botField) { nil }
        let roster = try? await transport.join(race: race, as: me)
        XCTAssertEqual(roster?.count, field.total)
        let snap = transport.snapshot(raceId: race.id, raceTime: 30, sentAt: 0)
        XCTAssertEqual(snap.entries.count, field.virtualCount)
        await transport.leave()
        // Rangliste
        var book = RaceRankingBook()
        book.add(results: results, race: race, startsAt: t, participants: field.participants)
        XCTAssertEqual(book.results(raceId: race.id).count, field.total)
        let realOnly = book.results(raceId: race.id, filter: .realOnly)
        XCTAssertEqual(realOnly.map(\.participantId), ["me"])
        XCTAssertEqual(realOnly.first?.place, 1)
        XCTAssertEqual(book.leaderboard(distance: 2000).count, field.total)
        XCTAssertEqual(book.leaderboard(distance: 2000, filter: .realOnly).count, 1)
        XCTAssertEqual(book.virtualHistory.lastRaced.count, field.virtualCount)
        let data = try! book.encoded()
        XCTAssertEqual(RaceRankingBook.decode(data), book)
    }

    func testOwnResultFromSamples() {
        // 3 s Stillstand vor dem ersten Schlag, dann 4 m/s
        var samples = (0...3).map { WorkoutSample(time: Double($0), distance: 0, pace: 0, strokeRate: 0, power: 0, heartRate: nil) }
        samples += (1...600).map { WorkoutSample(time: 3 + Double($0), distance: 4 * Double($0), pace: 125, strokeRate: 24, power: 180, heartRate: nil) }
        let r = RaceResult.fromSamples(participantId: "me", samples: samples, target: .distance(2000))
        XCTAssertTrue(r.finished)
        XCTAssertEqual(r.time ?? 0, 500, accuracy: 0.001)
        let short = RaceResult.fromSamples(participantId: "me", samples: Array(samples.prefix(100)), target: .distance(2000))
        XCTAssertFalse(short.finished)
        XCTAssertNil(short.time)
        let timed = RaceResult.fromSamples(participantId: "me", samples: samples, target: .time(300))
        XCTAssertEqual(timed.distance, 1200, accuracy: 0.001)
    }

    func testSeasonStandingsBestOf() {
        XCTAssertEqual(RowingSeason.id(at: Self.utc(2026, 11, 27, 12)), "2026/27")
        XCTAssertEqual(RowingSeason.id(at: Self.utc(2027, 4, 30, 12)), "2026/27")
        XCTAssertEqual(RowingSeason.id(at: Self.utc(2027, 5, 1, 12)), "2027/28")
        var book = RaceRankingBook()
        // virtuelle Person fährt 20 Rennen (Sieg), echte 5 Rennen (Sieg): es zählen höchstens 10
        for i in 0..<20 {
            book.entries.append(RaceRecordEntry(raceId: "r\(i)", tournamentId: nil, courseId: "c",
                                                date: Self.utc(2026, 11, 1 + i, 18), target: .distance(2000),
                                                participantId: "v1-0001", displayName: "Lea", country: "SE",
                                                isVirtual: true, place: 1, fieldSize: 50, time: 400, distance: 2000,
                                                finished: true))
        }
        for i in 0..<5 {
            book.entries.append(RaceRecordEntry(raceId: "h\(i)", tournamentId: nil, courseId: "c",
                                                date: Self.utc(2026, 11, 1 + i, 18), target: .distance(2000),
                                                participantId: "me", displayName: "Ich", country: nil,
                                                isVirtual: false, place: 1, fieldSize: 50, time: 410, distance: 2000,
                                                finished: true))
        }
        let all = book.seasonStandings(season: "2026/27")
        XCTAssertEqual(all.first?.participantId, "v1-0001")
        XCTAssertEqual(all.first?.value, 1000)
        XCTAssertEqual(all.first?.races, 20)
        XCTAssertEqual(all.last?.value, 500)
        XCTAssertEqual(book.seasonStandings(season: "2026/27", filter: .realOnly).map(\.participantId), ["me"])
    }
}
