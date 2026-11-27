import Foundation

// Datenmodell der Synchronisation (Online-Funktion a, docs/SYNC.md). Nur Foundation, damit iOS und Android
// dieselben Modelle, dieselbe Merge-Logik und dieselbe Serverform benutzen.
//
// Server (Firestore): users/{uid}/rides/{rideId} (Fahrten, unveränderlich bis auf die Belastung, Löschung als
// Tombstone), users/{uid}/rides/{rideId}/chunks/{i} (nur sehr lange Fahrten), users/{uid}/settings/{doc}
// (feldweise mit HLC-Zeitstempel), users/{uid}/consent/{research|sync} + consentLog, users/{uid}/entitlements/{id}
// (nur der Server schreibt).

public enum SyncSchema {
    /// Version der Serverform; neue optionale Felder erhöhen sie nicht, Formänderungen schon
    public static let version = 1
    /// Höchstgrösse der Binärdaten einer Fahrt im Hauptdokument (Firestore: 1 MiB je Dokument inkl. Feldnamen)
    public static let inlineBlobBudget = 700_000
    /// Grösse eines Zusatzstücks (users/{uid}/rides/{id}/chunks/{i})
    public static let chunkSize = 700_000
    /// Höchstens so viele Zusatzstücke; darüber wird die Zeitreihe ausgedünnt
    public static let maxChunks = 8
    /// Höchstgrösse der Fahrtdaten ohne Zeitreihe (JSON)
    public static let maxRecordJSONBytes = 200_000
    /// Höchstgrösse eines Einstellungswerts (JSON-Text)
    public static let maxSettingValueBytes = 16_000
}

// MARK: Fahrten

/// Eine Fahrt aus Sicht der Synchronisation: das Training (nil = gelöscht) und die Zeitstempel der veränderlichen
/// Teile. Die Fahrt selbst ist unveränderlich; nur die Belastung (`record.effort`) kann sich später ändern
/// (eigene Einschätzung nach der Fahrt), und eine Löschung ist endgültig (Tombstone gewinnt immer).
public struct SyncRide: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var record: WorkoutRecord?
    /// Zeitstempel der Belastung (nil = nie gesetzt, verliert gegen jeden Zeitstempel)
    public var effortClock: HybridTimestamp?
    /// gesetzt = gelöscht (Tombstone)
    public var deletedClock: HybridTimestamp?

    public init(record: WorkoutRecord, effortClock: HybridTimestamp?) {
        id = record.id
        self.record = record
        self.effortClock = effortClock
        deletedClock = nil
    }

    public static func tombstone(id: UUID, clock: HybridTimestamp) -> SyncRide {
        SyncRide(id: id, record: nil, effortClock: nil, deletedClock: clock)
    }

    init(id: UUID, record: WorkoutRecord?, effortClock: HybridTimestamp?, deletedClock: HybridTimestamp?) {
        self.id = id
        self.record = record
        self.effortClock = effortClock
        self.deletedClock = deletedClock
    }

    public var isTombstone: Bool { deletedClock != nil || record == nil }
    public var effort: WorkoutEffort? { record?.effort }
}

/// Eine Änderung, die ein Gerät an den Server schickt
public enum RideChange: Equatable, Sendable {
    /// neue Fahrt (vollständig)
    case create(SyncRide)
    /// nur die Belastung (Server übernimmt sie nur, wenn `clock` neuer ist)
    case effort(id: UUID, effort: WorkoutEffort?, clock: HybridTimestamp)
    /// Löschung: der Server ersetzt die Fahrt durch einen Tombstone ohne Trainingsdaten
    case tombstone(id: UUID, clock: HybridTimestamp)

    public var rideId: UUID {
        switch self {
        case .create(let r): return r.id
        case .effort(let id, _, _), .tombstone(let id, _): return id
        }
    }
}

/// Eine Seite geänderter Fahrten vom Server (aufsteigend nach Serverzeit)
public struct RidePage: Sendable {
    public var rides: [SyncRide]
    /// Serverzeit der letzten Fahrt auf der Seite (für die nächste Abfrage)
    public var cursor: Date?
    public var hasMore: Bool

    public init(rides: [SyncRide], cursor: Date?, hasMore: Bool) {
        self.rides = rides
        self.cursor = cursor
        self.hasMore = hasMore
    }
}

