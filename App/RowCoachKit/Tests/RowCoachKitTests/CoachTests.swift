import Foundation
import XCTest
@testable import RowCoachKit

// MARK: - Testhilfen

/// Kleine Phrasendatei für die Tests: je Szenario drei Varianten je Stil und Sprache (Stufe 1 und 2), dazu eigene
/// Fälle für dynamische Phrasen. Unabhängig von der echten coach_phrases.json.
enum CoachTestPhrases {
    static var json: Data {
        var scenarios: [String: Any] = [:]
        for s in CoachScenario.allCases {
            var levels: [String: Any] = [:]
            for l in [1, 2] {
                var styles: [String: Any] = [:]
                for st in ["calm", "motivating", "cox"] {
                    styles[st] = ["de": (1...3).map { "\(s.rawValue) \(l) \(st) de \($0)" },
                                  "en": (1...3).map { "\(s.rawValue) \(l) \(st) en \($0)" }]
                }
                levels["\(l)"] = styles
            }
            scenarios[s.rawValue] = ["dynamic": false, "levels": levels]
        }
        // dynamisch mit einer statischen Variante
        scenarios["prep_hard"] = ["dynamic": true, "variables": ["duration", "n"], "levels": ["1": [
            "motivating": ["de": ["Gleich Intervall {n}: {duration}.", "Gleich geht's los.", "Intervall {n} kommt."],
                           "en": ["Interval {n} coming: {duration}.", "Here we go soon."]]]]]
        // nur dynamisch (ohne Werte keine Phrase)
        scenarios["rate_low"] = ["dynamic": true, "variables": ["spm"], "levels": ["1": [
            "motivating": ["de": ["Schlagzahl {spm}, hoch!"], "en": ["Rate {spm}, up!"]]]]]
        return try! JSONSerialization.data(withJSONObject: ["version": 1, "scenarios": scenarios])
    }

    static var bank: CoachPhraseBank { try! CoachPhraseBank(data: json) }
}

/// Erzeugt synthetische Fahrten: Messpunkte je Sekunde nach einem Verhalten, das Phase und Zeit in der Phase kennt.
enum RideSim {
    struct Moment {
        var t: Double
        var phaseIndex: Int
        var phase: WorkoutPhase
        /// Sekunden seit Beginn der Phase (Uhrzeit)
        var phaseT: Double
        var finished: Bool
    }

    struct Row {
        var spm: Int
        var pace: Double
        var hr: Int?
        static let stop = Row(spm: 0, pace: 0, hr: nil)
    }

    /// Ziel der Phase mitten im Bereich (ohne Ziel: Schätzung der Phase)
    static func onTarget(_ p: WorkoutPhase, best2k: Double = 480) -> Row {
        let spm = p.spmRange.map { ($0.lowerBound + $0.upperBound) / 2 } ?? (p.kind == .work ? 26 : 20)
        return Row(spm: spm, pace: p.estimatedPace(best2k: best2k), hr: nil)
    }

    static func samples(plan: WorkoutPlan, best2k: Double = 480, limit: Double = 4 * 3600,
                        behaviour: (Moment) -> Row) -> [WorkoutSample] {
        var engine = PlanEngine(plan: plan, best2k: best2k)
        var out: [WorkoutSample] = []
        var t = 0.0, distance = 0.0, active = 0.0
        var phaseIndex = -1, phaseStart = 0.0
        var status = engine.status
        while t < limit {
            if status.phaseIndex != phaseIndex { phaseIndex = status.phaseIndex; phaseStart = t }
            let phase = plan.phases[status.phaseIndex]
            let row = behaviour(Moment(t: t, phaseIndex: status.phaseIndex, phase: phase, phaseT: t - phaseStart,
                                       finished: status.finished))
            if status.finished { break }
            // Messpunkt nach der Sekunde (wie der PM5: Werte beschreiben die vergangene Sekunde)
            t += 1
            if row.spm > 0, row.pace > 0 {
                distance += 500 / row.pace
                active += 1
            }
            status = engine.update(activeTime: active, elapsedTime: t, distance: distance,
                                   speed: row.spm > 0 && row.pace > 0 ? 500 / row.pace : 0)
            out.append(WorkoutSample(time: t, distance: distance, pace: row.spm > 0 ? row.pace : 0,
                                     strokeRate: row.spm, power: 0, heartRate: row.hr))
        }
        return out
    }
}

