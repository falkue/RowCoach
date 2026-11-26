import Foundation

// Konfliktregeln und Buchführung der Synchronisation (docs/SYNC.md, „Konflikte“):
// - Fahrten: angehängt, entdoppelt nach id; der Inhalt ist unveränderlich.
// - Belastung einer Fahrt: neuester Zeitstempel gewinnt (HLC).
// - Löschung: Tombstone gewinnt immer (eine gelöschte Fahrt kommt nie zurück).
// - Einstellungen: je Feld neuester Zeitstempel; ein entferntes Feld ist ein Wert nil mit Zeitstempel.

public enum SyncMerge {
    /// Neuerer von zwei optionalen Zeitstempeln (nil verliert)
    static func newer(_ a: HybridTimestamp?, than b: HybridTimestamp?) -> Bool {
        guard let a else { return false }
        guard let b else { return true }
        return a > b
    }

    /// Zwei Stände derselben Fahrt zusammenführen
    public static func mergeRide(_ a: SyncRide, _ b: SyncRide) -> SyncRide {
        precondition(a.id == b.id, "verschiedene Fahrten")
        if a.isTombstone || b.isTombstone {
            // frühester Löschzeitpunkt, damit alle Geräte denselben Tombstone haben
            let clocks = [a.deletedClock, b.deletedClock].compactMap { $0 }
            return .tombstone(id: a.id, clock: clocks.min() ?? .initial(node: "x"))
        }
        var base = a
        if newer(b.effortClock, than: a.effortClock) {
            base.record?.effort = b.record?.effort
            base.effortClock = b.effortClock
        }
        return base
    }

    /// Ein Einstellungsfeld: neuerer Zeitstempel gewinnt
    public static func mergeField(_ a: SettingField?, _ b: SettingField?) -> SettingField? {
        guard let a else { return b }
        guard let b else { return a }
        return b.clock > a.clock ? b : a
    }

    /// Zwei Einstellungsdokumente feldweise zusammenführen (kommutativ, assoziativ, idempotent)
    public static func mergeSettings(_ a: SettingsDocument, _ b: SettingsDocument) -> SettingsDocument {
        var out = a
        for (name, field) in b.fields {
            out.fields[name] = mergeField(a.fields[name], field)
        }
        return out
    }
}

/// Was ein Gerät über den Abgleich mit einem Konto weiss (eine Datei je Konto). Daraus ergibt sich, was neu,
/// geändert oder gelöscht ist, ohne die Datenbank der App umzubauen.
public struct SyncLedger: Codable, Equatable, Sendable {
    public struct RideEntry: Codable, Equatable, Sendable {
        public var effortSignature: String
        public var effortClock: HybridTimestamp?
        /// liegt die Fahrt (oder ihr Tombstone) auf dem Server?
        public var onServer: Bool
        public var effortDirty: Bool
        public var deletedClock: HybridTimestamp?
        public var tombstonePending: Bool

        public init(effortSignature: String, effortClock: HybridTimestamp?, onServer: Bool, effortDirty: Bool = false,
                    deletedClock: HybridTimestamp? = nil, tombstonePending: Bool = false) {
            self.effortSignature = effortSignature
            self.effortClock = effortClock
            self.onServer = onServer
            self.effortDirty = effortDirty
            self.deletedClock = deletedClock
            self.tombstonePending = tombstonePending
        }
    }

    public struct SettingEntry: Codable, Equatable, Sendable {
        public var value: String?
        public var clock: HybridTimestamp
        public var dirty: Bool

        public init(value: String?, clock: HybridTimestamp, dirty: Bool) {
            self.value = value
            self.clock = clock
            self.dirty = dirty
        }
    }

    public var formatVersion = 1
    public var uid: String
    public var clock: HybridLogicalClock
    /// Schlüssel: UUID-Text der Fahrt
    public var rides: [String: RideEntry] = [:]
    /// Schlüssel: „doc/feld“
    public var settings: [String: SettingEntry] = [:]
    /// Serverzeit der zuletzt gelesenen Fahrtänderung
    public var rideCursor: Date?
    public var lastSync: Date?
    /// false bis zur ersten Beobachtung: vorhandene Werte gelten dann als „Erststand“ (verlieren gegen den Server)
    public var initialized = false

    public init(uid: String, node: String) {
        self.uid = uid
        clock = HybridLogicalClock(node: node)
    }

    /// Lokale Fahrten mit dem bekannten Stand vergleichen: neue merken, geänderte Belastung und Löschungen stempeln
    public mutating func observe(rides local: [LocalRideInfo], now: Date) {
        var present = Set<String>()
        for info in local where info.syncable {
            let key = info.id.uuidString
            present.insert(key)
            guard var e = rides[key] else {
                let hasEffort = info.effortSignature != LocalRideInfo.signature(nil)
                let clock: HybridTimestamp? = hasEffort ? (initialized ? self.clock.tick(now: now) : .initial(node: self.clock.node)) : nil
                rides[key] = RideEntry(effortSignature: info.effortSignature, effortClock: clock, onServer: false)
                continue
            }
            guard e.deletedClock == nil else { continue }
            if e.effortSignature != info.effortSignature {
                e.effortSignature = info.effortSignature
                e.effortClock = clock.tick(now: now)
                e.effortDirty = e.onServer
                rides[key] = e
            }
        }
        for (key, var e) in rides where e.deletedClock == nil && !present.contains(key) {
            if e.onServer {
                e.deletedClock = clock.tick(now: now)
                e.tombstonePending = true
                e.effortDirty = false
                rides[key] = e
            } else {
                // nie hochgeladen: auf keinem anderen Gerät vorhanden, einfach vergessen
                rides[key] = nil
            }
        }
    }

    /// Lokale Einstellungswerte vergleichen und Änderungen stempeln
    public mutating func observe(settings local: [String: String?], now: Date) {
        for (path, value) in local.sorted(by: { $0.key < $1.key }) {
            guard SyncSettingsCatalog.key(path: path) != nil else { continue }
            if var e = settings[path] {
                if e.value != value {
                    e.value = value
                    e.clock = clock.tick(now: now)
                    e.dirty = true
                    settings[path] = e
                }
            } else if let value {
                let c = initialized ? clock.tick(now: now) : HybridTimestamp.initial(node: clock.node)
                settings[path] = SettingEntry(value: value, clock: c, dirty: true)
            }
        }
    }

    /// Fahrten, die noch hochgeladen werden müssen (für die Anzeige „n ausstehend“)
    public var pendingRideCount: Int {
        rides.values.filter { $0.tombstonePending || $0.effortDirty || (!$0.onServer && $0.deletedClock == nil) }.count
    }

    public var pendingSettingCount: Int { settings.values.filter(\.dirty).count }
}
