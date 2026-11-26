import Foundation

// Trainingspläne über mehrere Wochen (`training_plans.json` im App-Bundle; Regeln: docs/trainingsplaene/RECHERCHE.md,
// Kapitel 5; Umsetzung: docs/trainingsplaene/UMSETZUNG.md). Ein Plan ordnet Programme aus `plans.json` (per id)
// Wochen und Einheiten zu. Nur Foundation, damit die Android-Hülle dieselbe Logik nutzt.

/// Was mit einer verpassten Einheit geschieht, wenn sie sich in der Woche nicht verschieben lässt (RECHERCHE 5.2)
public enum MissedSessionPolicy: String, Codable, Sendable, CaseIterable {
    /// Einsteiger, Pete-artig: nachrücken, die Woche wird um höchstens 2 Tage länger
    case shift
    /// Masters, Wiedereinstieg, Wettkampf: fällt weg
    case skip
    /// Leistungs-/Testpläne: harte Einheit durch leichte Grundlage ersetzen, sonst streichen
    case replaceEasy = "replace-easy"
}

/// Regeln eines Plans (`rules`); fehlende Werte bekommen die Standards der Recherche
public struct ProgramRules: Equatable, Sendable {
    /// jede n-te Woche leichter (nur Information; die Wochen tragen `deload` selbst)
    public var deloadEvery: Int?
    /// höchstens so viele Trainingstage hintereinander (Einsteiger 1 = immer ein Ruhetag dazwischen)
    public var maxConsecutiveDays: Int
    /// Mindestabstand zwischen harten Einheiten (h); 48, Masters 72
    public var hardSessionsMinGapHours: Int
    public var missedSessionPolicy: MissedSessionPolicy
    /// Woche mit Schlusstest
    public var retestWeek: Int?
    /// offener Plan: läuft nach der letzten Woche ab dieser Woche weiter
    public var repeatFrom: Int?
    /// Einsteiger: fehlen so viele Pflicht-Einheiten einer Woche, wird die Woche wiederholt
    public var repeatWeekIfMissed: Int?
    /// Woche mit Zwischentest
    public var interimTestWeek: Int?

    public init(deloadEvery: Int? = nil, maxConsecutiveDays: Int = 2, hardSessionsMinGapHours: Int = 48,
                missedSessionPolicy: MissedSessionPolicy = .shift, retestWeek: Int? = nil, repeatFrom: Int? = nil,
                repeatWeekIfMissed: Int? = nil, interimTestWeek: Int? = nil) {
        self.deloadEvery = deloadEvery
        self.maxConsecutiveDays = max(1, maxConsecutiveDays)
        self.hardSessionsMinGapHours = max(0, hardSessionsMinGapHours)
        self.missedSessionPolicy = missedSessionPolicy
        self.retestWeek = retestWeek
        self.repeatFrom = repeatFrom
        self.repeatWeekIfMissed = repeatWeekIfMissed
        self.interimTestWeek = interimTestWeek
    }

    /// Mindestabstand harter Einheiten in Kalendertagen (48 h → 2, 72 h → 3)
    public var hardGapDays: Int { max(1, Int((Double(hardSessionsMinGapHours) / 24).rounded(.up))) }
}

extension ProgramRules: Decodable {
    enum CodingKeys: String, CodingKey {
        case deloadEvery, maxConsecutiveDays, hardSessionsMinGapHours, missedSessionPolicy, retestWeek, repeatFrom,
             repeatWeekIfMissed, interimTestWeek
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let policy = c.lenientString(.missedSessionPolicy).flatMap {
            MissedSessionPolicy(rawValue: $0.trimmingCharacters(in: .whitespaces).lowercased())
        }
        self.init(deloadEvery: c.lenientInt(.deloadEvery),
                  maxConsecutiveDays: c.lenientInt(.maxConsecutiveDays) ?? 2,
                  hardSessionsMinGapHours: c.lenientInt(.hardSessionsMinGapHours) ?? 48,
                  missedSessionPolicy: policy ?? .shift,
                  retestWeek: c.lenientInt(.retestWeek),
                  repeatFrom: c.lenientInt(.repeatFrom),
                  repeatWeekIfMissed: c.lenientInt(.repeatWeekIfMissed),
                  interimTestWeek: c.lenientInt(.interimTestWeek))
    }
}

/// Eine Einheit einer Planwoche
public struct ProgramSession: Equatable, Sendable {
    /// Reihenfolge in der Woche (1…)
    public var slot: Int
    /// Programm aus plans.json
    public var planId: String
    /// freiwillige Einheit
    public var optional: Bool
    public var intensity: PlanIntensity
    /// Hinweis zur Einheit (in der Sprache der App)
    public var note: String
    /// Zieleinheit des Plans (Schlusstest oder Rennen): wird verschoben, nie gestrichen
    public var event: Bool

