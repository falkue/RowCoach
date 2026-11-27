import Foundation

/// Antwort im Talk-Test am Ende einer Stufe („Kannst du noch in ganzen Sätzen sprechen?“)
public enum TalkAnswer: String, Codable, Sendable, CaseIterable {
    case easy, soSo, no
}

/// Eine gefahrene Testeinheit für die Auswertung
public struct ThresholdRideData: Sendable {
    public var workoutId: UUID?
    public var date: Date
    public var plan: WorkoutPlan?
    public var samples: [WorkoutSample]
    public var phases: [PlanPhaseResult]
    /// RR-Intervalle (s), beginnend mit der Fahrt
    public var rrIntervals: [Double]?
    /// Talk-Test je Phasenindex
    public var talk: [Int: TalkAnswer]

    public init(workoutId: UUID? = nil, date: Date, plan: WorkoutPlan?, samples: [WorkoutSample],
                phases: [PlanPhaseResult], rrIntervals: [Double]? = nil, talk: [Int: TalkAnswer] = [:]) {
        self.workoutId = workoutId
        self.date = date
        self.plan = plan
        self.samples = samples
        self.phases = phases
        self.rrIntervals = rrIntervals
        self.talk = talk
    }

    /// Aus einer gespeicherten Fahrt
    public init(record: WorkoutRecord, plan: WorkoutPlan?, talk: [Int: TalkAnswer] = [:]) {
        self.init(workoutId: record.id, date: record.header.startDate, plan: plan, samples: record.samples,
                  phases: record.planPhases ?? [], rrIntervals: record.rrIntervals, talk: talk)
    }
}

/// Ergebnis einer Testauswertung
public struct ThresholdEvaluation: Equatable, Sendable {
    /// Hauptergebnis (nil = keine Schwelle, siehe `notes`)
    public var estimate: ThresholdEstimate?
    /// zweites Ergebnis zum Vergleich (7 × 4: Stufe 7 als 4-min-Zeitfahren; DFA-α1)
    public var comparison: ThresholdEstimate?
    public var notes: [EvaluationNote]
    /// Schwellenpuls-Vorschlag (30-min-Test bzw. DFA-α1 0,5)
    public var lthrSuggestion: Int?
    /// "test30" | "stepDFA"
    public var lthrSource: String?
    /// neuer Maximalpuls (höchster 5-s-Puls über dem gespeicherten)
    public var maxHRSuggestion: Int?
    /// Puls-Leistungs-Gerade HR = intercept + slope · P (Stufentest)
    public var heartRateLine: LinearFit?
    /// LT1-Leistung und -Puls (DFA-α1 0,75)
    public var lt1Power: Double?
    public var lt1HeartRate: Int?
    /// nächste Rampe 10 % tiefer (−1) bzw. höher (+1)
    public var rampStartAdjust: Int?
    /// nur Bestmarke (zu kurz für eine Schwelle)
    public var bestMarkOnly: Bool

    public init(estimate: ThresholdEstimate? = nil, comparison: ThresholdEstimate? = nil, notes: [EvaluationNote] = [],
                bestMarkOnly: Bool = false) {
        self.estimate = estimate
        self.comparison = comparison
        self.notes = notes
        self.bestMarkOnly = bestMarkOnly
    }
}

/// Wertet eine Fahrt eines Testprogramms aus (docs/schwelle/SPEC.md 3.1–3.5).
public enum ThresholdEvaluator {
    /// Evaluator eines Programms: Feld `test`, sonst nach id (alte Tests ohne Feld)
    public static func evaluator(for plan: WorkoutPlan?) -> PlanTestInfo.Evaluator? {
        guard let plan else { return nil }
        if let e = plan.test?.evaluatorKind { return e }
        if plan.id.hasPrefix("stufentest") { return .stepHR }
        if TrainingProgramEngine.isTestPlan(plan.id) { return .timeTrial }
        return nil
    }

