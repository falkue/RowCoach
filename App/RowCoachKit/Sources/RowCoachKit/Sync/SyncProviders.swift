import Foundation

// Schmale Schnittstellen der Online-Module (docs/SYNC.md, „Schnittstellen“). Die App arbeitet standardmässig mit
// den No-op-Umsetzungen: kein Konto, keine Netzanfrage. Die Firebase-Umsetzungen liegen in der iOS-Hülle
// (App/RowCoach/Sync), die In-Memory-Umsetzungen dienen den Tests und als Muster für Android.

public enum SyncError: Error, Equatable, Sendable {
    /// kein Konto / nicht angemeldet
    case notSignedIn
    /// Online-Funktion nicht verfügbar (No-op, Firebase nicht eingerichtet)
    case unavailable
    case invalidCredentials
    case emailInUse
    case weakPassword
    case emailNotVerified
    /// Server hat neuere Daten als diese App versteht
    case needsAppUpdate
    case network(String)
    case server(String)
}

// MARK: Konto

public struct SyncUser: Equatable, Sendable {
    public var uid: String
    public var email: String?
    public var emailVerified: Bool
    /// "password", "google.com", "apple.com"
    public var providers: [String]

    public init(uid: String, email: String?, emailVerified: Bool, providers: [String]) {
        self.uid = uid
        self.email = email
        self.emailVerified = emailVerified
        self.providers = providers
    }

    /// Darf schreiben: bestätigte E-Mail oder Anmeldung über Google/Apple (dieselbe Regel wie firestore.rules)
    public var canWrite: Bool { emailVerified || providers.contains { $0 != "password" } }
}

/// Anmeldung. Google und Apple brauchen eine Oberfläche der Plattform und hängen deshalb an der Hülle; hier nur
/// das Gemeinsame.
public protocol AuthProvider: AnyObject {
    func currentUser() async -> SyncUser?
    func signIn(email: String, password: String) async throws -> SyncUser
    func register(email: String, password: String) async throws -> SyncUser
    func sendEmailVerification() async throws
    func sendPasswordReset(email: String) async throws
    /// Stand vom Server neu holen (z. B. nach dem Klick auf den Bestätigungslink)
    func reload() async throws -> SyncUser?
    func signOut() async throws
    /// Konto beim Anmeldedienst löschen (vorher `SyncBackend.deleteAllUserData`)
    func deleteAccount() async throws
}

/// Kein Konto: niemand ist angemeldet, alles andere meldet `unavailable`. Keine Netzanfrage.
public final class NoopAuthProvider: AuthProvider {
    public init() {}
    public func currentUser() async -> SyncUser? { nil }
    public func signIn(email: String, password: String) async throws -> SyncUser { throw SyncError.unavailable }
    public func register(email: String, password: String) async throws -> SyncUser { throw SyncError.unavailable }
    public func sendEmailVerification() async throws { throw SyncError.unavailable }
    public func sendPasswordReset(email: String) async throws { throw SyncError.unavailable }
    public func reload() async throws -> SyncUser? { nil }
    public func signOut() async throws {}
    public func deleteAccount() async throws { throw SyncError.unavailable }
}

/// Konten im Arbeitsspeicher (Tests). Neue Konten mit Passwort sind unbestätigt, bis `verify(email:)` läuft.
public final class InMemoryAuthProvider: AuthProvider {
    private struct Account { var user: SyncUser; var password: String }
    private var accounts: [String: Account] = [:]
    private var current: String?
    public private(set) var sentVerifications: [String] = []
    public private(set) var sentResets: [String] = []

    public init() {}

    /// Direkt angemeldetes Konto (z. B. Google)
    public init(signedIn user: SyncUser) {
        accounts[user.email ?? user.uid] = Account(user: user, password: "")
        current = user.email ?? user.uid
    }

    public func currentUser() async -> SyncUser? { current.flatMap { accounts[$0]?.user } }

    public func signIn(email: String, password: String) async throws -> SyncUser {
        guard let a = accounts[email.lowercased()], a.password == password else { throw SyncError.invalidCredentials }
        current = email.lowercased()
        return a.user
    }

