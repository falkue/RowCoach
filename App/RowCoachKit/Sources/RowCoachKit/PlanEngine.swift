import Foundation

/// Stand eines Trainings zu einem Zeitpunkt (Ausgang von `PlanEngine`).
public struct PlanStatus: Equatable, Sendable {
    /// Index der aktuellen Phase (nach dem Ende: letzte Phase)
    public var phaseIndex: Int
    public var phaseCount: Int
    public var phase: WorkoutPhase?
    public var nextPhase: WorkoutPhase?
    /// 0…1 innerhalb der Phase
    public var phaseProgress: Double
    /// Restzeit der Phase (nur Zeitphasen, s)
    public var remainingTime: Double?
    /// Restdistanz der Phase (nur Distanzphasen, m)
    public var remainingDistance: Double?
    /// Sekunden bis zum Phasenwechsel bzw. Trainingsende; bei Distanzphasen aus der Geschwindigkeit geschätzt
    /// (nil, solange keine Geschwindigkeit bekannt ist)
    public var secondsToChange: Double?
    /// Countdown zeigen: höchstens `PlanEngine.countdownSeconds` bis zum Wechsel
    public var countdownActive: Bool
    /// Distanz der Fahrt (m), bei der die nächste Phase beginnt bzw. das Training endet (für das Tor).
    /// Bei Distanzphasen exakt, bei Zeitphasen aus der Geschwindigkeit vorausberechnet.
    public var nextChangeDistance: Double?
    /// true, wenn `nextChangeDistance` exakt ist (Distanzphase)
    public var nextChangeIsExact: Bool
    /// 0…1 über das ganze Training (gewichtet nach geschätzter Dauer der Phasen)
    public var overallProgress: Double
    /// geschätzte Restdauer des ganzen Trainings (s)
    public var estimatedRemaining: Double
    public var finished: Bool

    public init(phaseIndex: Int, phaseCount: Int, phase: WorkoutPhase?, nextPhase: WorkoutPhase?,
                phaseProgress: Double, remainingTime: Double?, remainingDistance: Double?, secondsToChange: Double?,
                countdownActive: Bool, nextChangeDistance: Double?, nextChangeIsExact: Bool, overallProgress: Double,
                estimatedRemaining: Double, finished: Bool) {
        self.phaseIndex = phaseIndex
        self.phaseCount = phaseCount
        self.phase = phase
        self.nextPhase = nextPhase
        self.phaseProgress = phaseProgress
        self.remainingTime = remainingTime
        self.remainingDistance = remainingDistance
        self.secondsToChange = secondsToChange
        self.countdownActive = countdownActive
        self.nextChangeDistance = nextChangeDistance
        self.nextChangeIsExact = nextChangeIsExact
        self.overallProgress = overallProgress
        self.estimatedRemaining = estimatedRemaining
        self.finished = finished
    }
}

/// Beginn und Ende einer abgeschlossenen Phase (für die Auswertung je Phase).
public struct PhaseBoundary: Codable, Equatable, Sendable {
    public var index: Int
    /// Trainingsuhr (s): Ruderzeit, in Pausenphasen die Uhrzeit
    public var startTime: Double
    public var endTime: Double
    /// Distanz der Fahrt (m)
    public var startDistance: Double
    public var endDistance: Double

    public init(index: Int, startTime: Double, endTime: Double, startDistance: Double, endDistance: Double) {
        self.index = index
        self.startTime = startTime
        self.endTime = endTime
        self.startDistance = startDistance
        self.endDistance = endDistance
    }
}

/// Führt durch ein Trainingsprogramm. Reine Logik ohne Uhr: Eingang sind Ruderzeit, Uhrzeit seit Start,
/// Distanz und Geschwindigkeit der Fahrt (etwa jede Sekunde oder öfter), Ausgang ist `PlanStatus`.
///
/// Trainingsuhr: Belastung, Einrudern und Ausrudern zählen die Ruderzeit (hält man an, wartet die Phase).
/// Pausen (`kind == .rest`) zählen die Uhrzeit, damit sie auch im Stillstand ablaufen.
/// Die Geschwindigkeit wird geglättet (Zeitkonstante `speedTau`); sie dient nur für Schätzungen
/// (Countdown bei Distanzphasen, Tor bei Zeitphasen).
public struct PlanEngine: Sendable {
    public static let countdownSeconds: Double = 10

