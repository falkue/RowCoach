import Foundation

// Auswertung und Regeln rund um eine Fahrt (UX-Überarbeitung, docs/design/ux-synthese.md):
// Mindestlänge fürs Speichern, Härte einer Phase (Phasenleiste), Auswertung je Intervall mit Ampel gegenüber dem
// Ziel (Zusammenfassung), Ansagen-Zeitpunkte (gesprochene Ansagen) und die gemeinsame Quellenliste der Strecken.

// MARK: - Mindestlänge

/// Kurzfahrten (Testtipps, versehentliche Starts) kommen nicht in den Verlauf.
public enum RideSaveRule {
    /// Unter dieser Distanz (m) wird nicht gespeichert
    public static let minimumDistance: Double = 100
    /// Unter dieser Ruderzeit (s) wird nicht gespeichert
    public static let minimumDuration: TimeInterval = 60

    /// true = Fahrt speichern (mindestens 100 m und mindestens 1 min Ruderzeit)
    public static func shouldKeep(distance: Double, activeDuration: TimeInterval) -> Bool {
        distance.isFinite && activeDuration.isFinite
            && distance >= minimumDistance && activeDuration >= minimumDuration
    }

    public static func shouldKeep(_ summary: WorkoutSummary) -> Bool {
        shouldKeep(distance: summary.distance, activeDuration: summary.activeDuration)
    }
}

// MARK: - Härte einer Phase

/// Härte einer Trainingsphase für die Phasenleiste: leicht, mittel, hart oder Pause.
public enum PhaseIntensity: String, Sendable, CaseIterable, Equatable {
    case easy, moderate, hard, rest

    public var title: String {
        switch self {
        case .easy: return String(localized: "leicht")
        case .moderate: return String(localized: "mittel")
        case .hard: return String(localized: "hart")
        case .rest: return String(localized: "Pause")
        }
    }
}

extension WorkoutPhase {
    /// Härte aus Zielzone und Zieltempo (die härtere der beiden Angaben):
    /// - Zone ≥ 4 hart, Zone 3 mittel, sonst leicht
    /// - Tempo (Mitte des Zielbereichs) höchstens 5 s langsamer als das 2000-m-Tempo hart, höchstens 18 s mittel,
    ///   sonst leicht
    /// - ohne Ziel: Intervall mittel, alle anderen leicht. Pausen sind immer `.rest`.
    public func intensity() -> PhaseIntensity {
        if kind == .rest { return .rest }
        var levels: [PhaseIntensity] = []
        if let z = hrZone { levels.append(z >= 4 ? .hard : (z == 3 ? .moderate : .easy)) }
        if let a = paceOffsetMinS ?? paceOffsetMaxS {
            let b = paceOffsetMaxS ?? a
            let mid = (a + b) / 2
            levels.append(mid <= 5 ? .hard : (mid <= 18 ? .moderate : .easy))
        }
        if levels.isEmpty { return kind == .work ? .moderate : .easy }
        if levels.contains(.hard) { return .hard }
        if levels.contains(.moderate) { return .moderate }
        return .easy
    }
}

extension WorkoutPlan {
    /// Nummer des Intervalls (1, 2, …) unter den Intervallen des Programms; nil, wenn die Phase kein Intervall ist
    public func workNumber(at index: Int) -> Int? {
        guard phases.indices.contains(index), phases[index].kind == .work else { return nil }
        return phases[..<index].filter { $0.kind == .work }.count + 1
    }
}

// MARK: - Auswertung je Phase

/// Ergebnis einer Phase mit Ampel gegenüber dem Ziel (Zusammenfassung, eine Zeile je Phase bzw. je Intervall).
public struct IntervalResult: Equatable, Sendable, Identifiable {
    /// Index der Phase im Programm
    public var index: Int
    public var kind: WorkoutPhase.Kind
    public var label: String
    /// Nummer unter den Intervallen (1, 2, …), nil bei anderen Phasen
    public var workNumber: Int?
    public var duration: Double
    public var distance: Double
    /// s/500 m
    public var averagePace: Double?
    public var averageStrokeRate: Double?
    public var averagePower: Int?
    public var averageHeartRate: Int?
    public var targetPace: ClosedRange<Double>?
    public var targetStrokeRate: ClosedRange<Int>?
    public var paceLight: TargetLight
    public var strokeRateLight: TargetLight
    public var completed: Bool

    public var id: Int { index }

    /// Gesamtampel: die schlechtere von Tempo und Schlagzahl (`.none`, wenn keines ein Ziel hat)
    public var overallLight: TargetLight { IntervalEvaluation.worse(paceLight, strokeRateLight) }
}