enum CoachPlans {
    /// Einrudern 5 min, 4 × 4 min hart (Schlagzahl 26–28, Zone 4, Tempo 2k+0…4) mit 2 min Pause, Ausrudern 5 min
    static var intervals: WorkoutPlan {
        var phases = [WorkoutPhase(kind: .warmup, durationS: 300, spmMin: 18, spmMax: 20, hrZone: 2)]
        for i in 0..<4 {
            phases.append(WorkoutPhase(kind: .work, durationS: 240, spmMin: 26, spmMax: 28, hrZone: 4,
                                       paceOffsetMinS: 0, paceOffsetMaxS: 4))
            if i < 3 { phases.append(WorkoutPhase(kind: .rest, durationS: 120, activeRest: false)) }
        }
        phases.append(WorkoutPhase(kind: .cooldown, durationS: 300, spmMin: 18, spmMax: 20, hrZone: 1))
        return WorkoutPlan(id: "test-4x4", name: "4 × 4 min", phases: phases)
    }

    /// 60 min Grundlage (Schlagzahl 18–20, Zone 2, Tempo 2k+20…25)
    static var steadyState: WorkoutPlan {
        WorkoutPlan(id: "test-grundlage", name: "Grundlage 60", phases: [
            WorkoutPhase(kind: .work, durationS: 3600, spmMin: 18, spmMax: 20, hrZone: 2,
                         paceOffsetMinS: 20, paceOffsetMaxS: 25),
        ])
    }

    /// 3 × 1000 m hart mit 3 min Pause
    static var distanceIntervals: WorkoutPlan {
        var phases: [WorkoutPhase] = []
        for i in 0..<3 {
            phases.append(WorkoutPhase(kind: .work, distanceM: 1000, spmMin: 28, spmMax: 30, hrZone: 5,
                                       paceOffsetMinS: 0, paceOffsetMaxS: 3))
            if i < 2 { phases.append(WorkoutPhase(kind: .rest, durationS: 180, activeRest: true)) }
        }
        return WorkoutPlan(id: "test-3x1000", name: "3 × 1000 m", phases: phases)
    }
}

// MARK: - Engine

final class CoachEngineTests: XCTestCase {
    private let bank = CoachTestPhrases.bank

    private func replay(_ plan: WorkoutPlan, settings: CoachSettings = CoachSettings(),
                        config: CoachConfig = CoachConfig(), zones: HeartRateZones? = nil, seed: UInt64 = 7,
                        behaviour: (RideSim.Moment) -> RideSim.Row) -> CoachReplay.Result {
        let samples = RideSim.samples(plan: plan, behaviour: behaviour)
        return CoachReplay.run(samples: samples, plan: plan, settings: settings, config: config, phrases: bank,
                               zones: zones, seed: seed)
    }

    private func entries(_ r: CoachReplay.Result, _ s: CoachScenario) -> [CoachReplay.Entry] {
        r.entries.filter { $0.utterance.scenario == s }
    }

    /// Kurzes Abflachen im letzten Viertel von Intervall 2 (12 s) → fade_end genau einmal, Stufe 1
    func testFadeEndShortDipOnce() {
        let plan = CoachPlans.intervals
        let r = replay(plan) { m in
            var row = RideSim.onTarget(m.phase)
            if m.phaseIndex == 3, (195..<207).contains(m.phaseT) { row.spm -= 4; row.pace += 4 }
            return row
        }
        let fades = entries(r, .fadeEnd)
        XCTAssertEqual(fades.count, 1, r.log)
        XCTAssertEqual(fades.first?.utterance.level, 1)
        XCTAssertEqual(fades.first?.phaseIndex, 3)
        XCTAssertTrue(entries(r, .fadeMid).isEmpty, r.log)
    }

