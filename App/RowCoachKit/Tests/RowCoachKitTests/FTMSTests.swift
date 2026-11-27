import XCTest
@testable import RowCoachKit

/// FTMS Rower Data (0x2AD1) und Co. – Pakete von Hand nach der Spezifikation gebaut (Little Endian), nicht mit dem
/// eigenen Encoder, damit Parser und Encoder sich nicht gegenseitig bestätigen.
final class FTMSRowerDataParserTests: XCTestCase {
    func testTypicalPacketWithStrokeFields() throws {
        // Flags 0x002C: Total Distance, Instantaneous Pace, Instantaneous Power; Bit 0 = 0 → Schlagfelder enthalten
        let b: [UInt8] = [0x2C, 0x00,
                          0x30,               // Stroke Rate 48 × 0,5 = 24,0
                          0x39, 0x00,         // Stroke Count 57
                          0xD2, 0x04, 0x00,   // Distanz 1234 m
                          0x76, 0x00,         // Tempo 118 s/500 m
                          0xC8, 0x00]         // 200 W
        let d = try FTMSRowerDataParser.parse(b)
        XCTAssertEqual(d.strokeRate, 24.0)
        XCTAssertEqual(d.strokeCount, 57)
        XCTAssertEqual(d.totalDistance, 1234)
        XCTAssertEqual(d.instantaneousPace, 118)
        XCTAssertEqual(d.instantaneousPower, 200)
        XCTAssertNil(d.averagePace)
        XCTAssertNil(d.heartRate)
        XCTAssertNil(d.resistanceLevel)
    }

    func testHalfStrokeResolution() throws {
        let d = try FTMSRowerDataParser.parse([0x00, 0x00, 0x2B, 0x01, 0x00])   // 43 × 0,5 = 21,5
        XCTAssertEqual(d.strokeRate, 21.5)
        XCTAssertEqual(d.strokeCount, 1)
    }

    func testMoreDataBitIsInvertedAndSkipsStrokeFields() throws {
        // Flags 0x0005: More Data (keine Schlagfelder) + Total Distance
        let d = try FTMSRowerDataParser.parse([0x05, 0x00, 0x10, 0x27, 0x00])
        XCTAssertNil(d.strokeRate)
        XCTAssertNil(d.strokeCount)
        XCTAssertEqual(d.totalDistance, 10_000)
        XCTAssertTrue(d.flags.contains(.moreData))
    }

    /// Alle Felder (Flags 0x1FFE): 30 Bytes mit Widerstand sint16, 29 Bytes mit Widerstand uint8
    private func fullPacket(resistanceWide: Bool) -> [UInt8] {
        var b: [UInt8] = [0xFE, 0x1F]
        b += [0x34, 0x10, 0x02]          // Stroke Rate 26, Stroke Count 528
        b += [0x32]                      // Ø Schlagzahl 25
        b += [0xFF, 0xFF, 0xFF]          // Distanz uint24 Maximum 16 777 215
        b += [0x73, 0x00]                // Tempo 115
        b += [0x78, 0x00]                // Ø Tempo 120
        b += [0xFF, 0xFF]                // Leistung −1 (sint16)
        b += [0xB4, 0x00]                // Ø Leistung 180
        b += resistanceWide ? [0x05, 0x00] : [0x07]
        b += [0xFF, 0xFF, 0x10, 0x03, 0x0D]   // Energie: gesamt „nicht verfügbar“, 784 kcal/h, 13 kcal/min
        b += [0x8C]                      // Puls 140
        b += [0x5A]                      // MET 9,0
        b += [0x10, 0x0E]                // 3600 s
        b += [0x2C, 0x01]                // Rest 300 s
        return b
    }

