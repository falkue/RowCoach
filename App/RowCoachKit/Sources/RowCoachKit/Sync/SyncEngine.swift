import Foundation

/// Ablauf eines Abgleichs (docs/SYNC.md, „Sync-Engine“). Offline-first: die App arbeitet immer mit ihrem lokalen
/// Speicher; der Abgleich liest Änderungen vom Server, wendet sie lokal an und schickt danach die eigenen.
///
/// Grundregel: Ist die Synchronisation aus oder niemand angemeldet, stellt die Engine **keine einzige Anfrage**
/// an den Server (Test `SyncEngineTests.testNoAccountNoRequest`).
public actor SyncEngine {
    public struct Report: Equatable, Sendable {
        public var pulledRides = 0
        public var deletedLocally = 0
        public var updatedEfforts = 0
        public var pushedRides = 0
        public var pushedEfforts = 0
        public var pushedTombstones = 0
        public var appliedSettings = 0
        public var pushedSettings = 0
        public init() {}
    }

    public enum Outcome: Equatable, Sendable {
        /// Synchronisation ausgeschaltet
        case disabled
        /// kein Konto
        case signedOut
        /// E-Mail noch nicht bestätigt (der Server würde Schreibvorgänge ablehnen)
        case notVerified
        /// ein Abgleich läuft schon
        case busy
        case synced(Report)
        case failed(SyncError)
    }

    private let auth: AuthProvider
    private let backend: SyncBackend
    private let store: SyncLocalStore
    private let isEnabled: @Sendable () -> Bool
    private let node: String
    private var busy = false
    /// Fahrten je Anfrage beim Hochladen
    public static let pushBatch = 20
    public static let pageSize = 100

    /// - Parameters:
    ///   - isEnabled: Schalter „Synchronisation“ (Standard der App: aus)
    ///   - node: Geräte-Id für die HLC (einmal je Installation erzeugt und gespeichert)
    public init(auth: AuthProvider, backend: SyncBackend, store: SyncLocalStore, node: String,
                isEnabled: @escaping @Sendable () -> Bool) {
        self.auth = auth
        self.backend = backend
        self.store = store
        self.node = node
        self.isEnabled = isEnabled
    }

    /// Engine ohne Konto und ohne Server (Standard der App)
    public static func offline(store: SyncLocalStore) -> SyncEngine {
        SyncEngine(auth: NoopAuthProvider(), backend: NoopSyncBackend(), store: store, node: "offline",
                   isEnabled: { false })
    }

    private func signedInUser() async -> SyncUser? {
        guard isEnabled() else { return nil }
        return await auth.currentUser()
    }

    /// Lokale Änderungen sofort stempeln (ohne Netz), damit Konflikte nach dem Zeitpunkt der Änderung
    /// entschieden werden und nicht nach dem des nächsten Abgleichs. Ohne Konto passiert nichts.
    public func noteLocalChanges(now: Date = Date()) async {
        guard !busy, let user = await signedInUser() else { return }
        busy = true
        defer { busy = false }
        guard var ledger = await store.loadLedger(uid: user.uid), ledger.initialized else { return }
        ledger.observe(rides: await store.rideIndex(), now: now)
        ledger.observe(settings: await store.settingValues(), now: now)
        await store.saveLedger(ledger)
    }

    public func sync(now: Date = Date()) async -> Outcome {
        guard isEnabled() else { return .disabled }
        guard let user = await auth.currentUser() else { return .signedOut }
        guard user.canWrite else { return .notVerified }
        guard !busy else { return .busy }
        busy = true
        defer { busy = false }

        var ledger = await store.loadLedger(uid: user.uid) ?? SyncLedger(uid: user.uid, node: node)
        var report = Report()
        let index = await store.rideIndex()
        ledger.observe(rides: index, now: now)
        ledger.observe(settings: await store.settingValues(), now: now)
        ledger.initialized = true

        do {
            try await pullRides(&ledger, localIds: Set(index.map(\.id)), report: &report, now: now)
            await store.saveLedger(ledger)
            try await pushRides(&ledger, report: &report, now: now)
            try await syncSettings(&ledger, report: &report, now: now)
            ledger.lastSync = now
            await store.saveLedger(ledger)
            return .synced(report)
        } catch {
            await store.saveLedger(ledger)
            return .failed(Self.map(error))
        }
    }

    static func map(_ error: Error) -> SyncError {
        if let e = error as? SyncError { return e }
        if case RideWireCodec.WireError.newerSchema = error { return .needsAppUpdate }
        return .server(String(describing: error))
    }

    // MARK: Fahrten

    private func pullRides(_ ledger: inout SyncLedger, localIds: Set<UUID>, report: inout Report, now: Date) async throws {
        var inserts = [WorkoutRecord]()
        var effortUpdates = [UUID: WorkoutEffort?]()
        var deletions = [UUID]()
        var page: RidePage
        repeat {
            page = try await backend.fetchRides(since: ledger.rideCursor, limit: Self.pageSize)
            for remote in page.rides {
                let key = remote.id.uuidString
                if let c = remote.effortClock { ledger.clock.observe(c, now: now) }
                if let c = remote.deletedClock { ledger.clock.observe(c, now: now) }
                if remote.isTombstone {
                    var e = ledger.rides[key] ?? SyncLedger.RideEntry(effortSignature: "", effortClock: nil, onServer: true)
                    if e.deletedClock == nil {
                        e.deletedClock = remote.deletedClock ?? .initial(node: "x")
                        if localIds.contains(remote.id) {
                            deletions.append(remote.id)
                            report.deletedLocally += 1
                        }
                    }
                    e.onServer = true
                    e.tombstonePending = false
                    e.effortDirty = false
                    ledger.rides[key] = e
                    continue
                }
                guard let record = remote.record else { continue }
                if var e = ledger.rides[key] {
                    e.onServer = true
                    if e.deletedClock == nil {
                        if SyncMerge.newer(remote.effortClock, than: e.effortClock) {
                            effortUpdates[remote.id] = .some(record.effort)
                            e.effortClock = remote.effortClock
                            e.effortSignature = LocalRideInfo.signature(record.effort)
                            e.effortDirty = false
                            report.updatedEfforts += 1
                        } else if SyncMerge.newer(e.effortClock, than: remote.effortClock) {
                            e.effortDirty = true
                        } else {
                            e.effortDirty = false
                        }
                    }
                    ledger.rides[key] = e
                } else {
                    if localIds.contains(remote.id) {
                        // lokal vorhanden, aber nicht synchronisierbar markiert: Belastung trotzdem übernehmen
                        effortUpdates[remote.id] = .some(record.effort)
                    } else {
                        inserts.append(record)
                        report.pulledRides += 1
                    }
                    ledger.rides[key] = SyncLedger.RideEntry(effortSignature: LocalRideInfo.signature(record.effort),
                                                             effortClock: remote.effortClock, onServer: true)
                }
            }
            if let c = page.cursor { ledger.rideCursor = c }
        } while page.hasMore && !page.rides.isEmpty
        if !inserts.isEmpty || !effortUpdates.isEmpty || !deletions.isEmpty {
            await store.apply(inserts: inserts, effortUpdates: effortUpdates, deletions: deletions)
        }
    }

    private func pushRides(_ ledger: inout SyncLedger, report: inout Report, now: Date) async throws {
        var changes = [RideChange]()
        for (key, e) in ledger.rides.sorted(by: { $0.key < $1.key }) {
            guard let id = UUID(uuidString: key) else { continue }
            if e.tombstonePending, let clock = e.deletedClock {
                changes.append(.tombstone(id: id, clock: clock))
            } else if e.deletedClock == nil, !e.onServer {
                guard let record = await store.ride(id: id) else { continue }
                // Erststand (Wanduhr 0) wird beim ersten Hochladen ein echter Zeitstempel
                var clock = e.effortClock
                if let c = clock, c.wallMillis == 0 {
                    clock = ledger.clock.tick(now: now)
                    ledger.rides[key]?.effortClock = clock
                }
                changes.append(.create(SyncRide(record: record, effortClock: clock)))
            } else if e.deletedClock == nil, e.effortDirty, let clock = e.effortClock {
                guard let record = await store.ride(id: id) else { continue }
                changes.append(.effort(id: id, effort: record.effort, clock: clock))
            }
        }
        var start = 0
        while start < changes.count {
            let batch = Array(changes[start..<min(start + Self.pushBatch, changes.count)])
            try await backend.push(batch)
            for change in batch {
                let key = change.rideId.uuidString
                guard var e = ledger.rides[key] else { continue }
                switch change {
                case .create:
                    e.onServer = true
                    e.effortDirty = false
                    report.pushedRides += 1
                case .effort:
                    e.effortDirty = false
                    report.pushedEfforts += 1
                case .tombstone:
                    e.tombstonePending = false
                    e.onServer = true
                    report.pushedTombstones += 1
                }
                ledger.rides[key] = e
            }
            await store.saveLedger(ledger)
            start += Self.pushBatch
        }
    }

    // MARK: Einstellungen

    private func syncSettings(_ ledger: inout SyncLedger, report: inout Report, now: Date) async throws {
        let remote = try await backend.fetchSettings()
        var remotePaths = Set<String>()
        var toApply = [String: String?]()
        for (doc, d) in remote {
            for (field, rf) in d.fields {
                let path = doc + "/" + field
                guard SyncSettingsCatalog.key(path: path) != nil else { continue }
                remotePaths.insert(path)
                ledger.clock.observe(rf.clock, now: now)
                if var le = ledger.settings[path] {
                    if rf.clock > le.clock {
                        if rf.value != le.value { toApply[path] = .some(rf.value) }
                        le = SyncLedger.SettingEntry(value: rf.value, clock: rf.clock, dirty: false)
                    } else if rf.clock == le.clock {
                        le.dirty = false
                    } else {
                        le.dirty = true
                    }
                    ledger.settings[path] = le
                } else {
                    toApply[path] = .some(rf.value)
                    ledger.settings[path] = SyncLedger.SettingEntry(value: rf.value, clock: rf.clock, dirty: false)
                }
            }
        }
        if !toApply.isEmpty {
            await store.applySettings(toApply)
            report.appliedSettings = toApply.count
        }
        var docs = [String: SettingsDocument]()
        var pushed = [String]()
        for (path, var le) in ledger.settings.sorted(by: { $0.key < $1.key }) where le.dirty || !remotePaths.contains(path) {
            guard let key = SyncSettingsCatalog.key(path: path) else { continue }
            if let v = le.value, v.utf8.count > SyncSchema.maxSettingValueBytes { continue }
            // Erststand ohne Gegenstück auf dem Server: wird jetzt ein echter Wert
            if le.clock.wallMillis == 0 {
                le.clock = ledger.clock.tick(now: now)
                ledger.settings[path] = le
            }
            docs[key.document, default: SettingsDocument()].fields[key.field] = SettingField(value: le.value, clock: le.clock)
            pushed.append(path)
        }
        guard !docs.isEmpty else { return }
        try await backend.pushSettings(docs)
        for path in pushed { ledger.settings[path]?.dirty = false }
        report.pushedSettings = pushed.count
    }

    // MARK: Einwilligung, Export, Löschen

    /// Einwilligung auf dem Server speichern (nur angemeldet; ohne Konto keine Anfrage)
    public func recordConsent(_ consent: ConsentRecord) async throws {
        guard let user = await auth.currentUser() else { throw SyncError.notSignedIn }
        guard user.canWrite else { throw SyncError.emailNotVerified }
        try await backend.pushConsent(consent)
    }

    /// Alle Server-Daten des Kontos (unabhängig vom Schalter „Synchronisation“)
    public func exportServerData() async throws -> SyncExport {
        guard await auth.currentUser() != nil else { throw SyncError.notSignedIn }
        return try await backend.exportAll()
    }

    /// Alle Server-Daten löschen; die Daten auf dem Gerät bleiben. Der Abgleichsstand wird verworfen, damit ein
    /// späterer Abgleich wieder bei null beginnt (dann lädt das Gerät seine Fahrten neu hoch).
    public func deleteServerData() async throws {
        guard let user = await auth.currentUser() else { throw SyncError.notSignedIn }
        try await backend.deleteAllUserData()
        await store.deleteLedger(uid: user.uid)
    }

    /// Abgleichsstand für die Anzeige
    public func status() async -> (lastSync: Date?, pendingRides: Int, pendingSettings: Int)? {
        guard let user = await auth.currentUser(), let l = await store.loadLedger(uid: user.uid) else { return nil }
        return (l.lastSync, l.pendingRideCount, l.pendingSettingCount)
    }

    /// Serverzeit der zuletzt geholten Fahrtenänderung (Startpunkt für einen Live-Listener; nil = noch nie geholt).
    /// Fragt den Server nicht.
    public func rideCursor() async -> Date? {
        guard let user = await auth.currentUser() else { return nil }
        return await store.loadLedger(uid: user.uid)?.rideCursor
    }
}
