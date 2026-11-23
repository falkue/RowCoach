import SwiftUI

/// Einstellungen: Apple Health verbinden, Profil, Quellen.
struct SettingsView: View {
    @Environment(HealthService.self) private var health
    @Environment(\.openURL) private var openURL
    @AppStorage("profile.maxHR") private var maxHR = 185
    @AppStorage("profile.restHR") private var restHR = 55

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Status", value: health.status.rawValue)
                    if health.status != .authorized && health.status != .unavailable {
                        Button("Apple Health verbinden") { Task { await health.connect() } }
                    }
                    Button("Health-Einstellungen öffnen") {
                        if let u = URL(string: "x-apple-health://") { openURL(u) }
                    }
                    if let e = health.lastError { Text(e).font(.footnote).foregroundStyle(.red) }
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("RowCoach schreibt nach jeder Einheit ein Training „Rudern (indoor)“ mit Dauer, Distanz, aktiven Kalorien und Puls.")
                }

                Section("Profil (für Pulszonen)") {
                    Stepper("Maximalpuls: \(maxHR)", value: $maxHR, in: 120...220)
                    Stepper("Ruhepuls: \(restHR)", value: $restHR, in: 30...100)
                }

                Section("Quellen und Lizenzen") {
                    Text("Landschaftsdaten: © swisstopo (swissALTI3D, SWISSIMAGE, swissBUILDINGS3D 3.0), Open Government Data.")
                    Text("PM5-Protokoll nach Concept2 „PM CSAFE Communication Definition“. Concept2 und PM5 sind Marken von Concept2, Inc.; RowCoach ist kein Produkt von Concept2.")
                }
                .font(.footnote)
            }
            .navigationTitle("Einstellungen")
            .onAppear { health.refreshStatus() }
        }
    }
}
