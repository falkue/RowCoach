import Foundation

/// Ein Trainingsprogramm (offenes JSON-Format, `plans.json` im App-Bundle; Quelle: docs/trainings-recherche.json).
///
/// Format (Phasen bereits ausgerollt, also ohne Wiederholungsangaben):
/// ```json
/// [{"id": "…", "name": "…", "summary": "…", "purpose": "…", "level": "…",
///   "sources": [{"title": "…", "publisher": "…", "url": "…", "published": "…", "zotero": "…"}],
///   "phases": [{"kind": "warmup|work|rest|cooldown", "durationS": 300, "distanceM": 500,
///               "spmMin": 18, "spmMax": 20, "hrZone": 2, "paceOffsetMinS": 10, "paceOffsetMaxS": 15,
///               "activeRest": true, "label": "…"}]}]
/// ```
/// Das Programm ist unabhängig von der Strecke; es steuert nur Phasen und Ziele.
/// Das Dekodieren ist tolerant: unbekannte Felder werden ignoriert, unbekannte Phasenarten werden zu `.other`,
/// Zahlen dürfen auch als Text kommen, Phasen ohne Länge und Programme ohne id oder Phasen fallen weg.
public struct WorkoutPlan: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// Kurze Erklärung (ein, zwei Sätze)
    public var summary: String
    /// Wozu das Training dient
    public var purpose: String
    /// Intensität bzw. Niveau, wie in der Recherche angegeben (z. B. „leicht“, „mittel“, „hart“)
    public var level: String
    /// Trainingsart für Filter in der App (z. B. „Grundlage“, „Intervalle“, „Test“); optional
    public var category: String
    /// Niveau und Art in der Quellsprache Deutsch (für Regeln und Sortierung, unabhängig von der Anzeigesprache)
    public var levelID: String
    public var categoryID: String
    /// Schlagworte aus fester Liste (Intensität, Fokus, Form), siehe `PlanTag`; unbekannte bleiben erhalten
    public var tags: [String]
    public var sources: [PlanSource]
    public var phases: [WorkoutPhase]

    enum CodingKeys: String, CodingKey { case id, name, summary, purpose, level, category, tags, sources, phases }

    public init(id: String, name: String, summary: String = "", purpose: String = "", level: String = "",
                category: String = "", tags: [String] = [], sources: [PlanSource] = [], phases: [WorkoutPhase]) {
        self.id = id
        self.name = name
        self.summary = summary
        self.purpose = purpose
        self.level = level
        self.category = category
        self.levelID = level
        self.categoryID = category
        self.tags = tags
        self.sources = sources
        self.phases = phases.filter(\.hasLength)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.lenientString(.id)?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "Programm ohne id")
        }
        self.id = id
        // Texte einsprachig („…“) oder zweisprachig ({"de": "…", "en": "…"}), angezeigt in der Sprache der App
        let lang = AppLocalization.languageCode
        name = c.localizedText(.name)?.resolved(languageCode: lang) ?? id
        summary = c.localizedText(.summary)?.resolved(languageCode: lang) ?? ""
        purpose = c.localizedText(.purpose)?.resolved(languageCode: lang) ?? ""
        let lv = c.localizedText(.level)
        let cat = c.localizedText(.category)
        level = lv?.resolved(languageCode: lang) ?? ""
        category = cat?.resolved(languageCode: lang) ?? ""
        levelID = lv?.resolved(languageCode: "de") ?? ""
        categoryID = cat?.resolved(languageCode: "de") ?? ""
        tags = ((try? c.decodeIfPresent([Lossy<String>].self, forKey: .tags))?.compactMap(\.value) ?? [])
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        sources = (try? c.decodeIfPresent([Lossy<PlanSource>].self, forKey: .sources))?.compactMap(\.value) ?? []
        let ph = (try? c.decodeIfPresent([Lossy<WorkoutPhase>].self, forKey: .phases))?.compactMap(\.value) ?? []
        phases = ph.filter(\.hasLength)
        guard !phases.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .phases, in: c, debugDescription: "Programm ohne Phasen")
        }
    }

    // MARK: Abgeleitete Werte

    /// Gesamtdauer, wenn alle Phasen zeitbasiert sind (s)
    public var totalDuration: Double? {
        phases.allSatisfy(\.isTimed) ? phases.reduce(0) { $0 + ($1.durationS ?? 0) } : nil
    }

    /// Gesamtdistanz, wenn alle Phasen distanzbasiert sind (m)
    public var totalDistance: Double? {
        phases.allSatisfy { !$0.isTimed } ? phases.reduce(0) { $0 + ($1.distanceM ?? 0) } : nil
    }

    /// Geschätzte Dauer (s) mit den Zieltempi zur 2000-m-Bestzeit
    public func estimatedDuration(best2k: Double) -> Double {
        phases.reduce(0) { $0 + $1.estimatedSeconds(best2k: best2k) }
    }

    /// Geschätzte Distanz (m) mit den Zieltempi zur 2000-m-Bestzeit
    public func estimatedDistance(best2k: Double) -> Double {
        phases.reduce(0) { $0 + $1.estimatedMeters(best2k: best2k) }
    }

    /// Anzahl der Belastungsphasen
    public var workCount: Int { phases.filter { $0.kind == .work }.count }
}

