import XCTest
@testable import RowCoachKit

final class DailySuggestionTests: XCTestCase {
    typealias F = StatsFixture

    private func suggest(_ sessions: [TrainingSession], now: Date = StatsFixture.now,
                         preferred: String? = nil) -> DailySuggestion {
        DailySuggestion.make(sessions: sessions, plans: F.plans, courseIds: F.courseIds, now: now, calendar: F.cal,
                             best2k: 480, preferredCourseId: preferred)
    }

    /// Regelmässig leicht: alle 2–3 Tage 30 min Zone 2 über `weeks` Wochen, letzte Fahrt vor `lastAgo` Tagen
    private func regularEasy(weeks: Int = 5, lastAgo: Int = 2) -> [TrainingSession] {
        stride(from: lastAgo, through: weeks * 7, by: 3).map { F.easy(F.ago($0), course: F.courseIds[$0 % 5]) }
    }

    // MARK: Regel 0

    func testNoHistoryWelcomesWithEasyOnHomeCourse() {
        let s = suggest([])
        XCTAssertEqual(s.planId, "grundlage-locker-30")
        XCTAssertEqual(s.rule, .start)
        XCTAssertEqual(s.courseId, "zuerichsee-utoquai")
        XCTAssertFalse(s.doneToday)
        XCTAssertEqual(s.level, .easy)
        XCTAssertTrue(s.reason.contains("Willkommen"))
        XCTAssertEqual(s.alternatives.count, 2)
        XCTAssertEqual(s.alternatives[1], .free(courseId: "zuerichsee-utoquai"))
    }

    func testFewerThanThreeSessions() {
        let s = suggest([F.hard(F.ago(3)), F.hard(F.ago(5))])
        XCTAssertEqual(s.rule, .start)
        XCTAssertEqual(s.planId, "grundlage-locker-30")
    }

    func testLongPauseRestartsEasy() {
        let s = suggest([F.hard(F.ago(8)), F.easy(F.ago(10)), F.easy(F.ago(12))])
        XCTAssertEqual(s.rule, .start)
        XCTAssertFalse(s.reason.contains("Tage"), "keine Schuld-Formulierung mit Tagen Pause")
    }

    func testSimulatorRidesDoNotCount() {
        let sim = (1...5).map { F.session(F.ago($0), plan: "kurzintervalle-8x2", origin: .simulator) }
        XCTAssertEqual(suggest(sim).rule, .start)
    }

    // MARK: Regel 1

    func testHardYesterdayGivesTechnique() {
        let s = suggest([F.easy(F.ago(5)), F.easy(F.ago(3)), F.hard(F.ago(1, hour: 18))])
        XCTAssertEqual(s.rule, .recovery)
        XCTAssertEqual(s.planId, "technik-locker-25")
        XCTAssertTrue(s.reason.hasPrefix("Gestern"))
    }

    func testModerateYesterdayGivesEasy30() {
        let s = suggest([F.easy(F.ago(5)), F.easy(F.ago(3)), F.session(F.ago(1), plan: "schwelle-4x6")])
        XCTAssertEqual(s.rule, .recovery)
        XCTAssertEqual(s.planId, "grundlage-locker-30")
    }

    func testHardTwoDaysAgoWithin48hGivesEasy30() {
        // So 20:00 → Di 18:05 = 46 h
        let s = suggest([F.easy(F.ago(5)), F.easy(F.ago(4)), F.hard(F.ago(2, hour: 20))])
        XCTAssertEqual(s.rule, .recovery)
        XCTAssertEqual(s.planId, "grundlage-locker-30")
        XCTAssertTrue(s.reason.hasPrefix("Vorgestern"))
    }

    func testHardMoreThan48hAgoIsNoLongerRecovery() {
        let s = suggest([F.easy(F.ago(5)), F.easy(F.ago(4)), F.hard(F.ago(2, hour: 9))])
        XCTAssertNotEqual(s.rule, .recovery)
    }

    // MARK: Regel 2

    func testTwoHardInSevenDaysGivesBase() {
        let s = suggest([F.easy(F.ago(9)), F.hard(F.ago(6)), F.hard(F.ago(3, hour: 9))])
        XCTAssertEqual(s.rule, .enoughHard)
        XCTAssertEqual(s.planId, "grundlage-3x10-r20", "nie gefahren → 3 × 10 zuerst")
        XCTAssertEqual(s.level, .easy)
    }

    func testBaseAlternatesWithEasy30() {
        let s = suggest([F.easy(F.ago(9), plan: "grundlage-locker-30"), F.easy(F.ago(8), plan: "grundlage-3x10-r20"),
                         F.hard(F.ago(6)), F.hard(F.ago(3, hour: 9))])
        XCTAssertEqual(s.rule, .enoughHard)
        XCTAssertEqual(s.planId, "grundlage-locker-30")
    }

