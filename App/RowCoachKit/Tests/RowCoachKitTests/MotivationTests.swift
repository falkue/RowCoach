import XCTest
@testable import RowCoachKit

/// Motivationsfunktionen (docs/motivation/UMSETZUNG.md): Bestmarken aus Samples, Meilensteine, sanfter
/// Wiedereinstieg, Erholungs-Wächter, Wochenziel mit Pause, Erinnerungen, „Was heute gut war“.
final class MotivationTests: XCTestCase {
    typealias F = StatsFixture

    /// Gleichmässige Fahrt: Messpunkte jede Sekunde mit `pace` s/500 m über `seconds`
    private func steady(pace: Double, seconds: Int, start: Double = 0, from d0: Double = 0) -> [WorkoutSample] {
        (0...seconds).map { i in
            WorkoutSample(time: start + Double(i), distance: d0 + Double(i) * 500 / pace, pace: pace, strokeRate: 22,
                          power: 150, heartRate: nil)
        }
    }

    // MARK: Bestmarken aus Samples

    func testSteadyRideGivesExactDistanceTimes() {
        let e = BestEffortFinder.find(samples: steady(pace: 120, seconds: 1300))   // 2:00 /500 m, ≈ 5417 m
        XCTAssertEqual(e[.distance(500)] ?? 0, 120, accuracy: 0.01)
        XCTAssertEqual(e[.distance(2000)] ?? 0, 480, accuracy: 0.01)
        XCTAssertEqual(e[.distance(5000)] ?? 0, 1200, accuracy: 0.01)
        XCTAssertNil(e[.distance(6000)], "Fahrt zu kurz")
        XCTAssertNil(e[.time(1800)], "kürzer als 30 min")
    }

    func testFastMiddleSegmentIsFound() {
        // 1000 m locker (2:20), 2000 m schnell (1:50), 1000 m locker
        var s = steady(pace: 140, seconds: 280)
        let t1 = s.last!.time, d1 = s.last!.distance
        s += steady(pace: 110, seconds: 440, start: t1, from: d1).dropFirst()
        let t2 = s.last!.time, d2 = s.last!.distance
        s += steady(pace: 140, seconds: 280, start: t2, from: d2).dropFirst()
        let e = BestEffortFinder.find(samples: s)
        XCTAssertEqual(e[.distance(2000)] ?? 0, 440, accuracy: 0.5)
        XCTAssertEqual(e[.distance(500)] ?? 0, 110, accuracy: 0.5)
    }

    func testTimeTargetGivesFarthestDistance() {
        let e = BestEffortFinder.find(samples: steady(pace: 125, seconds: 1900))
        XCTAssertEqual(e[.time(1800)] ?? 0, 1800 * 500 / 125, accuracy: 0.5)
    }

    func testIntervalRestsSlowLongSegments() {
        // 4 × 500 m in 1:40 mit je 2 min Pause ohne Distanz: 2000 m enthalten die Pausen
        var s: [WorkoutSample] = []
        var t = 0.0, d = 0.0
        for _ in 0..<4 {
            for i in 1...100 { s.append(WorkoutSample(time: t + Double(i), distance: d + Double(i) * 5, pace: 100,
                                                      strokeRate: 30, power: 300, heartRate: nil)) }
            t += 100; d += 500
            for i in 1...120 { s.append(WorkoutSample(time: t + Double(i), distance: d, pace: 0, strokeRate: 0,
                                                      power: 0, heartRate: nil)) }
            t += 120
        }
        let e = BestEffortFinder.find(samples: s)
        XCTAssertEqual(e[.distance(500)] ?? 0, 100, accuracy: 0.5)
        XCTAssertGreaterThan(e[.distance(2000)] ?? 0, 400 + 3 * 120 - 1, "Pausen zählen mit, kein 2000-m-Rekord aus Intervallen")
    }