/// Quelle eines Programms (Zotero-Key optional)
public struct PlanSource: Codable, Equatable, Hashable, Sendable {
    public var title: String
    public var publisher: String?
    public var url: String?
    public var published: String?
    public var zotero: String?

    enum CodingKeys: String, CodingKey { case title, publisher, url, published, zotero }

    public init(title: String, publisher: String? = nil, url: String? = nil, published: String? = nil,
                zotero: String? = nil) {
        self.title = title
        self.publisher = publisher
        self.url = url
        self.published = published
        self.zotero = zotero
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = c.lenientString(.title) ?? ""
        publisher = c.lenientString(.publisher)
        url = c.lenientString(.url)
        published = c.lenientString(.published)
        zotero = c.lenientString(.zotero)
    }
}

/// Eine Phase eines Programms: zeit- oder distanzbasiert, mit Zielen.
/// Sind Dauer und Distanz angegeben, gilt die Dauer.
public struct WorkoutPhase: Codable, Equatable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case warmup, work, rest, cooldown, other

        /// Deutscher Name für die Anzeige
        public var title: String {
            switch self {
            case .warmup: return String(localized: "Einrudern")
            case .work: return String(localized: "Intervall")
            case .rest: return String(localized: "Pause")
            case .cooldown: return String(localized: "Ausrudern")
            case .other: return String(localized: "Phase")
            }
        }
    }

    public var kind: Kind
    /// Dauer (s); nil bei Distanzphasen
    public var durationS: Double?
    /// Distanz (m); nil bei Zeitphasen
    public var distanceM: Double?
    public var spmMin: Int?
    public var spmMax: Int?
    /// Zielzone 1…5 (siehe HeartRateZones)
    public var hrZone: Int?
    /// Tempo-Ziel relativ zum Tempo der 2000-m-Bestzeit (s/500 m; positiv = langsamer)
    public var paceOffsetMinS: Double?
    public var paceOffsetMaxS: Double?
    /// Pause mit lockerem Weiterrudern (true) oder Stillstand (false)
    public var activeRest: Bool?
    public var label: String

    enum CodingKeys: String, CodingKey {
        case kind, durationS, distanceM, spmMin, spmMax, hrZone, paceOffsetMinS, paceOffsetMaxS, activeRest, label
    }

    public init(kind: Kind, durationS: Double? = nil, distanceM: Double? = nil, spmMin: Int? = nil,
                spmMax: Int? = nil, hrZone: Int? = nil, paceOffsetMinS: Double? = nil, paceOffsetMaxS: Double? = nil,
                activeRest: Bool? = nil, label: String = "") {
        self.kind = kind
        let d = durationS.flatMap { $0 > 0 && $0.isFinite ? $0 : nil }
        self.durationS = d
        self.distanceM = d == nil ? distanceM.flatMap { $0 > 0 && $0.isFinite ? $0 : nil } : nil
        self.spmMin = spmMin
        self.spmMax = spmMax
        self.hrZone = hrZone
        self.paceOffsetMinS = paceOffsetMinS
        self.paceOffsetMaxS = paceOffsetMaxS
        self.activeRest = activeRest
        self.label = label
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = (c.lenientString(.kind) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let kind: Kind
        switch raw {
        case "warmup", "warm-up", "warm_up": kind = .warmup
        case "work", "interval": kind = .work
        case "rest", "recovery": kind = .rest
        case "cooldown", "cool-down", "cool_down": kind = .cooldown
        default: kind = .other
        }
        self.init(kind: kind,
                  durationS: c.lenientDouble(.durationS),
                  distanceM: c.lenientDouble(.distanceM),
                  spmMin: c.lenientInt(.spmMin),
                  spmMax: c.lenientInt(.spmMax),
                  hrZone: c.lenientInt(.hrZone).flatMap { (1...HeartRateZones.count).contains($0) ? $0 : nil },
                  paceOffsetMinS: c.lenientDouble(.paceOffsetMinS),
                  paceOffsetMaxS: c.lenientDouble(.paceOffsetMaxS),
                  activeRest: c.lenientBool(.activeRest),
                  label: c.localizedText(.label)?.resolved(languageCode: AppLocalization.languageCode) ?? "")
    }

    // MARK: Abgeleitete Werte

    public var isTimed: Bool { durationS != nil }
    public var hasLength: Bool { durationS != nil || distanceM != nil }
    /// Anzeigename: Bezeichnung aus dem Programm, sonst die Phasenart
    public var title: String {
        let l = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return l.isEmpty ? kind.title : l
    }
    /// Pausen laufen nach der Uhr weiter (auch wenn man still sitzt); alle anderen Phasen nach der Ruderzeit.
    public var countsWallTime: Bool { kind == .rest }

    /// Schlagzahl-Bereich (/min)
    public var spmRange: ClosedRange<Int>? {
        guard let a = spmMin ?? spmMax else { return nil }
        let b = spmMax ?? a
        return min(a, b)...max(a, b)
    }

    /// Absoluter Tempobereich (s/500 m, schnell…langsam) zur 2000-m-Bestzeit (s)
    public func paceRange(best2k: Double) -> ClosedRange<Double>? {
        guard let a = paceOffsetMinS ?? paceOffsetMaxS else { return nil }
        let b = paceOffsetMaxS ?? a
        let base = PaceTargets.basePace500(best2k: best2k)
        return (base + min(a, b))...(base + max(a, b))
    }

    /// Angenommenes Tempo für Schätzungen (s/500 m): Mitte des Zielbereichs, sonst ein Standardabstand je Phasenart.
    public func estimatedPace(best2k: Double) -> Double {
        if let r = paceRange(best2k: best2k) { return max((r.lowerBound + r.upperBound) / 2, 60) }
        let base = PaceTargets.basePace500(best2k: best2k)
        switch kind {
        case .work: return base + 10
        case .warmup: return base + 30
        case .cooldown: return base + 35
        case .rest: return base + 45
        case .other: return base + 20
        }
    }

    /// Geschätzte Geschwindigkeit (m/s); 0 bei einer Pause im Stillstand
    public func estimatedSpeed(best2k: Double) -> Double {
        if kind == .rest, activeRest == false { return 0 }
        return 500 / estimatedPace(best2k: best2k)
    }

    public func estimatedSeconds(best2k: Double) -> Double {
        if let d = durationS { return d }
        guard let m = distanceM else { return 0 }
        return m / max(500 / estimatedPace(best2k: best2k), 0.5)
    }

    public func estimatedMeters(best2k: Double) -> Double {
        if let m = distanceM { return m }
        return (durationS ?? 0) * estimatedSpeed(best2k: best2k)
    }
}

