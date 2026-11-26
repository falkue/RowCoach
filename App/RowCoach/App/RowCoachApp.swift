import SwiftUI
import os
import SwiftData
import RowCoachKit

@main
struct RowCoachApp: App {
    @State private var devices: DeviceManager
    @State private var health: HealthService
    @State private var simulator: SimulatorDevice
    @State private var session: SessionController
    @State private var library: CourseLibrary
    @State private var downloads: CourseDownloads
    @State private var recovery: WorkoutRecovery
    @Environment(\.scenePhase) private var scenePhase
    private let container: ModelContainer

    init() {
        let devices = DeviceManager()
        let health = HealthService()
        let container = WorkoutStore.makeContainer()
        let store = WorkoutStore(container: container)
        let checkpoints = CheckpointStore()
        let session = SessionController(devices: devices, health: health, store: store, checkpoints: checkpoints)
        // Unterbrochene Fahrt (Akku leer, App beendet, Absturz)? Sicherungspunkt übernehmen, bevor eine neue Fahrt startet.
        let recovery = WorkoutRecovery(store: store, health: health, checkpoints: checkpoints)
        recovery.claim()
        let library = CourseLibrary()
        // Testbetrieb: `-seedDemoHistory 1` legt Beispieltrainings an, `-clearDemoHistory 1` entfernt sie (nie nach Health)
        DemoHistory.applyLaunchArguments(store: store, courses: library.courses)
        // Konto & Synchronisation (docs/SYNC.md): tut ohne Anmeldung nichts, keine Netzanfrage
        SyncController.shared.attach(store: store)
        // Gerätedaten → Session/Health. CoreBluetooth und Simulator liefern auf dem Hauptthread.
        devices.onHeartRate = { m, date in
            MainActor.assumeIsolated { session.handleHeartRate(m, at: date) }
        }
        devices.onPM5Message = { m, date in
            MainActor.assumeIsolated { session.handlePM5(m, at: date) }
        }
        _devices = State(initialValue: devices)
        _health = State(initialValue: health)
        _simulator = State(initialValue: SimulatorDevice(devices: devices))
        _session = State(initialValue: session)
        _library = State(initialValue: library)
        _downloads = State(initialValue: CourseDownloads(library: library))
        _recovery = State(initialValue: recovery)
        self.container = container
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(devices)
                .environment(health)
                .environment(simulator)
                .environment(session)
                .environment(library)
                .environment(downloads)
                .environment(recovery)
                .modelContainer(container)
                .task {
                    // Unterbrochene Fahrt übernehmen und in Apple Health schreiben.
                    // Testbetrieb: `-backfillHealth 1` trägt danach die echten Trainings der letzten 7 Tage nach,
                    // die noch kein Training in Apple Health haben (Ergebnis im Protokoll, Kategorie Health).
                    await recovery.run(backfill: UserDefaults.standard.bool(forKey: "backfillHealth"))
                    // Testbetrieb: `-healthReport 1` schreibt Freigaben und RowCoach-Trainings ins Protokoll
                    if UserDefaults.standard.bool(forKey: "healthReport") { await health.logReport() }
                }
                .onChange(of: scenePhase) { _, phase in
                    Logger(subsystem: "com.falkue.RowCoach", category: "Session").info("App-Zustand: \(String(describing: phase), privacy: .public)")
                    // Beim Wechsel in den Hintergrund den Stand sofort sichern (danach kann iOS die App beenden)
                    if phase == .background { session.writeCheckpointNow() }
                    if phase == .active { SyncController.shared.appBecameActive() }
                }
                // Rückkehr von „Mit Google anmelden“
                .onOpenURL { url in SyncController.shared.handleOpenURL(url) }
        }
    }
}