    public init(slot: Int, planId: String, optional: Bool = false, intensity: PlanIntensity = .easy, note: String = "",
                event: Bool = false) {
        self.slot = slot
        self.planId = planId
        self.optional = optional
        self.intensity = intensity
        self.note = note
        self.event = event
    }

    public var isHard: Bool { intensity >= .hard }
}

extension ProgramSession: Decodable {
    enum CodingKeys: String, CodingKey { case slot, planId, optional, intensity, note, event }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.lenientString(.planId)?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .planId, in: c, debugDescription: "Einheit ohne planId")
        }
        let raw = c.lenientString(.intensity)?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        self.init(slot: c.lenientInt(.slot) ?? 0, planId: id, optional: c.lenientBool(.optional) ?? false,
                  intensity: PlanIntensity(rawValue: raw) ?? .easy,
                  note: c.localizedText(.note)?.resolved(languageCode: AppLocalization.languageCode) ?? "",
                  event: c.lenientBool(.event) ?? false)
    }
}

/// Eine Woche eines Plans
public struct ProgramWeek: Equatable, Sendable {
    public var week: Int
    public var focus: String
    /// leichtere Woche
    public var deload: Bool
    /// Tapering-Woche
    public var taper: Bool
    public var sessions: [ProgramSession]

    public init(week: Int, focus: String = "", deload: Bool = false, taper: Bool = false, sessions: [ProgramSession]) {
        self.week = week
        self.focus = focus
        self.deload = deload
        self.taper = taper
        self.sessions = sessions
    }

    public var required: [ProgramSession] { sessions.filter { !$0.optional } }
    public var optionals: [ProgramSession] { sessions.filter(\.optional) }
}

extension ProgramWeek: Decodable {
    enum CodingKeys: String, CodingKey { case week, focus, deload, taper, sessions }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var list = (try? c.decodeIfPresent([Lossy<ProgramSession>].self, forKey: .sessions))?.compactMap(\.value) ?? []
        // Slots fortlaufend 1…n in der Reihenfolge der Datei (fehlende oder doppelte Nummern stören nicht)
        for i in list.indices { list[i].slot = i + 1 }
        self.init(week: c.lenientInt(.week) ?? 0,
                  focus: c.localizedText(.focus)?.resolved(languageCode: AppLocalization.languageCode) ?? "",
                  deload: c.lenientBool(.deload) ?? false, taper: c.lenientBool(.taper) ?? false, sessions: list)
    }
}

/// Ein Trainingsplan über mehrere Wochen.
/// Das Dekodieren ist tolerant: unbekannte Felder werden ignoriert, Texte ein- oder zweisprachig, Zahlen auch als Text,
/// Einheiten ohne planId und Wochen ohne Einheiten fallen weg, Pläne ohne id oder ohne Wochen werden übersprungen.
public struct TrainingProgram: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var summary: String
    public var goal: String
    public var prerequisites: String
    /// Niveau in der Sprache der App und auf Deutsch (für Sortierung und Regeln)
    public var level: String
    public var levelID: String
    /// Kategorie-Kennung (`einstieg`, `fitness`, `grundlage`, `test-2k`, …), siehe `TrainingProgramCategory`
    public var category: String
    public var sessionsPerWeek: ClosedRange<Int>
    /// geschätzte Minuten pro Woche (kleinste Pflichtwoche … grösste Woche mit freiwilligen)
    public var minutesPerWeek: ClosedRange<Int>?
    /// `winter` oder nil
    public var season: String?
    public var rules: ProgramRules
    public var weekPlans: [ProgramWeek]
    public var sources: [PlanSource]
    public var evidence: String

    public init(id: String, name: String, summary: String = "", goal: String = "", prerequisites: String = "",
                level: String = "", category: String = "", sessionsPerWeek: ClosedRange<Int>? = nil,
                minutesPerWeek: ClosedRange<Int>? = nil, season: String? = nil, rules: ProgramRules = ProgramRules(),
                weekPlans: [ProgramWeek], sources: [PlanSource] = [], evidence: String = "") {
        self.id = id
        self.name = name
        self.summary = summary
        self.goal = goal
        self.prerequisites = prerequisites
        self.level = level
        self.levelID = level
        self.category = category
        self.weekPlans = weekPlans.enumerated().map { i, w in var w = w; w.week = i + 1; return w }
        let counts = weekPlans.map { $0.required.count }
        self.sessionsPerWeek = sessionsPerWeek ?? ((counts.min() ?? 0)...(counts.max() ?? 0))
        self.minutesPerWeek = minutesPerWeek
        self.season = season
        self.rules = rules
        self.sources = sources
        self.evidence = evidence
    }

    /// Zahl der Wochen
    public var weeks: Int { weekPlans.count }

    /// Woche 1…n; nil ausserhalb
    public func week(_ n: Int) -> ProgramWeek? {
        n >= 1 && n <= weekPlans.count ? weekPlans[n - 1] : nil
    }

    /// Belegart: „direkt“, „angepasst“ oder „abgeleitet“ (Teil vor dem Doppelpunkt)
    public var evidenceKind: String {
        evidence.split(separator: ":", maxSplits: 1).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    }

    /// Hat der Plan eigene Tests (Schlusstest, Zwischentest oder Test-Programme)? Dann ruht Regel 4 des Tagesvorschlags.
    public var hasOwnTest: Bool {
        rules.retestWeek != nil || rules.interimTestWeek != nil
            || weekPlans.contains { $0.sessions.contains { TrainingProgramEngine.isTestPlan($0.planId) } }
    }

    /// Alle Programm-ids des Plans (ohne Doppelte, in Reihenfolge des Auftretens)
    public var planIds: [String] {
        var seen = Set<String>()
        return weekPlans.flatMap(\.sessions).map(\.planId).filter { seen.insert($0).inserted }
    }

    /// Anzeige der Wochenklasse für Filter
    public var weekClass: ProgramWeekClass { ProgramWeekClass.of(weeks: weeks) }

    /// Geschätzte Minuten je Woche (Pflicht-Einheiten) mit den Zieltempi zur 2000-m-Bestzeit
    public func weekMinutes(workouts: [WorkoutPlan], best2k: Double) -> [Double] {
        let byId = Dictionary(workouts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return weekPlans.map { w in
            w.required.reduce(0) { $0 + (byId[$1.planId]?.estimatedDuration(best2k: best2k) ?? 0) } / 60
        }
    }
}