    func testResetAndImplausibleSpikeAreIgnored() {
        // Abschnitt 1: 600 m; PM5-Neustart; Abschnitt 2: 600 m – kein 1000-m-Teilstück über den Sprung
        var s = steady(pace: 120, seconds: 144)
        s += steady(pace: 120, seconds: 144, start: 200).map { var x = $0; x.distance -= 0; return x }
        XCTAssertNil(BestEffortFinder.find(samples: s)[.distance(1000)])
        // Messfehler: 200 m in 1 s
        var spike = steady(pace: 120, seconds: 300)
        for i in 100..<spike.count { spike[i].distance += 600 }
        let e = BestEffortFinder.find(samples: spike)
        XCTAssertGreaterThanOrEqual((e[.distance(500)] ?? 0) / 500 * 500, BestEffortFinder.minimumPace)
    }

    func testPersonalRecordOnlyWhenImprovingAnEarlierValue() {
        let first = RideDigest(session: F.session(F.ago(10)), efforts: [.distance(2000): 480])
        XCTAssertTrue(PersonalRecords.improvements(in: first, history: []).isEmpty, "erste Messung ist kein Rekord")
        let second = RideDigest(session: F.session(F.ago(2)), efforts: [.distance(2000): 470, .distance(500): 110])
        let imp = PersonalRecords.improvements(in: second, history: [first])
        XCTAssertEqual(imp.map(\.target), [.distance(2000)])
        XCTAssertEqual(imp.first?.previous, 480)
        let best = PersonalRecords.best([first, second])
        XCTAssertEqual(best[.distance(2000)]?.workoutId, second.id)
        let sim = RideDigest(session: F.session(F.ago(1), origin: .simulator), efforts: [.distance(2000): 300])
        XCTAssertEqual(PersonalRecords.best([first, second, sim])[.distance(2000)]?.value, 470)
    }

    func testEffortTargetIdsAndGhostSamples() {
        XCTAssertEqual(EffortTarget(id: "d21097"), .distance(EffortTarget.halfMarathon))
        XCTAssertEqual(EffortTarget(id: "t1800"), .time(1800))
        let ghost = PersonalRecords.ghostSamples([WorkoutSample(time: 0, distance: 0, pace: 0, strokeRate: 0, power: 0, heartRate: nil),
                                                  WorkoutSample(time: 9, distance: 0, pace: 0, strokeRate: 0, power: 0, heartRate: nil),
                                                  WorkoutSample(time: 10, distance: 4, pace: 120, strokeRate: 20, power: 100, heartRate: nil)])
        XCTAssertEqual(ghost.map(\.time), [0, 1])
    }

    // MARK: Meilensteine

    private let places = [
        CoursePlace(courseId: "zuerichsee-utoquai", region: "Zürichsee, unteres Seebecken", countryCode: "CH", countryName: "Schweiz"),
        CoursePlace(courseId: "zuerichsee-mythenquai", region: "Zürichsee, unteres Seebecken", countryCode: "CH", countryName: "Schweiz"),
        CoursePlace(courseId: "rhein-basel", region: "Rhein, Basel (Rheinknie)", countryCode: "CH", countryName: "Schweiz"),
    ]

    func testWaterNameFromRegion() {
        XCTAssertEqual(places[0].waterName, "Zürichsee")
        XCTAssertEqual(places[2].waterName, "Rhein")
        XCTAssertEqual(places[0].waterKey, places[1].waterKey)
    }

