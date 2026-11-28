import XCTest
@testable import RowCoachKit

/// Beispielwerte aus der Concept2-Formel (docs/KALORIEN.md): 179 W über 30 min
final class RowingEnergyTests: XCTestCase {
    func testPM5MatchesConcept2Formula() {
        // (4 × 179 + 300) kcal/h × 0,5 h = 508 kcal
        XCTAssertEqual(RowingEnergy.pm5Kcal(averageWatts: 179, seconds: 1800), 508, accuracy: 0.001)
    }

    func testReferencePersonReproducesPM5Total() {
        // 175 lb: die Concept2-Korrektur ergibt wieder die PM-Zahl (1,714 × 175 = 299,95)
        let kg = 175 / RowingEnergy.lbPerKg
        let b = RowingEnergy.breakdown(averageWatts: 179, seconds: 1800, bodyMassKg: kg)
        XCTAssertEqual(b.total, 508, accuracy: 0.05)
    }

    func testWeightAdjustedActiveAndResting() {
        let light = RowingEnergy.breakdown(averageWatts: 179, seconds: 1800, bodyMassKg: 75)
        // gesamt (716 + 3,7787 × 75) / 2 = 499,7; Ruhe 75 × 0,5 = 37,5; aktiv 462,2
        XCTAssertEqual(light.total, 499.70, accuracy: 0.05)
        XCTAssertEqual(light.resting, 37.5, accuracy: 0.001)
        XCTAssertEqual(light.active, 462.20, accuracy: 0.05)
        XCTAssertEqual(light.active + light.resting, light.total, accuracy: 1e-9)

        let heavy = RowingEnergy.breakdown(averageWatts: 179, seconds: 1800, bodyMassKg: 95)
        // gesamt (716 + 3,7787 × 95) / 2 = 537,5; Ruhe 47,5; aktiv 490,0
        XCTAssertEqual(heavy.total, 537.49, accuracy: 0.05)
        XCTAssertEqual(heavy.active, 489.99, accuracy: 0.05)
        // 20 kg mehr: +2,779 kcal/h je kg aktiv → +27,8 kcal in 30 min
        XCTAssertEqual(heavy.active - light.active, 27.79, accuracy: 0.05)
    }

    func testMissingOrImplausibleWeightUsesDefault() {
        let std = RowingEnergy.breakdown(averageWatts: 120, seconds: 600, bodyMassKg: 75)
        XCTAssertEqual(RowingEnergy.breakdown(averageWatts: 120, seconds: 600, bodyMassKg: nil), std)
        XCTAssertEqual(RowingEnergy.breakdown(averageWatts: 120, seconds: 600, bodyMassKg: 12), std)
        XCTAssertEqual(RowingEnergy.breakdown(averageWatts: 120, seconds: 600, bodyMassKg: .nan), std)
    }

    func testActiveKcalPrefersStoredValue() {
        var s = WorkoutSummary(distance: 7000, activeDuration: 1800, totalDuration: 1800, averagePace: 128,
                               averageSpeed: 3.9, averageStrokeRate: 22, strokeCount: 660, averagePower: 179,
                               maxPower: 250, calories: 508, averageHeartRate: nil, maxHeartRate: nil,
                               heartRateZoneSeconds: nil, completedCourse: false, pauseCount: 0)
        XCTAssertEqual(RowingEnergy.activeKcal(s, bodyMassKg: 95), 489.99, accuracy: 0.05)
        s.activeCalories = 462
        XCTAssertEqual(RowingEnergy.activeKcal(s, bodyMassKg: 95), 462)
        s.activeCalories = nil
        s.averagePower = 0
        XCTAssertEqual(RowingEnergy.activeKcal(s, bodyMassKg: 95), 0)
    }

    func testSummaryDecodesWithoutActiveCalories() throws {
        let s = WorkoutSummary(distance: 100, activeDuration: 30, totalDuration: 30, averagePace: 150, averageSpeed: 3.3,
                               averageStrokeRate: 20, strokeCount: 10, averagePower: 100, maxPower: 120, calories: 4,
                               averageHeartRate: nil, maxHeartRate: nil, heartRateZoneSeconds: nil,
                               completedCourse: false, pauseCount: 0, activeCalories: 3)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as! [String: Any]
        XCTAssertEqual(json["activeCalories"] as? Int, 3)
        json.removeValue(forKey: "activeCalories")
        let old = try JSONDecoder().decode(WorkoutSummary.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.activeCalories)
        XCTAssertEqual(old.calories, 4)
    }
}

