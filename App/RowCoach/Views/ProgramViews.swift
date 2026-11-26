import SwiftUI
import RowCoachKit

// Tab „Pläne“: Trainingspläne über mehrere Wochen (training_plans.json, Regeln in RowCoachKit,
// docs/trainingsplaene/UMSETZUNG.md). Liste mit Filtern → Plandetail → „Plan starten“ (Wunschtage, Startdatum) →
// aktiver Plan mit Wochenansicht, Fortschritt, Pause und Tausch gegen die leichte Variante.

/// Navigation im Tab „Pläne“
enum ProgramRoute: Hashable {
    /// Detailansicht eines Plans
    case program(String)
    /// aktiver Plan: Wochenansicht
    case active
}

struct ProgramDestination: View {
    let route: ProgramRoute

    var body: some View {
        switch route {
        case .program(let id):
            if let p = ProgramLibrary.program(id: id) {
                ProgramDetailView(program: p)
            } else {
                DSEmptyState(title: String(localized: "Plan nicht gefunden"), systemImage: "questionmark.circle")
            }
        case .active:
            ActiveProgramView()
        }
    }
}

// MARK: - Texte

enum ProgramFormat {
    /// „12 Wochen“
    static func weeks(_ n: Int) -> String { String(localized: "\(n) Wochen") }

    /// „3–4 × pro Woche“ bzw. „3 × pro Woche“
    static func sessions(_ r: ClosedRange<Int>) -> String {
        r.lowerBound == r.upperBound ? String(localized: "\(r.lowerBound) × pro Woche")
            : String(localized: "\(r.lowerBound)–\(r.upperBound) × pro Woche")
    }

    /// „70–150 min pro Woche“
    static func minutes(_ r: ClosedRange<Int>?) -> String? {
        guard let r else { return nil }
        return String(localized: "\(r.lowerBound)–\(r.upperBound) min pro Woche")
    }

    /// „Mo 30. Nov.“ in der Sprache des Geräts
    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// Titel des Programms einer Einheit
    static func sessionName(_ planId: String) -> String {
        PlanLibrary.plan(id: planId)?.shortName ?? planId
    }

    /// Länge des Programms einer Einheit
    static func sessionLength(_ planId: String, best2k: Double) -> String {
        PlanLibrary.plan(id: planId).map { PlanFormat.planLength($0, best2k: best2k) } ?? ""
    }

    /// Text eines Hinweises
    static func notice(_ n: ProgramNotice) -> String {
        switch n.kind {
        case .recoveryCheck:
            return String(localized: "Lockere Einheiten fühlten sich zuletzt hart an. Die nächste Woche wird leichter – Schlaf, Krankheit und Stress im Blick behalten.")
        case .paceLowered:
            return String(localized: "Harte Einheiten waren zuletzt am Anschlag. Die Tempoziele sind bis zum nächsten Test etwas langsamer.")
        case .retestSuggested:
            return String(localized: "Ein neuer Test lohnt sich: Deine Tempoziele sind vermutlich nicht mehr aktuell.")
        case .pauseSuggested:
            return String(localized: "Auch in der leichteren Woche fühlt sich vieles hart an. Eine Pause mit sanftem Wiedereinstieg ist sinnvoll.")
        case .weekRepeated:
            return String(localized: "Diese Woche läuft noch einmal – das ist völlig in Ordnung.")
        case .autoPaused:
            return String(localized: "Der Plan ruht, weil zehn Tage keine Fahrt dazukam. Fortsetzen, wann es passt.")
        case .resumed:
            return String(localized: "Willkommen zurück. Der Plan geht in einer passenden Woche weiter.")
        case .restarted:
            return String(localized: "Nach der langen Pause beginnt der Plan von vorne.")
        case .referenceImproved:
            if let v = n.value {
                return String(localized: "Neue Referenz aus dem Test: 2000 m in \(Format.duration(v)). Die Tempoziele sind angepasst.")
            }
            return String(localized: "Neue Referenz aus dem Test übernommen.")
        case .referenceWorse:
            return String(localized: "Der Test war langsamer als deine Referenz.")
        case .finished:
            return String(localized: "Plan geschafft. Stark!")
        }
    }

    static func noticeIcon(_ k: ProgramNotice.Kind) -> String {
        switch k {
        case .recoveryCheck, .pauseSuggested: return "bed.double"
        case .paceLowered: return "gauge.with.dots.needle.33percent"
        case .retestSuggested: return "stopwatch"
        case .weekRepeated: return "arrow.counterclockwise"
        case .autoPaused: return "pause.circle"
        case .resumed, .restarted: return "play.circle"
        case .referenceImproved: return "arrow.up.right.circle"
        case .referenceWorse: return "questionmark.circle"
        case .finished: return "flag.checkered"
        }
    }
}

extension PlanIntensity {
    /// Stufe für Farben (wie bei den Programmen)
    var level: IntensityLevel {
        switch self {
        case .easy: return .easy
        case .moderate: return .moderate
        case .hard, .max: return .hard
        }
    }
}

// MARK: - Liste

/// Planliste mit Filtern (Ziel/Kategorie, Niveau, Wochen, Suche); oben der aktive Plan
struct ProgramListView: View {
    @Environment(ProgramStore.self) private var store
    @AppStorage(TrainingSettings.best2kKey) private var best2k = PaceTargets.defaultBest2k
    @State private var filter = ProgramFilter()
    private let columns = [GridItem(.adaptive(minimum: 320), spacing: DS.Space.m, alignment: .top)]

