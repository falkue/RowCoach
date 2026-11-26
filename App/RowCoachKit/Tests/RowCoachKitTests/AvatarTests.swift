import XCTest
@testable import RowCoachKit

/// Kleiner Testkatalog im Format von appearance.json (die echte Datei prüft `testRealCatalogIfPresent`)
private let testCatalogJSON = """
{"version": 1,
 "skinTones": [{"id": "skin-1", "rgb": "#F3D5C0", "name": {"de": "Hell", "en": "Light"}},
               {"id": "skin-2", "rgb": "#7A4E30", "name": {"de": "Dunkel", "en": "Dark"}}],
 "hairColors": [{"id": "hair-black", "rgb": "#1E1A18", "name": {"de": "Schwarz", "en": "Black"}},
                {"id": "hair-blond", "rgb": "D8B46A", "name": {"de": "Blond", "en": "Blond"}}],
 "shirtColors": [{"id": "shirt-navy", "rgb": "#1A2F66", "name": {"de": "Marine", "en": "Navy"}},
                 {"id": "shirt-red", "rgb": "#C4302B", "name": {"de": "Rot", "en": "Red"}}],
 "characters": [{"id": "char-01", "name": {"de": "Kurzhaar", "en": "Short hair"}, "build": "athletic",
                 "heightScale": 1.0, "shoulderScale": 1.05, "skinToneId": "skin-1", "hairStyle": "short",
                 "hairColorId": "hair-black", "shirtColorId": "shirt-navy", "shirtStyle": "tank",
                 "accessories": ["watch"], "description": {"de": "…", "en": "…"}, "futureField": 42},
                {"id": "char-02", "name": {"de": "Locken", "en": "Curls"}, "skinToneId": "skin-2",
                 "hairColorId": "hair-blond", "shirtColorId": "shirt-red"}],
 "boatStyles": [{"id": "boat-a", "name": {"de": "Gelb", "en": "Yellow"}, "inspiredBy": "klassische Holzboote",
                 "hullColor": "#F2C230", "deckColor": "#E8E2D0", "stripeColor": "#000000",
                 "riggerType": "traditional", "riggerColor": "#C8C8C8", "bladeShape": "macon",
                 "bladeColor": "#FFFFFF", "shaftColor": "#222222", "finish": "gloss", "bowBall": true},
                {"id": "boat-b", "name": "Carbon", "hullColor": "#2A2C30", "deckColor": "#3A3D42",
                 "bladeColor": "#F29C4D"}]}
"""

final class AppearanceCatalogTests: XCTestCase {
    private func catalog() throws -> AppearanceCatalog {
        try AppearanceCatalog.load(from: Data(testCatalogJSON.utf8))
    }

    func testLoadsWithDefaultsAndIgnoresUnknownFields() throws {
        let c = try catalog()
        XCTAssertEqual(c.characters.count, 2)
        XCTAssertEqual(c.characters[0].accessories, ["watch"])
        XCTAssertEqual(c.characters[1].build, "athletic")
        XCTAssertEqual(c.characters[1].hairStyle, "short")
        XCTAssertEqual(c.characters[1].heightScale, 1)
        XCTAssertEqual(c.boatStyles[1].name.resolved(languageCode: "en"), "Carbon")
        XCTAssertEqual(c.boatStyles[1].riggerType, "wing")
        XCTAssertNil(c.boatStyles[1].stripe)
        XCTAssertEqual(c.hairColors[1].color, RGBColor(hex: "#D8B46A"))
        XCTAssertEqual(c.characters[0].name.resolved(languageCode: "en"), "Short hair")
    }

