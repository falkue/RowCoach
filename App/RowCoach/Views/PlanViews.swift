import SwiftUI
import RowCoachKit

/// Programme aus `plans.json` im App-Bundle (Kopie von docs/trainings-recherche.json)
enum PlanLibrary {
    static let plans: [WorkoutPlan] = WorkoutPlanCatalog.loadBundled()

    static func plan(id: String) -> WorkoutPlan? { plans.first { $0.id == id } }
}

/// Navigation in den Tabs Strecken und Programme
enum RowingRoute: Hashable {
    /// Streckenseite: Route, Sehenswertes, Fakten, deine Fahrten, „Frei rudern“ / „Mit Training“
    case course(String)
    /// Programmliste für eine schon gewählte Strecke: Programm wählen startet direkt
    case coursePlans(courseId: String)
    /// Detailansicht eines Programms auf einer schon gewählten Strecke: „Los“ startet direkt
    case planOnCourse(planId: String, courseId: String)
    /// Detailansicht eines Programms
    case plan(String)
    /// Streckenwahl für ein Programm
    case courses(planId: String)
    /// Online-Rennen: Liste (kommende, eigene) und ein Rennen (Warteraum), docs/MULTIPLAYER.md
    case races
    case race(String)
}

/// Kacheln der Trainingsprogramme mit Filtern (Niveau, Art, Intensität, Zeit/Distanz, Dauer, Suche) und Sortierung. Der Filter gilt nur für diesen
/// Einstieg (kein gemeinsamer globaler Filter); ist einer aktiv, zeigt eine Zeile „6 von 10 · Filter löschen“.
struct PlanListView: View {
    let plans: [WorkoutPlan]
    /// schon gewählte Strecke (von der Streckenseite): Programm wählen startet die Fahrt
    let courseId: String?
    @AppStorage(TrainingSettings.best2kKey) private var best2k = PaceTargets.defaultBest2k
    @State private var filter = PlanFilter()
    @State private var sort = PlanSort.standard
    @Environment(\.rowingLaunch) private var launch
    private let columns = [GridItem(.adaptive(minimum: 320), spacing: DS.Space.m, alignment: .top)]

    init(plans: [WorkoutPlan], courseId: String? = nil) {
        self.plans = plans
        self.courseId = courseId
    }

    enum PlanSort: String, CaseIterable, Identifiable {
        case standard, shortest, longest, name
        var id: String { rawValue }
        var label: String {
            switch self {
            case .standard: return String(localized: "Empfohlene Reihenfolge")
            case .shortest: return String(localized: "Kürzeste zuerst")
            case .longest: return String(localized: "Längste zuerst")
            case .name: return String(localized: "Name A–Z")
            }
        }
    }

