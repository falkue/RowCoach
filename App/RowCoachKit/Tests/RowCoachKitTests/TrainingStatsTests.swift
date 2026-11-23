import XCTest
@testable import RowCoachKit

/// Gemeinsame Bausteine für die Tests von TrainingStats und DailySuggestion: fester Kalender (Zürich),
/// „jetzt“ = Dienstag, 24.11.2026, 18:05 (KW 48), und ein kleiner Programmkatalog wie plans.json.
enum StatsFixture {
    static let cal = TrainingCalendar.swiss(timeZone: TimeZone(identifier: "Europe/Zurich")!)

    static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 11, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    static let now = date(2026, 11, 24, 18, 5)

    /// Zeitpunkt `days` Tage vor jetzt um `hour` Uhr
    static func ago(_ days: Int, hour: Int = 11) -> Date {
        let d = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: now))!
        return cal.date(bySettingHour: hour, minute: 0, second: 0, of: d)!
    }

    private static func plan(_ id: String, _ category: String, workZone: Int) -> WorkoutPlan {
        WorkoutPlan(id: id, name: id, category: category,
                    phases: [WorkoutPhase(kind: .warmup, durationS: 300, hrZone: 2),
                             WorkoutPhase(kind: .work, durationS: 600, spmMin: 20, spmMax: 24, hrZone: workZone,
                                          paceOffsetMinS: 2, paceOffsetMaxS: 6),
                             WorkoutPhase(kind: .cooldown, durationS: 300, hrZone: 1)])
    }

    static let plans: [WorkoutPlan] = [
        plan("grundlage-locker-30", "Grundlage", workZone: 2),
        plan("grundlage-3x10-r20", "Grundlage", workZone: 2),
        plan("schwelle-4x6", "Schwelle", workZone: 4),
        plan("kurzintervalle-8x2", "Intervalle", workZone: 5),
        plan("langintervalle-4x4", "Intervalle", workZone: 4),
        plan("pyramide-1-2-3-4-3-2-1", "Intervalle", workZone: 4),
        plan("frequenzleiter-18-24", "Technik & Rhythmus", workZone: 3),
        plan("sprint-8x250", "Sprint", workZone: 5),
        plan("test-2000m", "Test", workZone: 5),
        plan("technik-locker-25", "Technik & Rhythmus", workZone: 2),
    ]

    static let courseIds = ["luzern-nationalquai", "rhein-basel", "rhein-stein", "zuerichsee-mythenquai",
                            "zuerichsee-utoquai"]

    static func level(_ planId: String) -> IntensityLevel? {
        plans.first { $0.id == planId }.map(IntensityRules.level(plan:))
    }

    /// Eine Fahrt; `zones` = Minuten in Zone 0…5 (nil = ohne Puls)
    static func session(_ start: Date, plan: String? = nil, course: String? = "zuerichsee-utoquai",
                        minutes: Double = 30, distance: Double = 7000, pace: Double = 140,
                        zones: [Double]? = nil, full: Bool = false, interrupted: Bool = false,
                        effort: Int? = nil, origin: TrainingSession.Origin = .pm5) -> TrainingSession {
        TrainingSession(start: start, courseId: course, courseTitle: course, courseLength: 4000, planId: plan,
                        planName: plan, planLevel: plan.flatMap(level), distance: distance,
                        activeDuration: minutes * 60, averagePace: pace, zoneSeconds: zones?.map { $0 * 60 },
                        completedCourse: full, interrupted: interrupted, effortScore: effort, origin: origin)
    }

    /// 30 min leicht mit Puls (Zone 2)
    static func easy(_ start: Date, course: String? = "zuerichsee-utoquai", plan: String? = nil) -> TrainingSession {
        session(start, plan: plan, course: course, zones: [0, 2, 28, 0, 0, 0])
    }

    /// harte Fahrt mit Programm
    static func hard(_ start: Date, plan: String = "kurzintervalle-8x2", course: String? = "rhein-basel") -> TrainingSession {
        session(start, plan: plan, course: course, zones: [0, 5, 15, 2, 6, 2])
    }
}

final class TrainingStatsTests: XCTestCase {
    typealias F = StatsFixture