    public static func evaluate(_ ride: ThresholdRideData, profile: ThresholdProfile) -> ThresholdEvaluation? {
        guard let plan = ride.plan, let ev = evaluator(for: plan) else { return nil }
        var result: ThresholdEvaluation
        switch ev {
        case .timeTrial: result = timeTrial(ride, plan: plan, profile: profile)
        case .stepHR: result = stepHR(ride, plan: plan, profile: profile)
        case .ramp: result = ramp(ride, plan: plan, profile: profile)
        case .allOut3min: result = allOut3min(ride, plan: plan, profile: profile)
        }
        // Maximalpuls-Vorschlag aus jeder Testfahrt
        if let peak = ThresholdSeries(samples: ride.samples).peakHeartRate5s(),
           peak >= (profile.heart.maxHR ?? 0) + 3, profile.heart.maxHR != nil || ev != .stepHR {
            result.maxHRSuggestion = peak
        }
        result.estimate = result.estimate.map { finish($0, ride: ride, profile: profile, notes: result.notes) }
        result.comparison = result.comparison.map { finish($0, ride: ride, profile: profile, notes: []) }
        return result
    }

    /// Gemeinsame Felder, Lerneffekt (+2 % beim ersten Test dieser Art)
    private static func finish(_ e: ThresholdEstimate, ride: ThresholdRideData, profile: ThresholdProfile,
                               notes: [EvaluationNote]) -> ThresholdEstimate {
        var e = e
        e.workoutId = ride.workoutId
        e.planId = ride.plan?.id
        e.date = ride.date
        let first = !profile.estimates.contains { $0.kind == e.kind && $0.workoutId != ride.workoutId }
        if first && !e.firstOfKind {
            e.firstOfKind = true
            e.sigmaPct += 2
        }
        e.sigmaPct = min(e.sigmaPct, 20)
        var all = e.notes
        for n in notes.map(\.rawValue) where !all.contains(n) { all.append(n) }
        e.notes = all
        e.details["b"] = profile.exponentB
        return e
    }

    // MARK: Phasen

    /// Phasen mit einer bestimmten Testrolle; ohne Rollen im Programm die Belastungsphasen
    static func testPhases(_ ride: ThresholdRideData, plan: WorkoutPlan, role: String) -> [PlanPhaseResult] {
        let hasRoles = plan.phases.contains { $0.testRole != nil }
        return ride.phases.filter { r in
            guard plan.phases.indices.contains(r.index) else { return false }
            let p = plan.phases[r.index]
            return hasRoles ? p.testRole == role : p.kind == .work
        }.sorted { $0.index < $1.index }
    }

    // MARK: Zeitfahren

    static func timeTrial(_ ride: ThresholdRideData, plan: WorkoutPlan, profile: ThresholdProfile) -> ThresholdEvaluation {
        let phases = testPhases(ride, plan: plan, role: "timeTrial")
        guard !phases.isEmpty else { return ThresholdEvaluation(notes: [.notEvaluable]) }
        let series = ThresholdSeries(samples: ride.samples)
        if phases.contains(where: { !$0.completed }) { return ThresholdEvaluation(notes: [.interrupted]) }
        if phases.contains(where: { series.longestStop(from: $0.startTime, to: $0.endTime) > 15 }) {
            return ThresholdEvaluation(notes: [.interrupted])
        }
        var work = 0.0, covered = 0.0, duration = 0.0
        for ph in phases {
            let r = series.power(from: ph.startTime, to: ph.endTime)
            work += r.mean * r.covered
            covered += r.covered
            duration += ph.duration
        }
        guard covered >= 0.5 * duration, duration > 0 else { return ThresholdEvaluation(notes: [.notEvaluable]) }
        let p = work / covered
        guard p > 0 else { return ThresholdEvaluation(notes: [.notEvaluable]) }
        if duration < 180 { return ThresholdEvaluation(notes: [.noThreshold], bestMarkOnly: true) }
        if duration > 5400 { return ThresholdEvaluation(notes: [.noThreshold], bestMarkOnly: true) }
        let b = profile.exponentB
        let t = ThresholdMath.thresholdFromEffort(power: p, duration: duration, b: b)
        // Grundunsicherheit nach Dauer (Tabelle 2.2)
        let distanceBased = phases.allSatisfy { plan.phases[$0.index].distanceM != nil }
        var sigma: Double
        switch duration {
        case ..<300: sigma = 8
        case ..<1080: sigma = 6
        case ..<1500: sigma = distanceBased ? 5 : 4
        case ...2100: sigma = 3
        default: sigma = 5
        }
        if plan.id.hasPrefix("einsteiger-test") { sigma = 8 }
        var notes: [EvaluationNote] = []
        var details: [String: Double] = ["p": p, "t": duration]
        let workDistance = phases.reduce(0) { $0 + $1.distance }
        if distanceBased, abs(phases.reduce(0) { $0 + (plan.phases[$1.index].distanceM ?? 0) } - 2000) < 1 {
            details["t2k"] = duration
        }
        if workDistance > 0 { details["distance"] = workDistance }
        // zu schnell gestartet (nur langes Zeitfahren in einem Stück)
        if phases.count == 1, duration >= 1000, let ph = phases.first,
           let early = series.meanPower(from: ph.startTime, to: ph.startTime + 300),
           let rest = series.meanPower(from: ph.startTime + 300, to: ph.endTime), early > 1.08 * rest {
            notes.append(.tooFastStart)
            sigma += 1
        }
        var result = ThresholdEvaluation()
        // Schwellenpuls aus dem 30-min-Test: Puls Minute 10–30
        if duration >= 1500, duration <= 2100, let first = phases.first, let last = phases.last {
            let hr = series.heartRate(from: first.startTime + 600, to: last.endTime)
            if hr.covered >= 0.8 * (last.endTime - first.startTime - 600) {
                result.lthrSuggestion = Int(hr.mean.rounded())
                result.lthrSource = "test30"
                details["hrT"] = hr.mean
            }
        }
        result.estimate = ThresholdEstimate(kind: .timeTrial, date: ride.date, powerW: t, sigmaPct: sigma,
                                            details: details, notes: notes)
        result.notes = notes
        return result
    }

