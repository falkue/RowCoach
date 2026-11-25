import Foundation

/// Übersetzbare Texte auch ausserhalb von Apple-Plattformen (Linux für Tests auf der Spark, später Android).
///
/// Auf iOS/macOS gilt das normale `String(localized:)` mit dem String Catalog `Localizable.xcstrings`. Die
/// Foundation von Linux/Android kennt es nicht; dort baut dieser Ersatz aus der Interpolation denselben Schlüssel
/// wie Xcode (`"vor %lld Tagen"`, `"%@ · ca. %@"`), schlägt die Übersetzung über `PortableLocalization.lookup` nach
/// (der Host lädt sie z. B. aus der xcstrings-Datei) und setzt die Werte ein, auch mit Positionen (`%2$@`).
/// Ohne Tabelle erscheint der deutsche Ausgangstext.
public enum PortableLocalization {
    /// Übersetzung zu einem Catalog-Schlüssel in der aktuellen Sprache (nil = Ausgangstext verwenden)
    nonisolated(unsafe) public static var lookup: ((String) -> String?)?

    /// Setzt `args` in eine Vorlage mit Formatangaben (`%lld`, `%d`, `%@`, `%1$@`, `%%`) ein
    public static func fill(_ template: String, _ args: [String]) -> String {
        var out = ""
        var next = 0
        var i = template.startIndex
        while i < template.endIndex {
            let c = template[i]
            guard c == "%" else { out.append(c); i = template.index(after: i); continue }
            var j = template.index(after: i)
            guard j < template.endIndex else { out.append(c); break }
            if template[j] == "%" { out.append("%"); i = template.index(after: j); continue }
            // optionale Position „n$“
            var digits = ""
            var k = j
            while k < template.endIndex, template[k].isNumber { digits.append(template[k]); k = template.index(after: k) }
            var position: Int?
            if !digits.isEmpty, k < template.endIndex, template[k] == "$" {
                position = Int(digits).map { $0 - 1 }
                j = template.index(after: k)
            }
            // Längenangaben überspringen, dann der Typbuchstabe
            while j < template.endIndex, "lhqzjt".contains(template[j]) { j = template.index(after: j) }
            guard j < template.endIndex, "@dDiuUxXfFeEgGsc".contains(template[j]) else {
                out.append(c); i = template.index(after: i); continue
            }
            let index = position ?? next
            if position == nil { next += 1 }
            out += index < args.count ? args[index] : ""
            i = template.index(after: j)
        }
        return out
    }
}

#if !canImport(Darwin)
/// Interpolation mit Catalog-Schlüssel und Werten (Ersatz für `String.LocalizationValue`)
public struct PortableLocalizationValue: ExpressibleByStringInterpolation, Sendable {
    public var key: String
    public var args: [String]

    public init(stringLiteral value: String) {
        key = value.replacingOccurrences(of: "%", with: "%%")
        args = []
    }

    public init(stringInterpolation: Interpolation) {
        key = stringInterpolation.key
        args = stringInterpolation.args
    }

    public struct Interpolation: StringInterpolationProtocol, Sendable {
        var key = ""
        var args: [String] = []

        public init(literalCapacity: Int, interpolationCount: Int) {}

        public mutating func appendLiteral(_ literal: String) {
            key += literal.replacingOccurrences(of: "%", with: "%%")
        }

        public mutating func appendInterpolation(_ value: Int) {
            key += "%lld"
            args.append(String(value))
        }

        public mutating func appendInterpolation(_ value: String) {
            key += "%@"
            args.append(value)
        }

        public mutating func appendInterpolation<T: CustomStringConvertible>(_ value: T) {
            key += "%@"
            args.append(value.description)
        }
    }
}

extension String {
    public init(localized value: PortableLocalizationValue, comment: StaticString? = nil) {
        let template = PortableLocalization.lookup?(value.key) ?? value.key
        self = PortableLocalization.fill(template, value.args)
    }
}
#endif
