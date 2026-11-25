import SwiftUI
import RowCoachKit

/// Tab „Strecken“: der Seen-Pass mit allen Strecken, gruppiert nach Land (mit Flagge) und Stadt. Tippen öffnet die Streckenseite
/// (dort „Frei rudern“ mit Tempo-Linie und „Mit Training“).
struct CourseGridView: View {
    @Environment(HomeModel.self) private var model
    @Environment(CourseLibrary.self) private var library
    @Environment(DeviceManager.self) private var devices
    private let columns = [GridItem(.adaptive(minimum: 250), spacing: DS.Space.m, alignment: .top)]

    init() {}

    private var courses: [Course] {
        var list = RideCourses.home(library: library)
        if devices.simulatorActive, !list.contains(where: { $0.id == RideCourses.testCourse.id }) {
            list.append(RideCourses.testCourse)
        }
        return list
    }

    private func record(_ c: Course) -> TrainingStats.CourseRecord? {
        model.stats?.courses[c.id] ?? model.stats?.courses[c.title]
    }

    /// Strecken nach Land (mit Flagge) und Stadt, Namen in der Sprache der App
    private var groups: [CourseCountryGroup] {
        let locale = Locale(identifier: AppLanguage.code)
        return CourseGrouping.byCountryAndCity(
            courses,
            countryName: { locale.localizedString(forRegionCode: $0) ?? $0 },
            cityName: { CourseText.localized($0) },
            otherName: String(localized: "Weitere Strecken"))
    }

    private var openCount: Int {
        courses.filter { (record($0)?.rides ?? 0) == 0 }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Text("Seen-Pass").font(.largeTitle.bold())
                    Text(openCount == 0 ? String(localized: "Alle Strecken gefahren.")
                         : String(localized: "\(courses.count) Strecken, davon \(openCount) noch offen."))
                        .font(.body)
                        .foregroundStyle(Theme.text2)
                }
                ForEach(groups) { country in
                    VStack(alignment: .leading, spacing: DS.Space.m) {
                        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                            if !country.flag.isEmpty {
                                Text(country.flag).font(.title).accessibilityHidden(true)
                            }
                            Text(country.countryName).font(.title2.bold())
                            Text(country.courseCount == 1 ? String(localized: "1 Strecke")
                                 : String(localized: "\(country.courseCount) Strecken"))
                                .font(.subheadline)
                                .foregroundStyle(Theme.text2)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isHeader)
                        ForEach(country.cities) { city in
                            VStack(alignment: .leading, spacing: DS.Space.s) {
                                Text(city.city)
                                    .font(.headline)
                                    .foregroundStyle(Theme.text2)
                                    .accessibilityAddTraits(.isHeader)
                                LazyVGrid(columns: columns, alignment: .leading, spacing: DS.Space.m) {
                                    ForEach(city.courses) { c in
                                        NavigationLink(value: RowingRoute.course(c.id)) {
                                            SeenPassTile(course: c, record: record(c),
                                                         isSuggested: model.suggestion?.courseId == c.id,
                                                         isLast: model.stats?.lastRide?.session.courseId == c.id, width: nil)
                                                .frame(maxHeight: .infinity, alignment: .top)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(DS.Space.l)
            .frame(maxWidth: 1200)
            .frame(maxWidth: .infinity)
        }
        .dsPageBackground()
        .navigationTitle(Text("Strecken"))
        .navigationBarTitleDisplayMode(.inline)
        .appToolbar()
    }
}

/// Streckenwahl für ein Programm (aus dem Programmdetail „Andere Strecke“): Tippen startet das Training.
struct CoursePickerView: View {
    let courses: [Course]
    let plan: WorkoutPlan?

    @Environment(\.rowingLaunch) private var launch
    private let columns = [GridItem(.adaptive(minimum: 280), spacing: DS.Space.m, alignment: .top)]

    init(courses: [Course], plan: WorkoutPlan?) {
        self.courses = courses
        self.plan = plan
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: DS.Space.m) {
                ForEach(courses) { c in
                    Button {
                        if let plan {
                            launch?.callAsFunction(.plan(planId: plan.id, courseId: c.id))
                        } else {
                            launch?.callAsFunction(.free(courseId: c.id))
                        }
                    } label: {
                        CourseTile(course: c)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(DS.Space.l)
        }
        .dsPageBackground()
        .navigationTitle(plan.map { Text("Strecke für „\($0.shortName)“") } ?? Text("Strecke wählen"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Kachel mit Luftbild, Titel, Region und Länge
private struct CourseTile: View {
    let course: Course

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CourseMapPreview(course: course, coverWithImage: true, showsMarkers: false)
                .frame(height: 160)
                .frame(maxWidth: .infinity)
                .clipped()
            VStack(alignment: .leading, spacing: 4) {
                Text(course.title).font(.headline).lineLimit(2)
                Text(course.regionText).font(.subheadline).foregroundStyle(Theme.text2)
                Label(DSFormat.courseLength(course), systemImage: "arrow.left.arrow.right")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.text2)
                Label("Training hier starten", systemImage: "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 4)
            }
            .padding(DS.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous).strokeBorder(Theme.cardStroke))
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Training auf dieser Strecke starten"))
    }
}
