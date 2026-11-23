import SwiftUI
import RowCoachKit

@main
struct RowCoachApp: App {
    @State private var devices = DeviceManager()
    @State private var health = HealthService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(devices)
                .environment(health)
                .onAppear { wire() }
        }
    }

    /// Verbindet Gerätedaten mit der Health-Aufzeichnung.
    private func wire() {
        devices.onHeartRate = { [health] m, date in health.record(heartRate: m, at: date) }
        devices.onPM5Message = { [devices, health] _, date in health.record(snapshot: devices.snapshot, at: date) }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Live", systemImage: "gauge.with.dots.needle.67percent") { LiveView() }
            Tab("Geräte", systemImage: "antenna.radiowaves.left.and.right") { DevicesView() }
            Tab("Einstellungen", systemImage: "gearshape") { SettingsView() }
        }
    }
}
