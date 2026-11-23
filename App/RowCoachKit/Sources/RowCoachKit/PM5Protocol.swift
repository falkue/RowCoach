import Foundation

/// Concept2 PM5 Bluetooth-Protokoll.
/// Quelle: Concept2 "PM CSAFE Communication Definition", Rev. 0.31 (2026-03), Abschnitt "Smart Bluetooth",
/// https://www.concept2.com/support/software-development – Byte-Layouts der Rowing-Service-Characteristics.
/// Mehrbyte-Werte in den Notifications sind Little Endian (Lo, Mid, Hi).
public enum PM5 {
    /// Basis-UUID CE06XXXX-43E5-11E4-916C-0800200C9A66
    public static func uuid(_ short: UInt16) -> String {
        String(format: "CE06%04X-43E5-11E4-916C-0800200C9A66", short)
    }

    public static let discoveryService = uuid(0x0000)
    public static let deviceInfoService = uuid(0x0010)
    public static let controlService = uuid(0x0020)
    public static let rowingService = uuid(0x0030)

    public enum Characteristic: UInt16, CaseIterable, Sendable {
        case generalStatus = 0x0031
        case additionalStatus1 = 0x0032
        case additionalStatus2 = 0x0033
        case sampleRate = 0x0034
        case strokeData = 0x0035
        case additionalStrokeData = 0x0036
        case workoutSummary = 0x0039

        public var uuid: String { PM5.uuid(rawValue) }

        /// Characteristics, die RowCoach abonniert.
        public static let subscribed: [Characteristic] = [
            .generalStatus, .additionalStatus1, .additionalStatus2, .strokeData, .additionalStrokeData, .workoutSummary,
        ]
    }

    /// Wert für 0x0034: wie oft der PM5 Status-Notifications sendet.
    public enum SampleRate: UInt8, Sendable {
        case s1 = 0, ms500 = 1, ms250 = 2, ms100 = 3
    }
}

/// Workout State (Appendix "Workout State").
public enum PM5WorkoutState: UInt8, Sendable {
    case waitToBegin = 0, workoutRow, countdownPause, intervalRest, intervalWorkTime, intervalWorkDistance,
         intervalRestEndToWorkTime, intervalRestEndToWorkDistance, intervalWorkTimeToRest,
         intervalWorkDistanceToRest, workoutEnd, terminate, workoutLogged, rearm
}

public enum PM5RowingState: UInt8, Sendable { case inactive = 0, active = 1 }

public enum PM5StrokeState: UInt8, Sendable {
    case waitingForWheelMinSpeed = 0, waitingForWheelAccelerate, driving, dwellingAfterDrive, recovery
}

// MARK: - Datensätze

/// 0x0031 General Status (19 Bytes)
public struct PM5GeneralStatus: Equatable, Sendable {
    public var elapsedTime: TimeInterval      // s
    public var distance: Double               // m
    public var workoutType: UInt8
    public var intervalType: UInt8
    public var workoutState: PM5WorkoutState?
    public var rowingState: PM5RowingState?
    public var strokeState: PM5StrokeState?
    public var totalWorkDistance: Int         // m
    public var workoutDuration: UInt32        // 0.01 s bei Zeit, sonst je nach durationType
    public var workoutDurationType: UInt8     // 0 Zeit, 0x40 Kalorien, 0x80 Distanz, 0xC0 Wattminuten
    public var dragFactor: UInt8
}

/// 0x0032 Additional Status 1 (17 Bytes)
public struct PM5AdditionalStatus1: Equatable, Sendable {
    public var elapsedTime: TimeInterval
    public var speed: Double                  // m/s
    public var strokeRate: Int                // Schläge/min
    public var heartRate: Int?                // bpm, nil wenn ungültig (255)
    public var currentPace: TimeInterval      // s pro 500 m
    public var averagePace: TimeInterval      // s pro 500 m
    public var restDistance: Int              // m
    public var restTime: TimeInterval         // s
    public var ergMachineType: UInt8?
}