    func testMilestonesLifetimeRidesWaterCountry() {
        // 10 Fahrten à 10 km: 100 km, 10 Fahrten, Zürichsee 25 km und 100 km (je nach Strecke), Seen-Pass CH
        var sessions: [TrainingSession] = []
        let courses = ["zuerichsee-utoquai", "zuerichsee-mythenquai", "rhein-basel"]
        for i in 0..<10 {
            sessions.append(F.session(F.ago(30 - i), course: courses[i % 3], distance: 10_000))
        }
        sessions.append(F.session(F.ago(1), course: "rhein-basel", distance: 50_000, origin: .simulator))
        let m = Milestones.reached(sessions: sessions, places: places)
        let ids = m.map(\.id)
        XCTAssertTrue(ids.contains("km-100"))
        XCTAssertTrue(ids.contains("rides-10"))
        XCTAssertTrue(ids.contains("water-zürichsee-25"))
        XCTAssertTrue(ids.contains("country-CH"))
        XCTAssertFalse(ids.contains("km-250"), "Simulator zählt nie")
        // Seen-Pass mit der dritten Fahrt (erste auf dem Rhein)
        XCTAssertEqual(m.first { $0.id == "country-CH" }?.workoutId, sessions[2].id)
        XCTAssertEqual(Milestones.reached(by: sessions[9].id, sessions: sessions, places: places).map(\.id).sorted(),
                       ["km-100", "rides-10"])
        XCTAssertEqual(Milestone(kind: .lifetimeDistance(km: 1000), reachedAt: F.now, workoutId: UUID()).title,
                       "1000 km – eine Million Meter")
    }

    func testNextMilestoneOnlyWhenNear() {
        // 9 Fahrten à 10 km: 90 km und 9 Fahrten → nächste Fahrt bringt beides; Fahrten-Zählung ist 1 Fahrt
        let sessions = (0..<9).map { F.session(F.ago(20 - $0), distance: 10_000) }
        let next = Milestones.next(sessions: sessions, places: places)
        XCTAssertEqual(next?.ridesNeeded, 1)
        // 50 km mit 5-km-Fahrten: 100 km ist 10 Fahrten weg, 10 Fahrten ebenfalls → nichts
        let far = (0..<5).map { F.session(F.ago(20 - $0), distance: 5000) }
        XCTAssertNil(Milestones.next(sessions: far, places: places))
    }

    // MARK: Sanfter Wiedereinstieg

    private var plansWithShort: [WorkoutPlan] {
        F.plans + [WorkoutPlan(id: "einsteiger-1-2-3-2-1", name: "Einstieg 1-2-3-2-1", category: "Grundlage",
                               phases: [WorkoutPhase(kind: .warmup, durationS: 240, hrZone: 1),
                                        WorkoutPhase(kind: .work, durationS: 540, hrZone: 2),
                                        WorkoutPhase(kind: .cooldown, durationS: 240, hrZone: 1)])]
    }

    func testMissedWishDayOffersShortEasySession() {
        // jetzt = Di 24.11.; gestern Mo war Wunschtag ohne Fahrt; letzte Fahrt Sa (leicht)
        let sessions = [F.easy(F.ago(9)), F.easy(F.ago(6)), F.easy(F.ago(3))]
        let s = DailySuggestion.make(sessions: sessions, plans: plansWithShort, courseIds: F.courseIds, now: F.now,
                                     calendar: F.cal, best2k: 480, wishDays: [.monday, .thursday])
        XCTAssertEqual(s.rule, .reentry)
        XCTAssertTrue(s.reentry)
        XCTAssertEqual(s.planId, "einsteiger-1-2-3-2-1")
        XCTAssertEqual(s.level, .easy)
        XCTAssertTrue(s.reason.contains("17 min"), s.reason)
        XCTAssertFalse(s.reason.lowercased().contains("verpasst"))
    }

    func testNoReentryWhenRowedYesterdayOrNoWishDay() {
        let rodeYesterday = [F.easy(F.ago(6)), F.easy(F.ago(3)), F.easy(F.ago(1))]
        XCTAssertNotEqual(DailySuggestion.make(sessions: rodeYesterday, plans: plansWithShort, courseIds: F.courseIds,
                                               now: F.now, calendar: F.cal, best2k: 480, wishDays: [.monday]).rule,
                          .reentry)
        let sessions = [F.easy(F.ago(9)), F.easy(F.ago(6)), F.easy(F.ago(3))]
        XCTAssertNotEqual(DailySuggestion.make(sessions: sessions, plans: plansWithShort, courseIds: F.courseIds,
                                               now: F.now, calendar: F.cal, best2k: 480, wishDays: [.friday]).rule,
                          .reentry)
        XCTAssertNotEqual(DailySuggestion.make(sessions: sessions, plans: plansWithShort, courseIds: F.courseIds,
                                               now: F.now, calendar: F.cal, best2k: 480).rule, .reentry,
                          "ohne Wunschtage aus")
    }

