import Foundation

/// Länder für die Nationalität im Profil: alle 249 Codes nach ISO 3166-1 alpha-2, Flagge als Emoji
/// (`Course.flag(_:)`), Name über `Locale` in der gewünschten Sprache. Unter Linux/Android ohne Ländernamen
/// erscheint der Code selbst.
public enum CountryList {
    public struct Country: Equatable, Hashable, Sendable, Identifiable {
        public var code: String
        public var flag: String
        public var name: String
        public var id: String { code }
    }

    /// Alle offiziell vergebenen Codes (ohne reservierte wie EU, UN, XK)
    public static let codes: [String] = [
        "AD AE AF AG AI AL AM AO AQ AR AS AT AU AW AX AZ BA BB BD BE",
        "BF BG BH BI BJ BL BM BN BO BQ BR BS BT BV BW BY BZ CA CC CD",
        "CF CG CH CI CK CL CM CN CO CR CU CV CW CX CY CZ DE DJ DK DM",
        "DO DZ EC EE EG EH ER ES ET FI FJ FK FM FO FR GA GB GD GE GF",
        "GG GH GI GL GM GN GP GQ GR GS GT GU GW GY HK HM HN HR HT HU",
        "ID IE IL IM IN IO IQ IR IS IT JE JM JO JP KE KG KH KI KM KN",
        "KP KR KW KY KZ LA LB LC LI LK LR LS LT LU LV LY MA MC MD ME",
        "MF MG MH MK ML MM MN MO MP MQ MR MS MT MU MV MW MX MY MZ NA",
        "NC NE NF NG NI NL NO NP NR NU NZ OM PA PE PF PG PH PK PL PM",
        "PN PR PS PT PW PY QA RE RO RS RU RW SA SB SC SD SE SG SH SI",
        "SJ SK SL SM SN SO SR SS ST SV SX SY SZ TC TD TF TG TH TJ TK",
        "TL TM TN TO TR TT TV TW TZ UA UG UM US UY UZ VA VC VE VG VI",
        "VN VU WF WS YE YT ZA ZM ZW",
    ].flatMap { $0.split(separator: " ").map(String.init) }

    private static let codeSet = Set(codes)

    public static func isValid(_ code: String) -> Bool { codeSet.contains(code.uppercased()) }

    /// Gross geschriebener, gültiger Code oder nil (leer, unbekannt)
    public static func normalized(_ code: String?) -> String? {
        guard let c = code?.trimmingCharacters(in: .whitespaces).uppercased(), codeSet.contains(c) else { return nil }
        return c
    }

    /// Ländername in `languageCode` (z. B. "de", "en"); ohne Namen in den Systemdaten der Code
    public static func name(_ code: String, languageCode: String) -> String {
        let c = code.uppercased()
        if let n = Locale(identifier: languageCode).localizedString(forRegionCode: c), !n.isEmpty, n != c { return n }
        return c
    }

    public static func country(_ code: String, languageCode: String) -> Country? {
        guard let c = normalized(code) else { return nil }
        return Country(code: c, flag: Course.flag(c), name: name(c, languageCode: languageCode))
    }

    /// Alle Länder, alphabetisch nach Namen in `languageCode` (ohne Rücksicht auf Akzente und Gross/klein)
    public static func all(languageCode: String) -> [Country] {
        let locale = Locale(identifier: languageCode)
        return codes.map { Country(code: $0, flag: Course.flag($0), name: name($0, languageCode: languageCode)) }
            .sorted { a, b in
                let ka = a.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
                let kb = b.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
                return ka == kb ? a.code < b.code : ka < kb
            }
    }

    /// Suche nach Namen (in der Sprache und auf Englisch, Wortteile, ohne Akzente) oder genauem Code
    public static func search(_ query: String, languageCode: String) -> [Country] {
        let list = all(languageCode: languageCode)
        let q = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !q.isEmpty else { return list }
        return list.filter { c in
            c.code.lowercased() == q || fold(c.name).contains(q)
                || (languageCode != "en" && fold(name(c.code, languageCode: "en")).contains(q))
        }
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en"))
    }
}
