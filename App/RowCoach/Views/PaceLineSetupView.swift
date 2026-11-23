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

/// Karte auf der Streckenseite: Schalter „Tempo-Linie“ und Zieltempo pro 500 m (ein Bedienelement, ±1 s;
/// Halten wiederholt). Vorbelegt mit dem zuletzt verwendeten Tempo bzw. dem Vorschlag aus der 2000-m-Bestzeit.
struct PaceLineSetupCard: View {
    @AppStorage(PaceLineSettings.enabledKey) private var enabled = false
    @AppStorage(PaceLineSettings.paceKey) private var storedPace = 0.0
    @AppStorage(TrainingSettings.best2kKey) private var best2k = PaceTargets.defaultBest2k

    init() {}

    private var pace: Double { PaceLineSettings.effectivePace(stored: storedPace, best2k: best2k) }
    private var suggested: Double { PaceLine.defaultPace(best2k: best2k) }

    private var paceBinding: Binding<Double> {
        Binding(get: { pace }, set: { storedPace = PaceLine.clamp(PaceLine.rounded($0)) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $enabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Label {
                        Text("Tempo-Linie")
                    } icon: {
                        Capsule().fill(Theme.paceLine).frame(width: 18, height: 6)
                    }
                    .font(.headline)
                    Text("Eine Linie auf dem Wasser fährt im Zieltempo mit und hält bei Pausen an.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Theme.accent)
            if enabled {
                Stepper(value: paceBinding, in: PaceLine.paceRange, step: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Format.duration(pace))
                            .font(.title.weight(.semibold).monospacedDigit())
                        Text("/500 m").font(.subheadline).foregroundStyle(Theme.text2)
                    }
                }
                .accessibilityValue(Text("\(Format.duration(pace)) pro 500 Meter"))
                Text("Zum Beispiel \(PaceLineSettings.finishText(distance: 2000, pace: pace)).")
                    .font(.footnote)
                    .foregroundStyle(Theme.text2)
                if abs(pace - suggested) >= 0.5 {
                    Button("Vorschlag aus der 2000-m-Bestzeit: \(Format.duration(suggested))") { storedPace = 0 }
                        .font(.footnote)
                        .foregroundStyle(Theme.link)
                        .buttonStyle(.borderless)
                }
            }
        }
        .padding(DS.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
            .strokeBorder(enabled ? Theme.paceLine.opacity(0.5) : Color.white.opacity(0.18)))
        .animation(.easeInOut(duration: 0.2), value: enabled)
    }
}
