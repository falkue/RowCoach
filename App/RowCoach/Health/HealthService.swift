import CoreLocation
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

/// Anlass für ein nachträglich geschriebenes Training; der Rohwert ist der Metadaten-Schlüssel im HKWorkout.
enum HealthBackfillReason: String {
    /// aus dem Sicherungspunkt nach Akku-Ausfall oder Absturz
    case recovered = "RowCoachRecovered"
    /// von Hand oder mit `-backfillHealth` aus dem Verlauf nachgetragen
    case backfilled = "RowCoachBackfilled"
}

enum HealthBackfillResult: Equatable {
    /// Es gab schon ein Training dieser App im Zeitfenster; nichts geschrieben
    case alreadyPresent
    case saved
    case failed(String)

    var succeeded: Bool {
        if case .failed = self { return false }
        return true
    }

    var message: String {
        switch self {
        case .alreadyPresent: return "Das Training war schon in Apple Health."
        case .saved: return "In Apple Health gespeichert."
        case .failed(let reason): return reason
        }
    }
}

/// Ergebnis beim Schreiben der Strecke als Route (HKWorkoutRoute) zu einem Training.
enum HealthRouteResult: Equatable {
    /// Route mit so vielen Punkten geschrieben
    case written(Int)
    /// Das Training hat schon eine Route (Anzahl Punkte); nichts geschrieben
    case alreadyPresent(Int)
    /// Routen-Freigabe nicht erteilt; keine Route (kein Fehler)
    case notAuthorized
    /// Keine Route möglich (z. B. Teststrecke ohne Landeskoordinaten, Strecke nicht im App-Bundle)
    case notApplicable(String)
    case failed(String)

    /// Text für den Hinweis in der App; nur bei Fehlern
    var note: String? {
        if case .failed(let reason) = self { return "Die Strecke wurde nicht als Route gespeichert (\(reason))." }
        return nil
    }

    var logText: String {
        switch self {
        case .written(let n): return "Route geschrieben, \(n) Punkte"
        case .alreadyPresent(let n): return "Route schon vorhanden, \(n) Punkte"
        case .notAuthorized: return "keine Routen-Freigabe, keine Route"
        case .notApplicable(let why): return "keine Route: \(why)"
        case .failed(let why): return "Route fehlgeschlagen: \(why)"
        }
    }
}

@Observable
final class HealthService {
    enum Status: String {
        case unavailable = "auf diesem Gerät nicht verfügbar"
        case notDetermined = "nicht verbunden"
        case authorized = "verbunden"
        case denied = "Schreibrecht fehlt – in Health → Teilen → Apps → RowCoach erlauben"
    }

    /// Freigabe zum Schreiben der Strecke als Route (HKWorkoutRoute); kam nach der ersten Freigabe dazu
    enum RouteStatus: String {
        case unavailable = "nicht verfügbar"
        case notDetermined = "nicht freigegeben"
        case authorized = "freigegeben"
        case denied = "abgelehnt – in Health → Teilen → Apps → RowCoach „Trainingsrouten“ erlauben"
    }

    private(set) var status: Status = .notDetermined
    private(set) var routeStatus: RouteStatus = .notDetermined
    /// Hinweis zur Route des zuletzt gespeicherten bzw. nachgetragenen Trainings (nur bei Fehlern, sonst nil)
    private(set) var lastRouteNote: String?
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
    private let routeType = HKSeriesType.workoutRoute()
    /// Laut Apple („Creating a workout route“) braucht eine Route Lese- und Schreibrecht für Training und Route.
    /// Eine Standortfreigabe ist nicht nötig: Die Punkte kommen aus der Strecke, nicht aus Core Location.
    private var shareTypes: Set<HKSampleType> { [HKWorkoutType.workoutType(), hrType, energyType, distanceType, routeType] }
    private var readTypes: Set<HKObjectType> {
        [HKWorkoutType.workoutType(), hrType, HKCharacteristicType(.dateOfBirth), routeType]
    }
    /// Metadaten der Route: virtuell (aus der Strecke gerechnet, kein GPS) und Strecken-id
    private static let routeVirtualKey = "RowCoachVirtualRoute"
    private static let routeCourseKey = "RowCoachCourseId"