    func testMissingListsFallBackToBuiltin() throws {
        let c = try AppearanceCatalog.load(from: Data(#"{"version": 1, "characters": []}"#.utf8))
        XCTAssertEqual(c.characters, AppearanceCatalog.builtin.characters)
        XCTAssertEqual(c.boatStyles, AppearanceCatalog.builtin.boatStyles)
        XCTAssertThrowsError(try AppearanceCatalog.load(from: Data("kein json".utf8)))
    }

    func testHexColors() {
        XCTAssertEqual(RGBColor(hex: "#FF8000"), RGBColor(red: 1, green: 128.0 / 255, blue: 0))
        XCTAssertEqual(RGBColor(hex: "1a2f66")?.hex, "#1A2F66")
        XCTAssertNil(RGBColor(hex: "#12345"))
        XCTAssertNil(RGBColor(hex: "#GG0000"))
        XCTAssertEqual(RGBColor(red: 0, green: 0, blue: 0.01).hex, "#000003")
    }

    func testResolveUsesOverridesThenTypeThenFirst() throws {
        let c = try catalog()
        // Farben des Typs
        var a = RowerAppearance(characterId: "char-02", boatStyleId: "boat-b")
        var r = c.resolve(a)
        XCTAssertEqual(r.character.id, "char-02")
        XCTAssertEqual(r.skinToneId, "skin-2")
        XCTAssertEqual(r.hairColorId, "hair-blond")
        XCTAssertEqual(r.shirt, RGBColor(hex: "#C4302B"))
        XCTAssertEqual(r.boat.id, "boat-b")
        // Überschreibungen
        a.skinToneId = "skin-1"
        a.shirtColorId = "shirt-navy"
        r = c.resolve(a)
        XCTAssertEqual(r.skinToneId, "skin-1")
        XCTAssertEqual(r.shirtColorId, "shirt-navy")
        // unbekannte Ids → Typ bzw. erster Eintrag
        a = RowerAppearance(characterId: "char-99", skinToneId: "skin-x", boatStyleId: "boat-neu")
        r = c.resolve(a)
        XCTAssertEqual(r.character.id, "char-01")
        XCTAssertEqual(r.skinToneId, "skin-1")
        XCTAssertEqual(r.boat.id, "boat-a")
        XCTAssertNil(r.shirtFlag)
    }

    func testNormalizedDropsUnknownIds() throws {
        let c = try catalog()
        let n = c.normalized(RowerAppearance(characterId: "x", skinToneId: "skin-2", hairColorId: "nope",
                                             boatStyleId: "", flagOnShirt: true))
        XCTAssertEqual(n.characterId, "char-01")
        XCTAssertEqual(n.boatStyleId, "boat-a")
        XCTAssertEqual(n.skinToneId, "skin-2")
        XCTAssertNil(n.hairColorId)
        XCTAssertTrue(n.flagOnShirt)
    }

    func testValidate() throws {
        var c = try catalog()
        let base = c.validate()
        // nur die Anzahlen weichen von der SPEC ab
        XCTAssertEqual(base.count, 2, "\(base)")
        XCTAssertTrue(base.contains { $0.contains("10") })
        c.characters.append(c.characters[0])
        c.characters[2].hairColorId = "hair-pink"
        c.skinTones[0].rgb = "rot"
        c.boatStyles[0].bladeColor = "#12"
        c.version = 2
        let issues = c.validate()
        XCTAssertTrue(issues.contains("characters: doppelte Id char-01"), "\(issues)")
        XCTAssertTrue(issues.contains { $0.contains("hair-pink") })
        XCTAssertTrue(issues.contains { $0.contains("skin-1: ungültige Farbe") })
        XCTAssertTrue(issues.contains { $0.contains("bladeColor") })
        XCTAssertTrue(issues.contains { $0.hasPrefix("version 2") })
    }

    func testBuiltinCatalogIsValid() {
        let issues = AppearanceCatalog.builtin.validate()
        // eingebaut: 10 Typen, aber nur 3 Boote (Ersatz)
        XCTAssertEqual(issues, ["boatStyles: 3 Stile (SPEC: 6–8)"])
    }

    /// Die echte appearance.json der Gestaltung (sobald vorhanden) muss laden und gültig sein
    func testRealCatalogIfPresent() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("RowCoach/Resources/appearance.json")
        guard let data = try? Data(contentsOf: url) else { throw XCTSkip("appearance.json noch nicht vorhanden") }
        let c = try AppearanceCatalog.load(from: data)
        XCTAssertEqual(c.validate(), [])
        // jede Figur löst ohne Ersatzwerte auf
        for ch in c.characters {
            let r = c.resolve(RowerAppearance(characterId: ch.id, boatStyleId: c.boatStyles[0].id))
            XCTAssertEqual(r.skinToneId, ch.skinToneId)
            XCTAssertEqual(r.hairColorId, ch.hairColorId)
            XCTAssertEqual(r.shirtColorId, ch.shirtColorId)
        }
    }
}

final class RowerProfileTests: XCTestCase {
    func testPublicAppearanceHidesNationalityWithoutFlag() {
        var p = RowerProfile(displayName: "Falk", nationality: "ch", gender: .male,
                             appearance: RowerAppearance(characterId: "char-03", boatStyleId: "boat-white"))
        XCTAssertEqual(p.nationality, "CH")
        XCTAssertNil(p.publicAppearance.nationality)
        XCTAssertNil(p.publicAppearance.shirtFlag)

        p.appearance.flagOnBoat = true
        XCTAssertEqual(p.publicAppearance.nationality, "CH")
        XCTAssertEqual(p.publicAppearance.boatFlag, "🇨🇭")
        XCTAssertNil(p.publicAppearance.shirtFlag)

        p.appearance.flagOnShirt = true
        p.appearance.flagOnBoat = false
        XCTAssertEqual(p.publicAppearance.shirtFlag, "🇨🇭")
        XCTAssertNil(p.publicAppearance.boatFlag)
    }

