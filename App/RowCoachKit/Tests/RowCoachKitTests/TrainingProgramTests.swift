import XCTest
@testable import RowCoachKit

/// Kleine Pläne und Programme für die Tests der Trainingspläne. Tag 0 = Montag, 30.11.2026 (Zürich).
enum ProgramFixture {
    static let cal = StatsFixture.cal
    static let monday = StatsFixture.date(2026, 11, 30, 0, 0)

    /// Tag `offset` ab Montag 30.11.2026, `hour` Uhr
    static func day(_ offset: Int, hour: Int = 10) -> Date {
        let d = cal.date(byAdding: .day, value: offset, to: monday)!
        return cal.date(bySettingHour: hour, minute: 0, second: 0, of: d)!
    }

    static func start(_ offset: Int) -> Date { cal.startOfDay(for: day(offset)) }

    private static func workout(_ id: String, _ category: String, minutes: Double, zone: Int,
                                distance: Double? = nil) -> WorkoutPlan {
        let work = distance.map { WorkoutPhase(kind: .work, distanceM: $0, hrZone: zone, paceOffsetMinS: 0, paceOffsetMaxS: 2) }
            ?? WorkoutPhase(kind: .work, durationS: minutes * 60 - 600, hrZone: zone, paceOffsetMinS: 2, paceOffsetMaxS: 6)
        return WorkoutPlan(id: id, name: id, category: category,
                           phases: [WorkoutPhase(kind: .warmup, durationS: 300, hrZone: 2), work,
                                    WorkoutPhase(kind: .cooldown, durationS: 300, hrZone: 1)])
    }

    static let workouts: [WorkoutPlan] = [
        workout("grundlage-locker-30", "Grundlage", minutes: 30, zone: 2),
        workout("grundlage-3x10-r20", "Grundlage", minutes: 40, zone: 2),
        workout("grundlage-ut2-20", "Grundlage", minutes: 28, zone: 2),
        workout("grundlage-locker-45", "Grundlage", minutes: 45, zone: 2),
        workout("technik-locker-25", "Technik & Rhythmus", minutes: 25, zone: 2),
        workout("regeneration-20", "Regeneration", minutes: 20, zone: 1),
        workout("schwelle-4x6", "Schwelle", minutes: 45, zone: 4),
        workout("kurzintervalle-8x2", "Intervalle", minutes: 40, zone: 5),
        workout("langintervalle-4x4", "Intervalle", minutes: 42, zone: 5),
        workout("test-2000m", "Test", minutes: 20, zone: 5, distance: 2000),
        workout("test-1000m", "Test", minutes: 15, zone: 5, distance: 1000),
    ]

    static func s(_ planId: String, _ intensity: PlanIntensity = .easy, optional: Bool = false,
                  event: Bool = false) -> ProgramSession {
        ProgramSession(slot: 0, planId: planId, optional: optional, intensity: intensity, event: event)
    }

    static func program(_ id: String = "testplan", weeks: [[ProgramSession]], rules: ProgramRules = ProgramRules(),
                        deload: Set<Int> = []) -> TrainingProgram {
        let wp = weeks.enumerated().map { i, list in
            ProgramWeek(week: i + 1, focus: "Woche \(i + 1)", deload: deload.contains(i + 1),
                        sessions: list.enumerated().map { j, x in var x = x; x.slot = j + 1; return x })
        }
        return TrainingProgram(id: id, name: "Plan \(id)", rules: rules, weekPlans: wp)
    }

    /// Wiedereinstieg mit drei leichten Wochen
    static let reentry = program(TrainingProgramEngine.reentryProgramId,
                                 weeks: Array(repeating: [s("grundlage-ut2-20"), s("technik-locker-25"), s("grundlage-locker-30")], count: 3),
                                 rules: ProgramRules(missedSessionPolicy: .skip))

    static func env(_ programs: [TrainingProgram], best2k: Double = 480) -> ProgramEnvironment {
        ProgramEnvironment(catalog: TrainingProgramCatalog(programs: programs + [reentry]), workouts: workouts,
                           calendar: cal, best2k: best2k)
    }

    static func ride(_ dayOffset: Int, _ planId: String?, hour: Int = 10, effort: Int? = nil, pace: Double? = nil,
                     ref: ProgramSessionRef? = nil, completed: Bool = true) -> ProgramRide {
        ProgramRide(start: day(dayOffset, hour: hour), planId: planId, ref: ref, effort: effort, workPace: pace,
                    completed: completed)
    }

    static func dayNumber(_ date: Date?) -> Int? {
        date.map { cal.dateComponents([.day], from: monday, to: cal.startOfDay(for: $0)).day! }
    }
}