    /// Anhaltendes Abflachen ab 3 min → Stufe 1, dann Stufe 2, je genau einmal
    func testFadeEndPersistentEscalatesOnce() {
        let plan = CoachPlans.intervals
        let r = replay(plan) { m in
            var row = RideSim.onTarget(m.phase)
            if m.phaseIndex == 3, m.phaseT >= 170 { row.spm -= 4; row.pace += 5 }
            return row
        }
        let fades = entries(r, .fadeEnd).filter { $0.phaseIndex == 3 }
        XCTAssertEqual(fades.map(\.utterance.level), [1, 2], r.log)
        if fades.count == 2 {
            XCTAssertGreaterThanOrEqual(fades[1].utterance.time - fades[0].utterance.time, CoachConfig().escalationDelay)
        }
        XCTAssertEqual(entries(r, .fadeEnd).count, 2)
    }

    /// Gleichmässig im Ziel → keine Korrektur, kein Abflachen, aber gelegentlich Lob
    func testStableRowingNoCorrectionsSomePraise() {
        let r = replay(CoachPlans.intervals) { RideSim.onTarget($0.phase) }
        let corrections = r.entries.filter {
            [.correction, .safety].contains($0.utterance.category) || $0.utterance.scenario == .fadeEnd
        }
        XCTAssertTrue(corrections.isEmpty, r.log)
        XCTAssertGreaterThanOrEqual(entries(r, .paceOnTarget).count, 1, r.log)
        // Struktur: go/last_interval an jedem Intervallstart, workout_done am Ende
        XCTAssertEqual(entries(r, .go).count, 3, r.log)
        XCTAssertEqual(entries(r, .lastInterval).count, 1)
        XCTAssertEqual(entries(r, .workoutDone).count, 1)
        XCTAssertFalse(r.entries.contains { if case .phaseStarted(let p, _)? = $0.utterance.cue { return p.kind == .work }; return false })
        XCTAssertFalse(r.entries.contains { $0.utterance.cue == .finished })
    }

    /// Unruhiges Rudern: Mindestabstand, Budget und Ruhezone vor dem Wechsel werden eingehalten
    func testMinGapBudgetQuietZone() {
        for freq in CoachFrequency.allCases {
            var rng = SeededRandom(seed: 99)
            let r = replay(CoachPlans.intervals, settings: CoachSettings(frequency: freq)) { m in
                var row = RideSim.onTarget(m.phase)
                if m.phase.kind == .rest { return Int(m.phaseT) % 40 < 20 ? .stop : RideSim.Row(spm: 28, pace: 118) }
                let block = Int(m.t / 25)
                var g = SeededRandom(seed: UInt64(block) &* 31 &+ rng.next() % 1)
                row.spm += Int(g.next() % 9) - 4
                row.pace += Double(Int(g.next() % 13) - 4)
                return row
            }
            let cfg = CoachConfig()
            let coach = r.entries.filter { !$0.utterance.isInfo && $0.utterance.category != .phase }
            XCTAssertGreaterThan(coach.count, 5, r.log)
            // Mindestabstand zur vorigen Ansage (welcher Art auch immer)
            for e in coach {
                let before = r.entries.filter { $0.utterance.time < e.utterance.time }.last
                if let b = before {
                    XCTAssertGreaterThanOrEqual(e.utterance.time - b.utterance.time, cfg.minGap,
                                                "\(freq): \(e.utterance.scenario!.rawValue)\n\(r.log)")
                }
                // keine Motivation in den letzten 4 s vor einem Wechsel
                if let s = e.secondsToChange { XCTAssertGreaterThan(s, cfg.quietBeforeChange) }
            }
            // Budget je 60 s
            let budgeted = coach.filter { !$0.utterance.scenario!.budgetExempt }.map(\.utterance.time)
            let limit = cfg.budgetPerMinute[freq]!
            for t in budgeted {
                XCTAssertLessThanOrEqual(budgeted.filter { $0 > t - 60 && $0 <= t }.count, limit, "\(freq)\n\(r.log)")
            }
        }
    }