    func testFlagsOffWithoutNationality() {
        let p = RowerProfile(nationality: nil,
                             appearance: RowerAppearance(flagOnShirt: true, flagOnBoat: true, nationality: "DE"))
        let pub = p.publicAppearance
        XCTAssertFalse(pub.flagOnShirt)
        XCTAssertFalse(pub.flagOnBoat)
        XCTAssertNil(pub.nationality, "eine alte Nationalität in der Erscheinung darf nicht durchrutschen")
    }

    func testGenderAndNameNeverInAppearanceJSON() throws {
        var p = RowerProfile(displayName: "Geheim", nationality: "SE", gender: .diverse)
        p.appearance.flagOnShirt = true
        let json = String(decoding: try JSONEncoder().encode(p.publicAppearance), as: UTF8.self)
        XCTAssertFalse(json.contains("gender"))
        XCTAssertFalse(json.contains("diverse"))
        XCTAssertFalse(json.contains("Geheim"))
        XCTAssertTrue(json.contains("\"SE\""))
    }

    func testRoundTripAndTolerantDecoding() throws {
        var p = RowerProfile(displayName: "Anna", nationality: "NO", gender: .female)
        p.appearance = RowerAppearance(characterId: "char-05", hairColorId: "hair-red", boatStyleId: "boat-carbon",
                                       flagOnShirt: true)
        XCTAssertEqual(RowerProfile.decode(p.encoded()), p)
        XCTAssertEqual(p.encoded(), p.encoded())

        // fehlende Felder, unbekanntes Geschlecht, ungültige Nationalität
        let old = #"{"displayName": "X", "gender": "other", "nationality": "ZZ", "appearance": {"characterId": "char-02"}}"#
        let q = RowerProfile.decode(Data(old.utf8))
        XCTAssertEqual(q.displayName, "X")
        XCTAssertNil(q.gender)
        XCTAssertNil(q.nationality)
        XCTAssertEqual(q.appearance.characterId, "char-02")
        XCTAssertEqual(q.appearance.boatStyleId, RowerAppearance.defaultBoatStyleId)
        XCTAssertFalse(q.appearance.flagOnBoat)

        XCTAssertEqual(RowerProfile.decode(nil), RowerProfile())
        XCTAssertEqual(RowerProfile.decode(Data("{".utf8)), RowerProfile())
        XCTAssertEqual(RowerProfile.decode(Data("{}".utf8)), RowerProfile())
    }

    func testResolvedDisplayName() {
        XCTAssertEqual(RowerProfile(displayName: "  ").resolvedDisplayName(fallback: "Ich"), "Ich")
        XCTAssertEqual(RowerProfile(displayName: " Falk ").resolvedDisplayName(fallback: "Ich"), "Falk")
        let long = String(repeating: "x", count: 40)
        XCTAssertEqual(RowerProfile(displayName: long).resolvedDisplayName(fallback: "Ich").count,
                       RowerProfile.maxDisplayNameLength)
    }

    func testRandomIsStablePerSeedAndVaried() throws {
        let c = try AppearanceCatalog.load(from: Data(testCatalogJSON.utf8))
        let a = RowerAppearance.random(seed: "bot-a", catalog: c)
        XCTAssertEqual(a, RowerAppearance.random(seed: "bot-a", catalog: c))
        XCTAssertFalse(a.flagOnShirt || a.flagOnBoat)
        XCTAssertNil(a.nationality)
        XCTAssertNotNil(c.character(a.characterId))
        XCTAssertNotNil(c.boatStyle(a.boatStyleId))
        XCTAssertNotNil(c.shirtColor(a.shirtColorId))
        // feste Werte: dieselbe Erscheinung auch nach Neustart und auf anderen Plattformen
        XCTAssertEqual(SeededGenerator(seed: "bot-a").first3, SeededGenerator(seed: "bot-a").first3)
        let builtin = (0..<40).map { RowerAppearance.random(seed: "traffic-\($0)", catalog: .builtin) }
        XCTAssertGreaterThan(Set(builtin.map(\.characterId)).count, 5)
        XCTAssertGreaterThan(Set(builtin.map(\.boatStyleId)).count, 1)
    }

    func testRandomKnownValues() {
        // FNV-1a/SplitMix64 sind festgelegt: diese Werte dürfen sich nie ändern (sonst wechseln Bots ihr Aussehen)
        var g = SeededGenerator(seed: "")
        XCTAssertEqual(g.next(), SeededGenerator.splitMix(0xcbf2_9ce4_8422_2325 &+ 0x9E37_79B9_7F4A_7C15))
    }
}

private extension SeededGenerator {
    var first3: [UInt64] { var g = self; return [g.next(), g.next(), g.next()] }

