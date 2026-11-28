import XCTest
@testable import RowCoachKit

/// course.json "water_tint" (Amazonas, amazonas.py): zweite Wasserfarbe, optional und tolerant
final class CourseWaterTintTests: XCTestCase {
    private func course(_ extra: String) throws -> Course {
        let json = """
        {"id": "t", "title": "T", "region": "R", "scene": "t/scene-{quality}.usdz", "qualities": ["standard"],
         "one_way_m": 100, "total_m": 200, "turns": 1, "lake_level_m": 11, "path_xz": [[0, 0], [0, -100]],
         "attribution": "x"\(extra)}
        """
        return try Course.decode(Data(json.utf8))
    }

    func testDecodesWaterTint() throws {
        let tint = #", "water_tint": {"image": "t/water_tint.jpg", "alpha": "t/water_tint_alpha.png", "#
            + #""bounds_xz": [-100, -200, 300, 400], "roughness": 0.08, "height_m": 0.03}"#
        let c = try course(tint)
        let w = try XCTUnwrap(c.waterTint)
        XCTAssertEqual(w.image, "t/water_tint.jpg")
        XCTAssertEqual(w.alpha, "t/water_tint_alpha.png")
        XCTAssertEqual(w.boundsXZ, [-100, -200, 300, 400])
        XCTAssertEqual(w.roughness, 0.08)
        XCTAssertNil(w.flipV)
    }

    func testMissingOrBrokenWaterTintKeepsCourse() throws {
        XCTAssertNil(try course("").waterTint)
        XCTAssertNil(try course(", \"water_tint\": {\"image\": 3}").waterTint)
    }
}