    private var programs: [TrainingProgram] { ProgramLibrary.programs }
    private var categories: [String] { TrainingProgramCategory.order.filter { c in programs.contains { $0.category == c } } }

    /// Niveau für den Filter: deutscher Quellwert (Kennung) und Anzeige
    private struct LevelOption: Hashable {
        let id: String
        let label: String
    }

    /// Niveaus in fester Reihenfolge (Einsteiger, Fortgeschritten, Leistung)
    private var levels: [LevelOption] {
        var seen = Set<String>(), out: [LevelOption] = []
        for p in programs where !p.levelID.isEmpty && seen.insert(p.levelID).inserted {
            out.append(LevelOption(id: p.levelID, label: p.level))
        }
        func rank(_ l: String) -> Int {
            let x = l.lowercased()
            return x.contains("einsteig") ? 0 : (x.contains("fortgeschritten") ? 1 : 2)
        }
        return out.sorted { rank($0.id) < rank($1.id) }
    }

    private var weekClasses: [ProgramWeekClass] {
        ProgramWeekClass.allCases.filter { c in programs.contains { $0.weekClass == c } }
    }

    private var shown: [TrainingProgram] { filter.apply(programs) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                if store.active != nil {
                    NavigationLink(value: ProgramRoute.active) {
                        ActiveProgramCard()
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Wochenansicht des aktiven Plans"))
                }
                if programs.isEmpty {
                    DSEmptyState(title: String(localized: "Keine Pläne"), systemImage: "calendar",
                                 text: String(localized: "training_plans.json fehlt im App-Bundle oder ist nicht lesbar."))
                        .padding(.top, 60)
                } else {
                    filters
                    if filter.isActive { filterLine }
                    if shown.isEmpty {
                        DSEmptyState(title: String(localized: "Kein Plan passt"),
                                     systemImage: "line.3.horizontal.decrease.circle",
                                     text: String(localized: "Filter ändern oder löschen."),
                                     actionTitle: String(localized: "Filter löschen"), action: { filter = ProgramFilter() })
                            .padding(.top, 40)
                    } else {
                        LazyVGrid(columns: columns, spacing: DS.Space.m) {
                            ForEach(shown) { p in
                                NavigationLink(value: ProgramRoute.program(p.id)) {
                                    ProgramTile(program: p, best2k: best2k, isActive: store.active?.programId == p.id)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, DS.Space.l)
            .padding(.vertical, DS.Space.m)
        }
        .dsPageBackground()
        .navigationTitle(Text("Pläne"))
        .searchable(text: $filter.text, prompt: Text("Plan suchen"))
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text("Trainingspläne über mehrere Wochen: Einheiten an deinen Wunschtagen, Verschieben und Pausen inklusive.")
                .font(.subheadline)
                .foregroundStyle(Theme.text2)
            Picker(selection: $filter.levelID) {
                Text("Alle Niveaus").tag("")
                ForEach(levels, id: \.self) { Text($0.label).tag($0.id) }
            } label: {
                Text("Niveau")
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 560)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.s) {
                    chip(String(localized: "Alle Ziele"), selected: filter.category.isEmpty) { filter.category = "" }
                    ForEach(categories, id: \.self) { c in
                        chip(TrainingProgramCategory.label(c), selected: filter.category == c) {
                            filter.category = filter.category == c ? "" : c
                        }
                    }
                }
            }
            if weekClasses.count > 1 {
                Menu {
                    Button(String(localized: "Alle")) { filter.weeks = nil }
                    ForEach(weekClasses) { w in
                        Button { filter.weeks = filter.weeks == w ? nil : w } label: {
                            if filter.weeks == w { Label(w.label, systemImage: "checkmark") } else { Text(w.label) }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(filter.weeks?.label ?? String(localized: "Jede Länge"))
                        Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                    }
                    .font(.subheadline.weight(filter.weeks != nil ? .semibold : .regular))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 36)
                    .background(Capsule().fill(filter.weeks != nil ? Color.white.opacity(0.22) : Color.white.opacity(0.07)))
                    .overlay(Capsule().strokeBorder(filter.weeks != nil ? Color.white.opacity(0.6) : Color.clear))
                    .foregroundStyle(Theme.text)
                }
            }
        }
    }

    private var filterLine: some View {
        HStack(spacing: DS.Space.m) {
            Image(systemName: "line.3.horizontal.decrease.circle.fill").foregroundStyle(Theme.text2)
            Text("\(shown.count) von \(programs.count) Plänen").font(.subheadline).foregroundStyle(Theme.text2)
            Button("Filter löschen") { filter = ProgramFilter() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.link)
                .buttonStyle(.borderless)
            Spacer(minLength: 0)
        }
    }

    private func chip(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(Capsule().fill(selected ? Color.white.opacity(0.22) : Color.white.opacity(0.07)))
                .overlay(Capsule().strokeBorder(selected ? Color.white.opacity(0.6) : Color.clear))
                .foregroundStyle(Theme.text)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Kachel eines Plans: Name, Niveau, Wochen · Einheiten · Minuten, Kurzbeschreibung, Wochenbalken
private struct ProgramTile: View {
    let program: TrainingProgram
    let best2k: Double
    var isActive = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(program.name).font(.headline).lineLimit(2).minimumScaleFactor(0.85)
                Spacer(minLength: DS.Space.s)
                if !program.level.isEmpty { LevelBadge(level: program.level) }
            }
            HStack(spacing: DS.Space.s) {
                Label(ProgramFormat.weeks(program.weeks), systemImage: "calendar")
                Text("·")
                Text(ProgramFormat.sessions(program.sessionsPerWeek))
            }
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(Theme.text2)
            Text(program.summary)
                .font(.subheadline)
                .foregroundStyle(Theme.text2)
                .lineLimit(3, reservesSpace: true)
            ProgramWeekBars(program: program, best2k: best2k, height: 30)
            HStack(spacing: DS.Space.s) {
                DSChip(TrainingProgramCategory.label(program.category))
                if isActive { DSChip(String(localized: "Aktiv"), tone: .ok, systemImage: "checkmark") }
            }
        }
        .dsCard(padding: DS.Space.m, cornerRadius: DS.Radius.tile)
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Plan ansehen"))
    }
}