    // MARK: Stufentest mit Puls

    struct Step {
        var index: Int
        var power: Double
        var heartRate: Double
        var start: Double
        var end: Double
    }

    static func stepHR(_ ride: ThresholdRideData, plan: WorkoutPlan, profile: ThresholdProfile) -> ThresholdEvaluation {
        let series = ThresholdSeries(samples: ride.samples)
        let phases = testPhases(ride, plan: plan, role: "step").filter { $0.completed || $0.duration >= 180 }
        let rest = Double(profile.heart.restHR ?? 55)
        var steps: [Step] = []
        var missingHR = false
        for ph in phases {
            let a = max(ph.endTime - 60, ph.startTime)
            let hr = series.heartRate(from: a, to: ph.endTime)
            guard hr.covered >= 45 else { missingHR = true; continue }
            guard let p = series.meanPower(from: a, to: ph.endTime), p > 0 else { continue }
            if hr.mean >= rest + 20 {
                steps.append(Step(index: ph.index, power: p, heartRate: hr.mean, start: ph.startTime, end: ph.endTime))
            }
        }
        var result = ThresholdEvaluation()
        var notes: [EvaluationNote] = missingHR ? [.heartRateMissing] : []
        // 7 × 4: letzte Stufe zusätzlich als 4-min-Zeitfahren
        var ttEstimate: ThresholdEstimate?
        if plan.id.contains("7x4"), let last = phases.last, last.completed,
           let p4 = series.meanPower(from: last.startTime, to: last.endTime), p4 > 0 {
            let t = ThresholdMath.thresholdFromEffort(power: p4, duration: last.duration, b: profile.exponentB)
            ttEstimate = ThresholdEstimate(kind: .timeTrial, date: ride.date, powerW: t, sigmaPct: 8,
                                           details: ["p": p4, "t": last.duration])
        }
        guard steps.count >= 3,
              let fit = LinearFit(x: steps.map(\.power), y: steps.map(\.heartRate)), fit.slope > 0 else {
            notes.insert(.notEvaluable, at: 0)
            result.notes = notes
            result.estimate = ttEstimate
            return result
        }
        result.heartRateLine = fit
        // Schwellenpuls
        var sigma = 12.0
        let hrT: Double
        if let l = profile.heart.currentLTHR(now: ride.date) {
            hrT = Double(l)
            sigma = 9
        } else {
            let maxHR: Double
            if let m = profile.heart.maxHR {
                maxHR = Double(m)
            } else {
                maxHR = Double(profile.heart.tanakaMaxHR(now: ride.date) ?? 185)
                notes.append(.maxHREstimated)
                sigma += 3
            }
            hrT = rest + 0.85 * (maxHR - rest)
        }
        if fit.r2 < 0.9 {
            notes.append(.irregularHeartRate)
            sigma += 5
        }
        let tHR = (hrT - fit.intercept) / fit.slope
        let maxStepHR = steps.map(\.heartRate).max() ?? 0
        if hrT - maxStepHR > 15 {
            notes.append(.extrapolatedTooFar)
        } else if hrT - maxStepHR > 5 {
            notes.append(.extrapolated)
            sigma += 3
        }
        // Talk-Test (Plausibilität)
        if let pTalk = steps.filter({ ride.talk[$0.index] == .easy }).map(\.power).max() {
            let expected = pTalk / 0.77
            if abs(tHR - expected) / expected > 0.15 { notes.append(.talkMismatch) }
        }
        var details: [String: Double] = ["hrT": hrT, "slope": fit.slope, "intercept": fit.intercept, "r2": fit.r2,
                                         "steps": Double(steps.count), "maxStepHR": maxStepHR]
        var main = ThresholdEstimate(kind: .stepHR, date: ride.date, powerW: tHR, sigmaPct: sigma, details: details)
        // DFA-α1 (experimentell)
        if let rr = ride.rrIntervals, rr.count > 200, let dfa = dfaResult(rr: rr, steps: steps, line: fit) {
            result.lt1Power = dfa.lt1Power
            result.lt1HeartRate = dfa.lt1Power.map { Int(fit.y(at: $0).rounded()) }
            if let lthr = dfa.lthr {
                result.lthrSuggestion = lthr
                result.lthrSource = "stepDFA"
            }
            if let tDFA = dfa.threshold {
                let dfaEst = ThresholdEstimate(kind: .stepDFA, date: ride.date, powerW: tDFA, sigmaPct: 12,
                                               details: ["alpha1Slope": dfa.slope, "lt1": dfa.lt1Power ?? 0])
                if abs(tDFA - tHR) / tHR <= 0.10 {
                    main.powerW = (tHR + tDFA) / 2
                    main.sigmaPct = min(main.sigmaPct, 10)
                    details["tHR"] = tHR
                    details["tDFA"] = tDFA
                    main.details = details
                } else {
                    notes.append(.dfaDisagrees)
                }
                result.comparison = dfaEst
            }
        }
        main.notes = notes.map(\.rawValue)
        result.notes = notes
        // 7 × 4: das genauere Ergebnis wird aktiv, das andere als Vergleich
        if let tt = ttEstimate {
            if tt.sigmaPct < main.sigmaPct || main.isHintOnly {
                result.estimate = tt
                result.comparison = main
                return result
            }
            result.comparison = tt
        }
        result.estimate = main
        return result
    }