/// Tempo-Ziele relativ zur 2000-m-Bestzeit
public enum PaceTargets {
    /// Standard, solange in den Einstellungen nichts anderes steht: 8:00 min
    public static let defaultBest2k: Double = 480

    /// Tempo der Bestzeit pro 500 m (s)
    public static func basePace500(best2k: Double) -> Double {
        (best2k > 0 && best2k.isFinite ? best2k : defaultBest2k) / 4
    }
}

/// Lädt Programme aus `plans.json`.
public enum WorkoutPlanCatalog {
    /// Liest eine Liste von Programmen. Akzeptiert ein Array oder ein Objekt mit dem Feld `plans`.
    /// Fehlerhafte einzelne Programme werden übersprungen; doppelte ids behalten das erste Programm.
    public static func decode(_ data: Data) throws -> [WorkoutPlan] {
        let decoder = JSONDecoder()
        let list: [Lossy<WorkoutPlan>]
        if let l = try? decoder.decode([Lossy<WorkoutPlan>].self, from: data) {
            list = l
        } else {
            list = try decoder.decode(PlanFile.self, from: data).plans
        }
        var seen = Set<String>()
        return list.compactMap(\.value).filter { seen.insert($0.id).inserted }
    }

    public static func load(url: URL) throws -> [WorkoutPlan] {
        try decode(Data(contentsOf: url))
    }