    /// Letzte Minute harter Intervalle (mit Abflachen und unruhigen Werten): höchstens `endPushPerMinute` Coach-Ansagen
    /// je Phase; `fade_end` Stufe 2 nie bei weniger als 15 s Rest; `workout_final` und `last_30s` nicht im selben
    /// 60-s-Fenster
    func testLastMinuteOfHardIntervalsWithinEndPushBudget() {
        let cfg = CoachConfig()
        for freq in CoachFrequency.allCases {
            for plan in [CoachPlans.intervals, CoachPlans.distanceIntervals] {
                let r = replay(plan, settings: CoachSettings(frequency: freq)) { m in
                    var row = RideSim.onTarget(m.phase)
                    if m.phase.kind == .work, m.phaseT > 150 {
                        row.spm -= 3 + Int(m.phaseT) % 3
                        row.pace += 4 + Double(Int(m.phaseT) % 4)
                    }
                    return row
                }
                var perPhase: [Int: Int] = [:]
                for e in r.entries where !e.utterance.isInfo && e.phaseKind == .work && e.phaseIntensity == .hard {
                    guard let s = e.secondsToChange, s <= 60 else { continue }
                    perPhase[e.phaseIndex!, default: 0] += 1
                }
                XCTAssertFalse(perPhase.isEmpty)
                for (_, n) in perPhase {
                    XCTAssertLessThanOrEqual(n, cfg.endPushPerMinute[freq]!, "\(freq)\n\(r.log)")
                }
                for e in entries(r, .fadeEnd) where e.utterance.level == 2 {
                    XCTAssertGreaterThanOrEqual(e.secondsToChange ?? 99, cfg.fadeEndLevel2MinRemaining, r.log)
                }
                for f in entries(r, .workoutFinal) {
                    for l in entries(r, .last30s) {
                        XCTAssertGreaterThanOrEqual(abs(f.utterance.time - l.utterance.time), 60, r.log)
                    }
                }
            }
        }
    }

    /// fade_end kurz vor last_30s ersetzt last_30s in dieser Phase
    func testFadeEndReplacesLast30s() {
        let r = replay(CoachPlans.intervals) { m in
            var row = RideSim.onTarget(m.phase)
            if m.phaseIndex == 3, m.phaseT >= 190 { row.spm -= 4; row.pace += 5 }
            return row
        }
        let fades = entries(r, .fadeEnd).filter { $0.phaseIndex == 3 }
        XCTAssertFalse(fades.isEmpty, r.log)
        if let f = fades.first, let s = f.secondsToChange, s - 30 < CoachConfig().fadeReplacesLast30Within, s >= 30 {
            XCTAssertTrue(entries(r, .last30s).filter { $0.phaseIndex == 3 }.isEmpty, r.log)
        }
    }

    /// Ruhezone auch bei stabilem Rudern und Distanzintervallen
    func testNoCoachingInLastFourSeconds() {
        for plan in [CoachPlans.intervals, CoachPlans.distanceIntervals] {
            let r = replay(plan) { RideSim.onTarget($0.phase) }
            for e in r.entries where !e.utterance.isInfo && e.utterance.category != .phase {
                if let s = e.secondsToChange { XCTAssertGreaterThan(s, 4, "\(e.utterance.scenario!)\n\(r.log)") }
            }
        }
    }

