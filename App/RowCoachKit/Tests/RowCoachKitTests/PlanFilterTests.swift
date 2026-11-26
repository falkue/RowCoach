import XCTest
@testable import RowCoachKit

final class PlanFilterTests: XCTestCase {
    private let easyTime = WorkoutPlan(id: "ut2-60", name: "Grundlage 60 Minuten", summary: "Ruhig", level: "Einsteiger",
                                       category: "Grundlage", tags: ["easy", "aerobic"], phases: [
        WorkoutPhase(kind: .warmup, durationS: 300), WorkoutPhase(kind: .work, durationS: 3000),
        WorkoutPhase(kind: .cooldown, durationS: 300)])
    private let hardDist = WorkoutPlan(id: "8x500", name: "8 × 500 m", summary: "Pete Plan", level: "Fortgeschritten",
                                       category: "Intervalle", tags: ["hard", "vo2max", "anaerobic"], phases: [
        WorkoutPhase(kind: .warmup, durationS: 600), WorkoutPhase(kind: .work, distanceM: 500),
        WorkoutPhase(kind: .rest, durationS: 210), WorkoutPhase(kind: .work, distanceM: 500),
        WorkoutPhase(kind: .cooldown, durationS: 300)])
    private let mixed = WorkoutPlan(id: "mix", name: "Gemischt", tags: ["max", "hard"], phases: [
        WorkoutPhase(kind: .work, durationS: 60), WorkoutPhase(kind: .work, distanceM: 500)])

    func testDerivedValues() {
        XCTAssertEqual(easyTime.intensity, .easy)
        XCTAssertEqual(hardDist.intensity, .hard)
        XCTAssertEqual(mixed.intensity, .max, "bei mehreren Angaben gilt die höchste")
        XCTAssertEqual(easyTime.metric, .time)
        XCTAssertEqual(hardDist.metric, .distance, "Ein- und Ausrudern nach Zeit zählen nicht")
        XCTAssertEqual(mixed.metric, .mixed)
        XCTAssertEqual(easyTime.durationClass(best2k: 480), .long)
        XCTAssertEqual(hardDist.durationClass(best2k: 480), .short)
        XCTAssertEqual(PlanDurationClass.of(seconds: 30 * 60), .short)
        XCTAssertEqual(PlanDurationClass.of(seconds: 45 * 60), .medium)
        XCTAssertEqual(PlanDurationClass.of(seconds: 60 * 60), .long)
    }

    func testFilter() {
        let all = [easyTime, hardDist, mixed]
        XCTAssertFalse(PlanFilter().isActive)
        XCTAssertEqual(PlanFilter().apply(all, best2k: 480).count, 3)
        XCTAssertEqual(PlanFilter(intensity: .hard).apply(all, best2k: 480).map(\.id), ["8x500"])
        XCTAssertEqual(PlanFilter(metric: .time).apply(all, best2k: 480).map(\.id), ["ut2-60"])
        XCTAssertEqual(PlanFilter(duration: .long).apply(all, best2k: 480).map(\.id), ["ut2-60"])
        XCTAssertEqual(PlanFilter(level: "Einsteiger", category: "Grundlage").apply(all, best2k: 480).count, 1)
        XCTAssertEqual(PlanFilter(text: "pete 500").apply(all, best2k: 480).map(\.id), ["8x500"])
        XCTAssertEqual(PlanFilter(text: "grundläge").apply(all, best2k: 480).map(\.id), ["ut2-60"], "ohne Akzente")
        XCTAssertTrue(PlanFilter(text: "x").isActive)
    }

    func testTagsDecodeAndRoundTrip() throws {
        let json = #"[{"id": "a", "name": "A", "tags": ["Hard", " vo2max ", 3], "phases": [{"kind": "work", "durationS": 60}]}]"#
        let p = try XCTUnwrap(WorkoutPlanCatalog.decode(Data(json.utf8)).first)
        XCTAssertEqual(p.tags, ["hard", "vo2max"], "Nicht-Text fällt weg")
        let again = try JSONDecoder().decode(WorkoutPlan.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(again.tags, p.tags)
    }
}