/// Balken je Woche: Höhe nach geschätzten Minuten, leichtere Wochen und Tapering heller, Woche mit Zieleinheit
/// markiert; `current` hebt die laufende Woche hervor
struct ProgramWeekBars: View {
    let program: TrainingProgram
    let best2k: Double
    var height: CGFloat = 30
    var current: Int? = nil

    var body: some View {
        let mins = program.weekMinutes(workouts: PlanLibrary.plans, best2k: best2k)
        let top = max(mins.max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: program.weeks > 16 ? 2 : 3) {
            ForEach(Array(program.weekPlans.enumerated()), id: \.offset) { i, w in
                let event = w.sessions.contains(where: \.event)
                RoundedRectangle(cornerRadius: 2)
                    .fill(color(w, event: event).opacity(current == nil || current == i + 1 ? 1 : 0.55))
                    .frame(maxWidth: .infinity)
                    .frame(height: max(4, height * CGFloat(mins[i] / top)))
                    .overlay(alignment: .top) {
                        if current == i + 1 {
                            RoundedRectangle(cornerRadius: 2).stroke(Color.white, lineWidth: 1.5)
                        }
                    }
            }
        }
        .frame(height: height, alignment: .bottom)
        .accessibilityHidden(true)
    }

    private func color(_ w: ProgramWeek, event: Bool) -> Color {
        if event { return Theme.accent }
        if w.deload || w.taper { return Theme.levelColor(.easy).opacity(0.55) }
        return Theme.levelColor(.easy)
    }
}

// MARK: - Detail

/// Detailansicht: Ziel, Voraussetzungen, Regeln, Wochen mit Fokus und Einheiten (Phasenbalken), Quellen;
/// „Plan starten“ unten
struct ProgramDetailView: View {
    let program: TrainingProgram
    @Environment(ProgramStore.self) private var store
    @Environment(AppRouter.self) private var router
    @AppStorage(TrainingSettings.best2kKey) private var best2k = PaceTargets.defaultBest2k
    @State private var showStart = false