extension TrainingProgram: Decodable {
    enum CodingKeys: String, CodingKey {
        case id, name, summary, goal, prerequisites, level, category, sessionsPerWeek, minutesPerWeek, season, rules,
             weeksDetail = "weeks_detail", sources, evidence
    }

    private struct Range: Decodable {
        var min: Int?
        var max: Int?
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            min = c.lenientInt(.min)
            max = c.lenientInt(.max)
        }
        enum Keys: String, CodingKey { case min, max }
        var range: ClosedRange<Int>? {
            guard let a = min ?? max else { return nil }
            let b = max ?? a
            return Swift.min(a, b)...Swift.max(a, b)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.lenientString(.id)?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "Plan ohne id")
        }
        let weeks = ((try? c.decodeIfPresent([Lossy<ProgramWeek>].self, forKey: .weeksDetail))?.compactMap(\.value) ?? [])
            .filter { !$0.sessions.isEmpty }
        guard !weeks.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .weeksDetail, in: c, debugDescription: "Plan ohne Wochen")
        }
        let lang = AppLocalization.languageCode
        let lv = c.localizedText(.level)
        let season = c.lenientString(.season)?.trimmingCharacters(in: .whitespaces).lowercased()
        self.init(id: id,
                  name: c.localizedText(.name)?.resolved(languageCode: lang) ?? id,
                  summary: c.localizedText(.summary)?.resolved(languageCode: lang) ?? "",
                  goal: c.localizedText(.goal)?.resolved(languageCode: lang) ?? "",
                  prerequisites: c.localizedText(.prerequisites)?.resolved(languageCode: lang) ?? "",
                  level: lv?.resolved(languageCode: lang) ?? "",
                  category: c.lenientString(.category)?.trimmingCharacters(in: .whitespaces).lowercased() ?? "",
                  sessionsPerWeek: (try? c.decodeIfPresent(Range.self, forKey: .sessionsPerWeek))?.range,
                  minutesPerWeek: (try? c.decodeIfPresent(Range.self, forKey: .minutesPerWeek))?.range,
                  season: season?.isEmpty == false ? season : nil,
                  rules: (try? c.decodeIfPresent(ProgramRules.self, forKey: .rules)) ?? ProgramRules(),
                  weekPlans: weeks,
                  sources: (try? c.decodeIfPresent([Lossy<PlanSource>].self, forKey: .sources))?.compactMap(\.value) ?? [],
                  evidence: c.lenientString(.evidence) ?? "")
        levelID = lv?.resolved(languageCode: "de") ?? ""
    }
}

/// Kategorien der Pläne (Kennungen aus training_plans.json) mit Anzeigenamen
public enum TrainingProgramCategory {
    /// Reihenfolge für Filter
    public static let order = ["einstieg", "fitness", "grundlage", "test-2k", "langdistanz", "masters", "erhaltung",
                               "wiedereinstieg", "wettkampf"]