    public func register(email: String, password: String) async throws -> SyncUser {
        let key = email.lowercased()
        guard accounts[key] == nil else { throw SyncError.emailInUse }
        guard password.count >= 6 else { throw SyncError.weakPassword }
        let user = SyncUser(uid: "u\(accounts.count + 1)", email: key, emailVerified: false, providers: ["password"])
        accounts[key] = Account(user: user, password: password)
        current = key
        return user
    }

    public func sendEmailVerification() async throws {
        guard let c = current else { throw SyncError.notSignedIn }
        sentVerifications.append(c)
    }

    public func sendPasswordReset(email: String) async throws { sentResets.append(email.lowercased()) }

    public func verify(email: String) { accounts[email.lowercased()]?.user.emailVerified = true }

    public func reload() async throws -> SyncUser? { await currentUser() }

    public func signOut() async throws { current = nil }

    public func deleteAccount() async throws {
        guard let c = current else { throw SyncError.notSignedIn }
        accounts[c] = nil
        current = nil
    }
}

// MARK: Server

/// Server der Synchronisation. Eine Instanz gehört zu genau einem angemeldeten Konto.
public protocol SyncBackend: AnyObject {
    /// Fahrten, die sich seit `cursor` (Serverzeit) geändert haben, aufsteigend; nil = alle
    func fetchRides(since cursor: Date?, limit: Int) async throws -> RidePage
    /// Änderungen anwenden. Der Server legt neue Fahrten an (vorhandene bleiben unverändert), übernimmt eine
    /// Belastung nur mit neuerem Zeitstempel und ersetzt gelöschte Fahrten durch Tombstones.
    func push(_ changes: [RideChange]) async throws
    func fetchSettings() async throws -> [String: SettingsDocument]
    /// Felder zusammenführen: je Feld gewinnt der neuere Zeitstempel (auf dem Server, in einer Transaktion)
    func pushSettings(_ documents: [String: SettingsDocument]) async throws
    func fetchConsents() async throws -> [ConsentRecord]
    /// aktuellen Stand setzen und im Protokoll anhängen
    func pushConsent(_ consent: ConsentRecord) async throws
    func exportAll() async throws -> SyncExport
    /// alle Daten des Kontos auf dem Server löschen (Fahrten, Stücke, Einstellungen, Einwilligungen)
    func deleteAllUserData() async throws
}

/// Kein Server: jede Anfrage meldet `unavailable`, es geht nichts hinaus.
public final class NoopSyncBackend: SyncBackend {
    public init() {}
    public func fetchRides(since cursor: Date?, limit: Int) async throws -> RidePage { throw SyncError.unavailable }
    public func push(_ changes: [RideChange]) async throws { throw SyncError.unavailable }
    public func fetchSettings() async throws -> [String: SettingsDocument] { throw SyncError.unavailable }
    public func pushSettings(_ documents: [String: SettingsDocument]) async throws { throw SyncError.unavailable }
    public func fetchConsents() async throws -> [ConsentRecord] { throw SyncError.unavailable }
    public func pushConsent(_ consent: ConsentRecord) async throws { throw SyncError.unavailable }
    public func exportAll() async throws -> SyncExport { throw SyncError.unavailable }
    public func deleteAllUserData() async throws { throw SyncError.unavailable }
}

/// Server im Arbeitsspeicher mit denselben Regeln wie Firestore + firestore.rules (Tests, Muster für Android).
/// Mehrere Geräte teilen sich eine Instanz. Zählt jede Anfrage (`requestCount`).
public final class InMemorySyncBackend: SyncBackend {
    public let uid: String
    private var rides: [UUID: (wire: RideWire, serverTime: Date)] = [:]
    private var settings: [String: SettingsDocument] = [:]
    private var consents: [ConsentKind: ConsentRecord] = [:]
    public private(set) var consentLog: [ConsentRecord] = []
    public var entitlements: [EntitlementStatus] = []
    public private(set) var requestCount = 0
    /// Serverzeit; steigt bei jedem Schreibvorgang um 1 ms (eindeutiger Cursor)
    private var clock: Date
    /// Fehler für die nächste Anfrage (Test von Abbrüchen)
    public var failNext: SyncError?