final class TrainingProgramCatalogTests: XCTestCase {
    private var resources: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("RowCoach/Resources")
    }

    /// training_plans.json: alle 17 Pläne lesbar, jede planId existiert in plans.json
    func testBundledCatalogLoadsAll17PlansAndEveryPlanIdExists() throws {
        let url = resources.appendingPathComponent("training_plans.json")
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("training_plans.json fehlt") }
        let catalog = try TrainingProgramCatalog.load(url: url)
        XCTAssertEqual(catalog.programs.count, 17)
        let workouts = try WorkoutPlanCatalog.load(url: resources.appendingPathComponent("plans.json"))
        let missing = catalog.missingPlanIds(in: workouts)
        XCTAssertTrue(missing.isEmpty, "fehlende Programme: \(missing)")
        XCTAssertNotNil(catalog.program(id: TrainingProgramEngine.reentryProgramId))
        for p in catalog.programs {
            XCTAssertGreaterThan(p.weeks, 0, p.id)
            XCTAssertFalse(p.name.isEmpty, p.id)
            XCTAssertFalse(p.sources.isEmpty, p.id)
            for w in p.weekPlans {
                XCTAssertTrue(p.sessionsPerWeek.contains(w.required.count), "\(p.id) Woche \(w.week)")
                XCTAssertEqual(w.sessions.map(\.slot), Array(1...w.sessions.count))
            }
        }
        let marathon = try XCTUnwrap(catalog.program(id: "marathon-16-wochen"))
        XCTAssertEqual(marathon.weeks, 16)
        XCTAssertEqual(marathon.rules.missedSessionPolicy, .replaceEasy)
        XCTAssertTrue(marathon.weekPlans.last!.taper)
        XCTAssertTrue(marathon.weekPlans.last!.sessions.contains { $0.event })
        XCTAssertTrue(marathon.planIds.contains("langdistanz-ut2-150"))
        let einstieg = try XCTUnwrap(catalog.program(id: "einstieg-4-wochen"))
        XCTAssertEqual(einstieg.weekPlans[0].sessions[0].planId, "einsteiger-5x1-2x5")
        XCTAssertEqual(einstieg.rules.maxConsecutiveDays, 1)
        XCTAssertEqual(einstieg.rules.repeatWeekIfMissed, 2)
        XCTAssertEqual(catalog.program(id: "masters-50plus-12-wochen")?.rules.hardGapDays, 3)
        XCTAssertEqual(catalog.program(id: "fitness-3x-12-wochen")?.rules.repeatFrom, 5)
    }

    /// Alle 17 Pläne laufen mit den vorgeschlagenen Wunschtagen und jeder Einheit am geplanten Tag bis zum Ende;
    /// harte Einheiten liegen nie näher als der Mindestabstand, nie zwei Einheiten an einem Tag.
    func testAllBundledPlansRunWithPerfectCompliance() throws {
        let url = resources.appendingPathComponent("training_plans.json")
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("training_plans.json fehlt") }
        let catalog = try TrainingProgramCatalog.load(url: url)
        let workouts = try WorkoutPlanCatalog.load(url: resources.appendingPathComponent("plans.json"))
        let env = ProgramEnvironment(catalog: catalog, workouts: workouts, calendar: ProgramFixture.cal, best2k: 480)
        for program in catalog.programs {
            let n = program.weekPlans.map { $0.sessions.count }.max() ?? 3
            let wd = TrainingProgramScheduler.suggestedWeekdays(count: n, maxConsecutiveDays: program.rules.maxConsecutiveDays)
            var st = try TrainingProgramEngine.start(program: program, startDate: ProgramFixture.day(0), weekdays: wd, env: env,
                                                     now: ProgramFixture.day(0, hour: 6))
            var rides: [ProgramRide] = []
            let lastDay = (program.weeks + 2) * 7
            for day in 0..<lastDay {
                let morning = ProgramFixture.day(day, hour: 6)
                TrainingProgramEngine.update(&st, rides: rides, now: morning, env: env)
                if st.isFinished { break }
                if let a = TrainingProgramEngine.agenda(st, now: morning, env: env),
                   let today = a.day(morning, calendar: ProgramFixture.cal), !today.done,
                   let s = st.session(id: today.sessionId) {
                    rides.append(ProgramRide(start: ProgramFixture.day(day, hour: 18), planId: s.planId, ref: s.ref,
                                             effort: s.isHard ? 8 : 3))
                }
                TrainingProgramEngine.update(&st, rides: rides, now: ProgramFixture.day(day, hour: 20), env: env)
            }
            XCTAssertFalse(st.isPaused, program.id)
            if program.rules.repeatFrom == nil {
                XCTAssertTrue(st.isFinished, "\(program.id) nicht fertig: Woche \(st.currentRun?.week ?? 0)")
            }
            let done = st.sessions.filter { $0.status == .done }
            let main = done.filter { $0.programId == program.id && !$0.optional }
            let required = program.weekPlans.reduce(0) { $0 + $1.required.count }
            if program.rules.repeatFrom == nil {
                XCTAssertGreaterThanOrEqual(main.count, required * 9 / 10, "\(program.id): \(main.count) von \(required)")
            }
            let days = done.compactMap { ProgramFixture.dayNumber($0.date) }
            XCTAssertEqual(days.count, Set(days).count, "\(program.id): zwei Einheiten an einem Tag")
            let hard = done.filter(\.isHard).compactMap { ProgramFixture.dayNumber($0.date) }.sorted()
            for (x, y) in zip(hard, hard.dropFirst()) {
                XCTAssertGreaterThanOrEqual(y - x, program.rules.hardGapDays, "\(program.id): harte Einheiten Tag \(x) und \(y)")
            }
        }
    }

    /// Tolerantes Lesen: unbekannte Felder, Zahlen als Text, kaputte Pläne und Einheiten fallen weg
    func testDecodingIsTolerant() throws {
        let json = """
        {"version": 1, "extra": true, "plans": [
          {"id": "a", "name": {"de": "Plan A", "en": "Plan A"}, "category": "Fitness", "sessionsPerWeek": {"min": "2", "max": 3},
           "rules": {"missedSessionPolicy": "replace-easy", "hardSessionsMinGapHours": "72", "unknown": 1},
           "weeks_detail": [{"week": 1, "focus": "x", "sessions": [{"slot": 1, "planId": "p1", "intensity": "hard"},
                                                              {"slot": 2}, {"slot": 3, "planId": "p2", "optional": "true"}]},
                            {"week": 2, "sessions": []}]},
          {"name": "ohne id", "weeks_detail": [{"sessions": [{"planId": "p"}]}]},
          {"id": "leer", "weeks_detail": []},
          {"id": "a", "name": "doppelt", "weeks_detail": [{"sessions": [{"planId": "p"}]}]}
        ]}
        """
        let c = try TrainingProgramCatalog.decode(Data(json.utf8))
        XCTAssertEqual(c.programs.map(\.id), ["a"])
        let a = c.programs[0]
        XCTAssertEqual(a.name, "Plan A")
        XCTAssertEqual(a.category, "fitness")
        XCTAssertEqual(a.weeks, 1)
        XCTAssertEqual(a.sessionsPerWeek, 2...3)
        XCTAssertEqual(a.rules.missedSessionPolicy, .replaceEasy)
        XCTAssertEqual(a.rules.hardGapDays, 3)
        XCTAssertEqual(a.rules.maxConsecutiveDays, 2)
        XCTAssertEqual(a.weekPlans[0].sessions.map(\.planId), ["p1", "p2"])
        XCTAssertEqual(a.weekPlans[0].sessions.map(\.slot), [1, 2])
        XCTAssertTrue(a.weekPlans[0].sessions[1].optional)
        XCTAssertEqual(a.weekPlans[0].sessions[0].intensity, .hard)
    }

    func testFilter() {
        let p1 = ProgramFixture.program("x", weeks: Array(repeating: [ProgramFixture.s("grundlage-locker-30")], count: 4))
        var p2 = ProgramFixture.program("y", weeks: Array(repeating: [ProgramFixture.s("grundlage-locker-30")], count: 12))
        p2.category = "langdistanz"
        p2.levelID = "Leistung"
        XCTAssertEqual(ProgramFilter(weeks: .short).apply([p1, p2]).map(\.id), ["x"])
        XCTAssertEqual(ProgramFilter(category: "langdistanz").apply([p1, p2]).map(\.id), ["y"])
        XCTAssertEqual(ProgramFilter(levelID: "Leistung", weeks: .long).apply([p1, p2]).map(\.id), ["y"])
        XCTAssertEqual(ProgramFilter(text: "plan Y").apply([p1, p2]).map(\.id), ["y"])
        XCTAssertFalse(ProgramFilter().isActive)
    }
}

final class TrainingProgramSchedulerTests: XCTestCase {
    typealias S = TrainingProgramScheduler

    private func items(_ hard: [Bool], event: Set<Int> = []) -> [S.Item] {
        hard.enumerated().map { S.Item(key: $0.offset + 1, hard: $0.element, event: event.contains($0.offset + 1)) }
    }