    func testCalendarWeekIsMondayToSundayKW48() {
        let s = TrainingStats(sessions: [], now: F.now, calendar: F.cal)
        XCTAssertEqual(s.week.number, 48)
        XCTAssertEqual(s.week.start, F.date(2026, 11, 23, 0, 0))
        XCTAssertEqual(s.week.days.count, 7)
        XCTAssertEqual(s.week.days.map(\.isToday), [false, true, false, false, false, false, false])
        XCTAssertEqual(s.week.days.map(\.isFuture), [false, false, true, true, true, true, true])
        XCTAssertTrue(s.isEmpty)
        XCTAssertNil(s.week.previousAverageMinutes)
        XCTAssertNil(s.lastRide)
        XCTAssertFalse(s.distribution.isMeaningful)
        XCTAssertEqual(s.streak.weeks, 0)
        XCTAssertTrue(s.streak.jokerAvailable)
    }

    func testSimulatorExcludedDemoIncluded() {
        let sessions = [F.session(F.ago(1), minutes: 20, origin: .simulator),
                        F.session(F.ago(1), minutes: 25, origin: .demo),
                        F.session(F.ago(0, hour: 9), minutes: 10)]
        let s = TrainingStats(sessions: sessions, now: F.now, calendar: F.cal)
        XCTAssertEqual(s.totalSessions, 2)
        XCTAssertEqual(s.week.minutes, 35, accuracy: 1e-9)
        XCTAssertEqual(s.week.sessions, 2)
    }

    func testFutureSessionsIgnored() {
        let s = TrainingStats(sessions: [F.session(F.now.addingTimeInterval(3600))], now: F.now, calendar: F.cal)
        XCTAssertTrue(s.isEmpty)
    }

    func testWeekSumsAndHardestPerDay() {
        let sessions = [
            F.easy(F.ago(1, hour: 8)),                          // Mo leicht
            F.hard(F.ago(1, hour: 18)),                         // Mo hart → Mo hart
            F.easy(F.ago(2)),                                   // So, Vorwoche
        ]
        let s = TrainingStats(sessions: sessions, now: F.now, calendar: F.cal)
        XCTAssertEqual(s.week.days[0].level, .hard)
        XCTAssertEqual(s.week.days[0].minutes, 60, accuracy: 1e-9)
        XCTAssertNil(s.week.days[1].level)
        XCTAssertEqual(s.week.minutes, 60, accuracy: 1e-9)
        XCTAssertEqual(s.week.distance, 14000, accuracy: 1e-9)
        XCTAssertEqual(s.week.sessions, 2)
        // Schnitt der 4 Vorwochen: nur die Sonntagsfahrt, 30 min / 4
        XCTAssertEqual(s.week.previousAverageMinutes ?? -1, 7.5, accuracy: 1e-9)
        XCTAssertEqual(s.week.previousAverageDistance ?? -1, 1750, accuracy: 1e-9)
        XCTAssertEqual(s.week.lastWeekSessions, 1)
        XCTAssertEqual(s.week.lastWeekMinutes, 30, accuracy: 1e-9)
        XCTAssertFalse(s.week.isFreshWeek)
    }

    func testFreshWeekAfterWeekChange() {
        // Montag früh, Fahrten nur in der Vorwoche (Sa, So) und davor
        let monday = F.date(2026, 11, 23, 7, 0)
        let sessions = [F.session(F.date(2026, 11, 21), minutes: 40), F.session(F.date(2026, 11, 22), minutes: 30),
                        F.session(F.date(2026, 11, 10), minutes: 20)]
        let s = TrainingStats(sessions: sessions, now: monday, calendar: F.cal)
        XCTAssertTrue(s.week.isFreshWeek)
        XCTAssertEqual(s.week.minutes, 0)
        XCTAssertEqual(s.week.lastWeekSessions, 2)
        XCTAssertEqual(s.week.lastWeekMinutes, 70, accuracy: 1e-9)
        XCTAssertFalse(TrainingStats(sessions: [], now: monday, calendar: F.cal).week.isFreshWeek)
    }