/// Die Fahrt so, wie sie im Firestore-Dokument steht (Feldnamen siehe `Field`). Unabhängig vom Firebase-SDK,
/// damit Grössenbudget, Stückelung und Versionierung im Kit getestet werden.
public struct RideWire: Equatable, Sendable {
    public enum Field {
        public static let schema = "v", id = "id", start = "start", distance = "distance"
        public static let activeDuration = "activeDuration", record = "record", blob = "samples"
        public static let codec = "codec", chunkCount = "chunkCount", effort = "effort"
        public static let effortClock = "effortClock", deleted = "deleted", deletedClock = "deletedClock"
        public static let updatedAt = "updatedAt", thinned = "thinned"
        /// Felder eines Zusatzstücks
        public static let chunkIndex = "i", chunkData = "data"
    }

    public var schemaVersion: Int
    public var id: String
    public var startDate: Date?
    public var distance: Double?
    public var activeDuration: Double?
    /// `WorkoutRecord` als JSON ohne Zeitreihe, RR und Belastung
    public var recordJSON: String?
    /// `SampleCodec` (Zeitreihe und RR); nil, wenn die Daten in `chunks` liegen
    public var blob: Data?
    public var codec: Int?
    /// Zusatzstücke (aneinandergehängt = Blob); leer bei normaler Grösse
    public var chunks: [Data]
    /// Ausdünnungsschritt, falls die Zeitreihe gekürzt werden musste (1 = vollständig)
    public var thinned: Int?
    /// `WorkoutEffort` als JSON
    public var effortJSON: String?
    public var effortClock: String?
    public var deleted: Bool
    public var deletedClock: String?
    /// vom Server gesetzt (Firestore: request.time)
    public var updatedAt: Date?

    public init(schemaVersion: Int = SyncSchema.version, id: String, startDate: Date? = nil, distance: Double? = nil,
                activeDuration: Double? = nil, recordJSON: String? = nil, blob: Data? = nil, codec: Int? = nil,
                chunks: [Data] = [], thinned: Int? = nil, effortJSON: String? = nil, effortClock: String? = nil,
                deleted: Bool = false, deletedClock: String? = nil, updatedAt: Date? = nil) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.startDate = startDate
        self.distance = distance
        self.activeDuration = activeDuration
        self.recordJSON = recordJSON
        self.blob = blob
        self.codec = codec
        self.chunks = chunks
        self.thinned = thinned
        self.effortJSON = effortJSON
        self.effortClock = effortClock
        self.deleted = deleted
        self.deletedClock = deletedClock
        self.updatedAt = updatedAt
    }

    /// Ungefähre Grösse des Hauptdokuments in Byte (Firestore zählt Feldnamen und Werte)
    public var approximateDocumentBytes: Int {
        200 + (recordJSON?.utf8.count ?? 0) + (blob?.count ?? 0) + (effortJSON?.utf8.count ?? 0)
    }
}

