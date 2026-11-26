import SwiftUI
import SwiftData
import RowCoachKit

/// Einstellungen des Verlaufs
enum HistorySettings {
    /// Simulatorfahrten im Verlauf zeigen (Einstellungen → Entwickler; Standard aus). Beispieltrainings
    /// (`-seedDemoHistory`) erscheinen immer.
    static let showSimulatedKey = "history.showSimulated"
}

/// Verlauf: oben die Wochenansicht, darunter die Fahrten nach Kalenderwoche (neueste zuerst). Titel ist das
/// Programm (sonst „Frei rudern“), Untertitel Strecke und Datum; Zustände als Text-Chips.
struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \StoredWorkout.startDate, order: .reverse) private var workouts: [StoredWorkout]
    @Environment(WorkoutRecovery.self) private var recovery
    @Environment(HomeModel.self) private var home
    @AppStorage(HistorySettings.showSimulatedKey) private var showSimulated = false

    init() {}

    /// Sichtbare Fahrten: Simulatorfahrten nur mit Schalter, Beispieltrainings immer
    private var visible: [StoredWorkout] {
        _ = home.stats   // neu zeichnen, sobald die Kennzahlen (und damit die Herkunft) gelesen sind
        return workouts.filter { w in
            guard w.simulated, !showSimulated else { return true }
            return home.session(id: w.id)?.origin == .demo
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if visible.isEmpty {
                    DSEmptyState(title: String(localized: "Noch keine Fahrten"), systemImage: "figure.rower",
                                 text: String(localized: "Nach jeder Fahrt ab 100 m und 1 min erscheint hier ein Eintrag."))
                } else {
                    List {
                        if let stats = home.stats {
                            Section {
                                WeekCard(stats: stats, compact: true)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                                    .listRowBackground(Color.clear)
                            }
                            Section {
                                NavigationLink { RecordsView() } label: {
                                    Label("Bestmarken und Meilensteine", systemImage: "trophy")
                                }
                            }
                            .listRowBackground(Theme.card)
                        }
                        if let notice = recovery.notice {
                            Section {
                                RecoveryNoticeRow(text: notice) { recovery.notice = nil }
                            }
                            .listRowBackground(Theme.card)
                        }
                        ForEach(weekGroups, id: \.key) { group in
                            Section {
                                ForEach(group.items) { w in
                                    NavigationLink {
                                        HistoryDetailView(item: w)
                                    } label: {
                                        HistoryRow(item: w, session: home.session(id: w.id))
                                    }
                                }
                                .onDelete { offsets in delete(offsets, in: group.items) }
                            } header: {
                                Text(group.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.text2)
                                    .textCase(nil)
                            }
                            .listRowBackground(Theme.card)
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .dsPageBackground()
            .navigationTitle(Text("Verlauf"))
            .appToolbar()
        }
    }

    private struct WeekGroup {
        let key: String
        let title: String
        let items: [StoredWorkout]
    }

    /// Gruppen nach Kalenderwoche in der Reihenfolge der Abfrage (neueste zuerst):
    /// „KW 48 · 3 Fahrten · 81 min · leicht/hart“
    private var weekGroups: [WeekGroup] {
        let cal = TrainingCalendar.swiss()
        var keys: [String] = []
        var items: [String: [StoredWorkout]] = [:]
        var weeks: [String: Int] = [:]
        for w in visible {
            let c = cal.dateComponents([.weekOfYear, .yearForWeekOfYear], from: w.startDate)
            let key = "\(c.yearForWeekOfYear ?? 0)-\(c.weekOfYear ?? 0)"
            if items[key] == nil { keys.append(key); weeks[key] = c.weekOfYear ?? 0 }
            items[key, default: []].append(w)
        }
        let thisYear = cal.component(.yearForWeekOfYear, from: Date())
        return keys.map { key -> WeekGroup in
            let list = items[key] ?? []
            let minutes = Int((list.reduce(0) { $0 + $1.duration } / 60).rounded())
            let week = weeks[key] ?? 0
            let year = Int(key.split(separator: "-").first ?? "") ?? thisYear
            let levels = Set(list.compactMap { home.session(id: $0.id)?.intensity(best2k: TrainingSettings.best2k) })
            let levelText = IntensityLevel.allCases.filter { levels.contains($0) }.map(\.title).joined(separator: "/")
            let rides = list.count == 1 ? String(localized: "1 Fahrt") : String(localized: "\(list.count) Fahrten")
            var title = year == thisYear ? String(localized: "KW \(week)") : String(localized: "KW \(week) \(String(year))")
            title += " · \(rides) · " + String(localized: "\(minutes) min")
            if !levelText.isEmpty { title += " · \(levelText)" }
            return WeekGroup(key: key, title: title, items: list)
        }
    }

    private func delete(_ offsets: IndexSet, in items: [StoredWorkout]) {
        for i in offsets { context.delete(items[i]) }
        try? context.save()
    }
}

private struct HistoryRow: View {
    let item: StoredWorkout
    let session: TrainingSession?

    private var title: String {
        if let id = session?.planId, let plan = PlanLibrary.plan(id: id) { return plan.shortName }
        if let name = session?.planName { return PlanTitle.short(name) }
        if session?.planId != nil { return String(localized: "Training") }
        return String(localized: "Frei rudern")
    }

    private var subtitle: String {
        let course = item.courseTitle.map { HomeFormat.courseShort($0) }
        let date = item.startDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
        return [course, date].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(Theme.text)
                Text(subtitle).font(.subheadline).foregroundStyle(Theme.text2)
                chips
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Format.distance(item.distance)) · \(Format.duration(item.duration))")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(Theme.text)
                Text("\(Format.pace(item.averagePace)) /500 m")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.text2)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// Text-Chips statt Symbolen
    @ViewBuilder
    private var chips: some View {
        let isDemo = session?.origin == .demo
        let items = chipItems(isDemo: isDemo)
        if !items.isEmpty {
            HStack(spacing: 6) {
                ForEach(items, id: \.text) { c in DSChip(c.text, tone: c.tone) }
            }
        }
    }

    private struct ChipItem {
        let text: String
        let tone: DSChip.Tone
    }

    private func chipItems(isDemo: Bool) -> [ChipItem] {
        var out: [ChipItem] = []
        if let effort = item.effortScore {
            out.append(ChipItem(text: String(localized: "Anstrengung \(effort)"), tone: .neutral))
        }
        if isDemo {
            out.append(ChipItem(text: String(localized: "Beispiel"), tone: .neutral))
        } else if item.simulated {
            out.append(ChipItem(text: String(localized: "Simulator"), tone: .neutral))
        } else if !item.savedToHealth {
            out.append(ChipItem(text: String(localized: "Nicht in Health"), tone: .warn))
        }
        if item.interrupted {
            out.append(ChipItem(text: String(localized: "Unterbrochen"), tone: .warn))
        } else if !item.completedCourse {
            out.append(ChipItem(text: String(localized: "Vorzeitig beendet"), tone: .neutral))
        }
        return out
    }
}

/// Programmname ohne lange Zusätze („Lockere Grundlage 30 Minuten“ → „Lockere Grundlage 30 min“)
enum PlanTitle {
    static func short(_ name: String) -> String {
        name.replacingOccurrences(of: " Minuten", with: " min").replacingOccurrences(of: " minutes", with: " min").replacingOccurrences(of: " x ", with: " × ")
    }
}

/// Hinweis nach einer wiederhergestellten Fahrt (Verlauf und Startseite)
struct RecoveryNoticeRow: View {
    let text: String
    let onClose: () -> Void

    init(text: String, onClose: @escaping () -> Void) {
        self.text = text
        self.onClose = onClose
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "bolt.slash").foregroundStyle(Theme.warn)
            Text(text).font(.subheadline)
            Spacer(minLength: 8)
            Button(action: onClose) {
                Image(systemName: "xmark").font(.caption.bold())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Hinweis schliessen")
        }
    }
}