    func testPreviousAverageOnlyFourWeeks() {
        // 30 min am Montag jeder der letzten 6 Wochen; nur 4 zählen
        let sessions = (1...6).map { F.session(F.cal.date(byAdding: .weekOfYear, value: -$0, to: F.date(2026, 11, 23))!) }
        let s = TrainingStats(sessions: sessions, now: F.now, calendar: F.cal)
        XCTAssertEqual(s.week.previousAverageMinutes ?? -1, 30, accuracy: 1e-9)
        XCTAssertEqual(s.week.minutes, 0)
    }

    func testDistribution28DaysByZoneTime() {
        var sessions = (0..<5).map { F.session(F.ago($0 + 1), zones: [1, 1, 8, 0, 0, 0]) }    // je 10 min leicht
        sessions.append(F.session(F.ago(30), zones: [0, 0, 0, 0, 60, 0]))                       // zu alt
        sessions.append(F.session(F.ago(6), zones: nil))                                        // ohne Puls
        var s = TrainingStats(sessions: sessions, now: F.now, calendar: F.cal)
        XCTAssertEqual(s.distribution.sessionsWithHeartRate, 5)
        XCTAssertEqual(s.distribution.sessions, 6)
        XCTAssertFalse(s.distribution.isMeaningful, "unter 6 Fahrten mit Puls keine Prozentwerte")

        sessions.append(F.session(F.ago(27), zones: [0, 0, 2, 3, 4, 1]))                         // 2 leicht, 3 mittel, 5 hart
        s = TrainingStats(sessions: sessions, now: F.now, calendar: F.cal)
        let d = s.distribution
        XCTAssertTrue(d.isMeaningful)
        XCTAssertEqual(d.easySeconds, 52 * 60, accuracy: 1e-9)
        XCTAssertEqual(d.moderateSeconds, 3 * 60, accuracy: 1e-9)
        XCTAssertEqual(d.hardSeconds, 5 * 60, accuracy: 1e-9)
        XCTAssertEqual(d.easyShare + d.moderateShare + d.hardShare, 1, accuracy: 1e-9)
        XCTAssertEqual(d.hardSessions, 1)
    }

    func testStreakCountsWeeksWithGoal() {
        // 3 volle Vorwochen mit je 3 Fahrten, diese Woche erst 1 → Serie 3, laufende Woche offen
        var sessions: [TrainingSession] = []
        for w in 1...3 {
            let mon = F.cal.date(byAdding: .weekOfYear, value: -w, to: F.date(2026, 11, 23))!
            for d in [0, 2, 4] { sessions.append(F.session(F.cal.date(byAdding: .day, value: d, to: mon)!)) }
        }
        sessions.append(F.session(F.ago(1)))
        var s = TrainingStats(sessions: sessions, now: F.now, calendar: F.cal)
        XCTAssertEqual(s.streak.weeks, 3)
        XCTAssertFalse(s.streak.thisWeekMet)
        XCTAssertEqual(s.streak.thisWeekSessions, 1)
        XCTAssertTrue(s.streak.jokerAvailable)

        // diese Woche 3 Fahrten → 4
        sessions += [F.session(F.ago(1, hour: 18)), F.session(F.ago(0, hour: 7))]
        s = TrainingStats(sessions: sessions, now: F.now, calendar: F.cal)
        XCTAssertEqual(s.streak.weeks, 4)
        XCTAssertTrue(s.streak.thisWeekMet)
    }

    /// Wochen relativ zur laufenden Woche: -1 = letzte Woche; `n` Fahrten je Woche
    private func weeks(_ plan: [Int: Int]) -> [TrainingSession] {
        var out: [TrainingSession] = []
        for (w, n) in plan {
            let mon = F.cal.date(byAdding: .weekOfYear, value: w, to: F.date(2026, 11, 23))!
            for d in 0..<n { out.append(F.session(F.cal.date(byAdding: .day, value: d, to: mon)!)) }
        }
        return out
    }

    func testStreakJokerBridgesOneMissedWeek() {
        // -5, -4 erreicht; -3 verpasst (Joker); -2, -1 erreicht → 4 Wochen, Joker verbraucht
        let s = TrainingStats(sessions: weeks([-5: 3, -4: 3, -3: 1, -2: 3, -1: 3]), now: F.now, calendar: F.cal)
        XCTAssertEqual(s.streak.weeks, 4)
        XCTAssertFalse(s.streak.jokerAvailable)
        XCTAssertFalse(s.streak.jokerUsedLastWeek)
    }