    func testRecoveryWinsOverReentry() {
        // So hart, Mo Wunschtag ohne Fahrt → Di gilt Erholung (Regel 1)
        let sessions = [F.easy(F.ago(9)), F.easy(F.ago(5)), F.hard(F.ago(2, hour: 19))]
        let s = DailySuggestion.make(sessions: sessions, plans: plansWithShort, courseIds: F.courseIds,
                                     now: F.now, calendar: F.cal, best2k: 480, wishDays: [.monday])
        XCTAssertEqual(s.rule, .recovery)
        XCTAssertFalse(s.reentry)
    }

    func testReentryRuleHelper() {
        XCTAssertEqual(ReentryRule.shortPlan(plans: F.plans), "grundlage-locker-30", "ohne kurze Einheit: 30 min")
        XCTAssertEqual(ReentryRule.shortPlan(plans: plansWithShort), "einsteiger-1-2-3-2-1")
        XCTAssertFalse(ReentryRule.missedWishDay(sessions: [], at: F.now, calendar: F.cal, wishDays: [.monday]),
                       "ohne Fahrten kein Wiedereinstieg")
    }

    // MARK: Erholungs-Wächter

    func testRecoveryGuardRules() {
        XCTAssertEqual(RecoveryGuard.state(sessions: [F.hard(F.ago(1))], now: F.now, calendar: F.cal).reason, .recentHard)
        XCTAssertNil(RecoveryGuard.state(sessions: [F.hard(F.ago(3))], now: F.now, calendar: F.cal).reason)
        // Masters 72 h
        XCTAssertEqual(RecoveryGuard.state(sessions: [F.hard(F.ago(2, hour: 10))], now: F.now, calendar: F.cal,
                                           hardGapHours: 72).reason, .recentHard)
        XCTAssertNil(RecoveryGuard.state(sessions: [F.hard(F.ago(2, hour: 10))], now: F.now, calendar: F.cal).reason)
        XCTAssertEqual(RecoveryGuard.state(sessions: [F.session(F.ago(1), plan: "schwelle-4x6")], now: F.now,
                                           calendar: F.cal).reason, .recentModerate)
        // sehr hohe Anstrengung bei leichter Einstufung
        XCTAssertEqual(RecoveryGuard.state(sessions: [F.session(F.ago(1), zones: [0, 2, 28, 0, 0, 0], effort: 9)],
                                           now: F.now, calendar: F.cal).reason, .highEffort)
        // drei lockere Einheiten mit Anstrengung ≥ 7
        let felt = [5, 3, 0].map { F.session(F.ago($0, hour: $0 == 0 ? 7 : 11), zones: [0, 2, 28, 0, 0, 0], effort: 7) }
        XCTAssertEqual(RecoveryGuard.state(sessions: felt, now: F.now, calendar: F.cal).reason, .easyFeltHard)
        XCTAssertEqual(RecoveryGuard.state(sessions: [], now: F.now, calendar: F.cal, planRestDay: true).reason, .planRestDay)
        XCTAssertFalse(RecoveryGuard.state(sessions: [F.easy(F.ago(1))], now: F.now, calendar: F.cal).silencesChallenges)
    }

    func testRestDayPraise() {
        XCTAssertNotNil(RecoveryGuard.restDayPraise(sessions: [F.hard(F.ago(2))], now: F.now, calendar: F.cal))
        XCTAssertNil(RecoveryGuard.restDayPraise(sessions: [F.easy(F.ago(2))], now: F.now, calendar: F.cal))
        XCTAssertNil(RecoveryGuard.restDayPraise(sessions: [F.hard(F.ago(2)), F.easy(F.ago(1))], now: F.now, calendar: F.cal))
    }

