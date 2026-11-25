import XCTest
@testable import RowCoachKit

final class CourseGroupingTests: XCTestCase {
    private func course(_ id: String, _ title: String, crs: String?, city: String?, country: String? = nil) -> Course {
        Course(id: id, title: title, oneWayM: 1000, totalM: 2000, pathXZ: [[0, 0], [0, -1000]],
               crs: crs, origin: crs == nil ? nil : [1, 2], country: country, city: city)
    }

    func testFlag() {
        XCTAssertEqual(Course.flag("CH"), "🇨🇭")
        XCTAssertEqual(Course.flag("de"), "🇩🇪")
        XCTAssertEqual(Course.flag("X"), "")
    }

    func testCountryFromCRSAndExplicit() {
        XCTAssertEqual(course("a", "A", crs: "EPSG:2056", city: nil).countryCode, "CH")
        XCTAssertEqual(course("b", "B", crs: "EPSG:25833", city: nil).countryCode, "DE")
        XCTAssertEqual(course("c", "C", crs: "EPSG:25832", city: nil, country: "at").countryCode, "AT")
        XCTAssertNil(course("t", "Test", crs: nil, city: nil).countryCode)
    }

    func testGroupsSorted() {
        let list = [
            course("utoquai", "Utoquai", crs: "EPSG:2056", city: "Zürich"),
            course("basel", "Rhein Basel", crs: "EPSG:2056", city: "Basel"),
            course("myth", "Mythenquai", crs: "EPSG:2056", city: "Zürich"),
            course("alster", "Außenalster", crs: "EPSG:25832", city: "Hamburg"),
            course("gruenau", "Grünau", crs: "EPSG:25833", city: "Berlin"),
            course("test", "Test", crs: nil, city: nil),
        ]
        let names = ["CH": "Schweiz", "DE": "Deutschland"]
        let g = CourseGrouping.byCountryAndCity(list, countryName: { names[$0] ?? $0 }, otherName: "Weitere")
        XCTAssertEqual(g.map(\.countryName), ["Deutschland", "Schweiz", "Weitere"])
        XCTAssertEqual(g[0].flag, "🇩🇪")
        XCTAssertEqual(g[0].cities.map(\.city), ["Berlin", "Hamburg"])
        XCTAssertEqual(g[1].cities.map(\.city), ["Basel", "Zürich"])
        XCTAssertEqual(g[1].cities[1].courses.map(\.id), ["myth", "utoquai"])
        XCTAssertEqual(g[2].cities.map(\.city), ["Weitere"])
        XCTAssertEqual(g[1].courseCount, 3)
    }

    func testDecodeCountryCity() throws {
        let json = #"{"id":"x","title":"X","region":"R","country":"CH","city":"Luzern","scene":"","qualities":[],"one_way_m":1,"total_m":2,"turns":1,"lake_level_m":0,"path_xz":[],"attribution":""}"#
        let c = try JSONDecoder().decode(Course.self, from: Data(json.utf8))
        XCTAssertEqual(c.city, "Luzern")
        XCTAssertEqual(c.countryCode, "CH")
        let back = try JSONDecoder().decode(Course.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(back.city, "Luzern")
    }

    func testShapeAndFilter() {
        var loop = course("l", "Loop", crs: "EPSG:2056", city: "Zürich")
        loop.turns = 0; loop.loop = true
        var oneWay = course("o", "One", crs: "EPSG:25833", city: "Berlin")
        oneWay.turns = 0
        let back = course("b", "Back", crs: "EPSG:2056", city: "Basel")
        XCTAssertEqual([loop.shape, oneWay.shape, back.shape], [.loop, .oneWay, .outAndBack])
        let all = [loop, oneWay, back]
        XCTAssertEqual(CourseFilter(countryCode: "CH").apply(all).map(\.id), ["l", "b"])
        XCTAssertEqual(CourseFilter(shape: .loop).apply(all).map(\.id), ["l"])
        XCTAssertEqual(CourseFilter(countryCode: "DE", shape: .outAndBack).apply(all).count, 0)
        XCTAssertFalse(CourseFilter().isActive)
    }
}
