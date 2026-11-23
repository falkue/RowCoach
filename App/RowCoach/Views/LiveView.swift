import SwiftUI
import RowCoachKit

/// Diagnose (aus Etappe 0): Live-Werte vom PM5 und Pulsgurt, Test-Aufzeichnung nach Apple Health.
/// Liegt unter Einstellungen → Entwickler; der eigentliche Ruderbildschirm ist RowingView.
struct LiveView: View {
    @Environment(DeviceManager.self) private var devices
    @Environment(HealthService.self) private var health

    private let columns = [GridItem(.adaptive(minimum: 200), spacing: 16)]

    var body: some View {
        let s = devices.snapshot
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                statusBar
                LazyVGrid(columns: columns, spacing: 16) {
                    Metric(title: "Zeit", value: Format.duration(s.elapsedTime))
                    Metric(title: "Distanz", value: Format.distance(s.distance))
                    Metric(title: "Tempo /500 m", value: Format.pace(s.pace))
                    Metric(title: "Geschwindigkeit", value: String(format: "%.1f km/h", s.speed * 3.6))
                    Metric(title: "Schlagzahl", value: s.strokeRate > 0 ? "\(s.strokeRate) /min" : "–")
                    Metric(title: "Leistung", value: s.power > 0 ? "\(s.power) W" : "–")
                    Metric(title: "Puls", value: s.heartRate.map { "\($0)" } ?? "–",
                           detail: s.heartRateSource.map { $0 == .strap ? String(localized: "Gurt") : "PM5" },
                           tint: .red)
                    Metric(title: "Kalorien", value: "\(s.calories) kcal")
                }
                recordSection
                diagnostics
            }
            .padding()
        }
        .navigationTitle("Diagnose")
    }

    private var statusBar: some View {
        HStack(spacing: 16) {
            Label("PM5: \(devices.pm5State.title)", systemImage: "figure.rower")
                .foregroundStyle(devices.pm5State == .connected ? .green : .secondary)
            Label("Puls: \(devices.strapState.title)", systemImage: "heart.fill")
                .foregroundStyle(devices.strapState == .connected ? .green : .secondary)
            Label("Health: \(health.status.title)", systemImage: "heart.text.square")
                .foregroundStyle(health.status == .authorized ? .green : .secondary)
            Spacer()
        }
        .font(.subheadline)
    }

    private var recordSection: some View {
        GroupBox("Aufzeichnung für Apple Health") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if health.isRecording {
                        Button("Beenden und in Health speichern") { Task { await health.finish() } }
                            .buttonStyle(.borderedProminent)
                        Button("Verwerfen", role: .destructive) { health.discard() }
                    } else {
                        Button("Aufzeichnung starten") { Task { await health.start(courseName: nil) } }
                            .buttonStyle(.borderedProminent)
                            .disabled(health.status != .authorized)
                    }
                }
                if health.status != .authorized {
                    Text("Zuerst unter Einstellungen Apple Health verbinden.").font(.footnote).foregroundStyle(.secondary)
                }
                if let d = health.lastSavedWorkout {
                    Label("Zuletzt gespeichert: \(d.formatted(date: .omitted, time: .shortened))",
                          systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
                if let e = health.lastError { Text(e).font(.footnote).foregroundStyle(.red) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var diagnostics: some View {
        DisclosureGroup("Diagnose") {
            VStack(alignment: .leading, spacing: 4) {
                let s = devices.snapshot
                Text("Workout-Status: \(s.workoutState.map { "\($0)" } ?? "–"), Rudern: \(s.rowingState.map { "\($0)" } ?? "–"), Widerstand (Drag): \(s.dragFactor)")
                Text("Ø Tempo: \(Format.pace(s.averagePace)), Ø Leistung: \(s.averagePower) W, Schläge: \(s.strokeCount)")
                if let b = devices.strapBattery { Text("Akku Pulsgurt: \(b) %") }
                ForEach(devices.messageCounts.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in
                    Text("\(k): \(v) Nachrichten").monospaced()
                }
                if let sum = devices.lastSummary {
                    Text("PM5-Zusammenfassung: \(Format.distance(sum.distance)) in \(Format.duration(sum.elapsedTime)), Ø Puls \(sum.averageHeartRate.map(String.init) ?? "–")")
                }
                if let e = devices.lastError { Text(e).foregroundStyle(.red) }
            }
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct Metric: View {
    let title: LocalizedStringKey
    let value: String
    var detail: String? = nil
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 40, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(tint).minimumScaleFactor(0.5).lineLimit(1)
            if let detail { Text(detail).font(.caption2).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