    struct DFAResult {
        var slope: Double
        var lt1Power: Double?
        var threshold: Double?
        var lthr: Int?
    }

    static func dfaResult(rr: [Double], steps: [Step], line: LinearFit) -> DFAResult? {
        let windows = DFAAlpha1.windows(rr: rr)
        var px: [Double] = [], ay: [Double] = []
        for s in steps {
            let w = windows.filter { $0.end <= s.end + 1e-6 && $0.start >= s.end - 180 - 1e-6 }.map(\.alpha1).sorted()
            guard !w.isEmpty else { continue }
            px.append(s.power)
            ay.append(w[w.count / 2])
        }
        guard px.count >= 3, let fit = LinearFit(x: px, y: ay), fit.slope < 0 else { return nil }
        let lo = px.min()!, hi = px.max()!
        var r = DFAResult(slope: fit.slope)
        if let p75 = fit.x(at: 0.75), p75 >= lo * 0.9, p75 <= hi * 1.1 { r.lt1Power = p75 }
        if let p50 = fit.x(at: 0.5), p50 >= lo, p50 <= hi * 1.1 {
            r.threshold = p50
            r.lthr = Int(line.y(at: p50).rounded())
        } else if let p75 = r.lt1Power {
            r.threshold = p75 / 0.77
        }
        return r
    }

    // MARK: Rampe