    func testRequiredInSlotOrderOnEarliestWishDays() {
        // Mo Mi Fr Sa, 3 Pflicht + 1 freiwillig
        let r = S.placeWeek(required: items([false, true, false]), optional: [S.Item(key: 4, hard: false, event: false)],
                            candidates: [0, 2, 4, 5], fixed: [:], rules: ProgramRules())
        XCTAssertEqual(r.days, [1: 0, 2: 2, 3: 4, 4: 5])
        XCTAssertTrue(r.replaced.isEmpty)
    }

    func testHardSessionsNeverOnConsecutiveDaysSwapWithEasy() {
        // Mo Di Mi Do, Woche hart – hart – leicht: hart nie an Folgetagen, höchstens 2 Tage hintereinander
        // → hart Mo, leicht Di, hart Do (Mo–Mi wären 3 Tage am Stück)
        let r = S.placeWeek(required: items([true, true, false]), optional: [], candidates: [0, 1, 2, 3], fixed: [:],
                            rules: ProgramRules())
        XCTAssertEqual(r.days[1], 0)
        XCTAssertEqual(r.days[3], 1)
        XCTAssertEqual(r.days[2], 3)
        // mit 3 Tagen am Stück erlaubt: hart Mo und Mi, leicht dazwischen
        let r3 = S.placeWeek(required: items([true, true, false]), optional: [], candidates: [0, 1, 2, 3], fixed: [:],
                             rules: ProgramRules(maxConsecutiveDays: 3))
        XCTAssertEqual(r3.days, [1: 0, 2: 2, 3: 1])
    }

    func testBeginnerRestDayBetweenSessions() {
        // Einsteiger (höchstens 1 Tag hintereinander), Wunschtage Mo–Fr → Mo, Mi, Fr
        let r = S.placeWeek(required: items([false, false, false]), optional: [], candidates: [0, 1, 2, 3, 4], fixed: [:],
                            rules: ProgramRules(maxConsecutiveDays: 1))
        XCTAssertEqual(Set(r.days.values), [0, 2, 4])
    }

    func testMasters72hAcrossWeekBoundary() {
        // harte Einheit am Sonntag der Vorwoche (Tag −1); 72 h: hart frühestens Mittwoch
        let rules = ProgramRules(hardSessionsMinGapHours: 72)
        let r = S.placeWeek(required: items([true, false, false]), optional: [], candidates: [0, 2, 4],
                            fixed: [-1: true], rules: rules)
        XCTAssertEqual(r.days[1], 2, "hart am Mittwoch")
        XCTAssertEqual(Set([r.days[2]!, r.days[3]!]), [0, 4])
    }

    func testHardReplacedWhenNoValidDay() {
        // zwei harte Einheiten, nur zwei aufeinanderfolgende Tage → eine wird leicht (die spätere)
        let r = S.placeWeek(required: items([true, true]), optional: [], candidates: [5, 6], fixed: [:], rules: ProgramRules())
        XCTAssertEqual(r.replaced, [2])
        XCTAssertEqual(r.days, [1: 5, 2: 6])
    }

    func testFewerDaysThanSessionsDropsEasyFromEndNeverEvent() {
        let r = S.placeWeek(required: items([false, true, false, true], event: [4]), optional: [], candidates: [0, 3],
                            fixed: [:], rules: ProgramRules())
        XCTAssertEqual(r.dropped, [1, 3])
        XCTAssertEqual(Set(r.days.keys), [2, 4])
    }

    func testOptionalOnlyWhenRulesAllow() {
        // Pflicht Mo (hart), Di frei: freiwillige harte Einheit nicht am Dienstag
        let r = S.placeWeek(required: items([true]), optional: [S.Item(key: 2, hard: true, event: false)],
                            candidates: [0, 1], fixed: [:], rules: ProgramRules())
        XCTAssertNil(r.days[2])
    }

    func testSuggestedWeekdaysAndCheck() {
        XCTAssertEqual(S.suggestedWeekdays(count: 3), [.monday, .wednesday, .friday])
        let p = ProgramFixture.program(weeks: [[ProgramFixture.s("a"), ProgramFixture.s("b"), ProgramFixture.s("c")]])
        XCTAssertEqual(S.check(weekdays: [.monday, .friday], program: p), .tooFewDays(needed: 3))
        XCTAssertNil(S.check(weekdays: [.monday, .wednesday, .friday], program: p))
        XCTAssertEqual(Weekday.of(ProgramFixture.day(0), calendar: ProgramFixture.cal), .monday)
        XCTAssertEqual(Weekday.of(ProgramFixture.day(6), calendar: ProgramFixture.cal), .sunday)
    }
}

final class TrainingProgramEngineTests: XCTestCase {
    typealias F = ProgramFixture
    typealias E = TrainingProgramEngine

    private let mwf: [Weekday] = [.monday, .wednesday, .friday]

    private func start(_ p: TrainingProgram, weekdays: [Weekday], startDay: Int = 0, now: Int = 0) throws -> ActiveTrainingProgram {
        try E.start(program: p, startDate: F.day(startDay), weekdays: weekdays, env: F.env([p]), now: F.day(now, hour: 8))
    }

    private func days(_ st: ActiveTrainingProgram, run: Int) -> [Int?] {
        st.sessions(inRun: run).sorted { $0.slot < $1.slot }.map { F.dayNumber($0.date) }
    }

    private func sess(_ st: ActiveTrainingProgram, run: Int, slot: Int) -> ScheduledProgramSession {
        st.sessions.first { $0.run == run && $0.slot == slot }!
    }

    func testStartRejectsTooFewDays() {
        let p = F.program(weeks: [[F.s("grundlage-locker-30"), F.s("schwelle-4x6", .moderate), F.s("grundlage-3x10-r20")]])
        XCTAssertThrowsError(try start(p, weekdays: [.monday, .friday])) { e in
            XCTAssertEqual(e as? ProgramStartProblem, .tooFewDays(needed: 3))
        }
    }

    func testStartPlacesFirstWeekOnWishDays() throws {
        let p = F.program(weeks: [[F.s("grundlage-locker-30"), F.s("kurzintervalle-8x2", .hard), F.s("grundlage-3x10-r20")]])
        let st = try start(p, weekdays: mwf)
        XCTAssertEqual(st.runs.count, 1)
        XCTAssertEqual(days(st, run: 0), [0, 2, 4])
        XCTAssertEqual(E.progress(st, env: F.env([p])).week, 1)
    }

