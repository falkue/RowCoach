import Foundation

// Katalog der Figuren, Farben und Bootsstile (`App/RowCoach/Resources/appearance.json`, Format in
// docs/avatar/SPEC.md). Lädt tolerant (fehlende Felder → Standardwerte, unbekannte Felder werden ignoriert), löst
// Ids einer `RowerAppearance` zu Farben auf (mit Ersatzwerten für unbekannte Ids) und prüft den Katalog.

/// Farbe als RGB (0…1), aus "#RRGGBB" bzw. "RRGGBB"
public struct RGBColor: Equatable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        red = Double((v >> 16) & 0xFF) / 255
        green = Double((v >> 8) & 0xFF) / 255
        blue = Double(v & 0xFF) / 255
    }

    /// "#RRGGBB"
    public var hex: String {
        func b(_ x: Double) -> Int { Int((min(max(x, 0), 1) * 255).rounded()) }
        let v = (b(red) << 16) | (b(green) << 8) | b(blue)
        let digits = String(v, radix: 16, uppercase: true)
        return "#" + String(repeating: "0", count: 6 - digits.count) + digits
    }

    public static let neutralGray = RGBColor(red: 0.5, green: 0.5, blue: 0.5)
}

public struct AppearanceCatalog: Codable, Equatable, Sendable {
    /// Farbe mit Id und Namen (Hautton, Haarfarbe, Trikotfarbe)
    public struct ColorEntry: Codable, Equatable, Hashable, Sendable, Identifiable {
        public var id: String
        /// "#RRGGBB"
        public var rgb: String
        public var name: LocalizedText

        public init(id: String, rgb: String, name: LocalizedText) {
            self.id = id
            self.rgb = rgb
            self.name = name
        }

        enum CodingKeys: String, CodingKey { case id, rgb, name }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            rgb = try c.decodeIfPresent(String.self, forKey: .rgb) ?? "#808080"
            name = try c.decodeIfPresent(LocalizedText.self, forKey: .name) ?? LocalizedText(id)
        }