    public init(uid: String = "u1", start: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
        self.uid = uid
        clock = start
    }

    private func request() throws {
        requestCount += 1
        if let e = failNext {
            failNext = nil
            throw e
        }
    }

    private func now() -> Date {
        clock = clock.addingTimeInterval(0.001)
        return clock
    }

    public var storedRideIds: Set<UUID> { Set(rides.keys) }
    public func storedWire(_ id: UUID) -> RideWire? { rides[id]?.wire }
    public func storedRide(_ id: UUID) -> SyncRide? { rides[id].flatMap { try? RideWireCodec.decode($0.wire) } }
    public var storedSettings: [String: SettingsDocument] { settings }

    public func fetchRides(since cursor: Date?, limit: Int) async throws -> RidePage {
        try request()
        let sorted = rides.values.filter { cursor == nil || $0.serverTime > cursor! }.sorted { $0.serverTime < $1.serverTime }
        let page = Array(sorted.prefix(limit))
        var out = [SyncRide]()
        for entry in page {
            do {
                out.append(try RideWireCodec.decode(entry.wire))
            } catch RideWireCodec.WireError.newerSchema {
                throw SyncError.needsAppUpdate
            }
        }
        return RidePage(rides: out, cursor: page.last?.serverTime ?? cursor, hasMore: sorted.count > page.count)
    }

    public func push(_ changes: [RideChange]) async throws {
        try request()
        for change in changes {
            switch change {
            case .create(let ride):
                // Fahrten sind unveränderlich: vorhandene (auch Tombstones) bleiben
                guard rides[ride.id] == nil else { continue }
                var wire = try RideWireCodec.encode(ride)
                wire.updatedAt = nil
                rides[ride.id] = (wire, now())
            case .effort(let id, let effort, let clock):
                guard var entry = rides[id], !entry.wire.deleted else { continue }
                if let old = entry.wire.effortClock.flatMap(HybridTimestamp.init(encoded:)), old >= clock { continue }
                entry.wire.effortJSON = RideWireCodec.effortJSON(effort)
                entry.wire.effortClock = clock.encoded
                entry.serverTime = now()
                rides[id] = entry
            case .tombstone(let id, let clock):
                if let entry = rides[id], entry.wire.deleted { continue }
                rides[id] = (RideWire(id: id.uuidString, deleted: true, deletedClock: clock.encoded), now())
            }
        }
    }

    public func fetchSettings() async throws -> [String: SettingsDocument] {
        try request()
        return settings
    }

    public func pushSettings(_ documents: [String: SettingsDocument]) async throws {
        try request()
        for (name, doc) in documents {
            settings[name] = SyncMerge.mergeSettings(settings[name] ?? SettingsDocument(), doc)
        }
    }

    public func fetchConsents() async throws -> [ConsentRecord] {
        try request()
        return ConsentKind.allCases.compactMap { consents[$0] }
    }

    public func pushConsent(_ consent: ConsentRecord) async throws {
        try request()
        consents[consent.kind] = consent
        consentLog.append(consent)
    }

    public func exportAll() async throws -> SyncExport {
        try request()
        let all = rides.values.sorted { $0.serverTime < $1.serverTime }.compactMap { try? RideWireCodec.decode($0.wire) }
        return SyncExport(exportedAt: clock, uid: uid, rides: all, settings: settings,
                          consents: ConsentKind.allCases.compactMap { consents[$0] }, entitlements: entitlements)
    }

    public func deleteAllUserData() async throws {
        try request()
        rides = [:]
        settings = [:]
        consents = [:]
        consentLog = []
        // Berechtigungen löscht nur der Server (Cloud Function bei Kontolöschung), wie in firestore.rules
    }
}

// MARK: Berechtigungen (Rennen-Abo, später)

/// Ob ein Konto eine kostenpflichtige Berechtigung hat. Heute nur Platzhalter: Kauf über StoreKit 2 / Play Billing,
/// Belegprüfung und Schreiben von users/{uid}/entitlements/{id} macht später der Server (docs/SYNC.md).
public protocol EntitlementProvider: AnyObject {
    func status(_ entitlement: Entitlement) async -> EntitlementStatus
}

