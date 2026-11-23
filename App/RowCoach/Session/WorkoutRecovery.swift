import Foundation
import os
import Observation
import RowCoachKit

private let recoveryLog = Logger(subsystem: "com.falkue.RowCoach", category: "Health")

/// Profil für die Einschätzung der Belastung (Maximalpuls und 2000-m-Bestzeit aus den Einstellungen)
enum EffortProfile {
    static var maxHR: Int {
        let v = UserDefaults.standard.integer(forKey: "profile.maxHR")
        return v > 0 ? v : 185
    }

    /// Einschätzung der App setzen, falls sie im Training noch fehlt (z. B. ältere Trainings im Verlauf)
    static func ensureEstimate(_ rec: inout WorkoutRecord) {
        rec.ensureEffortEstimate(maxHR: maxHR, best2k: TrainingSettings.best2k,
                                 plan: rec.header.workoutPlanId.flatMap { PlanLibrary.plan(id: $0) })
    }

    /// Einschätzung der App für die Anzeige (gespeichert oder frisch gerechnet)
    static func estimate(for rec: WorkoutRecord) -> Int? {
        if let e = rec.effort?.estimate { return e }
        var copy = rec
        ensureEstimate(&copy)
        return copy.effort?.estimate
    }
}

/// Wiederherstellung unterbrochener Fahrten und Nachtragen von Trainings in Apple Health.
///
/// Ablauf beim App-Start:
/// 1. `claim()` (synchron in `RowCoachApp.init`): vorhandene Sicherungspunkte übernehmen (umbenennen), bevor eine neue
///    Fahrt einen eigenen schreiben kann.
/// 2. `run(backfill:)` (in `.task`): eine vom System noch gehaltene Workout-Session beenden, jedes Training als
///    unterbrochen in den Verlauf übernehmen, in Apple Health schreiben (wenn während der Fahrt aufgezeichnet wurde),
///    dann die Datei löschen. Mit `backfill` (Startargument `-backfillHealth 1`) danach alle echten Trainings der
///    letzten 7 Tage nachtragen, die noch kein Training in Apple Health haben. Mit dem Startargument
///    `-backfillRoutes 1` danach zu den echten Trainings der letzten 7 Tage die Strecke als Route nachtragen, wo das
///    Training in Health noch keine hat.
@MainActor
@Observable
final class WorkoutRecovery {
    /// Dezenter Hinweis im Verlauf und auf der Startseite; nil = nichts anzeigen
    var notice: String?

    @ObservationIgnored private let store: WorkoutStore
    @ObservationIgnored private let health: HealthService
    @ObservationIgnored private let checkpoints: CheckpointStore
    @ObservationIgnored private var pending: [URL] = []
    @ObservationIgnored private var didRun = false

    init(store: WorkoutStore, health: HealthService, checkpoints: CheckpointStore) {
        self.store = store
        self.health = health
        self.checkpoints = checkpoints
    }

    /// Synchron beim Start: offene Sicherungspunkte übernehmen.
    func claim() {
        pending = checkpoints.claimPending()
        if !pending.isEmpty {
            recoveryLog.info("Wiederherstellung: \(self.pending.count, privacy: .public) Sicherungspunkt(e) gefunden")
        }
    }

    func run(backfill: Bool) async {
        guard !didRun else { return }
        didRun = true
        let urls = pending
        pending = []
        // Auch ohne Sicherungspunkt (Absturz in den ersten Sekunden) eine liegengebliebene Session beenden
        await health.endRecoveredSession()
        for url in urls { await recover(url) }
        if backfill { await backfillRecent(days: 7) }
        if UserDefaults.standard.bool(forKey: "backfillRoutes") { await backfillRoutes(days: 7) }
    }

    /// Hinweis zur Route nach dem letzten Speichern in Apple Health (nur bei Fehlern, sonst nil)
    var routeNote: String? { health.lastRouteNote }

    /// Ein Training aus dem Verlauf in Apple Health schreiben (Knopf in der Detailansicht). Setzt `savedToHealth`.
    func saveToHealth(_ item: StoredWorkout) async -> HealthBackfillResult {
        guard var rec = item.record else { return .failed(String(localized: "Die Trainingsdaten sind nicht lesbar.")) }
        // Ältere Trainings bekommen die Einschätzung der Belastung beim Nachtragen (im Verlauf und in Health)
        if rec.effort?.estimate == nil {
            EffortProfile.ensureEstimate(&rec)
            if rec.effort?.estimate != nil { store.updateRecord(item, rec) }
        }
        let result = await health.saveWorkout(from: rec, reason: .backfilled)
        if result.succeeded { store.markSavedToHealth(item, true) }
        return result
    }

    /// Hinweis zur Belastung nach dem letzten Speichern in Apple Health (nur bei Fehlern, sonst nil)
    var effortNote: String? { health.lastEffortNote }

    /// Eigene Belastung nachträglich eintragen oder ändern (Detailansicht im Verlauf): im Verlauf speichern, dann in
    /// Apple Health die alte eigene Probe dieser App ersetzen. Gibt den Text für die Anzeige zurück.
    func setEffort(_ item: StoredWorkout, score: Int) async -> String {
        guard var rec = item.record else { return String(localized: "Die Trainingsdaten sind nicht lesbar.") }
        EffortProfile.ensureEstimate(&rec)
        rec.setUserEffort(score)
        store.updateRecord(item, rec)
        if let error = store.lastError { return error }
        let saved = String(localized: "Anstrengung \(EffortScale.label(score)) gespeichert.")
        guard item.savedToHealth else { return saved + " " + String(localized: "Das Training ist nicht in Apple Health.") }
        let result = await health.writeEffort(for: rec)
        recoveryLog.info("Belastung nachgetragen: \(item.startDate.formatted(), privacy: .public) → \(result.logText, privacy: .public)")
        return [saved, result.note].compactMap { $0 }.joined(separator: " ")
    }