    static func ramp(_ ride: ThresholdRideData, plan: WorkoutPlan, profile: ThresholdProfile) -> ThresholdEvaluation {
        let phases = testPhases(ride, plan: plan, role: "ramp").filter { $0.duration > 0 }
        guard let first = phases.first, let last = phases.last else { return ThresholdEvaluation(notes: [.notEvaluable]) }
        let series = ThresholdSeries(samples: ride.samples)
        let rampSeconds = phases.reduce(0) { $0 + $1.duration }
        guard let best = series.bestRolling(length: 60, from: first.startTime, to: last.endTime) else {
            return ThresholdEvaluation(notes: [.rampTooShort])
        }
        let map = best.power
        var notes: [EvaluationNote] = []
        var result = ThresholdEvaluation()
        if rampSeconds < 360 {
            notes.append(.rampTooShort)
            result.rampStartAdjust = -1
        } else if rampSeconds > 1200 {
            notes.append(.rampTooLong)
            result.rampStartAdjust = 1
        }
        let t = profile.rampFactor * map
        result.estimate = ThresholdEstimate(kind: .ramp, date: ride.date, powerW: t, sigmaPct: 8,
                                            details: ["map": map, "rampFactor": profile.rampFactor,
                                                      "rampSeconds": rampSeconds],
                                            notes: notes)
        result.notes = notes
        return result
    }

    // MARK: 3 min All-out

    static func allOut3min(_ ride: ThresholdRideData, plan: WorkoutPlan, profile: ThresholdProfile) -> ThresholdEvaluation {
        let phases = testPhases(ride, plan: plan, role: "allOut3min")
        guard let ph = phases.first else { return ThresholdEvaluation(notes: [.notEvaluable]) }
        guard ph.completed, ph.duration >= 175 else { return ThresholdEvaluation(notes: [.interrupted]) }
        let series = ThresholdSeries(samples: ride.samples)
        let s = ph.startTime
        guard let ep = series.meanPower(from: s + 150, to: s + 180), ep > 0,
              let early = series.meanPower(from: s, to: s + 30),
              let late = series.meanPower(from: s + 120, to: s + 150) else {
            return ThresholdEvaluation(notes: [.notEvaluable])
        }
        var notes: [EvaluationNote] = []
        var sigma = 8.0
        if !(early >= 1.3 * ep && late <= 1.10 * ep) {
            notes.append(.notAllOut)
            sigma = 15
        }
        var result = ThresholdEvaluation(notes: notes)
        result.estimate = ThresholdEstimate(kind: .allOut3min, date: ride.date, powerW: 0.88 * ep, sigmaPct: sigma,
                                            details: ["ep": ep, "p0_30": early, "p120_150": late], notes: notes)
        return result
    }
}

/// Erkennt in der Rampe, dass das Ziel nicht mehr gehalten wird (docs/schwelle/SPEC.md 3.5): gleitende
/// 15-s-Leistung unter 90 % des aktuellen Ziels über 15 s am Stück (erst ab Stufe 4) oder Schlagzahl 0 über 5 s.
public struct RampFailureDetector: Sendable {
    public var window: Double = 15
    public var hold: Double = 15
    public var share: Double = 0.9
    public var minStep: Int = 4
    public var stopSeconds: Double = 5

    private var history: [(t: Double, p: Double)] = []
    private var belowSince: Double?
    private var stoppedSince: Double?
    public private(set) var failed = false

    public init() {}

    /// Neuer Messwert. `step` = Nummer der Rampenminute (1, 2, …), `target` = Zielleistung (W).
    @discardableResult
    public mutating func update(time t: Double, power: Double, target: Double, step: Int, strokeRate: Double) -> Bool {
        guard !failed else { return true }
        history.append((t, power))
        history.removeAll { $0.t < t - window }
        if strokeRate <= 0 {
            if stoppedSince == nil { stoppedSince = t }
            if t - stoppedSince! >= stopSeconds { failed = true }
        } else {
            stoppedSince = nil
        }
        guard step >= minStep, target > 0, let first = history.first, t - first.t >= window - 1.5 else { return failed }
        let mean = history.map(\.p).reduce(0, +) / Double(history.count)
        if mean < share * target {
            if belowSince == nil { belowSince = t }
            if t - belowSince! >= hold { failed = true }
        } else {
            belowSince = nil
        }
        return failed
    }

    /// Knopf „Ich kann nicht mehr“
    public mutating func giveUp() { failed = true }
}
