import SwiftUI
import RowCoachKit

/// Einstellungen als Sheet (Zahnrad in Kopf bzw. Toolbar): Profil, Training (Ansagen, Countdown-Ton, Wochenziel),
/// Rudern, Darstellung, Apple Health, Über, Quellen. Der Entwicklerbereich (Simulator, Diagnose) gibt es nur in
/// Debug-Builds.
struct SettingsView: View {
    @Environment(HealthService.self) private var health
    @Environment(SimulatorDevice.self) private var simulator
    @Environment(CourseLibrary.self) private var library
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @AppStorage("profile.maxHR") private var maxHR = 185
    @AppStorage("profile.restHR") private var restHR = 55
    @AppStorage(SessionController.pauseAfterKey) private var pauseAfter = 6.0
    @AppStorage(TrainingSettings.best2kKey) private var best2k = PaceTargets.defaultBest2k
    @AppStorage(TrainingSettings.countdownSoundKey) private var countdownSound = true
    @AppStorage(TrainingSettings.spokenCuesKey) private var spokenCues = true
    @AppStorage(HomeSettings.weeklyGoalKey) private var weeklyGoal = HomeSettings.defaultWeeklyGoal
    @AppStorage(TrafficSettings.enabledKey) private var trafficEnabled = true
    @AppStorage(TrafficSettings.densityKey) private var trafficDensity = TrafficDensity.normal.rawValue
    @AppStorage(SunSettings.storageKey) private var sunPreset = SunPreset.summerAfternoon.rawValue
    @AppStorage(HistorySettings.showSimulatedKey) private var showSimulated = false
    @AppStorage(CourseDownloads.serverKey) private var courseServer = ""
    @State private var profileConfirmed = 0
    @State private var confirmReset = false

    private var profileIsDefault: Bool {
        _ = (maxHR, restHR, best2k, profileConfirmed)
        return ProfileState.isDefault
    }

    /// Gemeinsame Quellenliste aus allen Kartenpaketen (Feld `attribution`)
    private var mapSources: [String] {
        AttributionList.merge(library.courses.map(\.attribution)).map(CourseText.localized)
    }