public final class NoopEntitlementProvider: EntitlementProvider {
    public init() {}
    public func status(_ entitlement: Entitlement) async -> EntitlementStatus { .inactive(entitlement) }
}

public final class InMemoryEntitlementProvider: EntitlementProvider {
    public var statuses: [Entitlement: EntitlementStatus] = [:]
    public init() {}
    public func status(_ entitlement: Entitlement) async -> EntitlementStatus {
        statuses[entitlement] ?? .inactive(entitlement)
    }
}

// MARK: lokaler Speicher

/// Kurzer Stand einer lokal gespeicherten Fahrt (ohne Zeitreihe; die App liest ihn aus den Listenspalten)
public struct LocalRideInfo: Equatable, Sendable {
    public var id: UUID
    /// ändert sich, wenn sich die Belastung ändert (z. B. "7|8" aus Schätzung und eigener Angabe)
    public var effortSignature: String
    /// false = wird nicht synchronisiert (Beispielfahrten, Simulator im Release-Build)
    public var syncable: Bool

    public init(id: UUID, effortSignature: String, syncable: Bool = true) {
        self.id = id
        self.effortSignature = effortSignature
        self.syncable = syncable
    }

    public static func signature(_ effort: WorkoutEffort?) -> String {
        "\(effort?.estimate.map(String.init) ?? "-")|\(effort?.userScore.map(String.init) ?? "-")"
    }
}

/// Was die Synchronisation vom Gerät braucht. Die App setzt es über SwiftData und UserDefaults um.
public protocol SyncLocalStore: AnyObject {
    func rideIndex() async -> [LocalRideInfo]
    func ride(id: UUID) async -> WorkoutRecord?
    /// neue Fahrten vom Server einfügen, Belastungen ersetzen, gelöschte entfernen
    func apply(inserts: [WorkoutRecord], effortUpdates: [UUID: WorkoutEffort?], deletions: [UUID]) async
    /// aktuelle Werte der synchronisierten Einstellungen (Pfad „doc/feld“ → JSON, nil = nicht gesetzt)
    func settingValues() async -> [String: String?]
    func applySettings(_ values: [String: String?]) async
    func loadLedger(uid: String) async -> SyncLedger?
    func saveLedger(_ ledger: SyncLedger) async
    func deleteLedger(uid: String) async
}

/// Lokaler Speicher im Arbeitsspeicher (Tests): ein simuliertes Gerät
public final class InMemorySyncStore: SyncLocalStore {
    public var records: [UUID: WorkoutRecord] = [:]
    public var settings: [String: String] = [:]
    public var ledgers: [String: SyncLedger] = [:]
    public var unsyncable: Set<UUID> = []

    public init() {}

    public func rideIndex() async -> [LocalRideInfo] {
        records.values.map { LocalRideInfo(id: $0.id, effortSignature: LocalRideInfo.signature($0.effort),
                                           syncable: !unsyncable.contains($0.id)) }
    }

    public func ride(id: UUID) async -> WorkoutRecord? { records[id] }

    public func apply(inserts: [WorkoutRecord], effortUpdates: [UUID: WorkoutEffort?], deletions: [UUID]) async {
        for r in inserts where records[r.id] == nil { records[r.id] = r }
        for (id, effort) in effortUpdates { records[id]?.effort = effort }
        for id in deletions { records[id] = nil }
    }

    public func settingValues() async -> [String: String?] {
        var out = [String: String?]()
        for k in SyncSettingsCatalog.keys { out[k.path] = .some(settings[k.path]) }
        return out
    }

    public func applySettings(_ values: [String: String?]) async {
        for (path, v) in values { settings[path] = v }
    }

    public func loadLedger(uid: String) async -> SyncLedger? { ledgers[uid] }
    public func saveLedger(_ ledger: SyncLedger) async { ledgers[ledger.uid] = ledger }
    public func deleteLedger(uid: String) async { ledgers[uid] = nil }
}
