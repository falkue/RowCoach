import Foundation

/// Adaptiver Sprachcoach (docs/coach/SPEC.md): Regeln erzeugen je Tick Kandidaten, der Planer wählt höchstens
/// eine Coach-Ansage (Mindestabstand, Abklingzeit, Hysterese, Eskalation, Ruhezonen, Budget, Priorität).
///
/// Die Informationsansagen von `CoachCueDetector` (Phasenwechsel, Countdown, Halbzeit, Ziel) laufen durch dieselbe
/// Engine: Sie kommen immer sofort (Info hat Vorrang; die Coach-Ansagen weichen aus). Wo es ein passendes Szenario
/// gibt, ersetzt die Coach-Phrase die Info-Ansage, damit nichts doppelt gesagt wird: Start einer Belastung → `go`
/// bzw. `last_interval`, Halbzeit → `workout_half`/`free_half`, „Noch 500 Meter“ → `free_500_left`, Ziel →
/// `workout_done`, Countdown am Ende einer harten Phase vor Pause/Ausrudern/Ende → `last_10s`. Fehlt die Phrase,
/// bleibt die Info-Ansage. Mit Stil `off` (oder ohne Phrasendatei) bleibt nur die Information wie vor dem Coach.
/// Schwellentest: Werte für die Live-Ansagen (Schwelle für „zu schnell“, Exponent und Rampenfaktor für das
/// Ergebnis am Ende des Testteils)
public struct CoachTestContext: Equatable, Sendable {
    public var thresholdW: Double
    public var exponentB: Double
    public var rampFactor: Double

    public init(thresholdW: Double, exponentB: Double = ThresholdProfile.defaultExponent,
                rampFactor: Double = ThresholdProfile.defaultRampFactor) {
        self.thresholdW = thresholdW
        self.exponentB = exponentB
        self.rampFactor = rampFactor
    }
}

public struct CoachEngine: Sendable {
    public let plan: WorkoutPlan?
    public let settings: CoachSettings
    public let config: CoachConfig
    public let best2k: Double
    public let zones: HeartRateZones?
    public private(set) var state: CoachState

    private var picker: CoachPhrasePicker?
    private var rng: SeededRandom
    private var detector = CoachCueDetector()

    // Planer
    private var lastAnyTime = -Double.infinity
    private var speakingUntil = -Double.infinity
    private var budgetTimes: [Double] = []
    /// Ansagen in der Gruppe „Ende harter Phase“ (Budget `endPushPerMinute`)
    private var endPushTimes: [Double] = []
    /// Gruppe der letzten Ansage (zwei Korrekturen nie direkt hintereinander)
    private var lastCategory: CoachCategory?
    private var lastBudgetTime = -Double.infinity
    private var lastByScenario: [CoachScenario: Double] = [:]
    /// einmalige Ansagen: "<szenario>#<phase>"
    private var done: Set<String> = []
    // je Phase
    private var phaseIndex: Int?
    private var spokenInPhase: [CoachScenario: Int] = [:]
    private var holds: [CoachScenario: Double] = [:]
    private var nextTechnique: Double?
    private var countdownDone = false
    /// Belastungsphase gerade beendet: Index (für `interval_done` und Vergleiche in der folgenden Phase)
    private var pendingInterval: Int?
    private var started = false
    private var freeStart: Double?
    // Schwellentests (docs/schwelle/SPEC.md 10)
    public let testContext: CoachTestContext?
    /// Leistung der letzten 70 s (für 10-s-, 30-s- und 60-s-Mittel)
    private var powerLog: [(t: Double, p: Double)] = []
    private var phasePowerSum = 0.0
    private var phasePowerTime = 0.0
    private var lastPowerTime: Double?
    /// beste gleitende 60-s-Leistung über alle Rampenphasen
    private var rampBest60 = 0.0
    private var pendingTestEnd: TestEnd?

    /// Ende eines Testteils (für `test_ramp_end`, `test_hr_reached`, `test_result`)
    private struct TestEnd {
        var role: String
        /// folgende Phasen derselben Rolle übersprungen (Stufentest vorzeitig beendet)
        var skipped: Bool
        var meanPower: Double?
        var duration: Double
        var last30: Double?
        var best60: Double?
        var at: Double
    }

    public init(plan: WorkoutPlan?, settings: CoachSettings, config: CoachConfig = CoachConfig(),
                phrases: CoachPhraseBank?, best2k: Double = PaceTargets.defaultBest2k, zones: HeartRateZones? = nil,
                seed: UInt64 = 1, test: CoachTestContext? = nil) {
        self.plan = plan
        testContext = test
        self.settings = settings
        self.config = config
        self.best2k = best2k
        self.zones = zones
        state = CoachState(config: config)
        picker = phrases.map { CoachPhrasePicker(bank: $0, seed: seed, historySize: config.phraseHistory) }
        rng = SeededRandom(seed: seed ^ 0x5EED)
    }

    private var coachOn: Bool { settings.style != .off && picker != nil }

    // MARK: Tick

