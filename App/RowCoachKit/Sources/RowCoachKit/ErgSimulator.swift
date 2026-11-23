import Foundation

/// Erzeugt PM5-Notifications als Bytes, genau im Layout, das `PM5Parser` liest (Little Endian).
/// Dient dem Simulator: er liefert dieselben Bytes wie ein echter PM5 und läuft durch denselben Parser.
public enum PM5Encoder {
    private static func u8(_ v: Double) -> [UInt8] { [UInt8(clamp(v, 255))] }
    private static func u16(_ v: Double) -> [UInt8] {
        let x = UInt32(clamp(v, 65_535)); return [UInt8(x & 0xFF), UInt8((x >> 8) & 0xFF)]
    }
    private static func u24(_ v: Double) -> [UInt8] {
        let x = UInt32(clamp(v, 16_777_215)); return [UInt8(x & 0xFF), UInt8((x >> 8) & 0xFF), UInt8((x >> 16) & 0xFF)]
    }
    private static func clamp(_ v: Double, _ maxV: Double) -> Double {
        guard v.isFinite else { return 0 }
        return min(max(v.rounded(), 0), maxV)
    }

    /// 0x0031, 19 Bytes
    public static func generalStatus(elapsed: TimeInterval, distance: Double, workoutState: PM5WorkoutState,
                                     rowingState: PM5RowingState, strokeState: PM5StrokeState,
                                     dragFactor: Int = 120) -> [UInt8] {
        var b: [UInt8] = []
        b += u24(elapsed * 100)
        b += u24(distance * 10)
        b += [1, 0]                                   // workoutType JustRowNoSplits, intervalType
        b += [workoutState.rawValue, rowingState.rawValue, strokeState.rawValue]
        b += u24(0)                                   // totalWorkDistance
        b += u24(0)                                   // workoutDuration
        b += [0]                                      // workoutDurationType
        b += u8(Double(dragFactor))
        return b
    }

    /// 0x0032, 17 Bytes; Puls nil = 255 (ungültig)
    public static func additionalStatus1(elapsed: TimeInterval, speed: Double, strokeRate: Int, heartRate: Int?,
                                         pace: TimeInterval, averagePace: TimeInterval) -> [UInt8] {
        var b: [UInt8] = []
        b += u24(elapsed * 100)
        b += u16(speed * 1000)
        b += u8(Double(strokeRate))
        b += u8(Double(heartRate ?? 255))
        b += u16(pace * 100)
        b += u16(averagePace * 100)
        b += u16(0)                                   // restDistance
        b += u24(0)                                   // restTime
        b += [0]                                      // ergMachineType
        return b
    }

    /// 0x0033, 20 Bytes
    public static func additionalStatus2(elapsed: TimeInterval, averagePower: Int, calories: Int) -> [UInt8] {
        var b: [UInt8] = []
        b += u24(elapsed * 100)
        b += [0]                                      // intervalCount
        b += u16(Double(averagePower))
        b += u16(Double(calories))
        b += u16(0)                                   // splitAveragePace
        b += u16(0)                                   // splitAveragePower
        b += u16(0)                                   // splitAverageCalories
        b += u24(0)                                   // lastSplitTime
        b += u24(0)                                   // lastSplitDistance
        return b
    }

    /// 0x0035, 20 Bytes
    public static func strokeData(elapsed: TimeInterval, distance: Double, strokeDistance: Double,
                                  driveTime: TimeInterval, recoveryTime: TimeInterval, strokeCount: Int) -> [UInt8] {
        var b: [UInt8] = []
        b += u24(elapsed * 100)
        b += u24(distance * 10)
        b += u8(140)                                  // driveLength 1,40 m
        b += u8(driveTime * 100)
        b += u16(recoveryTime * 100)
        b += u16(strokeDistance * 100)
        b += u16(0)                                   // peakDriveForce
        b += u16(0)                                   // averageDriveForce
        b += u16(0)                                   // workPerStroke
        b += u16(Double(strokeCount))
        return b
    }

    /// 0x0036, 18 Bytes
    public static func additionalStrokeData(elapsed: TimeInterval, power: Int, strokeCount: Int) -> [UInt8] {
        var b: [UInt8] = []
        b += u24(elapsed * 100)
        b += u16(Double(power))
        b += u16(Double(4 * power + 300))             // kcal/h
        b += u16(Double(strokeCount))
        b += u24(0)                                   // projectedWorkTime
        b += u24(0)                                   // projectedWorkDistance
        b += u24(0)                                   // Reserve (Parser erwartet 18 Bytes)
        return b
    }

    /// Heart Rate Measurement (0x2A37): 8-bit-Puls, Kontakt erkannt, optional RR-Intervalle (1/1024 s)
    public static func heartRate(bpm: Int, rrIntervals: [Double] = []) -> [UInt8] {
        var flags: UInt8 = 0x06
        if !rrIntervals.isEmpty { flags |= 0x10 }
        var b: [UInt8] = [flags, UInt8(min(max(bpm, 0), 255))]
        for rr in rrIntervals { b += u16(rr * 1024) }
        return b
    }
}

public struct PM5Packet: Equatable, Sendable {
    public var characteristic: PM5.Characteristic
    public var bytes: [UInt8]

    public init(characteristic: PM5.Characteristic, bytes: [UInt8]) {
        self.characteristic = characteristic
        self.bytes = bytes
    }
}