    func testAllFieldsWithWideResistance() throws {
        let b = fullPacket(resistanceWide: true)
        XCTAssertEqual(b.count, 30)
        let d = try FTMSRowerDataParser.parse(b)
        XCTAssertEqual(d.strokeRate, 26)
        XCTAssertEqual(d.strokeCount, 528)
        XCTAssertEqual(d.averageStrokeRate, 25)
        XCTAssertEqual(d.totalDistance, 16_777_215)
        XCTAssertEqual(d.instantaneousPace, 115)
        XCTAssertEqual(d.averagePace, 120)
        XCTAssertEqual(d.instantaneousPower, -1)
        XCTAssertEqual(d.averagePower, 180)
        XCTAssertEqual(d.resistanceLevel, 5)
        XCTAssertEqual(d.resistanceFieldWidth, 2)
        XCTAssertNil(d.totalEnergy)
        XCTAssertEqual(d.energyPerHour, 784)
        XCTAssertEqual(d.energyPerMinute, 13)
        XCTAssertEqual(d.heartRate, 140)
        XCTAssertEqual(d.metabolicEquivalent ?? 0, 9.0, accuracy: 1e-9)
        XCTAssertEqual(d.elapsedTime, 3600)
        XCTAssertEqual(d.remainingTime, 300)
    }

    func testAllFieldsWithNarrowResistance() throws {
        let b = fullPacket(resistanceWide: false)
        XCTAssertEqual(b.count, 29)
        let d = try FTMSRowerDataParser.parse(b)
        XCTAssertEqual(d.resistanceLevel, 7)
        XCTAssertEqual(d.resistanceFieldWidth, 1)
        XCTAssertEqual(d.heartRate, 140)
        XCTAssertEqual(d.elapsedTime, 3600)
        XCTAssertEqual(d.remainingTime, 300)
    }

    func testTooShortThrowsAndTrailingBytesAreIgnored() throws {
        XCTAssertThrowsError(try FTMSRowerDataParser.parse([0x2C]))
        XCTAssertThrowsError(try FTMSRowerDataParser.parse([0x2C, 0x00, 0x30, 0x39, 0x00, 0xD2]))
        let d = try FTMSRowerDataParser.parse([0x00, 0x00, 0x30, 0x02, 0x00, 0xAA, 0xBB])
        XCTAssertEqual(d.strokeCount, 2)
    }

    func testHeartRateZeroMeansNone() throws {
        let d = try FTMSRowerDataParser.parse([0x01, 0x02, 0x00])   // More Data + Heart Rate = 0
        XCTAssertNil(d.heartRate)
    }

    func testEncoderRoundTrip() throws {
        var d = FTMSRowerData()
        d.strokeRate = 23.5; d.strokeCount = 812; d.totalDistance = 5_432; d.instantaneousPace = 121
        d.averagePace = 124; d.instantaneousPower = 190; d.averagePower = 176; d.resistanceLevel = 4
        d.totalEnergy = 310; d.energyPerHour = 1060; d.energyPerMinute = 17; d.heartRate = 151
        d.metabolicEquivalent = 8.4; d.elapsedTime = 1_314; d.remainingTime = 0
        let p = try FTMSRowerDataParser.parse(FTMSRowerDataEncoder.encode(d))
        XCTAssertEqual(p.strokeRate, 23.5)
        XCTAssertEqual(p.strokeCount, 812)
        XCTAssertEqual(p.totalDistance, 5_432)
        XCTAssertEqual(p.resistanceLevel, 4)
        XCTAssertEqual(p.totalEnergy, 310)
        XCTAssertEqual(p.heartRate, 151)
        XCTAssertEqual(p.metabolicEquivalent ?? 0, 8.4, accuracy: 1e-9)
        XCTAssertEqual(p.elapsedTime, 1_314)
        XCTAssertEqual(p.remainingTime, 0)
    }

    func testMergeKeepsFieldsAcrossSplitPackets() throws {
        var m = FTMSRowerData()
        m.merge(try FTMSRowerDataParser.parse([0x05, 0x00, 0x64, 0x00, 0x00]))   // 100 m, ohne Schläge
        m.merge(try FTMSRowerDataParser.parse([0x00, 0x00, 0x30, 0x0A, 0x00]))   // 24 spm, 10 Schläge
        XCTAssertEqual(m.totalDistance, 100)
        XCTAssertEqual(m.strokeRate, 24)
        XCTAssertEqual(m.strokeCount, 10)
    }
}