    private var isActive: Bool { store.active?.programId == program.id }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.Space.l) {
                header
                rules
                Text("Wochen").font(.title3.bold())
                ForEach(program.weekPlans, id: \.week) { w in
                    ProgramWeekCard(week: w, best2k: best2k)
                }
                sources
            }
            .padding(DS.Space.l)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .dsPageBackground()
        .safeAreaInset(edge: .bottom) { actions }
        .navigationTitle(program.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showStart) {
            ProgramStartSheet(program: program) {
                showStart = false
                router.programsPath.append(ProgramRoute.active)
            }
        }
    }

    private var actions: some View {
        DSFooterBar {
            if isActive {
                NavigationLink(value: ProgramRoute.active) {
                    Label("Zum aktiven Plan", systemImage: "calendar")
                }
                .buttonStyle(PrimaryButtonStyle(compact: true))
                .frame(maxWidth: 820)
            } else {
                Button { showStart = true } label: {
                    Label("Plan starten", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle(compact: true))
                .keyboardShortcut(.defaultAction)
                .frame(maxWidth: 820)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Space.s + 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(program.name).font(.largeTitle.bold())
                Spacer(minLength: DS.Space.s)
                if !program.level.isEmpty { LevelBadge(level: program.level) }
            }
            HStack(spacing: DS.Space.s) {
                Label(ProgramFormat.weeks(program.weeks), systemImage: "calendar")
                Text("·")
                Text(ProgramFormat.sessions(program.sessionsPerWeek))
                if let m = ProgramFormat.minutes(program.minutesPerWeek) {
                    Text("·")
                    Text(m)
                }
            }
            .font(.headline.monospacedDigit())
            .foregroundStyle(Theme.text2)
            if !program.summary.isEmpty { Text(program.summary).font(.body) }
            if !program.goal.isEmpty {
                Label(program.goal, systemImage: "target").font(.subheadline)
            }
            if !program.prerequisites.isEmpty {
                Label(program.prerequisites, systemImage: "checklist").font(.subheadline).foregroundStyle(Theme.text2)
            }
            if program.season == "winter" {
                Label("Passt besonders in den Winter (Grundlagenzeit).", systemImage: "snowflake")
                    .font(.subheadline).foregroundStyle(Theme.text2)
            }
            ProgramWeekBars(program: program, best2k: best2k, height: 56)
                .padding(.top, DS.Space.xs)
            HStack(spacing: DS.Space.m) {
                legend(Theme.levelColor(.easy), String(localized: "Woche"))
                legend(Theme.levelColor(.easy).opacity(0.55), String(localized: "leichter / Tapering"))
                legend(Theme.accent, String(localized: "Zieleinheit"))
            }
            .font(.caption)
            .foregroundStyle(Theme.text2)
        }
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 12, height: 8)
            Text(text)
        }
    }

    private var rules: some View {
        let r = program.rules
        return VStack(alignment: .leading, spacing: 6) {
            Text("So läuft der Plan").font(.title3.bold())
            Group {
                Label(String(localized: "Harte Einheiten mindestens \(r.hardSessionsMinGapHours) Stunden auseinander, auch über das Wochenende."),
                      systemImage: "bolt.heart")
                if r.maxConsecutiveDays <= 1 {
                    Label("Immer ein Ruhetag zwischen zwei Einheiten.", systemImage: "bed.double")
                } else {
                    Label(String(localized: "Höchstens \(Int(r.maxConsecutiveDays)) Trainingstage hintereinander."), systemImage: "bed.double")
                }
                switch r.missedSessionPolicy {
                case .shift:
                    Label("Verpasst? Die Einheit rückt nach, die Woche wird höchstens zwei Tage länger.", systemImage: "arrow.right.circle")
                case .replaceEasy:
                    Label("Verpasst? Die Einheit rückt in der Woche nach – eine harte wird notfalls zur lockeren Grundlage.", systemImage: "arrow.right.circle")
                case .skip:
                    Label("Verpasst? Die Einheit entfällt, der Plan läuft nach Kalender weiter.", systemImage: "arrow.right.circle")
                }
                if let n = r.repeatWeekIfMissed {
                    Label(String(localized: "Fehlen \(n) Einheiten einer Woche, kommt die Woche noch einmal."), systemImage: "arrow.counterclockwise")
                }
                if let from = r.repeatFrom {
                    Label(String(localized: "Offener Plan: Nach der letzten Woche geht es ab Woche \(Int(from)) weiter."), systemImage: "repeat")
                }
                if program.weekPlans.contains(where: { $0.sessions.contains(where: \.event) }) {
                    Label("Die Zieleinheit wird verschoben, nie gestrichen.", systemImage: "flag.checkered")
                }
            }
            .font(.subheadline)
            .foregroundStyle(Theme.text2)
            Text("Belege: \(program.evidence)")
                .font(.footnote)
                .foregroundStyle(Theme.text3)
                .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var sources: some View {
        if !program.sources.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Text("Quellen").font(.title3.bold())
                ForEach(Array(program.sources.enumerated()), id: \.offset) { _, s in
                    VStack(alignment: .leading, spacing: 2) {
                        if let u = s.url, let url = URL(string: u) {
                            Link(s.title.isEmpty ? u : s.title, destination: url).foregroundStyle(Theme.link)
                        } else {
                            Text(s.title)
                        }
                        let meta = [s.publisher, s.published].compactMap { $0 }.filter { !$0.isEmpty }
                        if !meta.isEmpty {
                            Text(meta.joined(separator: ", ")).font(.caption).foregroundStyle(Theme.text2)
                        }
                    }
                    .font(.subheadline)
                }
            }
        }
    }
}

/// Eine Woche im Plandetail: Fokus, Kennzeichen, Einheiten mit Phasenbalken (antippen öffnet das Programm)
struct ProgramWeekCard: View {
    let week: ProgramWeek
    let best2k: Double

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                Text("Woche \(Int(week.week))").font(.headline)
                if week.deload { DSChip(String(localized: "leichter"), tone: .hint) }
                if week.taper { DSChip(String(localized: "Tapering"), tone: .hint) }
                Spacer(minLength: 0)
            }
            if !week.focus.isEmpty {
                Text(week.focus).font(.subheadline).foregroundStyle(Theme.text2)
            }
            VStack(spacing: 0) {
                ForEach(Array(week.sessions.enumerated()), id: \.offset) { i, s in
                    NavigationLink(value: RowingRoute.plan(s.planId)) {
                        ProgramSessionRow(planId: s.planId, intensity: s.intensity, optional: s.optional, event: s.event,
                                          note: s.note, best2k: best2k)
                    }
                    .buttonStyle(.plain)
                    if i + 1 < week.sessions.count { Divider().overlay(Theme.cardStroke) }
                }
            }
        }
        .dsCard(padding: DS.Space.m, cornerRadius: DS.Radius.tile)
    }
}