    func testRideCompletesSessionByRefAndByPlanId() throws {
        let p = F.program(weeks: [[F.s("grundlage-locker-30"), F.s("kurzintervalle-8x2", .hard), F.s("grundlage-3x10-r20")],
                                  [F.s("grundlage-locker-30")]])
        var st = try start(p, weekdays: mwf)
        let ref = sess(st, run: 0, slot: 2).ref
        // Montag: Programm passt (ohne Bezug); Dienstag: harte Einheit mit Bezug (einen Tag früher)
        E.update(&st, rides: [F.ride(0, "grundlage-locker-30"), F.ride(1, "kurzintervalle-8x2", ref: ref)],
                 now: F.day(1, hour: 20), env: F.env([p]))
        XCTAssertEqual(sess(st, run: 0, slot: 1).status, .done)
        XCTAssertEqual(sess(st, run: 0, slot: 2).status, .done)
        XCTAssertEqual(F.dayNumber(sess(st, run: 0, slot: 2).date), 1)
        XCTAssertEqual(sess(st, run: 0, slot: 3).status, .planned)
        // abgebrochene kurze Fahrt zählt nicht
        E.update(&st, rides: [F.ride(0, "grundlage-locker-30"), F.ride(1, "kurzintervalle-8x2", ref: ref),
                              ProgramRide(start: F.day(4), planId: "grundlage-3x10-r20", activeDuration: 300, completed: false)],
                 now: F.day(4, hour: 20), env: F.env([p]))
        XCTAssertEqual(sess(st, run: 0, slot: 3).status, .planned)
        XCTAssertEqual(E.launchRef(st, planId: "grundlage-3x10-r20", now: F.day(4), calendar: F.cal),
                       sess(st, run: 0, slot: 3).ref)
    }

    func testWeekRolloverAndCrossWeekHardGap() throws {
        // Woche 1 endet mit hart am Sonntag, Woche 2 beginnt mit hart: nicht am Montag
        let p = F.program(weeks: [[F.s("grundlage-locker-30"), F.s("grundlage-3x10-r20"), F.s("kurzintervalle-8x2", .hard)],
                                  [F.s("langintervalle-4x4", .hard), F.s("grundlage-locker-30"), F.s("grundlage-3x10-r20")]])
        let wd: [Weekday] = [.monday, .wednesday, .sunday]
        var st = try start(p, weekdays: wd)
        XCTAssertEqual(days(st, run: 0), [0, 2, 6])
        let rides = [F.ride(0, "grundlage-locker-30"), F.ride(2, "grundlage-3x10-r20"), F.ride(6, "kurzintervalle-8x2")]
        E.update(&st, rides: rides, now: F.day(7, hour: 8), env: F.env([p]))
        XCTAssertEqual(st.runs.count, 2)
        XCTAssertEqual(st.runs[1].week, 2)
        XCTAssertTrue(st.runs[0].closed)
        let hard = sess(st, run: 1, slot: 1)
        XCTAssertEqual(F.dayNumber(hard.date), 9, "hart am Mittwoch, nicht am Montag nach dem harten Sonntag")
        XCTAssertEqual(F.dayNumber(sess(st, run: 1, slot: 2).date), 7)
    }

    func testMissedSessionMovesWithinWeek() throws {
        let p = F.program(weeks: [[F.s("grundlage-locker-30"), F.s("schwelle-4x6", .moderate), F.s("grundlage-3x10-r20")]])
        var st = try start(p, weekdays: [.monday, .wednesday, .friday, .saturday])
        E.update(&st, rides: [], now: F.day(1, hour: 9), env: F.env([p]))
        let s1 = sess(st, run: 0, slot: 1)
        XCTAssertEqual(s1.status, .planned)
        XCTAssertEqual(F.dayNumber(s1.date), 5, "auf den freien Samstag")
        XCTAssertEqual(F.dayNumber(s1.originalDate), 0)
        XCTAssertEqual(s1.display(today: F.day(1)), .moved)
        // nie zwei Einheiten an einem Tag
        let dates = st.sessions.compactMap { F.dayNumber($0.date) }
        XCTAssertEqual(dates.count, Set(dates).count)
    }

    func testNeverTwoHardRescheduledReplaceEasyInstead() throws {
        let rules = ProgramRules(missedSessionPolicy: .replaceEasy)
        let p = F.program(weeks: [[F.s("kurzintervalle-8x2", .hard), F.s("grundlage-locker-30"), F.s("langintervalle-4x4", .hard)]],
                          rules: rules)
        var st = try start(p, weekdays: [.monday, .wednesday, .friday, .saturday, .sunday])
        XCTAssertEqual(days(st, run: 0), [0, 2, 4])
        let env = F.env([p])
        // Montag verpasst → harte Einheit auf Sonntag (Samstag wäre zu nah an Freitag)
        E.update(&st, rides: [], now: F.day(1, hour: 9), env: env)
        XCTAssertEqual(F.dayNumber(sess(st, run: 0, slot: 1).date), 6)
        XCTAssertEqual(st.runs[0].rescheduledHard, 1)
        // Mittwoch erledigt, Freitag verpasst → zweite harte nicht nachholen, sondern leicht am Samstag
        E.update(&st, rides: [F.ride(2, "grundlage-locker-30")], now: F.day(5, hour: 9), env: env)
        let s3 = sess(st, run: 0, slot: 3)
        XCTAssertEqual(s3.status, .planned)
        XCTAssertEqual(s3.intensity, .easy)
        XCTAssertNotEqual(s3.planId, "langintervalle-4x4")
        XCTAssertTrue(s3.isReplaced)
        XCTAssertEqual(F.dayNumber(s3.date), 5)
    }

    func testSkipPolicyDropsMissedSession() throws {
        let p = F.program(weeks: [[F.s("grundlage-locker-30"), F.s("kurzintervalle-8x2", .hard), F.s("grundlage-3x10-r20")]],
                          rules: ProgramRules(hardSessionsMinGapHours: 72, missedSessionPolicy: .skip))
        var st = try start(p, weekdays: mwf)
        E.update(&st, rides: [F.ride(0, "grundlage-locker-30")], now: F.day(3, hour: 9), env: F.env([p]))
        // Mittwoch (hart) verpasst, kein freier Wunschtag in der Woche → fällt weg
        XCTAssertEqual(sess(st, run: 0, slot: 2).status, .skipped)
        XCTAssertEqual(sess(st, run: 0, slot: 2).skipReason, .missed)
        XCTAssertEqual(sess(st, run: 0, slot: 2).display(today: F.day(3)), .missed)
    }

