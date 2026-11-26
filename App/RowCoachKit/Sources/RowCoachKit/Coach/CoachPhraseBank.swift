import Foundation

/// Phrasen des Sprachcoachs aus `coach_phrases.json` (Format siehe docs/coach/SPEC.md):
/// Szenario → Stufe ("1", "2") → Stil (calm/motivating/cox) → Sprache (de/en) → Liste von Varianten.
/// Varianten dürfen Platzhalter wie `{duration}` enthalten (dynamisch). Unbekannte Szenarien und Felder werden
/// mitgelesen bzw. ignoriert; eine Variante bleibt über ihren Index adressierbar (`phraseId`), neue Varianten
/// deshalb nur anhängen.
public struct CoachPhraseBank: Sendable {
    public struct Scenario: Sendable {
        public var dynamic: Bool
        public var variables: [String]
        /// Stufe → Stil → Sprache → Varianten
        public var levels: [Int: [String: [String: [String]]]]
    }

    public enum LoadError: Error { case notAnObject, noScenarios }

    public private(set) var scenarios: [String: Scenario] = [:]
    public var version: Int = 1

    public init(scenarios: [String: Scenario]) {
        self.scenarios = scenarios
    }

    /// Lädt die Phrasendatei (tolerant: falsche Einträge fallen weg)
    public init(data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw LoadError.notAnObject }
        version = root["version"] as? Int ?? 1
        guard let sc = root["scenarios"] as? [String: Any] else { throw LoadError.noScenarios }
        for (id, value) in sc {
            guard let obj = value as? [String: Any], let lv = obj["levels"] as? [String: Any] else { continue }
            var levels: [Int: [String: [String: [String]]]] = [:]
            for (lk, lvValue) in lv {
                guard let level = Int(lk), let styles = lvValue as? [String: Any] else { continue }
                var byStyle: [String: [String: [String]]] = [:]
                for (style, stValue) in styles {
                    guard let langs = stValue as? [String: Any] else { continue }
                    var byLang: [String: [String]] = [:]
                    for (lang, list) in langs {
                        if let arr = list as? [Any] {
                            // Index bleibt stabil: Nicht-Texte werden zu "" (nie gewählt) statt wegzufallen
                            byLang[lang] = arr.map { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
                        }
                    }
                    byStyle[style] = byLang
                }
                levels[level] = byStyle
            }
            scenarios[id] = Scenario(dynamic: obj["dynamic"] as? Bool ?? false,
                                     variables: obj["variables"] as? [String] ?? [], levels: levels)
        }
    }

    public func has(_ scenario: CoachScenario) -> Bool { scenarios[scenario.rawValue] != nil }

    /// Höchste vorhandene Stufe eines Szenarios (0 = fehlt)
    public func maxLevel(_ scenario: CoachScenario) -> Int {
        scenarios[scenario.rawValue]?.levels.keys.max() ?? 0
    }

    /// Varianten mit Stufen- und Stilersatz: die gewünschte Stufe, sonst die nächstniedrigere vorhandene;
    /// der gewünschte Stil, sonst motivating/calm/cox. Liefert die tatsächlich verwendete Stufe und den Stil.
    func variants(_ scenario: CoachScenario, level: Int, style: CoachStyle, language: String)
        -> (level: Int, style: String, list: [String])? {
        guard let s = scenarios[scenario.rawValue] else { return nil }
        let levelsDesc = s.levels.keys.sorted(by: >)
        let candidates = levelsDesc.filter { $0 <= level } + levelsDesc.filter { $0 > level }.reversed()
        for l in candidates {
            guard let byStyle = s.levels[l] else { continue }
            for st in style.fallbacks {
                if let list = byStyle[st.rawValue]?[language], list.contains(where: { !$0.isEmpty }) {
                    return (l, st.rawValue, list)
                }
            }
        }
        return nil
    }