/// Zeile einer Einheit: Farbe nach Härte, Name, freiwillig/Ziel, Länge, Phasenbalken, Hinweis
struct ProgramSessionRow: View {
    let planId: String
    let intensity: PlanIntensity
    var optional = false
    var event = false
    var note = ""
    let best2k: Double
    var replaced = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Theme.levelColor(intensity.level))
                .frame(width: 6)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                    Text(ProgramFormat.sessionName(planId)).font(.subheadline.weight(.semibold))
                        .italic(optional)
                    if event { DSChip(String(localized: "Zieleinheit"), tone: .warn, systemImage: "flag.checkered") }
                    if optional { DSChip(String(localized: "freiwillig")) }
                    if replaced { DSChip(String(localized: "leichter"), tone: .hint) }
                    Spacer(minLength: DS.Space.s)
                    Text(ProgramFormat.sessionLength(planId, best2k: best2k))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.text2)
                }
                if let plan = PlanLibrary.plan(id: planId) {
                    PhaseBar(plan: plan, best2k: best2k, height: 16)
                }
                if !note.isEmpty {
                    Text(note).font(.caption).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Plan starten

/// „Plan starten“: Wunschtage (Vorschlag je nach Einheiten pro Woche) und Startdatum, Vorschau der ersten Woche
struct ProgramStartSheet: View {
    let program: TrainingProgram
    let onStarted: () -> Void
    @Environment(ProgramStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var weekdays: Set<Weekday>
    @State private var startDate = Calendar.current.startOfDay(for: Date())
    @State private var startError: String?

    init(program: TrainingProgram, onStarted: @escaping () -> Void) {
        self.program = program
        self.onStarted = onStarted
        let n = program.sessionsPerWeek.upperBound
        _weekdays = State(initialValue: Set(TrainingProgramScheduler.suggestedWeekdays(
            count: n, maxConsecutiveDays: program.rules.maxConsecutiveDays)))
    }

    private var problem: ProgramStartProblem? { TrainingProgramScheduler.check(weekdays: weekdays, program: program) }

    /// Erste Woche, wie sie mit dieser Wahl aussähe
    private var preview: [ScheduledProgramSession] {
        guard problem == nil, let st = try? TrainingProgramEngine.start(
            program: program, startDate: startDate, weekdays: Array(weekdays), env: store.environment(), now: Date())
        else { return [] }
        return st.sessions(inRun: 0)
    }

    private var lastStart: Date { Calendar.current.date(byAdding: .day, value: 60, to: Date()) ?? Date() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        Text("Wann ruderst du?").font(.title3.bold())
                        Text(program.sessionsPerWeek.lowerBound == program.sessionsPerWeek.upperBound
                             ? String(localized: "Der Plan hat \(program.sessionsPerWeek.lowerBound) Einheiten pro Woche. Wähle mindestens so viele Tage.")
                             : String(localized: "Der Plan hat \(program.sessionsPerWeek.lowerBound) Pflicht-Einheiten pro Woche und bis zu \(program.sessionsPerWeek.upperBound) mit freiwilligen. Wähle mindestens \(program.sessionsPerWeek.lowerBound) Tage."))
                            .font(.subheadline)
                            .foregroundStyle(Theme.text2)
                        WeekdayPicker(selection: $weekdays)
                        if let problem {
                            Label(problem.message, systemImage: "exclamationmark.triangle")
                                .font(.subheadline)
                                .foregroundStyle(Theme.warn)
                        } else if program.rules.maxConsecutiveDays <= 1 {
                            Text("Zwischen zwei Einheiten liegt immer ein Ruhetag; die App verteilt entsprechend.")
                                .font(.footnote).foregroundStyle(Theme.text2)
                        }
                    }
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        DatePicker(selection: $startDate, in: Calendar.current.startOfDay(for: Date())...lastStart,
                                   displayedComponents: .date) {
                            Text("Start").font(.title3.bold())
                        }
                    }
                    if !preview.isEmpty {
                        VStack(alignment: .leading, spacing: DS.Space.s) {
                            Text("Woche 1").font(.title3.bold())
                            VStack(spacing: 0) {
                                ForEach(preview) { s in
                                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.m) {
                                        Text(s.date.map(ProgramFormat.day) ?? String(localized: "ohne Tag"))
                                            .font(.subheadline.monospacedDigit())
                                            .foregroundStyle(Theme.text2)
                                            .frame(width: 110, alignment: .leading)
                                        Circle().fill(Theme.levelColor(s.intensity.level)).frame(width: 8, height: 8)
                                        Text(ProgramFormat.sessionName(s.planId)).font(.subheadline)
                                        if s.optional { DSChip(String(localized: "freiwillig")) }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.vertical, 8)
                                }
                            }
                            .padding(.horizontal, DS.Space.m)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous))
                        }
                    }
                    if let current = store.program, current.id != program.id {
                        Label(String(localized: "Der laufende Plan „\(current.name)“ wird damit beendet."), systemImage: "info.circle")
                            .font(.subheadline)
                            .foregroundStyle(Theme.text2)
                    }
                    if let startError {
                        Text(startError).font(.subheadline).foregroundStyle(Theme.bad)
                    }
                }
                .padding(DS.Space.l)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom) {
                DSFooterBar {
                    Button {
                        do {
                            try store.start(program, startDate: startDate, weekdays: Array(weekdays))
                            onStarted()
                        } catch let p as ProgramStartProblem {
                            startError = p.message
                        } catch {
                            startError = error.localizedDescription
                        }
                    } label: {
                        Label("Plan starten", systemImage: "play.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle(compact: true))
                    .disabled(problem != nil)
                    .frame(maxWidth: 720)
                }
            }
            .dsSheetChrome(program.name) { dismiss() }
        }
    }
}

/// Sieben Tasten Mo–So
struct WeekdayPicker: View {
    @Binding var selection: Set<Weekday>