    func testShiftPolicyMovesToNextDayAndExtendsWeek() throws {
        let p = F.program(weeks: [[F.s("grundlage-locker-30"), F.s("grundlage-3x10-r20")], [F.s("grundlage-locker-30"), F.s("grundlage-ut2-20")]],
                          rules: ProgramRules(missedSessionPolicy: .shift))
        var st = try start(p, weekdays: [.monday, .sunday])
        XCTAssertEqual(days(st, run: 0), [0, 6])
        // Sonntag verpasst → Montag (Woche wird 1 Tag länger)
        E.update(&st, rides: [F.ride(0, "grundlage-locker-30")], now: F.day(7, hour: 8), env: F.env([p]))
        XCTAssertEqual(F.dayNumber(sess(st, run: 0, slot: 2).date), 7)
        XCTAssertEqual(st.runs.count, 1)
        XCTAssertEqual(st.runs[0].extendedDays, 1)
        // erledigt am Montag → Woche 2 beginnt am Dienstag
        E.update(&st, rides: [F.ride(0, "grundlage-locker-30"), F.ride(7, "grundlage-3x10-r20")], now: F.day(8, hour: 8),
                 env: F.env([p]))
        XCTAssertEqual(st.runs.count, 2)
        XCTAssertEqual(F.dayNumber(st.runs[1].start), 8)
    }

    func testBeginnerWeekRepeatedAfterTwoMissed() throws {
        let p = F.program(weeks: [[F.s("grundlage-ut2-20"), F.s("technik-locker-25"), F.s("grundlage-locker-30")],
                                  [F.s("grundlage-locker-30"), F.s("grundlage-3x10-r20"), F.s("grundlage-locker-30")]],
                          rules: ProgramRules(maxConsecutiveDays: 1, missedSessionPolicy: .shift, repeatWeekIfMissed: 2))
        var st = try start(p, weekdays: mwf)
        E.update(&st, rides: [F.ride(0, "grundlage-ut2-20")], now: F.day(9, hour: 8), env: F.env([p]))
        XCTAssertGreaterThanOrEqual(st.runs.count, 2)
        XCTAssertEqual(st.runs[1].week, 1)
        XCTAssertTrue(st.runs[1].repeated)
        XCTAssertTrue(st.notices.contains { $0.kind == .weekRepeated && $0.week == 1 })
    }

    func testEventMovedNeverDropped() throws {
        let p = F.program(weeks: [[F.s("grundlage-locker-30"), F.s("grundlage-3x10-r20"), F.s("test-2000m", .max, event: true)]],
                          rules: ProgramRules(missedSessionPolicy: .skip))
        var st = try start(p, weekdays: mwf)
        let env = F.env([p])
        E.update(&st, rides: [F.ride(0, "grundlage-locker-30"), F.ride(2, "grundlage-3x10-r20")], now: F.day(5, hour: 9), env: env)
        let ev = sess(st, run: 0, slot: 3)
        XCTAssertEqual(ev.status, .planned)
        XCTAssertEqual(F.dayNumber(ev.date), 5, "Test auf Samstag verschoben")
        // auch nach dem Wochenende nicht gestrichen: Woche verlängert
        E.update(&st, rides: [F.ride(0, "grundlage-locker-30"), F.ride(2, "grundlage-3x10-r20")], now: F.day(7, hour: 9), env: env)
        let ev2 = sess(st, run: 0, slot: 3)
        XCTAssertEqual(ev2.status, .planned)
        XCTAssertEqual(F.dayNumber(ev2.date), 7)
        XCTAssertEqual(F.dayNumber(st.runs[0].end), 8)
        XCTAssertNil(st.finishedAt)
        // erledigt → Plan zu Ende
        E.update(&st, rides: [F.ride(0, "grundlage-locker-30"), F.ride(2, "grundlage-3x10-r20"), F.ride(7, "test-2000m", pace: 118)],
                 now: F.day(8, hour: 9), env: env)
        XCTAssertNotNil(st.finishedAt)
        XCTAssertTrue(st.notices.contains { $0.kind == .finished })
    }

    func testOpenPlanRepeatsFromWeek() throws {
        let p = F.program(weeks: [[F.s("grundlage-locker-30")], [F.s("grundlage-3x10-r20")]],
                          rules: ProgramRules(repeatFrom: 2))
        var st = try start(p, weekdays: [.monday])
        let rides = [F.ride(0, "grundlage-locker-30"), F.ride(7, "grundlage-3x10-r20"), F.ride(14, "grundlage-3x10-r20")]
        E.update(&st, rides: rides, now: F.day(15), env: F.env([p]))
        XCTAssertEqual(st.runs.map(\.week), [1, 2, 2])
        XCTAssertEqual(st.runs.last?.cycle, 1)
        XCTAssertNil(st.finishedAt)
    }

    // MARK: Pause und Wiedereinstieg

    private var threeWeekPlan: TrainingProgram {
        F.program(weeks: [[F.s("grundlage-locker-30"), F.s("kurzintervalle-8x2", .hard), F.s("grundlage-3x10-r20")],
                          [F.s("kurzintervalle-8x2", .hard), F.s("grundlage-locker-30"), F.s("grundlage-3x10-r20")],
                          [F.s("langintervalle-4x4", .hard), F.s("grundlage-locker-30"), F.s("grundlage-3x10-r20")],
                          [F.s("grundlage-locker-30"), F.s("grundlage-ut2-20"), F.s("grundlage-3x10-r20")]],
                  rules: ProgramRules(missedSessionPolicy: .replaceEasy), deload: [4])
    }

    /// Wochen 1 und 2 vollständig, Plan steht in Woche 3
    private func inWeek3() throws -> (ActiveTrainingProgram, [ProgramRide]) {
        let p = threeWeekPlan
        var st = try start(p, weekdays: mwf)
        let rides = [F.ride(0, "grundlage-locker-30"), F.ride(2, "kurzintervalle-8x2"), F.ride(4, "grundlage-3x10-r20"),
                     F.ride(7, "kurzintervalle-8x2"), F.ride(9, "grundlage-locker-30"), F.ride(11, "grundlage-3x10-r20")]
        E.update(&st, rides: rides, now: F.day(14, hour: 8), env: F.env([p]))
        XCTAssertEqual(st.runs.last?.week, 3)
        return (st, rides)
    }

    func testShortPauseContinuesSameWeekWithEasyFirst() throws {
        var (st, rides) = try inWeek3()
        let env = F.env([threeWeekPlan])
        E.update(&st, rides: rides + [F.ride(14, "langintervalle-4x4")], now: F.day(14, hour: 20), env: env)
        E.pause(&st, now: F.day(15), calendar: F.cal)
        XCTAssertTrue(st.isPaused)
        // während der Pause gilt nichts als verpasst
        E.update(&st, rides: rides, now: F.day(18), env: env)
        XCTAssertEqual(st.runs.count, 3)
        E.resume(&st, now: F.day(19, hour: 8), env: env)
        XCTAssertFalse(st.isPaused)
        let run = try XCTUnwrap(st.runs.last)
        XCTAssertEqual(run.week, 3)
        XCTAssertEqual(F.dayNumber(run.start), 19)
        // die schon erledigte harte Einheit kommt nicht noch einmal
        XCTAssertEqual(sess(st, run: run.run, slot: 1).skipReason, .alreadyDone)
        XCTAssertEqual(st.paceAdjustment, 0)
        XCTAssertTrue(st.notices.contains { $0.kind == .resumed && $0.value == 4 })
    }

