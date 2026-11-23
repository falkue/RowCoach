import SwiftUI
import Charts
import RowCoachKit

/// Zusammenfassung eines Trainings: Werte, Belastung, Pulsverlauf (Swift Charts), Zonen, Splits, Apple-Health-Status.
/// Wird nach dem Ziel und in der Verlaufsansicht verwendet. Direkt nach der Fahrt (das Training ist
/// `SessionController.record`) fragt sie die Belastung 1–10 ab; im Verlauf zeigt sie sie nur an.
struct SummaryView: View {
    enum HealthState { case pending, saved, notSaved }

    let record: WorkoutRecord
    var health: HealthState
    var healthNote: String? = nil

    @AppStorage("profile.maxHR") private var maxHR = 185
    @AppStorage("profile.restHR") private var restHR = 55
    @Environment(SessionController.self) private var controller

    private var zones: HeartRateZones { HeartRateZones(maxHR: maxHR, restHR: restHR) }
    private var summary: WorkoutSummary { record.summary }
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    init(record: WorkoutRecord, health: HealthState, healthNote: String? = nil) {
        self.record = record
        self.health = health
        self.healthNote = healthNote
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                healthRow
                effortSection
                LazyVGrid(columns: columns, spacing: 12) {
                    value("Zeit", Format.duration(summary.activeDuration))
                    value("Distanz", Format.distance(summary.distance))
                    value("Ø Tempo", Format.pace(summary.averagePace), unit: "/500 m")
                    value("Ø Schlagzahl", summary.averageStrokeRate > 0 ? String(format: "%.1f", summary.averageStrokeRate) : "–",
                          unit: "/min")
                    value("Ø Leistung", summary.averagePower > 0 ? "\(summary.averagePower)" : "–", unit: "W")
                    value("Ø Puls", summary.averageHeartRate.map { "\($0)" } ?? "–", unit: "bpm",
                          detail: summary.maxHeartRate.map { "max. \($0)" })
                    value("Kalorien", "\(summary.calories)", unit: "kcal")
                    value("Schläge", "\(summary.strokeCount)",
                          detail: summary.pauseCount > 0 ? "\(summary.pauseCount) Pause(n)" : nil)
                    if let p = record.header.paceTarget, p > 0 {
                        // Vergleich mit der Tempo-Linie: positiv = schneller als die Linie
                        let g = PaceLine(pace: p).gap(boatDistance: summary.distance, activeTime: summary.activeDuration,
                                                      total: record.header.courseLength)
                        value("Gegen die Tempo-Linie",
                              (g.seconds >= 0 ? "+" : "−") + PaceLinePanel.decimal(abs(g.seconds)),
                              unit: "s", detail: "Ziel " + Format.pace(p) + " /500 m")
                    }
                }
                phasesSection
                heartRateSection
                splitsSection
            }
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(record.header.courseTitle ?? "Training")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Kopf

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(headline)
                .font(.largeTitle.bold())
            if let name = planName {
                Label("Training: \(name)", systemImage: "chart.bar.xaxis")
                    .font(.headline)
                    .foregroundStyle(Theme.phaseColor(.work))
            }
            HStack(spacing: 8) {
                Text(record.header.startDate.formatted(date: .complete, time: .shortened))
                if record.header.device.source == .simulator {
                    Text("Simulator").font(.caption.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.purple.opacity(0.7)))
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private var isTraining: Bool { record.header.workoutPlanId != nil }

    private var headline: String {
        if record.isInterrupted { return "Fahrt unterbrochen" }
        if isTraining { return summary.completedCourse ? "Training geschafft" : "Training vorzeitig beendet" }
        return summary.completedCourse ? "Ziel erreicht" : "Vorzeitig beendet"
    }

    private var planName: String? {
        guard let id = record.header.workoutPlanId else { return nil }
        return record.header.workoutPlanName ?? PlanLibrary.plan(id: id)?.name ?? id
    }

    @ViewBuilder
    private var healthRow: some View {
        switch health {
        case .pending:
            HStack(spacing: 8) {
                ProgressView()
                Text("Speichere in Apple Health …")
            }
            .foregroundStyle(.secondary)
        case .saved:
            Label("In Apple Health gespeichert", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.headline)
        case .notSaved:
            VStack(alignment: .leading, spacing: 2) {
                Label("Nicht in Apple Health gespeichert", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.orange)
                    .font(.headline)
                if let healthNote {
                    Text(healthNote).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func value(_ title: String, _ value: String, unit: String? = nil, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(Theme.number(30)).lineLimit(1).minimumScaleFactor(0.6)
                if let unit { Text(unit).font(.footnote).foregroundStyle(.secondary) }
            }
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .hudPanel(cornerRadius: 12)
    }

    // MARK: Belastung

    /// Zusammenfassung direkt nach der Fahrt (nicht im Verlauf)
    private var isLiveResult: Bool {
        controller.record?.id == record.id && (controller.phase == .saving || controller.phase == .done)
    }

    private var effortSuggestion: Int? { EffortProfile.estimate(for: record) }

    @ViewBuilder
    private var effortSection: some View {
        if isLiveResult {
            switch controller.effortPrompt {
            case .asking:
                EffortPicker(suggestion: effortSuggestion, basisText: record.effort?.basis?.title,
                             initial: record.effort?.userScore, waiting: controller.phase == .saving,
                             onSave: { controller.saveEffort($0) }, onSkip: { controller.skipEffort() })
            case .saving:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Speichere Belastung …")
                }
                .foregroundStyle(.secondary)
            case .saved, .skipped:
                EffortSummaryRow(userScore: record.effort?.userScore, suggestion: effortSuggestion,
                                 basisText: record.effort?.basis?.title,
                                 skipped: controller.effortPrompt == .skipped, note: controller.effortNote,
                                 changeTitle: controller.effortPrompt == .skipped ? "Doch eintragen" : "Ändern",
                                 onChange: { controller.reopenEffort() })
            }
        } else if record.effort?.userScore != nil || effortSuggestion != nil {
            EffortSummaryRow(userScore: record.effort?.userScore, suggestion: effortSuggestion,
                             basisText: record.effort?.basis?.title)
        }
    }

    // MARK: Puls

    private struct HRPoint: Identifiable {
        let id: Int
        let minute: Double
        let bpm: Int
    }

    private var hrPoints: [HRPoint] {
        record.samples.enumerated().compactMap { i, s in
            s.heartRate.map { HRPoint(id: i, minute: s.time / 60, bpm: $0) }
        }
    }

    @ViewBuilder
    private var heartRateSection: some View {
        let points = hrPoints
        if !points.isEmpty {
            let lo = max((points.map(\.bpm).min() ?? 60) - 10, 30)
            let hi = (points.map(\.bpm).max() ?? 180) + 10
            VStack(alignment: .leading, spacing: 10) {
                Text("Pulsverlauf").font(.title3.bold())
                Chart {
                    ForEach(1...HeartRateZones.count, id: \.self) { z in
                        let bound = zones.lowerBound(zone: z)
                        if bound > lo && bound < hi {
                            RuleMark(y: .value("Zone \(z)", bound))
                                .foregroundStyle(Theme.zoneColor(z).opacity(0.5))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        }
                    }
                    ForEach(points) { p in
                        LineMark(x: .value("Minute", p.minute), y: .value("Puls", p.bpm))
                            .foregroundStyle(Color.red)
                            .interpolationMethod(.monotone)
                    }
                }
                .chartYScale(domain: lo...hi)
                .chartXAxisLabel("Minuten")
                .chartYAxisLabel("bpm")
                .frame(height: 220)
                zoneBar
            }
            .padding()
            .hudPanel(cornerRadius: 12)
        }
    }

    @ViewBuilder
    private var zoneBar: some View {
        if let secs = summary.heartRateZoneSeconds, secs.reduce(0, +) > 0 {
            let total = secs.reduce(0, +)
            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geo in
                    HStack(spacing: 1) {
                        ForEach(Array(secs.enumerated()), id: \.offset) { z, s in
                            if s > 0 {
                                Rectangle().fill(Theme.zoneColor(z))
                                    .frame(width: max(geo.size.width * s / total - 1, 1))
                            }
                        }
                    }
                }
                .frame(height: 14)
                .clipShape(Capsule())
                HStack(spacing: 12) {
                    ForEach(Array(secs.enumerated()), id: \.offset) { z, s in
                        if s > 0 {
                            HStack(spacing: 4) {
                                Circle().fill(Theme.zoneColor(z)).frame(width: 8, height: 8)
                                Text("\(z == 0 ? "<1" : "Z\(z)") \(Format.duration(s))")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Phasen (Training)

    @ViewBuilder
    private var phasesSection: some View {
        if let phases = record.planPhases, !phases.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Phasen").font(.title3.bold())
                Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 6) {
                    GridRow {
                        Text("Phase").gridColumnAlignment(.leading)
                        Text("Zeit")
                        Text("Strecke")
                        Text("/500 m")
                        Text("SPM")
                        Text("Puls")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    Divider()
                    ForEach(phases) { p in
                        GridRow {
                            HStack(spacing: 6) {
                                Circle().fill(Theme.phaseColor(p.phaseKind)).frame(width: 8, height: 8)
                                Text(p.label).lineLimit(1)
                                if !p.completed { Text("(abgebrochen)").foregroundStyle(.secondary) }
                            }
                            .gridColumnAlignment(.leading)
                            Text(Format.duration(p.duration))
                            Text(Format.distance(p.distance))
                            Text(p.averagePace.map { Format.pace($0) } ?? "–")
                            Text(p.averageStrokeRate.map { String(format: "%.0f", $0) } ?? "–")
                            Text(p.averageHeartRate.map { "\($0)" } ?? "–")
                        }
                        .font(.body.monospacedDigit())
                    }
                }
            }
            .padding()
            .hudPanel(cornerRadius: 12)
        }
    }

    // MARK: Splits

    @ViewBuilder
    private var splitsSection: some View {
        if !record.splits.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Splits").font(.title3.bold())
                Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        Text("Strecke").gridColumnAlignment(.leading)
                        Text("Zeit")
                        Text("/500 m")
                        Text("SPM")
                        Text("Watt")
                        Text("Puls")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    Divider()
                    ForEach(record.splits) { s in
                        GridRow {
                            Text(Format.distance(s.endDistance))
                            Text(Format.duration(s.duration, tenths: true))
                            Text(Format.pace(s.pace))
                            Text(s.averageStrokeRate > 0 ? String(format: "%.0f", s.averageStrokeRate) : "–")
                            Text(s.averagePower > 0 ? "\(s.averagePower)" : "–")
                            Text(s.averageHeartRate.map { "\($0)" } ?? "–")
                        }
                        .font(.body.monospacedDigit())
                    }
                }
            }
            .padding()
            .hudPanel(cornerRadius: 12)
        }
    }
}

// MARK: - Belastung

/// Farbe je Stufe der Belastungsskala
enum EffortStyle {
    static func color(_ score: Int) -> Color {
        switch EffortScale.level(score) {
        case .easy: return .green
        case .moderate: return .yellow
        case .hard: return .orange
        case .allOut: return .red
        }
    }
}

/// Auswahl der Belastung 1–10 mit Apples Stufen (1–3 leicht, 4–6 moderat, 7–8 hart, 9–10 alles gegeben).
/// Grosse Tasten (auch mit verschwitzten Fingern), vorausgewählt ist der Vorschlag der App.
struct EffortPicker: View {
    let suggestion: Int?
    let basisText: String?
    var waiting: Bool
    var skipTitle: String
    let onSave: (Int) -> Void
    let onSkip: () -> Void

    @State private var selection: Int

    init(suggestion: Int?, basisText: String?, initial: Int?, waiting: Bool = false,
         skipTitle: String = "Überspringen", onSave: @escaping (Int) -> Void, onSkip: @escaping () -> Void) {
        self.suggestion = suggestion
        self.basisText = basisText
        self.waiting = waiting
        self.skipTitle = skipTitle
        self.onSave = onSave
        self.onSkip = onSkip
        _selection = State(initialValue: EffortScale.clamp(initial ?? suggestion ?? 5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Wie anstrengend war es?").font(.title2.bold())
                Text("Belastung 1–10, wie in Apple Health").font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(selection)").font(Theme.number(56)).foregroundStyle(EffortStyle.color(selection))
                Text(EffortScale.level(selection).title).font(.title.bold())
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach([1, 6], id: \.self) { first in
                    GridRow {
                        ForEach(first..<(first + 5), id: \.self) { n in scoreButton(n) }
                    }
                }
            }
            HStack(spacing: 10) {
                ForEach(EffortScale.Level.allCases, id: \.self) { level in
                    HStack(spacing: 4) {
                        Circle().fill(EffortStyle.color(level.scores.lowerBound)).frame(width: 8, height: 8)
                        Text("\(level.scores.lowerBound)–\(level.scores.upperBound) \(level.title)")
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            if let suggestion {
                Label {
                    Text("Vorschlag der App: \(EffortScale.label(suggestion))" + (basisText.map { " (\($0))" } ?? ""))
                } icon: {
                    Image(systemName: "wand.and.stars")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button(action: onSkip) {
                    Text(skipTitle).frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.bordered)
                Button { onSave(selection) } label: {
                    Text(waiting ? "Warte auf Apple Health …" : "Speichern").frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
                .disabled(waiting)
            }
            .font(.title3.bold())
        }
        .padding()
        .hudPanel(cornerRadius: 12)
    }

    private func scoreButton(_ n: Int) -> some View {
        let selected = n == selection
        let suggested = n == suggestion
        return Button { selection = n } label: {
            VStack(spacing: 2) {
                Text("\(n)").font(Theme.number(30))
                Text(suggested ? "Vorschlag" : " ").font(.caption2.bold())
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .foregroundStyle(selected ? Color.black : Color.primary)
            .background(RoundedRectangle(cornerRadius: 12)
                .fill(selected ? EffortStyle.color(n) : EffortStyle.color(n).opacity(0.18)))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(suggested ? Color.primary.opacity(0.8) : Color.clear,
                              style: StrokeStyle(lineWidth: 2, dash: [5, 3])))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Belastung \(n), \(EffortScale.level(n).title)" + (suggested ? ", Vorschlag der App" : ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Anzeige der Belastung: eigene Einschätzung gross, Vorschlag der App klein; optional mit Taste zum Ändern
struct EffortSummaryRow: View {
    let userScore: Int?
    let suggestion: Int?
    let basisText: String?
    var skipped: Bool = false
    var note: String? = nil
    var changeTitle: String? = nil
    var onChange: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Belastung").font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(.secondary)
                if let userScore {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(userScore)").font(Theme.number(30)).foregroundStyle(EffortStyle.color(userScore))
                        Text(EffortScale.level(userScore).title).font(.headline)
                        Text("eigene Einschätzung").font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    Text(skipped ? "Übersprungen – keine eigene Einschätzung" : "Keine eigene Einschätzung")
                        .font(.headline)
                }
                if let suggestion {
                    Text("Vorschlag der App: \(EffortScale.label(suggestion))" + (basisText.map { " (\($0))" } ?? ""))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let note {
                    Text(note).font(.footnote).foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 8)
            if let changeTitle, let onChange {
                Button(changeTitle, action: onChange)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .hudPanel(cornerRadius: 12)
    }
}