    /// Neuer Stand. Liefert die jetzt zu sprechenden Ansagen (meist keine, höchstens eine Coach-Phrase;
    /// Info-Ansagen können zu zweit kommen, z. B. Phasenstart und Countdown einer sehr kurzen Phase).
    public mutating func update(_ input: CoachInput) -> [CoachUtterance] {
        let t = input.time
        state.ingest(input)
        if let st = input.status { handlePhase(st, t: t) } else if !started { started = true; state.beginPhase(at: t) }
        logPower(input)
        if input.free != nil, freeStart == nil { freeStart = t }

        // 1. Information (sofort, ggf. als Coach-Phrase)
        var out: [CoachUtterance] = []
        var cues: [CoachCue] = []
        if let st = input.status {
            cues = detector.update(status: st)
        } else if let f = input.free {
            cues = detector.update(distance: f.distance, total: f.total)
        }
        for cue in cues {
            if case .countdown = cue { countdownDone = true }
            if let u = utterance(for: cue, input: input) { out.append(u) }
        }
        // 2. Regeln (Hysterese läuft jeden Tick weiter, auch wenn nichts gesagt wird)
        let candidates = coachOn ? rules(input) : []
        if !out.isEmpty { return out }
        guard coachOn else { return [] }
        let endZone = input.status.map(hardEndZone) ?? false
        for c in candidates.sorted(by: { $0.scenario.category.priority > $1.scenario.category.priority })
            where allowed(c, input: input) {
            for s in [c.scenario] + c.fallbacks {
                if let p = picker?.pick(s, level: c.level, style: settings.style, language: settings.language,
                                        values: c.values, preferMaxWords: endZone ? config.endZoneMaxWords : nil) {
                    let u = CoachUtterance(text: p.text, phraseId: p.phraseId, scenario: s, cue: nil, level: p.level,
                                           isDynamic: p.isDynamic, priority: s.category.priority,
                                           interrupting: false, time: t)
                    record(u, key: c.scenario, onceKey: c.onceKey, budgeted: !c.scenario.budgetExempt,
                           endPush: c.scenario.isEndPush || (endZone && c.scenario != .stopped), t: t)
                    if c.resetHold { holds[c.scenario] = nil }
                    return [u]
                }
            }
        }
        return []
    }

    // MARK: Phasen

    private mutating func handlePhase(_ st: PlanStatus, t: Double) {
        guard phaseIndex != st.phaseIndex || !started else { return }
        started = true
        noteTestPhaseEnd(newIndex: st.phaseIndex, finished: st.finished, t: t)
        if let prev = phaseIndex, let plan, plan.phases.indices.contains(prev), plan.phases[prev].kind == .work {
            state.closeInterval(phaseIndex: prev, workNumber: plan.workNumber(at: prev), phase: plan.phases[prev])
            pendingInterval = st.finished ? nil : prev
        } else {
            pendingInterval = nil
        }
        phaseIndex = st.phaseIndex
        state.beginPhase(at: t)
        spokenInPhase = [:]
        holds = [:]
        nextTechnique = nil
        countdownDone = false
    }

    // MARK: Info-Ansagen

    private mutating func utterance(for cue: CoachCue, input: CoachInput) -> CoachUtterance? {
        let t = input.time
        var scenario: CoachScenario?
        var values: [String: String] = [:]
        if coachOn {
            switch cue {
            case .phaseStarted(let p, let index) where p.kind == .work:
                if p.testRole == "allOut3min" {
                    scenario = .testAllOutGo
                } else if p.testRole == "step" || p.testRole == "ramp" {
                    scenario = nil   // Stufen und Rampenminuten: nur die Information, kein „Los!“
                } else {
                    let isLast = (plan?.workCount ?? 0) >= 2 && plan?.workNumber(at: index) == plan?.workCount
                    scenario = isLast ? .lastInterval : .go
                    values = phaseValues(p, index: index)
                }
            case .halfway:
                scenario = input.status != nil ? .workoutHalf : .freeHalf
                if let f = input.free {
                    // Rest bis zum Ziel
                    values["distance"] = CoachSpoken.distance(max(f.total - f.distance, 0), language: settings.language)
                    if let r = f.estimatedRemaining { values["duration"] = CoachSpoken.duration(r, language: settings.language) }
                }
            case .remaining(let m):
                scenario = .free500Left
                values["distance"] = CoachSpoken.distance(Double(m), language: settings.language)
            case .finished:
                scenario = .workoutDone
                values["duration"] = CoachSpoken.duration(t, language: settings.language)
                if let d = input.distance, d > 0 { values["distance"] = CoachSpoken.distance(d, language: settings.language) }
                if let n = plan?.workCount, n > 0 { values["n"] = "\(n)" }
            case .countdown(_, let next?, let nextIndex) where next.testRole == "ramp":
                // Rampe: neues Zieltempo statt des Countdowns
                scenario = .testRampNext
                values = phaseValues(next, index: nextIndex)
            case .countdown(let secs, let next, _):
                // last_10s nur, solange das Budget für das Ende harter Phasen reicht; sonst bleibt der Countdown
                let endPushLeft = endPushTimes.filter { $0 > t - 60 }.count
                    < config.endPushPerMinute[settings.frequency, default: 3]
                if config.last10ReplacesCountdown, endPushLeft, let cur = input.status?.phase, cur.kind == .work,
                   cur.intensity() == .hard, cur.testRole != "step",
                   next == nil || next?.kind == .rest || next?.kind == .cooldown {
                    scenario = .last10s
                    values["duration"] = CoachSpoken.duration(Double(secs), language: settings.language)
                }
            default:
                break
            }
        }
        let endZone = input.status.map(hardEndZone) ?? false
        if let s = scenario, let p = picker?.pick(s, style: settings.style, language: settings.language, values: values,
                                                  preferMaxWords: endZone ? config.endZoneMaxWords : nil) {
            let u = CoachUtterance(text: p.text, phraseId: p.phraseId, scenario: s, cue: nil, level: p.level,
                                   isDynamic: p.isDynamic, priority: s.category.priority, interrupting: true, time: t)
            record(u, key: s, onceKey: nil, budgeted: false, endPush: s.isEndPush, t: t)
            return u
        }
        let u = CoachUtterance(text: "", phraseId: nil, scenario: nil, cue: cue, level: 1, isDynamic: true,
                               priority: .info, interrupting: true, time: t)
        record(u, key: nil, onceKey: nil, budgeted: false, endPush: false, t: t)
        return u
    }