    func testHomeMotivationSilencesMilestoneDuringRecovery() {
        let sessions = (0..<9).map { F.session(F.ago(20 - $0), distance: 10_000) } + [F.hard(F.ago(1))]
        let h = HomeMotivation.make(sessions: sessions, now: F.now, calendar: F.cal, inputs: .init(places: places))
        XCTAssertTrue(h.recovery.recoveryRecommended)
        XCTAssertNil(h.milestone)
    }

    // MARK: Wochenziel mit Pause

    func testPauseFreezesStreakWithoutJoker() {
        // drei Wochen erreicht (3 Fahrten), Vorwoche komplett pausiert ohne Fahrt, diese Woche offen
        var sessions: [TrainingSession] = []
        for mon in [15, 22, 29] { for d in [0, 2, 4] { sessions.append(F.easy(F.ago(mon - d))) } }
        let lastWeekStart = F.date(2026, 11, 16, 0, 0)
        let pause = GoalPause(start: lastWeekStart, days: 7, reason: .ill, calendar: F.cal)
        let withPause = TrainingStats(sessions: sessions, now: F.now, calendar: F.cal, goal: .default, pauses: [pause])
        XCTAssertEqual(withPause.streak.weeks, 3)
        XCTAssertTrue(withPause.streak.jokerAvailable, "Pause verbraucht keinen Joker")
        XCTAssertFalse(withPause.streak.jokerUsedLastWeek)
        let without = TrainingStats(sessions: sessions, now: F.now, calendar: F.cal, goal: .default)
        XCTAssertFalse(without.streak.jokerAvailable, "ohne Pause hätte die leere Woche den Joker gebraucht")
    }

    func testPartialPauseScalesTargetAndMinutesGoal() {
        let goal = WeeklyGoal(kind: .rides, value: 3)
        XCTAssertEqual(goal.target(freeDays: 7), 3)
        XCTAssertEqual(goal.target(freeDays: 4), 2)
        XCTAssertEqual(goal.target(freeDays: 1), 0)
        XCTAssertEqual(WeeklyGoal(kind: .rides, value: 9).value, 6, "höchstens 6 Fahrten")
        // Minuten: diese Woche (ab Mo 23.11.) 2 × 30 min von 90
        let s = TrainingStats(sessions: [F.easy(F.ago(1)), F.easy(F.ago(0, hour: 7))], now: F.now, calendar: F.cal,
                              goal: WeeklyGoal(kind: .minutes, value: 90))
        XCTAssertEqual(s.streak.kind, .minutes)
        XCTAssertEqual(s.streak.thisWeekProgress, 60)
        XCTAssertFalse(s.streak.thisWeekMet)
        XCTAssertEqual(s.streak.progressText, "60 von 90 min")
        // Pause ab heute: Ziel der Woche sinkt (Mo frei, Di–So Pause → 1 freier Tag → eingefroren)
        let p = GoalPause(start: F.now, days: 6, calendar: F.cal)
        let paused = TrainingStats(sessions: [], now: F.now, calendar: F.cal, goal: goal, pauses: [p])
        XCTAssertEqual(paused.streak.effectiveTarget, 0)
        XCTAssertTrue(paused.streak.pausedToday)
        XCTAssertEqual(GoalPause(start: F.now, days: 60, calendar: F.cal).end,
                       F.cal.date(byAdding: .day, value: 27, to: F.cal.startOfDay(for: F.now)), "höchstens 4 Wochen")
        XCTAssertNil(p.ended(at: F.now, calendar: F.cal), "am ersten Tag beendet: entfällt")
    }

