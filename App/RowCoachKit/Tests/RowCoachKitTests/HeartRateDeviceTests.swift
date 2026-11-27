import XCTest
@testable import RowCoachKit

final class HeartRateDeviceTests: XCTestCase {
    func testKnownStrapNames() {
        for n in ["Polar H10 7B3A9C21", "HRM-Pro:123456", "HRM-Dual:654321", "HRM 600", "Forerunner 265",
                  "fenix 7", "TICKR 1A2B", "Wahoo KICKR", "COOSPO H6", "Suunto Smart Sensor", "WHOOP 4A1B"] {
            XCTAssertTrue(HeartRateProfile.looksLikeStrap(n), n)
        }
    }

    func testOtherDevicesIgnored() {
        for n in ["PM5 430123456", "", "AirPods Pro", "iPad", "Concept2 BikeErg"] {
            XCTAssertFalse(HeartRateProfile.looksLikeStrap(n), n)
        }
    }
}
