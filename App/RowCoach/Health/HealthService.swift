import Foundation
import HealthKit
import Observation
import os
import RowCoachKit

/// Apple Health: Freigaben und Aufzeichnung eines Rudertrainings (indoor) mit HKWorkoutSession + HKLiveWorkoutBuilder.
/// Auf iPhone/iPad seit iOS/iPadOS 26 verfügbar. Puls, Distanz und Energie schreibt die App selbst in den Builder,
/// weil der Polar-Gurt direkt mit der App verbunden ist (nicht in den iOS-Bluetooth-Einstellungen gekoppelt).
/// Protokoll für die Fehlersuche (Konsole bzw. `log collect` auf dem Gerät): Subsystem com.falkue.RowCoach, Kategorie Health
private let healthLog = Logger(subsystem: "com.falkue.RowCoach", category: "Health")

@Observable
final class HealthService {
    enum Status: String {
        case unavailable = "auf diesem Gerät nicht verfügbar"
        case notDetermined = "nicht verbunden"
        case authorized = "verbunden"
        case denied = "Schreibrecht fehlt – in Health → Teilen → Apps → RowCoach erlauben"
    }

    private(set) var status: Status = .notDetermined
    private(set) var isRecording = false
    private(set) var lastSavedWorkout: Date?
    private(set) var lastError: String?

    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?
    @ObservationIgnored private var pendingHR: [HKQuantitySample] = []
    @ObservationIgnored private var lastDistance: Double = 0
    @ObservationIgnored private var lastCalories: Int = 0
    @ObservationIgnored private var lastFlush = Date.distantPast
    @ObservationIgnored private var snapshotAtEnd = RowingSnapshot()

    private let hrType = HKQuantityType(.heartRate)
    private let energyType = HKQuantityType(.activeEnergyBurned)
    private let distanceType = HKQuantityType(.distanceRowing)
    private var shareTypes: Set<HKSampleType> { [HKWorkoutType.workoutType(), hrType, energyType, distanceType] }
    private var readTypes: Set<HKObjectType> { [HKWorkoutType.workoutType(), hrType, HKCharacteristicType(.dateOfBirth)] }

    init() { refreshStatus() }

    func refreshStatus() {
        guard HKHealthStore.isHealthDataAvailable() else { status = .unavailable; return }
        switch store.authorizationStatus(for: HKWorkoutType.workoutType()) {
        case .sharingAuthorized: status = .authorized
        case .sharingDenied: status = .denied
        default: status = .notDetermined
        }
    }