    func testStreakJokerUsedLastWeek() {
        let s = TrainingStats(sessions: weeks([-3: 3, -2: 3, -1: 0, 0: 1]), now: F.now, calendar: F.cal)
        XCTAssertEqual(s.streak.weeks, 2)
        XCTAssertTrue(s.streak.jokerUsedLastWeek)
        XCTAssertFalse(s.streak.jokerAvailable)
    }

    func testStreakBreaksAfterSecondMiss() {
        // -6 erreicht, -5 verpasst (Joker), -4 erreicht, -3 verpasst (kein Joker) → neu; -2, -1 erreicht → 2
        let s = TrainingStats(sessions: weeks([-6: 3, -5: 0, -4: 3, -3: 2, -2: 3, -1: 3]), now: F.now, calendar: F.cal)
        XCTAssertEqual(s.streak.weeks, 2)
        XCTAssertTrue(s.streak.jokerAvailable)
    }

    func testStreakJokerReturnsAfterFourWeeks() {
        // -7 erreicht, -6 verpasst (Joker), -5…-2 erreicht (4 Wochen → Joker zurück), -1 verpasst (Joker) → 5
        let s = TrainingStats(sessions: weeks([-7: 3, -6: 0, -5: 3, -4: 3, -3: 3, -2: 4, -1: 1]),
                              now: F.now, calendar: F.cal)
        XCTAssertEqual(s.streak.weeks, 5)
        XCTAssertTrue(s.streak.jokerUsedLastWeek)
    }

    func testStreakCustomGoal() {
        let s = TrainingStats(sessions: weeks([-2: 2, -1: 2]), now: F.now, calendar: F.cal, weeklyGoal: 2)
        XCTAssertEqual(s.streak.weeks, 2)
        XCTAssertEqual(s.streak.goal, 2)
    }

    func testCourseRecordsAndBestTimeOnlyFullFreeRuns() {
        let sessions = [
            F.session(F.ago(20), minutes: 19, distance: 4000, full: true),
            F.session(F.ago(15), minutes: 18.5, distance: 4000, full: true, interrupted: true),  // unterbrochen
            F.session(F.ago(10), plan: "grundlage-locker-30", minutes: 15, distance: 4000, full: true), // Programm
            F.session(F.ago(8), minutes: 10, distance: 2100, full: false),                       // nicht ganz
            F.session(F.ago(5), course: "rhein-basel", minutes: 16, distance: 3100, full: true),
        ]
        let s = TrainingStats(sessions: sessions, now: F.now, calendar: F.cal)
        let uto = s.courses["zuerichsee-utoquai"]
        XCTAssertEqual(uto?.rides, 4)
        XCTAssertEqual(uto?.distance ?? 0, 14100, accuracy: 1e-9)
        XCTAssertEqual(uto?.bestTime ?? 0, 19 * 60, accuracy: 1e-9)
        XCTAssertEqual(uto?.bestDate, F.ago(20))
        XCTAssertEqual(uto?.lastDate, F.ago(8))
        XCTAssertEqual(s.courses["rhein-basel"]?.rides, 1)
        XCTAssertNil(s.courses["rhein-stein"])
    }

    func testLastRideCourseBestOnlyWhenImproved() {
        var sessions = [F.session(F.ago(9), minutes: 19, distance: 4000, full: true),
                        F.session(F.ago(1), minutes: 18.45, distance: 4000, full: true)]
        var s = TrainingStats(sessions: sessions, now: F.now, calendar: F.cal)
        XCTAssertEqual(s.lastRide?.session.start, F.ago(1))
        XCTAssertEqual(s.lastRide?.isCourseBest, true)
        XCTAssertEqual(s.lastRide?.improvement ?? 0, 33, accuracy: 1e-6)

        // erste Fahrt auf der Strecke: kein Hinweis
        s = TrainingStats(sessions: [sessions[1]], now: F.now, calendar: F.cal)
        XCTAssertEqual(s.lastRide?.isCourseBest, false)

        // langsamer: kein Hinweis
        sessions[1] = F.session(F.ago(1), minutes: 20, distance: 4000, full: true)
        s = TrainingStats(sessions: sessions, now: F.now, calendar: F.cal)
        XCTAssertEqual(s.lastRide?.isCourseBest, false)
        XCTAssertNil(s.lastRide?.improvement)
    }

