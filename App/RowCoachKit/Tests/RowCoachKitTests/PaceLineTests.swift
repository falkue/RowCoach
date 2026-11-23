import XCTest
@testable import RowCoachKit

final class PaceLineTests: XCTestCase {
    /// 2:00 pro 500 m = 500/120 m/s
    private let line = PaceLine(pace: 120)

    func testSpeedAndDistance() {
        XCTAssertEqual(line.speed, 500.0 / 120, accuracy: 1e-12)
        XCTAssertEqual(line.distance(activeTime: 0), 0)
        XCTAssertEqual(line.distance(activeTime: -5), 0)
        XCTAssertEqual(line.distance(activeTime: 120), 500, accuracy: 1e-9)
        XCTAssertEqual(line.distance(activeTime: 480), 2000, accuracy: 1e-9)
    }

    func testStopsAtFinish() {
        XCTAssertEqual(line.distance(activeTime: 600, total: 2000), 2000, accuracy: 1e-9)
        let g = line.gap(boatDistance: 1900, activeTime: 600, total: 2000)
        XCTAssertTrue(g.lineFinished)
        XCTAssertEqual(g.lineDistance, 2000, accuracy: 1e-9)
        XCTAssertEqual(g.meters, -100, accuracy: 1e-9)
        // Linie war nach 456 s bei 1900 m, Boot braucht 600 s → 144 s zurück
        XCTAssertEqual(g.seconds, -144, accuracy: 1e-9)
        XCTAssertEqual(g.standing, .behind)
    }

    func testAheadAndBehind() {
        // nach 60 s: Linie 250 m
        let ahead = line.gap(boatDistance: 262, activeTime: 60)
        XCTAssertEqual(ahead.meters, 12, accuracy: 1e-9)
        XCTAssertEqual(ahead.seconds, 12 / line.speed, accuracy: 1e-9)
        XCTAssertEqual(ahead.standing, .ahead)
        XCTAssertFalse(ahead.lineFinished)

        let behind = line.gap(boatDistance: 242, activeTime: 60)
        XCTAssertEqual(behind.meters, -8, accuracy: 1e-9)
        XCTAssertEqual(behind.seconds, -8 / line.speed, accuracy: 1e-9)
        XCTAssertEqual(behind.standing, .behind)

        XCTAssertEqual(line.gap(boatDistance: 250.5, activeTime: 60).standing, .level)
    }

    /// Pausen: Die Linie hängt nur an der Ruderzeit; steht die Ruderzeit, steht die Linie.
    func testHoldsDuringPause() {
        let before = line.gap(boatDistance: 300, activeTime: 70)
        let after = line.gap(boatDistance: 300, activeTime: 70)
        XCTAssertEqual(before, after)
    }

    /// Im Ziel: Sekunden = Zielzeit der Linie − eigene Zeit (positiv = schneller)
    func testFinishComparison() {
        let g = line.gap(boatDistance: 2000, activeTime: 457, total: 2000)
        XCTAssertEqual(g.seconds, 23, accuracy: 1e-9)
        XCTAssertEqual(g.meters, 2000 - 457 * line.speed, accuracy: 1e-9)
        // Boot über das Ziel hinaus zählt nur bis zum Ziel
        XCTAssertEqual(line.gap(boatDistance: 2010, activeTime: 457, total: 2000).seconds, 23, accuracy: 1e-9)
    }

    func testTimeForDistance() {
        XCTAssertEqual(PaceLine(pace: 138).time(forDistance: 4000), 1104, accuracy: 1e-9)   // 18:24
        XCTAssertEqual(PaceLine(pace: 0).time(forDistance: 4000), 0)
        XCTAssertEqual(PaceLine(pace: 0).distance(activeTime: 100), 0)
    }

    func testDefaultPace() {
        // 7:00 → 105 + 18 = 2:03
        XCTAssertEqual(PaceLine.defaultPace(best2k: 420), 123, accuracy: 1e-9)
        // ungültig → Standard-Bestzeit 8:00 → 120 + 18
        XCTAssertEqual(PaceLine.defaultPace(best2k: 0), 138, accuracy: 1e-9)
        // auf 0,5 s gerundet
        XCTAssertEqual(PaceLine.defaultPace(best2k: 421), 123.5, accuracy: 1e-9)
        XCTAssertEqual(PaceLine.clamp(30), PaceLine.paceRange.lowerBound)
        XCTAssertEqual(PaceLine.clamp(500), PaceLine.paceRange.upperBound)
    }
}