        public var color: RGBColor { RGBColor(hex: rgb) ?? .neutralGray }
    }

    /// Figurtyp: Erscheinung (nicht Geschlecht oder Herkunft). Freie Texte (`build`, `hairStyle`, `shirtStyle`,
    /// `accessories`) bleiben Strings, damit neue Werte der Gestaltung ältere App-Versionen nicht brechen.
    public struct Character: Codable, Equatable, Hashable, Sendable, Identifiable {
        public var id: String
        public var name: LocalizedText
        /// slim | athletic | broad
        public var build: String
        public var heightScale: Double
        public var shoulderScale: Double
        public var skinToneId: String
        /// short | buzz | ponytail | bun | braid | curly | afro | long | bald | cap | headband
        public var hairStyle: String
        public var hairColorId: String
        public var shirtColorId: String
        /// tank | tee | unisuit
        public var shirtStyle: String
        public var accessories: [String]
        public var description: LocalizedText?

        public init(id: String, name: LocalizedText, build: String = "athletic", heightScale: Double = 1,
                    shoulderScale: Double = 1, skinToneId: String, hairStyle: String = "short", hairColorId: String,
                    shirtColorId: String, shirtStyle: String = "tank", accessories: [String] = [],
                    description: LocalizedText? = nil) {
            self.id = id
            self.name = name
            self.build = build
            self.heightScale = heightScale
            self.shoulderScale = shoulderScale
            self.skinToneId = skinToneId
            self.hairStyle = hairStyle
            self.hairColorId = hairColorId
            self.shirtColorId = shirtColorId
            self.shirtStyle = shirtStyle
            self.accessories = accessories
            self.description = description
        }

        enum CodingKeys: String, CodingKey {
            case id, name, build, heightScale, shoulderScale, skinToneId, hairStyle, hairColorId, shirtColorId,
                 shirtStyle, accessories, description
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            name = try c.decodeIfPresent(LocalizedText.self, forKey: .name) ?? LocalizedText(id)
            build = try c.decodeIfPresent(String.self, forKey: .build) ?? "athletic"
            heightScale = try c.decodeIfPresent(Double.self, forKey: .heightScale) ?? 1
            shoulderScale = try c.decodeIfPresent(Double.self, forKey: .shoulderScale) ?? 1
            skinToneId = try c.decodeIfPresent(String.self, forKey: .skinToneId) ?? ""
            hairStyle = try c.decodeIfPresent(String.self, forKey: .hairStyle) ?? "short"
            hairColorId = try c.decodeIfPresent(String.self, forKey: .hairColorId) ?? ""
            shirtColorId = try c.decodeIfPresent(String.self, forKey: .shirtColorId) ?? ""
            shirtStyle = try c.decodeIfPresent(String.self, forKey: .shirtStyle) ?? "tank"
            accessories = try c.decodeIfPresent([String].self, forKey: .accessories) ?? []
            description = try c.decodeIfPresent(LocalizedText.self, forKey: .description)
        }
    }

    /// Bootsstil (generische Anzeige, Herstellernamen höchstens in `inspiredBy`)
    public struct BoatStyle: Codable, Equatable, Hashable, Sendable, Identifiable {
        public var id: String
        public var name: LocalizedText
        public var inspiredBy: String?
        public var hullColor: String
        public var deckColor: String
        public var stripeColor: String?
        /// wing | traditional | backwing
        public var riggerType: String
        public var riggerColor: String
        /// macon | bigblade | fat2
        public var bladeShape: String
        public var bladeColor: String
        public var shaftColor: String
        /// gloss | matte | carbon
        public var finish: String
        public var bowBall: Bool
        public var description: LocalizedText?

        public init(id: String, name: LocalizedText, inspiredBy: String? = nil, hullColor: String,
                    deckColor: String, stripeColor: String? = nil, riggerType: String = "wing",
                    riggerColor: String = "#2B2B2B", bladeShape: String = "bigblade", bladeColor: String,
                    shaftColor: String = "#1E1E1E", finish: String = "gloss", bowBall: Bool = true,
                    description: LocalizedText? = nil) {
            self.id = id
            self.name = name
            self.inspiredBy = inspiredBy
            self.hullColor = hullColor
            self.deckColor = deckColor
            self.stripeColor = stripeColor
            self.riggerType = riggerType
            self.riggerColor = riggerColor
            self.bladeShape = bladeShape
            self.bladeColor = bladeColor
            self.shaftColor = shaftColor
            self.finish = finish
            self.bowBall = bowBall
            self.description = description
        }

        enum CodingKeys: String, CodingKey {
            case id, name, inspiredBy, hullColor, deckColor, stripeColor, riggerType, riggerColor, bladeShape,
                 bladeColor, shaftColor, finish, bowBall, description
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            name = try c.decodeIfPresent(LocalizedText.self, forKey: .name) ?? LocalizedText(id)
            inspiredBy = try c.decodeIfPresent(String.self, forKey: .inspiredBy)
            hullColor = try c.decodeIfPresent(String.self, forKey: .hullColor) ?? "#F2F2F2"
            deckColor = try c.decodeIfPresent(String.self, forKey: .deckColor) ?? "#E0E0E0"
            stripeColor = try c.decodeIfPresent(String.self, forKey: .stripeColor)
            riggerType = try c.decodeIfPresent(String.self, forKey: .riggerType) ?? "wing"
            riggerColor = try c.decodeIfPresent(String.self, forKey: .riggerColor) ?? "#2B2B2B"
            bladeShape = try c.decodeIfPresent(String.self, forKey: .bladeShape) ?? "bigblade"
            bladeColor = try c.decodeIfPresent(String.self, forKey: .bladeColor) ?? "#FFFFFF"
            shaftColor = try c.decodeIfPresent(String.self, forKey: .shaftColor) ?? "#1E1E1E"
            finish = try c.decodeIfPresent(String.self, forKey: .finish) ?? "gloss"
            bowBall = try c.decodeIfPresent(Bool.self, forKey: .bowBall) ?? true
            description = try c.decodeIfPresent(LocalizedText.self, forKey: .description)
        }

        public var hull: RGBColor { RGBColor(hex: hullColor) ?? .neutralGray }
        public var deck: RGBColor { RGBColor(hex: deckColor) ?? hull }
        public var stripe: RGBColor? { stripeColor.flatMap(RGBColor.init(hex:)) }
        public var rigger: RGBColor { RGBColor(hex: riggerColor) ?? .neutralGray }
        public var blade: RGBColor { RGBColor(hex: bladeColor) ?? .neutralGray }
        public var shaft: RGBColor { RGBColor(hex: shaftColor) ?? .neutralGray }
    }

    public var version: Int
    public var skinTones: [ColorEntry]
    public var hairColors: [ColorEntry]
    public var shirtColors: [ColorEntry]
    public var characters: [Character]
    public var boatStyles: [BoatStyle]

    public init(version: Int = 1, skinTones: [ColorEntry], hairColors: [ColorEntry], shirtColors: [ColorEntry],
                characters: [Character], boatStyles: [BoatStyle]) {
        self.version = version
        self.skinTones = skinTones
        self.hairColors = hairColors
        self.shirtColors = shirtColors
        self.characters = characters
        self.boatStyles = boatStyles
    }

    enum CodingKeys: String, CodingKey { case version, skinTones, hairColors, shirtColors, characters, boatStyles }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        skinTones = try c.decodeIfPresent([ColorEntry].self, forKey: .skinTones) ?? []
        hairColors = try c.decodeIfPresent([ColorEntry].self, forKey: .hairColors) ?? []
        shirtColors = try c.decodeIfPresent([ColorEntry].self, forKey: .shirtColors) ?? []
        characters = try c.decodeIfPresent([Character].self, forKey: .characters) ?? []
        boatStyles = try c.decodeIfPresent([BoatStyle].self, forKey: .boatStyles) ?? []
    }

    /// Katalog aus JSON (Fehler bei kaputtem JSON; fehlende Listen werden leer und mit dem eingebauten Katalog
    /// ergänzt, damit es immer Figuren, Farben und Boote gibt)
    public static func load(from data: Data) throws -> AppearanceCatalog {
        try JSONDecoder().decode(AppearanceCatalog.self, from: data).filledFromBuiltin()
    }

    /// Katalog, den Bots und Szene ohne ausdrückliche Angabe benutzen. Die App setzt ihn einmal beim Start aus
    /// appearance.json (`RowerProfileStore`); bis dahin und auf Linux gilt `builtin`.
    nonisolated(unsafe) public static var current: AppearanceCatalog = .builtin

    /// Leere Listen durch die des eingebauten Katalogs ersetzen
    func filledFromBuiltin() -> AppearanceCatalog {
        var c = self
        let b = AppearanceCatalog.builtin
        if c.skinTones.isEmpty { c.skinTones = b.skinTones }
        if c.hairColors.isEmpty { c.hairColors = b.hairColors }
        if c.shirtColors.isEmpty { c.shirtColors = b.shirtColors }
        if c.characters.isEmpty { c.characters = b.characters }
        if c.boatStyles.isEmpty { c.boatStyles = b.boatStyles }
        return c
    }

    // MARK: Nachschlagen und Auflösen

    public func character(_ id: String?) -> Character? { id.flatMap { i in characters.first { $0.id == i } } }
    public func boatStyle(_ id: String?) -> BoatStyle? { id.flatMap { i in boatStyles.first { $0.id == i } } }
    public func skinTone(_ id: String?) -> ColorEntry? { id.flatMap { i in skinTones.first { $0.id == i } } }
    public func hairColor(_ id: String?) -> ColorEntry? { id.flatMap { i in hairColors.first { $0.id == i } } }
    public func shirtColor(_ id: String?) -> ColorEntry? { id.flatMap { i in shirtColors.first { $0.id == i } } }

    /// Aufgelöste Erscheinung: Figurtyp, Farben und Boot, alle mit Ersatzwerten
    public struct Resolved: Equatable, Sendable {
        public var character: Character
        public var skinToneId: String
        public var hairColorId: String
        public var shirtColorId: String
        public var skin: RGBColor
        public var hair: RGBColor
        public var shirt: RGBColor
        public var boat: BoatStyle
        /// Flaggen-Emoji fürs Trikot bzw. Boot (nil = keine Flagge)
        public var shirtFlag: String?
        public var boatFlag: String?
    }

    /// Ids zu Farben: Überschreibung der Erscheinung → Farbe des Figurtyps → erste Farbe der Liste → Grau.
    /// Unbekannter Figurtyp → erster Typ; unbekanntes Boot → erstes Boot.
    public func resolve(_ a: RowerAppearance) -> Resolved {
        let ch = character(a.characterId) ?? characters.first ?? AppearanceCatalog.builtin.characters[0]
        let boat = boatStyle(a.boatStyleId) ?? boatStyles.first ?? AppearanceCatalog.builtin.boatStyles[0]
        func pick(_ override: String?, _ typeDefault: String, _ list: [ColorEntry]) -> ColorEntry? {
            if let o = override, let e = list.first(where: { $0.id == o }) { return e }
            if let e = list.first(where: { $0.id == typeDefault }) { return e }
            return list.first
        }
        let skin = pick(a.skinToneId, ch.skinToneId, skinTones)
        let hair = pick(a.hairColorId, ch.hairColorId, hairColors)
        let shirt = pick(a.shirtColorId, ch.shirtColorId, shirtColors)
        return Resolved(character: ch,
                        skinToneId: skin?.id ?? "", hairColorId: hair?.id ?? "", shirtColorId: shirt?.id ?? "",
                        skin: skin?.color ?? .neutralGray, hair: hair?.color ?? .neutralGray,
                        shirt: shirt?.color ?? .neutralGray, boat: boat,
                        shirtFlag: a.shirtFlag, boatFlag: a.boatFlag)
    }

    /// Erscheinung mit gültigen Ids: unbekannte Figur/Boot → erster Eintrag, unbekannte Farb-Überschreibungen → nil
    public func normalized(_ a: RowerAppearance) -> RowerAppearance {
        var n = a
        if character(a.characterId) == nil { n.characterId = characters.first?.id ?? a.characterId }
        if boatStyle(a.boatStyleId) == nil { n.boatStyleId = boatStyles.first?.id ?? a.boatStyleId }
        if skinTone(a.skinToneId) == nil { n.skinToneId = nil }
        if hairColor(a.hairColorId) == nil { n.hairColorId = nil }
        if shirtColor(a.shirtColorId) == nil { n.shirtColorId = nil }
        return n
    }

    // MARK: Prüfung

    /// Probleme des Katalogs (leer = in Ordnung): Version, leere Listen, doppelte Ids, ungültige Farben, Verweise
    /// der Figurtypen auf unbekannte Farben, Anzahl Figurtypen (SPEC: 10) und Bootsstile (6–8)
    public func validate() -> [String] {
        var issues: [String] = []
        if version != 1 { issues.append("version \(version) (erwartet 1)") }
        func checkColors(_ list: [ColorEntry], _ label: String) {
            if list.isEmpty { issues.append("\(label): leer") }
            for id in duplicates(list.map(\.id)) { issues.append("\(label): doppelte Id \(id)") }
            for e in list where RGBColor(hex: e.rgb) == nil { issues.append("\(label) \(e.id): ungültige Farbe \(e.rgb)") }
        }
        checkColors(skinTones, "skinTones")
        checkColors(hairColors, "hairColors")
        checkColors(shirtColors, "shirtColors")
        if characters.isEmpty { issues.append("characters: leer") }
        for id in duplicates(characters.map(\.id)) { issues.append("characters: doppelte Id \(id)") }
        for c in characters {
            if skinTone(c.skinToneId) == nil { issues.append("character \(c.id): unbekannter Hautton \(c.skinToneId)") }
            if hairColor(c.hairColorId) == nil { issues.append("character \(c.id): unbekannte Haarfarbe \(c.hairColorId)") }
            if shirtColor(c.shirtColorId) == nil { issues.append("character \(c.id): unbekannte Trikotfarbe \(c.shirtColorId)") }
            if !(0.7...1.3).contains(c.heightScale) { issues.append("character \(c.id): heightScale \(c.heightScale) ausserhalb 0.7–1.3") }
            if !(0.7...1.3).contains(c.shoulderScale) { issues.append("character \(c.id): shoulderScale \(c.shoulderScale) ausserhalb 0.7–1.3") }
        }
        if !characters.isEmpty && characters.count != 10 { issues.append("characters: \(characters.count) Typen (SPEC: 10)") }
        if boatStyles.isEmpty { issues.append("boatStyles: leer") }
        for id in duplicates(boatStyles.map(\.id)) { issues.append("boatStyles: doppelte Id \(id)") }
        for b in boatStyles {
            let colors = [("hullColor", b.hullColor), ("deckColor", b.deckColor), ("riggerColor", b.riggerColor),
                          ("bladeColor", b.bladeColor), ("shaftColor", b.shaftColor)] + (b.stripeColor.map { [("stripeColor", $0)] } ?? [])
            for (field, v) in colors where RGBColor(hex: v) == nil { issues.append("boatStyle \(b.id): ungültige Farbe \(field) \(v)") }
        }
        if !boatStyles.isEmpty && !(6...8).contains(boatStyles.count) { issues.append("boatStyles: \(boatStyles.count) Stile (SPEC: 6–8)") }
        return issues
    }

    private func duplicates(_ ids: [String]) -> [String] {
        var seen = Set<String>(), dup: [String] = []
        for id in ids { if !seen.insert(id).inserted, !dup.contains(id) { dup.append(id) } }
        return dup
    }
}