    // MARK: Planer

    private struct Candidate {
        var scenario: CoachScenario
        var level: Int = 1
        var values: [String: String] = [:]
        /// Ersatzszenarien, wenn die Phrasendatei das Szenario nicht kennt
        var fallbacks: [CoachScenario] = []
        /// einmalig je Phase (bzw. je Fahrt)
        var onceKey: String?
        /// Abklingzeit nicht prüfen (Eskalation: die Regel prüft `escalationDelay`)
        var ignoreCooldown = false
        /// Hysterese nach dem Sprechen neu starten (Lob: erst nach erneut erfüllter Dauer wieder)
        var resetHold = false
    }

    private func allowed(_ c: Candidate, input: CoachInput) -> Bool {
        let t = input.time, s = c.scenario
        if let k = c.onceKey, done.contains(k) { return false }
        // nicht während einer Ansage, Mindestabstand
        if input.isSpeaking || t < speakingUntil { return false }
        if t - lastAnyTime < config.minGap { return false }
        // Testansagen: eigenes Budget (die Regel bestimmt den Takt), nur die Ruhezone vor dem Wechsel gilt
        if s.isTest {
            if let secs = input.status?.secondsToChange, secs <= config.quietBeforeChange { return false }
            return true
        }
        if !c.ignoreCooldown, let last = lastByScenario[s], t - last < config.cooldown(s) { return false }
        if s.category == .correction, (spokenInPhase[s] ?? 0) >= config.maxCorrectionsPerPhase { return false }
        // nie zwei Korrekturen hintereinander ohne Lob oder Info dazwischen
        if s.category == .correction, lastCategory == .correction { return false }
        // `workout_final` und `last_30s` nicht im selben 60-s-Fenster (die erste gewinnt)
        if s == .workoutFinal, let l = lastByScenario[.last30s], t - l < 60 { return false }
        if s == .last30s, let l = lastByScenario[.workoutFinal], t - l < 60 { return false }
        // Budget für das Ende harter Phasen (dort zählt jede Coach-Ansage ausser `stopped`)
        let endZone = input.status.map(hardEndZone) ?? false
        if s.isEndPush || (endZone && s != .stopped) {
            let n = endPushTimes.filter { $0 > t - 60 }.count
            if n >= config.endPushPerMinute[settings.frequency, default: 3] { return false }
        }
        // Lob in Grundlage seltener, damit auch Technikimpulse Platz haben
        if s.category == .praise, easyContext(input), let last = lastByScenario[s], t - last < config.easyPraiseCooldown {
            return false
        }
        if let st = input.status {
            // Ruhezone vor dem Wechsel; nicht in den Countdown hineinsprechen
            if let secs = st.secondsToChange {
                if secs <= config.quietBeforeChange { return false }
                if !countdownDone, secs > PlanEngine.countdownSeconds,
                   secs - estimatedDuration(words: 6) - config.countdownGuard < PlanEngine.countdownSeconds {
                    return false
                }
            }
            // Einrudern: nur Information und Vorbereitung auf die erste Belastung
            if st.phase?.kind == .warmup, s != .prepHard, s != .restPrepare { return false }
        }
        // Budget nach Häufigkeit
        if !s.budgetExempt {
            if easyContext(input) {
                if t - lastBudgetTime < config.easyInterval[settings.frequency, default: 180] { return false }
            } else {
                let n = budgetTimes.filter { $0 > t - 60 }.count
                if n >= config.budgetPerMinute[settings.frequency, default: 2] { return false }
            }
        }
        return true
    }

    /// Grundlage (leichte Phase ausser Pause) und freies Rudern: Budget als Mindestabstand
    private func easyContext(_ input: CoachInput) -> Bool {
        guard let p = input.status?.phase else { return true }
        return p.kind != .rest && p.intensity() == .easy
    }

    /// Letzte 60 s bzw. 300 m einer harten Belastung
    private func hardEndZone(_ st: PlanStatus) -> Bool {
        guard !st.finished, let p = st.phase, p.kind == .work, p.intensity() == .hard else { return false }
        return (st.remainingTime.map { $0 <= config.fadeEndSeconds } ?? false)
            || (st.remainingDistance.map { $0 <= config.fadeEndMeters } ?? false)
    }

    private func estimatedDuration(words: Int) -> Double {
        Double(words) / max(config.wordsPerSecond, 0.5) + 0.5
    }

    private mutating func record(_ u: CoachUtterance, key: CoachScenario?, onceKey: String?, budgeted: Bool,
                                 endPush: Bool, t: Double) {
        lastAnyTime = t
        lastCategory = u.category
        if endPush { endPushTimes = endPushTimes.filter { $0 > t - 60 } + [t] }
        let words = u.text.split(whereSeparator: { $0 == " " }).count
        speakingUntil = max(speakingUntil, t + (u.isInfo ? config.infoDuration : estimatedDuration(words: words)))
        if let key {
            lastByScenario[key] = t
            spokenInPhase[key, default: 0] += 1
        }
        if let k = onceKey { done.insert(k) }
        if budgeted {
            budgetTimes = budgetTimes.filter { $0 > t - 60 } + [t]
            lastBudgetTime = t
        }
    }

