import Foundation
import os
import FirebaseAuth
import FirebaseFirestore
import RowCoachKit

private let syncLog = Logger(subsystem: "com.falkue.RowCoach", category: "Sync")

/// `SyncBackend` über Cloud Firestore (Datenbank in europe-west6, Zürich). Form der Dokumente: `RideWire`,
/// `SettingsDocument`, `ConsentRecord` im Kit; Regeln: firebase/firestore.rules; Beschreibung: docs/SYNC.md.
/// Jede Methode verlangt ein angemeldetes Konto; ohne Konto wirft sie `notSignedIn`, bevor etwas hinausgeht.
final class FirestoreSyncBackend: SyncBackend {
    private var db: Firestore { Firestore.firestore() }

    private func userRef() throws -> DocumentReference {
        guard FirebaseBootstrap.isConfigured, let uid = Auth.auth().currentUser?.uid else { throw SyncError.notSignedIn }
        return db.collection("users").document(uid)
    }

    private func wrap<T>(_ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch let e as SyncError {
            throw e
        } catch {
            let ns = error as NSError
            // FIRFirestoreErrorDomain 14 = unavailable (offline)
            if ns.domain == "FIRFirestoreErrorDomain", ns.code == 14 { throw SyncError.network(ns.localizedDescription) }
            throw SyncError.server(ns.localizedDescription)
        }
    }

    // MARK: Fahrten

    func fetchRides(since cursor: Date?, limit: Int) async throws -> RidePage {
        let col = try userRef().collection("rides")
        return try await wrap {
            var query: Query = col
            if let cursor { query = query.whereField(RideWire.Field.updatedAt, isGreaterThan: Timestamp(date: cursor)) }
            let snap = try await query.order(by: RideWire.Field.updatedAt).limit(to: limit).getDocuments()
            var rides = [SyncRide]()
            var last = cursor
            for doc in snap.documents {
                let data = doc.data()
                if let ts = data[RideWire.Field.updatedAt] as? Timestamp { last = ts.dateValue() }
                var wire = FirestoreSyncBackend.wire(from: data, id: doc.documentID)
                let chunkCount = (data[RideWire.Field.chunkCount] as? NSNumber)?.intValue ?? 0
                if chunkCount > 0, !wire.deleted {
                    let chunks = try await doc.reference.collection("chunks").getDocuments()
                    wire.chunks = chunks.documents
                        .sorted { (($0.data()[RideWire.Field.chunkIndex] as? NSNumber)?.intValue ?? 0)
                                < (($1.data()[RideWire.Field.chunkIndex] as? NSNumber)?.intValue ?? 0) }
                        .compactMap { $0.data()[RideWire.Field.chunkData] as? Data }
                }
                do {
                    rides.append(try RideWireCodec.decode(wire))
                } catch RideWireCodec.WireError.newerSchema {
                    throw SyncError.needsAppUpdate
                } catch {
                    // eine beschädigte Fahrt soll den Abgleich der übrigen nicht aufhalten
                    syncLog.error("Fahrt \(doc.documentID, privacy: .public) unlesbar: \(String(describing: error), privacy: .public)")
                }
            }
            return RidePage(rides: rides, cursor: last, hasMore: snap.documents.count >= limit)
        }
    }

    static func wire(from data: [String: Any], id: String) -> RideWire {
        typealias F = RideWire.Field
        return RideWire(schemaVersion: (data[F.schema] as? NSNumber)?.intValue ?? 1,
                        id: id,
                        startDate: (data[F.start] as? Timestamp)?.dateValue(),
                        distance: (data[F.distance] as? NSNumber)?.doubleValue,
                        activeDuration: (data[F.activeDuration] as? NSNumber)?.doubleValue,
                        recordJSON: data[F.record] as? String,
                        blob: data[F.blob] as? Data,
                        codec: (data[F.codec] as? NSNumber)?.intValue,
                        thinned: (data[F.thinned] as? NSNumber)?.intValue,
                        effortJSON: data[F.effort] as? String,
                        effortClock: data[F.effortClock] as? String,
                        deleted: (data[F.deleted] as? Bool) ?? false,
                        deletedClock: data[F.deletedClock] as? String,
                        updatedAt: (data[F.updatedAt] as? Timestamp)?.dateValue())
    }