    /// Pause von Sekunden (gleicher Tag): weiter wie geplant – kein „Willkommen zurück“, keine Wiederholung,
    /// harte Einheit bleibt
    func testPauseOfSecondsChangesNothingVisible() throws {
        var (st, rides) = try inWeek3()
        let env = F.env([threeWeekPlan])
        E.pause(&st, now: F.day(14, hour: 8), calendar: F.cal)
        E.resume(&st, now: F.day(14, hour: 8), env: env)
        E.update(&st, rides: rides, now: F.day(14, hour: 9), env: env)
        let run = try XCTUnwrap(st.runs.last)
        XCTAssertEqual(run.week, 3)
        XCTAssertFalse(run.repeated)
        XCTAssertFalse(st.notices.contains { $0.kind == .resumed })
        XCTAssertEqual(sess(st, run: run.run, slot: 1).intensity, .hard)
    }

    /// Bis 7 Tage Pause: kein Wiederholungs-Chip, aber „Willkommen zurück“ (Pause ≥ 1 Tag)
    func testShortPauseIsNotARepeat() throws {
        var (st, rides) = try inWeek3()
        let env = F.env([threeWeekPlan])
        E.pause(&st, now: F.day(14), calendar: F.cal)
        E.update(&st, rides: rides, now: F.day(17), env: env)
        E.resume(&st, now: F.day(17, hour: 8), env: env)
        XCTAssertFalse(try XCTUnwrap(st.runs.last).repeated)
        XCTAssertTrue(st.notices.contains { $0.kind == .resumed && $0.value == 3 })
    }

    /// Simulatorfahrten zählen für den Plan nur mit `includeSimulated`
    func testSimulatorRideCountsOnlyWhenIncluded() {
        let s = TrainingSession(start: F.day(0), planId: "grundlage-locker-30", distance: 7000, activeDuration: 1800,
                                origin: .simulator)
        XCTAssertNil(ProgramRide(session: s))
        XCTAssertNotNil(ProgramRide(session: s, includeSimulated: true))
    }

    func testShortPauseReplacesFirstHardSession() throws {
        var (st, rides) = try inWeek3()
        let env = F.env([threeWeekPlan])
        E.pause(&st, now: F.day(14), calendar: F.cal)
        E.update(&st, rides: rides, now: F.day(17), env: env)
        E.resume(&st, now: F.day(17, hour: 8), env: env)
        let run = try XCTUnwrap(st.runs.last)
        let first = sess(st, run: run.run, slot: 1)
        XCTAssertEqual(first.originalPlanId, "langintervalle-4x4")
        XCTAssertEqual(first.intensity, .easy, "erste harte Einheit nach der Pause leicht")
    }

    func testPauseTenDaysRepeatsLastWeekAndSlowsPace() throws {
        var (st, rides) = try inWeek3()
        let env = F.env([threeWeekPlan])
        E.pause(&st, now: F.day(14), calendar: F.cal)
        E.update(&st, rides: rides, now: F.day(24), env: env)
        E.resume(&st, now: F.day(24, hour: 8), env: env)
        XCTAssertEqual(st.runs.last?.week, 2)
        XCTAssertEqual(st.paceAdjustment, 1)
        XCTAssertEqual(st.effectiveBest2k(480), 484)
    }

    func testPauseThreeWeeksUsesReentryThenReturns() throws {
        var (st, rides) = try inWeek3()
        let env = F.env([threeWeekPlan])
        E.pause(&st, now: F.day(14), calendar: F.cal)
        E.resume(&st, now: F.day(32, hour: 8), env: env)   // 18 Tage
        let run = try XCTUnwrap(st.runs.last)
        XCTAssertEqual(run.programId, TrainingProgramEngine.reentryProgramId)
        XCTAssertEqual(run.week, 2, "15–20 Tage: Wiedereinstieg ab Woche 2")
        XCTAssertEqual(st.bridge?.resumeWeek, 2)
        XCTAssertTrue(st.inBridge)
        XCTAssertEqual(st.mainWeek, 2)
        XCTAssertEqual(st.paceAdjustment, 2)
        // zwei Wiedereinstiegswochen gefahren → zurück in Woche 2 des Plans
        var all = rides
        for (offset, planId) in [(32, "grundlage-ut2-20"), (34, "technik-locker-25"), (36, "grundlage-locker-30"),
                                 (39, "grundlage-ut2-20"), (41, "technik-locker-25"), (43, "grundlage-locker-30")] {
            all.append(F.ride(offset, planId))
        }
        E.update(&st, rides: all, now: F.day(46, hour: 8), env: env)
        XCTAssertEqual(st.runs.last?.programId, "testplan")
        XCTAssertEqual(st.runs.last?.week, 2)
        XCTAssertNil(st.bridge)
    }

    func testPauseSixWeeksFullReentryFromBlockStart() throws {
        var (st, rides) = try inWeek3()
        let env = F.env([threeWeekPlan])
        E.pause(&st, now: F.day(14), calendar: F.cal)
        _ = rides
        E.resume(&st, now: F.day(54, hour: 8), env: env)   // 40 Tage
        XCTAssertEqual(st.runs.last?.programId, TrainingProgramEngine.reentryProgramId)
        XCTAssertEqual(st.runs.last?.week, 1)
        XCTAssertEqual(st.bridge?.resumeWeek, 1, "kein Deload davor → Blockbeginn Woche 1")
        XCTAssertTrue(st.notices.contains { $0.kind == .retestSuggested })
    }

    func testVeryLongPauseRestartsPlan() throws {
        var (st, _) = try inWeek3()
        let env = F.env([threeWeekPlan])
        E.pause(&st, now: F.day(14), calendar: F.cal)
        E.resume(&st, now: F.day(90, hour: 8), env: env)
        XCTAssertEqual(st.runs.last?.week, 1)
        XCTAssertEqual(st.runs.last?.programId, "testplan")
        XCTAssertTrue(st.notices.contains { $0.kind == .restarted })
    }

    func testAutoPauseAfterTenDaysWithoutRide() throws {
        let p = threeWeekPlan
        var st = try start(p, weekdays: mwf)
        E.update(&st, rides: [F.ride(0, "grundlage-locker-30")], now: F.day(9), env: F.env([p]))
        XCTAssertFalse(st.isPaused)
        E.update(&st, rides: [F.ride(0, "grundlage-locker-30")], now: F.day(10), env: F.env([p]))
        XCTAssertTrue(st.isPaused)
        XCTAssertTrue(st.autoPaused)
        XCTAssertEqual(F.dayNumber(st.pausedAt), 1)
        XCTAssertTrue(st.notices.contains { $0.kind == .autoPaused })
    }

    // MARK: Effort und Tests