    /// Platzhalter einer Variante (`{name}`)
    static func placeholders(_ text: String) -> [String] {
        var out: [String] = []
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "{") {
            let after = rest[rest.index(after: open)...]
            guard let close = after.firstIndex(of: "}") else { break }
            let name = String(after[..<close])
            if !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) { out.append(name) }
            rest = after[after.index(after: close)...]
        }
        return out
    }

    /// Wörter einer Variante (Gedankenstriche und Auslassungspunkte zählen nicht)
    static func wordCount(_ text: String) -> Int {
        text.replacingOccurrences(of: "–", with: " ").replacingOccurrences(of: "…", with: " ")
            .split(whereSeparator: { $0 == " " }).count
    }

    static func fill(_ text: String, _ values: [String: String]) -> String {
        var out = text
        for (k, v) in values { out = out.replacingOccurrences(of: "{\(k)}", with: v) }
        return out
    }
}

/// Gewählte Phrase
public struct CoachPhrase: Equatable, Sendable {
    public var text: String
    public var phraseId: String
    public var level: Int
    public var isDynamic: Bool
}

/// Wählt Varianten zufällig (seedbar), ohne die letzten k je Szenario/Stufe/Stil/Sprache zu wiederholen.
/// Dynamische Varianten nur, wenn alle ihre Platzhalter Werte haben; sonst die statischen Varianten.
public struct CoachPhrasePicker: Sendable {
    public let bank: CoachPhraseBank
    public var historySize: Int
    private var rng: SeededRandom
    private var recent: [String: [Int]] = [:]

    public init(bank: CoachPhraseBank, seed: UInt64, historySize: Int = 3) {
        self.bank = bank
        self.historySize = max(historySize, 0)
        rng = SeededRandom(seed: seed)
    }

    /// - Parameter preferMaxWords: wenn gesetzt, Varianten mit höchstens so vielen Wörtern bevorzugen (z. B. in den
    ///   letzten 60 s harter Phasen); gibt es keine, gelten alle
    public mutating func pick(_ scenario: CoachScenario, level: Int = 1, style: CoachStyle, language: String,
                              values: [String: String] = [:], preferMaxWords: Int? = nil) -> CoachPhrase? {
        guard style != .off, let found = bank.variants(scenario, level: level, style: style, language: language) else {
            return nil
        }
        let usable = found.list.indices.filter { i in
            let t = found.list[i]
            return !t.isEmpty && CoachPhraseBank.placeholders(t).allSatisfy { values[$0] != nil }
        }
        guard !usable.isEmpty else { return nil }
        // Wenn Werte da sind, die dynamischen Varianten bevorzugen (sie tragen die Information)
        let dynamic = usable.filter { !CoachPhraseBank.placeholders(found.list[$0]).isEmpty }
        var pool = dynamic.isEmpty ? usable : dynamic
        if let maxWords = preferMaxWords {
            // kurze Rufe: statische Varianten zuerst (dynamische Werte verlängern den Satz)
            let short = usable.filter { CoachPhraseBank.wordCount(found.list[$0]) <= maxWords }
            let shortStatic = short.filter { CoachPhraseBank.placeholders(found.list[$0]).isEmpty }
            if !shortStatic.isEmpty { pool = shortStatic } else if !short.isEmpty { pool = short }
        }
        let key = "\(scenario.rawValue).\(found.level).\(found.style).\(language)"
        let hist = recent[key] ?? []
        let k = min(historySize, pool.count - 1)
        var allowed = pool.filter { !hist.suffix(k).contains($0) }
        if allowed.isEmpty { allowed = pool }
        let i = allowed[Int(rng.next() % UInt64(allowed.count))]
        recent[key] = Array((hist + [i]).suffix(max(historySize, 1)))
        let raw = found.list[i]
        let isDyn = !CoachPhraseBank.placeholders(raw).isEmpty
        return CoachPhrase(text: CoachPhraseBank.fill(raw, values),
                           phraseId: "\(scenario.rawValue).\(found.level).\(found.style).\(i)",
                           level: found.level, isDynamic: isDyn)
    }

    /// Gleichmässige Zufallszahl im Bereich (für Abstände, z. B. Technikimpulse)
    public mutating func uniform(_ r: ClosedRange<Double>) -> Double {
        let u = Double(rng.next() >> 11) / Double(1 << 53)
        return r.lowerBound + (r.upperBound - r.lowerBound) * u
    }
}

/// SplitMix64: kleiner, seedbarer Zufallsgenerator (gleiche Folge auf allen Plattformen)
public struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