    /// Hysterese: wie lange die Bedingung schon ununterbrochen gilt (0 = gilt nicht)
    private mutating func held(_ s: CoachScenario, _ cond: Bool, _ t: Double) -> Double {
        guard cond else { holds[s] = nil; return 0 }
        if holds[s] == nil { holds[s] = t }
        return t - holds[s]!
    }

    /// Stufe für Szenarien mit Eskalation (fade_mid, pace_slow, rate_low, rate_high; fade_end und stopped eigens):
    /// 1 beim ersten Mal in der Phase, danach 2. phase_half und interval_done wählen die Stufe nach der Lage.
    private func escalatedLevel(_ s: CoachScenario) -> Int { min((spokenInPhase[s] ?? 0) + 1, 2) }

    // MARK: Werte für Platzhalter

    private func phaseValues(_ p: WorkoutPhase, index: Int) -> [String: String] {
        let lang = settings.language
        var v: [String: String] = [:]
        if let n = plan?.workNumber(at: index) { v["n"] = "\(n)" }
        if let of = plan?.workCount, of > 0 { v["of"] = "\(of)" }
        if let d = p.durationS { v["duration"] = CoachSpoken.duration(d, language: lang) }
        if let m = p.distanceM { v["distance"] = CoachSpoken.distance(m, language: lang) }
        if let r = p.spmRange { v["spm_min"] = "\(r.lowerBound)"; v["spm_max"] = "\(r.upperBound)" }
        if let r = p.paceRange(best2k: best2k) {
            v["split"] = CoachSpoken.split((r.lowerBound + r.upperBound) / 2, language: lang)
        }
        return v
    }

    // MARK: Regeln