final class FTMSServiceTests: XCTestCase {
    func testAdvertisementServiceData() {
        let rower = FTMSAdvertisement.parse(serviceData: [0x01, 0x10, 0x00])
        XCTAssertEqual(rower?.available, true)
        XCTAssertEqual(rower?.machineTypes, .rower)
        XCTAssertTrue(FTMSAdvertisement.isRowerCandidate(advertisesService: true, serviceData: [0x01, 0x10, 0x00]))
        // Fahrrad (Bit 5): nicht anbieten, auch wenn der Dienst beworben wird
        XCTAssertFalse(FTMSAdvertisement.isRowerCandidate(advertisesService: true, serviceData: [0x01, 0x20, 0x00]))
        // ohne Service Data entscheidet erst das Verbinden
        XCTAssertTrue(FTMSAdvertisement.isRowerCandidate(advertisesService: true, serviceData: nil))
        XCTAssertFalse(FTMSAdvertisement.isRowerCandidate(advertisesService: false, serviceData: nil))
        XCTAssertNil(FTMSAdvertisement.parse(serviceData: [0x01]))
    }

    func testFeatures() {
        // Kadenz, Distanz, Tempo; Energie, Puls, Zeit, Leistung
        let f = FTMSFeatures.parse([0x26, 0x56, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00])
        XCTAssertEqual(f?.machine.contains(.cadence), true)
        XCTAssertEqual(f?.machine.contains(.totalDistance), true)
        XCTAssertEqual(f?.machine.contains(.pace), true)
        XCTAssertEqual(f?.machine.contains(.expendedEnergy), true)
        XCTAssertEqual(f?.machine.contains(.heartRate), true)
        XCTAssertEqual(f?.machine.contains(.elapsedTime), true)
        XCTAssertEqual(f?.machine.contains(.powerMeasurement), true)
        XCTAssertEqual(f?.machine.contains(.resistanceLevel), false)
        XCTAssertEqual(f?.targetSettings, 0x04)
        XCTAssertNil(FTMSFeatures.parse([0x01]))
    }

    func testControlPointAndStatus() {
        XCTAssertEqual(FTMSControlCommand.requestControl.bytes, [0x00])
        XCTAssertEqual(FTMSControlCommand.reset.bytes, [0x01])
        XCTAssertEqual(FTMSControlCommand.startOrResume.bytes, [0x07])
        XCTAssertEqual(FTMSControlCommand.stop.bytes, [0x08, 0x01])
        XCTAssertEqual(FTMSControlCommand.pause.bytes, [0x08, 0x02])
        let r = FTMSControlResponse.parse([0x80, 0x00, 0x01])
        XCTAssertEqual(r?.requestOpCode, 0x00)
        XCTAssertEqual(r?.result, .success)
        XCTAssertEqual(FTMSControlResponse.parse([0x80, 0x07, 0x05])?.result, .controlNotPermitted)
        XCTAssertNil(FTMSControlResponse.parse([0x01, 0x00, 0x01]))
        XCTAssertEqual(FTMSMachineStatus.parse([0x01]), .reset)
        XCTAssertEqual(FTMSMachineStatus.parse([0x02, 0x01]), .stoppedByUser)
        XCTAssertEqual(FTMSMachineStatus.parse([0x02, 0x02]), .pausedByUser)
        XCTAssertEqual(FTMSMachineStatus.parse([0x04]), .startedOrResumedByUser)
        XCTAssertEqual(FTMSMachineStatus.parse([0xFF]), .controlPermissionLost)
        XCTAssertEqual(FTMSMachineStatus.parse([0x05, 0x10, 0x00]), .other(0x05))
        XCTAssertNil(FTMSMachineStatus.parse([]))
    }
}

final class FTMSRowerTrackerTests: XCTestCase {
    private func packet(rate: Double? = nil, count: Int? = nil, distance: Int? = nil, pace: Int? = nil,
                        power: Int? = nil, hr: Int? = nil) -> FTMSRowerData {
        var d = FTMSRowerData()
        d.strokeRate = rate; d.strokeCount = count; d.totalDistance = distance
        d.instantaneousPace = pace; d.instantaneousPower = power; d.heartRate = hr
        return d
    }