    var body: some View {
        HStack(spacing: DS.Space.s) {
            ForEach(Weekday.allCases) { d in
                let on = selection.contains(d)
                Button {
                    if on { selection.remove(d) } else { selection.insert(d) }
                } label: {
                    Text(d.shortLabel)
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Capsule().fill(on ? Theme.accent : Color.white.opacity(0.08)))
                        .foregroundStyle(on ? Theme.onAccent : Theme.text)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(d.label))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .frame(maxWidth: 560)
    }
}

// MARK: - Aktiver Plan

/// Karte des aktiven Plans (oben in der Liste): Name, Woche x von n, Fortschritt, heute
struct ActiveProgramCard: View {
    @Environment(ProgramStore.self) private var store
    @AppStorage(TrainingSettings.best2kKey) private var best2k = PaceTargets.defaultBest2k

    var body: some View {
        if let st = store.active {
            let env = store.environment()
            let prog = TrainingProgramEngine.progress(st, env: env)
            VStack(alignment: .leading, spacing: DS.Space.s) {
                HStack {
                    Text("DEIN PLAN").font(.footnote.weight(.bold)).tracking(2).foregroundStyle(Theme.accent)
                    Spacer()
                    Image(systemName: "chevron.right").font(.body.weight(.semibold)).foregroundStyle(Theme.text2)
                }
                Text(store.program?.name ?? st.programId).font(.title2.bold())
                Text(weekLine(st, prog)).font(.subheadline.monospacedDigit()).foregroundStyle(Theme.text2)
                ProgressView(value: prog.doneShare).tint(Theme.accent)
                Text(todayLine(st)).font(.subheadline)
            }
            .dsCard(padding: DS.Space.m, cornerRadius: DS.Radius.tile)
            .contentShape(Rectangle())
        }
    }

    private func weekLine(_ st: ActiveTrainingProgram, _ p: (week: Int, weeks: Int, doneShare: Double)) -> String {
        if st.isFinished { return String(localized: "Geschafft") }
        if st.isPaused { return String(localized: "Pausiert · Woche \(Int(p.week)) von \(p.weeks)") }
        if st.inBridge, let r = st.currentRun { return String(localized: "Wiedereinstieg · Woche \(Int(r.week)) von 3") }
        return String(localized: "Woche \(Int(p.week)) von \(p.weeks)")
    }

    private func todayLine(_ st: ActiveTrainingProgram) -> String {
        guard !st.isPaused, !st.isFinished, let a = store.agenda() else { return "" }
        if let d = a.day(Date(), calendar: store.calendar) {
            let name = ProgramFormat.sessionName(d.planId)
            return d.done ? String(localized: "Heute erledigt: \(name)") : String(localized: "Heute: \(name)")
        }
        return String(localized: "Heute: Ruhetag laut Plan")
    }
}

/// Wochenansicht des aktiven Plans: Fortschritt, Hinweise, Tage dieser Woche mit Status, nächste Woche,
/// Pausieren/Fortsetzen und Beenden
struct ActiveProgramView: View {
    @Environment(ProgramStore.self) private var store
    @Environment(HomeModel.self) private var home
    @Environment(CourseLibrary.self) private var library
    @Environment(DeviceManager.self) private var devices
    @Environment(\.rowingLaunch) private var launch
    @Environment(\.dismiss) private var dismiss
    @AppStorage(TrainingSettings.best2kKey) private var best2k = PaceTargets.defaultBest2k
    @State private var confirmEnd = false

    private var cal: Calendar { store.calendar }

    var body: some View {
        Group {
            if let st = store.active, let run = st.currentRun {
                content(st, run: run)
            } else {
                DSEmptyState(title: String(localized: "Kein Plan aktiv"), systemImage: "calendar",
                             text: String(localized: "Wähle in der Liste einen Plan und starte ihn."))
            }
        }
        .dsPageBackground()
        .navigationTitle(store.program?.name ?? String(localized: "Plan"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Plan beenden?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("Plan beenden", role: .destructive) {
                store.end()
                dismiss()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Der Fortschritt im Plan wird gelöscht. Deine Fahrten bleiben im Verlauf.")
        }
    }

    private func content(_ st: ActiveTrainingProgram, run: ProgramWeekRun) -> some View {
        let env = store.environment()
        let prog = TrainingProgramEngine.progress(st, env: env)
        let runProgram = ProgramLibrary.program(id: run.programId)
        return ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                header(st, run: run, prog: prog, runProgram: runProgram)
                notices(st)
                if st.isPaused {
                    pausedCard(st)
                } else if !st.isFinished {
                    thisWeek(st, run: run)
                    nextWeek()
                }
                controls(st)
            }
            .padding(DS.Space.l)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func header(_ st: ActiveTrainingProgram, run: ProgramWeekRun,
                        prog: (week: Int, weeks: Int, doneShare: Double), runProgram: TrainingProgram?) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            if st.isFinished {
                Text("Plan geschafft").font(.largeTitle.bold())
            } else if st.inBridge {
                let weeks = runProgram?.weeks ?? 3
                let week = st.bridge?.resumeWeek ?? 1
                Text("Wiedereinstieg · Woche \(Int(run.week)) von \(weeks)").font(.largeTitle.bold())
                Text("Danach geht es in Woche \(week) des Plans weiter.")
                    .font(.subheadline).foregroundStyle(Theme.text2)
            } else {
                Text("Woche \(Int(prog.week)) von \(prog.weeks)").font(.largeTitle.bold())
            }
            if let w = runProgram?.week(run.week), !w.focus.isEmpty, !st.isFinished {
                Text(w.focus).font(.headline).foregroundStyle(Theme.text2)
            }
            HStack(spacing: DS.Space.s) {
                if run.deload || (runProgram?.week(run.week)?.deload ?? false) { DSChip(String(localized: "leichtere Woche"), tone: .hint) }
                if runProgram?.week(run.week)?.taper ?? false { DSChip(String(localized: "Tapering"), tone: .hint) }
                if run.repeated { DSChip(String(localized: "Wiederholung"), systemImage: "arrow.counterclockwise") }
                if st.paceAdjustment > 0 {
                    DSChip(String(localized: "Tempo +\(Int(st.paceAdjustment.rounded())) s/500 m"), systemImage: "gauge.with.dots.needle.33percent")
                }
            }
            ProgressView(value: prog.doneShare) {
                Text("\(Int((prog.doneShare * 100).rounded())) % der Einheiten erledigt")
                    .font(.caption).foregroundStyle(Theme.text2)
            }
            .tint(Theme.accent)
            if let p = store.program {
                ProgramWeekBars(program: p, best2k: best2k, height: 36, current: st.inBridge ? nil : prog.week)
            }
        }
    }