struct HistoryDetailView: View {
    let item: StoredWorkout
    /// „Nochmal“: gleiche Strecke bzw. gleiches Programm starten (im Sheet: erst schliessen, dann starten)
    var onAgain: ((DailySuggestion.Option) -> Void)? = nil

    @Environment(\.rowingLaunch) private var launch

    @Environment(HealthService.self) private var health
    @Environment(WorkoutRecovery.self) private var recovery
    @State private var busy = false
    @State private var resultText: String?
    @State private var confirmSimulator = false
    @State private var showEffort = false

    var body: some View {
        if let record = item.record {
            SummaryView(record: record, health: item.savedToHealth ? .saved : .notSaved)
                .safeAreaInset(edge: .bottom) { healthBar(isDemo: record.isDemo) }
                .sheet(isPresented: $showEffort) { effortSheet(record) }
                .confirmationDialog("Simulator-Training in Apple Health speichern?", isPresented: $confirmSimulator,
                                    titleVisibility: .visible) {
                    Button("Trotzdem speichern") { save() }
                    Button("Abbrechen", role: .cancel) {}
                } message: {
                    Text("Dieses Training stammt vom Simulator, nicht vom Rudergerät.")
                }
        } else {
            ContentUnavailableView("Daten nicht lesbar", systemImage: "exclamationmark.triangle",
                                   description: Text("Dieses Training kann nicht angezeigt werden."))
        }
    }

