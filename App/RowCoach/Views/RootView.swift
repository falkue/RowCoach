import SwiftUI
import SwiftData
import RowCoachKit

/// Tabs der App (UX-Überarbeitung): Heute · Strecken · Programme · Pläne · Verlauf. Geräte und Einstellungen sind
/// Sheets. „Programme“ sind einzelne Einheiten (plans.json), „Pläne“ Trainingspläne über mehrere Wochen
/// (training_plans.json).
enum AppTab: Hashable {
    case today, courses, plans, programs, history
}

/// Navigation über die Tabs hinweg: gewählter Tab, Sheets (Geräte, Einstellungen, erster Start) und die Pfade
/// der Tabs Strecken und Programme (je Tab eigener Stapel, eigener Filterzustand).
@MainActor
@Observable
final class AppRouter {
    var tab: AppTab = .today
    var showDevices = false
    var showSettings = false
    var showOnboarding = false
    var coursesPath: [RowingRoute] = []
    var plansPath: [RowingRoute] = []
    /// Tab „Pläne“: `ProgramRoute` (Plan, aktiver Plan) und `RowingRoute` (Programm einer Einheit, Streckenwahl)
    var programsPath = NavigationPath()

    init() {}

    /// Tab „Pläne“ an seinem Anfang (dort steht der aktive Plan oben)
    func openPrograms() {
        programsPath = NavigationPath()
        tab = .programs
    }

    /// „Anders wählen“ auf dem Startbildschirm: Tab Strecken an seinem Anfang
    func chooseCourse() {
        coursesPath = []
        tab = .courses
    }

    /// Verlauf mit Wochenansicht (aus dem Wochen-Sheet des Startbildschirms)
    func openHistory() {
        tab = .history
    }
}

/// Strecken, auf denen gerudert werden kann
enum RideCourses {
    /// Gerade Strecke ohne Landschaft, zum Testen mit dem Simulator oder wenn kein Kartenpaket installiert ist
    static let testCourse = Course.straight(id: "teststrecke-2x1000", title: String(localized: "Teststrecke 2 × 1000 m"),
                                              oneWay: 1000)

    /// Alle fahrbaren Strecken: Kartenpakete, dazu die Teststrecke ohne Pakete oder mit Simulator
    static func all(library: CourseLibrary, simulatorActive: Bool) -> [Course] {
        var list = library.courses
        if list.isEmpty || simulatorActive { list.append(testCourse) }
        return list
    }

    /// Strecken für Startbildschirm und Seen-Pass: die Kartenpakete; die Teststrecke nur, wenn keins installiert ist
    static func home(library: CourseLibrary) -> [Course] {
        library.courses.isEmpty ? [testCourse] : library.courses
    }
}

/// Strecke und (optional) Programm für den Ruderbildschirm
struct RideLaunch: Identifiable {
    let id = UUID()
    let course: Course
    let plan: WorkoutPlan?
    /// Zieltempo der Tempo-Linie (s/500 m), nur beim freien Rudern
    var paceLine: Double? = nil
    /// Einheit eines Trainingsplans (die Fahrt zählt dann als erledigt) und Tempo-Anpassung des Plans (s/500 m)
    var programRef: ProgramSessionRef? = nil
    var paceAdjust: Double = 0
    /// Geisterboot aus dieser Fahrt („Gegen meine Bestfahrt“)
    var ghost: WorkoutRecord? = nil
}

