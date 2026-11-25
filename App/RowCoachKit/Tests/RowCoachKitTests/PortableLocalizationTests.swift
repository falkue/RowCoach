import XCTest
@testable import RowCoachKit

final class PortableLocalizationTests: XCTestCase {
    func testFillSequentialAndPositional() {
        XCTAssertEqual(PortableLocalization.fill("vor %lld Tagen", ["3"]), "vor 3 Tagen")
        XCTAssertEqual(PortableLocalization.fill("%@ · ca. %@", ["2000 m", "8 min"]), "2000 m · ca. 8 min")
        XCTAssertEqual(PortableLocalization.fill("%2$@ before %1$@", ["A", "B"]), "B before A")
        XCTAssertEqual(PortableLocalization.fill("%lld %% leicht", ["80"]), "80 % leicht")
    }

    #if !canImport(Darwin)
    func testInterpolationBuildsCatalogKey() {
        let n = 4
        let v: PortableLocalizationValue = "vor \(n) Tagen bei \("Basel") – 100 %"
        XCTAssertEqual(v.key, "vor %lld Tagen bei %@ – 100 %%")
        XCTAssertEqual(v.args, ["4", "Basel"])
    }

    func testLookupTranslates() {
        PortableLocalization.lookup = { $0 == "vor %lld Tagen" ? "%lld days ago" : nil }
        defer { PortableLocalization.lookup = nil }
        let n = 2
        XCTAssertEqual(String(localized: "vor \(n) Tagen"), "2 days ago")
        XCTAssertEqual(String(localized: "heute"), "heute")
    }
    #endif
}
