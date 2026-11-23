import Foundation

/// Bluetooth SIG Heart Rate Service (0x180D), Characteristic Heart Rate Measurement (0x2A37).
/// Polar H9/H10 senden darüber Puls und RR-Intervalle.
public enum HeartRateProfile {
    public static let service = "180D"
    public static let measurement = "2A37"
    public static let bodySensorLocation = "2A38"
    public static let batteryService = "180F"
    public static let batteryLevel = "2A19"
}

public struct HeartRateMeasurement: Equatable, Sendable {
    public var bpm: Int
    /// nil = Gurt meldet keinen Kontaktstatus
    public var sensorContact: Bool?
    public var energyExpended: Int?           // kJ
    /// RR-Intervalle in Sekunden (Auflösung 1/1024 s)
    public var rrIntervals: [Double]
}

public enum HeartRateParser {
    public static func parse(_ b: [UInt8]) -> HeartRateMeasurement? {
        guard b.count >= 2 else { return nil }
        let flags = b[0]
        var i = 1
        let bpm: Int
        if flags & 0x01 != 0 {
            guard b.count >= 3 else { return nil }
            bpm = Int(UInt16(b[1]) | UInt16(b[2]) << 8); i = 3
        } else {
            bpm = Int(b[1]); i = 2
        }
        let contactSupported = flags & 0x04 != 0
        let contact: Bool? = contactSupported ? (flags & 0x02 != 0) : nil
        var energy: Int?
        if flags & 0x08 != 0, b.count >= i + 2 {
            energy = Int(UInt16(b[i]) | UInt16(b[i + 1]) << 8); i += 2
        }
        var rr: [Double] = []
        if flags & 0x10 != 0 {
            while i + 1 < b.count {
                rr.append(Double(UInt16(b[i]) | UInt16(b[i + 1]) << 8) / 1024); i += 2
            }
        }
        return HeartRateMeasurement(bpm: bpm, sensorContact: contact, energyExpended: energy, rrIntervals: rr)
    }
}
