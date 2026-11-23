import SwiftUI
import UIKit
import RowCoachKit

/// Tab „Rudern“: Streckenwahl, danach Ruderbildschirm im Vollbild.
struct RowingTab: View {
    @Environment(CourseLibrary.self) private var library
    @Environment(DeviceManager.self) private var devices
    @Environment(SimulatorDevice.self) private var simulator
    @State private var selected: Course?
    @State private var demoStarted = false

    init() {}

    /// Gerade Strecke ohne Landschaft, zum Testen mit dem Simulator oder wenn kein Kartenpaket installiert ist
    private static let testCourse = Course.straight(id: "teststrecke-2x1000", title: "Teststrecke 2 × 1000 m",
                                                    oneWay: 1000)

    private var courses: [Course] {
        var list = library.courses
        if list.isEmpty || devices.simulatorActive { list.append(Self.testCourse) }
        return list
    }

    var body: some View {
        NavigationStack {
            CoursePickerView(courses: courses,
                             previewURL: { library.previewImageURL(for: $0) },
                             onSelect: { selected = $0 })
                .navigationTitle("Rudern")
        }
        .fullScreenCover(item: $selected) { course in
            RowingView(course: course)
        }
        .task {
            // Demo-Start für Simulator-Tests und Bildschirmfotos: Startargument `-demoCourse <id>`
            // startet den Simulator-Ruderer und öffnet die Strecke direkt.
            guard !demoStarted, let id = UserDefaults.standard.string(forKey: "demoCourse") else { return }
            demoStarted = true
            if !simulator.isRunning { simulator.start() }
            try? await Task.sleep(for: .milliseconds(500))
            selected = courses.first { $0.id == id } ?? courses.first
        }
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