    func testIntensityRules() {
        let best2k = 480.0   // Basis 2:00 /500 m
        XCTAssertEqual(F.level("grundlage-locker-30"), .easy)
        XCTAssertEqual(F.level("technik-locker-25"), .easy)
        XCTAssertEqual(F.level("frequenzleiter-18-24"), .moderate)
        XCTAssertEqual(F.level("schwelle-4x6"), .moderate)
        XCTAssertEqual(F.level("langintervalle-4x4"), .hard)
        XCTAssertEqual(F.level("sprint-8x250"), .hard)
        XCTAssertEqual(F.level("test-2000m"), .hard)
        // frei mit Puls
        XCTAssertEqual(IntensityRules.level(zoneSeconds: [0, 0, 1800, 300, 300, 0]), .easy)
        XCTAssertEqual(IntensityRules.level(zoneSeconds: [0, 0, 600, 900, 300, 0]), .moderate)    // 20 min Z3–5
        XCTAssertEqual(IntensityRules.level(zoneSeconds: [0, 0, 1200, 300, 500, 100]), .hard)     // 10 min Z4–5
        XCTAssertEqual(IntensityRules.level(zoneSeconds: [0, 0, 60, 0, 400, 0]), .hard)            // kurz, meist hart
        XCTAssertNil(IntensityRules.level(zoneSeconds: [0, 0, 30, 0, 0, 0]))
        XCTAssertNil(IntensityRules.level(zoneSeconds: nil))
        // ohne Puls nach Tempo
        XCTAssertEqual(IntensityRules.level(averagePace: 130, best2k: best2k), .hard)
        XCTAssertEqual(IntensityRules.level(averagePace: 140, best2k: best2k), .moderate)
        XCTAssertEqual(IntensityRules.level(averagePace: 150, best2k: best2k), .easy)
        // Reihenfolge: Programm vor Puls vor Tempo vor Belastung
        let s = F.session(F.now, plan: "grundlage-locker-30", pace: 120, zones: [0, 0, 0, 0, 30, 0], effort: 9)
        XCTAssertEqual(s.intensity(best2k: best2k), .easy)
        let free = F.session(F.now, pace: 0, zones: nil, effort: 8)
        XCTAssertEqual(free.intensity(best2k: best2k), .hard)
    }