    private mutating func rules(_ input: CoachInput) -> [Candidate] {
        let t = input.time
        var out: [Candidate] = []
        let lang = settings.language
        let spm = state.recent(\.spm, at: t)
        let pace = state.recent(\.pace, at: t)

        // Freies Rudern
        guard let st = input.status else {
            if let f = input.free {
                if let gap = f.paceLineGap {
                    var v = ["distance": CoachSpoken.distance(abs(gap), language: lang)]
                    if let s = f.paceLineGapSeconds { v["delta"] = CoachSpoken.delta(s, language: lang) }
                    if held(.paceLineAhead, gap >= config.paceLineMeters, t) >= config.paceLineHold {
                        out.append(Candidate(scenario: .paceLineAhead, values: v, resetHold: true))
                    }
                    if held(.paceLineBehind, gap <= -config.paceLineMeters, t) >= config.paceLineHold {
                        out.append(Candidate(scenario: .paceLineBehind, values: v, resetHold: true))
                    }
                }
                if f.total >= 2000, input.isRowing, let start = freeStart {
                    techniqueRule(t: t, phaseStart: start, into: &out)
                }
            }
            return out
        }
        guard !st.finished, let phase = st.phase, let plan else { return out }
        let idx = st.phaseIndex
        let kind = phase.kind
        let intensity = phase.intensity()
        let isWork = kind == .work
        let isHard = isWork && intensity == .hard
        let isEasy = kind != .rest && intensity == .easy
        let phaseLen = phase.durationS ?? phase.estimatedSeconds(best2k: best2k)
        let tIn = t - state.phaseStart
        let progress = st.phaseProgress
        let targetPace = phase.paceRange(best2k: best2k)
        let targetRate = phase.spmRange
        let settled = tIn >= config.settleTime
        let inEnd = progress >= config.fadeEndFraction
            || (st.remainingTime.map { $0 <= config.fadeEndSeconds } ?? false)
            || (st.remainingDistance.map { $0 <= config.fadeEndMeters } ?? false)
        func once(_ s: CoachScenario) -> String { "\(s.rawValue)#\(idx)" }
        let testCandidates = plan.test != nil || phase.testRole != nil
            ? testRules(input, st: st, phase: phase, plan: plan, tIn: tIn, pace: pace) : []

        // --- Struktur ---
        if let next = st.nextPhase, next.kind == .work, let secs = st.secondsToChange {
            let nextValues = phaseValues(next, index: idx + 1)
            if next.intensity() == .hard, config.prepWindow.contains(secs) {
                out.append(Candidate(scenario: .prepHard, values: nextValues, fallbacks: [.restPrepare],
                                     onceKey: once(.prepHard)))
            } else if kind == .rest, phaseLen >= config.restPrepareMinRest, config.restPrepareWindow.contains(secs) {
                out.append(Candidate(scenario: .restPrepare, values: nextValues, onceKey: once(.restPrepare)))
            }
        }
        if isWork, intensity != .easy, phaseLen >= config.firstStrokesMinPhase, config.firstStrokesWindow.contains(tIn) {
            out.append(Candidate(scenario: .firstStrokes, onceKey: once(.firstStrokes)))
        }
        if isWork, phaseLen >= config.phaseHalfMinPhase, config.phaseHalfWindow.contains(progress) {
            // Stufe 1 = im Ziel („du liegst gut“), Stufe 2 = nicht im Ziel („dranbleiben“)
            let ok = onTarget(spm: spm, pace: pace, rate: targetRate, paceRange: targetPace, tolerance: 1) ?? true
            out.append(Candidate(scenario: .phaseHalf, level: ok ? 1 : 2, onceKey: once(.phaseHalf)))
        }
        if isWork, intensity != .easy, phaseLen >= config.lastQuarterMinPhase,
           config.lastQuarterWindow.contains(progress) {
            out.append(Candidate(scenario: .lastQuarter, onceKey: once(.lastQuarter)))
        }
        if isHard, let d = phase.durationS, d >= config.last30MinPhase, let r = st.remainingTime,
           config.last30Window.contains(r) {
            if let f = lastByScenario[.fadeEnd], f >= state.phaseStart, t - f < config.fadeReplacesLast30Within {
                done.insert(once(.last30s))   // fade_end hat last_30s ersetzt
            } else {
                out.append(Candidate(scenario: .last30s, onceKey: once(.last30s)))
            }
        }
        if isHard, let m = phase.distanceM, let r = st.remainingDistance {
            if m >= config.last250MinPhase, config.last250Window.contains(r) {
                out.append(Candidate(scenario: .last250m, onceKey: once(.last250m)))
            }
            if m >= config.last100MinPhase, config.last100Window.contains(r) {
                out.append(Candidate(scenario: .last100m, onceKey: once(.last100m)))
            }
        }
        if let prev = pendingInterval, config.intervalDoneWindow.contains(tIn) {
            out.append(intervalCandidate(prev: prev, onceKey: once(.intervalDone)))
        }
        // erst die Rückmeldung zum Intervall, dann „erholen“
        let feedbackPending = pendingInterval != nil && !done.contains(once(.intervalDone))
            && tIn <= config.intervalDoneWindow.upperBound
        if kind == .rest, phaseLen >= config.restRecoverMinRest, config.restRecoverWindow.contains(tIn), !feedbackPending {
            out.append(Candidate(scenario: .restRecover,
                                 values: ["duration": CoachSpoken.duration(phaseLen, language: lang)],
                                 onceKey: once(.restRecover)))
        }
        if isWork, plan.estimatedDuration(best2k: best2k) >= config.workoutFinalMinWorkout,
           st.estimatedRemaining <= config.workoutFinalSeconds, st.estimatedRemaining > config.quietBeforeChange {
            out.append(Candidate(scenario: .workoutFinal,
                                 values: ["duration": CoachSpoken.duration(st.estimatedRemaining, language: lang)],
                                 onceKey: "workout_final"))
        }

        // --- Adaptiv ---
        // Stehen geblieben (nur in Belastung)
        let noStroke = state.secondsWithoutStroke(at: t)
        if isWork, noStroke >= config.stoppedAfter {
            let n = spokenInPhase[.stopped] ?? 0
            let last = lastByScenario[.stopped] ?? -.infinity
            // Stufe 1, nach `escalationDelay` Stufe 2, danach nur noch alle `stoppedRepeat` s
            if n == 0 || (n == 1 && t - last >= config.escalationDelay) || t - last >= config.stoppedRepeat {
                out.append(Candidate(scenario: .stopped, level: min(n + 1, 2), ignoreCooldown: true))
            }
        } else if noStroke < 1 {
            spokenInPhase[.stopped] = nil   // neue Episode beginnt wieder mit Stufe 1
        }
        let rowingNow = noStroke < config.stoppedAfter

        // Abflachen
        if isWork, intensity != .easy, settled, rowingNow, progress >= config.fadeMidStart {
            var fading = false
            if let s = spm {
                if let b = state.baseline(\.spm, at: t), s <= b - config.fadeRateDrop { fading = true }
                if let lo = targetRate?.lowerBound, s <= Double(lo) - config.fadeRateDrop { fading = true }
            }
            if let p = pace, let m = state.phaseMean(\.pace, at: t),
               p >= m + max(config.fadePaceDrop, m * config.fadePaceDropFraction) { fading = true }
            let h = held(.fadeEnd, fading, t)
            if h >= config.fadeHold {
                if inEnd && isHard {
                    let n = spokenInPhase[.fadeEnd] ?? 0
                    let last = lastByScenario[.fadeEnd] ?? -.infinity
                    let level2OK = (st.secondsToChange ?? .infinity) >= config.fadeEndLevel2MinRemaining
                    if n == 0 || (n == 1 && t - last >= config.escalationDelay && level2OK) {
                        out.append(Candidate(scenario: .fadeEnd, level: n + 1, ignoreCooldown: true))
                    }
                } else if !inEnd {
                    out.append(Candidate(scenario: .fadeMid, level: escalatedLevel(.fadeMid)))
                }
            }
        } else {
            _ = held(.fadeEnd, false, t)
        }

        // Schlagzahl ausserhalb des Ziels (in harten Phasen am Ende übernimmt fade_end)
        if let r = targetRate, let s = spm, settled, rowingNow, kind != .rest, kind != .warmup, !(isHard && inEnd) {
            let tol = isEasy ? config.rateToleranceEasy : config.rateTolerance
            if held(.rateLow, s <= Double(r.lowerBound) - tol, t) >= (isHard ? config.rateHoldHard : config.rateHold) {
                out.append(Candidate(scenario: .rateLow, level: escalatedLevel(.rateLow),
                                     values: ["spm_min": "\(r.lowerBound)", "spm_max": "\(r.upperBound)",
                                              "spm": "\(Int(s.rounded()))"]))
            }
            if held(.rateHigh, s >= Double(r.upperBound) + tol, t) >= (isHard ? config.rateHoldHard : config.rateHold) {
                out.append(Candidate(scenario: .rateHigh, level: escalatedLevel(.rateHigh),
                                     values: ["spm_min": "\(r.lowerBound)", "spm_max": "\(r.upperBound)",
                                              "spm": "\(Int(s.rounded()))"]))
            }
        } else {
            _ = held(.rateLow, false, t); _ = held(.rateHigh, false, t)
        }

        // Im Ziel: Lob
        if kind != .rest, kind != .warmup, settled, rowingNow,
           let ok = onTarget(spm: spm, pace: pace, rate: targetRate, paceRange: targetPace, tolerance: 0) {
            var good = ok
            if good, let target = phase.hrZone, let z = currentZone() { good = z <= target }
            if held(.paceOnTarget, good, t) >= config.onTargetHold {
                var v: [String: String] = [:]
                if let p = pace { v["split"] = CoachSpoken.split(p, language: lang) }
                out.append(Candidate(scenario: .paceOnTarget, values: v, resetHold: true))
            }
        } else {
            _ = held(.paceOnTarget, false, t)
        }

        // Tempo: zu schnell angegangen, zu langsam
        if isWork, let tp = targetPace, let p = pace, settled, rowingNow {
            let long = (phase.durationS.map { $0 >= config.longPhaseSeconds } ?? false)
                || (phase.distanceM.map { $0 >= config.longPhaseMeters } ?? false)
            if held(.paceTooFastEarly, long && progress < config.tooFastFraction && p <= tp.lowerBound - config.tooFastDelta,
                    t) >= config.tooFastHold {
                out.append(Candidate(scenario: .paceTooFastEarly,
                                     values: ["split": CoachSpoken.split((tp.lowerBound + tp.upperBound) / 2, language: lang),
                                              "delta": CoachSpoken.delta(tp.lowerBound - p, language: lang)]))
            }
            let slow = !(isHard && inEnd) && p >= tp.upperBound + config.paceSlowTolerance
            if held(.paceSlow, slow, t) >= config.paceSlowHold {
                out.append(Candidate(scenario: .paceSlow, level: escalatedLevel(.paceSlow),
                                     values: ["split": CoachSpoken.split((tp.lowerBound + tp.upperBound) / 2, language: lang),
                                              "delta": CoachSpoken.delta(p - tp.upperBound, language: lang)]))
            }
        } else {
            _ = held(.paceTooFastEarly, false, t); _ = held(.paceSlow, false, t)
        }

        // Starker Schluss
        if isWork, phaseLen >= 60, progress >= 1 - config.strongFinishFraction, let p = pace,
           let m = state.phaseMean(\.pace, at: t), rowingNow {
            if held(.strongFinish, p <= m - config.strongFinishDelta, t) >= config.strongFinishHold {
                out.append(Candidate(scenario: .strongFinish, onceKey: once(.strongFinish)))
            }
        } else {
            _ = held(.strongFinish, false, t)
        }

        // Puls zu hoch in Grundlage/Regeneration
        if isEasy, kind != .warmup, let target = phase.hrZone, let z = currentZone() {
            if held(.hrHighEasy, z >= target + config.hrZoneOver, t) >= config.hrHold {
                out.append(Candidate(scenario: .hrHighEasy))
            }
        } else {
            _ = held(.hrHighEasy, false, t)
        }

        // Pause zu hart
        if kind == .rest, tIn >= 10 {
            let base = PaceTargets.basePace500(best2k: best2k)
            let hard = (pace.map { $0 <= base + config.restTooHardPaceOffset } ?? false)
                || (spm.map { $0 >= config.restTooHardRate } ?? false)
            if held(.restTooHard, hard && rowingNow, t) >= config.restTooHardHold {
                out.append(Candidate(scenario: .restTooHard))
            }
        }

        // Technik in langen ruhigen Phasen
        if kind != .warmup, kind != .rest, intensity != .hard, phaseLen >= config.techniqueMinPhase, rowingNow {
            techniqueRule(t: t, phaseStart: state.phaseStart, into: &out)
        }
        // fade_end ersetzt last_30s, wenn beide zugleich fällig sind
        if out.contains(where: { $0.scenario == .fadeEnd }) { out.removeAll { $0.scenario == .last30s } }
        // Stufentest: keine Motivation, nur Information, Testansagen und „stehen geblieben“;
        // 3-min-All-out: statt Korrekturen der Zuspruch des Tests
        if plan.test?.evaluatorKind == .stepHR || phase.testRole == "step" || phase.testRole == "allOut3min" {
            out.removeAll { $0.scenario != .stopped }
        }
        return testCandidates + out
    }