/// Synthetischer Ruderer am PM5: Tempo und Schlagzahl einstellbar, Puls folgt der Belastung träge.
/// Plattformunabhängig und deterministisch, damit er sich testen lässt. Die App ruft `step` etwa alle 0,25 s auf.
public struct ErgSimulator: Sendable {
    public struct Settings: Equatable, Sendable {
        /// Zieltempo, s pro 500 m
        public var pace: TimeInterval
        public var strokeRate: Int
        public var restHR: Int
        public var maxHR: Int
        /// false = Ruderer hört auf (Pause testen)
        public var rowing: Bool
        public var sendHeartRate: Bool

        public init(pace: TimeInterval = 125, strokeRate: Int = 22, restHR: Int = 60, maxHR: Int = 185,
                    rowing: Bool = true, sendHeartRate: Bool = true) {
            self.pace = pace
            self.strokeRate = strokeRate
            self.restHR = restHR
            self.maxHR = maxHR
            self.rowing = rowing
            self.sendHeartRate = sendHeartRate
        }
    }

    public struct Output: Equatable, Sendable {
        public var pm5: [PM5Packet]
        /// Bytes des Pulsgurts (0x2A37), etwa einmal pro Sekunde
        public var heartRate: [UInt8]?
    }

    public var settings: Settings
    public private(set) var elapsed: TimeInterval = 0
    public private(set) var distance: Double
    public private(set) var speed: Double = 0
    public private(set) var strokeCount = 0
    public private(set) var calories: Double = 0
    public private(set) var heartRate: Double
    public private(set) var energy: Double = 0
    private var sinceStroke: TimeInterval = 0
    private var sinceHR: TimeInterval = 0
    private var started = false
    private var clock: TimeInterval = 0

    public init(settings: Settings = Settings(), startDistance: Double = 0) {
        self.settings = settings
        self.distance = max(startDistance, 0)
        self.heartRate = Double(settings.restHR + 10)
    }

    /// Wie ein Neustart am PM5: Uhr, Distanz, Schläge und Kalorien springen auf 0.
    public mutating func resetMonitor() {
        elapsed = 0; distance = 0; strokeCount = 0; calories = 0; energy = 0; started = false
    }

    public var power: Int { speed > 0.05 ? Int((2.8 * pow(speed, 3)).rounded()) : 0 }
    public var currentPace: TimeInterval { speed > 0.1 ? 500 / speed : 0 }

    public mutating func step(dt: TimeInterval) -> Output {
        let dt = min(max(dt, 0), 2)
        clock += dt
        let target = settings.rowing && settings.pace > 0 ? 500 / settings.pace : 0
        // Schwungrad: Geschwindigkeit folgt dem Ziel mit etwa 1,5 s Verzögerung
        speed += (target - speed) * min(1, dt / 1.5)
        if target == 0 && speed < 0.1 { speed = 0 }
        if speed > 0 { started = true }
        if started && speed > 0 { elapsed += dt }
        distance += speed * dt
        let w = Double(power)
        energy += w * dt
        if speed > 0 { calories += (4 * w + 300) / 3600 * dt }

        var out = Output(pm5: [], heartRate: nil)
        let interval = settings.strokeRate > 0 ? 60 / Double(settings.strokeRate) : .infinity
        sinceStroke += dt
        if settings.rowing && sinceStroke >= interval {
            sinceStroke = 0
            strokeCount += 1
            let drive = min(0.8, interval / 3)
            out.pm5.append(PM5Packet(characteristic: .strokeData, bytes: PM5Encoder.strokeData(
                elapsed: elapsed, distance: distance, strokeDistance: speed * interval, driveTime: drive,
                recoveryTime: interval - drive, strokeCount: strokeCount)))
            out.pm5.append(PM5Packet(characteristic: .additionalStrokeData, bytes: PM5Encoder.additionalStrokeData(
                elapsed: elapsed, power: power, strokeCount: strokeCount)))
        }

        let rowingState: PM5RowingState = speed > 0 ? .active : .inactive
        let avgPower = elapsed > 0 ? Int((energy / elapsed).rounded()) : 0
        let avgPace = distance > 1 && elapsed > 0 ? elapsed / distance * 500 : 0
        out.pm5.append(PM5Packet(characteristic: .generalStatus, bytes: PM5Encoder.generalStatus(
            elapsed: elapsed, distance: distance, workoutState: started ? .workoutRow : .waitToBegin,
            rowingState: rowingState, strokeState: settings.rowing ? .recovery : .waitingForWheelMinSpeed)))
        out.pm5.append(PM5Packet(characteristic: .additionalStatus1, bytes: PM5Encoder.additionalStatus1(
            elapsed: elapsed, speed: speed, strokeRate: settings.rowing ? settings.strokeRate : 0, heartRate: nil,
            pace: currentPace, averagePace: avgPace)))
        out.pm5.append(PM5Packet(characteristic: .additionalStatus2, bytes: PM5Encoder.additionalStatus2(
            elapsed: elapsed, averagePower: avgPower, calories: Int(calories))))

        // Puls: Ziel aus der Leistung, träge (Zeitkonstante 25 s), leichte deterministische Schwankung
        let reserve = Double(max(settings.maxHR - settings.restHR, 1))
        let intensity = min(max((w - 40) / 260, 0), 1)
        let targetHR = Double(settings.restHR) + reserve * (speed > 0 ? 0.35 + 0.55 * intensity : 0.15)
        heartRate += (targetHR - heartRate) * min(1, dt / 25)
        sinceHR += dt
        if settings.sendHeartRate && sinceHR >= 1 {
            sinceHR = 0
            let bpm = Int((heartRate + 1.5 * sin(clock * 0.7)).rounded())
            out.heartRate = PM5Encoder.heartRate(bpm: bpm, rrIntervals: bpm > 0 ? [60 / Double(bpm)] : [])
        }
        return out
    }
}
