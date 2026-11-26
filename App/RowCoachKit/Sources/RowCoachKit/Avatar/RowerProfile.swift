import Foundation

// Profil und Erscheinung (Figur, Farben, Boot, Flaggen) des Ruderers. Spezifikation: docs/avatar/SPEC.md.
// Nur Foundation: die App speichert das Profil als JSON in UserDefaults (`RowerProfile.storageKey`), Rennen geben
// `publicAppearance` an die anderen weiter, die 3D-Szene löst die Ids über `AppearanceCatalog` zu Farben auf.

/// Angaben zur eigenen Person (bleiben auf dem Gerät; nach aussen geht nur `publicAppearance`)
public struct RowerProfile: Codable, Equatable, Sendable {
    /// Schlüssel in UserDefaults (JSON); die übrigen `profile.*`-Schlüssel (Puls, Bestzeit) bleiben getrennt
    public static let storageKey = "profile.rower"

    public enum Gender: String, Codable, CaseIterable, Sendable { case female, male, diverse }

    /// Anzeigename in Turnieren, leer = Standard der App („Ich“)
    public var displayName: String
    /// ISO 3166-1 alpha-2 (z. B. "CH"), nil = keine Angabe
    public var nationality: String?
    /// nil = keine Angabe; geht nie an andere
    public var gender: Gender?
    public var appearance: RowerAppearance

    public init(displayName: String = "", nationality: String? = nil, gender: Gender? = nil,
                appearance: RowerAppearance = RowerAppearance()) {
        self.displayName = displayName
        self.nationality = CountryList.normalized(nationality)
        self.gender = gender
        self.appearance = appearance
    }

    enum CodingKeys: String, CodingKey { case displayName, nationality, gender, appearance }

    /// Tolerant: fehlende Felder bekommen Standardwerte, unbekanntes Geschlecht gilt als „keine Angabe“
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        nationality = CountryList.normalized(try c.decodeIfPresent(String.self, forKey: .nationality))
        gender = (try? c.decodeIfPresent(String.self, forKey: .gender)).flatMap { $0 }.flatMap(Gender.init(rawValue:))
        appearance = try c.decodeIfPresent(RowerAppearance.self, forKey: .appearance) ?? RowerAppearance()
    }

    /// Höchstlänge des Anzeigenamens (Zeichen), damit er über dem Boot lesbar bleibt
    public static let maxDisplayNameLength = 24

    /// Anzeigename ohne Leerzeichen am Rand, gekürzt auf `maxDisplayNameLength`, leer → `fallback`
    public func resolvedDisplayName(fallback: String) -> String {
        let name = String(displayName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxDisplayNameLength))
        return name.isEmpty ? fallback : name
    }

    /// Ob ein Flaggen-Schalter überhaupt möglich ist (nur mit Nationalität)
    public var canShowFlag: Bool { nationality != nil }

    /// Was andere in Rennen und Turnieren sehen (Datenschutzregel der SPEC):
    /// - Nationalität nur, wenn mindestens ein Flaggen-Schalter an ist (sonst nil);
    /// - ohne Nationalität sind beide Schalter aus;
    /// - Geschlecht und Anzeigename stecken nie in der Erscheinung.
    /// Die eigene 3D-Szene benutzt dieselbe Erscheinung (Flagge genau dann, wenn sie auch andere sehen).
    public var publicAppearance: RowerAppearance {
        var a = appearance
        if nationality == nil {
            a.flagOnShirt = false
            a.flagOnBoat = false
        }
        a.nationality = (a.flagOnShirt || a.flagOnBoat) ? nationality : nil
        return a
    }

    /// Profil aus UserDefaults-Daten (nil oder unlesbar → Standardprofil)
    public static func decode(_ data: Data?) -> RowerProfile {
        guard let data, let p = try? JSONDecoder().decode(RowerProfile.self, from: data) else { return RowerProfile() }
        return p
    }

    /// JSON für UserDefaults (Schlüssel sortiert, damit gleiche Profile gleiche Daten ergeben)
    public func encoded() -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return (try? e.encode(self)) ?? Data()
    }
}

/// Erscheinung im Boot: Figur, Farben, Boot und Flaggen. Ids aus `appearance.json` (`AppearanceCatalog`);
/// unbekannte Ids löst der Katalog mit Ersatzwerten auf, damit ein neuerer Gegner nie die Szene bricht.
public struct RowerAppearance: Codable, Equatable, Hashable, Sendable {
    public static let defaultCharacterId = "char-01"
    /// leer = erster Bootsstil des Katalogs
    public static let defaultBoatStyleId = ""