    // MARK: Schwellentests

    /// Schwelle (W) für Live-Werte: aus dem Kontext, sonst aus der 2k-Referenz
    private var thresholdW: Double {
        testContext?.thresholdW ?? ThresholdMath.threshold(fromBest2k: best2k, b: ThresholdMath.activeExponent)
    }

    private mutating func logPower(_ input: CoachInput) {
        let t = input.time
        guard let p = input.power, input.isRowing || p > 0 else { lastPowerTime = t; return }
        let w = Double(max(p, 0))
        if let last = lastPowerTime {
            let dt = min(max(t - last, 0), 5)
            phasePowerSum += w * dt
            phasePowerTime += dt
        }
        lastPowerTime = t
        powerLog.append((t, w))
        powerLog.removeAll { $0.t < t - 70 }
        if input.status?.phase?.testRole == "ramp", let m = meanPower(last: 60, at: t, minSpan: 58) {
            rampBest60 = max(rampBest60, m)
        }
    }

    /// Mittlere Leistung der letzten `seconds` (nil, wenn die Werte weniger als `minSpan` s abdecken)
    private func meanPower(last seconds: Double, at t: Double, minSpan: Double? = nil) -> Double? {
        let w = powerLog.filter { $0.t > t - seconds }
        guard let first = w.first, !w.isEmpty, t - first.t >= (minSpan ?? seconds * 0.8) else { return nil }
        return w.map(\.p).reduce(0, +) / Double(w.count)
    }