    static func dictionary(_ w: RideWire) -> [String: Any] {
        typealias F = RideWire.Field
        if w.deleted {
            return [F.schema: w.schemaVersion, F.id: w.id, F.deleted: true, F.deletedClock: w.deletedClock ?? "",
                    F.updatedAt: FieldValue.serverTimestamp()]
        }
        var d: [String: Any] = [F.schema: w.schemaVersion, F.id: w.id, F.deleted: false,
                                F.codec: w.codec ?? 1, F.chunkCount: w.chunks.count,
                                F.updatedAt: FieldValue.serverTimestamp()]
        if let s = w.startDate { d[F.start] = Timestamp(date: s) }
        if let v = w.distance { d[F.distance] = v }
        if let v = w.activeDuration { d[F.activeDuration] = v }
        if let v = w.recordJSON { d[F.record] = v }
        if let v = w.blob, w.chunks.isEmpty { d[F.blob] = v }
        if let v = w.thinned { d[F.thinned] = v }
        if let v = w.effortJSON { d[F.effort] = v }
        if let v = w.effortClock { d[F.effortClock] = v }
        return d
    }

    func push(_ changes: [RideChange]) async throws {
        let col = try userRef().collection("rides")
        try await wrap {
            for change in changes {
                let ref = col.document(change.rideId.uuidString)
                switch change {
                case .create(let ride):
                    let wire = try RideWireCodec.encode(ride)
                    // schon vorhanden (zweiter Versuch, anderes Gerät, Tombstone): Fahrten sind unveränderlich
                    if try await ref.getDocument().exists { continue }
                    let batch = db.batch()
                    batch.setData(FirestoreSyncBackend.dictionary(wire), forDocument: ref)
                    for (i, chunk) in wire.chunks.enumerated() {
                        batch.setData([RideWire.Field.chunkIndex: i, RideWire.Field.chunkData: chunk],
                                      forDocument: ref.collection("chunks").document(String(i)))
                    }
                    try await batch.commit()
                case .effort(_, let effort, let clock):
                    let json = RideWireCodec.effortJSON(effort)
                    _ = try await db.runTransaction { transaction, errorPointer -> Any? in
                        let snap: DocumentSnapshot
                        do {
                            snap = try transaction.getDocument(ref)
                        } catch let e as NSError {
                            errorPointer?.pointee = e
                            return nil
                        }
                        guard snap.exists, (snap.data()?[RideWire.Field.deleted] as? Bool) == false else { return nil }
                        if let old = (snap.data()?[RideWire.Field.effortClock] as? String).flatMap(HybridTimestamp.init(encoded:)),
                           old >= clock { return nil }
                        transaction.updateData([RideWire.Field.effort: json.map { $0 as Any } ?? FieldValue.delete(),
                                                RideWire.Field.effortClock: clock.encoded,
                                                RideWire.Field.updatedAt: FieldValue.serverTimestamp()],
                                               forDocument: ref)
                        return nil
                    }
                case .tombstone(let id, let clock):
                    let snap = try await ref.getDocument()
                    if snap.exists, (snap.data()?[RideWire.Field.deleted] as? Bool) == true { continue }
                    let batch = db.batch()
                    if snap.exists {
                        for chunk in try await ref.collection("chunks").getDocuments().documents {
                            batch.deleteDocument(chunk.reference)
                        }
                    }
                    let wire = RideWire(id: id.uuidString, deleted: true, deletedClock: clock.encoded)
                    batch.setData(FirestoreSyncBackend.dictionary(wire), forDocument: ref)
                    try await batch.commit()
                }
            }
        }
    }

    // MARK: Einstellungen

