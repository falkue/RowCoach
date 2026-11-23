import SwiftUI
import RowCoachKit

/// Einstellungen der Tempo-Linie (UserDefaults bzw. @AppStorage)
enum PaceLineSettings {
    /// Schalter „Tempo-Linie“ beim freien Rudern
    static let enabledKey = "paceLine.enabled"
    /// zuletzt verwendetes Zieltempo (s/500 m); 0 = noch keins, dann Vorschlag aus der 2000-m-Bestzeit
    static let paceKey = "paceLine.pace"

    static func effectivePace(stored: Double, best2k: Double) -> Double {
        stored > 0 ? PaceLine.clamp(stored) : PaceLine.defaultPace(best2k: best2k)
    }

    /// Zieltempo für die nächste freie Fahrt, nil = Tempo-Linie aus
    static var current: Double? {
        let d = UserDefaults.standard
        guard d.bool(forKey: enabledKey) else { return nil }
        return effectivePace(stored: d.double(forKey: paceKey), best2k: TrainingSettings.best2k)
    }

    /// Tempo als zuletzt verwendet merken (beim Start der Fahrt)
    static func remember(_ pace: Double) {
        UserDefaults.standard.set(PaceLine.clamp(PaceLine.rounded(pace)), forKey: paceKey)
    }

    /// Länge der Strecke wie in der Fahrt (hin und zurück bei Strecken mit Wende)
    static func courseLength(_ c: Course) -> Double {
        c.turns > 0 ? 2 * c.oneWayM : c.oneWayM
    }

    /// „4000 m in 18:24“
    static func finishText(distance: Double, pace: Double) -> String {
        "\(Format.distance(distance)) in \(Format.duration(PaceLine(pace: pace).time(forDistance: distance).rounded()))"
    }
}

/// Karte im Ablauf „Frei rudern“ über der Streckenwahl: Schalter „Tempo-Linie“ und Zieltempo pro 500 m.
struct PaceLineSetupCard: View {
    @AppStorage(PaceLineSettings.enabledKey) private var enabled = false
    @AppStorage(PaceLineSettings.paceKey) private var storedPace = 0.0
    @AppStorage(TrainingSettings.best2kKey) private var best2k = PaceTargets.defaultBest2k

    init() {}

    private var pace: Double { PaceLineSettings.effectivePace(stored: storedPace, best2k: best2k) }
    private var suggested: Double { PaceLine.defaultPace(best2k: best2k) }

    private var examplesText: String {
        let a = PaceLineSettings.finishText(distance: 2000, pace: pace)
        let b = PaceLineSettings.finishText(distance: 5000, pace: pace)
        return "Zum Beispiel \(a) · \(b). Die Zeit für jede Strecke steht auf ihrer Kachel."
    }

    private var paceBinding: Binding<Double> {
        Binding(get: { pace }, set: { storedPace = PaceLine.clamp(PaceLine.rounded($0)) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $enabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Tempo-Linie", systemImage: "flag.pattern.checkered")
                        .font(.headline)
                    Text("Eine Linie auf dem Wasser fährt im Zieltempo mit und hält bei Pausen an.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(Theme.paceLine)
            if enabled {
                HStack(spacing: 12) {
                    Button("−5 s") { paceBinding.wrappedValue = pace - 5 }
                        .buttonStyle(.bordered)
                        .disabled(pace <= PaceLine.paceRange.lowerBound)
                        .accessibilityLabel("5 Sekunden schneller")
                    Stepper(value: paceBinding, in: PaceLine.paceRange, step: 0.5) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(Format.pace(pace))
                                .font(Theme.number(34))
                                .contentTransition(.numericText())
                            Text("pro 500 m").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityValue("\(Format.pace(pace)) pro 500 Meter")
                    Button("+5 s") { paceBinding.wrappedValue = pace + 5 }
                        .buttonStyle(.bordered)
                        .disabled(pace >= PaceLine.paceRange.upperBound)
                        .accessibilityLabel("5 Sekunden langsamer")
                }
                Text(examplesText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if abs(pace - suggested) >= 0.25 {
                    Button("Vorschlag aus der 2000-m-Bestzeit: \(Format.pace(suggested))") { storedPace = 0 }
                        .font(.footnote)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: 560, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(.snappy, value: enabled)
    }
}