    /// Programme aus dem Bundle (`plans.json`); leer, wenn die Datei fehlt oder unlesbar ist.
    public static func loadBundled(bundle: Bundle = .main, resource: String = "plans") -> [WorkoutPlan] {
        guard let url = bundle.url(forResource: resource, withExtension: "json") else { return [] }
        return (try? load(url: url)) ?? []
    }

    private struct PlanFile: Decodable {
        var plans: [Lossy<WorkoutPlan>]
    }
}

/// Texte für die Anzeige von Programmen und Phasen
public enum PlanFormat {
    /// „20 min“, „45 s“, „1:30 min“, „1 h 10 min“
    public static func duration(_ s: Double) -> String {
        guard s.isFinite, s > 0 else { return "–" }
        let t = Int(s.rounded())
        if t < 60 { return String(localized: "\(t) s") }
        if t % 60 == 0 {
            let m = t / 60
            if m < 60 { return String(localized: "\(m) min") }
            return m % 60 == 0 ? String(localized: "\(m / 60) h") : String(localized: "\(m / 60) h \(m % 60) min")
        }
        let secs = String(format: "%02d", t % 60)
        return String(localized: "\(t / 60):\(secs) min")
    }

    /// Länge einer Phase: Dauer oder Distanz
    public static func length(_ p: WorkoutPhase) -> String {
        if let d = p.durationS { return duration(d) }
        if let m = p.distanceM { return Format.distance(m) }
        return "–"
    }

    /// „18–20 /min“ bzw. „20 /min“
    public static func strokeRate(_ r: ClosedRange<Int>) -> String {
        r.lowerBound == r.upperBound ? String(localized: "\(r.lowerBound) /min")
            : String(localized: "\(r.lowerBound)–\(r.upperBound) /min")
    }

    /// „2:10.0–2:15.0“ ohne Zehntel: „2:10–2:15“
    public static func paceRange(_ r: ClosedRange<Double>) -> String {
        let a = Format.duration(r.lowerBound), b = Format.duration(r.upperBound)
        return a == b ? a : "\(a)–\(b)"
    }

    /// Länge eines ganzen Programms: genau, wenn alle Phasen gleichartig sind, sonst geschätzt
    public static func planLength(_ plan: WorkoutPlan, best2k: Double) -> String {
        if let d = plan.totalDuration { return duration(d) }
        // Schätzungen auf ganze Minuten („ca. 28 min“ statt „ca. 27:44 min“)
        let est = max((plan.estimatedDuration(best2k: best2k) / 60).rounded(), 1) * 60
        let approx = duration(est)
        if let m = plan.totalDistance { return String(localized: "\(Format.distance(m)) · ca. \(approx)") }
        return String(localized: "ca. \(approx)")
    }
}