public enum RideWireCodec {
    public enum WireError: Error, Equatable {
        case badId, newerSchema(Int), missingRecord, recordTooLarge, badClock, blob(SampleCodec.CodecError)
    }

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }

    /// Fahrt → Serverform; stückelt grosse Zeitreihen und dünnt sie nur im Notfall aus
    public static func encode(_ ride: SyncRide) throws -> RideWire {
        let id = ride.id.uuidString
        guard let record = ride.record, ride.deletedClock == nil else {
            return RideWire(id: id, deleted: true, deletedClock: (ride.deletedClock ?? .initial(node: "x")).encoded)
        }
        var core = record
        core.samples = []
        core.rrIntervals = nil
        core.effort = nil
        let json = String(decoding: try encoder().encode(core), as: UTF8.self)
        guard json.utf8.count <= SyncSchema.maxRecordJSONBytes else { throw WireError.recordTooLarge }
        var step = 1
        var blob = SampleCodec.encode(samples: record.samples, rr: record.rrIntervals)
        while blob.count > SyncSchema.chunkSize * SyncSchema.maxChunks {
            step *= 2
            blob = SampleCodec.encode(samples: SampleCodec.thinned(record.samples, step: step),
                                      rr: step > 4 ? nil : record.rrIntervals)
        }
        var wire = RideWire(id: id, startDate: record.header.startDate, distance: record.summary.distance,
                            activeDuration: record.summary.activeDuration, recordJSON: json,
                            codec: Int(SampleCodec.formatVersion), thinned: step > 1 ? step : nil)
        if blob.count <= SyncSchema.inlineBlobBudget {
            wire.blob = blob
        } else {
            var chunks = [Data]()
            var start = blob.startIndex
            while start < blob.endIndex {
                let end = blob.index(start, offsetBy: SyncSchema.chunkSize, limitedBy: blob.endIndex) ?? blob.endIndex
                chunks.append(Data(blob[start..<end]))
                start = end
            }
            wire.chunks = chunks
        }
        if let effort = record.effort {
            wire.effortJSON = String(decoding: try encoder().encode(effort), as: UTF8.self)
        }
        wire.effortClock = ride.effortClock?.encoded
        return wire
    }

    /// Serverform → Fahrt. Neuere Schemaversionen werden abgelehnt (die App bittet dann um ein Update),
    /// unbekannte Felder im JSON übergeht `WorkoutRecord` ohnehin.
    public static func decode(_ wire: RideWire) throws -> SyncRide {
        guard let id = UUID(uuidString: wire.id) else { throw WireError.badId }
        guard wire.schemaVersion <= SyncSchema.version else { throw WireError.newerSchema(wire.schemaVersion) }
        if wire.deleted {
            guard let s = wire.deletedClock, let clock = HybridTimestamp(encoded: s) else { throw WireError.badClock }
            return .tombstone(id: id, clock: clock)
        }
        guard let json = wire.recordJSON else { throw WireError.missingRecord }
        var record = try decoder().decode(WorkoutRecord.self, from: Data(json.utf8))
        record.id = id
        let blob = wire.blob ?? wire.chunks.reduce(into: Data()) { $0.append($1) }
        if !blob.isEmpty {
            do {
                let decoded = try SampleCodec.decode(blob)
                record.samples = decoded.samples
                record.rrIntervals = decoded.rr
            } catch let e as SampleCodec.CodecError {
                throw WireError.blob(e)
            }
        }
        if let e = wire.effortJSON { record.effort = try? decoder().decode(WorkoutEffort.self, from: Data(e.utf8)) }
        var clock: HybridTimestamp?
        if let s = wire.effortClock {
            guard let c = HybridTimestamp(encoded: s) else { throw WireError.badClock }
            clock = c
        }
        return SyncRide(record: record, effortClock: clock)
    }

    /// Belastung als JSON (für `RideChange.effort`)
    public static func effortJSON(_ effort: WorkoutEffort?) -> String? {
        guard let effort, let data = try? encoder().encode(effort) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: Einstellungen

/// Ein Einstellungswert mit Zeitstempel. `value` ist kanonisches JSON („185“, „true“, „"cox"“, Objekt);
/// nil = auf dem Gerät entfernt (Tombstone des Felds, z. B. Trainingsplan beendet).
public struct SettingField: Codable, Equatable, Sendable {
    public var value: String?
    public var clock: HybridTimestamp

    public init(value: String?, clock: HybridTimestamp) {
        self.value = value
        self.clock = clock
    }

    enum CodingKeys: String, CodingKey { case value = "v", clock = "c" }
}

/// Ein Einstellungsdokument (users/{uid}/settings/{doc}): Feldname → Wert mit Zeitstempel
public struct SettingsDocument: Codable, Equatable, Sendable {
    public var fields: [String: SettingField]

    public init(fields: [String: SettingField] = [:]) {
        self.fields = fields
    }
}

/// Welche lokalen Einstellungen synchronisiert werden und wo sie auf dem Server liegen. Die lokalen Schlüssel
/// sind die der iOS-App (UserDefaults); Android benutzt dieselben Namen.
public struct SyncSettingKey: Equatable, Hashable, Sendable {
    public enum Kind: String, Sendable { case int, double, bool, string, json }

    public var localKey: String
    public var document: String
    public var field: String
    public var kind: Kind

    public init(_ localKey: String, _ document: String, _ field: String, _ kind: Kind) {
        self.localKey = localKey
        self.document = document
        self.field = field
        self.kind = kind
    }

    /// „profile/maxHR“
    public var path: String { document + "/" + field }
}

public enum SyncSettingsCatalog {
    public static let profile = "profile", program = "program", motivation = "motivation"
    public static let documents = [profile, program, motivation]

    /// Synchronisiert: Profil (Figur, Anzeigename, Nationalität – ohne Geschlecht), Puls, Bestzeit und Schwellenprofil,
    /// Trainingsplan-Zustand, Motivations-Einstellungen. Gerätebezogenes (gekoppelte Geräte, Erinnerungsprotokoll,
    /// Darstellung, Strecken-Server) bleibt lokal.
    public static let keys: [SyncSettingKey] = [
        SyncSettingKey(RowerProfile.storageKey, profile, "rower", .json),
        SyncSettingKey("profile.maxHR", profile, "maxHR", .int),
        SyncSettingKey("profile.restHR", profile, "restHR", .int),
        SyncSettingKey("profile.best2k", profile, "best2k", .double),
        SyncSettingKey("profile.weightKg", profile, "weightKg", .double),
        // Schwellenprofil (docs/schwelle/SPEC.md; gekürzt auf die Feldgrenze, siehe ThresholdProfile.encodedForSync)
        SyncSettingKey("threshold.profile.v1", profile, "threshold", .json),
        SyncSettingKey("trainingProgram.active", program, "active", .json),
        SyncSettingKey("home.weeklyGoal", motivation, "weeklyGoal", .int),
        SyncSettingKey("motivation.successLines", motivation, "successLines", .bool),
        SyncSettingKey("motivation.milestones", motivation, "milestones", .bool),
        SyncSettingKey("motivation.goalKind", motivation, "goalKind", .string),
        SyncSettingKey("motivation.goalMinutes", motivation, "goalMinutes", .int),
        SyncSettingKey("motivation.goalSince", motivation, "goalSince", .double),
        SyncSettingKey("motivation.goalReviewDismissed", motivation, "goalReviewDismissed", .double),
        SyncSettingKey("motivation.pauses", motivation, "pauses", .json),
        SyncSettingKey("motivation.intention", motivation, "intention", .json),
    ]

    public static func key(path: String) -> SyncSettingKey? { keys.first { $0.path == path } }

    /// Feldnamen je Dokument (auch für die Firestore-Regeln, firebase/firestore.rules)
    public static func fields(of document: String) -> [String] {
        keys.filter { $0.document == document }.map(\.field)
    }
}

// MARK: Einwilligung, Berechtigungen, Export

/// Einwilligungen (eigene Dokumente users/{uid}/consent/{kind}, dazu ein Protokoll consentLog)
public enum ConsentKind: String, Codable, CaseIterable, Sendable {
    /// Forschung: anonymisierte/aggregierte Auswertung der Trainingsdaten (Standard aus, jederzeit widerrufbar)
    case research
    /// Synchronisation: Speicherung der Trainingsdaten inkl. Puls auf dem Server (DSGVO Art. 9 Abs. 2 lit. a)
    case sync
}

public struct ConsentRecord: Codable, Equatable, Sendable {
    public var kind: ConsentKind
    public var granted: Bool
    /// Fassung des angezeigten Einwilligungstexts (z. B. "research-2026-11")
    public var textVersion: String
    /// Sprache des angezeigten Texts ("de", "en")
    public var locale: String
    /// Zeitpunkt auf dem Gerät; der Server speichert zusätzlich seine eigene Zeit (`at`)
    public var decidedAt: Date

    public init(kind: ConsentKind, granted: Bool, textVersion: String, locale: String, decidedAt: Date) {
        self.kind = kind
        self.granted = granted
        self.textVersion = textVersion
        self.locale = locale
        self.decidedAt = decidedAt
    }
}

/// Kostenpflichtige Berechtigungen (users/{uid}/entitlements/{id}); schreibt nur der Server nach Belegprüfung
public enum Entitlement: String, Codable, CaseIterable, Sendable {
    /// Rennen-Abo (später; StoreKit 2 / Play Billing)
    case races
}

public struct EntitlementStatus: Codable, Equatable, Sendable {
    public var entitlement: Entitlement
    public var active: Bool
    public var expiresAt: Date?
    /// "appStore", "playStore", "promo"
    public var source: String?
    public var productId: String?

    public init(entitlement: Entitlement, active: Bool, expiresAt: Date? = nil, source: String? = nil,
                productId: String? = nil) {
        self.entitlement = entitlement
        self.active = active
        self.expiresAt = expiresAt
        self.source = source
        self.productId = productId
    }

    public static func inactive(_ e: Entitlement) -> EntitlementStatus { EntitlementStatus(entitlement: e, active: false) }

    public func isActive(at date: Date) -> Bool { active && (expiresAt.map { $0 > date } ?? true) }
}

/// Alle Server-Daten eines Kontos (Export, DSGVO Art. 15/20)
public struct SyncExport: Codable, Equatable, Sendable {
    public var formatVersion: Int
    public var exportedAt: Date
    public var uid: String
    public var rides: [SyncRide]
    public var settings: [String: SettingsDocument]
    public var consents: [ConsentRecord]
    public var entitlements: [EntitlementStatus]

    public init(exportedAt: Date, uid: String, rides: [SyncRide], settings: [String: SettingsDocument],
                consents: [ConsentRecord], entitlements: [EntitlementStatus]) {
        formatVersion = 1
        self.exportedAt = exportedAt
        self.uid = uid
        self.rides = rides
        self.settings = settings
        self.consents = consents
        self.entitlements = entitlements
    }

    /// Lesbares JSON (ISO-8601-Daten, sortierte Schlüssel)
    public func jsonData() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return try e.encode(self)
    }
}