    func testBundledPlanCategories() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("RowCoach/Resources/plans.json")
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("plans.json fehlt") }
        let plans = try WorkoutPlanCatalog.load(url: url)
        func lv(_ id: String) -> IntensityLevel? { plans.first { $0.id == id }.map(IntensityRules.level(plan:)) }
        XCTAssertEqual(lv("grundlage-locker-30"), .easy)
        XCTAssertEqual(lv("grundlage-3x10-r20"), .easy)
        XCTAssertEqual(lv("technik-locker-25"), .easy)
        XCTAssertEqual(lv("frequenzleiter-18-24"), .moderate)
        XCTAssertEqual(lv("schwelle-4x6"), .moderate)
        XCTAssertEqual(lv("pyramide-1-2-3-4-3-2-1"), .hard)
        XCTAssertEqual(lv("test-2000m"), .hard)
        // Zielwerte der Pyramide aus der 2000-m-Bestzeit
        let pyr = try XCTUnwrap(plans.first { $0.id == "pyramide-1-2-3-4-3-2-1" })
        let t = PlanTargetSummary(plan: pyr, best2k: 480)
        XCTAssertEqual(t.zone, 4)
        XCTAssertNotNil(t.pace)
        XCTAssertNotNil(t.strokeRate)
    }

    func testSessionFromRecordUsesWorkPaceAndDemoFlag() {
        let start = F.ago(1)
        let header = WorkoutHeader(startDate: start, endDate: start.addingTimeInterval(1200), courseId: "rhein-basel",
                                   courseTitle: "Rhein Basel", courseLength: 3100,
                                   device: WorkoutDevice(source: .simulator), workoutPlanId: "kurzintervalle-8x2")
        let summary = WorkoutSummary(distance: 4000, activeDuration: 1100, totalDuration: 1200, averagePace: 137.5,
                                     averageSpeed: 3.6, averageStrokeRate: 26, strokeCount: 400, averagePower: 180,
                                     maxPower: 300, calories: 200, averageHeartRate: 150, maxHeartRate: 175,
                                     heartRateZoneSeconds: [0, 60, 300, 300, 300, 140], completedCourse: false,
                                     pauseCount: 0)
        let phases = [
            PlanPhaseResult(index: 0, kind: "warmup", label: "", startTime: 0, endTime: 300, startDistance: 0,
                            endDistance: 1000, averageStrokeRate: 20, averageHeartRate: 120, completed: true),
            PlanPhaseResult(index: 1, kind: "work", label: "", startTime: 300, endTime: 420, startDistance: 1000,
                            endDistance: 1500, averageStrokeRate: 30, averageHeartRate: 165, completed: true),
            PlanPhaseResult(index: 2, kind: "rest", label: "", startTime: 420, endTime: 480, startDistance: 1500,
                            endDistance: 1550, averageStrokeRate: 14, averageHeartRate: 150, completed: true),
            PlanPhaseResult(index: 3, kind: "work", label: "", startTime: 480, endTime: 600, startDistance: 1550,
                            endDistance: 2050, averageStrokeRate: 30, averageHeartRate: 170, completed: true),
        ]
        var rec = WorkoutRecord(header: header, summary: summary, samples: [], splits: [], planPhases: phases,
                                effort: WorkoutEffort(estimate: 7, userScore: 8))
        var s = TrainingSession(record: rec, plan: F.plans.first { $0.id == "kurzintervalle-8x2" })
        XCTAssertEqual(s.origin, .simulator)
        XCTAssertFalse(s.countsInStats)
        XCTAssertEqual(s.workPace ?? 0, 120, accuracy: 1e-9)   // 240 s für 1000 m
        XCTAssertEqual(s.displayPace, 120, accuracy: 1e-9)
        XCTAssertEqual(s.effortScore, 8)
        XCTAssertEqual(s.planLevel, .hard)

        rec.demo = true
        s = TrainingSession(record: rec, plan: nil)
        XCTAssertEqual(s.origin, .demo)
        XCTAssertTrue(s.countsInStats)
        XCTAssertNil(s.planLevel)

        // Demo-Kennzeichnung übersteht JSON; ältere JSONs ohne Feld lesen sich als echt
        let round = try? WorkoutRecord(jsonData: rec.jsonData())
        XCTAssertEqual(round?.isDemo, true)
        rec.demo = nil
        XCTAssertEqual((try? WorkoutRecord(jsonData: rec.jsonData()))?.isDemo, false)
    }

    func testRecordsInitializerMatchesSessions() {
        let header = WorkoutHeader(startDate: F.ago(1), endDate: F.ago(1).addingTimeInterval(1800),
                                   courseId: "zuerichsee-utoquai", device: WorkoutDevice(source: .pm5))
        let summary = WorkoutSummary(distance: 7000, activeDuration: 1800, totalDuration: 1800, averagePace: 128.6,
                                     averageSpeed: 3.9, averageStrokeRate: 20, strokeCount: 600, averagePower: 150,
                                     maxPower: 200, calories: 300, averageHeartRate: 130, maxHeartRate: 140,
                                     heartRateZoneSeconds: [0, 100, 1700, 0, 0, 0], completedCourse: false,
                                     pauseCount: 0)
        let rec = WorkoutRecord(header: header, summary: summary, samples: [], splits: [])
        let s = TrainingStats(records: [rec], plans: F.plans, now: F.now, calendar: F.cal)
        XCTAssertEqual(s.totalSessions, 1)
        XCTAssertEqual(s.week.days[0].level, .easy)
    }

    func testPlanShortName() {
        let p = WorkoutPlan(id: "x", name: "Schwelle 4 x 6 Minuten", phases: [WorkoutPhase(kind: .work, durationS: 60)])
        XCTAssertEqual(p.shortName, "Schwelle 4 × 6 min")
    }
}