    /// Ende eines Testteils merken (Wechsel in eine Phase mit anderer Rolle)
    private mutating func noteTestPhaseEnd(newIndex: Int, finished: Bool, t: Double) {
        defer {
            phasePowerSum = 0
            phasePowerTime = 0
        }
        guard let prev = phaseIndex, let plan, plan.phases.indices.contains(prev),
              let role = plan.phases[prev].testRole else { return }
        let newRole = plan.phases.indices.contains(newIndex) && !finished ? plan.phases[newIndex].testRole : nil
        guard newRole != role else { return }
        let skipped = plan.phases.indices.contains(prev + 1)
            && plan.phases[(prev + 1)...].contains { $0.testRole == role } && newIndex > prev + 1
        pendingTestEnd = TestEnd(role: role, skipped: skipped,
                                 meanPower: phasePowerTime > 0 ? phasePowerSum / phasePowerTime : nil,
                                 duration: t - state.phaseStart, last30: meanPower(last: 30, at: t),
                                 best60: rampBest60 > 0 ? rampBest60 : nil, at: t)
    }

    private mutating func testRules(_ input: CoachInput, st: PlanStatus, phase: WorkoutPhase, plan: WorkoutPlan,
                                    tIn: Double, pace: Double?) -> [Candidate] {
        let t = input.time, idx = st.phaseIndex, lang = settings.language
        let tw = thresholdW
        var out: [Candidate] = []
        func key(_ s: CoachScenario, _ extra: String = "") -> String { "\(s.rawValue)#\(idx)\(extra)" }
        func encourage(level: Int, every: Double) {
            if lastByScenario[.testAllOutEncourage].map({ t - $0 >= every }) ?? true {
                out.append(Candidate(scenario: .testAllOutEncourage, level: level, ignoreCooldown: true))
            }
        }
        // Einführung (einmal je Fahrt): Stufe 1 submaximal, Stufe 2 maximal mit Abbruch-Hinweis
        if plan.test != nil {
            let maximal = plan.test?.allOut == true || plan.test?.evaluatorKind != .stepHR
            out.append(Candidate(scenario: .testIntro, level: maximal ? 2 : 1, onceKey: "test_intro"))
        }
        // nächste Stufe mit Zieltempo
        if let next = st.nextPhase, next.testRole == "step", let secs = st.secondsToChange, (12...17).contains(secs) {
            out.append(Candidate(scenario: .testStepNext, values: phaseValues(next, index: idx + 1),
                                 onceKey: key(.testStepNext)))
        }
        let role = phase.testRole
        if role == "step" {
            if let tp = phase.paceRange(best2k: best2k), let p = pace, tIn >= config.settleTime {
                if held(.testStepHold, p <= tp.lowerBound - 3, t) >= 10,
                   lastByScenario[.testStepHold].map({ t - $0 >= 30 }) ?? true {
                    out.append(Candidate(scenario: .testStepHold, ignoreCooldown: true, resetHold: true))
                }
            } else {
                _ = held(.testStepHold, false, t)
            }
            if let n = plan.workNumber(at: idx), n >= 2, let secs = st.secondsToChange, (20...40).contains(secs) {
                out.append(Candidate(scenario: .testTalkCheck, onceKey: key(.testTalkCheck)))
            }
        }
        // Zeitfahren 20/30 min
        let isTT = role == "timeTrial"
            || (role == nil && plan.test?.evaluatorKind == .timeTrial && phase.kind == .work && (phase.durationS ?? 0) >= 1200)
        if isTT, let d = phase.durationS {
            if tIn >= 20, tIn < 180, let p10 = meanPower(last: 10, at: t) {
                if held(.testTTPacing, p10 > 1.10 * tw, t) >= 10 {
                    var v: [String: String] = [:]
                    if let r = phase.paceRange(best2k: best2k) {
                        v["split"] = CoachSpoken.split((r.lowerBound + r.upperBound) / 2, language: lang)
                    }
                    out.append(Candidate(scenario: .testTTPacing, level: 1, values: v, onceKey: key(.testTTPacing, "fast")))
                }
            } else {
                _ = held(.testTTPacing, false, t)
            }
            let mark = Int(tIn / 300)
            if mark >= 1, tIn - Double(mark) * 300 < 20, d - tIn > 90, phasePowerTime > 30 {
                let mean = phasePowerSum / phasePowerTime
                out.append(Candidate(scenario: .testTTPacing, level: 2,
                                     values: ["watts": CoachSpoken.watts(mean, language: lang),
                                              "split": CoachSpoken.split(ThresholdMath.pace(watts: mean), language: lang)],
                                     onceKey: key(.testTTPacing, "/\(mark)")))
            }
            if d - tIn <= 120 { encourage(level: d - tIn <= 30 ? 2 : 1, every: 25) }
        }
        // 3 min All-out: Zuspruch alle 20 s, letzte 30 s Stufe 2
        if role == "allOut3min", tIn >= 15, let d = phase.durationS {
            encourage(level: d - tIn <= 30 ? 2 : 1, every: 20)
        }
        // Rampe: ab 100 % der Schwelle anfeuern
        if role == "ramp", (phase.powerPctRange?.lowerBound ?? 0) >= 99, tIn >= 10 {
            encourage(level: 1, every: 25)
        }
        // Ende des Testteils
        if let e = pendingTestEnd {
            if t - e.at > 150 {
                pendingTestEnd = nil
            } else if e.role == "ramp", !done.contains("test_ramp_end") {
                out.append(Candidate(scenario: .testRampEnd, onceKey: "test_ramp_end"))
            } else if e.role == "step", e.skipped, !done.contains("test_hr_reached") {
                out.append(Candidate(scenario: .testHRReached, onceKey: "test_hr_reached"))
            } else if t - e.at >= 5 {
                var watts: Double?
                switch e.role {
                case "timeTrial":
                    watts = e.meanPower.map { ThresholdMath.thresholdFromEffort(power: $0, duration: e.duration,
                                                                                b: testContext?.exponentB ?? ThresholdMath.activeExponent) }
                case "allOut3min": watts = e.last30.map { 0.88 * $0 }
                case "ramp": watts = e.best60.map { (testContext?.rampFactor ?? ThresholdProfile.defaultRampFactor) * $0 }
                default: watts = nil
                }
                var v: [String: String] = [:]
                if let w = watts, w > 0, e.duration >= (e.role == "timeTrial" ? 600 : 0) {
                    v["watts"] = CoachSpoken.watts(w, language: lang)
                    v["split"] = CoachSpoken.split(ThresholdMath.pace(watts: w), language: lang)
                }
                out.append(Candidate(scenario: .testResult, values: v, onceKey: "test_result"))
            }
        }
        return out
    }