    func testStrokesFromCountIncludingWrapAndReset() {
        var tr = FTMSRowerTracker(), s = RowingSnapshot()
        XCTAssertEqual(tr.ingest(packet(rate: 24, count: 65_534), at: 0, into: &s), 0)     // Grundlinie
        XCTAssertEqual(tr.ingest(packet(rate: 24, count: 65_535), at: 2.5, into: &s), 1)
        XCTAssertEqual(tr.ingest(packet(rate: 24, count: 1), at: 5, into: &s), 2)           // Überlauf
        XCTAssertEqual(tr.ingest(packet(rate: 24, count: 0), at: 7.5, into: &s), 0)         // Reset am Gerät
        XCTAssertEqual(tr.ingest(packet(rate: 24, count: 1), at: 10, into: &s), 1)
        XCTAssertEqual(tr.ingest(packet(rate: 24, count: 500), at: 12.5, into: &s), 0)      // unplausibler Sprung
        XCTAssertEqual(s.strokeCount, 4)
        XCTAssertEqual(s.strokeRate, 24)
        XCTAssertEqual(tr.lastStrokeInterval ?? 0, 2.5, accuracy: 1e-9)
        // 6 s ohne Schlag: Schlagzahl 0, obwohl das Gerät noch 24 meldet
        tr.ingest(packet(rate: 24, count: 500), at: 19, into: &s)
        XCTAssertEqual(s.strokeRate, 0)
        XCTAssertEqual(s.rowingState, .inactive)
    }

    func testDevicePaceAndPowerAreUsed() {
        var tr = FTMSRowerTracker(), s = RowingSnapshot()
        tr.ingest(packet(rate: 22, count: 1, distance: 10, pace: 118, power: 214, hr: 150), at: 0, into: &s)
        XCTAssertEqual(s.distance, 10)
        XCTAssertEqual(s.pace, 118)
        XCTAssertEqual(s.speed, 500.0 / 118, accuracy: 1e-9)
        XCTAssertEqual(s.power, 214)
        XCTAssertFalse(s.isPowerEstimated)
        XCTAssertEqual(s.heartRate, 150)
        XCTAssertEqual(s.heartRateSource, .machine)
    }

    func testStrapHeartRateWins() {
        var tr = FTMSRowerTracker(), s = RowingSnapshot()
        s.apply(strap: HeartRateMeasurement(bpm: 133, sensorContact: true, energyExpended: nil, rrIntervals: []))
        tr.ingest(packet(rate: 22, count: 1, hr: 150), at: 0, into: &s)
        XCTAssertEqual(s.heartRate, 133)
        XCTAssertEqual(s.heartRateSource, .strap)
    }

    /// Karges Gerät: nur Schlagzahl, Zähler, Distanz – Tempo aus der Distanzänderung, Watt geschätzt
    func testDerivedPaceAndEstimatedPower() {
        var tr = FTMSRowerTracker(), s = RowingSnapshot()
        for i in 0...8 {
            let t = Double(i) * 0.5
            tr.ingest(packet(rate: 24, count: i / 5, distance: Int(4 * t)), at: t, into: &s)
        }
        XCTAssertTrue(tr.paceDerived)
        XCTAssertEqual(s.pace, 125, accuracy: 0.5)
        XCTAssertEqual(s.power, 0)
        XCTAssertTrue(s.isPowerEstimated)
        XCTAssertEqual(s.displayPower, RowingSnapshot.watts(pace500: s.pace))
        XCTAssertEqual(s.displayPower, 179, accuracy: 3)
        XCTAssertEqual(s.elapsedTime, 2.0, accuracy: 1e-9)   // eigene Uhr: zählt ab dem ersten Schlag (t = 2,5 s)
    }

    func testDistanceFromPaceWhenDeviceHasNoDistance() {
        var tr = FTMSRowerTracker(), s = RowingSnapshot()
        for i in 0...10 {
            tr.ingest(packet(rate: 24, count: i / 2, pace: 125, power: 180), at: Double(i), into: &s)
        }
        XCTAssertTrue(tr.distanceDerived)
        XCTAssertEqual(s.distance, 40, accuracy: 0.01)   // 10 s × 4 m/s
    }

    func testStrokesFromRateWhenDeviceHasNoCount() {
        var tr = FTMSRowerTracker(), s = RowingSnapshot()
        var strokes = 0
        for i in 0...60 {
            var d = FTMSRowerData()
            d.strokeRate = 30
            // Gerät ohne Zähler (Paket nur mit Schlagzahl; der Tracker nimmt Felder unabhängig voneinander)
            strokes += tr.ingest(d, at: Double(i) * 0.5, into: &s)
        }
        XCTAssertTrue(tr.strokesDerived)
        XCTAssertEqual(strokes, 15)          // 30 s × 30/min
        XCTAssertEqual(s.strokeRate, 30)
    }

