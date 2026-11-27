import Foundation
import os
import SwiftData
import RowCoachKit

private let storeLog = Logger(subsystem: "com.falkue.RowCoach", category: "Sync")

/// Lokaler Speicher für die Synchronisation (`SyncLocalStore`): Fahrten aus SwiftData (`StoredWorkout`),
/// Einstellungen aus UserDefaults (Schlüssel aus `SyncSettingsCatalog`), Abgleichsstand je Konto als JSON-Datei
/// unter Application Support/Sync/<uid>.json. Die Datenbank der App bleibt unverändert.
@MainActor
final class AppSyncStore: SyncLocalStore {
    private let store: WorkoutStore
    private let defaults: UserDefaults
    /// true, solange Änderungen vom Server angewendet werden (die eigenen Beobachter sollen dann nicht reagieren)
    private(set) var isApplying = false

    init(store: WorkoutStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
    }

    private var context: ModelContext { store.container.mainContext }

    // MARK: Fahrten

    /// Beispielfahrten nie; Simulatorfahrten nur im Debug-Build (dort geht alles an rowcoach-dev)
    static func isSyncable(_ item: StoredWorkout) -> Bool {
        guard item.simulated else { return true }
        #if DEBUG
        return !(item.record?.isDemo ?? true)
        #else
        return false
        #endif
    }

    func rideIndex() async -> [LocalRideInfo] {
        let items = (try? context.fetch(FetchDescriptor<StoredWorkout>())) ?? []
        return items.map { item in
            LocalRideInfo(id: item.id,
                          effortSignature: LocalRideInfo.signature(WorkoutEffort(estimate: item.effortEstimate,
                                                                                 userScore: item.effortScore)),
                          syncable: Self.isSyncable(item))
        }
    }

    func ride(id: UUID) async -> WorkoutRecord? { store.item(id: id)?.record }

    func apply(inserts: [WorkoutRecord], effortUpdates: [UUID: WorkoutEffort?], deletions: [UUID]) async {
        isApplying = true
        defer { isApplying = false }
        for record in inserts where store.item(id: record.id) == nil {
            // Fahrt eines anderen Geräts: dort schon nach Apple Health geschrieben (Health gleicht selbst ab);
            // als gespeichert markieren, damit hier kein zweites Training in Health entsteht
            context.insert(StoredWorkout(record: record, savedToHealth: true))
        }
        if !inserts.isEmpty {
            do { try context.save() } catch { storeLog.error("Fahrten nicht gespeichert: \(error.localizedDescription, privacy: .public)") }
        }
        for (id, effort) in effortUpdates {
            guard let item = store.item(id: id), var record = item.record else { continue }
            record.effort = effort
            store.updateRecord(item, record)
        }
        for id in deletions {
            if let item = store.item(id: id) { store.delete(item) }
        }
    }

    // MARK: Einstellungen

    func settingValues() async -> [String: String?] {
        var out = [String: String?]()
        for key in SyncSettingsCatalog.keys {
            if key.localKey == ThresholdSettings.storageKey {
                // Schwellenprofil: auf die Feldgrenze gekürzt (älteste Schätzungen bleiben nur lokal)
                let p = ThresholdProfile.decode(defaults.data(forKey: key.localKey))
                out[key.path] = .some(p.flatMap { String(data: $0.encodedForSync(), encoding: .utf8) })
                continue
            }
            out[key.path] = .some(Self.encode(defaults.object(forKey: key.localKey), kind: key.kind))
        }
        return out
    }

    /// UserDefaults-Wert → kanonisches JSON (nil = nicht gesetzt oder unlesbar)
    static func encode(_ value: Any?, kind: SyncSettingKey.Kind) -> String? {
        guard let value else { return nil }
        switch kind {
        case .int:
            return (value as? NSNumber).map { String($0.intValue) }
        case .double:
            return (value as? NSNumber).map { String($0.doubleValue) }
        case .bool:
            return (value as? NSNumber).map { $0.boolValue ? "true" : "false" }
        case .string:
            guard let s = value as? String, let data = try? JSONEncoder().encode(s) else { return nil }
            return String(decoding: data, as: UTF8.self)
        case .json:
            guard let data = value as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }

    func applySettings(_ values: [String: String?]) async {
        isApplying = true
        defer { isApplying = false }
        var profileChanged = false
        var thresholdChanged = false
        for (path, value) in values {
            guard let key = SyncSettingsCatalog.key(path: path) else { continue }
            guard let value else {
                defaults.removeObject(forKey: key.localKey)
                continue
            }
            switch key.kind {
            case .int:
                if let v = Int(value) { defaults.set(v, forKey: key.localKey) }
            case .double:
                if let v = Double(value) { defaults.set(v, forKey: key.localKey) }
            case .bool:
                defaults.set(value == "true", forKey: key.localKey)
            case .string:
                if let s = try? JSONDecoder().decode(String.self, from: Data(value.utf8)) { defaults.set(s, forKey: key.localKey) }
            case .json:
                if key.localKey == ThresholdSettings.storageKey {
                    // Verlauf vereinigen statt überschreiben (dort gekürzt)
                    if let remote = ThresholdProfile.decode(Data(value.utf8)) {
                        let local = ThresholdProfile.decode(defaults.data(forKey: key.localKey))
                        defaults.set((local?.merged(withRemote: remote) ?? remote).encoded(), forKey: key.localKey)
                        thresholdChanged = true
                    }
                } else {
                    defaults.set(Data(value.utf8), forKey: key.localKey)
                }
            }
            if key.localKey == RowerProfile.storageKey { profileChanged = true }
        }
        // Stores mit eigenem Zwischenstand neu laden
        if profileChanged {
            RowerProfileStore.shared.profile = RowerProfile.decode(defaults.data(forKey: RowerProfile.storageKey))
        }
        if thresholdChanged { ThresholdStore.shared.reload() }
        NotificationCenter.default.post(name: SyncNotifications.settingsApplied, object: nil)
    }

    // MARK: Abgleichsstand

    private static func ledgerURL(uid: String) -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let safe = uid.filter { $0.isLetter || $0.isNumber }
        return base.appendingPathComponent("Sync", isDirectory: true).appendingPathComponent("\(safe).json")
    }

    func loadLedger(uid: String) async -> SyncLedger? {
        guard let url = Self.ledgerURL(uid: uid), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SyncLedger.self, from: data)
    }

    func saveLedger(_ ledger: SyncLedger) async {
        guard let url = Self.ledgerURL(uid: ledger.uid) else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(ledger).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            storeLog.error("Abgleichsstand nicht gespeichert: \(error.localizedDescription, privacy: .public)")
        }
    }

    func deleteLedger(uid: String) async {
        guard let url = Self.ledgerURL(uid: uid) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
