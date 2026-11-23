import SwiftUI
import UIKit
import RowCoachKit

/// Tab „Rudern“: Startbildschirm (Vorschlag für heute, Woche, letzte Fahrt, Seen-Pass) → Ruderbildschirm im Vollbild.
/// Die bisherigen Wege bleiben: „Anders wählen“ bzw. „Alle Wege“ führen zu „Frei rudern“ (Streckenwahl mit
/// Tempo-Linie) und „Training“ (Programmliste mit Filtern → Strecke).
struct RowingTab: View {
    @Environment(CourseLibrary.self) private var library
    @Environment(DeviceManager.self) private var devices
    @Environment(SimulatorDevice.self) private var simulator
    @State private var path: [RowingRoute] = []
    @State private var launch: RowingLaunch?
    @State private var demoStarted = false
    @State private var home = HomeModel()

    init() {}

    /// Strecke und (optional) Programm für den Ruderbildschirm
    private struct RowingLaunch: Identifiable {
        let id = UUID()
        let course: Course
        let plan: WorkoutPlan?
        /// Zieltempo der Tempo-Linie (s/500 m), nur beim freien Rudern
        var paceLine: Double? = nil
    }

    /// Gerade Strecke ohne Landschaft, zum Testen mit dem Simulator oder wenn kein Kartenpaket installiert ist
    private static let testCourse = Course.straight(id: "teststrecke-2x1000", title: "Teststrecke 2 × 1000 m",
                                                    oneWay: 1000)

    private var courses: [Course] {
        var list = library.courses
        if list.isEmpty || devices.simulatorActive { list.append(Self.testCourse) }
        return list
    }

    /// Strecken für Startbildschirm und Seen-Pass: die Kartenpakete; die Teststrecke nur, wenn keins installiert ist
    private var homeCourses: [Course] {
        library.courses.isEmpty ? [Self.testCourse] : library.courses
    }

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(model: home, courses: homeCourses,
                     onStart: { start($0) },
                     onRoute: { path.append($0) })
                .navigationTitle("Rudern")
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: RowingRoute.self) { route in
                    destination(route)
                }
        }
        .environment(\.rowingLaunch, RowingLaunchAction { start($0) })
        .fullScreenCover(item: $launch) { l in
            RowingView(course: l.course, plan: l.plan, paceLine: l.paceLine)
        }
        .task {
            // Demo-Start für Simulator-Tests und Bildschirmfotos: Startargument `-demoCourse <id>`
            // startet den Simulator-Ruderer und öffnet die Strecke direkt; mit `-demoPlan <id>` als Training,
            // mit `-demoPaceLine <s/500 m>` als freie Fahrt mit Tempo-Linie.
            guard !demoStarted, let id = UserDefaults.standard.string(forKey: "demoCourse") else { return }
            demoStarted = true
            if !simulator.isRunning { simulator.start() }
            try? await Task.sleep(for: .milliseconds(500))
            guard let course = courses.first(where: { $0.id == id }) ?? courses.first else { return }
            let plan = UserDefaults.standard.string(forKey: "demoPlan").flatMap { PlanLibrary.plan(id: $0) }
            let demoPace = UserDefaults.standard.double(forKey: "demoPaceLine")
            let paceLine = plan == nil && demoPace > 0 ? PaceLine.clamp(demoPace) : nil
            launch = RowingLaunch(course: course, plan: plan, paceLine: paceLine)
        }
    }

    /// Fahrt starten: Programm auf einer Strecke oder frei (dann mit der eingestellten Tempo-Linie, wie in der
    /// Streckenwahl). Unbekannte Strecke → erste verfügbare; unbekanntes Programm → frei.
    private func start(_ option: DailySuggestion.Option) {
        let courseId: String?
        let plan: WorkoutPlan?
        switch option {
        case .plan(let planId, let cId):
            courseId = cId
            plan = PlanLibrary.plan(id: planId)
        case .free(let cId):
            courseId = cId
            plan = nil
        }
        guard let course = courses.first(where: { $0.id == courseId }) ?? courses.first else { return }
        let paceLine = plan == nil ? PaceLineSettings.current : nil
        if let paceLine { PaceLineSettings.remember(paceLine) }
        launch = RowingLaunch(course: course, plan: plan, paceLine: paceLine)
    }

    @ViewBuilder
    private func destination(_ route: RowingRoute) -> some View {
        switch route {
        case .free:
            coursePicker(plan: nil)
                .navigationTitle("Frei rudern")
        case .plans:
            PlanListView(plans: PlanLibrary.plans)
        case .plan(let id):
            if let plan = PlanLibrary.plan(id: id) {
                PlanDetailView(plan: plan)
            } else {
                ContentUnavailableView("Programm nicht gefunden", systemImage: "questionmark.circle")
            }
        case .courses(let planId):
            let plan = PlanLibrary.plan(id: planId)
            coursePicker(plan: plan)
                .navigationTitle(plan.map { "Strecke für „\($0.name)“" } ?? "Strecke wählen")
                .navigationBarTitleDisplayMode(.inline)
        case .choose:
            CourseChoiceView(model: home, courses: homeCourses)
        case .course(let courseId):
            if let course = courses.first(where: { $0.id == courseId }) {
                CourseDetailView(course: course, model: home)
            } else {
                ContentUnavailableView("Strecke nicht gefunden", systemImage: "map")
            }
        case .coursePlans(let courseId):
            PlanListView(plans: PlanLibrary.plans, courseId: courseId)
        case .planOnCourse(let planId, let courseId):
            if let plan = PlanLibrary.plan(id: planId) {
                PlanDetailView(plan: plan, course: courses.first { $0.id == courseId })
            } else {
                ContentUnavailableView("Programm nicht gefunden", systemImage: "questionmark.circle")
            }
        }
    }

    private func coursePicker(plan: WorkoutPlan?) -> some View {
        CoursePickerView(courses: courses,
                         previewURL: { library.previewImageURL(for: $0) },
                         onSelect: { course in
                             // Tempo-Linie nur beim freien Rudern; das Tempo gilt als zuletzt verwendet
                             let paceLine = plan == nil ? PaceLineSettings.current : nil
                             if let paceLine { PaceLineSettings.remember(paceLine) }
                             launch = RowingLaunch(course: course, plan: plan, paceLine: paceLine)
                         },
                         showsPaceLine: plan == nil)
    }
}