final class BodyWeightRuleTests: XCTestCase {
    private let d0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func reading(_ kg: Double, hoursAfter h: Double) -> BodyWeightRule.Reading {
        .init(kg: kg, date: d0.addingTimeInterval(h * 3600), source: "Waage")
    }

    func testAppliesNewerReadingOnly() {
        let t = BodyWeightRule.Tracking(asOf: d0, seen: 80)
        XCTAssertEqual(BodyWeightRule.action(current: 80, reading: reading(78.43, hoursAfter: 1), fromHealth: true,
                                             tracking: t), .apply(78.4))
        XCTAssertEqual(BodyWeightRule.action(current: 80, reading: reading(78.4, hoursAfter: -1), fromHealth: true,
                                             tracking: t), .none)
        // eingeschaltet: neueste Messung gilt sofort
        XCTAssertEqual(BodyWeightRule.action(current: 80, reading: reading(78.4, hoursAfter: -1), fromHealth: true,
                                             tracking: t, force: true), .apply(78.4))
    }

    func testUnknownAgeAcceptsAnyReadingAndImplausibleIsIgnored() {
        let t = BodyWeightRule.Tracking()
        XCTAssertEqual(BodyWeightRule.action(current: 75, reading: reading(82, hoursAfter: 0), fromHealth: true,
                                             tracking: t), .apply(82))
        XCTAssertEqual(BodyWeightRule.action(current: 75, reading: reading(12, hoursAfter: 0), fromHealth: true,
                                             tracking: t), .none)
        XCTAssertEqual(BodyWeightRule.action(current: 75, reading: reading(300, hoursAfter: 0), fromHealth: true,
                                             tracking: t), .none)
        XCTAssertEqual(BodyWeightRule.action(current: 75, reading: nil, fromHealth: true, tracking: t), .none)
    }

    func testOfferOnlyFromHalfKilo() {
        let t = BodyWeightRule.manual(78, now: d0)
        XCTAssertEqual(BodyWeightRule.action(current: 78, reading: reading(78.4, hoursAfter: 1), fromHealth: false,
                                             tracking: t), .none)
        XCTAssertEqual(BodyWeightRule.action(current: 78, reading: reading(78.5, hoursAfter: 1), fromHealth: false,
                                             tracking: t), .offer(78.5))
        // Messung älter als die Eingabe von Hand: kein Angebot
        XCTAssertEqual(BodyWeightRule.action(current: 78, reading: reading(80, hoursAfter: -1), fromHealth: false,
                                             tracking: t), .none)
    }

    /// Zwei Geräte mit Übernahme, iPad sieht die neue Wägung später: kein Hin und Her
    func testTwoDevicesConverge() {
        let old = reading(80, hoursAfter: 0), new = reading(79, hoursAfter: 24)
        // iPhone übernimmt die neue Messung
        var phone = BodyWeightRule.Tracking()
        guard case .apply(let kg) = BodyWeightRule.action(current: 80, reading: new, fromHealth: true, tracking: phone)
        else { return XCTFail("iPhone übernimmt nicht") }
        phone = BodyWeightRule.applied(new)
        XCTAssertEqual(kg, 79)
        // iPad: hatte die alte Messung übernommen, bekommt 79 per Synchronisation
        var pad = BodyWeightRule.applied(old)
        let syncAt = d0.addingTimeInterval(25 * 3600)
        pad = BodyWeightRule.observe(current: 79, tracking: pad, now: syncAt)
        XCTAssertEqual(pad.asOf, syncAt)
        // iPad liest weiter die alte Messung: überschreibt nicht
        XCTAssertEqual(BodyWeightRule.action(current: 79, reading: old, fromHealth: true, tracking: pad), .none)
        // iPhone sieht seinen eigenen Wert unverändert
        XCTAssertEqual(BodyWeightRule.observe(current: 79, tracking: phone, now: syncAt), phone)
        XCTAssertEqual(BodyWeightRule.action(current: 79, reading: new, fromHealth: true, tracking: phone), .none)
    }

    func testFirstObservationKeepsUnknownAge() {
        let t = BodyWeightRule.observe(current: 75, tracking: .init(), now: d0)
        XCTAssertNil(t.asOf)
        XCTAssertEqual(t.seen, 75)
    }
}
