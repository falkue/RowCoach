import Foundation

// Profil und Erscheinung (Figur, Farben, Boot, Flaggen) des Ruderers. Spezifikation: docs/avatar/SPEC.md.
// Nur Foundation: die App speichert das Profil als JSON in UserDefaults (`RowerProfile.storageKey`), Rennen geben
// `publicAppearance` an die anderen weiter, die 3D-Szene löst die Ids über `AppearanceCatalog` zu Farben auf.

/// Angaben zur eigenen Person (bleiben auf dem Gerät; nach aussen geht nur `publicAppearance`).
/// Kein Geschlechtsfeld (Entscheidung Falk, 26.11.2026: man wählt eine Figur, kein Geschlecht); ein `gender` aus
/// älteren Daten wird beim Lesen übergangen und beim nächsten Speichern verworfen.
public struct RowerProfile: Codable, Equatable, Sendable {
    /// Schlüssel in UserDefaults (JSON); die übrigen `profile.*`-Schlüssel (Puls, Bestzeit) bleiben getrennt
    public static let storageKey = "profile.rower"

    /// Anzeigename in Turnieren, leer = Standard der App („Ich“)
    public var displayName: String
    /// ISO 3166-1 alpha-2 (z. B. "CH"), nil = keine Angabe
    public var nationality: String?
    public var appearance: RowerAppearance

    public init(displayName: String = "", nationality: String? = nil,
                appearance: RowerAppearance = RowerAppearance()) {
        self.displayName = displayName
        self.nationality = CountryList.normalized(nationality)
        self.appearance = appearance
    }

    enum CodingKeys: String, CodingKey { case displayName, nationality, appearance }

    /// Tolerant: fehlende Felder bekommen Standardwerte, unbekannte (z. B. altes `gender`) werden übergangen
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        nationality = CountryList.normalized(try c.decodeIfPresent(String.self, forKey: .nationality))
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
    /// - der Anzeigename steckt nie in der Erscheinung.
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
/// Die Figurtypen sind Startvorlagen: Farben und Form (Frisur, Statur, Grösse, Oberteil, Beine, Bart, Accessoires)
/// lassen sich einzeln überschreiben (nil = wie die Vorlage).
public struct RowerAppearance: Codable, Equatable, Hashable, Sendable {
    /// Standardvorlage (mittlerer Hautton, keine helle Vorauswahl)
    public static let defaultCharacterId = "char-01"
    /// leer = erster Bootsstil des Katalogs
    public static let defaultBoatStyleId = ""

    public var characterId: String
    /// Überschreibungen, nil = Farbe des Figurtyps
    public var skinToneId: String?
    public var hairColorId: String?
    public var shirtColorId: String?
    /// Form-Überschreibungen, nil = wie die Vorlage. Werte siehe `AppearanceCatalog.Character`.
    public var hairStyle: String?
    public var build: String?
    /// 0,95 klein · 1,0 mittel · 1,05 gross
    public var heightScale: Double?
    public var shirtStyle: String?
    public var legStyle: String?
    public var beard: String?
    /// vollständige Liste (sunglasses, watch, höchstens eine Kopfbedeckung cap/headband/hijab/patka)
    public var accessories: [String]?
    public var boatStyleId: String
    public var flagOnShirt: Bool
    public var flagOnBoat: Bool
    /// ISO 3166-1 alpha-2; gesetzt aus dem Profil, und nur wenn ein Flaggen-Schalter an ist (`publicAppearance`)
    public var nationality: String?

    public init(characterId: String = RowerAppearance.defaultCharacterId, skinToneId: String? = nil,
                hairColorId: String? = nil, shirtColorId: String? = nil,
                boatStyleId: String = RowerAppearance.defaultBoatStyleId,
                flagOnShirt: Bool = false, flagOnBoat: Bool = false, nationality: String? = nil,
                hairStyle: String? = nil, build: String? = nil, heightScale: Double? = nil,
                shirtStyle: String? = nil, legStyle: String? = nil, beard: String? = nil,
                accessories: [String]? = nil) {
        self.characterId = characterId
        self.hairStyle = hairStyle
        self.build = build
        self.heightScale = heightScale
        self.shirtStyle = shirtStyle
        self.legStyle = legStyle
        self.beard = beard
        self.accessories = accessories
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
        case hairStyle, build, heightScale, shirtStyle, legStyle, beard, accessories
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
        // Form-Überschreibungen (neu 26.11.2026); falscher Typ gilt als „wie die Vorlage“
        hairStyle = (try? c.decodeIfPresent(String.self, forKey: .hairStyle)) ?? nil
        build = (try? c.decodeIfPresent(String.self, forKey: .build)) ?? nil
        heightScale = (try? c.decodeIfPresent(Double.self, forKey: .heightScale)) ?? nil
        shirtStyle = (try? c.decodeIfPresent(String.self, forKey: .shirtStyle)) ?? nil
        legStyle = (try? c.decodeIfPresent(String.self, forKey: .legStyle)) ?? nil
        beard = (try? c.decodeIfPresent(String.self, forKey: .beard)) ?? nil
        accessories = (try? c.decodeIfPresent([String].self, forKey: .accessories)) ?? nil
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
        try c.encodeIfPresent(hairStyle, forKey: .hairStyle)
        try c.encodeIfPresent(build, forKey: .build)
        try c.encodeIfPresent(heightScale, forKey: .heightScale)
        try c.encodeIfPresent(shirtStyle, forKey: .shirtStyle)
        try c.encodeIfPresent(legStyle, forKey: .legStyle)
        try c.encodeIfPresent(beard, forKey: .beard)
        try c.encodeIfPresent(accessories, forKey: .accessories)
    }

    /// Ob irgendeine Form-Eigenschaft von der Vorlage abweicht
    public var hasShapeOverrides: Bool {
        hairStyle != nil || build != nil || heightScale != nil || shirtStyle != nil || legStyle != nil ||
            beard != nil || accessories != nil
    }

    /// Auf die Vorlage zurücksetzen (Farben und Form), Boot und Flaggen bleiben
    public mutating func resetToTemplate(_ characterId: String) {
        self.characterId = characterId
        skinToneId = nil
        hairColorId = nil
        shirtColorId = nil
        hairStyle = nil
        build = nil
        heightScale = nil
        shirtStyle = nil
        legStyle = nil
        beard = nil
        accessories = nil
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