    @ViewBuilder
    private func notices(_ st: ActiveTrainingProgram) -> some View {
        if let ref = st.reference, ref.isWorse {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Label(String(localized: "Der Test ergibt 2000 m in \(Format.duration(ref.best2k)), langsamer als deine Referenz \(Format.duration(ref.previous)). Tagesform und Einteilung streuen stark. Neue Referenz übernehmen?"),
                      systemImage: "questionmark.circle")
                    .font(.subheadline)
                HStack(spacing: DS.Space.m) {
                    Button("Übernehmen") { store.answerReference(accept: true) }
                        .buttonStyle(SecondaryButtonStyle(compact: true, fullWidth: false))
                    Button("Alte behalten") { store.answerReference(accept: false) }
                        .buttonStyle(SecondaryButtonStyle(compact: true, fullWidth: false))
                }
            }
            .dsCard(padding: DS.Space.m, cornerRadius: DS.Radius.tile)
        }
        ForEach(st.notices.filter { $0.kind != .referenceWorse }.suffix(4)) { n in
            DSBanner(systemImage: ProgramFormat.noticeIcon(n.kind), text: ProgramFormat.notice(n),
                     tone: n.kind == .finished || n.kind == .referenceImproved ? .ok : .hint,
                     onClose: { store.dismissNotice(n.id) })
        }
    }

    private func pausedCard(_ st: ActiveTrainingProgram) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Label(st.autoPaused ? String(localized: "Pausiert, weil zehn Tage keine Fahrt dazukam.")
                  : String(localized: "Plan pausiert."), systemImage: "pause.circle")
                .font(.headline)
            if let since = st.pausedAt {
                Text("Seit \(ProgramFormat.day(since)). Beim Fortsetzen wählt die App die passende Woche: bis 7 Tage weiter wie geplant, bis 14 Tage eine Woche zurück, länger mit Wiedereinstieg.")
                    .font(.subheadline).foregroundStyle(Theme.text2)
            }
            Button { store.resume() } label: {
                Label("Fortsetzen", systemImage: "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle(compact: true, fullWidth: false))
        }
        .dsCard(padding: DS.Space.m, cornerRadius: DS.Radius.tile)
    }