    func testGoalReviewUpAfterFourMetWeeksDownAfterThreeMissed() {
        var met: [TrainingSession] = []
        for mon in [8, 15, 22, 29, 36] { for d in [0, 2, 4] { met.append(F.easy(F.ago(mon - d))) } }
        let up = GoalReview.make(sessions: met, now: F.now, calendar: F.cal, goal: .default, pauses: [], goalSince: nil,
                                 dismissedAt: nil)
        XCTAssertEqual(up?.direction, .up)
        XCTAssertEqual(up?.proposed.value, 4)
        XCTAssertNil(GoalReview.make(sessions: met, now: F.now, calendar: F.cal, goal: .default, pauses: [],
                                     goalSince: F.ago(10), dismissedAt: nil), "erst nach 4 Wochen mit diesem Ziel")
        XCTAssertNil(GoalReview.make(sessions: met, now: F.now, calendar: F.cal, goal: .default, pauses: [],
                                     goalSince: nil, dismissedAt: F.ago(3)), "nach „Passt so“ Ruhe")
        let missed = [F.easy(F.ago(40)), F.easy(F.ago(20)), F.easy(F.ago(12)), F.easy(F.ago(5))]
        let down = GoalReview.make(sessions: missed, now: F.now, calendar: F.cal, goal: .default, pauses: [],
                                   goalSince: nil, dismissedAt: nil)
        XCTAssertEqual(down?.direction, .down)
        XCTAssertEqual(down?.proposed.value, 2)
    }

    // MARK: Erinnerungen

    func testRemindersOnlyOnWishDaysOncePerDay() {
        let intention = RowingIntention(days: [.tuesday, .thursday], hour: 19, cue: .afterWork, remindersOn: true)
        // jetzt Di 18:05: heute 19:00, Do, nächster Di (8 Tage Horizont: Di, Do, Di)
        let slots = ReminderPlanner.plan(intention: intention, days: intention.days, now: F.now, calendar: F.cal,
                                         sessions: [])
        XCTAssertEqual(slots.count, 3)
        XCTAssertEqual(Set(slots.map(\.identifier)).count, slots.count)
        XCTAssertTrue(slots[0].body.hasPrefix("Nach der Arbeit"))
        XCTAssertFalse(slots[0].body.contains("verpass"))
        // heute schon gerudert → nicht heute
        let rowed = ReminderPlanner.plan(intention: intention, days: intention.days, now: F.now, calendar: F.cal,
                                         sessions: [F.easy(F.ago(0, hour: 7))])
        XCTAssertEqual(rowed.count, 2)
        // Pause bis Freitag → nur der nächste Dienstag
        let pause = GoalPause(start: F.now, days: 4, calendar: F.cal)
        XCTAssertEqual(ReminderPlanner.plan(intention: intention, days: intention.days, now: F.now, calendar: F.cal,
                                            sessions: [], pauses: [pause]).count, 1)
        // Plan: nur Tage mit Einheit (Do ist Ruhetag laut Plan)
        let planDays = [F.cal.startOfDay(for: F.now)]
        XCTAssertEqual(ReminderPlanner.plan(intention: intention, days: intention.days, now: F.now, calendar: F.cal,
                                            sessions: [], trainingDates: planDays).count, 1)
        // aus → nichts
        var off = intention
        off.remindersOn = false
        XCTAssertTrue(ReminderPlanner.plan(intention: off, days: off.days, now: F.now, calendar: F.cal, sessions: []).isEmpty)
    }

    func testQuietWeekAfterTwoIgnoredReminders() {
        let r1 = F.ago(5, hour: 19), r2 = F.ago(3, hour: 19)
        let q = ReminderPlanner.quietUntil(reminders: [r1, r2], sessions: [], now: F.now, calendar: F.cal)
        XCTAssertEqual(q, F.cal.date(byAdding: .day, value: 7, to: F.cal.startOfDay(for: r2)))
        XCTAssertNil(ReminderPlanner.quietUntil(reminders: [r1, r2], sessions: [F.easy(F.ago(3))], now: F.now,
                                                calendar: F.cal))
        let intention = RowingIntention(days: Set(Weekday.allCases), remindersOn: true)
        let slots = ReminderPlanner.plan(intention: intention, days: intention.days, now: F.now, calendar: F.cal,
                                         sessions: [], quietUntil: q)
        XCTAssertTrue(slots.allSatisfy { $0.date >= q! })
    }