    /// Werte in der Reihenfolge ihres ersten Auftretens
    private func distinct(_ key: (WorkoutPlan) -> String) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for p in plans {
            let v = key(p)
            if !v.isEmpty && seen.insert(v).inserted { out.append(v) }
        }
        return out
    }

    private var levels: [String] { distinct(\.level).sorted { rank($0) < rank($1) } }
    private var categories: [String] { distinct(\.category) }

    /// Reihenfolge der Niveaus nach dem deutschen Quellwert (Einsteiger vor Fortgeschritten, in jeder Sprache)
    private func rank(_ level: String) -> Int {
        let l = (plans.first { $0.level == level }?.levelID ?? level).lowercased()
        if l.contains("einsteig") || l.contains("anfäng") { return 0 }
        if l.contains("fortgeschritten") { return 1 }
        if l.contains("profi") || l.contains("leistung") { return 2 }
        return 1
    }

    private var filterActive: Bool { filter.isActive }

    /// Intensitäten, Messarten und Dauerklassen, die in den Programmen vorkommen (Menüs nur bei Auswahl)
    private var intensities: [PlanIntensity] { PlanIntensity.allCases.filter { i in plans.contains { $0.intensity == i } } }
    private var metrics: [PlanMetric] { PlanMetric.allCases.filter { m in plans.contains { $0.metric == m } } }
    private var durations: [PlanDurationClass] {
        PlanDurationClass.allCases.filter { d in plans.contains { $0.durationClass(best2k: best2k) == d } }
    }

    private var shown: [WorkoutPlan] {
        let filtered = filter.apply(plans, best2k: best2k)
        switch sort {
        case .standard: return filtered
        case .shortest: return filtered.sorted { $0.estimatedDuration(best2k: best2k) < $1.estimatedDuration(best2k: best2k) }
        case .longest: return filtered.sorted { $0.estimatedDuration(best2k: best2k) > $1.estimatedDuration(best2k: best2k) }
        case .name: return filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    var body: some View {
        ScrollView {
            if plans.isEmpty {
                DSEmptyState(title: String(localized: "Keine Programme"), systemImage: "list.bullet.rectangle",
                             text: String(localized: "plans.json fehlt im App-Bundle oder ist nicht lesbar."))
                    .padding(.top, 60)
            } else {
                VStack(alignment: .leading, spacing: DS.Space.m) {
                    filters
                    if filterActive { filterLine }
                    if shown.isEmpty {
                        DSEmptyState(title: String(localized: "Kein Programm passt"),
                                     systemImage: "line.3.horizontal.decrease.circle",
                                     text: String(localized: "Filter ändern oder löschen."),
                                     actionTitle: String(localized: "Filter löschen"), action: clearFilters)
                            .padding(.top, 40)
                    } else {
                        LazyVGrid(columns: columns, spacing: DS.Space.m) {
                            ForEach(shown) { plan in tile(plan) }
                        }
                    }
                }
                .padding(.horizontal, DS.Space.l)
                .padding(.vertical, DS.Space.m)
            }
        }
        .dsPageBackground()
        .navigationTitle(courseId == nil ? Text("Programme") : Text("Training auf dieser Strecke"))
        .searchable(text: $filter.text, prompt: Text("Programm suchen"))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker(selection: $sort) {
                        ForEach(PlanSort.allCases) { Text($0.label).tag($0) }
                    } label: {
                        Text("Sortierung")
                    }
                } label: {
                    Label("Sortieren", systemImage: "arrow.up.arrow.down")
                }
            }
        }
    }

    @ViewBuilder
    private func tile(_ plan: WorkoutPlan) -> some View {
        if let courseId, let launch {
            // Strecke steht schon fest: Programm wählen startet die Fahrt
            Button { launch(.plan(planId: plan.id, courseId: courseId)) } label: {
                PlanTile(plan: plan, best2k: best2k, startsRide: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Training auf dieser Strecke starten"))
        } else {
            NavigationLink(value: RowingRoute.plan(plan.id)) {
                PlanTile(plan: plan, best2k: best2k)
            }
            .buttonStyle(.plain)
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Picker(selection: $filter.level) {
                Text("Alle Niveaus").tag("")
                ForEach(levels, id: \.self) { Text($0).tag($0) }
            } label: {
                Text("Niveau")
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 560)
            if !categories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Space.s) {
                        chip(String(localized: "Alle Arten"), selected: filter.category.isEmpty) { filter.category = "" }
                        ForEach(categories, id: \.self) { c in
                            chip(c, selected: filter.category == c) {
                                filter.category = filter.category == c ? "" : c
                            }
                        }
                    }
                }
            }
            HStack(spacing: DS.Space.s) {
                if intensities.count > 1 {
                    menu(filter.intensity?.label ?? String(localized: "Alle Intensitäten"), active: filter.intensity != nil,
                         options: intensities.map { ($0.label, $0) }, selected: $filter.intensity)
                }
                if metrics.count > 1 {
                    menu(filter.metric?.label ?? String(localized: "Zeit und Distanz"), active: filter.metric != nil,
                         options: metrics.map { ($0.label, $0) }, selected: $filter.metric)
                }
                if durations.count > 1 {
                    menu(filter.duration?.label ?? String(localized: "Jede Dauer"), active: filter.duration != nil,
                         options: durations.map { ($0.label, $0) }, selected: $filter.duration)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// Auswahlmenü als Chip; nochmals wählen hebt die Auswahl auf
    private func menu<T: Hashable>(_ title: String, active: Bool, options: [(String, T)],
                                   selected: Binding<T?>) -> some View {
        Menu {
            Button(String(localized: "Alle")) { selected.wrappedValue = nil }
            ForEach(options, id: \.1) { o in
                Button { selected.wrappedValue = selected.wrappedValue == o.1 ? nil : o.1 } label: {
                    if selected.wrappedValue == o.1 { Label(o.0, systemImage: "checkmark") } else { Text(o.0) }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
            }
            .font(.subheadline.weight(active ? .semibold : .regular))
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(Capsule().fill(active ? Color.white.opacity(0.22) : Color.white.opacity(0.07)))
            .overlay(Capsule().strokeBorder(active ? Color.white.opacity(0.6) : Color.clear))
            .foregroundStyle(Theme.text)
        }
    }

    private var filterLine: some View {
        HStack(spacing: DS.Space.m) {
            Image(systemName: "line.3.horizontal.decrease.circle.fill").foregroundStyle(Theme.text2)
            Text("\(shown.count) von \(plans.count) Programmen").font(.subheadline).foregroundStyle(Theme.text2)
            Button("Filter löschen", action: clearFilters)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.link)
                .buttonStyle(.borderless)
            Spacer(minLength: 0)
        }
    }

    private func clearFilters() {
        filter = PlanFilter()
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

private struct PlanTile: View {
    let plan: WorkoutPlan
    let best2k: Double
    var startsRide = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(plan.shortName).font(.headline).lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: DS.Space.s)
                if !plan.level.isEmpty { LevelBadge(level: plan.level) }
            }
            Label(PlanFormat.planLength(plan, best2k: best2k), systemImage: "clock")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Theme.text2)
            Text(plan.summary)
                .font(.subheadline)
                .foregroundStyle(Theme.text2)
                .lineLimit(3, reservesSpace: true)
            PhaseBar(plan: plan, best2k: best2k, height: 28)
            if startsRide {
                Label("Auf dieser Strecke starten", systemImage: "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .dsCard(padding: DS.Space.m, cornerRadius: DS.Radius.tile)
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint(startsRide ? Text("Training starten") : Text("Programm ansehen"))
    }
}

struct LevelBadge: View {
    let level: String

    var body: some View {
        Text(level)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.text2)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(0.10)))
    }
}