    static func settingsDocument(from data: [String: Any]?) -> SettingsDocument {
        var doc = SettingsDocument()
        guard let fields = data?["fields"] as? [String: Any] else { return doc }
        for (name, raw) in fields {
            guard let m = raw as? [String: Any], let c = (m["c"] as? String).flatMap(HybridTimestamp.init(encoded:))
            else { continue }
            doc.fields[name] = SettingField(value: m["v"] as? String, clock: c)
        }
        return doc
    }

    static func dictionary(_ doc: SettingsDocument) -> [String: Any] {
        var fields = [String: Any]()
        for (name, f) in doc.fields {
            fields[name] = ["v": f.value.map { $0 as Any } ?? NSNull(), "c": f.clock.encoded]
        }
        return ["v": SyncSchema.version, "fields": fields, "updatedAt": FieldValue.serverTimestamp()]
    }

    func fetchSettings() async throws -> [String: SettingsDocument] {
        let user = try userRef()
        return try await wrap {
            var out = [String: SettingsDocument]()
            for name in SyncSettingsCatalog.documents {
                let snap = try await user.collection("settings").document(name).getDocument()
                if snap.exists { out[name] = FirestoreSyncBackend.settingsDocument(from: snap.data()) }
            }
            return out
        }
    }

    /// Je Dokument eine Transaktion: Serverstand lesen, feldweise zusammenführen (neuerer Zeitstempel gewinnt),
    /// zurückschreiben. Die Regeln lehnen ältere Stände zusätzlich ab.
    func pushSettings(_ documents: [String: SettingsDocument]) async throws {
        let user = try userRef()
        try await wrap {
            for (name, local) in documents {
                let ref = user.collection("settings").document(name)
                _ = try await db.runTransaction { transaction, errorPointer -> Any? in
                    let snap: DocumentSnapshot
                    do {
                        snap = try transaction.getDocument(ref)
                    } catch let e as NSError {
                        errorPointer?.pointee = e
                        return nil
                    }
                    let remote = FirestoreSyncBackend.settingsDocument(from: snap.exists ? snap.data() : nil)
                    let merged = SyncMerge.mergeSettings(remote, local)
                    transaction.setData(FirestoreSyncBackend.dictionary(merged), forDocument: ref)
                    return nil
                }
            }
        }
    }

    // MARK: Live-Aktualisierung (docs/SYNC.md „Live-Aktualisierung“)

    /// Lauscht, solange die App im Vordergrund ist, auf Änderungen von anderen Geräten: die drei Einstellungsdokumente
    /// und Fahrten mit `updatedAt` nach `since`. Der erste Stand jedes Listeners wird übergangen (den holt der normale
    /// Abgleich), ebenso Stände mit eigenen, noch nicht bestätigten Schreibvorgängen. `onChange` und `onError` kommen
    /// auf dem Hauptthread. Gibt eine Funktion zum Beenden zurück; wirft ohne Konto, bevor etwas hinausgeht.
    func listenForRemoteChanges(since: Date, onChange: @escaping @MainActor () -> Void,
                                onError: @escaping @MainActor (Error) -> Void) throws -> () -> Void {
        let user = try userRef()
        func handler(_ name: String) -> (QuerySnapshot?, Error?) -> Void {
            var first = true
            return { snap, error in
                if let error {
                    syncLog.error("Live-Abgleich \(name, privacy: .public) beendet: \(error.localizedDescription, privacy: .public)")
                    Task { @MainActor in onError(error) }
                    return
                }
                guard let snap else { return }
                defer { first = false }
                guard !first, !snap.metadata.hasPendingWrites, !snap.documentChanges.isEmpty else { return }
                syncLog.info("Live-Abgleich: \(snap.documentChanges.count, privacy: .public) Änderung(en) in \(name, privacy: .public)")
                Task { @MainActor in onChange() }
            }
        }
        let settings = user.collection("settings").addSnapshotListener(handler("settings"))
        let rides = user.collection("rides")
            .whereField(RideWire.Field.updatedAt, isGreaterThan: Timestamp(date: since))
            .addSnapshotListener(handler("rides"))
        return {
            settings.remove()
            rides.remove()
        }
    }

