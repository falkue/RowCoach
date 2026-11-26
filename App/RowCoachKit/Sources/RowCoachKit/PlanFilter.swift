import Foundation

// Filter und Einordnung der Trainingsprogramme (rund 100 Programme, docs/plans-new/BRIEF.md).
// Portabel (nur Foundation), damit die Android-Hülle dieselben Filter nutzt.

/// Feste Schlagworte in plans.json (`tags`)
public enum PlanTag {
    /// Intensität: genau eins je Programm
    public static let intensities = ["easy", "moderate", "hard", "max"]
    /// Energiesystem bzw. Fokus
    public static let focuses = ["aerobic", "threshold", "vo2max", "anaerobic", "power", "technique", "recovery"]
    /// Form des Programms
    public static let forms = ["pyramid", "ladder", "rate-ladder", "rate-cap", "progressive", "negative-split", "fartlek",
                               "over-under", "race-pace", "benchmark", "c2-ranked", "beginner-friendly", "time-efficient"]
    public static let all = Set(intensities + focuses + forms)
}

/// Intensität eines Programms (aus den Tags)
public enum PlanIntensity: String, CaseIterable, Sendable, Identifiable, Comparable {
    case easy, moderate, hard, max
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .easy: return String(localized: "Leicht")
        case .moderate: return String(localized: "Mittel")
        case .hard: return String(localized: "Hart")
        case .max: return String(localized: "Maximal")
        }
    }

    private var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    public static func < (a: Self, b: Self) -> Bool { a.rank < b.rank }
}

/// Wonach das Programm gesteuert wird
public enum PlanMetric: String, CaseIterable, Sendable, Identifiable {
    /// alle Belastungsphasen nach Zeit
    case time
    /// alle Belastungsphasen nach Distanz
    case distance
    /// gemischt
    case mixed
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .time: return String(localized: "Nach Zeit")
        case .distance: return String(localized: "Nach Distanz")
        case .mixed: return String(localized: "Gemischt")
        }
    }
}

/// Dauerklasse nach geschätzter Gesamtdauer
public enum PlanDurationClass: String, CaseIterable, Sendable, Identifiable {
    /// bis 30 min
    case short
    /// über 30 bis unter 60 min
    case medium
    /// ab 60 min
    case long
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .short: return String(localized: "Bis 30 min")
        case .medium: return String(localized: "30–60 min")
        case .long: return String(localized: "Ab 60 min")
        }
    }

    public static func of(seconds: Double) -> PlanDurationClass {
        seconds <= 30 * 60 + 1 ? .short : (seconds < 60 * 60 - 1 ? .medium : .long)
    }
}

extension WorkoutPlan {
    public var intensity: PlanIntensity? {
        tags.lazy.compactMap(PlanIntensity.init(rawValue:)).max()
    }

    /// Nach Zeit oder Distanz: entscheidend sind die Belastungsphasen (Ein- und Ausrudern zählen nicht)
    public var metric: PlanMetric {
        let work = phases.filter { $0.kind == .work }
        let relevant = work.isEmpty ? phases : work
        if relevant.allSatisfy(\.isTimed) { return .time }
        if relevant.allSatisfy({ !$0.isTimed }) { return .distance }
        return .mixed
    }

    public func durationClass(best2k: Double) -> PlanDurationClass {
        .of(seconds: estimatedDuration(best2k: best2k))
    }

    public func hasTag(_ t: String) -> Bool { tags.contains(t) }
}

/// Auswahl in der Programmliste; leere Werte = kein Filter
public struct PlanFilter: Equatable, Sendable {
    public var level = ""
    public var category = ""
    public var intensity: PlanIntensity?
    public var metric: PlanMetric?
    public var duration: PlanDurationClass?
    /// Freitext: Name, Kurzbeschreibung, Zweck, Art
    public var text = ""

    public init(level: String = "", category: String = "", intensity: PlanIntensity? = nil, metric: PlanMetric? = nil,
                duration: PlanDurationClass? = nil, text: String = "") {
        self.level = level
        self.category = category
        self.intensity = intensity
        self.metric = metric
        self.duration = duration
        self.text = text
    }

    public var isActive: Bool {
        !level.isEmpty || !category.isEmpty || intensity != nil || metric != nil || duration != nil
            || !text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public func matches(_ p: WorkoutPlan, best2k: Double) -> Bool {
        if !level.isEmpty && p.level != level { return false }
        if !category.isEmpty && p.category != category { return false }
        if let intensity, p.intensity != intensity { return false }
        if let metric, p.metric != metric { return false }
        if let duration, p.durationClass(best2k: best2k) != duration { return false }
        let q = text.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            let hay = [p.name, p.summary, p.purpose, p.category, p.id].joined(separator: " ")
            let words = q.split(whereSeparator: \.isWhitespace)
            for w in words where hay.range(of: w, options: [.caseInsensitive, .diacriticInsensitive]) == nil {
                return false
            }
        }
        return true
    }

    public func apply(_ plans: [WorkoutPlan], best2k: Double) -> [WorkoutPlan] {
        plans.filter { matches($0, best2k: best2k) }
    }
}