    public var characterId: String
    /// Überschreibungen, nil = Farbe des Figurtyps
    public var skinToneId: String?
    public var hairColorId: String?
    public var shirtColorId: String?
    public var boatStyleId: String
    public var flagOnShirt: Bool
    public var flagOnBoat: Bool
    /// ISO 3166-1 alpha-2; gesetzt aus dem Profil, und nur wenn ein Flaggen-Schalter an ist (`publicAppearance`)
    public var nationality: String?

    public init(characterId: String = RowerAppearance.defaultCharacterId, skinToneId: String? = nil,
                hairColorId: String? = nil, shirtColorId: String? = nil,
                boatStyleId: String = RowerAppearance.defaultBoatStyleId,
                flagOnShirt: Bool = false, flagOnBoat: Bool = false, nationality: String? = nil) {
        self.characterId = characterId
        self.skinToneId = skinToneId
        self.hairColorId = hairColorId
        self.shirtColorId = shirtColorId
        self.boatStyleId = boatStyleId
        self.flagOnShirt = flagOnShirt
        self.flagOnBoat = flagOnBoat
        self.nationality = CountryList.normalized(nationality)
    }

    enum CodingKeys: String, CodingKey {
        case characterId, skinToneId, hairColorId, shirtColorId, boatStyleId, flagOnShirt, flagOnBoat, nationality
    }

    /// Tolerant gegenüber fehlenden Feldern (ältere oder knappere Absender)
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        characterId = try c.decodeIfPresent(String.self, forKey: .characterId) ?? Self.defaultCharacterId
        skinToneId = try c.decodeIfPresent(String.self, forKey: .skinToneId)
        hairColorId = try c.decodeIfPresent(String.self, forKey: .hairColorId)
        shirtColorId = try c.decodeIfPresent(String.self, forKey: .shirtColorId)
        boatStyleId = try c.decodeIfPresent(String.self, forKey: .boatStyleId) ?? Self.defaultBoatStyleId
        flagOnShirt = try c.decodeIfPresent(Bool.self, forKey: .flagOnShirt) ?? false
        flagOnBoat = try c.decodeIfPresent(Bool.self, forKey: .flagOnBoat) ?? false
        nationality = CountryList.normalized(try c.decodeIfPresent(String.self, forKey: .nationality))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(characterId, forKey: .characterId)
        try c.encodeIfPresent(skinToneId, forKey: .skinToneId)
        try c.encodeIfPresent(hairColorId, forKey: .hairColorId)
        try c.encodeIfPresent(shirtColorId, forKey: .shirtColorId)
        try c.encode(boatStyleId, forKey: .boatStyleId)
        try c.encode(flagOnShirt, forKey: .flagOnShirt)
        try c.encode(flagOnBoat, forKey: .flagOnBoat)
        try c.encodeIfPresent(nationality, forKey: .nationality)
    }

    /// Flaggen-Emoji fürs Trikot (nil = keine Flagge zeigen)
    public var shirtFlag: String? { flagOnShirt ? flagEmoji : nil }
    /// Flaggen-Emoji fürs Boot (nil = keine Flagge zeigen)
    public var boatFlag: String? { flagOnBoat ? flagEmoji : nil }

    private var flagEmoji: String? {
        guard let n = nationality else { return nil }
        let f = Course.flag(n)
        return f.isEmpty ? nil : f
    }

    /// Zufällige, aber je `seed` stabile Erscheinung für Bots, Geister und Verkehr: Figurtyp, Trikotfarbe und
    /// Boot aus dem Katalog, keine Flaggen. Gleicher Seed und gleicher Katalog ergeben immer dieselbe Erscheinung
    /// (eigener Hash, nicht `Hasher`, der je Programmstart wechselt).
    public static func random(seed: String, catalog: AppearanceCatalog = .current) -> RowerAppearance {
        var rng = SeededGenerator(seed: seed)
        func pick<T>(_ list: [T]) -> T? {
            list.isEmpty ? nil : list[Int(rng.next() % UInt64(list.count))]
        }
        let character = pick(catalog.characters)
        let shirt = pick(catalog.shirtColors)
        let boat = pick(catalog.boatStyles)
        return RowerAppearance(characterId: character?.id ?? defaultCharacterId,
                               shirtColorId: shirt?.id,
                               boatStyleId: boat?.id ?? defaultBoatStyleId)
    }
}

/// Deterministischer Zufall aus einer Zeichenkette (FNV-1a 64 als Startwert, dann SplitMix64)
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: String) {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in seed.utf8 {
            h ^= UInt64(b)
            h = h &* 0x0000_0100_0000_01B3
        }
        state = h
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
