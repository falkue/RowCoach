import SwiftUI
import UIKit
import RowCoachKit

/// Tab „Rudern“: Wahl „Frei rudern“ oder „Training“ → (Programm →) Strecke → Ruderbildschirm im Vollbild.
struct RowingTab: View {
    @Environment(CourseLibrary.self) private var library
    @Environment(DeviceManager.self) private var devices
    @Environment(SimulatorDevice.self) private var simulator
    @Environment(WorkoutRecovery.self) private var recovery
    @State private var path: [RowingRoute] = []
    @State private var launch: RowingLaunch?
    @State private var demoStarted = false

    init() {}

    /// Strecke und (optional) Programm für den Ruderbildschirm
    private struct RowingLaunch: Identifiable {
        let id = UUID()
        let course: Course
        let plan: WorkoutPlan?
    }

    /// Gerade Strecke ohne Landschaft, zum Testen mit dem Simulator oder wenn kein Kartenpaket installiert ist
    private static let testCourse = Course.straight(id: "teststrecke-2x1000", title: "Teststrecke 2 × 1000 m",
                                                    oneWay: 1000)

    private var courses: [Course] {
        var list = library.courses
        if list.isEmpty || devices.simulatorActive { list.append(Self.testCourse) }
        return list
    }

    var body: some View {
        NavigationStack(path: $path) {
            RowingModeView()
                .navigationTitle("Rudern")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Image("Logo")
                            .resizable()
                            .frame(width: 34, height: 34)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .accessibilityLabel("RowCoach")
                    }
                }
                .navigationDestination(for: RowingRoute.self) { route in
                    destination(route)
                }
                .safeAreaInset(edge: .top) {
                    // Hinweis nach einer unterbrochenen Fahrt (Akku leer, App beendet oder abgestürzt)
                    if let notice = recovery.notice {
                        RecoveryNoticeRow(text: notice) { recovery.notice = nil }
                            .padding(12)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal)
                    }
                }
        }
        .fullScreenCover(item: $launch) { l in
            RowingView(course: l.course, plan: l.plan)
        }
        .task {
            // Demo-Start für Simulator-Tests und Bildschirmfotos: Startargument `-demoCourse <id>`
            // startet den Simulator-Ruderer und öffnet die Strecke direkt; mit `-demoPlan <id>` als Training.
            guard !demoStarted, let id = UserDefaults.standard.string(forKey: "demoCourse") else { return }
            demoStarted = true
            if !simulator.isRunning { simulator.start() }
            try? await Task.sleep(for: .milliseconds(500))
            guard let course = courses.first(where: { $0.id == id }) ?? courses.first else { return }
            let plan = UserDefaults.standard.string(forKey: "demoPlan").flatMap { PlanLibrary.plan(id: $0) }
            launch = RowingLaunch(course: course, plan: plan)
        }
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
        }
    }

    private func coursePicker(plan: WorkoutPlan?) -> some View {
        CoursePickerView(courses: courses,
                         previewURL: { library.previewImageURL(for: $0) },
                         onSelect: { launch = RowingLaunch(course: $0, plan: plan) })
    }
}

/// Kacheln mit Vorschaubild, Titel und Länge; darüber der Gerätestatus.
struct CoursePickerView: View {
    let courses: [Course]
    let previewURL: (Course) -> URL?
    let onSelect: (Course) -> Void

    @Environment(DeviceManager.self) private var devices
    private let columns = [GridItem(.adaptive(minimum: 300), spacing: 16)]

    init(courses: [Course], previewURL: @escaping (Course) -> URL?, onSelect: @escaping (Course) -> Void) {
        self.courses = courses
        self.previewURL = previewURL
        self.onSelect = onSelect
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                deviceStatus
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(courses) { c in
                        Button { onSelect(c) } label: {
                            CourseTile(course: c, imageURL: previewURL(c))
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

    @ViewBuilder
    private var preview: some View {
        if let url = imageURL, let image = UIImage(contentsOfFile: url.path(percentEncoded: false)) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            ZStack {
                LinearGradient(colors: [Color(red: 0.12, green: 0.22, blue: 0.34), Color(red: 0.05, green: 0.10, blue: 0.14)],
                               startPoint: .top, endPoint: .bottom)
                Image(systemName: "water.waves").font(.system(size: 44)).foregroundStyle(.white.opacity(0.5))
            }
        }
    }
}