/// Kacheln mit Vorschaubild, Titel und Länge; darüber der Gerätestatus.
struct CoursePickerView: View {
    let courses: [Course]
    let previewURL: (Course) -> URL?
    let onSelect: (Course) -> Void
    /// Schalter „Tempo-Linie“ zeigen (nur freies Rudern)
    let showsPaceLine: Bool

    @Environment(DeviceManager.self) private var devices
    @AppStorage(PaceLineSettings.enabledKey) private var paceLineEnabled = false
    @AppStorage(PaceLineSettings.paceKey) private var storedPace = 0.0
    @AppStorage(TrainingSettings.best2kKey) private var best2k = PaceTargets.defaultBest2k
    private let columns = [GridItem(.adaptive(minimum: 300), spacing: 16)]

    init(courses: [Course], previewURL: @escaping (Course) -> URL?, onSelect: @escaping (Course) -> Void,
         showsPaceLine: Bool = false) {
        self.courses = courses
        self.previewURL = previewURL
        self.onSelect = onSelect
        self.showsPaceLine = showsPaceLine
    }

    /// Zieltempo für die Kacheln (nil = Tempo-Linie aus)
    private var tilePace: Double? {
        guard showsPaceLine, paceLineEnabled else { return nil }
        return PaceLineSettings.effectivePace(stored: storedPace, best2k: best2k)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                deviceStatus
                if showsPaceLine {
                    PaceLineSetupCard()
                }
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(courses) { c in
                        Button { onSelect(c) } label: {
                            CourseTile(course: c, imageURL: previewURL(c), paceLine: tilePace)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
    }

    private var deviceStatus: some View {
        HStack(spacing: 16) {
            if devices.simulatorActive {
                Label("Simulator aktiv", systemImage: "desktopcomputer").foregroundStyle(.purple)
            } else {
                Label("PM5: \(devices.pm5State.rawValue)", systemImage: "figure.rower")
                    .foregroundStyle(devices.pm5State == .connected ? .green : .secondary)
                Label("Puls: \(devices.strapState.rawValue)", systemImage: "heart.fill")
                    .foregroundStyle(devices.strapState == .connected ? .green : .secondary)
            }
            Spacer()
        }
        .font(.subheadline)
    }
}

private struct CourseTile: View {
    let course: Course
    let imageURL: URL?
    /// Zieltempo der Tempo-Linie: zeigt, wann die Linie im Ziel ist
    var paceLine: Double? = nil

    private var lengthText: String {
        if course.turns > 0 {
            return "2 × \(Format.distance(course.oneWayM)) = \(Format.distance(2 * course.oneWayM))"
        }
        return Format.distance(course.oneWayM)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            preview
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .clipped()
            VStack(alignment: .leading, spacing: 4) {
                Text(course.title).font(.headline)
                Text(course.region).font(.subheadline).foregroundStyle(.secondary)
                Label(lengthText, systemImage: "arrow.left.arrow.right")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let paceLine {
                    Label(paceLineText(paceLine), systemImage: "flag.pattern.checkered")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.paceLine)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Strecke wählen und losrudern")
    }

    /// „Tempo-Linie: 4000 m in 18:24“
    private func paceLineText(_ pace: Double) -> String {
        "Tempo-Linie: " + PaceLineSettings.finishText(distance: PaceLineSettings.courseLength(course), pace: pace)
    }

    /// Strecke von oben (wie der Navigator) statt eines 3D-Vorschaubilds
    private var preview: some View {
        CourseMapPreview(course: course)
    }
}