/// 0x0033 Additional Status 2 (20 Bytes)
public struct PM5AdditionalStatus2: Equatable, Sendable {
    public var elapsedTime: TimeInterval
    public var intervalCount: Int
    public var averagePower: Int              // W
    public var totalCalories: Int             // kcal
    public var splitAveragePace: TimeInterval // s pro 500 m
    public var splitAveragePower: Int         // W
    public var splitAverageCalories: Int      // kcal/h
    public var lastSplitTime: TimeInterval    // s (0.1 s Auflösung)
    public var lastSplitDistance: Int         // m
}

/// 0x0035 Stroke Data (20 Bytes)
public struct PM5StrokeData: Equatable, Sendable {
    public var elapsedTime: TimeInterval
    public var distance: Double               // m
    public var driveLength: Double            // m
    public var driveTime: TimeInterval        // s
    public var recoveryTime: TimeInterval     // s
    public var strokeDistance: Double         // m
    public var peakDriveForce: Double         // lbf
    public var averageDriveForce: Double      // lbf
    public var workPerStroke: Double          // J
    public var strokeCount: Int
}

/// 0x0036 Additional Stroke Data (18 Bytes)
public struct PM5AdditionalStrokeData: Equatable, Sendable {
    public var elapsedTime: TimeInterval
    public var strokePower: Int               // W
    public var strokeCalories: Int            // kcal/h
    public var strokeCount: Int
    public var projectedWorkTime: Int         // s
    public var projectedWorkDistance: Int     // m
}

/// 0x0039 End of Workout Summary (20 Bytes)
public struct PM5WorkoutSummary: Equatable, Sendable {
    public var logDate: UInt16
    public var logTime: UInt16
    public var elapsedTime: TimeInterval
    public var distance: Double
    public var averageStrokeRate: Int
    public var endingHeartRate: Int?
    public var averageHeartRate: Int?
    public var minHeartRate: Int?
    public var maxHeartRate: Int?
    public var dragFactorAverage: Int
    public var recoveryHeartRate: Int?        // 0 = (noch) ungültig; kommt nach 1 min Erholung erneut
    public var workoutType: UInt8
    public var averagePace: TimeInterval      // s pro 500 m (0.1 s Auflösung)
}

public enum PM5Message: Equatable, Sendable {
    case generalStatus(PM5GeneralStatus)
    case additionalStatus1(PM5AdditionalStatus1)
    case additionalStatus2(PM5AdditionalStatus2)
    case strokeData(PM5StrokeData)
    case additionalStrokeData(PM5AdditionalStrokeData)
    case workoutSummary(PM5WorkoutSummary)
}

// MARK: - Parser

public enum PM5ParseError: Error, Equatable {
    case tooShort(characteristic: UInt16, expected: Int, got: Int)
    case unsupported(UInt16)
}

private struct LEReader {
    let b: [UInt8]
    var i = 0
    init(_ data: [UInt8]) { b = data }
    mutating func u8() -> UInt8 { defer { i += 1 }; return b[i] }
    mutating func u16() -> UInt16 { defer { i += 2 }; return UInt16(b[i]) | UInt16(b[i + 1]) << 8 }
    mutating func u24() -> UInt32 {
        defer { i += 3 }
        return UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16
    }
}

private func hr(_ v: UInt8) -> Int? { (v == 0 || v == 255) ? nil : Int(v) }

public enum PM5Parser {
    public static let expectedLength: [PM5.Characteristic: Int] = [
        .generalStatus: 19, .additionalStatus1: 17, .additionalStatus2: 20,
        .strokeData: 20, .additionalStrokeData: 18, .workoutSummary: 20,
    ]

    /// Mindestlänge je Characteristic: nur die Felder, ohne die die Nachricht nutzlos ist. Ältere PM5-Firmware
    /// sendet manche Nachrichten kürzer (z. B. 0x0036 mit 15 statt 18 Bytes, ohne „Projected Work Other“);
    /// fehlende hintere Felder werden mit 0 aufgefüllt statt die ganze Nachricht zu verwerfen.
    public static let minimumLength: [PM5.Characteristic: Int] = [
        .generalStatus: 19, .additionalStatus1: 16, .additionalStatus2: 8,
        .strokeData: 18, .additionalStrokeData: 9, .workoutSummary: 18,
    ]

