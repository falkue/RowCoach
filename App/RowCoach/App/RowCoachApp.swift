import SwiftUI
import SwiftData
import RowCoachKit

@main
struct RowCoachApp: App {
    @State private var devices: DeviceManager
    @State private var health: HealthService
    @State private var simulator: SimulatorDevice
    @State private var session: SessionController
    @State private var library: CourseLibrary
    private let container: ModelContainer

    init() {
        let devices = DeviceManager()
        let health = HealthService()
        let container = WorkoutStore.makeContainer()
        let session = SessionController(devices: devices, health: health, store: WorkoutStore(container: container))
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
        _library = State(initialValue: CourseLibrary())
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
                .modelContainer(container)
        }
    }
}

/// Hauptnavigation: Rudern (Streckenwahl → Rudern), Verlauf, Geräte, Einstellungen (mit Diagnose).
struct RootView: View {
    var body: some View {
        TabView {
            Tab("Rudern", systemImage: "figure.rower") { RowingTab() }
            Tab("Verlauf", systemImage: "clock.arrow.circlepath") { HistoryView() }
            Tab("Geräte", systemImage: "antenna.radiowaves.left.and.right") { DevicesView() }
            Tab("Einstellungen", systemImage: "gearshape") { SettingsView() }
        }
    }
}