    /// Belastung nachträglich eintragen oder ändern (ersetzt die eigene Probe dieser App in Apple Health)
    private func effortSheet(_ record: WorkoutRecord) -> some View {
        NavigationStack {
            ScrollView {
                EffortPicker(suggestion: EffortProfile.estimate(for: record), basisText: record.effort?.basis?.title,
                             initial: record.effort?.userScore, skipTitle: String(localized: "Abbrechen"),
                             onSave: { score in saveEffort(score) }, onSkip: { showEffort = false })
                    .padding()
            }
            .dsSheetChrome(String(localized: "Anstrengung")) { showEffort = false }
        }
        .presentationDetents([.large])
    }

    /// `isDemo`: Beispieltraining aus dem Testbetrieb – nie nach Apple Health
    /// Aktionen in einer dunklen Fussleiste (aus dem Gestaltungssystem)
    /// Wahl für „Nochmal“: Programm auf der Strecke, sonst frei auf der Strecke
    private func againOption(_ record: WorkoutRecord) -> DailySuggestion.Option {
        if let planId = record.header.workoutPlanId, PlanLibrary.plan(id: planId) != nil {
            return .plan(planId: planId, courseId: record.header.courseId)
        }
        return .free(courseId: record.header.courseId)
    }

    @ViewBuilder
    private func healthBar(isDemo: Bool) -> some View {
        DSFooterBar {
            if let record = item.record {
                Button {
                    let option = againOption(record)
                    if let onAgain { onAgain(option) } else { launch?.callAsFunction(option) }
                } label: {
                    Label("Nochmal", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(PrimaryButtonStyle(compact: true))
                .frame(maxWidth: 820)
            }
            HStack(spacing: DS.Space.m) {
                Button {
                    showEffort = true
                } label: {
                    Label(item.effortScore == nil ? String(localized: "Anstrengung eintragen")
                          : String(localized: "Anstrengung ändern"), systemImage: "flame")
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .buttonStyle(SecondaryButtonStyle(compact: true))
                .disabled(busy)
                if !isDemo, health.status != .unavailable {
                    Button {
                        if item.simulated { confirmSimulator = true } else { save() }
                    } label: {
                        HStack(spacing: 8) {
                            if busy { ProgressView() } else { Image(systemName: "heart.text.square") }
                            Text(item.savedToHealth ? String(localized: "Health prüfen")
                                 : String(localized: "In Apple Health speichern"))
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle(compact: true))
                    .disabled(busy)
                }
            }
            .frame(maxWidth: 820)
            if let resultText {
                Text(resultText).font(.footnote).foregroundStyle(Theme.text2)
            }
        }
    }

    private func saveEffort(_ score: Int) {
        guard !busy else { return }
        showEffort = false
        busy = true
        resultText = nil
        Task {
            // Neue Freigabe für die Belastung anfragen (der Dialog zeigt nur die noch offenen Typen)
            if health.status != .unavailable, health.effortStatus == .notDetermined { await health.connect() }
            resultText = await recovery.setEffort(item, score: score)
            busy = false
        }
    }

    private func save() {
        guard !busy else { return }
        busy = true
        resultText = nil
        Task {
            if health.status != .authorized { await health.connect() }
            let result = await recovery.saveToHealth(item)
            resultText = [result.message, recovery.routeNote, recovery.effortNote].compactMap { $0 }.joined(separator: " ")
            busy = false
        }
    }
}
