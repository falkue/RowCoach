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

    public init(plan: WorkoutPlan?, settings: CoachSettings, config: CoachConfig = CoachConfig(),
                phrases: CoachPhraseBank?, best2k: Double = PaceTargets.defaultBest2k, zones: HeartRateZones? = nil,
                seed: UInt64 = 1) {
        self.plan = plan
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
        for c in candidates.sorted(by: { $0.scenario.category.priority > $1.scenario.category.priority })
            where allowed(c, input: input) {
            for s in [c.scenario] + c.fallbacks {
                if let p = picker?.pick(s, level: c.level, style: settings.style, language: settings.language,
                                        values: c.values) {
                    let u = CoachUtterance(text: p.text, phraseId: p.phraseId, scenario: s, cue: nil, level: p.level,
                                           isDynamic: p.isDynamic, priority: s.category.priority,
                                           interrupting: false, time: t)
                    record(u, key: c.scenario, onceKey: c.onceKey, budgeted: !c.scenario.budgetExempt, t: t)
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
                let isLast = (plan?.workCount ?? 0) >= 2 && plan?.workNumber(at: index) == plan?.workCount
                scenario = isLast ? .lastInterval : .go
                values = phaseValues(p, index: index)
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
            case .countdown(let secs, let next, _):
                if config.last10ReplacesCountdown, let cur = input.status?.phase, cur.kind == .work,
                   cur.intensity() == .hard, next == nil || next?.kind == .rest || next?.kind == .cooldown {
                    scenario = .last10s
                    values["duration"] = CoachSpoken.duration(Double(secs), language: settings.language)
                }
            default:
                break
            }
        }
        if let s = scenario, let p = picker?.pick(s, style: settings.style, language: settings.language, values: values) {
            let u = CoachUtterance(text: p.text, phraseId: p.phraseId, scenario: s, cue: nil, level: p.level,
                                   isDynamic: p.isDynamic, priority: s.category.priority, interrupting: true, time: t)
            record(u, key: s, onceKey: nil, budgeted: false, t: t)
            return u
        }
        let u = CoachUtterance(text: "", phraseId: nil, scenario: nil, cue: cue, level: 1, isDynamic: true,
                               priority: .info, interrupting: true, time: t)
        record(u, key: nil, onceKey: nil, budgeted: false, t: t)
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
        if !c.ignoreCooldown, let last = lastByScenario[s], t - last < config.cooldown(s) { return false }
        if s.category == .correction, (spokenInPhase[s] ?? 0) >= config.maxCorrectionsPerPhase { return false }
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

    private func estimatedDuration(words: Int) -> Double {
        Double(words) / max(config.wordsPerSecond, 0.5) + 0.5
    }

    private mutating func record(_ u: CoachUtterance, key: CoachScenario?, onceKey: String?, budgeted: Bool, t: Double) {
        lastAnyTime = t
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
            out.append(Candidate(scenario: .last30s, onceKey: once(.last30s)))
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
            if let p = pace, let m = state.phaseMean(\.pace, at: t), p >= m + config.fadePaceDrop { fading = true }
            let h = held(.fadeEnd, fading, t)
            if h >= config.fadeHold {
                if inEnd && isHard {
                    let n = spokenInPhase[.fadeEnd] ?? 0
                    let last = lastByScenario[.fadeEnd] ?? -.infinity
                    if n == 0 || (n == 1 && t - last >= config.escalationDelay) {
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
            if held(.rateLow, s <= Double(r.lowerBound) - tol, t) >= config.rateHold {
                out.append(Candidate(scenario: .rateLow, level: escalatedLevel(.rateLow),
                                     values: ["spm_min": "\(r.lowerBound)", "spm_max": "\(r.upperBound)",
                                              "spm": "\(Int(s.rounded()))"]))
            }
            if held(.rateHigh, s >= Double(r.upperBound) + tol, t) >= config.rateHold {
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
