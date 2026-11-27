import Foundation

/// Bluetooth SIG Fitness Machine Service (FTMS, 0x1826), Fassung 1.0, für Rudergeräte.
///
/// Quellen (nur Spezifikation, kein fremder Code): Bluetooth SIG „Fitness Machine Service 1.0“ (2017) mit den
/// Characteristic-Definitionen der GATT Specification Supplement (GSS) bzw. den älteren XML-Definitionen
/// (org.bluetooth.characteristic.rower_data). Alle Mehrbyte-Werte sind Little Endian.
/// Einzelheiten, Gerätebesonderheiten und Belege: docs/geraete/RECHERCHE.md und docs/geraete/UMSETZUNG.md.
public enum FTMS {
    /// 16-Bit-UUIDs (CoreBluetooth akzeptiert die Kurzform)
    public static let service = "1826"

    public enum Characteristic: String, CaseIterable, Sendable {
        case feature = "2ACC"
        case rowerData = "2AD1"
        case trainingStatus = "2AD3"
        case supportedResistanceRange = "2AD6"
        case controlPoint = "2AD9"
        case machineStatus = "2ADA"
    }
}

// MARK: - Werbepaket (Service Data)

/// Fitness Machine Type im Service-Data-Feld des Werbepakets (FTMS 1.0, Abschnitt 3.1.1).
public struct FTMSMachineTypes: OptionSet, Equatable, Sendable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }
    public static let treadmill = FTMSMachineTypes(rawValue: 1 << 0)
    public static let crossTrainer = FTMSMachineTypes(rawValue: 1 << 1)
    public static let stepClimber = FTMSMachineTypes(rawValue: 1 << 2)
    public static let stairClimber = FTMSMachineTypes(rawValue: 1 << 3)
    public static let rower = FTMSMachineTypes(rawValue: 1 << 4)
    public static let indoorBike = FTMSMachineTypes(rawValue: 1 << 5)
}

/// Service Data zu 0x1826: Flags (1 Byte, Bit 0 = „Fitness Machine Available“) und Fitness Machine Type (2 Byte).
public struct FTMSAdvertisement: Equatable, Sendable {
    public var available: Bool
    public var machineTypes: FTMSMachineTypes

    public init(available: Bool, machineTypes: FTMSMachineTypes) {
        self.available = available
        self.machineTypes = machineTypes
    }

    public static func parse(serviceData b: [UInt8]) -> FTMSAdvertisement? {
        guard b.count >= 3 else { return nil }
        return FTMSAdvertisement(available: b[0] & 0x01 != 0,
                                 machineTypes: FTMSMachineTypes(rawValue: UInt16(b[1]) | UInt16(b[2]) << 8))
    }

    /// Ist das ein Gerät, das RowCoach als Rudergerät anbieten soll? Ohne Service Data (viele Geräte senden keine)
    /// entscheidet erst die Characteristic 0x2AD1 beim Verbinden.
    public static func isRowerCandidate(advertisesService: Bool, serviceData: [UInt8]?) -> Bool {
        if let d = serviceData, let ad = parse(serviceData: d) {
            // Typ-Bits gesetzt, aber kein Rudergerät (z. B. Fahrrad, Laufband): nicht anbieten
            return ad.machineTypes.isEmpty || ad.machineTypes.contains(.rower)
        }
        return advertisesService
    }
}

// MARK: - Fitness Machine Feature (0x2ACC)