    // MARK: intern

    private func recover(_ url: URL) async {
        guard let cp = checkpoints.load(url) else {
            checkpoints.quarantine(url)
            return
        }
        let item: StoredWorkout
        let distance: Double
        if let existing = store.item(id: cp.record.id) {
            // Absturz zwischen Speichern im Verlauf und Löschen des Sicherungspunkts: nicht doppelt anlegen
            recoveryLog.info("Wiederherstellung: Training \(cp.record.id.uuidString, privacy: .public) ist schon im Verlauf")
            item = existing
            distance = existing.distance
        } else {
            var rec = cp.interruptedRecord()
            EffortProfile.ensureEstimate(&rec)
            guard RideSaveRule.shouldKeep(rec.summary) else {
                recoveryLog.info("Wiederherstellung: Sicherungspunkt zu kurz (unter 100 m oder 1 min), verworfen")
                checkpoints.remove(url)
                return
            }
            item = store.save(rec)
            if let error = store.lastError {
                // Datei bleibt liegen, nächster Start versucht es wieder
                recoveryLog.error("Wiederherstellung: Verlauf speichern fehlgeschlagen: \(error, privacy: .public)")
                return
            }
            distance = rec.summary.distance
            recoveryLog.info("Wiederherstellung: unterbrochene Fahrt übernommen, \(Int(distance), privacy: .public) m, Ende \(rec.header.endDate.formatted(), privacy: .public)")
            notice = String(localized: "Die letzte Fahrt wurde unterbrochen und gespeichert (\(Int(distance.rounded())) m).")
        }
        if cp.healthRecording, !item.savedToHealth, let rec = item.record {
            let result = await health.saveWorkout(from: rec, reason: .recovered)
            if result.succeeded { store.markSavedToHealth(item, true) }
            recoveryLog.info("Wiederherstellung: Apple Health: \(result.message, privacy: .public)")
            if result == .saved, notice != nil {
                notice = String(localized: "Die letzte Fahrt wurde unterbrochen und gespeichert (\(Int(distance.rounded())) m), auch in Apple Health.")
            }
            if result.succeeded, let routeNote = health.lastRouteNote, let n = notice {
                notice = n + " " + routeNote
            }
        }
        checkpoints.remove(url)
    }

    private func backfillRecent(days: Int) async {
        let since = Date().addingTimeInterval(-Double(days) * 86_400)
        let items = store.items(since: since).filter { !$0.simulated }
        recoveryLog.info("Nachtragen (-backfillHealth): \(items.count, privacy: .public) Trainings ohne Simulator seit \(since.formatted(), privacy: .public)")
        var saved = 0, present = 0, failed = 0
        for item in items {
            let result = await saveToHealth(item)
            switch result {
            case .saved: saved += 1
            case .alreadyPresent: present += 1
            case .failed: failed += 1
            }
            recoveryLog.info("Nachtragen: \(item.startDate.formatted(), privacy: .public), \(Int(item.distance), privacy: .public) m → \(result.message, privacy: .public)")
        }
        recoveryLog.info("Nachtragen fertig: \(saved, privacy: .public) gespeichert, \(present, privacy: .public) schon vorhanden, \(failed, privacy: .public) Fehler")
    }

    /// Testbetrieb (`-backfillRoutes 1`): zu echten Trainings (nicht Simulator) der letzten `days` Tage die Strecke als
    /// Route nachtragen, wenn das Training in Apple Health noch keine hat. Strecke aus dem gespeicherten Training.
    private func backfillRoutes(days: Int) async {
        let since = Date().addingTimeInterval(-Double(days) * 86_400)
        let items = store.items(since: since).filter { !$0.simulated }
        recoveryLog.info("Routen nachtragen (-backfillRoutes): \(items.count, privacy: .public) Trainings ohne Simulator seit \(since.formatted(), privacy: .public)")
        var written = 0, present = 0, skipped = 0, failed = 0
        for item in items {
            guard let rec = item.record else {
                skipped += 1
                recoveryLog.info("Routen nachtragen: \(item.startDate.formatted(), privacy: .public) → Trainingsdaten nicht lesbar")
                continue
            }
            let result = await health.backfillRoute(for: rec)
            switch result {
            case .written: written += 1
            case .alreadyPresent: present += 1
            case .notAuthorized, .notApplicable: skipped += 1
            case .failed: failed += 1
            }
            recoveryLog.info("Routen nachtragen: \(item.startDate.formatted(), privacy: .public), \(Int(item.distance), privacy: .public) m, Strecke \(rec.header.courseId ?? "-", privacy: .public) → \(result.logText, privacy: .public)")
        }
        recoveryLog.info("Routen nachtragen fertig: \(written, privacy: .public) geschrieben, \(present, privacy: .public) schon vorhanden, \(skipped, privacy: .public) übersprungen, \(failed, privacy: .public) Fehler")
    }
}
