import SwiftUI
import RowCoachKit

/// Erster Start abgeschlossen (Einstieg: Profil, PM5, Health)
enum OnboardingSettings {
    static let doneKey = "onboarding.done"
}

extension ProfileState {
    /// Gewicht in kg (Profil; für spätere Auswertungen, z. B. Kalorien)
    static let weightKey = "profile.weightKg"

    /// Angezeigte Werte als bestätigt speichern (auch wenn sie den Voreinstellungen entsprechen); die 2000-m-Zeit
    /// als Eingabe ins Schwellenprofil (docs/schwelle/SPEC.md 4: keine doppelte Wahrheit)
    @MainActor
    static func confirmCurrentValues() {
        let d = UserDefaults.standard
        d.set(d.object(forKey: maxHRKey) as? Int ?? 185, forKey: maxHRKey)
        d.set(d.object(forKey: restHRKey) as? Int ?? 55, forKey: restHRKey)
        let best = d.double(forKey: TrainingSettings.best2kKey)
        d.set(best > 0 ? best : PaceTargets.defaultBest2k, forKey: TrainingSettings.best2kKey)
        if ThresholdStore.shared.isDefault { ThresholdStore.shared.enter2k(best > 0 ? best : PaceTargets.defaultBest2k) }
    }
}

/// Profilwerte als Formularzeilen: Maximalpuls, Ruhepuls und Gewicht per Drehrad im Popover (`WheelIntRow`,
/// `WheelValueRow`), 2000-m-Bestzeit per Auswahlrad (Minuten : Sekunden , Zehntel). Für Einstellungen, „Profil prüfen“ und den ersten Start.
/// In den Einstellungen (`heartLinks`) führen Maximal- und Ruhepuls nach „Schwelle & Zonen“ (Abschnitt Puls), wo alle
/// Pulswerte zusammen stehen; dort werden sie auch bearbeitet.
struct ProfileFields: View {
    @AppStorage(ProfileState.maxHRKey) private var maxHR = 185
    @AppStorage(ProfileState.restHRKey) private var restHR = 55
    @AppStorage(ProfileState.weightKey) private var weight = 75.0
    @AppStorage(TrainingSettings.best2kKey) private var best2k = PaceTargets.defaultBest2k
    @State private var showWheel = false

    /// Maximal- und Ruhepuls als Verweis nach „Schwelle & Zonen“ statt als Zahlenfeld (nur in einem NavigationStack)
    private let heartLinks: Bool

    init(heartLinks: Bool = false) {
        self.heartLinks = heartLinks
    }