public enum IntervalEvaluation {
    /// Eine Zeile je gefahrener Phase (aus `record.planPhases`). Ziele kommen aus dem Programm (falls bekannt),
    /// Leistung aus der Zeitreihe (Ø der Messpunkte mit Schlag). Pausen bekommen keine Ampel.
    public static func evaluate(record: WorkoutRecord, plan: WorkoutPlan?, best2k: Double) -> [IntervalResult] {
        guard let phases = record.planPhases else { return [] }
        return phases.map { p -> IntervalResult in
            let planPhase = plan.flatMap { $0.phases.indices.contains(p.index) ? $0.phases[p.index] : nil }
            let kind = planPhase?.kind ?? p.phaseKind
            let inPhase = record.samples.filter { $0.time >= p.startTime && $0.time < p.endTime && $0.strokeRate > 0 }
            let power = inPhase.isEmpty ? nil
                : Int((Double(inPhase.reduce(0) { $0 + $1.power }) / Double(inPhase.count)).rounded())
            let targetPace = kind == .rest ? nil : planPhase?.paceRange(best2k: best2k)
            let targetSpm = kind == .rest ? nil : planPhase?.spmRange
            let paceLight = TargetLight.pace(p.averagePace ?? 0, target: targetPace)
            let spmLight = TargetLight.strokeRate(Int((p.averageStrokeRate ?? 0).rounded()), target: targetSpm)
            return IntervalResult(index: p.index, kind: kind, label: p.label,
                                  workNumber: plan?.workNumber(at: p.index), duration: p.duration,
                                  distance: p.distance, averagePace: p.averagePace,
                                  averageStrokeRate: p.averageStrokeRate, averagePower: power,
                                  averageHeartRate: p.averageHeartRate, targetPace: targetPace,
                                  targetStrokeRate: targetSpm, paceLight: paceLight, strokeRateLight: spmLight,
                                  completed: p.completed)
        }
    }

    /// Schlechtere von zwei Ampeln (rot vor gelb vor grün vor keiner)
    public static func worse(_ a: TargetLight, _ b: TargetLight) -> TargetLight {
        func rank(_ l: TargetLight) -> Int {
            switch l {
            case .none: return 0
            case .green: return 1
            case .yellow: return 2
            case .red: return 3
            }
        }
        return rank(a) >= rank(b) ? a : b
    }
}

// MARK: - Zeitpunkte der Ansagen

/// Anlass für eine gesprochene Ansage während der Fahrt. Die App macht daraus den Text (lokalisierbar).
public enum CoachCue: Equatable, Sendable {
    /// etwa 10 s vor dem Phasenwechsel; `next` nil = danach ist das Training zu Ende
    case countdown(seconds: Int, next: WorkoutPhase?, nextIndex: Int)
    /// neue Phase hat begonnen
    case phaseStarted(phase: WorkoutPhase, index: Int)
    /// Hälfte des Trainings bzw. der Strecke
    case halfway
    /// noch so viele Meter bis zum Ziel (freies Rudern)
    case remaining(meters: Int)
    /// Training geschafft
    case finished
}

/// Erkennt aus dem Stand der Fahrt, wann eine Ansage fällig ist. Jede Ansage kommt höchstens einmal.
public struct CoachCueDetector: Sendable {
    /// Countdown-Ansage nur, wenn noch mindestens so viele Sekunden bleiben (sonst käme sie zu spät)
    public static let minimumCountdownSeconds: Double = 4
    /// „Noch … Meter“ beim freien Rudern
    public static let remainingMarks: [Int] = [500]

    private var lastIndex: Int?
    private var countdownFor: Int?
    private var halfwayDone = false
    private var finishedDone = false
    private var remainingDone: Set<Int> = []
    private var lastDistance: Double?

    public init() {}

    /// Training: neuer `PlanStatus` (bei jeder Änderung)
    public mutating func update(status: PlanStatus) -> [CoachCue] {
        var cues: [CoachCue] = []
        if status.finished {
            if !finishedDone {
                finishedDone = true
                cues.append(.finished)
            }
            lastIndex = status.phaseIndex
            return cues
        }
        if let last = lastIndex, status.phaseIndex != last, let p = status.phase {
            cues.append(.phaseStarted(phase: p, index: status.phaseIndex))
        }
        lastIndex = status.phaseIndex
        if status.countdownActive, countdownFor != status.phaseIndex, let s = status.secondsToChange,
           s >= Self.minimumCountdownSeconds {
            countdownFor = status.phaseIndex
            cues.append(.countdown(seconds: Int(s.rounded()), next: status.nextPhase,
                                   nextIndex: status.phaseIndex + 1))
        }
        if !halfwayDone, status.overallProgress >= 0.5 {
            halfwayDone = true
            // nicht gleichzeitig mit einem Phasenwechsel ansagen (der hat Vorrang)
            if cues.isEmpty { cues.append(.halfway) }
        }
        return cues
    }

    /// Freies Rudern auf einer Strecke mit Länge `total` (m)
    public mutating func update(distance: Double, total: Double) -> [CoachCue] {
        guard total > 0, distance.isFinite else { return [] }
        defer { lastDistance = distance }
        var cues: [CoachCue] = []
        guard let prev = lastDistance else { return [] }
        if !halfwayDone, prev < total / 2, distance >= total / 2 {
            halfwayDone = true
            cues.append(.halfway)
        }
        for mark in Self.remainingMarks where !remainingDone.contains(mark) && total >= Double(mark) * 2 {
            let at = total - Double(mark)
            if prev < at, distance >= at, distance < total {
                remainingDone.insert(mark)
                cues.append(.remaining(meters: mark))
            }
        }
        return cues
    }
}

// MARK: - Quellen

/// Gemeinsame Quellenliste aus den `attribution`-Feldern der Strecken: Teile (getrennt durch „;“) ohne Doppelte,
/// in der Reihenfolge ihres ersten Auftretens.
public enum AttributionList {
    public static func merge(_ texts: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for text in texts {
            for part in text.components(separatedBy: ";") {
                let p = part.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !p.isEmpty, seen.insert(p).inserted else { continue }
                out.append(p)
            }
        }
        return out
    }
}
