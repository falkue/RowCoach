import SwiftUI
import Charts
import RowCoachKit

/// Zusammenfassung eines Trainings: Kernaussage, sechs Kennzahlen, Anstrengung, eine Zeile je Phase mit Ampel
/// gegenüber dem Ziel (Training), Splits je 500 m, Pulsverlauf mit Zonenbändern, Apple-Health-Status (einmal).
/// Wird nach dem Ziel und in der Verlaufsansicht verwendet und erzwingt das dunkle Farbschema (lesbar auch in
/// Sheets). Direkt nach der Fahrt fragt sie die Anstrengung 1–10 ab; im Verlauf zeigt sie sie nur an.
struct SummaryView: View {
    enum HealthState {
        case pending, saved, notSaved
        /// Fahrt zu kurz, gar nicht gespeichert (`RideSaveRule`)
        case notStored
    }

    let record: WorkoutRecord
    var health: HealthState
    var healthNote: String? = nil

    @AppStorage("profile.maxHR") private var maxHR = 185
    @AppStorage("profile.restHR") private var restHR = 55
    @AppStorage(TrainingSettings.best2kKey) private var best2k = PaceTargets.defaultBest2k
    @Environment(SessionController.self) private var controller
    @Environment(HealthService.self) private var healthService

    private var zones: HeartRateZones { HeartRateZones(maxHR: maxHR, restHR: restHR) }
    private var summary: WorkoutSummary { record.summary }
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12, alignment: .top)]

    init(record: WorkoutRecord, health: HealthState, healthNote: String? = nil) {
        self.record = record
        self.health = health
        self.healthNote = healthNote
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                header
                healthBanner
                effortSection
                tiles
                intervalsSection
                splitsSection
                heartRateSection
            }
            .padding(DS.Space.l)
            .frame(maxWidth: 1000, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .dsPageBackground()
        .environment(\.colorScheme, .dark)
        .navigationTitle(record.header.courseTitle ?? String(localized: "Training"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.bg, for: .navigationBar)
    }

    // MARK: Kopf

    private var isTraining: Bool { record.header.workoutPlanId != nil }

    private var headline: String {
        if record.isInterrupted { return String(localized: "Fahrt unterbrochen") }
        if isTraining {
            return summary.completedCourse ? String(localized: "Training geschafft")
                : String(localized: "Training vorzeitig beendet")
        }
        return summary.completedCourse ? String(localized: "Ziel erreicht") : String(localized: "Vorzeitig beendet")
    }

    private var planName: String? {
        guard let id = record.header.workoutPlanId else { return nil }
        // aktueller Name in der Sprache der App vor dem bei der Fahrt gespeicherten
        return PlanLibrary.plan(id: id)?.name ?? record.header.workoutPlanName ?? id
    }

    private var plan: WorkoutPlan? { record.header.workoutPlanId.flatMap { PlanLibrary.plan(id: $0) } }

    /// Kernaussage: „4001 m in 18:51 · Ø 2:21,3 /500 m“
    private var keyLine: String {
        String(localized: "\(Format.distance(summary.distance)) in \(Format.duration(summary.activeDuration)) · Ø \(Format.pace(summary.averagePace)) /500 m")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            if let planName {
                Text(planName.uppercased()).font(.subheadline.weight(.bold)).tracking(1.5).foregroundStyle(Theme.accent)
            }
            Text(headline).font(.largeTitle.bold())
            Text(keyLine).font(.title3.monospacedDigit()).foregroundStyle(Theme.text)
            HStack(spacing: DS.Space.s) {
                Text(record.header.startDate.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()))
                if record.isDemo {
                    DSChip(String(localized: "Beispiel"))
                } else if record.header.device.source == .simulator {
                    DSChip(String(localized: "Simulator"))
                }
            }
            .font(.subheadline)
            .foregroundStyle(Theme.text2)
        }
    }

    /// Apple Health: genau einmal, als Banner (bei Beispiel- und Simulatorfahrten neutral)
    @ViewBuilder
    private var healthBanner: some View {
        switch health {
        case .notStored:
            DSBanner(systemImage: "info.circle",
                     text: String(localized: "Zu kurz zum Speichern: Fahrten unter 100 m oder 1 min kommen nicht in den Verlauf."),
                     tone: .hint)
        case .pending:
            HStack(spacing: DS.Space.s) {
                ProgressView()
                Text("Speichere in Apple Health …")
            }
            .foregroundStyle(Theme.text2)
        case .saved:
            Label("In Apple Health gespeichert", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ok)
        case .notSaved:
            if record.isDemo || record.header.device.source == .simulator {
                Label(record.isDemo ? String(localized: "Beispieltraining – geht nicht nach Apple Health")
                      : String(localized: "Simulatorfahrt – nicht in Apple Health"), systemImage: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(Theme.text2)
            } else if healthService.status == .notDetermined {
                DSBanner(systemImage: "heart.text.square",
                         text: String(localized: "Nicht in Apple Health gespeichert – Apple Health ist nicht verbunden."),
                         tone: .warn, actionTitle: String(localized: "Verbinden"),
                         action: { Task { await healthService.connect() } })
            } else {
                DSBanner(systemImage: "heart.text.square",
                         text: healthNote.map { note in String(localized: "Nicht in Apple Health gespeichert: \(note)") }
                            ?? String(localized: "Nicht in Apple Health gespeichert."),
                         tone: .warn)
            }
        }
    }

    // MARK: Kennzahlen

    private var tiles: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            LazyVGrid(columns: columns, spacing: 12) {
                MetricTile(String(localized: "Zeit"), value: Format.duration(summary.activeDuration))
                MetricTile(String(localized: "Distanz"), value: Format.distance(summary.distance))
                MetricTile(String(localized: "Ø Tempo"), value: Format.pace(summary.averagePace), unit: "/500 m")
                MetricTile(String(localized: "Ø Schlagzahl"),
                           value: summary.averageStrokeRate > 0 ? DSFormat.decimal(summary.averageStrokeRate) : "–",
                           unit: "/min")
                MetricTile(String(localized: "Ø Leistung"),
                           value: summary.averagePower > 0 ? "\(summary.averagePower)" : "–", unit: "W")
                MetricTile(String(localized: "Ø Puls"), value: summary.averageHeartRate.map { "\($0)" } ?? "–",
                           unit: "/min", detail: summary.maxHeartRate.map { String(localized: "max. \($0)") })
                if let p = record.header.paceTarget, p > 0 {
                    // Vergleich mit der Tempo-Linie: positiv = schneller als die Linie
                    let g = PaceLine(pace: p).gap(boatDistance: summary.distance, activeTime: summary.activeDuration,
                                                  total: record.header.courseLength)
                    MetricTile(String(localized: "Gegen die Tempo-Linie"),
                               value: (g.seconds >= 0 ? "+" : "−") + DSFormat.decimal(abs(g.seconds)), unit: "s",
                               detail: String(localized: "Linie \(Format.duration(p)) /500 m"))
                }
            }
            Text(footLine).font(.footnote).foregroundStyle(Theme.text2)
        }
    }

    /// Schläge, Kalorien und Pausen als Text unter den Kacheln
    private var footLine: String {
        var parts = [String(localized: "\(summary.strokeCount) Schläge"), String(localized: "\(summary.calories) kcal")]
        if summary.pauseCount > 0 { parts.append(String(localized: "Pausen: \(summary.pauseCount)")) }
        return parts.joined(separator: " · ")
    }

    // MARK: Anstrengung

    /// Zusammenfassung direkt nach der Fahrt (nicht im Verlauf)
    private var isLiveResult: Bool {
        controller.record?.id == record.id && (controller.phase == .saving || controller.phase == .done)
            && !controller.discardedTooShort
    }

    private var effortSuggestion: Int? { EffortProfile.estimate(for: record) }

    @ViewBuilder
    private var effortSection: some View {
        if health == .notStored {
            EmptyView()
        } else if isLiveResult {
            switch controller.effortPrompt {
            case .asking:
                EffortPicker(suggestion: effortSuggestion, basisText: record.effort?.basis?.title,
                             initial: record.effort?.userScore, waiting: controller.phase == .saving,
                             onSave: { controller.saveEffort($0) }, onSkip: { controller.skipEffort() })
            case .saving:
                HStack(spacing: DS.Space.s) {
                    ProgressView()
                    Text("Speichere Anstrengung …")
                }
                .foregroundStyle(Theme.text2)
            case .saved, .skipped:
                EffortSummaryRow(userScore: record.effort?.userScore, suggestion: effortSuggestion,
                                 basisText: record.effort?.basis?.title,
                                 skipped: controller.effortPrompt == .skipped, note: controller.effortNote,
                                 changeTitle: controller.effortPrompt == .skipped ? String(localized: "Doch eintragen")
                                    : String(localized: "Ändern"),
                                 onChange: { controller.reopenEffort() })
            }
        } else if record.effort?.userScore != nil || effortSuggestion != nil {
            EffortSummaryRow(userScore: record.effort?.userScore, suggestion: effortSuggestion,
                             basisText: record.effort?.basis?.title)
        }
    }

    // MARK: Phasen bzw. Intervalle (Training)

    @ViewBuilder
    private var intervalsSection: some View {
        let rows = IntervalEvaluation.evaluate(record: record, plan: plan, best2k: best2k)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Text("Intervalle").font(.title2.bold())
                Text("Ampel gegenüber dem Ziel der Phase: Tempo und Schlagzahl.")
                    .font(.footnote).foregroundStyle(Theme.text2)
                ScrollView(.horizontal, showsIndicators: false) {
                    Grid(alignment: .trailing, horizontalSpacing: 18, verticalSpacing: 8) {
                        GridRow {
                            Text("Phase").gridColumnAlignment(.leading)
                            Text("Zeit")
                            Text("Strecke")
                            Text("Tempo /500 m")
                            Text("Ziel")
                            Text("SZ /min")
                            Text("W")
                            Text("Puls")
                            Text("Ampel")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.text2)
                        Divider().overlay(Theme.cardStroke)
                        ForEach(rows) { r in
                            GridRow {
                                HStack(spacing: 8) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Theme.phaseColor(plan?.phases.indices.contains(r.index) == true
                                                               ? plan?.phases[r.index] : nil))
                                        .frame(width: 5, height: 18)
                                    Text(rowTitle(r)).lineLimit(1)
                                    if !r.completed { Text("(abgebrochen)").foregroundStyle(Theme.text2) }
                                }
                                .gridColumnAlignment(.leading)
                                Text(Format.duration(r.duration))
                                Text(Format.distance(r.distance))
                                Text(r.averagePace.map { Format.pace($0) } ?? "–")
                                Text(r.targetPace.map { PlanFormat.paceRange($0) } ?? "–").foregroundStyle(Theme.text2)
                                Text(r.averageStrokeRate.map { DSFormat.decimal($0, digits: 0) } ?? "–")
                                Text(r.averagePower.map { "\($0)" } ?? "–")
                                Text(r.averageHeartRate.map { "\($0)" } ?? "–")
                                lightCell(r)
                            }
                            .font(r.kind == .work ? .body.weight(.semibold).monospacedDigit() : .body.monospacedDigit())
                            .foregroundStyle(r.kind == .work ? Theme.text : Theme.text2)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .dsCard(padding: DS.Space.m, cornerRadius: DS.Radius.tile)
        }
    }

    private func rowTitle(_ r: IntervalResult) -> String {
        if let n = r.workNumber { return String(localized: "Intervall \(n)") }
        return r.kind.title
    }

    @ViewBuilder
    private func lightCell(_ r: IntervalResult) -> some View {
        if r.overallLight == .none {
            Text("–").foregroundStyle(Theme.text3)
        } else {
            HStack(spacing: 4) {
                LightSymbol(light: r.paceLight,
                            shouldIncrease: LightSymbol.paceDirection(r.averagePace ?? 0, target: r.targetPace),
                            size: 17)
                LightSymbol(light: r.strokeRateLight,
                            shouldIncrease: LightSymbol.valueDirection(
                                r.averageStrokeRate ?? 0,
                                target: r.targetStrokeRate.map { Double($0.lowerBound)...Double($0.upperBound) }),
                            size: 17)
            }
        }
    }

    // MARK: Splits je 500 m

    @ViewBuilder
    private var splitsSection: some View {
        if !record.splits.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Text("Splits je 500 m").font(.title2.bold())
                Grid(alignment: .trailing, horizontalSpacing: 18, verticalSpacing: 8) {
                    GridRow {
                        Text("Strecke").gridColumnAlignment(.leading)
                        Text("Zeit")
                        Text("Tempo /500 m")
                        Text("SZ /min")
                        Text("W")
                        Text("Puls")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.text2)
                    Divider().overlay(Theme.cardStroke)
                    ForEach(record.splits) { s in
                        GridRow {
                            Text(splitLabel(s)).gridColumnAlignment(.leading)
                            Text(Format.duration(s.duration, tenths: true))
                            Text(Format.pace(s.pace)).fontWeight(.semibold)
                            Text(s.averageStrokeRate > 0 ? DSFormat.decimal(s.averageStrokeRate, digits: 0) : "–")
                            Text(s.averagePower > 0 ? "\(s.averagePower)" : "–")
                            Text(s.averageHeartRate.map { "\($0)" } ?? "–")
                        }
                        .font(.body.monospacedDigit())
                    }
                }
            }
            .dsCard(padding: DS.Space.m, cornerRadius: DS.Radius.tile)
        }
    }

    /// „500 m“, „1000 m“ …; ein kürzerer letzter Split zeigt seine Länge („bis 1363 m“)
    private func splitLabel(_ s: SplitTime) -> String {
        s.length < 499 ? String(localized: "bis \(Format.distance(s.endDistance))") : Format.distance(s.endDistance)
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
            let maxMinute = points.last?.minute ?? 1
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Text("Pulsverlauf").font(.title2.bold())
                Chart {
                    // Zonen als farbige Bänder hinter der Kurve
                    ForEach(1...HeartRateZones.count, id: \.self) { z in
                        let lower = Double(zones.lowerBound(zone: z))
                        let upper = z < HeartRateZones.count ? Double(zones.lowerBound(zone: z + 1)) : Double(hi)
                        if upper > Double(lo) && lower < Double(hi) {
                            RectangleMark(xStart: .value("Start", 0), xEnd: .value("Ende", maxMinute),
                                          yStart: .value("von", max(lower, Double(lo))),
                                          yEnd: .value("bis", min(upper, Double(hi))))
                                .foregroundStyle(Theme.zoneColor(z).opacity(0.16))
                        }
                    }
                    ForEach(points) { p in
                        LineMark(x: .value("Minute", p.minute), y: .value("Puls", p.bpm))
                            .foregroundStyle(Theme.text)
                            .interpolationMethod(.monotone)
                    }
                }
                .chartYScale(domain: lo...hi)
                .chartXAxis {
                    AxisMarks { v in
                        AxisGridLine()
                        AxisValueLabel {
                            if let m = v.as(Double.self) { Text(Format.duration(m * 60)) }
                        }
                    }
                }
                .chartXAxisLabel(String(localized: "Zeit"))
                .chartYAxisLabel(String(localized: "Puls /min"))
                .frame(height: 220)
                .accessibilityLabel(Text("Pulsverlauf"))
                zoneBar
            }
            .dsCard(padding: DS.Space.m, cornerRadius: DS.Radius.tile)
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
                .accessibilityHidden(true)
                HStack(spacing: 14) {
                    ForEach(Array(secs.enumerated()), id: \.offset) { z, s in
                        if s > 0 {
                            HStack(spacing: 4) {
                                Circle().fill(Theme.zoneColor(z)).frame(width: 8, height: 8)
                                Text("\(Theme.zoneName(z)) \(Format.duration(s))")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(Theme.text2)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Anstrengung

/// Farbe je Stufe der Anstrengungsskala (aus dem Satz der Pulszonen)
enum EffortStyle {
    static func color(_ score: Int) -> Color {
        switch EffortScale.level(score) {
        case .easy: return Theme.zoneColor(2)
        case .moderate: return Theme.zoneColor(3)
        case .hard: return Theme.zoneColor(4)
        case .allOut: return Theme.zoneColor(5)
        }
    }
}

/// Abfrage der Anstrengung 1–10 mit Apples Stufen (1–3 leicht, 4–6 moderat, 7–8 hart, 9–10 alles gegeben).
/// Grosse Tasten; ein Tipp auf eine Zahl speichert. Der Vorschlag der App ist gestrichelt umrandet.
struct EffortPicker: View {
    let suggestion: Int?
    let basisText: String?
    var waiting: Bool
    var skipTitle: String
    let initial: Int?
    let onSave: (Int) -> Void
    let onSkip: () -> Void

    init(suggestion: Int?, basisText: String?, initial: Int?, waiting: Bool = false,
         skipTitle: String = String(localized: "Überspringen"), onSave: @escaping (Int) -> Void,
         onSkip: @escaping () -> Void) {
        self.suggestion = suggestion
        self.basisText = basisText
        self.waiting = waiting
        self.skipTitle = skipTitle
        self.initial = initial
        self.onSave = onSave
        self.onSkip = onSkip
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Wie anstrengend war es?").font(.title2.bold())
                Text("Anstrengung 1–10, wie in Apple Health. Ein Tipp speichert.")
                    .font(.subheadline).foregroundStyle(Theme.text2)
            }
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach([1, 6], id: \.self) { first in
                    GridRow {
                        ForEach(first..<(first + 5), id: \.self) { n in scoreButton(n) }
                    }
                }
            }
            .disabled(waiting)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) { legendItems }
                VStack(alignment: .leading, spacing: 4) { legendItems }
            }
            .font(.caption)
            .foregroundStyle(Theme.text2)
            if waiting {
                Label("Warte auf Apple Health …", systemImage: "hourglass").font(.subheadline)
                    .foregroundStyle(Theme.text2)
            } else if let suggestion {
                Label {
                    Text(EffortSuggestionText.make(suggestion, basis: basisText))
                } icon: {
                    Image(systemName: "wand.and.stars")
                }
                .font(.subheadline)
                .foregroundStyle(Theme.text2)
            }
            Button(skipTitle, action: onSkip)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.link)
                .buttonStyle(.borderless)
        }
        .dsCard(padding: DS.Space.m, cornerRadius: DS.Radius.tile)
    }

    @ViewBuilder
    private var legendItems: some View {
        ForEach(EffortScale.Level.allCases, id: \.self) { level in
            HStack(spacing: 4) {
                Circle().fill(EffortStyle.color(level.scores.lowerBound)).frame(width: 8, height: 8)
                Text("\(level.scores.lowerBound)–\(level.scores.upperBound) \(level.title)")
            }
        }
    }

    private func scoreButton(_ n: Int) -> some View {
        let selected = n == initial
        let suggested = n == suggestion
        return Button { onSave(n) } label: {
            VStack(spacing: 2) {
                Text("\(n)").font(Theme.number(30))
                Text(suggested ? String(localized: "Vorschlag") : " ").font(.caption2.bold())
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .foregroundStyle(selected ? Color.black : Theme.text)
            .background(RoundedRectangle(cornerRadius: 12)
                .fill(selected ? EffortStyle.color(n) : EffortStyle.color(n).opacity(0.2)))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(suggested ? Theme.text.opacity(0.85) : Color.clear,
                              style: StrokeStyle(lineWidth: 2, dash: [5, 3])))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Anstrengung \(n), \(EffortScale.level(n).title)"))
        .accessibilityHint(suggested ? Text("Vorschlag der App") : Text(""))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Anzeige der Anstrengung: eigene Einschätzung gross, Vorschlag der App klein; optional mit Taste zum Ändern
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
                Text("Anstrengung").dsLabelStyle()
                if let userScore {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(userScore)").font(Theme.number(30)).foregroundStyle(EffortStyle.color(userScore))
                        Text(EffortScale.level(userScore).title).font(.headline)
                        Text("eigene Einschätzung").font(.footnote).foregroundStyle(Theme.text2)
                    }
                } else {
                    (skipped ? Text("Übersprungen – keine eigene Einschätzung") : Text("Keine eigene Einschätzung"))
                        .font(.headline)
                }
                if let suggestion {
                    Text(EffortSuggestionText.make(suggestion, basis: basisText))
                        .font(.footnote).foregroundStyle(Theme.text2)
                }
                if let note {
                    Text(note).font(.footnote).foregroundStyle(Theme.warn)
                }
            }
            Spacer(minLength: 8)
            if let changeTitle, let onChange {
                Button(changeTitle, action: onChange)
                    .buttonStyle(SecondaryButtonStyle(compact: true, fullWidth: false))
            }
        }
        .dsCard(padding: DS.Space.m, cornerRadius: DS.Radius.tile)
    }
}

/// „Vorschlag der App: 3 · leicht (aus dem Puls)“ als ganzer, lokalisierbarer Satz
enum EffortSuggestionText {
    static func make(_ suggestion: Int, basis: String?) -> String {
        let label = EffortScale.label(suggestion)
        if let basis { return String(localized: "Vorschlag der App: \(label) (\(basis))") }
        return String(localized: "Vorschlag der App: \(label)")
    }
}
