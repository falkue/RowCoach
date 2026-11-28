import Foundation

/// Körpergewicht aus einem Gesundheitsspeicher (Apple Health, später Health Connect) ins Profil übernehmen –
/// ohne Endlosschleife zwischen synchronisierten Geräten (docs/HEALTH.md, Abschnitt Körpergewicht).
///
/// Regel: Jedes Gerät merkt sich lokal, seit wann der aktuelle Profilwert gilt (`asOf`). Ein Health-Wert wird nur
/// übernommen, wenn seine Messung **neuer** ist als `asOf`.
/// - Übernahme aus Health: `asOf` = Messzeit.
/// - Eingabe von Hand: `asOf` = jetzt.
/// - Wert von einem anderen Gerät (Synchronisation; erkannt daran, dass der Profilwert nicht mehr dem zuletzt
///   gesehenen entspricht): `asOf` = jetzt. Eine ältere Messung dieses Geräts überschreibt ihn also nicht; erst
///   eine neue Wägung tut das. Weil jede Übernahme eine neuere Messung braucht, endet jedes Hin und Her.
public enum BodyWeightRule {
    /// Plausible Messwerte (kg); andere werden ignoriert
    public static let plausibleKg: ClosedRange<Double> = 30...250
    /// Ab dieser Abweichung bietet die App den Health-Wert an, wenn die Übernahme aus ist
    public static let offerDifferenceKg = 0.5

    /// Eine Messung aus dem Gesundheitsspeicher
    public struct Reading: Equatable, Sendable {
        public var kg: Double
        public var date: Date
        /// Name der Quelle (Waage, App), nur zur Anzeige
        public var source: String

        public init(kg: Double, date: Date, source: String) {
            self.kg = kg
            self.date = date
            self.source = source
        }

        /// auf 0,1 kg gerundet (so zeigt und speichert die App das Gewicht)
        public var roundedKg: Double { (kg * 10).rounded() / 10 }
    }

    /// Lokaler Stand je Gerät (nicht synchronisiert)
    public struct Tracking: Equatable, Sendable {
        /// seit wann der aktuelle Profilwert gilt; nil = unbekannt (älter als jede Messung)
        public var asOf: Date?
        /// zuletzt gesehener Profilwert; nil = noch nie gesehen
        public var seen: Double?

        public init(asOf: Date? = nil, seen: Double? = nil) {
            self.asOf = asOf
            self.seen = seen
        }
    }

    public enum Action: Equatable, Sendable {
        case none
        /// Profilwert auf diesen Wert setzen (Übernahme an)
        case apply(Double)
        /// dezent anbieten (Übernahme aus)
        case offer(Double)
    }

    /// Profilwert prüfen: anders als zuletzt gesehen → von aussen geändert (Synchronisation), gilt ab `now`.
    /// Beim ersten Mal ist das Alter unbekannt (`asOf` bleibt).
    public static func observe(current: Double, tracking: Tracking, now: Date) -> Tracking {
        var t = tracking
        guard let seen = t.seen else {
            t.seen = current
            return t
        }
        if abs(seen - current) > 0.001 {
            t.asOf = now
            t.seen = current
        }
        return t
    }

    /// Was mit einer Messung zu tun ist. `force`: Übernahme gerade eingeschaltet (neueste Messung gilt sofort).
    public static func action(current: Double, reading: Reading?, fromHealth: Bool, tracking: Tracking,
                              force: Bool = false) -> Action {
        guard let r = reading, r.kg.isFinite, plausibleKg.contains(r.kg) else { return .none }
        let newer = force || tracking.asOf.map { r.date > $0 } ?? true
        guard newer else { return .none }
        let kg = r.roundedKg
        if fromHealth { return .apply(kg) }
        return abs(kg - current) >= offerDifferenceKg - 1e-9 ? .offer(kg) : .none
    }

    /// Stand nach einer Übernahme aus Health
    public static func applied(_ r: Reading) -> Tracking {
        Tracking(asOf: r.date, seen: r.roundedKg)
    }

    /// Stand nach einer Eingabe von Hand
    public static func manual(_ kg: Double, now: Date) -> Tracking {
        Tracking(asOf: now, seen: kg)
    }
}
