import SwiftUI
import RowCoachKit

/// Einstellungen: Apple Health verbinden, Profil, Fahrt, Entwickler (Simulator, Diagnose), Quellen.
struct SettingsView: View {
    @Environment(HealthService.self) private var health
    @Environment(SimulatorDevice.self) private var simulator
    @Environment(\.openURL) private var openURL
    @AppStorage("profile.maxHR") private var maxHR = 185
    @AppStorage("profile.restHR") private var restHR = 55
    @AppStorage(SessionController.pauseAfterKey) private var pauseAfter = 6.0
    @AppStorage(TrainingSettings.best2kKey) private var best2k = PaceTargets.defaultBest2k
    @AppStorage(TrainingSettings.countdownSoundKey) private var countdownSound = true

    var body: some View {
        @Bindable var simulator = simulator
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

                Section {
                    Stepper("Maximalpuls: \(maxHR)", value: $maxHR, in: 120...220)
                    Stepper("Ruhepuls: \(restHR)", value: $restHR, in: 30...100)
                    zonePreview
                    Stepper("2000 m Bestzeit: \(Format.duration(best2k))", value: $best2k, in: 330...720, step: 1)
                } header: {
                    Text("Profil (für Pulszonen und Tempo-Ziele)")
                } footer: {
                    Text("Zonen nach Herzfrequenzreserve: Zone 1 ab 50 %, Zone 2 ab 60 %, Zone 3 ab 70 %, Zone 4 ab 80 %, Zone 5 ab 90 %. Die Tempo-Ziele der Trainings richten sich nach der 2000-m-Bestzeit (\(Format.pace(PaceTargets.basePace500(best2k: best2k))) /500 m).")
                }

                Section {
                    Toggle("Ton beim Countdown", isOn: $countdownSound)
                } header: {
                    Text("Training")
                } footer: {
                    Text("Leiser Systemton bei 3, 2, 1 und beim Phasenwechsel; folgt der Systemlautstärke.")
                }

                Section("Fahrt") {
                    Stepper("Pause nach \(Int(pauseAfter)) s ohne Schlag", value: $pauseAfter, in: 3...30, step: 1)
                }

                Section {
                    Toggle("Simulator statt PM5", isOn: Binding(
                        get: { simulator.isRunning },
                        set: { $0 ? simulator.start() : simulator.stop() }))
                    if simulator.isRunning {
                        Stepper("Tempo: \(Format.pace(simulator.pace)) /500 m", value: $simulator.pace, in: 90...200, step: 1)
                        Stepper("Schlagzahl: \(simulator.strokeRate) /min", value: $simulator.strokeRate, in: 14...40)
                        Toggle("Rudert (aus = Pause testen)", isOn: $simulator.rowing)
                        Toggle("Puls senden", isOn: $simulator.sendHeartRate)
                        Button("PM5 neu starten (Distanz auf 0)") { simulator.resetMonitor() }
                    } else {
                        Stepper("Startdistanz am PM5: \(Int(simulator.startDistance)) m",
                                value: $simulator.startDistance, in: 0...5000, step: 250)
                    }
                    NavigationLink("Diagnose (Live-Werte)") { LiveView() }
                } header: {
                    Text("Entwickler")
                } footer: {
                    Text("Der Simulator liefert dieselben Daten wie PM5 und Pulsgurt. Solange er läuft, werden echte Geräte ignoriert.")
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

    private var zonePreview: some View {
        let z = HeartRateZones(maxHR: maxHR, restHR: restHR)
        return HStack(spacing: 6) {
            ForEach(1...HeartRateZones.count, id: \.self) { i in
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 3).fill(Theme.zoneColor(i)).frame(height: 6)
                    Text("Z\(i) ≥\(z.lowerBound(zone: i))").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
    }
}