    func testThreeEasySessionsFeltHardMakeNextWeekLighter() throws {
        let p = threeWeekPlan
        var st = try start(p, weekdays: [.monday, .wednesday, .friday, .saturday])
        let env = F.env([p])
        let rides = [F.ride(0, "grundlage-locker-30", effort: 8), F.ride(2, "kurzintervalle-8x2", effort: 8),
                     F.ride(4, "grundlage-3x10-r20", effort: 7)]
        E.update(&st, rides: rides, now: F.day(4, hour: 20), env: env)
        XCTAssertFalse(st.forceDeloadNext, "nur zwei leichte Einheiten")
        let more = rides + [F.ride(5, nil)]
        E.update(&st, rides: more, now: F.day(6), env: env)
        // in Woche 2: erste leichte Einheit wieder RPE 8 → drei leichte in Folge
        E.update(&st, rides: more + [F.ride(9, "grundlage-locker-30", effort: 8)], now: F.day(9, hour: 20), env: env)
        XCTAssertTrue(st.forceDeloadNext)
        XCTAssertTrue(st.notices.contains { $0.kind == .recoveryCheck })
        E.update(&st, rides: more + [F.ride(9, "grundlage-locker-30", effort: 8)], now: F.day(14, hour: 8), env: env)
        let run = try XCTUnwrap(st.runs.last)
        XCTAssertEqual(run.week, 3)
        XCTAssertTrue(run.deload)
        XCTAssertFalse(st.sessions(inRun: run.run).contains { $0.isHard }, "leichtere Woche ohne harte Einheit")
    }

    func testTwoMaxedHardSessionsWithMissedPaceLowerTargets() throws {
        let p = F.program(weeks: Array(repeating: [F.s("kurzintervalle-8x2", .hard), F.s("grundlage-locker-30"),
                                                   F.s("langintervalle-4x4", .hard)], count: 2))
        var st = try start(p, weekdays: mwf)
        // Ziel 120+2…120+6 = 2:02–2:06; gefahren 2:10 mit RPE 10
        let rides = [F.ride(0, "kurzintervalle-8x2", effort: 10, pace: 130), F.ride(2, "grundlage-locker-30", effort: 3),
                     F.ride(4, "langintervalle-4x4", effort: 10, pace: 131)]
        E.update(&st, rides: rides, now: F.day(4, hour: 20), env: F.env([p]))
        XCTAssertEqual(st.paceAdjustment, 2)
        XCTAssertTrue(st.notices.contains { $0.kind == .paceLowered && $0.value == 2 })
        // greift nicht zweimal für dieselben Einheiten
        E.update(&st, rides: rides, now: F.day(5), env: F.env([p]))
        XCTAssertEqual(st.paceAdjustment, 2)
    }

    func testHardSessionsFeelingEasySuggestRetest() throws {
        let p = F.program(weeks: Array(repeating: [F.s("kurzintervalle-8x2", .hard), F.s("grundlage-locker-30"),
                                                   F.s("langintervalle-4x4", .hard)], count: 2))
        var st = try start(p, weekdays: mwf)
        let rides = [F.ride(0, "kurzintervalle-8x2", effort: 5, pace: 123), F.ride(2, "grundlage-locker-30", effort: 3),
                     F.ride(4, "langintervalle-4x4", effort: 6, pace: 124),
                     F.ride(7, "kurzintervalle-8x2", effort: 6, pace: 122)]
        E.update(&st, rides: rides, now: F.day(7, hour: 20), env: F.env([p]))
        XCTAssertTrue(st.notices.contains { $0.kind == .retestSuggested })
    }

    func testFasterTestUpdatesReferenceSlowerAsks() throws {
        let p = F.program(weeks: [[F.s("grundlage-locker-30"), F.s("test-2000m", .max, event: true)]])
        var st = try start(p, weekdays: [.monday, .wednesday])
        // 2000 m in 1:55/500 m → 7:40 = 460 s, schneller als 480
        E.update(&st, rides: [F.ride(0, "grundlage-locker-30"), F.ride(2, "test-2000m", pace: 115)], now: F.day(2, hour: 20),
                 env: F.env([p]))
        XCTAssertEqual(st.reference?.best2k, 460)
        XCTAssertEqual(st.reference?.isWorse, false)
        XCTAssertTrue(st.notices.contains { $0.kind == .referenceImproved })
        E.resolveReference(&st)
        XCTAssertNil(st.reference)

        var st2 = try start(p, weekdays: [.monday, .wednesday])
        E.update(&st2, rides: [F.ride(0, "grundlage-locker-30"), F.ride(2, "test-2000m", pace: 125)], now: F.day(2, hour: 20),
                 env: F.env([p]))
        XCTAssertEqual(st2.reference?.best2k, 500)
        XCTAssertEqual(st2.reference?.isWorse, true, "schlechter: nur nach Rückfrage")
    }

    func testPowerLawEstimate() {
        let w = ProgramFixture.workouts.first { $0.id == "test-1000m" }
        // 1000 m in 1:50/500 m (220 s, 263,0 W) → Schwelle 191,9 W → gleichwertige 2k 7:36,3
        // (bis 27.11.2026 Paul's Law: 2000-m-Tempo 1:55 → 7:40,0; docs/schwelle/SPEC.md 8.1)
        XCTAssertEqual(E.estimateBest2k(ride: ProgramRide(start: F.day(0), workPace: 110), plan: w, b: 0.15)!, 456.3,
                       accuracy: 0.05)
    }

    func testSwapToEasyAndRestore() throws {
        let p = threeWeekPlan
        var st = try start(p, weekdays: mwf)
        let id = sess(st, run: 0, slot: 2).id
        XCTAssertTrue(E.swapToEasy(&st, sessionId: id, env: F.env([p])))
        XCTAssertEqual(st.session(id: id)?.intensity, .easy)
        XCTAssertTrue(st.session(id: id)!.isReplaced)
        E.restoreOriginal(&st, sessionId: id)
        XCTAssertEqual(st.session(id: id)?.planId, "kurzintervalle-8x2")
    }

    func testCodableRoundTrip() throws {
        var (st, _) = try inWeek3()
        st.notices.append(ProgramNotice(kind: .paceLowered, date: F.day(3), value: 2))
        let data = try JSONEncoder().encode(st)
        let back = try JSONDecoder().decode(ActiveTrainingProgram.self, from: data)
        XCTAssertEqual(back, st)
    }

    func testWorkoutHeaderKeepsProgramRef() throws {
        var h = WorkoutHeader(startDate: F.day(0), endDate: F.day(0, hour: 11), device: WorkoutDevice(source: .pm5))
        h.trainingProgram = ProgramSessionRef(programId: "p", run: 2, week: 3, slot: 1)
        let back = try JSONDecoder().decode(WorkoutHeader.self, from: JSONEncoder().encode(h))
        XCTAssertEqual(back.trainingProgram, h.trainingProgram)
    }
}

