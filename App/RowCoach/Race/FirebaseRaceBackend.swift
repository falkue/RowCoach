import Foundation
import os
import FirebaseAuth
import FirebaseDatabase
import FirebaseFirestore
import RowCoachKit

private let raceNetLog = Logger(subsystem: "com.falkue.RowCoach", category: "Race")

// Anbindung der Online-Rennen an Firebase (docs/MULTIPLAYER.md „Umsetzung Firebase“). Nur Übersetzung: die Logik
// (Abos, Kleinfeld-Übersicht, Anwesenheit, Nummern) liegt im Kit (`RaceLiveTransport`, `RaceOnline.swift`).
// Realtime Database: europe-west1 (DATABASE_URL aus der GoogleService-Info.plist), Firestore: europe-west6.
// Beides wird nur benutzt, wenn Firebase eingerichtet und jemand angemeldet ist (docs/SYNC.md „Offline zuerst“).

/// Abo-Handle für beide Datenbanken
private final class FirebaseObservation: RaceLiveObservation, @unchecked Sendable {
    private let lock = NSLock()
    private var onCancel: (() -> Void)?
    init(_ onCancel: @escaping () -> Void) { self.onCancel = onCancel }
    func cancel() {
        let c = lock.withLock { () -> (() -> Void)? in defer { onCancel = nil }; return onCancel }
        c?()
    }
    deinit { cancel() }
}

// MARK: - Realtime Database

/// `RaceLiveBackend` über die Firebase Realtime Database
final class FirebaseRaceLiveBackend: RaceLiveBackend, @unchecked Sendable {
    private var root: DatabaseReference { Database.database().reference() }

    func serverTimeOffset() async throws -> TimeInterval {
        let ref = Database.database().reference(withPath: ".info/serverTimeOffset")
        return await withCheckedContinuation { (c: CheckedContinuation<TimeInterval, Never>) in
            ref.observeSingleEvent(of: .value) { snap in
                c.resume(returning: ((snap.value as? NSNumber)?.doubleValue ?? 0) / 1000)
            }
        }
    }

    func joinLive(raceId: String, uid: String) async throws {
        _ = try await root.child(RaceLiveWire.memberPath(raceId: raceId, uid: uid)).setValue(true)
        let presence = root.child(RaceLiveWire.presencePath(raceId: raceId, uid: uid))
        // zuerst onDisconnect, dann setzen: bricht die Verbindung dazwischen ab, bleibt kein Geist zurück
        _ = try await presence.onDisconnectRemoveValue()
        _ = try await presence.setValue(true)
    }

    func leaveLive(raceId: String, uid: String) async {
        let presence = root.child(RaceLiveWire.presencePath(raceId: raceId, uid: uid))
        do {
            _ = try await presence.removeValue()
            _ = try await presence.cancelDisconnectOperations()
        } catch {
            raceNetLog.error("Anwesenheit entfernen: \(error.localizedDescription, privacy: .public)")
        }
    }

    func readFrame(raceId: String, uid: String) async throws -> RaceWireFrame? {
        let snap = try await root.child(RaceLiveWire.framePath(raceId: raceId, uid: uid)).getData()
        return RaceWireFrame(value: snap.value)
    }

    func writeFrame(raceId: String, uid: String, frame: RaceWireFrame) async throws {
        let value = frame.value(serverTimestamp: ServerValue.timestamp())
        _ = try await root.child(RaceLiveWire.framePath(raceId: raceId, uid: uid)).setValue(value)
    }

    func observeFrame(raceId: String, uid: String,
                      onChange: @escaping @Sendable (RaceWireFrame?) -> Void) -> any RaceLiveObservation {
        let ref = root.child(RaceLiveWire.framePath(raceId: raceId, uid: uid))
        let handle = ref.observe(.value, with: { snap in onChange(RaceWireFrame(value: snap.value)) },
                                 withCancel: { error in
                                     raceNetLog.error("Frames von \(uid, privacy: .public): \(error.localizedDescription, privacy: .public)")
                                 })
        return FirebaseObservation { ref.removeObserver(withHandle: handle) }
    }

    func observePresence(raceId: String, onChange: @escaping @Sendable (Set<String>) -> Void) -> any RaceLiveObservation {
        let ref = root.child(RaceLiveWire.presenceRoot(raceId: raceId))
        let handle = ref.observe(.value) { snap in
            onChange(Set((snap.value as? [String: Any])?.keys.map { $0 } ?? []))
        }
        return FirebaseObservation { ref.removeObserver(withHandle: handle) }
    }

    func observeField(raceId: String, onChange: @escaping @Sendable (RaceFieldSnapshot) -> Void) -> any RaceLiveObservation {
        let ref = root.child(RaceLiveWire.fieldPath(raceId: raceId))
        let handle = ref.observe(.value) { snap in
            if let s = Self.snapshot(snap.value) { onChange(s) }
        }
        return FirebaseObservation { ref.removeObserver(withHandle: handle) }
    }

