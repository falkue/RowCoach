import XCTest
@testable import RowCoachKit

final class CourseInfoTests: XCTestCase {
    private func course(extra: String) throws -> Course {
        let json = """
        {"id": "x", "title": "X", "region": "R", "scene": "s", "qualities": ["standard"], "one_way_m": 1000,
         "total_m": 2000, "turns": 1, "lake_level_m": 400, "path_xz": [[0, 0], [0, -1000]], "attribution": "© A"\(extra)}
        """
        return try Course.decode(Data(json.utf8))
    }

    func testOldPackagesHaveNoInfo() throws {
        let c = try course(extra: "")
        XCTAssertNil(c.description)
        XCTAssertNil(c.highlights)
        XCTAssertNil(c.bridges)
    }

    func testPlainAndLocalizedText() throws {
        let c = try course(extra: """
        , "description": {"de": "Ruhige Strecke.", "en": "Calm course."},
          "highlights": [{"name": "Münster", "side": "links", "note": {"de": "Turm", "en": "Tower"}},
                         {"name": {"de": "Brücke", "en": "Bridge"}, "side": "voraus"},
                         {"name": "Seltsam", "side": "oben"},
                         {"side": "rechts"}],
          "bridges": ["Wettsteinbrücke", "Mittlere Brücke"]
        """)
        XCTAssertEqual(c.description?.resolved(languageCode: "de"), "Ruhige Strecke.")
        XCTAssertEqual(c.description?.resolved(languageCode: "en"), "Calm course.")
        XCTAssertEqual(c.description?.resolved(languageCode: "fr"), "Ruhige Strecke.", "Rückfall auf Deutsch")
        XCTAssertEqual(c.highlights?.count, 3, "Eintrag ohne Namen fällt weg")
        XCTAssertEqual(c.highlights?[0].name.resolved(languageCode: "en"), "Münster", "einfacher String für alle")
        XCTAssertEqual(c.highlights?[0].side, .left)
        XCTAssertEqual(c.highlights?[0].note?.resolved(languageCode: "en"), "Tower")
        XCTAssertEqual(c.highlights?[1].side, .ahead)
        XCTAssertNil(c.highlights?[2].side, "unbekannte Seite → nil")
        XCTAssertEqual(c.bridges, ["Wettsteinbrücke", "Mittlere Brücke"])
    }

    func testBrokenInfoDoesNotBreakCourse() throws {
        let c = try course(extra: #", "description": 42, "highlights": "x", "bridges": {"a": 1}"#)
        XCTAssertEqual(c.id, "x")
        XCTAssertNil(c.description)
        XCTAssertNil(c.highlights)
    }

    func testLocalizedTextRoundTrip() throws {
        let plain = LocalizedText("Hallo")
        let multi = LocalizedText(values: ["de": "Hallo", "en": "Hello"])
        XCTAssertEqual(String(data: try JSONEncoder().encode(plain), encoding: .utf8), "\"Hallo\"")
        XCTAssertEqual(try JSONDecoder().decode(LocalizedText.self, from: JSONEncoder().encode(multi)), multi)
        XCTAssertEqual(LocalizedText(values: ["fr": "Salut"]).resolved(languageCode: "de"), "Salut")
    }
}