/// Wurzel der App: Tabs (auf dem iPad als Seitenleiste umschaltbar), dunkles Thema, Akzentfarbe, Start einer Fahrt
/// im Vollbild, Sheets für Geräte, Einstellungen und den ersten Start. Rechnet die Kennzahlen des Startbildschirms
/// (HomeModel) für alle Tabs.
struct RootView: View {
    @Environment(CourseLibrary.self) private var library
    @Environment(DeviceManager.self) private var devices
    @Environment(SimulatorDevice.self) private var simulator
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \StoredWorkout.startDate, order: .reverse) private var workouts: [StoredWorkout]
    @AppStorage(TrainingSettings.best2kKey) private var best2k = PaceTargets.defaultBest2k
    @AppStorage(HomeSettings.weeklyGoalKey) private var weeklyGoal = HomeSettings.defaultWeeklyGoal
    @AppStorage(OnboardingSettings.doneKey) private var onboardingDone = false
    // Motivation (Wochenziel, Pause, Wann ruderst du?, Meilensteine): Änderung rechnet den Startbildschirm neu
    @AppStorage(MotivationSettings.goalKindKey) private var goalKind = WeeklyGoal.Kind.rides.rawValue
    @AppStorage(MotivationSettings.goalMinutesKey) private var goalMinutes = MotivationSettings.defaultGoalMinutes
    @AppStorage(MotivationSettings.pausesKey) private var pausesData: Data?
    @AppStorage(MotivationSettings.intentionKey) private var intentionData: Data?
    @AppStorage(MotivationSettings.milestonesKey) private var milestonesOn = true
    @State private var router = AppRouter()
    @State private var home = HomeModel()
    @State private var programs = ProgramStore()
    @State private var launch: RideLaunch?
    @State private var demoStarted = false
    /// Schwellentest wartet auf die Gesundheitsfragen (docs/schwelle/SPEC.md 9)
    @State private var healthPending: DailySuggestion.Option?
    @State private var showHealth = false
    /// zählt hoch, wenn die App wieder aktiv wird (neuer Tag) oder das Profil bestätigt wurde
    @State private var tick = 0

    init() {}

    private struct RefreshID: Equatable {
        let keys: [HomeWorkoutKey]
        let courseIds: [String]
        let best2k: Double
        let weeklyGoal: Int
        let tick: Int
        var motivation: [String] = []
    }

    private var motivationKey: [String] {
        [goalKind, String(goalMinutes), pausesData?.base64EncodedString() ?? "", intentionData?.base64EncodedString() ?? "",
         String(milestonesOn)]
    }

    private var keys: [HomeWorkoutKey] {
        workouts.map { HomeWorkoutKey(id: $0.id, effort: $0.effortScore ?? $0.effortEstimate) }
    }

    private var courses: [Course] { RideCourses.all(library: library, simulatorActive: devices.simulatorActive) }
    private var homeCourses: [Course] { RideCourses.home(library: library) }

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Heute", systemImage: "sun.horizon", value: AppTab.today) {
                TodayTab(courses: homeCourses)
            }
            Tab("Strecken", systemImage: "map", value: AppTab.courses) {
                CoursesTab()
            }
            Tab("Programme", systemImage: "list.bullet.rectangle", value: AppTab.plans) {
                PlansTab()
            }
            Tab("Pläne", systemImage: "calendar", value: AppTab.programs) {
                ProgramsTab()
            }
            Tab("Verlauf", systemImage: "clock.arrow.circlepath", value: AppTab.history) {
                HistoryView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $router.showDevices) {
            DevicesSheet()
                .presentationDetents([.large])
        }
        .sheet(isPresented: $router.showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $router.showOnboarding) {
            OnboardingSheet { tick += 1 }
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showHealth) {
            HealthScreenSheet(screen: ThresholdStore.shared.profile.healthScreen) { answers in
                ThresholdStore.shared.setHealthScreen(answers)
                let option = healthPending
                healthPending = nil
                if let option, !(answers?.blocksMaximalTests ?? true) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { start(option) }
                }
            }
        }
        .fullScreenCover(item: $launch) { l in
            RowingView(course: l.course, plan: l.plan, paceLine: l.paceLine, programRef: l.programRef,
                       paceAdjust: l.paceAdjust, ghost: l.ghost)
        }
        .task(id: RefreshID(keys: keys, courseIds: homeCourses.map(\.id), best2k: best2k, weeklyGoal: weeklyGoal,
                            tick: tick, motivation: motivationKey)) {
            home.programs = programs
            home.places = MotivationPlaces.make(homeCourses)
            await home.refresh(container: context.container, keys: keys, courseIds: homeCourses.map(\.id),
                               best2k: best2k, weeklyGoal: weeklyGoal)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { tick += 1 }
        }
        .task { await startup() }
        // zuletzt, damit auch Sheets und der Ruderbildschirm sie sehen
        .environment(router)
        .environment(home)
        .environment(programs)
        .environment(\.rowingLaunch, RowingLaunchAction(start: { start($0) },
                                                         startGhost: { startGhost(courseId: $0, record: $1) }))
    }

    /// Erster Start (Einstieg) bzw. Demo-Start für Simulator-Tests und Bildschirmfotos
    private func startup() async {
        // Änderungen am Trainingsplan (Start, Pause, Tausch) rechnen den Vorschlag für heute neu
        home.programs = programs
        programs.onChange = { [home] in home.recompute() }
        let d = UserDefaults.standard
        let demoCourse = d.string(forKey: "demoCourse")
        let testRun = demoCourse != nil || d.bool(forKey: "seedDemoHistory")
        if !onboardingDone {
            if !testRun && ProfileState.isDefault && workouts.isEmpty {
                router.showOnboarding = true
            } else {
                onboardingDone = true
            }
        }
        // `-demoCourse <id>` startet den Simulator-Ruderer und öffnet die Strecke direkt; mit `-demoPlan <id>` als
        // Training, mit `-demoPaceLine <s/500 m>` als freie Fahrt mit Tempo-Linie.
        guard !demoStarted, let id = demoCourse else { return }
        demoStarted = true
        if !simulator.isRunning { simulator.start() }
        try? await Task.sleep(for: .milliseconds(500))
        let list = RideCourses.all(library: library, simulatorActive: true)
        guard let course = list.first(where: { $0.id == id }) ?? list.first else { return }
        let plan = d.string(forKey: "demoPlan").flatMap { PlanLibrary.plan(id: $0) }
        let demoPace = d.double(forKey: "demoPaceLine")
        let paceLine = plan == nil && demoPace > 0 ? PaceLine.clamp(demoPace) : nil
        launch = RideLaunch(course: course, plan: plan, paceLine: paceLine)
    }

    /// Rennen gegen eine gespeicherte Fahrt: frei rudern auf der Strecke, ohne Tempo-Linie, mit Geisterboot
    private func startGhost(courseId: String, record: WorkoutRecord) {
        guard let course = courses.first(where: { $0.id == courseId }) else { return }
        launch = RideLaunch(course: course, plan: nil, paceLine: nil, ghost: record)
    }

    /// Fahrt starten: Programm auf einer Strecke oder frei (dann mit der eingestellten Tempo-Linie).
    /// Unbekannte Strecke → erste verfügbare; unbekanntes Programm → frei.
    private func start(_ option: DailySuggestion.Option) {
        let courseId: String?
        let plan: WorkoutPlan?
        var programRef: ProgramSessionRef?
        switch option {
        case .plan(let planId, let cId):
            courseId = cId
            plan = PlanLibrary.plan(id: planId)
            // Einheit des Trainingsplans (vorgemerkt in der Wochenansicht oder heute fällig): zählt dann als erledigt
            programRef = plan == nil ? nil : programs.launchRef(for: planId)
        case .free(let cId):
            courseId = cId
            plan = nil
        }
        guard let course = courses.first(where: { $0.id == courseId }) ?? courses.first else { return }
        // maximale Schwellentests erst nach den Gesundheitsfragen bzw. nicht bei einem Ja ohne ärztliche Freigabe
        if let plan, ThresholdRetest.isMaximalTest(plan) {
            let screen = ThresholdStore.shared.profile.healthScreen
            if screen == nil || screen?.blocksMaximalTests == true {
                healthPending = option
                showHealth = true
                return
            }
        }
        let paceLine = plan == nil ? PaceLineSettings.current : nil
        if let paceLine { PaceLineSettings.remember(paceLine) }
        launch = RideLaunch(course: course, plan: plan, paceLine: paceLine, programRef: programRef,
                            paceAdjust: programRef == nil ? 0 : programs.paceAdjustment)
    }
}