public struct FTMSMachineFeatures: OptionSet, Equatable, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let averageSpeed = FTMSMachineFeatures(rawValue: 1 << 0)
    public static let cadence = FTMSMachineFeatures(rawValue: 1 << 1)
    public static let totalDistance = FTMSMachineFeatures(rawValue: 1 << 2)
    public static let inclination = FTMSMachineFeatures(rawValue: 1 << 3)
    public static let elevationGain = FTMSMachineFeatures(rawValue: 1 << 4)
    public static let pace = FTMSMachineFeatures(rawValue: 1 << 5)
    public static let stepCount = FTMSMachineFeatures(rawValue: 1 << 6)
    public static let resistanceLevel = FTMSMachineFeatures(rawValue: 1 << 7)
    public static let strideCount = FTMSMachineFeatures(rawValue: 1 << 8)
    public static let expendedEnergy = FTMSMachineFeatures(rawValue: 1 << 9)
    public static let heartRate = FTMSMachineFeatures(rawValue: 1 << 10)
    public static let metabolicEquivalent = FTMSMachineFeatures(rawValue: 1 << 11)
    public static let elapsedTime = FTMSMachineFeatures(rawValue: 1 << 12)
    public static let remainingTime = FTMSMachineFeatures(rawValue: 1 << 13)
    public static let powerMeasurement = FTMSMachineFeatures(rawValue: 1 << 14)
    public static let forceOnBeltAndPowerOutput = FTMSMachineFeatures(rawValue: 1 << 15)
    public static let userDataRetention = FTMSMachineFeatures(rawValue: 1 << 16)
}

/// 0x2ACC: Fitness Machine Features (uint32) und Target Setting Features (uint32).
public struct FTMSFeatures: Equatable, Sendable {
    public var machine: FTMSMachineFeatures
    /// Bits der Target Setting Features (Bit 2 Widerstand, Bit 3 Leistung …); RowCoach steuert das Gerät nicht.
    public var targetSettings: UInt32

    public init(machine: FTMSMachineFeatures, targetSettings: UInt32) {
        self.machine = machine
        self.targetSettings = targetSettings
    }

    public static func parse(_ b: [UInt8]) -> FTMSFeatures? {
        guard b.count >= 4 else { return nil }
        func u32(_ i: Int) -> UInt32 {
            UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
        }
        return FTMSFeatures(machine: FTMSMachineFeatures(rawValue: u32(0)),
                            targetSettings: b.count >= 8 ? u32(4) : 0)
    }
}

// MARK: - Rower Data (0x2AD1)

/// Flags der Rower Data. Achtung: Bit 0 „More Data“ ist invertiert – ist es 0, sind Stroke Rate und Stroke Count
/// enthalten; ist es 1, fehlen sie (das Paket ist ein Teil einer aufgeteilten Nachricht).
public struct FTMSRowerFlags: OptionSet, Equatable, Sendable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }
    public static let moreData = FTMSRowerFlags(rawValue: 1 << 0)
    public static let averageStrokeRate = FTMSRowerFlags(rawValue: 1 << 1)
    public static let totalDistance = FTMSRowerFlags(rawValue: 1 << 2)
    public static let instantaneousPace = FTMSRowerFlags(rawValue: 1 << 3)
    public static let averagePace = FTMSRowerFlags(rawValue: 1 << 4)
    public static let instantaneousPower = FTMSRowerFlags(rawValue: 1 << 5)
    public static let averagePower = FTMSRowerFlags(rawValue: 1 << 6)
    public static let resistanceLevel = FTMSRowerFlags(rawValue: 1 << 7)
    public static let expendedEnergy = FTMSRowerFlags(rawValue: 1 << 8)
    public static let heartRate = FTMSRowerFlags(rawValue: 1 << 9)
    public static let metabolicEquivalent = FTMSRowerFlags(rawValue: 1 << 10)
    public static let elapsedTime = FTMSRowerFlags(rawValue: 1 << 11)
    public static let remainingTime = FTMSRowerFlags(rawValue: 1 << 12)
}

/// Eine Rower-Data-Notification; nil = Feld nicht im Paket (oder vom Gerät als „nicht verfügbar“ markiert).
public struct FTMSRowerData: Equatable, Sendable {
    public var flags: FTMSRowerFlags = []
    /// Schläge/min (Auflösung 0,5)
    public var strokeRate: Double?
    public var strokeCount: Int?
    /// Schläge/min (Auflösung 0,5)
    public var averageStrokeRate: Double?
    /// m (uint24)
    public var totalDistance: Int?
    /// s pro 500 m
    public var instantaneousPace: Int?
    public var averagePace: Int?
    /// W (sint16, kann negativ sein)
    public var instantaneousPower: Int?
    public var averagePower: Int?
    /// Widerstandsstufe ohne Einheit (Rohwert)
    public var resistanceLevel: Int?
    /// Breite des Widerstandsfelds im Paket: 2 (sint16, FTMS 1.0/XML) oder 1 (uint8, neuere GSS); nil = nicht enthalten
    public var resistanceFieldWidth: Int?
    /// kcal gesamt
    public var totalEnergy: Int?
    /// kcal/h
    public var energyPerHour: Int?
    /// kcal/min
    public var energyPerMinute: Int?
    /// bpm
    public var heartRate: Int?
    /// MET (Auflösung 0,1)
    public var metabolicEquivalent: Double?
    /// s
    public var elapsedTime: Int?
    /// s
    public var remainingTime: Int?