// MARK: Eingebauter Ersatzkatalog

extension AppearanceCatalog {
    private static func t(_ de: String, _ en: String) -> LocalizedText { LocalizedText(values: ["de": de, "en": en]) }

    /// Kleiner Ersatz, solange appearance.json fehlt oder unlesbar ist (und für Tests unter Linux). Die echten
    /// Typen, Farben und Boote kommen aus der Gestaltung (docs/avatar/DESIGN.md).
    public static let builtin = AppearanceCatalog(
        version: 1,
        skinTones: [
            ColorEntry(id: "skin-1", rgb: "#F3D5C0", name: t("Sehr hell", "Very light")),
            ColorEntry(id: "skin-2", rgb: "#E8B998", name: t("Hell", "Light")),
            ColorEntry(id: "skin-3", rgb: "#D19A6E", name: t("Mittel", "Medium")),
            ColorEntry(id: "skin-4", rgb: "#A8714A", name: t("Gebräunt", "Tan")),
            ColorEntry(id: "skin-5", rgb: "#7A4E30", name: t("Dunkel", "Dark")),
            ColorEntry(id: "skin-6", rgb: "#4E3020", name: t("Sehr dunkel", "Very dark")),
        ],
        hairColors: [
            ColorEntry(id: "hair-black", rgb: "#1E1A18", name: t("Schwarz", "Black")),
            ColorEntry(id: "hair-brown", rgb: "#5A3A22", name: t("Braun", "Brown")),
            ColorEntry(id: "hair-blond", rgb: "#D8B46A", name: t("Blond", "Blond")),
            ColorEntry(id: "hair-red", rgb: "#A0461E", name: t("Rot", "Red")),
            ColorEntry(id: "hair-grey", rgb: "#A8A8A8", name: t("Grau", "Grey")),
        ],
        shirtColors: [
            ColorEntry(id: "shirt-navy", rgb: "#1A2F66", name: t("Marineblau", "Navy")),
            ColorEntry(id: "shirt-red", rgb: "#C4302B", name: t("Rot", "Red")),
            ColorEntry(id: "shirt-white", rgb: "#F2F2F2", name: t("Weiss", "White")),
            ColorEntry(id: "shirt-green", rgb: "#2E7D4F", name: t("Grün", "Green")),
            ColorEntry(id: "shirt-orange", rgb: "#F29C4D", name: t("Orange", "Orange")),
            ColorEntry(id: "shirt-black", rgb: "#222222", name: t("Schwarz", "Black")),
        ],
        characters: [
            Character(id: "char-01", name: t("Kurzhaar", "Short hair"), skinToneId: "skin-2", hairStyle: "short",
                      hairColorId: "hair-brown", shirtColorId: "shirt-navy"),
            Character(id: "char-02", name: t("Pferdeschwanz", "Ponytail"), build: "slim", skinToneId: "skin-1",
                      hairStyle: "ponytail", hairColorId: "hair-blond", shirtColorId: "shirt-red"),
            Character(id: "char-03", name: t("Locken", "Curls"), skinToneId: "skin-4", hairStyle: "curly",
                      hairColorId: "hair-black", shirtColorId: "shirt-green"),
            Character(id: "char-04", name: t("Glatze mit Sonnenbrille", "Bald with sunglasses"), build: "broad",
                      skinToneId: "skin-5", hairStyle: "bald", hairColorId: "hair-black",
                      shirtColorId: "shirt-white", accessories: ["sunglasses"]),
            Character(id: "char-05", name: t("Dutt", "Bun"), build: "slim", skinToneId: "skin-3", hairStyle: "bun",
                      hairColorId: "hair-brown", shirtColorId: "shirt-orange"),
            Character(id: "char-06", name: t("Afro", "Afro"), skinToneId: "skin-6", hairStyle: "afro",
                      hairColorId: "hair-black", shirtColorId: "shirt-navy"),
            Character(id: "char-07", name: t("Mütze", "Cap"), skinToneId: "skin-2", hairStyle: "cap",
                      hairColorId: "hair-red", shirtColorId: "shirt-black", accessories: ["cap"]),
            Character(id: "char-08", name: t("Zopf", "Braid"), build: "slim", skinToneId: "skin-4", hairStyle: "braid",
                      hairColorId: "hair-black", shirtColorId: "shirt-white"),
            Character(id: "char-09", name: t("Grau mit Stirnband", "Grey with headband"), build: "broad",
                      skinToneId: "skin-1", hairStyle: "headband", hairColorId: "hair-grey",
                      shirtColorId: "shirt-red", accessories: ["headband"]),
            Character(id: "char-10", name: t("Langes Haar", "Long hair"), skinToneId: "skin-3", hairStyle: "long",
                      hairColorId: "hair-brown", shirtColorId: "shirt-green"),
        ],
        boatStyles: [
            BoatStyle(id: "boat-classic-yellow", name: t("Klassisch Gelb", "Classic yellow"), hullColor: "#F2C230",
                      deckColor: "#E8E2D0", riggerType: "traditional", riggerColor: "#C8C8C8",
                      bladeShape: "macon", bladeColor: "#FFFFFF"),
            BoatStyle(id: "boat-white-blue-stripe", name: t("Weiss", "White"), hullColor: "#F4F4F4", deckColor: "#D8D8D8",
                      stripeColor: "#1A2F66", bladeColor: "#1A2F66"),
            BoatStyle(id: "boat-carbon-black", name: t("Carbon", "Carbon"), hullColor: "#2A2C30", deckColor: "#3A3D42",
                      riggerType: "backwing", bladeColor: "#F29C4D", finish: "carbon"),
        ])
}
