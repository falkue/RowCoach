import XCTest
@testable import RowCoachKit

/// Referenzwerte: SPA-Algorithmus des NREL (pvlib 0.13, scheinbare Höhe mit Refraktion; Zürich 47.3769° N,
/// 8.5417° E, 406 m), gerechnet am 23.11.2026. NOAA weicht davon um weniger als 0,02° ab.
final class SolarPositionTests: XCTestCase {
    private let lat = 47.3769, lon = 8.5417

    private func at(_ unix: TimeInterval) -> SolarPosition {
        SolarPosition.compute(date: Date(timeIntervalSince1970: unix), latitude: lat, longitude: lon)
    }

    /// Sommersonnenwende, wahrer Mittag (11:28 UTC = 13:28 MESZ): 90° − 47,38° + 23,44° ≈ 66,1° hoch, im Süden
    func testZurichSummerSolsticeNoon() {
        let p = at(1_782_041_280)   // 2026-06-21T11:28:00Z
        XCTAssertEqual(p.elevationDegrees, 66.067, accuracy: 0.05)
        XCTAssertEqual(p.azimuthDegrees, 180.200, accuracy: 0.1)
    }

    func testReferenceValuesAgainstSPA() {
        let refs: [(unix: TimeInterval, az: Double, el: Double)] = [
            (1_782_018_000, 68.958, 12.662),    // 2026-06-21T05:00Z, Morgen
            (1_782_067_500, 299.644, 5.146),    // 2026-06-21T18:45Z, Abend
            (1_774_006_500, 180.586, 42.585),   // 2026-03-20T11:35Z, Tagundnachtgleiche
            (1_797_852_300, 180.271, 19.228),   // 2026-12-21T11:25Z, Wintersonnenwende
            (1_788_274_800, 247.054, 30.173),   // 2026-09-01T15:00Z, Nachmittag
            (1_795_420_800, 134.986, 9.777),    // 2026-11-23T08:00Z, Wintermorgen
        ]
        for r in refs {
            let p = at(r.unix)
            XCTAssertEqual(p.azimuthDegrees, r.az, accuracy: 0.05, "Azimut \(r.unix)")
            XCTAssertEqual(p.elevationDegrees, r.el, accuracy: 0.05, "Höhe \(r.unix)")
        }
    }

    func testSolarNoonZurichMidsummer() {
        // wahrer Mittag 21.06.2026 in Zürich: 11:27:39 UTC
        let noon = SolarPosition.solarNoon(containing: Date(timeIntervalSince1970: 1_782_043_200), longitude: lon)
        XCTAssertEqual(noon.timeIntervalSince1970, 1_782_041_259, accuracy: 30)
        let p = SolarPosition.compute(date: noon, latitude: lat, longitude: lon)
        XCTAssertEqual(p.azimuthDegrees, 180, accuracy: 0.05)
    }

    /// Nachts: keine Nachtszene, sondern die Abenddämmerung desselben Tages (Sonne 2° hoch, ca. 236,8°)
    func testNightIsClampedToDusk() {
        let night = Date(timeIntervalSince1970: 1_795_471_200)   // 2026-11-23T22:00Z
        XCTAssertLessThan(SolarPosition.compute(date: night, latitude: lat, longitude: lon).elevationDegrees, -20)
        let p = SolarPosition.scene(date: night, latitude: lat, longitude: lon)
        XCTAssertEqual(p.elevationDegrees, SolarPosition.minimumSceneElevation, accuracy: 1e-9)
        XCTAssertEqual(p.azimuthDegrees, 236.78, accuracy: 0.1)
    }

    func testDaytimeIsNotClamped() {
        let d = Date(timeIntervalSince1970: 1_788_274_800)
        XCTAssertEqual(SolarPosition.scene(date: d, latitude: lat, longitude: lon),
                       SolarPosition.compute(date: d, latitude: lat, longitude: lon))
    }

    func testPresets() {
        let now = Date(timeIntervalSince1970: 1_795_420_800)   // November 2026 → 21.06.2026
        XCTAssertEqual(SunPreset.summerAfternoon.position(latitude: lat, longitude: lon, now: now), SunPreset.bakedSun)
        let m = SunPreset.morning.position(latitude: lat, longitude: lon, now: now)
        XCTAssertEqual(m.azimuthDegrees, 78.74, accuracy: 0.1)
        XCTAssertEqual(m.elevationDegrees, 22.0, accuracy: 0.1)
        let n = SunPreset.noon.position(latitude: lat, longitude: lon, now: now)
        XCTAssertEqual(n.azimuthDegrees, 180, accuracy: 0.1)
        XCTAssertEqual(n.elevationDegrees, 66.07, accuracy: 0.1)
        let e = SunPreset.evening.position(latitude: lat, longitude: lon, now: now)
        XCTAssertEqual(e.azimuthDegrees, 299.23, accuracy: 0.1)
        XCTAssertEqual(e.elevationDegrees, 5.50, accuracy: 0.1)
        XCTAssertTrue(SunPreset.summerAfternoon.matchesBakedSun)
        XCTAssertFalse(SunPreset.evening.matchesBakedSun)
        XCTAssertEqual(SunPreset(argument: "evening"), .evening)
        XCTAssertEqual(SunPreset(argument: "Morgen"), .morning)
        XCTAssertNil(SunPreset(argument: "nacht"))
    }

    /// Ort der Strecke aus origin_lv95 (Zürich, unteres Seebecken)
    func testCourseLocation() {
        let c = Course(id: "x", title: "x", oneWayM: 1, totalM: 2, originLV95: [2_683_500, 1_245_000],
                       lakeLevelM: 405.9, pathXZ: [[0, 0], [0, -1]])
        let loc = SolarPosition.location(of: c)
        XCTAssertEqual(loc?.latitude ?? 0, 47.3506, accuracy: 1e-3)
        XCTAssertEqual(loc?.longitude ?? 0, 8.5438, accuracy: 1e-3)
        XCTAssertNil(SolarPosition.location(of: .straight()))
    }

    /// Light-Varianten in course.json sind optional; alte Pakete ohne Feld lesen sich weiter.
    func testCourseLightVariantsOptional() throws {
        let old = #"{"id":"a","title":"A","region":"","scene":"g/scene-{quality}.usdz","qualities":["standard"],"one_way_m":1,"total_m":2,"turns":1,"origin_lv95":[],"lake_level_m":0,"path_xz":[[0,0]],"attribution":""}"#
        XCTAssertNil(try Course.decode(Data(old.utf8)).lightVariants)
        let new = #"{"id":"a","title":"A","region":"","scene":"g/scene-{quality}.usdz","qualities":["standard","hoch"],"one_way_m":1,"total_m":2,"turns":1,"origin_lv95":[],"lake_level_m":0,"path_xz":[[0,0]],"attribution":"","light_variants":{"ambient":{"textures":"g/light-ambient-{quality}","qualities":["standard"],"replaces":["Buildings","Bridges"]}}}"#
        let c = try Course.decode(Data(new.utf8))
        XCTAssertEqual(c.lightVariants?["ambient"]?.replaces, ["Buildings", "Bridges"])
        XCTAssertEqual(c.lightVariantPath("ambient", quality: "standard"), "g/light-ambient-standard")
        XCTAssertNil(c.lightVariantPath("ambient", quality: "hoch"))
        XCTAssertNil(c.lightVariantPath("morning", quality: "standard"))
    }
}