    static func splitMix(_ s: UInt64) -> UInt64 {
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

final class CountryListTests: XCTestCase {
    func testAllCodes() {
        XCTAssertEqual(CountryList.codes.count, 249)
        XCTAssertEqual(Set(CountryList.codes).count, 249)
        XCTAssertTrue(CountryList.codes.allSatisfy { $0.count == 2 && $0 == $0.uppercased() })
        XCTAssertFalse(CountryList.isValid("EU"))
        XCTAssertTrue(CountryList.isValid("ch"))
        XCTAssertEqual(CountryList.normalized(" de "), "DE")
        XCTAssertNil(CountryList.normalized(""))
        XCTAssertNil(CountryList.normalized(nil))
    }

    func testFlagsAndNames() {
        let all = CountryList.all(languageCode: "de")
        XCTAssertEqual(all.count, 249)
        XCTAssertTrue(all.allSatisfy { $0.flag.unicodeScalars.count == 2 })
        XCTAssertEqual(CountryList.country("ch", languageCode: "de")?.flag, "🇨🇭")
        XCTAssertNil(CountryList.country("XX", languageCode: "de"))
        // Namen nur prüfen, wenn die Plattform sie kennt (Linux/Android können ohne ICU-Daten den Code zeigen)
        let ch = CountryList.name("CH", languageCode: "de")
        if ch != "CH" {
            XCTAssertEqual(ch, "Schweiz")
            XCTAssertEqual(CountryList.name("CH", languageCode: "en"), "Switzerland")
            // sortiert nach Namen, Akzente ignoriert: Österreich unter O
            let names = all.map(\.name)
            let oe = names.firstIndex(of: "Österreich")!, om = names.firstIndex(of: "Oman")!, pk = names.firstIndex(of: "Pakistan")!
            XCTAssertLessThan(om, oe)
            XCTAssertLessThan(oe, pk)
        }
    }

    func testSearch() {
        XCTAssertEqual(CountryList.search("", languageCode: "de").count, 249)
        XCTAssertEqual(CountryList.search("ch", languageCode: "de").first { $0.code == "CH" }?.code, "CH")
        if CountryList.name("CH", languageCode: "de") != "CH" {
            XCTAssertTrue(CountryList.search("schwei", languageCode: "de").contains { $0.code == "CH" })
            XCTAssertTrue(CountryList.search("switz", languageCode: "de").contains { $0.code == "CH" })
            XCTAssertTrue(CountryList.search("osterr", languageCode: "de").contains { $0.code == "AT" })
        }
    }
}

final class RaceParticipantAppearanceTests: XCTestCase {
    func testOldJSONWithoutAppearanceDecodes() throws {
        let old = #"{"id": "p1", "displayName": "Ben", "lane": 3, "source": "bot"}"#
        let p = try JSONDecoder().decode(RaceParticipant.self, from: Data(old.utf8))
        XCTAssertEqual(p, RaceParticipant(id: "p1", displayName: "Ben", lane: 3, source: .bot))
        XCTAssertNil(p.appearance)
        // ohne Erscheinung: stabile zufällige
        XCTAssertEqual(p.resolvedAppearance(catalog: .builtin), RowerAppearance.random(seed: "p1", catalog: .builtin))
        // nil wird nicht mitgeschickt
        let json = String(decoding: try JSONEncoder().encode(p), as: UTF8.self)
        XCTAssertFalse(json.contains("appearance"))
    }

    func testAppearanceRoundTrip() throws {
        var profile = RowerProfile(displayName: "Falk", nationality: "CH", gender: .male)
        profile.appearance = RowerAppearance(characterId: "char-04", shirtColorId: "shirt-red",
                                             boatStyleId: "boat-carbon", flagOnShirt: true)
        let me = RaceParticipant(id: "me", displayName: "Falk", lane: 2, appearance: profile.publicAppearance)
        let back = try JSONDecoder().decode(RaceParticipant.self, from: JSONEncoder().encode(me))
        XCTAssertEqual(back, me)
        XCTAssertEqual(back.appearance?.nationality, "CH")
        XCTAssertEqual(back.resolvedAppearance(), me.appearance)
        // eine knappe Erscheinung eines anderen Clients (nur Figur) dekodiert mit Standardwerten
        let sparse = #"{"id": "x", "displayName": "X", "lane": 1, "source": "human", "appearance": {"characterId": "char-07"}}"#
        let x = try JSONDecoder().decode(RaceParticipant.self, from: Data(sparse.utf8))
        XCTAssertEqual(x.appearance?.characterId, "char-07")
        XCTAssertNil(x.appearance?.shirtFlag)
    }
}