    // MARK: Regel 3

    func testTooLittleEasyGivesBase() {
        // 6 Fahrten mit Puls, je 15 min leicht + 10 min Zone 3 → 60 % leicht; keine harte Einheit
        let mixed = (0..<6).map { F.session(F.ago(3 + 3 * $0), plan: "frequenzleiter-18-24",
                                            zones: [0, 5, 10, 10, 0, 0]) }
        let s = suggest(mixed)
        XCTAssertEqual(s.rule, .moreEasy)
        XCTAssertTrue(s.reason.contains("60 %"))
        XCTAssertTrue(["grundlage-3x10-r20", "grundlage-locker-30"].contains(s.planId))
    }

    func testFiveHeartRateSessionsAreNotEnoughForRule3() {
        let mixed = (0..<5).map { F.session(F.ago(3 + 3 * $0), plan: "frequenzleiter-18-24",
                                            zones: [0, 5, 10, 10, 0, 0]) }
        XCTAssertNotEqual(suggest(mixed).rule, .moreEasy)
    }

    // MARK: Regel 4

    func testTestAfterFourRegularWeeksWithoutTest() {
        let s = suggest(regularEasy())
        XCTAssertEqual(s.rule, .test)
        XCTAssertEqual(s.planId, "test-2000m")
    }

    func testRecentTestPreventsAnotherTest() {
        var sessions = regularEasy()
        sessions.append(F.session(F.ago(40), plan: "test-2000m", zones: [0, 0, 2, 2, 4, 0]))
        let s = suggest(sessions)
        XCTAssertEqual(s.rule, .stimulus)
    }

    func testOldTestAllowsNewTest() {
        var sessions = regularEasy()
        sessions.append(F.session(F.ago(60), plan: "test-2000m", zones: [0, 0, 2, 2, 4, 0]))
        XCTAssertEqual(suggest(sessions).rule, .test)
    }

    func testIrregularTrainingSkipsTest() {
        // nur in den letzten 2 Wochen regelmässig
        let s = suggest(regularEasy(weeks: 2))
        XCTAssertEqual(s.rule, .stimulus)
    }

    // MARK: Regel 5

    func testStimulusPicksLongestNotRowed() {
        var sessions = regularEasy(weeks: 2)
        sessions += [F.hard(F.ago(20), plan: "schwelle-4x6"), F.hard(F.ago(13), plan: "langintervalle-4x4"),
                     F.hard(F.ago(10), plan: "kurzintervalle-8x2"), F.hard(F.ago(30), plan: "sprint-8x250")]
        let s = suggest(sessions)
        XCTAssertEqual(s.rule, .stimulus)
        XCTAssertEqual(s.planId, "pyramide-1-2-3-4-3-2-1", "nie gefahren zuerst")
        XCTAssertTrue(s.reason.contains("Zuletzt kurzintervalle-8x2"))
        XCTAssertEqual(s.level, .hard)
    }

    func testStimulusOldestWhenAllRowed() {
        var sessions = regularEasy(weeks: 2)
        sessions += [F.hard(F.ago(16), plan: "schwelle-4x6"), F.hard(F.ago(13), plan: "langintervalle-4x4"),
                     F.hard(F.ago(10), plan: "kurzintervalle-8x2"), F.hard(F.ago(20), plan: "pyramide-1-2-3-4-3-2-1"),
                     F.hard(F.ago(9), plan: "sprint-8x250")]
        XCTAssertEqual(suggest(sessions).planId, "pyramide-1-2-3-4-3-2-1")
    }

    func testSprintAtMostEvery14Days() {
        var sessions = regularEasy(weeks: 2)
        // Test vor 40 Tagen, damit Regel 4 (4 Wochen regelmässig) nicht greift
        sessions.insert(F.session(F.ago(40), plan: "test-2000m", zones: [0, 0, 2, 2, 4, 0]), at: 0)
        // alle Rotationsprogramme kürzlich, Sprint vor 10 Tagen → kein Sprint
        sessions += [F.hard(F.ago(25), plan: "schwelle-4x6"), F.hard(F.ago(22), plan: "langintervalle-4x4"),
                     F.hard(F.ago(19), plan: "kurzintervalle-8x2"), F.hard(F.ago(16), plan: "pyramide-1-2-3-4-3-2-1"),
                     F.hard(F.ago(10), plan: "sprint-8x250")]
        XCTAssertNotEqual(suggest(sessions).planId, "sprint-8x250")
        XCTAssertEqual(suggest(sessions).planId, "schwelle-4x6")

        // Sprint vor 30 Tagen und älter als alle anderen → Sprint
        sessions[sessions.count - 1] = F.hard(F.ago(30), plan: "sprint-8x250")
        XCTAssertEqual(suggest(sessions).planId, "sprint-8x250")
    }