    public let plan: WorkoutPlan
    public let best2k: Double
    /// Zeitkonstante der Geschwindigkeitsglättung (s)
    public var speedTau: Double = 4

    public private(set) var index = 0
    public private(set) var phaseStartTime: Double = 0
    public private(set) var phaseStartDistance: Double = 0
    /// Trainingsuhr (s)
    public private(set) var planTime: Double = 0
    public private(set) var distance: Double = 0
    /// geglättete Geschwindigkeit (m/s); nil vor dem ersten Messwert
    public private(set) var speedEstimate: Double?
    public private(set) var finished = false
    public private(set) var boundaries: [PhaseBoundary] = []

    private var lastActive: Double?
    private var lastElapsed: Double?
    /// geschätzte Dauer je Phase (Gewicht für den Gesamtfortschritt)
    private let weights: [Double]
    private let totalWeight: Double

    public var phases: [WorkoutPhase] { plan.phases }

    public init(plan: WorkoutPlan, best2k: Double = PaceTargets.defaultBest2k) {
        self.plan = plan
        self.best2k = best2k
        let w = plan.phases.map { max($0.estimatedSeconds(best2k: best2k), 1) }
        weights = w
        totalWeight = w.reduce(0, +)
        finished = plan.phases.isEmpty
    }

    // MARK: Eingang

    /// Neuer Stand der Fahrt. Werte sind kumuliert seit Start der Fahrt; Rückschritte werden ignoriert.
    @discardableResult
    public mutating func update(activeTime: Double, elapsedTime: Double, distance d: Double,
                                speed: Double) -> PlanStatus {
        let dA = max(activeTime - (lastActive ?? 0), 0)
        let dE = max(elapsedTime - (lastElapsed ?? 0), 0)
        lastActive = max(activeTime, lastActive ?? 0)
        lastElapsed = max(elapsedTime, lastElapsed ?? 0)
        let newDistance = d.isFinite ? max(d, distance) : distance
        guard !finished else {
            distance = newDistance
            return status
        }
        let prevTime = planTime
        let prevDistance = distance
        let dt = phases[index].countsWallTime ? dE : dA
        planTime += dt
        distance = newDistance

        // Geschwindigkeit glätten (nur wenn die Trainingsuhr läuft; im Halt bleibt die letzte Schätzung)
        if dt > 0 {
            let v = speed.isFinite ? max(speed, 0) : 0
            if let e = speedEstimate {
                speedEstimate = e + (v - e) * (1 - exp(-dt / max(speedTau, 0.1)))
            } else if v > 0.3 {
                speedEstimate = v
            }
        }

        // Phasenwechsel (auch mehrere in einem Schritt)
        func clamp01(_ x: Double) -> Double { min(max(x, 0), 1) }
        while index < phases.count {
            let p = phases[index]
            if let dur = p.durationS {
                let end = phaseStartTime + dur
                guard planTime >= end - 1e-9 else { break }
                let f = planTime > prevTime ? clamp01((end - prevTime) / (planTime - prevTime)) : 1
                let dAtEnd = max(prevDistance + (newDistance - prevDistance) * f, phaseStartDistance)
                advance(endTime: end, endDistance: dAtEnd)
            } else if let len = p.distanceM {
                let end = phaseStartDistance + len
                guard newDistance >= end - 1e-9 else { break }
                let f = newDistance > prevDistance ? clamp01((end - prevDistance) / (newDistance - prevDistance)) : 1
                let tAtEnd = max(prevTime + (planTime - prevTime) * f, phaseStartTime)
                advance(endTime: tAtEnd, endDistance: end)
            } else {
                advance(endTime: phaseStartTime, endDistance: phaseStartDistance)
            }
        }
        if index >= phases.count {
            finished = true
            index = max(phases.count - 1, 0)
        }
        return status
    }