    var body: some View {
        Group {
            if heartLinks {
                heartLink(Text("Maximalpuls"), value: maxHR)
                heartLink(Text("Ruhepuls"), value: restHR)
            } else {
                WheelIntRow(label: Text("Maximalpuls"), value: $maxHR, range: 120...230, unit: "/min")
                WheelIntRow(label: Text("Ruhepuls"), value: $restHR, range: 30...110, unit: "/min")
            }
            // 30–200 kg in 0,5-kg-Schritten (die App kennt nur kg)
            WheelValueRow(label: Text("Gewicht"), value: $weight, range: 30...200, step: 0.5, unit: "kg", decimals: 1)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showWheel.toggle() }
            } label: {
                LabeledContent {
                    Text(Format.duration(best2k, tenths: true)).monospacedDigit().foregroundStyle(Theme.link)
                } label: {
                    // stammt die Schwelle nicht aus einer 2k-Zeit, ist es die gleichwertige 2k-Zeit (Referenz)
                    if ThresholdStore.shared.active?.details["t2k"] == nil {
                        Text("2k-Referenz für Ziele").foregroundStyle(Theme.text)
                    } else {
                        Text("2000-m-Bestzeit").foregroundStyle(Theme.text)
                    }
                }
            }
            .accessibilityHint(Text("Auswahlrad öffnen"))
            if showWheel {
                // schreibt eine Eingabe ins Schwellenprofil (Spiegel zurück nach best2k)
                Best2kWheel(seconds: Binding(get: { best2k }, set: { ThresholdStore.shared.enter2k($0) }))
            }
            if let warning {
                Text(warning).font(.footnote).foregroundStyle(Theme.warn)
            }
        }
        .onChange(of: maxHR) { _, _ in clamp() }
        .onChange(of: restHR) { _, _ in clamp() }
        .onDisappear { clamp() }
    }

    private func heartLink(_ label: Text, value: Int) -> some View {
        NavigationLink {
            ThresholdSettingsView(scrollToHeart: true)
        } label: {
            LabeledContent {
                HStack(spacing: 4) {
                    Text(verbatim: String(value)).monospacedDigit()
                    Text("/min")
                }
            } label: {
                label
            }
        }
    }

    private var warning: String? {
        if !(120...230).contains(maxHR) { return String(localized: "Maximalpuls zwischen 120 und 230 eingeben.") }
        if !(30...110).contains(restHR) { return String(localized: "Ruhepuls zwischen 30 und 110 eingeben.") }
        if restHR >= maxHR { return String(localized: "Der Ruhepuls muss unter dem Maximalpuls liegen.") }
        return nil
    }

    /// Werte in sinnvolle Bereiche bringen (Ruhepuls mindestens 20 unter dem Maximalpuls)
    private func clamp() {
        maxHR = min(max(maxHR, 120), 230)
        restHR = min(max(restHR, 30), min(110, maxHR - 20))
        weight = min(max(weight, 30), 200)
    }
}

/// Auswahlrad für die 2000-m-Bestzeit: Minuten, Sekunden, Zehntel (5:30,0 bis 12:00,0)
struct Best2kWheel: View {
    @Binding var seconds: Double

    private var tenths: Int { Int((min(max(seconds, 330), 720) * 10).rounded()) }

    private func set(minutes: Int? = nil, secs: Int? = nil, tenth: Int? = nil) {
        let m = minutes ?? tenths / 600
        let s = secs ?? (tenths / 10) % 60
        let t = tenth ?? tenths % 10
        let total = Double(m * 60 + s) + Double(t) / 10
        seconds = min(max(total, 330), 720)
    }

    var body: some View {
        HStack(spacing: 0) {
            Picker(selection: Binding(get: { tenths / 600 }, set: { set(minutes: $0) })) {
                ForEach(5...12, id: \.self) { Text("\($0) min").tag($0) }
            } label: { Text("Minuten") }
            Picker(selection: Binding(get: { (tenths / 10) % 60 }, set: { set(secs: $0) })) {
                ForEach(0..<60, id: \.self) { Text(String(format: "%02d s", $0)).tag($0) }
            } label: { Text("Sekunden") }
            Picker(selection: Binding(get: { tenths % 10 }, set: { set(tenth: $0) })) {
                ForEach(0..<10, id: \.self) { Text(",\($0)").tag($0) }
            } label: { Text("Zehntel") }
        }
        .pickerStyle(.wheel)
        .frame(height: 160)
        .accessibilityElement(children: .contain)
    }
}

/// „Profil prüfen“ (Hinweis auf dem Startbildschirm): Werte ändern, „Werte stimmen“ speichert sie als bestätigt.
struct ProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onDone: () -> Void

    init(onDone: @escaping () -> Void = {}) {
        self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ProfileFields()
                } footer: {
                    Text("Pulszonen richten sich nach Maximal- und Ruhepuls, die Tempo-Ziele der Programme nach der 2000-m-Bestzeit.")
                }
            }
            .scrollContentBackground(.hidden)
            .dsSheetChrome(String(localized: "Profil prüfen")) { dismiss() }
            .safeAreaInset(edge: .bottom) {
                DSFooterBar {
                    Button("Werte stimmen") {
                        ProfileState.confirmCurrentValues()
                        onDone()
                        dismiss()
                    }
                    .buttonStyle(PrimaryButtonStyle(compact: true))
                }
            }
        }
    }
}