    public init() {}

    /// Felder eines späteren Pakets übernehmen (nur die enthaltenen).
    public mutating func merge(_ o: FTMSRowerData) {
        flags.formUnion(o.flags)
        if let v = o.strokeRate { strokeRate = v }
        if let v = o.strokeCount { strokeCount = v }
        if let v = o.averageStrokeRate { averageStrokeRate = v }
        if let v = o.totalDistance { totalDistance = v }
        if let v = o.instantaneousPace { instantaneousPace = v }
        if let v = o.averagePace { averagePace = v }
        if let v = o.instantaneousPower { instantaneousPower = v }
        if let v = o.averagePower { averagePower = v }
        if let v = o.resistanceLevel { resistanceLevel = v; resistanceFieldWidth = o.resistanceFieldWidth }
        if let v = o.totalEnergy { totalEnergy = v }
        if let v = o.energyPerHour { energyPerHour = v }
        if let v = o.energyPerMinute { energyPerMinute = v }
        if let v = o.heartRate { heartRate = v }
        if let v = o.metabolicEquivalent { metabolicEquivalent = v }
        if let v = o.elapsedTime { elapsedTime = v }
        if let v = o.remainingTime { remainingTime = v }
    }
}

public enum FTMSParseError: Error, Equatable {
    case tooShort(expected: Int, got: Int)
}

public enum FTMSRowerDataParser {
    /// Länge der Felder vor bzw. nach dem Widerstandsfeld (ohne die 2 Flag-Bytes).
    static func fieldBytes(_ f: FTMSRowerFlags) -> (before: Int, after: Int) {
        var before = 0, after = 0
        if !f.contains(.moreData) { before += 3 }            // Stroke Rate uint8 + Stroke Count uint16
        if f.contains(.averageStrokeRate) { before += 1 }
        if f.contains(.totalDistance) { before += 3 }
        if f.contains(.instantaneousPace) { before += 2 }
        if f.contains(.averagePace) { before += 2 }
        if f.contains(.instantaneousPower) { before += 2 }
        if f.contains(.averagePower) { before += 2 }
        if f.contains(.expendedEnergy) { after += 5 }         // uint16 + uint16 + uint8
        if f.contains(.heartRate) { after += 1 }
        if f.contains(.metabolicEquivalent) { after += 1 }
        if f.contains(.elapsedTime) { after += 2 }
        if f.contains(.remainingTime) { after += 2 }
        return (before, after)
    }