    init() { refreshStatus() }

    func refreshStatus() {
        guard HKHealthStore.isHealthDataAvailable() else { status = .unavailable; routeStatus = .unavailable; return }
        switch store.authorizationStatus(for: HKWorkoutType.workoutType()) {
        case .sharingAuthorized: status = .authorized
        case .sharingDenied: status = .denied
        default: status = .notDetermined
        }
        switch store.authorizationStatus(for: routeType) {
        case .sharingAuthorized: routeStatus = .authorized
        case .sharingDenied: routeStatus = .denied
        default: routeStatus = .notDetermined
        }
    }

    /// Fragt die Freigaben an (zeigt den Health-Dialog beim ersten Mal). Später zeigt der Dialog nur noch Typen,
    /// über die noch nicht entschieden wurde (z. B. die Routen-Freigabe nach einem Update).
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
    /// Mit `route` (dem gespeicherten Training der Fahrt) wird danach die Strecke als Route angehängt; ein Fehler dabei
    /// ändert nichts am gespeicherten Training (Protokoll und `lastRouteNote`).
    @discardableResult
    func finish(route routeRecord: WorkoutRecord? = nil) async -> Bool {
        lastRouteNote = nil
        guard isRecording, let s = session, let b = builder else { return false }
        let end = Date()
        record(snapshot: snapshotAtEnd, at: end, force: true) // letzte Werte sicher übernehmen
        var saved = false
        var savedWorkout: HKWorkout?
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
                savedWorkout = workout
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
        if let routeRecord, let workout = savedWorkout {
            let route = await addRoute(for: routeRecord, to: workout)
            lastRouteNote = route.note
            healthLog.info("Training \(workout.uuid.uuidString, privacy: .public): \(route.logText, privacy: .public)")
        } else if routeRecord != nil, saved {
            healthLog.info("Keine Route: Apple Health hat das gespeicherte Training nicht zurückgegeben (Gerät gesperrt?)")
        }
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
        refreshStatus()
        healthLog.info("Bericht: Routen-Freigabe (Strecke als Route) = \(self.routeStatus.rawValue, privacy: .public)")
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
                let routeText: String
                do {
                    if let n = try await routePointCount(for: w) {
                        routeText = "Route \(n) Punkte"
                    } else {
                        routeText = "keine Route"
                    }
                } catch {
                    routeText = "Route unbekannt (\(error.localizedDescription))"
                }
                healthLog.info("Bericht: \(w.startDate.formatted(), privacy: .public), \(Int(w.duration), privacy: .public) s, \(Int(dist), privacy: .public) m, Ø Puls \(Int(hr), privacy: .public), Typ \(w.workoutActivityType.rawValue, privacy: .public), \(routeText, privacy: .public)")
            }
        } catch {
            healthLog.error("Bericht: Abfrage fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Wiederherstellen und Nachtragen

    /// Nach einem Absturz: eine vom System noch gehaltene Workout-Session (`recoverActiveWorkoutSession`, iOS 26)
    /// beenden und ihren Builder verwerfen. Das Training selbst kommt aus dem Sicherungspunkt der App
    /// (`saveWorkout(from:reason:)`), weil nur der Sicherungspunkt Splits, Zusammenfassung und das richtige Ende hat.
    /// Ohne aktive Session (Akku leer, App vom Nutzer beendet) liefert HealthKit nil; dann passiert nichts.
    func endRecoveredSession() async {
        guard status == .authorized, !isRecording else { return }
        do {
            guard let s = try await store.recoverActiveWorkoutSession() else {
                healthLog.info("Wiederherstellung: keine aktive Workout-Session beim System")
                return
            }
            // Inzwischen eine neue Aufzeichnung gestartet (z. B. Demo-Fahrt)? Dann nichts anfassen.
            guard !isRecording else { return }
            healthLog.info("Wiederherstellung: aktive Workout-Session gefunden (Status \(s.state.rawValue), Start \(s.startDate?.formatted() ?? "-", privacy: .public)); wird beendet und verworfen")
            let b = s.associatedWorkoutBuilder()
            s.end()
            var waited = 0
            while s.state != .ended && waited < 30 {
                try? await Task.sleep(for: .milliseconds(100))
                waited += 1
            }
            b.discardWorkout()
        } catch {
            healthLog.info("Wiederherstellung: recoverActiveWorkoutSession: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Schreibt ein Training aus dem Verlauf als HKWorkout in Apple Health (Wiederherstellung oder Nachtragen).
    ///
    /// 1. Gibt es schon ein Training dieser App, das sich mit [Start − 5 min, Ende + 5 min] überschneidet, passiert
    ///    nichts (Erfolg, `.alreadyPresent`). So entsteht nie ein zweites Training und es werden nie Werte eines
    ///    vorhandenen Trainings gelöscht.
    /// 2. Sonst werden verwaiste Einzelwerte dieser App (Puls, aktive Energie, Ruderdistanz), die ganz in
    ///    [Start − 1 min, Ende + 2 min] liegen, gelöscht – nur Quelle = diese App; Werte anderer Apps und Geräte
    ///    bleiben unberührt.
    /// 3. Dann baut ein `HKWorkoutBuilder` (ohne Session) das Training aus der Zeitreihe: Puls je Sample, Distanz und
    ///    Energie als Zuwächse in Abschnitten von ca. 10 s. `finishWorkout` ohne Ergebnis gilt als Fehler.
    ///
    /// Danach die Strecke als Route (HKWorkoutRoute): beim neuen Training immer, beim schon vorhandenen nur, wenn es
    /// noch keine Route hat (`addRouteIfMissing`). Fehler bei der Route ändern das Ergebnis nicht (`lastRouteNote`).
    func saveWorkout(from record: WorkoutRecord, reason: HealthBackfillReason) async -> HealthBackfillResult {
        lastRouteNote = nil
        refreshStatus()
        guard status == .authorized else {
            let msg = status == .unavailable ? "Apple Health ist auf diesem Gerät nicht verfügbar."
                : "Apple Health ist nicht verbunden (Einstellungen)."
            healthLog.error("Nachtragen: \(msg, privacy: .public)")
            return .failed(msg)
        }
        let start = record.header.startDate
        var end = record.header.endDate
        if end <= start {
            end = start.addingTimeInterval(max(record.summary.totalDuration, record.samples.last?.time ?? 0, 1))
        }
        let label = "\(Int(record.summary.distance)) m ab \(start.formatted()) (\(reason.rawValue))"

        // 1. Vorhandenes Training dieser App?
        do {
            let existing = try await workoutsFromThisApp(overlapping: start.addingTimeInterval(-5 * 60),
                                                         end.addingTimeInterval(5 * 60))
            if let w = existing.first {
                healthLog.info("Nachtragen \(label, privacy: .public): Training schon vorhanden (\(w.uuid.uuidString, privacy: .public), \(w.startDate.formatted(), privacy: .public), \(Int(w.duration), privacy: .public) s) – nichts zu tun")
                if let match = matchingWorkout(for: record, in: existing) {
                    let route = await addRouteIfMissing(for: record, to: match)
                    lastRouteNote = route.note
                    healthLog.info("Nachtragen \(label, privacy: .public): \(route.logText, privacy: .public)")
                }
                return .alreadyPresent
            }
        } catch {
            healthLog.error("Nachtragen \(label, privacy: .public): Abfrage fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            return .failed("Health-Abfrage: \(error.localizedDescription)")
        }

        // 2. Verwaiste Einzelwerte dieser App löschen
        do {
            let n = try await deleteOrphanSamples(from: start.addingTimeInterval(-60), to: end.addingTimeInterval(120))
            healthLog.info("Nachtragen \(label, privacy: .public): \(n, privacy: .public) verwaiste Einzelwerte gelöscht")
        } catch {
            healthLog.error("Nachtragen \(label, privacy: .public): Löschen fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            return .failed("Health-Löschen: \(error.localizedDescription)")
        }

        // 3. Training bauen
        let config = HKWorkoutConfiguration()
        config.activityType = .rowing
        config.locationType = .indoor
        let b = HKWorkoutBuilder(healthStore: store, configuration: config, device: HKDevice.local())
        do {
            try await b.beginCollection(at: start)
            let samples = makeSamples(for: record, start: start, end: end)
            if !samples.isEmpty { try await b.addSamples(samples) }
            var meta: [String: Any] = [
                HKMetadataKeyIndoorWorkout: true,
                HKMetadataKeyExternalUUID: record.id.uuidString,
                reason.rawValue: true,
                "RowCoachAvgStrokeRate": record.summary.averageStrokeRate,
                "RowCoachAvgPower": Double(record.summary.averagePower),
                "RowCoachAvgPace500m": record.summary.averagePace,
            ]
            if let title = record.header.courseTitle { meta["RowCoachCourse"] = title }
            try await b.addMetadata(meta)
            try await b.endCollection(at: end)
            guard let workout = try await b.finishWorkout() else {
                b.discardWorkout()
                healthLog.error("Nachtragen \(label, privacy: .public): finishWorkout lieferte kein Training")
                return .failed("Apple Health hat kein Training angelegt.")
            }
            healthLog.info("Nachtragen \(label, privacy: .public): gespeichert \(workout.uuid.uuidString, privacy: .public), \(Int(workout.duration), privacy: .public) s, \(samples.count, privacy: .public) Werte")
            lastSavedWorkout = Date()
            let route = await addRoute(for: record, to: workout)
            lastRouteNote = route.note
            healthLog.info("Nachtragen \(label, privacy: .public): \(route.logText, privacy: .public)")
            return .saved
        } catch {
            b.discardWorkout()
            healthLog.error("Nachtragen \(label, privacy: .public): Speichern fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            return .failed("Health-Speichern: \(error.localizedDescription)")
        }
    }

    /// Trainings dieser App, die sich mit [from, to] überschneiden. Abgefragt wird grosszügig (± 6 h), die
    /// Überschneidung prüft der Code selbst – unabhängig davon, wie HealthKit Randfälle im Prädikat behandelt.
    private func workoutsFromThisApp(overlapping from: Date, _ to: Date) async throws -> [HKWorkout] {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(from: HKSource.default()),
            HKQuery.predicateForSamples(withStart: from.addingTimeInterval(-6 * 3600), end: to.addingTimeInterval(6 * 3600)),
        ])
        let descriptor = HKSampleQueryDescriptor(predicates: [.workout(predicate)],
                                                 sortDescriptors: [SortDescriptor(\.startDate)],
                                                 limit: 200)
        let workouts = try await descriptor.result(for: store)
        return workouts.filter { $0.startDate <= to && $0.endDate >= from }
    }

    /// Löscht Puls, aktive Energie und Ruderdistanz dieser App, die ganz im Zeitfenster liegen. Gibt die Anzahl zurück.
    /// Nur Objekte, die die Abfrage mit Quelle = diese App geliefert hat, werden gelöscht.
    private func deleteOrphanSamples(from: Date, to: Date) async throws -> Int {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(from: HKSource.default()),
            HKQuery.predicateForSamples(withStart: from, end: to, options: [.strictStartDate, .strictEndDate]),
        ])
        var total = 0
        for type in [hrType, energyType, distanceType] {
            let descriptor = HKSampleQueryDescriptor(predicates: [.quantitySample(type: type, predicate: predicate)],
                                                     sortDescriptors: [])
            let found = try await descriptor.result(for: store)
            guard !found.isEmpty else { continue }
            let objects: [HKObject] = found
            try await store.delete(objects)
            total += found.count
            healthLog.info("Nachtragen: \(found.count, privacy: .public) × \(type.identifier, privacy: .public) gelöscht")
        }
        return total
    }

    /// Einzelwerte für den Builder: Puls je Sample, Distanz und Energie als Zuwächse je ca. 10 s.
    private func makeSamples(for record: WorkoutRecord, start: Date, end: Date) -> [HKSample] {
        var result: [HKSample] = []
        let bpm = HKUnit.count().unitDivided(by: .minute())
        for s in record.samples {
            guard let hr = s.heartRate, hr > 0 else { continue }
            let t = min(start.addingTimeInterval(max(s.time, 0)), end)
            result.append(HKQuantitySample(type: hrType, quantity: HKQuantity(unit: bpm, doubleValue: Double(hr)),
                                           start: t, end: t))
        }
        let blocks = WorkoutIncrements.blocks(samples: record.samples, totalDistance: record.summary.distance,
                                              totalEnergy: Double(record.summary.calories))
        for blk in blocks {
            let from = min(start.addingTimeInterval(max(blk.start, 0)), end)
            let to = min(max(start.addingTimeInterval(blk.end), from), end)
            if blk.distance > 0 {
                result.append(HKQuantitySample(type: distanceType,
                                               quantity: HKQuantity(unit: .meter(), doubleValue: blk.distance),
                                               start: from, end: to))
            }
            if blk.energy > 0 {
                result.append(HKQuantitySample(type: energyType,
                                               quantity: HKQuantity(unit: .kilocalorie(), doubleValue: blk.energy),
                                               start: from, end: to))
            }
        }
        return result
    }

    // MARK: Strecke als Route (HKWorkoutRoute)

    /// Testbetrieb (`-backfillRoutes 1`): Hat das Training dieser Fahrt in Apple Health noch keine Route, wird sie
    /// nachgetragen. Das Training selbst wird nicht angefasst; fehlt es in Health, passiert nichts.
    func backfillRoute(for record: WorkoutRecord) async -> HealthRouteResult {
        lastRouteNote = nil
        refreshStatus()
        guard status == .authorized else { return .notApplicable("Apple Health nicht verbunden") }
        let start = record.header.startDate
        var end = record.header.endDate
        if end <= start { end = start.addingTimeInterval(max(record.summary.totalDuration, 1)) }
        do {
            let existing = try await workoutsFromThisApp(overlapping: start.addingTimeInterval(-5 * 60),
                                                         end.addingTimeInterval(5 * 60))
            guard let w = matchingWorkout(for: record, in: existing) else {
                return .notApplicable("kein passendes Training von RowCoach in Apple Health")
            }
            let route = await addRouteIfMissing(for: record, to: w)
            lastRouteNote = route.note
            return route
        } catch {
            return .failed("Health-Abfrage: \(error.localizedDescription)")
        }
    }

    /// Das Training in Health, das zu dieser Fahrt gehört: gleiche externe ID (nachgetragen) oder Start auf ±2 min.
    private func matchingWorkout(for record: WorkoutRecord, in workouts: [HKWorkout]) -> HKWorkout? {
        let id = record.id.uuidString
        if let w = workouts.first(where: { ($0.metadata?[HKMetadataKeyExternalUUID] as? String) == id }) { return w }
        let start = record.header.startDate
        return workouts
            .filter { abs($0.startDate.timeIntervalSince(start)) <= 120 }
            .min { abs($0.startDate.timeIntervalSince(start)) < abs($1.startDate.timeIntervalSince(start)) }
    }

    /// Route nur schreiben, wenn das Training noch keine hat (nie doppelt).
    private func addRouteIfMissing(for record: WorkoutRecord, to workout: HKWorkout) async -> HealthRouteResult {
        guard store.authorizationStatus(for: routeType) == .sharingAuthorized else { return .notAuthorized }
        do {
            if let n = try await routePointCount(for: workout) { return .alreadyPresent(n) }
        } catch {
            return .failed("Abfrage der Route: \(error.localizedDescription)")
        }
        return await addRoute(for: record, to: workout)
    }

    /// Punkte aller Routen, die mit dem Training verbunden sind; nil = keine Route
    private func routePointCount(for workout: HKWorkout) async throws -> Int? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workoutRoute(HKQuery.predicateForObjects(from: workout))],
            sortDescriptors: [])
        let routes = try await descriptor.result(for: store)
        guard !routes.isEmpty else { return nil }
        return routes.reduce(0) { $0 + $1.count }
    }

    /// Rechnet die Route aus dem Training (`RoutePoints`) und schreibt sie mit einem `HKWorkoutRouteBuilder`
    /// zum gespeicherten Training: Punkte in Blöcken einfügen, dann `finishRoute(with:metadata:)`.
    private func addRoute(for record: WorkoutRecord, to workout: HKWorkout) async -> HealthRouteResult {
        guard store.authorizationStatus(for: routeType) == .sharingAuthorized else { return .notAuthorized }
        guard let courseId = record.header.courseId else { return .notApplicable("Training ohne Strecke") }
        guard let course = Self.bundledCourse(id: courseId) else {
            return .notApplicable("Strecke \(courseId) nicht im App-Bundle")
        }
        guard RoutePoints.hasGeoreference(course) else {
            return .notApplicable("Strecke \(courseId) ohne Landeskoordinaten")
        }
        let planEnd = record.header.workoutPlanId.flatMap { PlanLibrary.plan(id: $0)?.totalDistance }
        let points = RoutePoints.make(record: record, course: course, planEndDistance: planEnd)
        guard !points.isEmpty else { return .notApplicable("keine Punkte") }

        let base = record.header.startDate
        let first = workout.startDate, last = workout.endDate
        let locations = points.map { p -> CLLocation in
            let t = min(max(base.addingTimeInterval(p.time), first), last)
            return CLLocation(coordinate: CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude),
                              altitude: p.altitude, horizontalAccuracy: 5, verticalAccuracy: 5,
                              course: p.course, speed: p.speed, timestamp: t)
        }
        // device nil: die App erzeugt die Positionen selbst (Apple-Doku zu init(healthStore:device:))
        let builder = HKWorkoutRouteBuilder(healthStore: store, device: nil)
        do {
            var i = 0
            while i < locations.count {
                let chunk = Array(locations[i..<min(i + 500, locations.count)])
                try await builder.insertRouteData(chunk)
                i += 500
            }
            let route = try await builder.finishRoute(with: workout, metadata: [
                Self.routeVirtualKey: true,
                Self.routeCourseKey: courseId,
            ])
            return .written(route.count)
        } catch {
            healthLog.error("Route zu \(workout.uuid.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .failed(error.localizedDescription)
        }
    }

    /// Strecke aus dem App-Bundle (`Courses/<id>/course.json`, wie `CourseLibrary`)
    static func bundledCourse(id: String) -> Course? {
        guard let base = Bundle.main.url(forResource: "Courses", withExtension: nil) else { return nil }
        let file = base.appendingPathComponent(id, isDirectory: true).appendingPathComponent("course.json")
        if let data = try? Data(contentsOf: file), let course = try? Course.decode(data), course.id == id {
            return course
        }
        // Ordnername weicht ab: alle Pakete durchsuchen
        let dirs = (try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil,
                                                                 options: [.skipsHiddenFiles])) ?? []
        for dir in dirs {
            let f = dir.appendingPathComponent("course.json")
            if let data = try? Data(contentsOf: f), let course = try? Course.decode(data), course.id == id {
                return course
            }
        }
        return nil
    }

    /// Bricht ab, ohne etwas zu speichern.
    func discard() {
        session?.end()
        builder?.discardWorkout()
        isRecording = false
        session = nil; builder = nil; lastFlush = .distantPast
    }
}
