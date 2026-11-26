import Foundation

/// Szenarien des Sprachcoachs (ids fest, wie in docs/coach/SPEC.md und coach_phrases.json).
public enum CoachScenario: String, Codable, Sendable, CaseIterable {
    // planbasiert
    case prepHard = "prep_hard"
    case go
    case firstStrokes = "first_strokes"
    case phaseHalf = "phase_half"
    case lastQuarter = "last_quarter"
    case last30s = "last_30s"
    case last10s = "last_10s"
    case last250m = "last_250m"
    case last100m = "last_100m"
    case lastInterval = "last_interval"
    case intervalDone = "interval_done"
    case restRecover = "rest_recover"
    case restPrepare = "rest_prepare"
    case workoutHalf = "workout_half"
    case workoutFinal = "workout_final"
    case workoutDone = "workout_done"
    // adaptiv
    case fadeEnd = "fade_end"
    case fadeMid = "fade_mid"
    case rateLow = "rate_low"
    case rateHigh = "rate_high"
    case paceOnTarget = "pace_on_target"
    case paceTooFastEarly = "pace_too_fast_early"
    case paceSlow = "pace_slow"
    case strongFinish = "strong_finish"
    case consistent
    case slowerThanPrev = "slower_than_prev"
    case bestInterval = "best_interval"
    case hrHighEasy = "hr_high_easy"
    case stopped
    case restTooHard = "rest_too_hard"
    case technique
    // freies Rudern
    case freeHalf = "free_half"
    case free500Left = "free_500_left"
    case paceLineAhead = "paceline_ahead"
    case paceLineBehind = "paceline_behind"

    /// Gruppe für Priorität, Budget und Ruhezonen
    public var category: CoachCategory {
        switch self {
        case .go, .lastInterval, .workoutHalf, .workoutDone, .freeHalf, .free500Left, .last10s:
            return .phase
        case .stopped:
            return .safety
        case .fadeEnd, .last30s, .last250m, .last100m, .workoutFinal:
            return .endPush
        case .fadeMid, .rateLow, .rateHigh, .paceSlow, .paceTooFastEarly, .hrHighEasy, .restTooHard:
            return .correction
        case .prepHard, .restPrepare, .restRecover, .firstStrokes:
            return .prep
        case .phaseHalf, .lastQuarter, .intervalDone, .consistent, .slowerThanPrev, .bestInterval, .paceOnTarget,
             .strongFinish, .paceLineAhead, .paceLineBehind:
            return .praise
        case .technique:
            return .technique
        }
    }

    /// Zählt nicht zum Budget nach Häufigkeit (Gruppe ausgenommen, Vorbereitung auf die nächste Belastung oder
    /// Rückmeldung zum gerade beendeten Intervall – beides einmal je Phase)
    public var budgetExempt: Bool {
        category.budgetExempt || self == .prepHard || self == .restPrepare || isIntervalFeedback
    }

    /// Rückmeldung am Ende einer Belastung (`interval_done` oder ein Vergleich)
    public var isIntervalFeedback: Bool {
        self == .intervalDone || self == .consistent || self == .slowerThanPrev || self == .bestInterval
    }
}

/// Gruppen der Ansagen. Priorität nach SPEC: Sicherheit/Info > Phasenwechsel > Korrektur am Ende > Vorbereitung
/// > Lob > Technik; Korrekturen mitten in der Phase liegen zwischen „Korrektur am Ende“ und „Vorbereitung“.
public enum CoachCategory: String, Sendable, CaseIterable {
    /// Informationsansage aus `CoachCueDetector` (Phasenwechsel, Countdown, Halbzeit, Ziel)
    case info
    /// Phasenwechsel-Rufe des Coachs (`go`, `last_interval`, `workout_done` …), ersetzen die Info-Ansage
    case phase
    /// `stopped` (in Belastung stehen geblieben)
    case safety
    /// Korrektur und Anfeuern am Ende einer harten Phase
    case endPush
    case correction
    case prep
    case praise
    case technique

    public var priority: CoachPriority {
        switch self {
        case .info: return CoachPriority(100)
        case .safety: return CoachPriority(95)
        case .phase: return CoachPriority(90)
        case .endPush: return CoachPriority(70)
        case .correction: return CoachPriority(60)
        case .prep: return CoachPriority(50)
        case .praise: return CoachPriority(40)
        case .technique: return CoachPriority(20)
        }
    }

    /// Zählt nicht zum Budget nach Häufigkeit (Information, Struktur, Sicherheit, Ende einer harten Phase,
    /// Vorbereitung auf die nächste Belastung)
    var budgetExempt: Bool {
        switch self {
        case .info, .phase, .safety, .endPush: return true
        case .prep, .correction, .praise, .technique: return false
        }
    }
}

/// Priorität einer Ansage (grösser = wichtiger)
public struct CoachPriority: Comparable, Hashable, Sendable {
    public var value: Int
    public init(_ value: Int) { self.value = value }
    public static func < (a: CoachPriority, b: CoachPriority) -> Bool { a.value < b.value }

    public static let info = CoachCategory.info.priority
    public static let phase = CoachCategory.phase.priority
}