// MARK: - Tabs

/// Tab „Heute“: Startbildschirm (Variante C)
struct TodayTab: View {
    let courses: [Course]
    @Environment(HomeModel.self) private var home
    @Environment(AppRouter.self) private var router
    @Environment(\.rowingLaunch) private var launch

    var body: some View {
        NavigationStack {
            HomeView(model: home, courses: courses,
                     onStart: { launch?.callAsFunction($0) },
                     onChoose: { router.chooseCourse() })
                .toolbar(.hidden, for: .navigationBar)
        }
    }
}

/// Tab „Strecken“: Seen-Pass (alle Strecken) → Streckenseite → frei rudern oder mit Training
struct CoursesTab: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.coursesPath) {
            CourseGridView()
                .navigationDestination(for: RowingRoute.self) { RouteDestination(route: $0) }
        }
    }
}

/// Tab „Programme“: Liste mit Filtern → Programmdetail mit „Los auf <Strecke>“ bzw. Streckenwahl
struct PlansTab: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.plansPath) {
            PlanListView(plans: PlanLibrary.plans)
                .appToolbar()
                .navigationDestination(for: RowingRoute.self) { RouteDestination(route: $0) }
        }
    }
}

/// Tab „Pläne“: Trainingspläne über mehrere Wochen; oben der aktive Plan, darunter die Liste mit Filtern →
/// Plandetail mit „Plan starten“; Einheiten öffnen das Programm (wie im Tab Programme)
struct ProgramsTab: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.programsPath) {
            ProgramListView()
                .appToolbar()
                .navigationDestination(for: ProgramRoute.self) { ProgramDestination(route: $0) }
                .navigationDestination(for: RowingRoute.self) { RouteDestination(route: $0) }
        }
    }
}