    // MARK: Was heute gut war

    func testHighlightsCourseBestRecordAndMaxThree() {
        let earlier = RideDigest(session: F.session(F.ago(10), minutes: 20, distance: 4000, full: true),
                                 efforts: [.distance(2000): 500, .distance(1000): 245])
        let today = RideDigest(session: F.session(F.ago(0, hour: 7), minutes: 19, distance: 4000, full: true),
                               efforts: [.distance(2000): 490, .distance(1000): 240])
        let h = RideHighlights.make(ride: today, history: [earlier], goal: .default, calendar: F.cal, best2k: 480)
        XCTAssertLessThanOrEqual(h.count, 3)
        XCTAssertEqual(h.first?.kind, .courseBest)
        XCTAssertTrue(h.first?.text.contains("60 s schneller") ?? false, h.first?.text ?? "")
        XCTAssertEqual(h[1].kind, .personalRecord)
        XCTAssertTrue(h[1].text.contains("1000 m") && h[1].text.contains("2000 m"))
        XCTAssertEqual(PostRideCoach.level(for: h), 2)
    }

    func testHighlightsFallbackAlwaysSaysSomethingTrue() {
        let ride = RideDigest(session: F.session(F.ago(0, hour: 7), minutes: 12))
        let h = RideHighlights.make(ride: ride, history: [RideDigest(session: F.session(F.ago(2)))], calendar: F.cal)
        XCTAssertEqual(h.map(\.kind), [.presence])
        XCTAssertTrue(h[0].text.hasPrefix("12 min"))
        XCTAssertEqual(PostRideCoach.level(for: h), 1)
        let sim = RideDigest(session: F.session(F.ago(0), origin: .simulator))
        XCTAssertTrue(RideHighlights.make(ride: sim, history: []).isEmpty)
    }

    func testHighlightsComebackIntervalsAndRestRule() {
        let old = RideDigest(session: F.session(F.ago(20), plan: "kurzintervalle-8x2"), workPaces: [112, 113, 115])
        let ride = RideDigest(session: F.session(F.ago(0, hour: 7), plan: "kurzintervalle-8x2"),
                              workPaces: [110, 111, 110.5, 111.5])
        let kinds = RideHighlights.make(ride: ride, history: [old], calendar: F.cal).map(\.kind)
        XCTAssertEqual(kinds, [.fastestInterval, .steadyIntervals, .comeback])
        // locker nach hart gestern
        let easy = RideDigest(session: F.easy(F.ago(0, hour: 7)))
        let afterHard = RideHighlights.make(ride: easy, history: [RideDigest(session: F.hard(F.ago(1)))], calendar: F.cal)
        XCTAssertTrue(afterHard.contains { $0.kind == .restRule })
        XCTAssertTrue(afterHard.contains { $0.kind == .zoneHeld })
    }

    func testHighlightsHeartRateLowerAtSamePace() {
        func ride(_ ago: Int, hr: Int, hour: Int = 11) -> RideDigest {
            var s = F.easy(F.ago(ago, hour: hour))
            s.averageHeartRate = hr
            return RideDigest(session: s)
        }
        let h = RideHighlights.make(ride: ride(0, hr: 132, hour: 7), history: [ride(35, hr: 140), ride(40, hr: 138)],
                                    calendar: F.cal)
        XCTAssertTrue(h.contains { $0.kind == .heartRateLower && $0.text.contains("7 Schläge") }, h.map(\.text).description)
    }

    func testWeeklyGoalHighlightWhenThisRideReachesIt() {
        let ride = RideDigest(session: F.easy(F.ago(0, hour: 7)))
        let history = [RideDigest(session: F.easy(F.ago(1)))]
        let h = RideHighlights.make(ride: ride, history: history, goal: WeeklyGoal(kind: .rides, value: 2), calendar: F.cal)
        XCTAssertTrue(h.contains { $0.kind == .weeklyGoal })
    }
}