/// Ampel: liegt ein Wert im Zielbereich?
public enum TargetLight: String, Sendable, Equatable {
    /// kein Ziel oder kein Messwert
    case none
    case green
    case yellow
    case red

    /// Grün im Bereich, Gelb bis `tolerance` daneben, sonst Rot. `value <= 0` gilt als „kein Messwert“.
    public static func evaluate(_ value: Double, in range: ClosedRange<Double>?, tolerance: Double) -> TargetLight {
        guard let range, value > 0, value.isFinite else { return .none }
        if range.contains(value) { return .green }
        let off = value < range.lowerBound ? range.lowerBound - value : value - range.upperBound
        return off <= tolerance ? .yellow : .red
    }

    /// Schlagzahl: Toleranz 2 /min
    public static func strokeRate(_ spm: Int, target: ClosedRange<Int>?) -> TargetLight {
        evaluate(Double(spm), in: target.map { Double($0.lowerBound)...Double($0.upperBound) }, tolerance: 2)
    }

    /// Tempo (s/500 m): Toleranz 3 s
    public static func pace(_ pace: Double, target: ClosedRange<Double>?) -> TargetLight {
        evaluate(pace, in: target, tolerance: 3)
    }

    /// Pulszone: genau getroffen grün, eine Zone daneben gelb
    public static func heartRate(zone: Int?, target: Int?) -> TargetLight {
        guard let zone, let target else { return .none }
        let d = abs(zone - target)
        return d == 0 ? .green : (d == 1 ? .yellow : .red)
    }
}

// MARK: - Tolerantes Dekodieren

/// Dekodiert ein Element und liefert nil statt eines Fehlers.
struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

extension KeyedDecodingContainer {
    /// Text einsprachig oder als {"de": "…", "en": "…"}; Zahlen werden zu Text
    func localizedText(_ key: Key) -> LocalizedText? {
        if let t = try? decodeIfPresent(LocalizedText.self, forKey: key) { return t }
        return lenientString(key).map { LocalizedText($0) }
    }

    func lenientString(_ key: Key) -> String? {
        if let s = try? decodeIfPresent(String.self, forKey: key) { return s }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return String(i) }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return String(d) }
        return nil
    }

    func lenientDouble(_ key: Key) -> Double? {
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return d.isFinite ? d : nil }
        if let s = try? decodeIfPresent(String.self, forKey: key) {
            return Double(s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
        }
        return nil
    }

    /// Ganze Zahl; aus Text wie „2-3“ wird die erste Zahl genommen.
    func lenientInt(_ key: Key) -> Int? {
        if let d = try? decodeIfPresent(Double.self, forKey: key), d.isFinite { return Int(d.rounded()) }
        if let s = try? decodeIfPresent(String.self, forKey: key) {
            let digits = s.trimmingCharacters(in: .whitespaces).prefix { $0.isNumber }
            return Int(digits)
        }
        return nil
    }

    func lenientBool(_ key: Key) -> Bool? {
        if let b = try? decodeIfPresent(Bool.self, forKey: key) { return b }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return i != 0 }
        if let s = try? decodeIfPresent(String.self, forKey: key) {
            switch s.lowercased() {
            case "true", "yes", "ja", "1": return true
            case "false", "no", "nein", "0": return false
            default: return nil
            }
        }
        return nil
    }
}

/// Sprache der App (wie das App-Bundle sie gewählt hat; folgt der Spracheinstellung des Systems je App).
/// Bestimmt, welche Sprache zweisprachige Texte aus plans.json und course.json zeigen.
public enum AppLocalization {
    /// Vom Host gesetzte Sprache (z. B. Android, wo es kein App-Bundle mit Lokalisierungen gibt); nil = Bundle fragen
    nonisolated(unsafe) public static var override: String?

    public static var languageCode: String {
        if let override { return override }
        #if canImport(Darwin)
        let first = Bundle.main.preferredLocalizations.first ?? "de"
        return Locale(identifier: first).language.languageCode?.identifier ?? "de"
        #else
        return Locale.current.language.languageCode?.identifier ?? "de"
        #endif
    }
}