    /// 60 min Grundlage → höchstens etwa eine Coach-Ansage je 3 min
    func testSteadyState60MinutesIsQuiet() {
        let zones = HeartRateZones(maxHR: 185, restHR: 55)
        let r = replay(CoachPlans.steadyState, zones: zones) { m in
            var row = RideSim.onTarget(m.phase)
            row.spm += Int(m.t / 30) % 3 - 1     // leichte Schwankung im Ziel
            row.hr = 140                          // Zone 2
            return row
        }
        let motivation = r.entries.filter { !$0.utterance.isInfo && $0.utterance.category != .phase }
        XCTAssertGreaterThan(motivation.count, 3, r.log)
        XCTAssertLessThanOrEqual(motivation.count, 21, r.log)
        let budgeted = motivation.filter { !$0.utterance.scenario!.budgetExempt }
        for (a, b) in zip(budgeted, budgeted.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b.utterance.time - a.utterance.time, 180 - 1e-9, r.log)
        }
        XCTAssertGreaterThanOrEqual(entries(r, .technique).count, 1)
    }

    /// Stehen geblieben: in der Belastung ja (Stufe 2 bei anhaltendem Stillstand), in der Pause nie
    func testStoppedInWorkNotInRest() {
        let r = replay(CoachPlans.intervals) { m in
            if m.phase.kind == .rest { return .stop }
            if m.phaseIndex == 3, (100..<125).contains(m.phaseT) { return .stop }
            return RideSim.onTarget(m.phase)
        }
        let stops = entries(r, .stopped)
        XCTAssertEqual(stops.map(\.utterance.level), [1, 2], r.log)
        XCTAssertTrue(stops.allSatisfy { $0.phaseKind == .work })
    }

    /// Intervallvergleich: 2 wie 1 → consistent, 3 langsamer → slower_than_prev, 4 schnellstes → best_interval
    func testIntervalComparison() {
        let paces: [Int: Double] = [1: 122, 3: 122.5, 5: 126.5, 7: 118.5]
        let r = replay(CoachPlans.intervals) { m in
            var row = RideSim.onTarget(m.phase)
            if let p = paces[m.phaseIndex] { row.pace = p }
            return row
        }
        XCTAssertEqual(entries(r, .consistent).map(\.phaseIndex), [4], r.log)
        XCTAssertEqual(entries(r, .slowerThanPrev).map(\.phaseIndex), [6], r.log)
        // das letzte Intervall endet mit dem Training (Ausrudern folgt): Vergleich im Ausrudern
        XCTAssertEqual(entries(r, .bestInterval).map(\.phaseIndex), [8], r.log)
        XCTAssertEqual(entries(r, .intervalDone).map(\.phaseIndex), [2], r.log)
    }

    /// Schneller als das vorige Intervall (ohne Bestwert) → interval_done Stufe 2
    func testFasterThanPreviousIsIntervalDoneLevel2() {
        let paces: [Int: Double] = [1: 124, 3: 121]
        let r = replay(CoachPlans.intervals) { m in
            var row = RideSim.onTarget(m.phase)
            if let p = paces[m.phaseIndex] { row.pace = p }
            return row
        }
        let done = entries(r, .intervalDone).filter { $0.phaseIndex == 4 }
        XCTAssertEqual(done.map(\.utterance.level), [2], r.log)
    }

    /// Stil „aus“: nur die bisherigen Info-Ansagen, genau wie CoachCueDetector
    func testStyleOffGivesOnlyInfo() {
        let plan = CoachPlans.intervals
        let samples = RideSim.samples(plan: plan) { RideSim.onTarget($0.phase) }
        let r = CoachReplay.run(samples: samples, plan: plan, settings: CoachSettings(style: .off), phrases: bank)
        XCTAssertTrue(r.entries.allSatisfy(\.utterance.isInfo))
        var detector = CoachCueDetector()
        var pe = PlanEngine(plan: plan)
        var expected = 0
        var active = 0.0
        for s in samples {
            if s.strokeRate > 0, s.time > 0 { active += 1 }
            expected += detector.update(status: pe.update(activeTime: active, elapsedTime: s.time, distance: s.distance,
                                                          speed: s.pace > 0 ? 500 / s.pace : 0)).count
        }
        XCTAssertEqual(r.entries.count, expected)
    }

    /// Ohne Phrasendatei bleibt alles wie bisher (nur Info)
    func testWithoutPhrasesOnlyInfo() {
        let plan = CoachPlans.intervals
        let samples = RideSim.samples(plan: plan) { RideSim.onTarget($0.phase) }
        let r = CoachReplay.run(samples: samples, plan: plan, phrases: nil)
        XCTAssertFalse(r.entries.isEmpty)
        XCTAssertTrue(r.entries.allSatisfy(\.utterance.isInfo))
    }

    /// Vorbereitung vor harten Intervallen (dynamisch mit Werten), Countdown bleibt Info, last_10s ersetzt den
    /// Countdown am Ende der harten Intervalle
    func testPrepAndCountdown() {
        let r = replay(CoachPlans.intervals) { RideSim.onTarget($0.phase) }
        let preps = entries(r, .prepHard)
        XCTAssertEqual(preps.count, 4, r.log)
        XCTAssertTrue(preps.allSatisfy { $0.utterance.isDynamic && $0.utterance.text.contains("Intervall") }, r.log)
        XCTAssertTrue(preps.contains { $0.utterance.text.contains("4 Minuten") }, r.log)
        // am Ende jedes harten Intervalls entweder last_10s oder (Budget erschöpft) der Countdown
        let countdowns = r.entries.filter { if case .countdown? = $0.utterance.cue { return true }; return false }
        let workCountdowns = countdowns.filter { $0.phaseKind == .work }
        XCTAssertEqual(entries(r, .last10s).count + workCountdowns.count, 4, r.log)
        XCTAssertGreaterThanOrEqual(entries(r, .last10s).count, 1, r.log)
        // dazu Countdown vor jedem Intervall (aus Einrudern und Pausen) und vor dem Ende des Ausruderns
        XCTAssertEqual(countdowns.count - workCountdowns.count, 5, r.log)
    }

    /// Distanzintervalle: last_250m und last_100m in jeder harten Distanzphase
    func testDistanceIntervalMarks() {
        let r = replay(CoachPlans.distanceIntervals) { RideSim.onTarget($0.phase) }
        XCTAssertEqual(entries(r, .last250m).count, 3, r.log)
        XCTAssertEqual(entries(r, .last100m).count, 3, r.log)
    }

    /// Freies Rudern: Halbzeit und „Noch 500 Meter“ als Coach-Phrasen, Tempo-Linie
    func testFreeRowing() {
        var samples: [WorkoutSample] = []
        var d = 0.0
        for t in 0..<700 {
            samples.append(WorkoutSample(time: Double(t), distance: d, pace: 120, strokeRate: 24, power: 0, heartRate: nil))
            d += 500 / 120
        }
        let r = CoachReplay.run(samples: samples, plan: nil, courseLength: 2000, paceLine: 125, phrases: bank)
        XCTAssertEqual(r.countByScenario["free_half"], 1, r.log)
        XCTAssertEqual(r.countByScenario["free_500_left"], 1, r.log)
        XCTAssertGreaterThanOrEqual(r.countByScenario["paceline_ahead"] ?? 0, 1, r.log)
        XCTAssertNil(r.countByScenario["info"], r.log)
    }

    /// Wiedergabe-Werkzeug: Ansagen je Minute einer (synthetischen) gespeicherten Fahrt; mit
    /// `ROWCOACH_REPLAY=<WorkoutRecord.json>` (optional `ROWCOACH_PLAN=<id aus plans.json>`,
    /// `ROWCOACH_STYLE`, `ROWCOACH_FREQUENCY`) wird eine echte Fahrt wiedergegeben und protokolliert.
    func testReplayCountsPerMinute() throws {
        let env = ProcessInfo.processInfo.environment
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let realPhrases = (try? Data(contentsOf: root.appendingPathComponent("RowCoach/Resources/coach_phrases.json")))
            .flatMap { try? CoachPhraseBank(data: $0) }
        let phrases = realPhrases ?? bank
        let settings = CoachSettings(style: env["ROWCOACH_STYLE"].flatMap(CoachStyle.init(rawValue:)) ?? .motivating,
                                     frequency: env["ROWCOACH_FREQUENCY"].flatMap(CoachFrequency.init(rawValue:)) ?? .normal)
        let samples: [WorkoutSample]
        var plan: WorkoutPlan? = CoachPlans.intervals
        if let path = env["ROWCOACH_REPLAY"] {
            let record = try WorkoutRecord(jsonData: Data(contentsOf: URL(fileURLWithPath: path)))
            samples = record.samples
            let id = env["ROWCOACH_PLAN"] ?? record.header.workoutPlanId
            let plans = (try? WorkoutPlanCatalog.load(url: root.appendingPathComponent("RowCoach/Resources/plans.json"))) ?? []
            plan = id.flatMap { id in plans.first { $0.id == id } }
        } else {
            // Probe wie eine gespeicherte Fahrt: JSON hin und zurück
            let synthetic = RideSim.samples(plan: CoachPlans.intervals) { m in
                var row = RideSim.onTarget(m.phase)
                if m.phase.kind == .work, m.phaseT > 180 { row.spm -= 3; row.pace += 3 }
                return row
            }
            samples = try JSONDecoder().decode([WorkoutSample].self, from: JSONEncoder().encode(synthetic))
        }
        let r = CoachReplay.run(samples: samples, plan: plan, courseLength: plan == nil ? 2000 : nil,
                                settings: settings, phrases: phrases,
                                zones: HeartRateZones(maxHR: 185, restHR: 55))
        let perMinute = r.perMinute()
        XCTAssertEqual(perMinute.reduce(0, +), r.entries.filter { !$0.utterance.isInfo }.count)
        XCTAssertLessThanOrEqual(perMinute.max() ?? 0, 5)
        print("Coach-Wiedergabe (\(realPhrases == nil ? "Test-Phrasen" : "coach_phrases.json")), Ansagen je Minute: \(perMinute)")
        print("je Szenario: \(r.countByScenario.sorted { $0.key < $1.key })")
        if env["ROWCOACH_REPLAY"] != nil || env["ROWCOACH_REPLAY_LOG"] != nil { print(r.log) }
    }
}