    /// Liest ein Rower-Data-Paket. Das Widerstandsfeld ist in der Spezifikation uneinheitlich (FTMS 1.0/XML: sint16,
    /// neuere GSS: uint8): die Breite ergibt sich aus der Paketlänge; passt beides nicht genau, gilt sint16.
    /// Überzählige Bytes am Ende werden ignoriert.
    public static func parse(_ b: [UInt8]) throws -> FTMSRowerData {
        guard b.count >= 2 else { throw FTMSParseError.tooShort(expected: 2, got: b.count) }
        let flags = FTMSRowerFlags(rawValue: UInt16(b[0]) | UInt16(b[1]) << 8)
        let (before, after) = fieldBytes(flags)
        var resistanceWidth = 0
        if flags.contains(.resistanceLevel) {
            let wide = 2 + before + 2 + after, narrow = 2 + before + 1 + after
            if b.count >= wide { resistanceWidth = 2 } else if b.count == narrow { resistanceWidth = 1 } else {
                throw FTMSParseError.tooShort(expected: wide, got: b.count)
            }
        } else if b.count < 2 + before + after {
            throw FTMSParseError.tooShort(expected: 2 + before + after, got: b.count)
        }

        var i = 2
        func u8() -> Int { defer { i += 1 }; return Int(b[i]) }
        func u16() -> Int { defer { i += 2 }; return Int(b[i]) | Int(b[i + 1]) << 8 }
        func s16() -> Int { Int(Int16(bitPattern: UInt16(u16()))) }
        func u24() -> Int { defer { i += 3 }; return Int(b[i]) | Int(b[i + 1]) << 8 | Int(b[i + 2]) << 16 }

        var d = FTMSRowerData()
        d.flags = flags
        if !flags.contains(.moreData) {
            d.strokeRate = Double(u8()) / 2
            d.strokeCount = u16()
        }
        if flags.contains(.averageStrokeRate) { d.averageStrokeRate = Double(u8()) / 2 }
        if flags.contains(.totalDistance) { d.totalDistance = u24() }
        if flags.contains(.instantaneousPace) { d.instantaneousPace = u16() }
        if flags.contains(.averagePace) { d.averagePace = u16() }
        if flags.contains(.instantaneousPower) { d.instantaneousPower = s16() }
        if flags.contains(.averagePower) { d.averagePower = s16() }
        if resistanceWidth == 2 {
            d.resistanceLevel = s16(); d.resistanceFieldWidth = 2
        } else if resistanceWidth == 1 {
            d.resistanceLevel = u8(); d.resistanceFieldWidth = 1
        }
        if flags.contains(.expendedEnergy) {
            // 0xFFFF bzw. 0xFF = „vom Gerät nicht unterstützt“
            let total = u16(), perHour = u16(), perMinute = u8()
            d.totalEnergy = total == 0xFFFF ? nil : total
            d.energyPerHour = perHour == 0xFFFF ? nil : perHour
            d.energyPerMinute = perMinute == 0xFF ? nil : perMinute
        }
        if flags.contains(.heartRate) { let h = u8(); d.heartRate = h == 0 ? nil : h }
        if flags.contains(.metabolicEquivalent) { d.metabolicEquivalent = Double(u8()) / 10 }
        if flags.contains(.elapsedTime) { d.elapsedTime = u16() }
        if flags.contains(.remainingTime) { d.remainingTime = u16() }
        return d
    }
}

/// Erzeugt Rower-Data-Pakete (für den FTMS-Simulator und Tests), Widerstand als sint16.
public enum FTMSRowerDataEncoder {
    public static func encode(_ d: FTMSRowerData) -> [UInt8] {
        var f: FTMSRowerFlags = []
        if d.strokeRate == nil || d.strokeCount == nil { f.insert(.moreData) }
        if d.averageStrokeRate != nil { f.insert(.averageStrokeRate) }
        if d.totalDistance != nil { f.insert(.totalDistance) }
        if d.instantaneousPace != nil { f.insert(.instantaneousPace) }
        if d.averagePace != nil { f.insert(.averagePace) }
        if d.instantaneousPower != nil { f.insert(.instantaneousPower) }
        if d.averagePower != nil { f.insert(.averagePower) }
        if d.resistanceLevel != nil { f.insert(.resistanceLevel) }
        if d.totalEnergy != nil || d.energyPerHour != nil || d.energyPerMinute != nil { f.insert(.expendedEnergy) }
        if d.heartRate != nil { f.insert(.heartRate) }
        if d.metabolicEquivalent != nil { f.insert(.metabolicEquivalent) }
        if d.elapsedTime != nil { f.insert(.elapsedTime) }
        if d.remainingTime != nil { f.insert(.remainingTime) }

        func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int { min(max(v, lo), hi) }
        func u8(_ v: Int) -> [UInt8] { [UInt8(clamp(v, 0, 255))] }
        func u16(_ v: Int) -> [UInt8] { let x = clamp(v, 0, 65_535); return [UInt8(x & 0xFF), UInt8(x >> 8)] }
        func s16(_ v: Int) -> [UInt8] {
            let x = UInt16(bitPattern: Int16(clamp(v, -32_768, 32_767))); return [UInt8(x & 0xFF), UInt8(x >> 8)]
        }
        func u24(_ v: Int) -> [UInt8] {
            let x = clamp(v, 0, 16_777_215); return [UInt8(x & 0xFF), UInt8((x >> 8) & 0xFF), UInt8(x >> 16)]
        }
        func half(_ spm: Double) -> Int { spm.isFinite ? Int((spm * 2).rounded()) : 0 }

        var b = u16(Int(f.rawValue))
        if !f.contains(.moreData), let r = d.strokeRate, let c = d.strokeCount { b += u8(half(r)) + u16(c) }
        if let v = d.averageStrokeRate { b += u8(half(v)) }
        if let v = d.totalDistance { b += u24(v) }
        if let v = d.instantaneousPace { b += u16(v) }
        if let v = d.averagePace { b += u16(v) }
        if let v = d.instantaneousPower { b += s16(v) }
        if let v = d.averagePower { b += s16(v) }
        if let v = d.resistanceLevel { b += s16(v) }
        if f.contains(.expendedEnergy) {
            b += u16(d.totalEnergy ?? 0xFFFF) + u16(d.energyPerHour ?? 0xFFFF) + u8(d.energyPerMinute ?? 0xFF)
        }
        if let v = d.heartRate { b += u8(v) }
        if let v = d.metabolicEquivalent { b += u8(Int((v * 10).rounded())) }
        if let v = d.elapsedTime { b += u16(v) }
        if let v = d.remainingTime { b += u16(v) }
        return b
    }
}