    func readFieldFull(raceId: String) async throws -> RaceFieldSnapshot? {
        Self.snapshot(try await root.child(RaceLiveWire.fieldFullPath(raceId: raceId)).getData().value)
    }

    /// `{r, at, b}` → Übersicht (gleiches JSON wie `RaceFieldSnapshot`)
    private static func snapshot(_ value: Any?) -> RaceFieldSnapshot? {
        guard let d = value as? [String: Any], JSONSerialization.isValidJSONObject(d),
              let data = try? JSONSerialization.data(withJSONObject: d) else { return nil }
        return try? JSONDecoder().decode(RaceFieldSnapshot.self, from: data)
    }

    /// Rennen in der Realtime Database anmelden (`meta/{raceId}`), Voraussetzung für Mitgliedschaft und Frames
    func writeMeta(raceId: String, startsAt: TimeInterval, createdBy: String) async throws {
        _ = try await root.child(RaceLiveWire.metaPath(raceId: raceId))
            .setValue(["startsAt": Int64((startsAt * 1000).rounded()), "createdBy": createdBy])
    }

    func writeMember(raceId: String, uid: String) async throws {
        _ = try await root.child(RaceLiveWire.memberPath(raceId: raceId, uid: uid)).setValue(true)
    }
}

// MARK: - Firestore

/// Neutrale Dokumentwerte des Kits ↔ Firestore-Typen
enum FirestoreRaceDoc {
    static func encode(_ v: RaceDocValue) -> Any {
        switch v {
        case .string(let s): return s
        case .int(let i): return i
        case .double(let d): return d
        case .bool(let b): return b
        case .timestamp(let t): return Timestamp(date: Date(timeIntervalSince1970: t))
        case .map(let m): return m.mapValues(encode)
        case .null: return NSNull()
        case .serverTimestamp: return FieldValue.serverTimestamp()
        }
    }

    static func encode(_ d: RaceDocument) -> [String: Any] { d.mapValues(encode) }

    static func decode(_ any: Any) -> RaceDocValue {
        switch any {
        case let s as String: return .string(s)
        case let t as Timestamp: return .timestamp(t.dateValue().timeIntervalSince1970)
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
            return CFNumberIsFloatType(n) ? .double(n.doubleValue) : .int(n.intValue)
        case let m as [String: Any]: return .map(m.mapValues(decode))
        default: return .null
        }
    }

    static func decode(_ data: [String: Any]) -> RaceDocument { data.mapValues(decode) }
}

/// `RaceDirectory` über Firestore; legt zusätzlich `meta/` und `members/` in der Realtime Database an
final class FirestoreRaceDirectory: RaceDirectory, @unchecked Sendable {
    private let live: FirebaseRaceLiveBackend
    private var db: Firestore { Firestore.firestore() }

    init(live: FirebaseRaceLiveBackend) { self.live = live }

    private func uid() throws -> String {
        guard FirebaseBootstrap.isConfigured, let uid = Auth.auth().currentUser?.uid else { throw RaceDirectoryError.notSignedIn }
        return uid
    }

    private func wrap<T>(_ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch let e as RaceDirectoryError {
            throw e
        } catch {
            let ns = error as NSError
            if ns.domain == "FIRFirestoreErrorDomain" {
                switch ns.code {
                case 14: throw RaceDirectoryError.network(ns.localizedDescription)   // unavailable
                case 7: throw RaceDirectoryError.notAllowed                         // permission denied
                case 5: throw RaceDirectoryError.notFound
                default: break
                }
            }
            throw RaceDirectoryError.server(ns.localizedDescription)
        }
    }

    private func races() -> CollectionReference { db.collection("races") }

    func upcoming(serverNow: TimeInterval, limit: Int) async throws -> [OnlineRace] {
        _ = try uid()
        // Rennen, die noch laufen könnten (Start bis zu 3 h zurück); Liste nur öffentliche (Regeln)
        let since = Timestamp(date: Date(timeIntervalSince1970: serverNow - 3 * 3600))
        return try await wrap {
            let snap: QuerySnapshot
            do {
                snap = try await races().whereField("visibility", isEqualTo: "public")
                    .whereField("startsAt", isGreaterThan: since).order(by: "startsAt").limit(to: limit).getDocuments()
            } catch let error as NSError where error.domain == "FIRFirestoreErrorDomain" && error.code == 9 {
                // Index (visibility, startsAt) noch nicht angelegt (firestore.indexes.json): ohne Bereich abfragen
                raceNetLog.error("Index für Rennen fehlt, Abfrage ohne Sortierung: \(error.localizedDescription, privacy: .public)")
                snap = try await races().whereField("visibility", isEqualTo: "public").limit(to: 200).getDocuments()
            }
            return snap.documents.compactMap { OnlineRace(id: $0.documentID, document: FirestoreRaceDoc.decode($0.data())) }
                .filter { $0.status != .cancelled && $0.startsAt + $0.maxDuration > serverNow }
                .sorted { $0.startsAt < $1.startsAt }
        }
    }