// MARK: - Phrasen

final class CoachPhraseTests: XCTestCase {
    func testNoDirectRepetitionAndHistory() {
        var picker = CoachPhrasePicker(bank: CoachTestPhrases.bank, seed: 42, historySize: 2)
        var last: [String] = []
        for _ in 0..<300 {
            let p = picker.pick(.go, style: .cox, language: "de")!
            XCTAssertFalse(last.suffix(2).contains(p.phraseId), "\(p.phraseId) nach \(last.suffix(2))")
            last.append(p.phraseId)
        }
        XCTAssertEqual(Set(last).count, 3)
    }

    func testSeededSelectionIsReproducible() {
        var a = CoachPhrasePicker(bank: CoachTestPhrases.bank, seed: 5)
        var b = CoachPhrasePicker(bank: CoachTestPhrases.bank, seed: 5)
        for _ in 0..<20 { XCTAssertEqual(a.pick(.technique, style: .calm, language: "en"), b.pick(.technique, style: .calm, language: "en")) }
    }

    func testDynamicFallsBackToStatic() {
        var picker = CoachPhrasePicker(bank: CoachTestPhrases.bank, seed: 1)
        for _ in 0..<10 {
            let p = picker.pick(.prepHard, style: .motivating, language: "de")!
            XCTAssertEqual(p.text, "Gleich geht's los.")
            XCTAssertEqual(p.phraseId, "prep_hard.1.motivating.1")
            XCTAssertFalse(p.isDynamic)
        }
        let d = picker.pick(.prepHard, style: .motivating, language: "de", values: ["n": "2", "duration": "4 Minuten"])!
        XCTAssertTrue(d.isDynamic)
        XCTAssertFalse(d.text.contains("{"))
        XCTAssertTrue(["Gleich Intervall 2: 4 Minuten.", "Intervall 2 kommt."].contains(d.text), d.text)
        // nur dynamisch und ohne Werte → keine Phrase
        XCTAssertNil(picker.pick(.rateLow, style: .motivating, language: "de"))
        XCTAssertEqual(picker.pick(.rateLow, style: .motivating, language: "de", values: ["spm": "22"])?.text,
                       "Schlagzahl 22, hoch!")
    }