    // MARK: Einwilligung

    static func consent(from data: [String: Any]?) -> ConsentRecord? {
        guard let d = data, let kind = (d["kind"] as? String).flatMap(ConsentKind.init(rawValue:)),
              let granted = d["granted"] as? Bool, let version = d["textVersion"] as? String else { return nil }
        let decided = (d["decidedAt"] as? Timestamp)?.dateValue() ?? (d["at"] as? Timestamp)?.dateValue() ?? Date(timeIntervalSince1970: 0)
        return ConsentRecord(kind: kind, granted: granted, textVersion: version, locale: d["locale"] as? String ?? "",
                             decidedAt: decided)
    }

    func fetchConsents() async throws -> [ConsentRecord] {
        let user = try userRef()
        return try await wrap {
            var out = [ConsentRecord]()
            for kind in ConsentKind.allCases {
                let snap = try await user.collection("consent").document(kind.rawValue).getDocument()
                if let c = FirestoreSyncBackend.consent(from: snap.data()) { out.append(c) }
            }
            return out
        }
    }

    func pushConsent(_ consent: ConsentRecord) async throws {
        let user = try userRef()
        let data: [String: Any] = ["v": 1, "kind": consent.kind.rawValue, "granted": consent.granted,
                                   "textVersion": consent.textVersion, "locale": consent.locale,
                                   "decidedAt": Timestamp(date: consent.decidedAt),
                                   "at": FieldValue.serverTimestamp()]
        try await wrap {
            let batch = db.batch()
            batch.setData(data, forDocument: user.collection("consent").document(consent.kind.rawValue))
            batch.setData(data, forDocument: user.collection("consentLog").document())
            try await batch.commit()
        }
    }

    // MARK: Export und Löschen

    func exportAll() async throws -> SyncExport {
        let user = try userRef()
        var rides = [SyncRide]()
        var cursor: Date?
        while true {
            let page = try await fetchRides(since: cursor, limit: 100)
            rides += page.rides
            guard page.hasMore, page.cursor != cursor else { break }
            cursor = page.cursor
        }
        let settings = try await fetchSettings()
        let consents = try await fetchConsents()
        let entitlements: [EntitlementStatus] = try await wrap {
            try await user.collection("entitlements").getDocuments().documents.compactMap { doc -> EntitlementStatus? in
                guard let e = Entitlement(rawValue: doc.documentID) else { return nil }
                let d = doc.data()
                return EntitlementStatus(entitlement: e, active: d["active"] as? Bool ?? false,
                                         expiresAt: (d["expiresAt"] as? Timestamp)?.dateValue(),
                                         source: d["source"] as? String, productId: d["productId"] as? String)
            }
        }
        return SyncExport(exportedAt: Date(), uid: user.documentID, rides: rides, settings: settings,
                          consents: consents, entitlements: entitlements)
    }

    /// Alles unter users/{uid} löschen, was die Regeln dem Konto erlauben. Berechtigungen (Abo) löscht nur der
    /// Server (Cloud Function bei der Kontolöschung, docs/SYNC.md).
    func deleteAllUserData() async throws {
        let user = try userRef()
        try await wrap {
            var refs = [DocumentReference]()
            for doc in try await user.collection("rides").getDocuments().documents {
                if ((doc.data()[RideWire.Field.chunkCount] as? NSNumber)?.intValue ?? 0) > 0 {
                    refs += try await doc.reference.collection("chunks").getDocuments().documents.map(\.reference)
                }
                refs.append(doc.reference)
            }
            refs += SyncSettingsCatalog.documents.map { user.collection("settings").document($0) }
            refs += ConsentKind.allCases.map { user.collection("consent").document($0.rawValue) }
            refs += try await user.collection("consentLog").getDocuments().documents.map(\.reference)
            var start = 0
            while start < refs.count {
                let batch = db.batch()
                for ref in refs[start..<min(start + 400, refs.count)] { batch.deleteDocument(ref) }
                try await batch.commit()
                start += 400
            }
        }
    }
}