/// Erster Start: kurzer Einstieg in drei Schritten (Profil, PM5 verbinden, Apple Health), dann „Los“.
struct OnboardingSheet: View {
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(HealthService.self) private var health
    @Environment(DeviceManager.self) private var devices
    @AppStorage(OnboardingSettings.doneKey) private var done = false
    @State private var step = Step.profile

    private enum Step: Int, CaseIterable { case profile, pm5, health }

    init(onDone: @escaping () -> Void = {}) {
        self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .profile:
                    Form {
                        Section {
                            ProfileFields()
                        } header: {
                            Text("Dein Profil")
                        } footer: {
                            Text("Daraus rechnet RowCoach Pulszonen und Zieltempi. Später änderbar unter Einstellungen.")
                        }
                    }
                    .scrollContentBackground(.hidden)
                case .pm5:
                    ScrollView {
                        VStack(alignment: .leading, spacing: DS.Space.m) {
                            Text("PM5 verbinden").font(.title.bold())
                            Text("Am PM5 im Menü „Connect“ wählen. RowCoach merkt sich das Gerät für die nächsten Starts.")
                                .foregroundStyle(Theme.text2)
                            DeviceConnectView()
                        }
                        .padding(DS.Space.l)
                    }
                case .health:
                    VStack(alignment: .leading, spacing: DS.Space.m) {
                        Text("Apple Health").font(.title.bold())
                        Text("RowCoach speichert jede Fahrt als Training „Rudern (indoor)“ mit Puls, Distanz und Strecke und fragt nach der Fahrt die Anstrengung ab.")
                            .foregroundStyle(Theme.text2)
                        if health.status == .authorized {
                            Label("Verbunden", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.ok)
                        } else if health.status != .unavailable {
                            Button("Apple Health verbinden") { Task { await health.connect() } }
                                .buttonStyle(SecondaryButtonStyle(compact: true, fullWidth: false))
                        } else {
                            Text("Apple Health ist auf diesem Gerät nicht verfügbar.").foregroundStyle(Theme.text2)
                        }
                        Spacer()
                    }
                    .padding(DS.Space.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .dsPageBackground()
            .navigationTitle(Text("Willkommen bei RowCoach"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.bg, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if step != .profile {
                        Button("Zurück") { step = Step(rawValue: step.rawValue - 1) ?? .profile }
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("Schritt \(step.rawValue + 1) von \(Step.allCases.count)")
                        .font(.subheadline).foregroundStyle(Theme.text2)
                }
            }
            .safeAreaInset(edge: .bottom) { footer }
        }
    }

    private var footer: some View {
        DSFooterBar {
            switch step {
            case .profile:
                Button("Weiter") { step = .pm5 }
                    .buttonStyle(PrimaryButtonStyle(compact: true))
            case .pm5:
                Button(devices.pm5State == .connected ? String(localized: "Weiter") : String(localized: "Später verbinden")) {
                    step = .health
                }
                .buttonStyle(devices.pm5State == .connected ? AnyButtonStyleBox.primary : AnyButtonStyleBox.secondary)
            case .health:
                Button {
                    finish()
                } label: {
                    Label("Los", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle(compact: true))
            }
        }
    }

    private func finish() {
        ProfileState.confirmCurrentValues()
        done = true
        onDone()
        dismiss()
    }
}

/// Haupt- oder Nebentaste je nach Zustand (ein Typ für `.buttonStyle`)
struct AnyButtonStyleBox: ButtonStyle {
    let isPrimary: Bool

    static let primary = AnyButtonStyleBox(isPrimary: true)
    static let secondary = AnyButtonStyleBox(isPrimary: false)

    func makeBody(configuration: Configuration) -> some View {
        Group {
            if isPrimary {
                PrimaryButtonStyle(compact: true).makeBody(configuration: configuration)
            } else {
                SecondaryButtonStyle(compact: true).makeBody(configuration: configuration)
            }
        }
    }
}
