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
    @AppStorage(HomeSettings.weeklyGoalKey) private var weeklyGoal = HomeSettings.defaultWeeklyGoal
    @State private var profileConfirmed = 0

    private var profileIsDefault: Bool {
        _ = (maxHR, restHR, best2k, profileConfirmed)
        return ProfileState.isDefault
    }
    @AppStorage(TrafficSettings.enabledKey) private var trafficEnabled = true
    @AppStorage(TrafficSettings.densityKey) private var trafficDensity = TrafficDensity.normal.rawValue
    @AppStorage(SunSettings.storageKey) private var sunPreset = SunPreset.summerAfternoon.rawValue

    var body: some View {
        @Bindable var simulator = simulator
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Status", value: health.status.rawValue)
                    if health.status != .authorized && health.status != .unavailable {
                        Button("Apple Health verbinden") { Task { await health.connect() } }
                    }
                    if health.status == .authorized {
                        LabeledContent("Strecke als Route", value: health.routeStatus.rawValue)
                        if health.routeStatus == .notDetermined {
                            // Fragt alle Typen erneut an; der Dialog zeigt nur die neue Routen-Freigabe
                            Button("Strecke als Route freigeben") { Task { await health.connect() } }
                        }
                        LabeledContent("Belastung", value: health.effortStatus.rawValue)
                        LabeledContent("Vorschlag der App als Schätzung", value: health.estimatedEffortStatus.rawValue)
                        if health.effortStatus == .notDetermined || health.estimatedEffortStatus == .notDetermined {
                            // Wie bei der Route: fragt alle Typen erneut an; der Dialog zeigt nur die neuen Freigaben
                            Button("Belastung freigeben") { Task { await health.connect() } }
                        }
                    }
                    Button("Health-Einstellungen öffnen") {
                        if let u = URL(string: "x-apple-health://") { openURL(u) }
                    }
                    if let e = health.lastError { Text(e).font(.footnote).foregroundStyle(.red) }
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("RowCoach schreibt nach jeder Einheit ein Training „Rudern (indoor)“ mit Dauer, Distanz, aktiven Kalorien und Puls. Mit der Routen-Freigabe kommt die gefahrene Strecke dazu, die Health und Fitness als Karte zeigen. Die Route ist virtuell: Sie folgt der Strecke auf dem Bildschirm, nicht einem GPS-Signal. Die Belastung (1–10, in Health „Anstrengung“) fragt RowCoach nach jeder Fahrt ab; der Vorschlag der App geht als geschätzte Belastung mit.")
                }

                Section {
                    Stepper("Maximalpuls: \(maxHR)", value: $maxHR, in: 120...220)
                    Stepper("Ruhepuls: \(restHR)", value: $restHR, in: 30...100)
                    zonePreview
                    Stepper("2000 m Bestzeit: \(Format.duration(best2k))", value: $best2k, in: 330...720, step: 1)
                    if profileIsDefault {
                        // Werte übernehmen, auch wenn sie den Voreinstellungen entsprechen (Badge am Tab verschwindet)
                        Button("Werte stimmen") {
                            let d = UserDefaults.standard
                            d.set(maxHR, forKey: ProfileState.maxHRKey)
                            d.set(restHR, forKey: ProfileState.restHRKey)
                            d.set(best2k, forKey: TrainingSettings.best2kKey)
                            profileConfirmed += 1
                        }
                    }
                } header: {
                    Text("Profil (für Pulszonen und Tempo-Ziele)")
                } footer: {
                    Text("Zonen nach Herzfrequenzreserve: Zone 1 ab 50 %, Zone 2 ab 60 %, Zone 3 ab 70 %, Zone 4 ab 80 %, Zone 5 ab 90 %. Die Tempo-Ziele der Trainings richten sich nach der 2000-m-Bestzeit (\(Format.pace(PaceTargets.basePace500(best2k: best2k))) /500 m).")
                }

                Section {
                    Toggle("Ton beim Countdown", isOn: $countdownSound)
                    Stepper("Wochenziel: \(weeklyGoal) Fahrten", value: $weeklyGoal, in: 1...7)
                } header: {
                    Text("Training")
                } footer: {
                    Text("Leiser Systemton bei 3, 2, 1 und beim Phasenwechsel; folgt der Systemlautstärke. Das Wochenziel zählt für die Wochenserie auf dem Startbildschirm (mit einem Joker für eine verpasste Woche).")
                }

                Section {
                    Stepper("Pause nach \(Int(pauseAfter)) s ohne Schlag", value: $pauseAfter, in: 3...30, step: 1)
                    Toggle("Andere Boote auf dem Wasser", isOn: $trafficEnabled)
                    if trafficEnabled {
                        Picker("Dichte", selection: $trafficDensity) {
                            Text("wenig").tag(TrafficDensity.low.rawValue)
                            Text("normal").tag(TrafficDensity.normal.rawValue)
                        }
                        .pickerStyle(.segmented)
                    }
                } header: {
                    Text("Rudern")
                } footer: {
                    Text("Andere Ruderer überholen dich oder werden überholt, Schiffe fahren in sicherem Abstand vorbei. Gilt ab der nächsten Fahrt.")
                }

                Section {
                    Picker("Sonnenstand", selection: $sunPreset) {
                        ForEach(SunPreset.allCases) { p in
                            Text(SunSettings.label(p)).tag(p.rawValue)
                        }
                    }
                } header: {
                    Text("Darstellung")
                } footer: {
                    Text("Sommernachmittag passt genau zu den vorgerechneten Schatten der Gebäude. „Jetzt“ stellt die Sonne nach Datum und Uhrzeit am Ort der Strecke (nachts Abenddämmerung); Morgen, Mittag und Abend zeigen einen Sommertag. Bei diesen Ständen nutzt die Szene Gebäude ohne vorgerechnete Sonnenschatten, falls das Kartenpaket sie mitbringt. Gilt ab der nächsten Fahrt.")
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

                Section {
                    HStack(spacing: 14) {
                        Image("Logo")
                            .resizable()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 13))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("RowCoach").font(.headline)
                            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")")
                                .font(.footnote).foregroundStyle(.secondary)
                            Text("Open Source, für den Concept2 RowErg mit PM5").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Über RowCoach")
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