    func testStyleAndLevelFallback() {
        var picker = CoachPhrasePicker(bank: CoachTestPhrases.bank, seed: 1)
        // prep_hard hat nur motivating
        XCTAssertTrue(picker.pick(.prepHard, style: .cox, language: "en")!.phraseId.hasPrefix("prep_hard.1.motivating."))
        // Stufe 3 gibt es nicht → Stufe 2
        XCTAssertEqual(picker.pick(.fadeEnd, level: 3, style: .cox, language: "de")?.level, 2)
        XCTAssertNil(picker.pick(.go, style: .off, language: "de"))
    }

    func testPhraseIdIsZeroBasedPosition() {
        let bank = CoachTestPhrases.bank
        var picker = CoachPhrasePicker(bank: bank, seed: 3)
        for _ in 0..<10 {
            let p = picker.pick(.strongFinish, level: 1, style: .calm, language: "en")!
            let idx = Int(p.phraseId.split(separator: ".").last!)!
            XCTAssertEqual(p.text, "strong_finish 1 calm en \(idx + 1)")
        }
    }

    /// Die echte Phrasendatei (wenn vorhanden): lesbar, nur bekannte Szenarien und Variablen
    func testBundledPhraseFileIsValid() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("RowCoach/Resources/coach_phrases.json")
        guard let data = try? Data(contentsOf: url) else { throw XCTSkip("coach_phrases.json fehlt noch") }
        let bank = try CoachPhraseBank(data: data)
        let known = Set(CoachScenario.allCases.map(\.rawValue))
        let vars: Set<String> = ["n", "of", "duration", "distance", "spm", "spm_min", "spm_max", "split", "delta"]
        XCTAssertEqual(Set(bank.scenarios.keys).subtracting(known), [])
        XCTAssertEqual(known.subtracting(bank.scenarios.keys), [])
        for (id, s) in bank.scenarios {
            for (_, styles) in s.levels {
                for (_, langs) in styles {
                    for (_, list) in langs {
                        for text in list {
                            XCTAssertEqual(Set(CoachPhraseBank.placeholders(text)).subtracting(vars), [], "\(id): \(text)")
                        }
                    }
                }
            }
            // jede Kombination liefert eine Phrase, auch ohne Werte (statische Variante vorhanden)
            var picker = CoachPhrasePicker(bank: bank, seed: 1)
            for style in [CoachStyle.calm, .motivating, .cox] {
                for lang in ["de", "en"] {
                    XCTAssertNotNil(picker.pick(CoachScenario(rawValue: id)!, style: style, language: lang), "\(id) \(style) \(lang)")
                }
            }
        }
    }

    /// `last_10s` ersetzt den Countdown nur, wenn jede Variante die Restzeit nennt
    func testLast10sVariantsNameTheTime() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("RowCoach/Resources/coach_phrases.json")
        guard let data = try? Data(contentsOf: url) else { throw XCTSkip("coach_phrases.json fehlt noch") }
        guard CoachConfig().last10ReplacesCountdown else { return }
        let bank = try CoachPhraseBank(data: data)
        for (_, styles) in bank.scenarios["last_10s"]?.levels ?? [:] {
            for (style, langs) in styles {
                for (lang, list) in langs {
                    for text in list {
                        let lower = text.lowercased()
                        XCTAssertTrue(lower.contains("zehn") || lower.contains("ten"), "\(style) \(lang): \(text)")
                    }
                }
            }
        }
    }

    /// Ganze Fahrt mit der echten Phrasendatei: keine offenen Platzhalter im gesprochenen Text
    func testRealPhrasesInReplayHaveNoOpenPlaceholders() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("RowCoach/Resources/coach_phrases.json")
        guard let data = try? Data(contentsOf: url) else { throw XCTSkip("coach_phrases.json fehlt noch") }
        let bank = try CoachPhraseBank(data: data)
        for lang in ["de", "en"] {
            for style in [CoachStyle.calm, .motivating, .cox] {
                let plan = CoachPlans.intervals
                let samples = RideSim.samples(plan: plan) { m in
                    var row = RideSim.onTarget(m.phase)
                    if m.phase.kind == .work, m.phaseT > 170 { row.spm -= 4; row.pace += 4 }
                    return row
                }
                let r = CoachReplay.run(samples: samples, plan: plan, settings: CoachSettings(style: style, language: lang),
                                        phrases: bank)
                XCTAssertGreaterThan(r.entries.filter { !$0.utterance.isInfo }.count, 10)
                for e in r.entries where !e.utterance.isInfo {
                    XCTAssertFalse(e.utterance.text.contains("{"), e.utterance.text)
                    XCTAssertFalse(e.utterance.text.isEmpty)
                }
            }
        }
    }
}