    /// Testteil vorzeitig beenden (docs/schwelle/SPEC.md 3.1/3.2/3.5): Rampe nicht mehr gehalten (`endOnFailure`),
    /// Stufentest „Schwelle erreicht“ oder Knopf „zu anstrengend“. Die laufende Phase endet jetzt; folgende Phasen mit
    /// `endOnFailure` bzw. Testrolle werden übersprungen (Länge 0), weiter geht es mit der nächsten anderen Phase
    /// (Ausrudern). Liefert true, wenn gesprungen wurde.
    @discardableResult
    public mutating func endTestPart() -> Bool {
        guard !finished, phases.indices.contains(index) else { return false }
        let cur = phases[index]
        guard cur.endOnFailure == true || cur.testRole != nil else { return false }
        advance(endTime: planTime, endDistance: distance)
        while index < phases.count, phases[index].endOnFailure == true || phases[index].testRole != nil {
            advance(endTime: planTime, endDistance: distance)
        }
        if index >= phases.count {
            finished = true
            index = max(phases.count - 1, 0)
        }
        return true
    }

    private mutating func advance(endTime: Double, endDistance: Double) {
        boundaries.append(PhaseBoundary(index: index, startTime: phaseStartTime, endTime: endTime,
                                        startDistance: phaseStartDistance, endDistance: endDistance))
        phaseStartTime = endTime
        phaseStartDistance = endDistance
        index += 1
    }

    // MARK: Ausgang

    /// Geschwindigkeit für Schätzungen: geglätteter Messwert, sonst das Zieltempo der Phase
    private func predictionSpeed(_ p: WorkoutPhase) -> Double {
        if let s = speedEstimate { return s }
        return p.estimatedSpeed(best2k: best2k)
    }

    public var status: PlanStatus {
        guard !phases.isEmpty else {
            return PlanStatus(phaseIndex: 0, phaseCount: 0, phase: nil, nextPhase: nil, phaseProgress: 1,
                              remainingTime: nil, remainingDistance: nil, secondsToChange: nil,
                              countdownActive: false, nextChangeDistance: nil, nextChangeIsExact: false,
                              overallProgress: 1, estimatedRemaining: 0, finished: true)
        }
        let p = phases[index]
        let next = index + 1 < phases.count ? phases[index + 1] : nil
        if finished {
            return PlanStatus(phaseIndex: index, phaseCount: phases.count, phase: p, nextPhase: nil, phaseProgress: 1,
                              remainingTime: p.isTimed ? 0 : nil, remainingDistance: p.isTimed ? nil : 0,
                              secondsToChange: nil, countdownActive: false, nextChangeDistance: nil,
                              nextChangeIsExact: false, overallProgress: 1, estimatedRemaining: 0, finished: true)
        }
        let speed = predictionSpeed(p)
        var progress = 0.0
        var remTime: Double?
        var remDist: Double?
        var toChange: Double?
        var changeAt: Double?
        var exact = false
        if let dur = p.durationS {
            let r = max(phaseStartTime + dur - planTime, 0)
            remTime = r
            progress = dur > 0 ? 1 - r / dur : 1
            toChange = r
            changeAt = distance + r * speed
        } else if let len = p.distanceM {
            let r = max(phaseStartDistance + len - distance, 0)
            remDist = r
            progress = len > 0 ? 1 - r / len : 1
            toChange = speed > 0.3 ? r / speed : nil
            changeAt = phaseStartDistance + len
            exact = true
        }
        progress = min(max(progress, 0), 1)
        let done = weights[..<index].reduce(0, +)
        let overall = totalWeight > 0 ? min((done + weights[index] * progress) / totalWeight, 1) : 0
        let later = weights[(index + 1)...].reduce(0, +)
        let currentLeft = toChange ?? weights[index] * (1 - progress)
        let countdown = toChange.map { $0 > 0 && $0 <= Self.countdownSeconds } ?? false
        return PlanStatus(phaseIndex: index, phaseCount: phases.count, phase: p, nextPhase: next,
                          phaseProgress: progress, remainingTime: remTime, remainingDistance: remDist,
                          secondsToChange: toChange, countdownActive: countdown, nextChangeDistance: changeAt,
                          nextChangeIsExact: exact, overallProgress: overall,
                          estimatedRemaining: currentLeft + later, finished: false)
    }