final class DailySuggestionProgramTests: XCTestCase {
    typealias F = ProgramFixture
    typealias E = TrainingProgramEngine

    private let p = ProgramFixture.program(weeks: [
        [ProgramFixture.s("grundlage-locker-30"), ProgramFixture.s("kurzintervalle-8x2", .hard), ProgramFixture.s("grundlage-3x10-r20"),
         ProgramFixture.s("technik-locker-25", optional: true)],
        [ProgramFixture.s("grundlage-locker-30"), ProgramFixture.s("schwelle-4x6", .moderate), ProgramFixture.s("grundlage-3x10-r20")],
    ])

    private func setup(now: Date, rides: [ProgramRide] = []) throws -> ProgramAgenda {
        var st = try E.start(program: p, startDate: F.day(0), weekdays: [.monday, .wednesday, .friday], env: F.env([p]),
                             now: F.day(0, hour: 8))
        E.update(&st, rides: rides, now: now, env: F.env([p]))
        return try XCTUnwrap(E.agenda(st, now: now, env: F.env([p])))
    }

    private func suggest(_ sessions: [TrainingSession], now: Date, agenda: ProgramAgenda?) -> DailySuggestion {
        DailySuggestion.make(sessions: sessions, plans: F.workouts, courseIds: StatsFixture.courseIds, now: now,
                             calendar: F.cal, best2k: 480, program: agenda)
    }

    private func ts(_ day: Int, _ planId: String?, hour: Int = 10) -> TrainingSession {
        TrainingSession(start: F.day(day, hour: hour), courseId: "rhein-basel", planId: planId,
                        planLevel: planId.flatMap { id in F.workouts.first { $0.id == id } }.map(IntensityRules.level(plan:)),
                        distance: 7000, activeDuration: 1800, averagePace: planId == nil ? 155 : 140, completedCourse: true)
    }

    func testPlanDayShowsPlannedSessionEvenForNewUser() throws {
        let a = try setup(now: F.day(0, hour: 9))
        let s = suggest([], now: F.day(0, hour: 9), agenda: a)
        XCTAssertEqual(s.rule, .plan, "Regel 0 (wenige Fahrten) ruht mit Plan")
        XCTAssertEqual(s.planId, "grundlage-locker-30")
        XCTAssertTrue(s.reason.contains("Woche 1 von 2"))
        XCTAssertTrue(s.reason.contains("Einheit 1 von 3"))
        XCTAssertEqual(s.program?.index, 1)
        XCTAssertEqual(s.program?.isRestDay, false)
        XCTAssertEqual(s.alternatives.count, 2)
    }

    func testRestDayOffersOptionalAndFree() throws {
        let rides = [F.ride(0, "grundlage-locker-30")]
        let a = try setup(now: F.day(1, hour: 9), rides: rides)
        let s = suggest([ts(0, "grundlage-locker-30")], now: F.day(1, hour: 9), agenda: a)
        XCTAssertEqual(s.rule, .planRest)
        XCTAssertEqual(s.program?.isRestDay, true)
        XCTAssertTrue(s.reason.contains("Ruhetag"))
        XCTAssertTrue(s.alternatives.contains { if case .free = $0 { return true } else { return false } })
    }

    func testRecoveryBeatsHardPlanSession() throws {
        // Mittwoch hart geplant, gestern (Dienstag) frei hart gerudert
        let rides = [F.ride(0, "grundlage-locker-30"), F.ride(1, "langintervalle-4x4")]
        let a = try setup(now: F.day(2, hour: 9), rides: rides)
        let s = suggest([ts(0, "grundlage-locker-30"), ts(1, "langintervalle-4x4", hour: 18)], now: F.day(2, hour: 9), agenda: a)
        XCTAssertEqual(s.rule, .recovery)
        XCTAssertEqual(s.planId, "technik-locker-25")
        XCTAssertEqual(s.program?.plannedPlanId, "kurzintervalle-8x2")
    }

    func testRulesTwoToFiveRestWithPlan() throws {
        // zwei harte Einheiten in 7 Tagen (Regel 2), aber leichte Planeinheit am Freitag → Plan
        let rides = [F.ride(0, "grundlage-locker-30"), F.ride(2, "kurzintervalle-8x2")]
        let a = try setup(now: F.day(4, hour: 11), rides: rides)
        let hist = [ts(-1, "kurzintervalle-8x2"), ts(0, "grundlage-locker-30"), ts(2, "kurzintervalle-8x2")]
        let s = suggest(hist, now: F.day(4, hour: 11), agenda: a)
        XCTAssertEqual(s.rule, .plan)
        XCTAssertEqual(s.planId, "grundlage-3x10-r20")
        // ohne Plan griffe Regel 2
        XCTAssertEqual(suggest(hist, now: F.day(4, hour: 11), agenda: nil).rule, .enoughHard)
    }

    func testDoneTodaySuggestsTomorrowsPlanDay() throws {
        // Dienstag schon gerudert → Vorschlag für Mittwoch (Plantag)
        let rides = [F.ride(0, "grundlage-locker-30")]
        let a = try setup(now: F.day(1, hour: 20), rides: rides)
        let s = suggest([ts(0, "grundlage-locker-30"), ts(1, nil, hour: 9)], now: F.day(1, hour: 20), agenda: a)
        XCTAssertTrue(s.doneToday)
        XCTAssertEqual(s.rule, .plan)
        XCTAssertEqual(s.planId, "kurzintervalle-8x2")
    }

    func testNextWeekPreviewInAgenda() throws {
        let rides = [F.ride(0, "grundlage-locker-30"), F.ride(2, "kurzintervalle-8x2"), F.ride(4, "grundlage-3x10-r20")]
        let a = try setup(now: F.day(6, hour: 20), rides: rides)
        // Sonntag schon gerudert → Montag der nächsten Woche aus der Vorschau
        let hist = [ts(0, "grundlage-locker-30"), ts(2, "kurzintervalle-8x2"), ts(4, "grundlage-3x10-r20"), ts(6, nil, hour: 9)]
        let s = suggest(hist, now: F.day(6, hour: 20), agenda: a)
        XCTAssertEqual(s.rule, .plan)
        XCTAssertTrue(s.reason.contains("Woche 2 von 2"))
    }

    func testPausedPlanFallsBackToNormalRules() throws {
        var st = try E.start(program: p, startDate: F.day(0), weekdays: [.monday, .wednesday, .friday], env: F.env([p]),
                             now: F.day(0, hour: 8))
        E.pause(&st, now: F.day(0), calendar: F.cal)
        let a = E.agenda(st, now: F.day(1), env: F.env([p]))
        XCTAssertEqual(a?.paused, true)
        let s = suggest([], now: F.day(1), agenda: a)
        XCTAssertEqual(s.rule, .start)
        XCTAssertNil(s.program)
    }
}