    public static func label(_ id: String) -> String {
        switch id {
        case "einstieg": return String(localized: "Einstieg")
        case "fitness": return String(localized: "Fitness")
        case "grundlage": return String(localized: "Grundlage")
        case "test-2k": return String(localized: "2000 m")
        case "langdistanz": return String(localized: "Langdistanz")
        case "masters": return String(localized: "Masters")
        case "erhaltung": return String(localized: "Form halten")
        case "wiedereinstieg": return String(localized: "Wiedereinstieg")
        case "wettkampf": return String(localized: "Wettkampf")
        default: return id
        }
    }
}

/// Länge eines Plans für den Filter „Wochen“
public enum ProgramWeekClass: String, CaseIterable, Sendable, Identifiable {
    /// bis 4 Wochen
    case short
    /// 5–8 Wochen
    case medium
    /// 9–12 Wochen
    case long
    /// über 12 Wochen
    case extended
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .short: return String(localized: "Bis 4 Wochen")
        case .medium: return String(localized: "5–8 Wochen")
        case .long: return String(localized: "9–12 Wochen")
        case .extended: return String(localized: "Über 12 Wochen")
        }
    }

    public static func of(weeks: Int) -> ProgramWeekClass {
        if weeks <= 4 { return .short }
        if weeks <= 8 { return .medium }
        return weeks <= 12 ? .long : .extended
    }
}

/// Filter der Planliste: Kategorie, Niveau (deutscher Quellwert), Wochenklasse, Suchtext
public struct ProgramFilter: Equatable, Sendable {
    public var category = ""
    public var levelID = ""
    public var weeks: ProgramWeekClass?
    public var text = ""

    public init(category: String = "", levelID: String = "", weeks: ProgramWeekClass? = nil, text: String = "") {
        self.category = category
        self.levelID = levelID
        self.weeks = weeks
        self.text = text
    }

    public var isActive: Bool {
        !category.isEmpty || !levelID.isEmpty || weeks != nil
            || !text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public func matches(_ p: TrainingProgram) -> Bool {
        if !category.isEmpty && p.category != category { return false }
        if !levelID.isEmpty && p.levelID != levelID { return false }
        if let weeks, p.weekClass != weeks { return false }
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            let hay = [p.name, p.summary, p.goal, TrainingProgramCategory.label(p.category), p.level].joined(separator: " ")
            if hay.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) == nil { return false }
        }
        return true
    }

    public func apply(_ list: [TrainingProgram]) -> [TrainingProgram] { list.filter(matches) }
}

/// Lädt die Pläne aus `training_plans.json`
public struct TrainingProgramCatalog: Equatable, Sendable {
    public var programs: [TrainingProgram]

    public init(programs: [TrainingProgram]) {
        var seen = Set<String>()
        self.programs = programs.filter { seen.insert($0.id).inserted }
    }

    public static let empty = TrainingProgramCatalog(programs: [])

    public func program(id: String) -> TrainingProgram? { programs.first { $0.id == id } }

    /// Akzeptiert `{"version": 1, "plans": [...]}` oder eine Liste. Fehlerhafte einzelne Pläne werden übersprungen,
    /// doppelte ids behalten den ersten.
    public static func decode(_ data: Data) throws -> TrainingProgramCatalog {
        let decoder = JSONDecoder()
        if let list = try? decoder.decode([Lossy<TrainingProgram>].self, from: data) {
            return TrainingProgramCatalog(programs: list.compactMap(\.value))
        }
        return TrainingProgramCatalog(programs: try decoder.decode(File.self, from: data).plans.compactMap(\.value))
    }

    public static func load(url: URL) throws -> TrainingProgramCatalog {
        try decode(Data(contentsOf: url))
    }

    /// Pläne aus dem Bundle; leer, wenn die Datei fehlt oder unlesbar ist
    public static func loadBundled(bundle: Bundle = .main, resource: String = "training_plans") -> TrainingProgramCatalog {
        guard let url = bundle.url(forResource: resource, withExtension: "json") else { return .empty }
        return (try? load(url: url)) ?? .empty
    }

    /// Programm-ids, die in `workouts` fehlen (Plan-id, Programm-id) – für Tests und Prüfungen
    public func missingPlanIds(in workouts: [WorkoutPlan]) -> [(program: String, planId: String)] {
        let ids = Set(workouts.map(\.id))
        return programs.flatMap { p in p.planIds.filter { !ids.contains($0) }.map { (p.id, $0) } }
    }

    private struct File: Decodable {
        var plans: [Lossy<TrainingProgram>]
    }
}