    /// Relativer Anteil jeder Phase an der geschätzten Gesamtdauer (für Phasenleisten), Summe 1
    public var phaseShares: [Double] {
        totalWeight > 0 ? weights.map { $0 / totalWeight } : weights.map { _ in 0 }
    }
}

/// Beginn einer Phase während der Fahrt (Uhrzeit seit Start der Fahrt, wie `WorkoutSample.time`).
public struct PlanPhaseMark: Codable, Equatable, Sendable {
    public var index: Int
    public var startTime: Double
    public var startDistance: Double

    public init(index: Int, startTime: Double, startDistance: Double) {
        self.index = index
        self.startTime = startTime
        self.startDistance = startDistance
    }
}

/// Werte je Phase eines Trainings (im gespeicherten Training, für die Zusammenfassung).
public struct PlanPhaseResult: Codable, Equatable, Sendable, Identifiable {
    public var index: Int
    /// Phasenart als Text (unbekannte Werte aus neueren Versionen bleiben lesbar)
    public var kind: String
    public var label: String
    /// Sekunden seit Start der Fahrt (Uhrzeit, wie `WorkoutSample.time`)
    public var startTime: Double
    public var endTime: Double
    public var startDistance: Double
    public var endDistance: Double
    public var averageStrokeRate: Double?
    public var averageHeartRate: Int?
    /// false = Phase wurde nicht zu Ende gerudert (Training vorzeitig beendet)
    public var completed: Bool

    public var id: Int { index }
    public var phaseKind: WorkoutPhase.Kind { WorkoutPhase.Kind(rawValue: kind) ?? .other }
    public var duration: Double { max(endTime - startTime, 0) }
    public var distance: Double { max(endDistance - startDistance, 0) }
    /// s/500 m über die Uhrzeit der Phase; nil bei weniger als 10 m
    public var averagePace: Double? { distance >= 10 ? duration / distance * 500 : nil }

    public init(index: Int, kind: String, label: String, startTime: Double, endTime: Double, startDistance: Double,
                endDistance: Double, averageStrokeRate: Double?, averageHeartRate: Int?, completed: Bool) {
        self.index = index
        self.kind = kind
        self.label = label
        self.startTime = startTime
        self.endTime = endTime
        self.startDistance = startDistance
        self.endDistance = endDistance
        self.averageStrokeRate = averageStrokeRate
        self.averageHeartRate = averageHeartRate
        self.completed = completed
    }

    /// Ergebnisse aus den Phasenanfängen und der Zeitreihe. Die letzte begonnene Phase endet bei `endTime`;
    /// sie gilt als abgeschlossen, wenn `planFinished` true ist.
    public static func compute(plan: WorkoutPlan, marks: [PlanPhaseMark], samples: [WorkoutSample],
                               endTime: Double, endDistance: Double, planFinished: Bool) -> [PlanPhaseResult] {
        let sorted = marks.filter { $0.index >= 0 && $0.index < plan.phases.count }.sorted { $0.index < $1.index }
        var out: [PlanPhaseResult] = []
        for (i, m) in sorted.enumerated() {
            let last = i + 1 >= sorted.count
            let tEnd = last ? max(endTime, m.startTime) : sorted[i + 1].startTime
            let dEnd = last ? max(endDistance, m.startDistance) : sorted[i + 1].startDistance
            let inPhase = samples.filter { $0.time >= m.startTime && $0.time < tEnd }
            let rowing = inPhase.filter { $0.strokeRate > 0 }
            let spm = rowing.isEmpty ? nil : Double(rowing.reduce(0) { $0 + $1.strokeRate }) / Double(rowing.count)
            let hrs = inPhase.compactMap(\.heartRate)
            let hr = hrs.isEmpty ? nil : Int((Double(hrs.reduce(0, +)) / Double(hrs.count)).rounded())
            let p = plan.phases[m.index]
            out.append(PlanPhaseResult(index: m.index, kind: p.kind.rawValue, label: p.title, startTime: m.startTime,
                                       endTime: tEnd, startDistance: m.startDistance, endDistance: dEnd,
                                       averageStrokeRate: spm, averageHeartRate: hr,
                                       completed: !last || planFinished))
        }
        return out
    }
}