    var body: some View {
        NavigationStack {
            Form {
                profileSection
                trainingSection
                rowingSection
                displaySection
                healthSection
                #if DEBUG
                developerSection
                #endif
                aboutSection
                sourcesSection
            }
            .scrollContentBackground(.hidden)
            .dsPageBackground()
            .navigationTitle(Text("Einstellungen"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.bg, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .onAppear { health.refreshStatus() }
        }
    }

    // MARK: Abschnitte

    private var profileSection: some View {
        Section {
            ProfileFields()
            zonePreview
            if profileIsDefault {
                Button("Werte stimmen") {
                    ProfileState.confirmCurrentValues()
                    profileConfirmed += 1
                }
                .foregroundStyle(Theme.link)
            }
        } header: {
            Text("Profil")
        } footer: {
            Text("Pulszonen nach Herzfrequenzreserve, Tempo-Ziele nach der 2000-m-Bestzeit (\(Format.duration(PaceTargets.basePace500(best2k: best2k))) /500 m).")
        }
    }

    private var trainingSection: some View {
        Section {
            Toggle("Gesprochene Ansagen", isOn: $spokenCues)
            Toggle("Ton beim Countdown", isOn: $countdownSound)
            Stepper("Wochenziel: \(weeklyGoal) Fahrten", value: $weeklyGoal, in: 1...7)
        } header: {
            Text("Training")
        } footer: {
            Text("Ansagen vor und bei jedem Phasenwechsel, zur Halbzeit und 500 m vor dem Ziel; Musik wird dabei leiser. Auf dem iPhone zusätzlich eine kurze Vibration.")
        }
    }

    private var rowingSection: some View {
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
            Text("Gilt ab der nächsten Fahrt.")
        }
    }

    private var displaySection: some View {
        Section {
            Picker("Sonnenstand", selection: $sunPreset) {
                ForEach(SunPreset.allCases) { p in
                    Text(SunSettings.label(p)).tag(p.rawValue)
                }
            }
        } header: {
            Text("Darstellung")
        } footer: {
            Text("Sommernachmittag passt zu den vorgerechneten Schatten der Gebäude. Gilt ab der nächsten Fahrt.")
        }
    }

    private var healthSection: some View {
        Section {
            LabeledContent("Status", value: health.status.title)
            if health.status != .authorized && health.status != .unavailable {
                Button("Apple Health verbinden") { Task { await health.connect() } }
                    .foregroundStyle(Theme.link)
            }
            if health.status == .authorized {
                LabeledContent("Strecke als Route", value: health.routeStatus.title)
                LabeledContent("Anstrengung", value: health.effortStatus.title)
                LabeledContent("Vorschlag der App", value: health.estimatedEffortStatus.title)
                if health.routeStatus == .notDetermined || health.effortStatus == .notDetermined
                    || health.estimatedEffortStatus == .notDetermined {
                    // Fragt alle offenen Typen in einem Dialog an (Route, eigene und geschätzte Anstrengung)
                    Button("Weitere Freigaben erteilen") { Task { await health.connect() } }
                        .foregroundStyle(Theme.link)
                }
            }
            Button("Health-Einstellungen öffnen") {
                if let u = URL(string: "x-apple-health://") { openURL(u) }
            }
            .foregroundStyle(Theme.link)
            if let e = health.lastError { Text(e).font(.footnote).foregroundStyle(Theme.bad) }
        } header: {
            Text("Apple Health")
        } footer: {
            Text("Jede Fahrt als Training „Rudern (indoor)“ mit Puls, Distanz und – falls freigegeben – der Strecke als virtuelle Route. Dazu die Anstrengung (1–10) und der Vorschlag der App als geschätzte Anstrengung.")
        }
    }

    #if DEBUG
    private var developerSection: some View {
        @Bindable var simulator = simulator
        return Section {
            Toggle("Simulator statt PM5", isOn: Binding(
                get: { simulator.isRunning },
                set: { $0 ? simulator.start() : simulator.stop() }))
            if simulator.isRunning {
                Stepper("Tempo: \(Format.duration(simulator.pace)) /500 m", value: $simulator.pace, in: 90...200, step: 1)
                Stepper("Schlagzahl: \(simulator.strokeRate) /min", value: $simulator.strokeRate, in: 14...40)
                Toggle("Rudert (aus = Pause testen)", isOn: $simulator.rowing)
                Toggle("Puls senden", isOn: $simulator.sendHeartRate)
                Button("PM5 neu starten (Distanz auf 0)", role: .destructive) { confirmReset = true }
                    .confirmationDialog("Simulierten PM5 neu starten?", isPresented: $confirmReset,
                                        titleVisibility: .visible) {
                        Button("Neu starten", role: .destructive) { simulator.resetMonitor() }
                        Button("Abbrechen", role: .cancel) {}
                    }
            } else {
                Stepper("Startdistanz am PM5: \(Int(simulator.startDistance)) m",
                        value: $simulator.startDistance, in: 0...5000, step: 250)
            }
            Toggle("Simulatorfahrten im Verlauf zeigen", isOn: $showSimulated)
            // Strecken-Server (bis Firebase steht, z. B. ein Testserver mit dist/courses von publish_catalog.py)
            TextField("Strecken-Server (URL)", text: $courseServer)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            NavigationLink("Diagnose (Live-Werte)") { LiveView() }
        } header: {
            Text("Entwickler (nur Debug-Build)")
        } footer: {
            Text("Der Simulator liefert dieselben Daten wie PM5 und Pulsgurt. Solange er läuft, werden echte Geräte ignoriert.")
        }
    }
    #endif

    private var aboutSection: some View {
        Section {
            HStack(spacing: 14) {
                Image("Logo")
                    .resizable()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("RowCoach").font(.headline)
                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")")
                        .font(.footnote).foregroundStyle(Theme.text2)
                    Text("Open Source, für den Concept2 RowErg mit PM5").font(.footnote).foregroundStyle(Theme.text2)
                }
            }
        } header: {
            Text("Über RowCoach")
        }
    }

    private var sourcesSection: some View {
        Section {
            ForEach(mapSources, id: \.self) { Text($0) }
            if mapSources.isEmpty {
                Text("Landschaftsdaten: © swisstopo (swissALTI3D, SWISSIMAGE, swissBUILDINGS3D 3.0, swissTLM3D), Open Government Data.")
            }
            Text("PM5-Protokoll nach Concept2 „PM CSAFE Communication Definition“. Concept2, RowErg und PM5 sind Marken von Concept2, Inc.; RowCoach ist kein Produkt von Concept2 und steht in keiner Verbindung zu Concept2.")
            Text("Trainingsprogramme: Quellen je Programm in der Programmansicht.")
        } header: {
            Text("Quellen und Lizenzen")
        }
        .font(.footnote)
    }

    private var zonePreview: some View {
        let z = HeartRateZones(maxHR: maxHR, restHR: restHR)
        return HStack(spacing: 6) {
            ForEach(1...HeartRateZones.count, id: \.self) { i in
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 3).fill(Theme.zoneColor(i)).frame(height: 6)
                    Text("Z\(i) ≥\(z.lowerBound(zone: i))").font(.caption2.monospacedDigit()).foregroundStyle(Theme.text2)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Pulszonen ab \(z.lowerBound(zone: 1)), \(z.lowerBound(zone: 2)), \(z.lowerBound(zone: 3)), \(z.lowerBound(zone: 4)) und \(z.lowerBound(zone: 5)) Schlägen pro Minute"))
    }
}