    func race(id: String) async throws -> OnlineRace? {
        _ = try uid()
        return try await wrap {
            let d = try await races().document(id).getDocument()
            return d.data().flatMap { OnlineRace(id: id, document: FirestoreRaceDoc.decode($0)) }
        }
    }

    func raceId(inviteCode: String) async throws -> String? {
        _ = try uid()
        let code = RaceInviteCode.normalize(inviteCode)
        guard RaceInviteCode.isValid(code) else { return nil }
        return try await wrap {
            try await db.collection("raceCodes").document(code).getDocument().data()?["raceId"] as? String
        }
    }

    func create(_ race: OnlineRace, inviteCode: String?) async throws -> OnlineRace {
        let me = try uid()
        guard race.createdBy == me else { throw RaceDirectoryError.notAllowed }
        let ref = races().document()
        var r = race
        r.id = ref.documentID
        r.createdAt = nil
        try await wrap {
            // zuerst die Realtime Database (meta), sonst dürfte niemand Mitglied werden
            try await live.writeMeta(raceId: r.id, startsAt: r.startsAt, createdBy: me)
            let batch = db.batch()
            batch.setData(FirestoreRaceDoc.encode(r.document), forDocument: ref)
            if let code = inviteCode {
                batch.setData(["raceId": r.id], forDocument: db.collection("raceCodes").document(code))
            }
            try await batch.commit()
        }
        return r
    }

    func cancel(raceId: String) async throws {
        _ = try uid()
        try await wrap { try await races().document(raceId).updateData(["status": OnlineRaceStatus.cancelled.rawValue]) }
    }

    func entries(raceId: String) async throws -> [OnlineRaceEntry] {
        _ = try uid()
        return try await wrap {
            try await races().document(raceId).collection("participants").getDocuments().documents.compactMap {
                OnlineRaceEntry(id: $0.documentID, document: FirestoreRaceDoc.decode($0.data()))
            }
        }
    }

    func register(raceId: String, entry: OnlineRaceEntry) async throws {
        let me = try uid()
        guard entry.id == me else { throw RaceDirectoryError.notAllowed }
        let ref = races().document(raceId).collection("participants").document(me)
        try await wrap {
            let existing = try? await ref.getDocument()
            if existing?.exists == true {
                // schon angemeldet: nur Name und Erscheinung (die Anmeldezeit bestimmt die Bahn und bleibt)
                let fields: [String: Any] = [
                    "displayName": String(entry.displayName.prefix(OnlineRaceLimits.displayNameMax)),
                    "appearance": entry.appearance.flatMap(OnlineRaceEntry.encodeAppearance) ?? FieldValue.delete(),
                ]
                try await ref.updateData(fields)
            } else {
                var e = entry
                e.joinedAt = nil   // Serverzeit (Regeln: joinedAt == request.time)
                try await ref.setData(FirestoreRaceDoc.encode(e.document))
            }
            try await live.writeMember(raceId: raceId, uid: me)
        }
    }

    func unregister(raceId: String, uid other: String) async throws {
        let me = try uid()
        guard other == me else { throw RaceDirectoryError.notAllowed }
        try await wrap { try await races().document(raceId).collection("participants").document(me).delete() }
    }

    func observeEntries(raceId: String, onChange: @escaping @Sendable ([OnlineRaceEntry]) -> Void) -> any RaceLiveObservation {
        let reg = races().document(raceId).collection("participants").addSnapshotListener { snap, error in
            if let error { raceNetLog.error("Anmeldungen: \(error.localizedDescription, privacy: .public)") }
            guard let snap else { return }
            // eigene Anmeldung mit noch ausstehender Serverzeit: joinedAt geschätzt (ans Ende), nicht verwerfen
            let list = snap.documents.compactMap { d -> OnlineRaceEntry? in
                OnlineRaceEntry(id: d.documentID, document: FirestoreRaceDoc.decode(d.data(with: .estimate)))
            }
            onChange(list)
        }
        return FirebaseObservation { reg.remove() }
    }

    func submitResult(raceId: String, result: OnlineRaceResult) async throws {
        let me = try uid()
        guard result.id == me, result.provisional, result.place == nil else { throw RaceDirectoryError.notAllowed }
        var r = result
        r.submittedAt = nil
        r.flags = []
        try await wrap {
            try await races().document(raceId).collection("results").document(me).setData(FirestoreRaceDoc.encode(r.document))
        }
    }

    func observeResults(raceId: String, onChange: @escaping @Sendable ([OnlineRaceResult]) -> Void) -> any RaceLiveObservation {
        let reg = races().document(raceId).collection("results").addSnapshotListener { snap, error in
            if let error { raceNetLog.error("Ergebnisse: \(error.localizedDescription, privacy: .public)") }
            guard let snap else { return }
            onChange(snap.documents.compactMap {
                OnlineRaceResult(id: $0.documentID, document: FirestoreRaceDoc.decode($0.data(with: .estimate)))
            })
        }
        return FirebaseObservation { reg.remove() }
    }
}