    /// Fragt die Freigaben an (zeigt den Health-Dialog beim ersten Mal).
    func connect() async {
        guard HKHealthStore.isHealthDataAvailable() else { status = .unavailable; return }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
        } catch {
            lastError = error.localizedDescription
        }
        refreshStatus()
    }

    // MARK: Aufzeichnung

    func start(courseName: String?) async {
        guard status == .authorized, !isRecording else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .rowing
        config.locationType = .indoor
        do {
            let s = try HKWorkoutSession(healthStore: store, configuration: config)
            let b = s.associatedWorkoutBuilder()
            session = s; builder = b
            lastDistance = 0; lastCalories = 0; pendingHR = []
            let start = Date()
            s.startActivity(with: start)
            try await b.beginCollection(at: start)
            var meta: [String: Any] = [HKMetadataKeyIndoorWorkout: true]
            if let courseName { meta["RowCoachCourse"] = courseName }
            try await b.addMetadata(meta)
            isRecording = true
            lastError = nil
            healthLog.info("Aufzeichnung gestartet (\(courseName ?? "ohne Strecke", privacy: .public))")
        } catch {
            healthLog.error("Start fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            lastError = "Health-Start: \(error.localizedDescription)"
            session = nil; builder = nil
        }
    }

    /// Pulswert vom Gurt merken; wird gesammelt in den Builder geschrieben.
    func record(heartRate m: HeartRateMeasurement, at date: Date) {
        guard isRecording, m.bpm > 0 else { return }
        let q = HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: Double(m.bpm))
        pendingHR.append(HKQuantitySample(type: hrType, quantity: q, start: date, end: date))
    }

    /// Distanz- und Energiezuwachs aus dem PM5-Zustand übernehmen (höchstens alle 5 s, `force` sofort).
    /// Distanz und Kalorien zählen ab 0 beim Start; der Ruderbildschirm übergibt deshalb Werte relativ zur Session.
    func record(snapshot: RowingSnapshot, at date: Date, force: Bool = false) {
        guard isRecording, let b = builder else { return }
        snapshotAtEnd = snapshot
        guard force || date.timeIntervalSince(lastFlush) >= 5 else { return }
        let from = lastFlush == .distantPast ? (b.startDate ?? date) : lastFlush
        lastFlush = date
        var samples = pendingHR
        pendingHR = []
        let dDist = snapshot.distance - lastDistance
        if dDist > 0 {
            samples.append(HKQuantitySample(type: distanceType, quantity: HKQuantity(unit: .meter(), doubleValue: dDist),
                                            start: from, end: date))
            lastDistance = snapshot.distance
        }
        let dCal = snapshot.calories - lastCalories
        if dCal > 0 {
            samples.append(HKQuantitySample(type: energyType,
                                            quantity: HKQuantity(unit: .kilocalorie(), doubleValue: Double(dCal)),
                                            start: from, end: date))
            lastCalories = snapshot.calories
        }
        guard !samples.isEmpty else { return }
        b.add(samples) { [weak self] ok, error in
            if !ok {
                healthLog.error("Daten hinzufügen fehlgeschlagen: \(error?.localizedDescription ?? "?", privacy: .public)")
                DispatchQueue.main.async { self?.lastError = "Health-Daten: \(error?.localizedDescription ?? "?")" }
            }
        }
    }

    /// Pause/Weiter an die Workout-Session melden (Health rechnet Pausen aus der Dauer heraus).
    func pause() {
        guard isRecording else { return }
        session?.pause()
    }

    func resume() {
        guard isRecording else { return }
        session?.resume()
    }

    /// Beendet die Aufzeichnung und speichert das Training in Apple Health. true = gespeichert.
    @discardableResult
    func finish() async -> Bool {
        guard isRecording, let s = session, let b = builder else { return false }
        let end = Date()
        record(snapshot: snapshotAtEnd, at: end, force: true) // letzte Werte sicher übernehmen
        var saved = false
        s.stopActivity(with: end)
        s.end()
        // Laut Apple erst nach dem Übergang der Session in „beendet“ die Sammlung schliessen und speichern
        var waited = 0
        while s.state != .ended && waited < 50 {
            try? await Task.sleep(for: .milliseconds(100))
            waited += 1
        }
        healthLog.info("Session-Status vor dem Speichern: \(s.state.rawValue) nach \(waited * 100) ms")
        do {
            try await b.addMetadata([
                "RowCoachAvgStrokeRate": snapshotAtEnd.strokeCount > 0 && snapshotAtEnd.elapsedTime > 0
                    ? Double(snapshotAtEnd.strokeCount) / (snapshotAtEnd.elapsedTime / 60) : 0,
                "RowCoachAvgPower": Double(snapshotAtEnd.averagePower),
                "RowCoachAvgPace500m": snapshotAtEnd.averagePace,
            ])
            try await b.endCollection(at: end)
            if let workout = try await b.finishWorkout() {
                lastSavedWorkout = end
                lastError = nil
                saved = true
                healthLog.info("Training gespeichert: \(workout.uuid.uuidString, privacy: .public), \(workout.duration, privacy: .public) s")
            } else {
                lastError = "Health-Speichern: Apple Health hat kein Training angelegt."
                healthLog.error("finishWorkout lieferte kein Training")
            }
        } catch {
            lastError = "Health-Speichern: \(error.localizedDescription)"
            healthLog.error("Speichern fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
        }
        isRecording = false
        session = nil; builder = nil; lastFlush = .distantPast
        return saved
    }

    /// Testbetrieb (Startargument `-healthReport 1`): schreibt Freigaben und die Trainings dieser App der letzten
    /// 14 Tage ins Protokoll (Logger com.falkue.RowCoach / Health), damit man sie ohne Bedienung am Gerät prüfen kann.
    func logReport() async {
        guard HKHealthStore.isHealthDataAvailable() else { healthLog.info("Bericht: Health nicht verfügbar"); return }
        for t in shareTypes {
            let st = store.authorizationStatus(for: t)
            healthLog.info("Bericht: Freigabe \(t.identifier, privacy: .public) = \(st.rawValue, privacy: .public) (2 = erlaubt)")
        }
        let since = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(from: HKSource.default()),
            HKQuery.predicateForSamples(withStart: since, end: nil),
        ])
        let descriptor = HKSampleQueryDescriptor(predicates: [.workout(predicate)],
                                                 sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
                                                 limit: 50)
        do {
            let workouts = try await descriptor.result(for: store)
            healthLog.info("Bericht: \(workouts.count, privacy: .public) Trainings von RowCoach in 14 Tagen")
            for w in workouts {
                let dist = w.statistics(for: distanceType)?.sumQuantity()?.doubleValue(for: .meter()) ?? 0
                let hr = w.statistics(for: hrType)?.averageQuantity()?
                    .doubleValue(for: HKUnit.count().unitDivided(by: .minute())) ?? 0
                healthLog.info("Bericht: \(w.startDate.formatted(), privacy: .public), \(Int(w.duration), privacy: .public) s, \(Int(dist), privacy: .public) m, Ø Puls \(Int(hr), privacy: .public), Typ \(w.workoutActivityType.rawValue, privacy: .public)")
            }
        } catch {
            healthLog.error("Bericht: Abfrage fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Bricht ab, ohne etwas zu speichern.
    func discard() {
        session?.end()
        builder?.discardWorkout()
        isRecording = false
        session = nil; builder = nil; lastFlush = .distantPast
    }
}