    /// Konsole meldet ganze statt halbe Schläge: 24 spm werden als Rohwert 24 → 12,0 gelesen
    func testHalfReportedStrokeRateIsCorrected() {
        var tr = FTMSRowerTracker(), s = RowingSnapshot()
        var count = 0
        var t = 0.0
        while t < 60 {
            if t.truncatingRemainder(dividingBy: 2.5) < 0.25 && t > 0 { count += 1 }
            tr.ingest(packet(rate: 12, count: count), at: t, into: &s)
            t += 0.5
        }
        XCTAssertEqual(tr.strokeRateScale, 2)
        XCTAssertEqual(s.strokeRate, 24)
    }

    func testCorrectReportedStrokeRateStaysUnscaled() {
        var tr = FTMSRowerTracker(), s = RowingSnapshot()
        var count = 0
        var t = 0.0
        while t < 60 {
            if t.truncatingRemainder(dividingBy: 2.5) < 0.25 && t > 0 { count += 1 }
            tr.ingest(packet(rate: 24, count: count), at: t, into: &s)
            t += 0.5
        }
        XCTAssertEqual(tr.strokeRateScale, 1)
        XCTAssertEqual(s.strokeRate, 24)
    }

    func testStrokePhaseTrackerFromStrokes() {
        var p = StrokePhaseTracker()
        p.registerStroke(at: 10, interval: 2.4)
        XCTAssertEqual(p.driveTime, 0.8, accuracy: 1e-9)
        XCTAssertEqual(p.recoveryTime, 1.6, accuracy: 1e-9)
        XCTAssertEqual(p.phase(at: 10, strokeRate: 25) ?? -1, 0, accuracy: 1e-9)
        XCTAssertNil(p.phase(at: 17, strokeRate: 25))
    }
}

/// Simulator → Bytes → Parser → Tracker → Fahrt: der ganze FTMS-Pfad ohne Hardware.
final class FTMSSimulatorTests: XCTestCase {
    private func run(minimal: Bool, seconds: Double) -> (RowingSession, RowingSnapshot, FTMSRowerTracker) {
        var sim = FTMSRowerSimulator(settings: .init(pace: 125, strokeRate: 24, sendHeartRate: false), minimal: minimal)
        var tracker = FTMSRowerTracker()
        var snap = RowingSnapshot()
        var session = RowingSession(track: CourseTrack(course: .straight(oneWay: 2000)))
        let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var t = 0.0
        while t < seconds {
            t += 0.25
            let out = sim.step(dt: 0.25)
            for bytes in out.rowerData {
                guard let d = try? FTMSRowerDataParser.parse(bytes) else { XCTFail("Parser"); continue }
                tracker.ingest(d, at: t, into: &snap)
            }
            session.update(snap, at: t0.addingTimeInterval(t))
        }
        return (session, snap, tracker)
    }

    func testFullSimulatorDrivesSession() {
        let (session, snap, tracker) = run(minimal: false, seconds: 120)
        XCTAssertEqual(session.state, .rowing)
        XCTAssertGreaterThan(session.distance, 400)
        XCTAssertLessThan(session.distance, 500)
        XCTAssertGreaterThan(session.strokeCount, 40)
        XCTAssertEqual(snap.strokeRate, 24)
        XCTAssertEqual(snap.pace, 125, accuracy: 2)
        XCTAssertFalse(snap.isPowerEstimated)
        XCTAssertEqual(snap.heartRateSource, .machine)
        XCTAssertFalse(tracker.paceDerived)
        XCTAssertGreaterThan(snap.calories, 0)
    }

    func testMinimalSimulatorDerivesPaceAndPower() {
        let (session, snap, tracker) = run(minimal: true, seconds: 120)
        XCTAssertEqual(session.state, .rowing)
        XCTAssertGreaterThan(session.distance, 400)
        XCTAssertTrue(tracker.paceDerived)
        XCTAssertEqual(snap.pace, 125, accuracy: 6)
        XCTAssertTrue(snap.isPowerEstimated)
        XCTAssertGreaterThan(snap.displayPower, 150)
        XCTAssertNil(snap.heartRate)
    }
}