// MARK: - Control Point (0x2AD9) und Status (0x2ADA)

/// Befehle an den Fitness Machine Control Point. Vor jedem anderen Befehl muss „Request Control“ erfolgreich sein.
/// RowCoach sendet heute keine Befehle von selbst (siehe docs/geraete/UMSETZUNG.md); die Kodierung ist getestet.
public enum FTMSControlCommand: Equatable, Sendable {
    case requestControl
    case reset
    case startOrResume
    case stop
    case pause

    public var opCode: UInt8 {
        switch self {
        case .requestControl: return 0x00
        case .reset: return 0x01
        case .startOrResume: return 0x07
        case .stop, .pause: return 0x08
        }
    }

    public var bytes: [UInt8] {
        switch self {
        case .stop: return [opCode, 0x01]
        case .pause: return [opCode, 0x02]
        default: return [opCode]
        }
    }
}

public enum FTMSResultCode: UInt8, Sendable {
    case success = 0x01, opCodeNotSupported = 0x02, invalidParameter = 0x03, operationFailed = 0x04,
         controlNotPermitted = 0x05
}

/// Antwort des Geräts (Indication auf 0x2AD9): 0x80, Op Code der Anfrage, Ergebnis.
public struct FTMSControlResponse: Equatable, Sendable {
    public var requestOpCode: UInt8
    public var result: FTMSResultCode?
    public var rawResult: UInt8

    public static func parse(_ b: [UInt8]) -> FTMSControlResponse? {
        guard b.count >= 3, b[0] == 0x80 else { return nil }
        return FTMSControlResponse(requestOpCode: b[1], result: FTMSResultCode(rawValue: b[2]), rawResult: b[2])
    }
}

/// Fitness Machine Status (Notification auf 0x2ADA), nur die für ein Rudergerät wichtigen Meldungen.
public enum FTMSMachineStatus: Equatable, Sendable {
    case reset
    case stoppedByUser
    case pausedByUser
    case stoppedBySafetyKey
    case startedOrResumedByUser
    case controlPermissionLost
    case other(UInt8)

    public static func parse(_ b: [UInt8]) -> FTMSMachineStatus? {
        guard let op = b.first else { return nil }
        switch op {
        case 0x01: return .reset
        case 0x02: return b.count >= 2 && b[1] == 0x02 ? .pausedByUser : .stoppedByUser
        case 0x03: return .stoppedBySafetyKey
        case 0x04: return .startedOrResumedByUser
        case 0xFF: return .controlPermissionLost
        default: return .other(op)
        }
    }
}