    /// Tage der laufenden Planwoche
    private func thisWeek(_ st: ActiveTrainingProgram, run: ProgramWeekRun) -> some View {
        let sessions = st.sessions(inRun: run.run).filter { $0.skipReason != .alreadyDone }
        let first = cal.startOfDay(for: run.start)
        let count = max(1, cal.dateComponents([.day], from: first, to: cal.startOfDay(for: run.end)).day ?? 7)
        let days = (0..<count).compactMap { cal.date(byAdding: .day, value: $0, to: first) }
        let unscheduled = sessions.filter { $0.date == nil && $0.status == .planned }
        return VStack(alignment: .leading, spacing: DS.Space.s) {
            Text("Diese Woche").font(.title3.bold())
            VStack(spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.offset) { i, day in
                    let onDay = sessions.filter { $0.date.map { cal.isDate($0, inSameDayAs: day) } ?? false }
                    ProgramDayRow(day: day, sessions: onDay, isToday: cal.isDateInToday(day), best2k: best2k,
                                  onStart: { start($0) }, onSwap: { store.swapToEasy(sessionId: $0.id) },
                                  onRestore: { store.restoreOriginal(sessionId: $0.id) })
                    if i + 1 < days.count { Divider().overlay(Theme.cardStroke) }
                }
            }
            .padding(.horizontal, DS.Space.m)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous))
            if !unscheduled.isEmpty {
                Text("Freiwillig, wenn ein Tag frei ist").font(.subheadline.weight(.semibold)).padding(.top, DS.Space.s)
                ForEach(unscheduled) { s in
                    HStack {
                        ProgramSessionRow(planId: s.planId, intensity: s.intensity, optional: true, best2k: best2k)
                        Button { start(s) } label: { Image(systemName: "play.fill") }
                            .buttonStyle(SecondaryButtonStyle(compact: true, fullWidth: false))
                            .accessibilityLabel(Text("Starten"))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func nextWeek() -> some View {
        let next = store.preview()
        if !next.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Text("Nächste Woche").font(.title3.bold())
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(next.filter { $0.status == .planned && $0.date != nil }) { s in
                        HStack(spacing: DS.Space.m) {
                            Text(s.date.map(ProgramFormat.day) ?? "")
                                .font(.subheadline.monospacedDigit()).foregroundStyle(Theme.text2)
                                .frame(width: 110, alignment: .leading)
                            Circle().fill(Theme.levelColor(s.intensity.level)).frame(width: 8, height: 8)
                            Text(ProgramFormat.sessionName(s.planId)).font(.subheadline)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .dsCard(padding: DS.Space.m, cornerRadius: DS.Radius.tile)
            }
        }
    }

    private func controls(_ st: ActiveTrainingProgram) -> some View {
        HStack(spacing: DS.Space.m) {
            if !st.isFinished {
                if st.isPaused {
                    Button { store.resume() } label: { Label("Fortsetzen", systemImage: "play.fill") }
                        .buttonStyle(SecondaryButtonStyle(compact: true))
                } else {
                    Button { store.pause() } label: { Label("Plan pausieren", systemImage: "pause.fill") }
                        .buttonStyle(SecondaryButtonStyle(compact: true))
                }
            }
            Button { confirmEnd = true } label: { Label("Plan beenden", systemImage: "stop.fill") }
                .buttonStyle(SecondaryButtonStyle(compact: true, destructive: true))
        }
        .padding(.top, DS.Space.m)
    }

    /// Strecke für den Start: die der letzten Fahrt, sonst die des Vorschlags, sonst die erste
    private var startCourseId: String? {
        let all = RideCourses.all(library: library, simulatorActive: devices.simulatorActive)
        let ids = [home.stats?.lastRide?.session.courseId, home.suggestion?.courseId].compactMap { $0 }
        for id in ids where all.contains(where: { $0.id == id }) { return id }
        return all.first?.id
    }

    /// Einheit starten: Bezug vormerken, damit die Fahrt genau diese Einheit erledigt
    private func start(_ s: ScheduledProgramSession) {
        store.prepareLaunch(sessionId: s.id)
        launch?.callAsFunction(.plan(planId: s.planId, courseId: startCourseId))
    }
}

/// Ein Tag der Wochenansicht: Datum, Einheit(en) bzw. Ruhetag, Status; offene Einheiten mit „Starten“ und Tausch
struct ProgramDayRow: View {
    let day: Date
    let sessions: [ScheduledProgramSession]
    let isToday: Bool
    let best2k: Double
    let onStart: (ScheduledProgramSession) -> Void
    let onSwap: (ScheduledProgramSession) -> Void
    let onRestore: (ScheduledProgramSession) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(day.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.headline)
                    .foregroundStyle(isToday ? Theme.accent : Theme.text)
                Text(day.formatted(.dateTime.day().month(.abbreviated)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.text2)
            }
            .frame(width: 64, alignment: .leading)
            if sessions.isEmpty {
                Text(isToday ? String(localized: "Ruhetag – Erholung gehört dazu") : String(localized: "Ruhetag"))
                    .font(.subheadline)
                    .foregroundStyle(Theme.text3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    ForEach(sessions) { s in sessionView(s) }
                }
            }
        }
        .padding(.vertical, 10)
        .background(isToday ? Theme.accent.opacity(0.06) : Color.clear)
    }

    @ViewBuilder
    private func sessionView(_ s: ScheduledProgramSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                NavigationLink(value: RowingRoute.plan(s.planId)) {
                    ProgramSessionRow(planId: s.planId, intensity: s.intensity, optional: s.optional, event: s.event,
                                      note: s.note, best2k: best2k, replaced: s.isReplaced)
                }
                .buttonStyle(.plain)
                statusChip(s)
            }
            if s.status == .planned {
                HStack(spacing: DS.Space.s) {
                    Button { onStart(s) } label: { Label("Starten", systemImage: "play.fill") }
                        .buttonStyle(SecondaryButtonStyle(compact: true, fullWidth: false))
                    if s.isReplaced {
                        Button { onRestore(s) } label: { Label("Wie geplant", systemImage: "arrow.uturn.backward") }
                            .buttonStyle(SecondaryButtonStyle(compact: true, fullWidth: false))
                    } else if !s.event {
                        Button { onSwap(s) } label: { Label("Leichter", systemImage: "arrow.down.circle") }
                            .buttonStyle(SecondaryButtonStyle(compact: true, fullWidth: false))
                            .accessibilityHint(Text("Gegen eine leichte Variante tauschen"))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func statusChip(_ s: ScheduledProgramSession) -> some View {
        switch s.display(today: day) {
        case .done: DSChip(String(localized: "erledigt"), tone: .ok, systemImage: "checkmark")
        case .missed: DSChip(String(localized: "entfallen"))
        case .moved: DSChip(String(localized: "verschoben"), tone: .hint, systemImage: "arrow.right")
        case .open: DSChip(String(localized: "offen"))
        }
    }
}