    // MARK: Zusätze

    func testDoneTodaySuggestsForTomorrow() {
        var sessions = regularEasy(weeks: 2)
        sessions.append(F.hard(F.ago(0, hour: 7)))
        let s = suggest(sessions)
        XCTAssertTrue(s.doneToday)
        XCTAssertEqual(F.cal.dateComponents([.day], from: F.now, to: s.forDate).day, 1)
        // morgen: heute hart → Technik
        XCTAssertEqual(s.planId, "technik-locker-25")
        XCTAssertTrue(s.reason.hasPrefix("Gestern"))
    }

    func testDeterministicAndOrderIndependent() {
        var sessions = regularEasy(weeks: 3)
        sessions += [F.hard(F.ago(12), plan: "schwelle-4x6"), F.hard(F.ago(15), plan: "pyramide-1-2-3-4-3-2-1")]
        let a = suggest(sessions), b = suggest(sessions.reversed())
        XCTAssertEqual(a, b)
        XCTAssertEqual(a, suggest(sessions))
    }

    func testCourseRotationPrefersLongestNotRowed() {
        // alle Strecken gefahren; Rhein Stein am längsten her
        let sessions = [F.easy(F.ago(9), course: "rhein-stein"), F.easy(F.ago(7), course: "luzern-nationalquai"),
                        F.easy(F.ago(5), course: "rhein-basel"), F.easy(F.ago(4), course: "zuerichsee-mythenquai"),
                        F.easy(F.ago(3), course: "zuerichsee-utoquai")]
        let s = suggest(sessions)
        XCTAssertEqual(s.courseId, "rhein-stein")
        XCTAssertEqual(s.alternatives[1], .free(courseId: "zuerichsee-utoquai"), "frei rudern auf der letzten Strecke")
    }

    func testNeverRowedCourseFirst() {
        let sessions = [F.easy(F.ago(9), course: "rhein-stein"), F.easy(F.ago(7), course: "luzern-nationalquai"),
                        F.easy(F.ago(5), course: "zuerichsee-utoquai")]
        XCTAssertEqual(suggest(sessions).courseId, "rhein-basel")
    }

    func testPreferredCourseWins() {
        let s = suggest([], preferred: "rhein-basel")
        XCTAssertEqual(s.courseId, "rhein-basel")
        XCTAssertEqual(s.option, .plan(planId: "grundlage-locker-30", courseId: "rhein-basel"))
        // unbekannte Strecke wird ignoriert
        XCTAssertEqual(suggest([], preferred: "gibt-es-nicht").courseId, "zuerichsee-utoquai")
    }

    func testAlternativesForHardSuggestion() {
        var sessions = regularEasy(weeks: 2)
        sessions.append(F.hard(F.ago(20), plan: "schwelle-4x6"))
        let s = suggest(sessions)
        XCTAssertEqual(s.level, .hard)
        guard case .plan(let alt, _) = s.alternatives[0] else { return XCTFail("erste Alternative ist ein Programm") }
        XCTAssertEqual(alt, "grundlage-locker-30")
        guard case .free = s.alternatives[1] else { return XCTFail("zweite Alternative ist frei rudern") }
    }

    func testLadderOfferedAfterThreeSameEasySessions() {
        // 3 × dieselbe Grundlage, dazu 2 harte in 7 Tagen → Regel 2, Frequenzleiter als Alternative
        let sessions = [F.easy(F.ago(12), plan: "grundlage-locker-30"), F.easy(F.ago(10), plan: "grundlage-locker-30"),
                        F.easy(F.ago(8), plan: "grundlage-locker-30"), F.hard(F.ago(6)), F.hard(F.ago(3, hour: 9))]
        let s = suggest(sessions)
        XCTAssertEqual(s.rule, .enoughHard)
        XCTAssertEqual(s.alternatives[0], .plan(planId: "frequenzleiter-18-24", courseId: s.courseId))
    }

    func testEmptyCatalogStillSuggests() {
        let s = DailySuggestion.make(sessions: regularEasy(weeks: 2), plans: [], courseIds: [], now: F.now,
                                     calendar: F.cal)
        XCTAssertEqual(s.rule, .stimulus)
        XCTAssertEqual(s.planId, "schwelle-4x6")
        XCTAssertNil(s.courseId)
    }
}