/// Ziele der Navigation in den Tabs Strecken und Programme
struct RouteDestination: View {
    let route: RowingRoute
    @Environment(CourseLibrary.self) private var library
    @Environment(DeviceManager.self) private var devices
    @Environment(HomeModel.self) private var home

    private var courses: [Course] { RideCourses.all(library: library, simulatorActive: devices.simulatorActive) }

    var body: some View {
        switch route {
        case .course(let courseId):
            if let course = courses.first(where: { $0.id == courseId }) {
                CourseDetailView(course: course, model: home)
            } else {
                DSEmptyState(title: String(localized: "Strecke nicht gefunden"), systemImage: "map")
            }
        case .coursePlans(let courseId):
            PlanListView(plans: PlanLibrary.plans, courseId: courseId)
        case .planOnCourse(let planId, let courseId):
            if let plan = PlanLibrary.plan(id: planId) {
                PlanDetailView(plan: plan, course: courses.first { $0.id == courseId })
            } else {
                DSEmptyState(title: String(localized: "Programm nicht gefunden"), systemImage: "questionmark.circle")
            }
        case .plan(let id):
            if let plan = PlanLibrary.plan(id: id) {
                PlanDetailView(plan: plan)
            } else {
                DSEmptyState(title: String(localized: "Programm nicht gefunden"), systemImage: "questionmark.circle")
            }
        case .courses(let planId):
            let plan = PlanLibrary.plan(id: planId)
            CoursePickerView(courses: courses, plan: plan)
        }
    }
}

// MARK: - Toolbar: Geräte und Einstellungen

/// Rechts in der Toolbar jedes Tabs: Gerätestatus (öffnet Geräte) und Zahnrad (öffnet Einstellungen)
struct AppToolbar: ViewModifier {
    @Environment(AppRouter.self) private var router

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                DeviceStatusButton(compact: true)
            }
            ToolbarItem(placement: .topBarTrailing) {
                SettingsButton()
            }
        }
    }
}

extension View {
    func appToolbar() -> some View { modifier(AppToolbar()) }
}

/// Zahnrad: öffnet die Einstellungen
struct SettingsButton: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        Button { router.showSettings = true } label: {
            Label("Einstellungen", systemImage: "gearshape")
        }
        .labelStyle(.iconOnly)
    }
}

/// Statusanzeige PM5 und Puls; antippen öffnet das Geräte-Sheet
struct DeviceStatusButton: View {
    var compact = false
    @Environment(AppRouter.self) private var router

    var body: some View {
        Button { router.showDevices = true } label: {
            DeviceStatusChips(compact: compact)
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Geräte verbinden"))
    }
}