/// Balkengrafik der Phasen: Breite nach geschätzter Dauer, Höhe nach Art (Arbeit hoch, Pause niedrig), Farbe nach
/// Härte (leicht, mittel, hart, Pause). `progress` (0…1) hebt im Ruderbildschirm den erledigten Teil hervor.
struct PhaseBar: View {
    let shares: [Double]
    let kinds: [WorkoutPhase.Kind]
    let colors: [Color]
    var height: CGFloat = 24
    var progress: Double? = nil

    init(plan: WorkoutPlan, best2k: Double, height: CGFloat = 24, progress: Double? = nil) {
        let secs = plan.phases.map { max($0.estimatedSeconds(best2k: best2k), 1) }
        let total = secs.reduce(0, +)
        self.shares = secs.map { total > 0 ? $0 / total : 0 }
        self.kinds = plan.phases.map(\.kind)
        self.colors = plan.phases.map { Theme.phaseColor($0) }
        self.height = height
        self.progress = progress
    }

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = shares.count > 40 ? 0.5 : 1.5
            let usable = max(geo.size.width - gap * CGFloat(max(shares.count - 1, 0)), 1)
            ZStack(alignment: .bottomLeading) {
                HStack(alignment: .bottom, spacing: gap) {
                    ForEach(Array(shares.enumerated()), id: \.offset) { i, share in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(colors[i].opacity(progress == nil ? 0.95 : 0.4))
                            .frame(width: max(usable * share, 1), height: geo.size.height * Theme.phaseHeight(kinds[i]))
                    }
                }
                if let progress {
                    // erledigter Teil kräftig: dieselbe Leiste, auf die Breite des Fortschritts beschnitten
                    HStack(alignment: .bottom, spacing: gap) {
                        ForEach(Array(shares.enumerated()), id: \.offset) { i, share in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(colors[i])
                                .frame(width: max(usable * share, 1), height: geo.size.height * Theme.phaseHeight(kinds[i]))
                        }
                    }
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: geo.size.width * min(max(progress, 0), 1))
                    }
                    Rectangle().fill(Color.white)
                        .frame(width: 3, height: geo.size.height + 6)
                        .offset(x: min(max(geo.size.width * progress - 1.5, 0), geo.size.width - 3), y: 3)
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Legende der Phasenleiste (Härte)
struct PhaseLegend: View {
    var body: some View {
        HStack(spacing: DS.Space.m) {
            ForEach(PhaseIntensity.allCases, id: \.self) { i in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(Theme.intensityColor(i)).frame(width: 12, height: 8)
                    Text(i.title)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(Theme.text2)
        .accessibilityElement(children: .combine)
    }
}

/// Detailansicht eines Programms: Zweck, Phasen mit Zielen, Quellen. Hauptaktion „Los auf <Strecke>“ (gewählte,
/// sonst zuletzt gefahrene bzw. vorgeschlagene Strecke), daneben „Andere Strecke“.
struct PlanDetailView: View {
    let plan: WorkoutPlan
    /// schon gewählte Strecke
    let course: Course?
    @AppStorage(TrainingSettings.best2kKey) private var best2k = PaceTargets.defaultBest2k
    @Environment(\.rowingLaunch) private var launch
    @Environment(HomeModel.self) private var home
    @Environment(CourseLibrary.self) private var library
    @Environment(DeviceManager.self) private var devices
    @State private var showHealth = false
    @State private var pendingCourseId: String?

    init(plan: WorkoutPlan, course: Course? = nil) {
        self.plan = plan
        self.course = course
    }

    /// Strecke für „Los“: gewählt, sonst die der letzten Fahrt, sonst die des Vorschlags, sonst die erste
    private var startCourse: Course? {
        if let course { return course }
        let all = RideCourses.all(library: library, simulatorActive: devices.simulatorActive)
        let ids = [home.stats?.lastRide?.session.courseId, home.suggestion?.courseId].compactMap { $0 }
        for id in ids { if let c = all.first(where: { $0.id == id }) { return c } }
        return all.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                header
                phases
                sources
            }
            .padding(DS.Space.l)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .dsPageBackground()
        .safeAreaInset(edge: .bottom) { actions }
        .sheet(isPresented: $showHealth) {
            HealthScreenSheet(screen: ThresholdStore.shared.profile.healthScreen) { answers in
                ThresholdStore.shared.setHealthScreen(answers)
                if let c = pendingCourseId, !(answers?.blocksMaximalTests ?? true) {
                    launch?.callAsFunction(.plan(planId: plan.id, courseId: c))
                }
                pendingCourseId = nil
            }
        }
        .navigationTitle(plan.shortName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var actions: some View {
        DSFooterBar {
            HStack(spacing: DS.Space.m) {
                if let c = startCourse, launch != nil {
                    Button { startTest(courseId: c.id) } label: {
                        Label("Los auf \(HomeFormat.courseShort(c.title))", systemImage: "play.fill")
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .buttonStyle(PrimaryButtonStyle(compact: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled((plan.test != nil || TrainingProgramEngine.isTestPlan(plan.id))
                              && testGate.blockReason != nil && !testGate.needsHealthScreen)
                }
                NavigationLink(value: RowingRoute.courses(planId: plan.id)) {
                    Label("Andere Strecke", systemImage: "map").lineLimit(1).minimumScaleFactor(0.7)
                }
                .buttonStyle(SecondaryButtonStyle(compact: true))
            }
            .frame(maxWidth: 820)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Space.s + 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(plan.shortName).font(DSFont.pageTitle)
                Spacer(minLength: DS.Space.s)
                if !plan.level.isEmpty { LevelBadge(level: plan.level) }
            }
            Label(PlanFormat.planLength(plan, best2k: best2k), systemImage: "clock")
                .font(.headline.monospacedDigit())
                .foregroundStyle(Theme.text2)
            if !plan.summary.isEmpty { Text(plan.summary).font(.body) }
            if !plan.purpose.isEmpty {
                Label(plan.purpose, systemImage: "target").font(.subheadline).foregroundStyle(Theme.text2)
            }
            PhaseBar(plan: plan, best2k: best2k, height: 40)
                .padding(.top, DS.Space.xs)
            PhaseLegend()
            // Schwellentests: Sicherheit, Pulsgurt, „Ziele aus Schwelle …“ (docs/schwelle/SPEC.md 6, 9)
            if plan.test != nil || TrainingProgramEngine.isTestPlan(plan.id) {
                ThresholdTestNotice(plan: plan)
                if let reason = testGate.blockReason {
                    Label(reason, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Theme.warn)
                }
            }
        }
    }

    /// Darf der Test starten? (Gesundheitsfragen, Pulsgurt)
    private var testGate: ThresholdTestGate {
        ThresholdTestGate(plan: plan, profile: ThresholdStore.shared.profile,
                          strapConnected: devices.strapState == .connected || devices.simulatorActive)
    }

    /// Start mit Prüfung: vor dem ersten maximalen Test die Gesundheitsfragen
    private func startTest(courseId: String) {
        let gate = testGate
        if gate.needsHealthScreen {
            pendingCourseId = courseId
            showHealth = true
        } else if gate.blockReason == nil || !(plan.test != nil || TrainingProgramEngine.isTestPlan(plan.id)) {
            launch?.callAsFunction(.plan(planId: plan.id, courseId: courseId))
        }
    }

    private var phases: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text("Phasen").font(.title3.bold())
            Text("Tempo bezogen auf deine 2000-m-Bestzeit von \(Format.duration(best2k)) (\(Format.duration(PaceTargets.basePace500(best2k: best2k))) /500 m; ändern unter Einstellungen → Profil).")
                .font(.footnote)
                .foregroundStyle(Theme.text2)
            ThresholdTargetLine()
            if TrainingSettings.paceTargetsAreGuides(plan) {
                Label("Tempo-Ziele sind Richtwerte", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(Theme.text2)
            }
            VStack(spacing: 0) {
                ForEach(Array(plan.phases.enumerated()), id: \.offset) { i, p in
                    PhaseRow(number: i + 1, phase: p, best2k: best2k, workNumber: plan.workNumber(at: i),
                             workCount: plan.workCount)
                    if i + 1 < plan.phases.count { Divider().overlay(Theme.cardStroke) }
                }
            }
            .padding(.horizontal, DS.Space.m)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous))
        }
    }

    @ViewBuilder
    private var sources: some View {
        if !plan.sources.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Text("Quellen").font(.title3.bold())
                ForEach(Array(plan.sources.enumerated()), id: \.offset) { _, s in
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

struct PhaseRow: View {
    let number: Int
    let phase: WorkoutPhase
    let best2k: Double
    var workNumber: Int? = nil
    var workCount: Int = 0

    private var kindTitle: String {
        if let workNumber, workCount > 1 { return String(localized: "Intervall \(workNumber) von \(workCount)") }
        return phase.kind.title
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Theme.phaseColor(phase))
                .frame(width: 6)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(kindTitle).dsLabelStyle()
                    Text(phase.intensity().title).font(.caption).foregroundStyle(Theme.phaseColor(phase))
                    Spacer()
                    Text(PlanFormat.length(phase)).font(.headline.monospacedDigit())
                }
                Text(PhaseText.title(phase)).font(.subheadline)
                targets
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private var targets: some View {
        HStack(spacing: 14) {
            if let r = phase.paceRange(best2k: best2k) {
                Label("Tempo \(PlanFormat.paceRange(r)) /500 m", systemImage: "gauge.with.needle")
            }
            if let r = phase.spmRange {
                Label("Schlagzahl \(PlanFormat.strokeRate(r))", systemImage: "metronome")
            }
            if let z = phase.hrZone {
                Label("Zone \(z)", systemImage: "heart.fill").foregroundStyle(Theme.zoneColor(z))
            }
            if phase.kind == .rest {
                phase.activeRest == false ? Text("Stillstand") : Text("locker weiterrudern")
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(Theme.text2)
    }
}