// MARK: - Gesprochene Werte

final class CoachSpokenTests: XCTestCase {
    func testDurations() {
        XCTAssertEqual(CoachSpoken.duration(240, language: "de"), "4 Minuten")
        XCTAssertEqual(CoachSpoken.duration(60, language: "de"), "1 Minute")
        XCTAssertEqual(CoachSpoken.duration(90, language: "de"), "1 Minute 30")
        XCTAssertEqual(CoachSpoken.duration(30, language: "en"), "30 seconds")
        XCTAssertEqual(CoachSpoken.duration(1, language: "en"), "1 second")
        XCTAssertEqual(CoachSpoken.duration(150, language: "en"), "2 minutes 30")
    }

    func testOtherValues() {
        XCTAssertEqual(CoachSpoken.distance(500, language: "de"), "500 Meter")
        XCTAssertEqual(CoachSpoken.distance(500, language: "en"), "500 meters")
        XCTAssertEqual(CoachSpoken.split(125.4, language: "de"), "2 Minuten 5")
        XCTAssertEqual(CoachSpoken.split(120, language: "en"), "2 minutes")
        XCTAssertEqual(CoachSpoken.delta(-3.2, language: "de"), "3 Sekunden")
        XCTAssertEqual(CoachSpoken.delta(0.2, language: "en"), "1 second")
    }
}
