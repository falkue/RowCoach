import Foundation

/// Text in mehreren Sprachen. In JSON entweder ein einfacher String (gilt für alle Sprachen) oder ein Objekt
/// `{"de": "…", "en": "…"}`. Anzeige in der Sprache des Geräts, Rückfall de → en → erster Wert (nach Sprachcode).
public struct LocalizedText: Codable, Equatable, Hashable, Sendable {
    /// Sprachcode → Text; ein einfacher String steht unter dem Schlüssel "" (alle Sprachen)
    public var values: [String: String]

    public init(_ text: String) { values = ["": text] }

    public init(values: [String: String]) { self.values = values }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            values = ["": s]
        } else {
            values = try c.decode([String: String].self)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if values.count == 1, let s = values[""] {
            try c.encode(s)
        } else {
            try c.encode(values)
        }
    }

    /// Text für `languageCode` (Standard: Sprache des Geräts)
    public func resolved(languageCode: String? = Locale.current.language.languageCode?.identifier) -> String {
        if let s = values[""] { return s }
        if let code = languageCode, let s = values[code] { return s }
        if let s = values["de"] ?? values["en"] { return s }
        return values.keys.sorted().first.flatMap { values[$0] } ?? ""
    }

    /// Text in der Sprache des Geräts
    public var text: String { resolved() }
}

/// Sehenswürdigkeit entlang einer Strecke, in Fahrreihenfolge der Hinfahrt
public struct CourseHighlight: Codable, Equatable, Sendable {
    public enum Side: String, Codable, Sendable {
        case left = "links", right = "rechts", ahead = "voraus"

        public var title: String {
            switch self {
            case .left: return "links"
            case .right: return "rechts"
            case .ahead: return "voraus"
            }
        }
    }

    public var name: LocalizedText
    /// Seite auf der Hinfahrt; unbekannte Werte werden zu nil
    public var side: Side?
    public var note: LocalizedText?

    enum CodingKeys: String, CodingKey { case name, side, note }

    public init(name: LocalizedText, side: Side?, note: LocalizedText? = nil) {
        self.name = name
        self.side = side
        self.note = note
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(LocalizedText.self, forKey: .name)
        side = try? c.decodeIfPresent(Side.self, forKey: .side)
        note = try? c.decodeIfPresent(LocalizedText.self, forKey: .note)
    }
}