    private mutating func techniqueRule(t: Double, phaseStart: Double, into out: inout [Candidate]) {
        if nextTechnique == nil {
            nextTechnique = phaseStart + config.techniqueFirstAfter + uniform(0...60)
        }
        // nach dem Sprechen neu planen (siehe record → lastByScenario)
        if let last = lastByScenario[.technique], last >= phaseStart, let n = nextTechnique, last >= n {
            nextTechnique = last + uniform(config.techniqueInterval)
        }
        if let n = nextTechnique, t >= n {
            out.append(Candidate(scenario: .technique))
        }
    }

    private mutating func uniform(_ r: ClosedRange<Double>) -> Double {
        let u = Double(rng.next() >> 11) / Double(UInt64(1) << 53)
        return r.lowerBound + (r.upperBound - r.lowerBound) * u
    }

    private func currentZone() -> Int? {
        guard let zones, let hr = state.smoothedHeartRate else { return nil }
        return zones.zone(for: Int(hr.rounded()))
    }

    /// Im Ziel? nil, wenn die Phase weder Tempo- noch Schlagzahlziel hat oder Messwerte fehlen
    private func onTarget(spm: Double?, pace: Double?, rate: ClosedRange<Int>?, paceRange: ClosedRange<Double>?,
                          tolerance: Double) -> Bool? {
        guard rate != nil || paceRange != nil else { return nil }
        if let r = rate {
            guard let s = spm else { return nil }
            if s < Double(r.lowerBound) - tolerance - 0.5 || s > Double(r.upperBound) + tolerance + 0.5 { return false }
        }
        if let pr = paceRange {
            guard let p = pace else { return nil }
            if p < pr.lowerBound - tolerance - 0.5 || p > pr.upperBound + tolerance + 0.5 { return false }
        }
        return true
    }

    /// `interval_done` oder ein Vergleich mit den vorigen Intervallen ähnlicher Länge
    private func intervalCandidate(prev: Int, onceKey: String) -> Candidate {
        let lang = settings.language
        var c = Candidate(scenario: .intervalDone, onceKey: onceKey)
        guard let cur = state.intervals.last, cur.phaseIndex == prev else { return c }
        if let n = cur.workNumber { c.values["n"] = "\(n)" }
        if let of = plan?.workCount { c.values["of"] = "\(of)" }
        guard let pace = cur.pace else { return c }
        c.values["split"] = CoachSpoken.split(pace, language: lang)
        let comparable = state.intervals.dropLast().filter { similar($0, cur) && $0.pace != nil }
        guard let last = comparable.last, let lastPace = last.pace else { return c }
        let diff = pace - lastPace
        c.values["delta"] = CoachSpoken.delta(diff, language: lang)
        // Ersatz ist die neutrale Abschlussansage (interval_done Stufe 1)
        c.fallbacks = [.intervalDone]
        if comparable.count + 1 >= config.bestIntervalMinCount,
           let best = comparable.compactMap(\.pace).min(), pace < best - 0.5 {
            c.scenario = .bestInterval
        } else if diff >= config.slowerThreshold {
            c.scenario = .slowerThanPrev
        } else if abs(diff) <= config.consistentTolerance {
            c.scenario = .consistent
        } else if diff < 0 {
            // schneller als das vorige: interval_done Stufe 2 (Lage, keine Eskalation), {delta} = Zeitgewinn
            c.level = 2
            c.fallbacks = []
        } else {
            c.fallbacks = []
            c.values["delta"] = nil
        }
        return c
    }

    private func similar(_ a: CoachState.IntervalStat, _ b: CoachState.IntervalStat) -> Bool {
        func close(_ x: Double?, _ y: Double?) -> Bool {
            guard let x, let y, x > 0, y > 0 else { return false }
            return max(x, y) / min(x, y) <= config.compareLengthRatio
        }
        return close(a.plannedSeconds, b.plannedSeconds) || close(a.plannedMeters, b.plannedMeters)
    }
}