    public static func parse(characteristic: PM5.Characteristic, bytes: [UInt8]) throws -> PM5Message {
        guard let need = expectedLength[characteristic], let minimum = minimumLength[characteristic] else {
            throw PM5ParseError.unsupported(characteristic.rawValue)
        }
        guard bytes.count >= minimum else {
            throw PM5ParseError.tooShort(characteristic: characteristic.rawValue, expected: minimum, got: bytes.count)
        }
        let original = bytes.count
        let bytes = bytes.count >= need ? bytes : bytes + [UInt8](repeating: 0, count: need - bytes.count)
        var r = LEReader(bytes)
        switch characteristic {
        case .generalStatus:
            return .generalStatus(PM5GeneralStatus(
                elapsedTime: Double(r.u24()) / 100, distance: Double(r.u24()) / 10,
                workoutType: r.u8(), intervalType: r.u8(),
                workoutState: PM5WorkoutState(rawValue: r.u8()), rowingState: PM5RowingState(rawValue: r.u8()),
                strokeState: PM5StrokeState(rawValue: r.u8()),
                totalWorkDistance: Int(r.u24()), workoutDuration: r.u24(), workoutDurationType: r.u8(),
                dragFactor: r.u8()))
        case .additionalStatus1:
            return .additionalStatus1(PM5AdditionalStatus1(
                elapsedTime: Double(r.u24()) / 100, speed: Double(r.u16()) / 1000, strokeRate: Int(r.u8()),
                heartRate: hr(r.u8()), currentPace: Double(r.u16()) / 100, averagePace: Double(r.u16()) / 100,
                restDistance: Int(r.u16()), restTime: Double(r.u24()) / 100,
                ergMachineType: original >= 17 ? r.u8() : nil))
        case .additionalStatus2:
            return .additionalStatus2(PM5AdditionalStatus2(
                elapsedTime: Double(r.u24()) / 100, intervalCount: Int(r.u8()), averagePower: Int(r.u16()),
                totalCalories: Int(r.u16()), splitAveragePace: Double(r.u16()) / 100,
                splitAveragePower: Int(r.u16()), splitAverageCalories: Int(r.u16()),
                lastSplitTime: Double(r.u24()) / 10, lastSplitDistance: Int(r.u24())))
        case .strokeData:
            return .strokeData(PM5StrokeData(
                elapsedTime: Double(r.u24()) / 100, distance: Double(r.u24()) / 10,
                driveLength: Double(r.u8()) / 100, driveTime: Double(r.u8()) / 100,
                recoveryTime: Double(r.u16()) / 100, strokeDistance: Double(r.u16()) / 100,
                peakDriveForce: Double(r.u16()) / 10, averageDriveForce: Double(r.u16()) / 10,
                workPerStroke: Double(r.u16()) / 10, strokeCount: Int(r.u16())))
        case .additionalStrokeData:
            return .additionalStrokeData(PM5AdditionalStrokeData(
                elapsedTime: Double(r.u24()) / 100, strokePower: Int(r.u16()), strokeCalories: Int(r.u16()),
                strokeCount: Int(r.u16()), projectedWorkTime: Int(r.u24()), projectedWorkDistance: Int(r.u24())))
        case .workoutSummary:
            return .workoutSummary(PM5WorkoutSummary(
                logDate: r.u16(), logTime: r.u16(), elapsedTime: Double(r.u24()) / 100,
                distance: Double(r.u24()) / 10, averageStrokeRate: Int(r.u8()),
                endingHeartRate: hr(r.u8()), averageHeartRate: hr(r.u8()), minHeartRate: hr(r.u8()),
                maxHeartRate: hr(r.u8()), dragFactorAverage: Int(r.u8()), recoveryHeartRate: hr(r.u8()),
                workoutType: r.u8(), averagePace: Double(r.u16()) / 10))
        case .sampleRate:
            throw PM5ParseError.unsupported(characteristic.rawValue)
        }
    }
}
