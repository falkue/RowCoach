import SwiftUI
import RowCoachKit

/// Tab „Strecken“: der Seen-Pass mit allen Strecken, gruppiert nach Land (mit Flagge) und Stadt. Tippen öffnet die Streckenseite
/// (dort „Frei rudern“ mit Tempo-Linie und „Mit Training“).
struct CourseGridView: View {
    @Environment(HomeModel.self) private var model
    @Environment(CourseLibrary.self) private var library
    @Environment(DeviceManager.self) private var devices
    private let columns = [GridItem(.adaptive(minimum: 250), spacing: DS.Space.m, alignment: .top)]
    /// Filter nach Land und Streckenform (bleibt beim Wechsel der Tabs erhalten)
    @AppStorage("courseFilterCountry") private var filterCountry = ""
    @AppStorage("courseFilterShape") private var filterShape = ""

    init() {}

    private var filter: CourseFilter {
        CourseFilter(countryCode: filterCountry.isEmpty ? nil : filterCountry, shape: CourseShape(rawValue: filterShape))
    }

    private var countryLocale: Locale { Locale(identifier: AppLanguage.code) }

    private func countryName(_ code: String) -> String { countryLocale.localizedString(forRegionCode: code) ?? code }

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
            filter.apply(courses),
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
                filterBar
                if groups.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        Text("Keine Strecke passt zum Filter.").font(.headline)
                        Button("Filter zurücksetzen") { filterCountry = ""; filterShape = "" }
                            .buttonStyle(SecondaryButtonStyle(compact: true, fullWidth: false))
                    }
                    .dsCard(padding: DS.Space.m, cornerRadius: DS.Radius.tile)
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

extension CourseGridView {
    /// Filterleiste: Land (mit Flagge) und Form (Hin und zurück, Rundkurs, eine Richtung); nur Werte, die vorkommen
    @ViewBuilder
    fileprivate var filterBar: some View {
        let codes = Array(Set(courses.compactMap(\.countryCode))).sorted { countryName($0) < countryName($1) }
        let shapes = CourseShape.allCases.filter { s in courses.contains { $0.shape == s } }
        HStack(spacing: DS.Space.s) {
            Menu {
                Picker(selection: $filterCountry) {
                    Text("Alle Länder").tag("")
                    ForEach(codes, id: \.self) { code in
                        Text(verbatim: "\(Course.flag(code)) \(countryName(code))").tag(code)
                    }
                } label: { EmptyView() }
            } label: {
                filterChip(filterCountry.isEmpty ? String(localized: "Alle Länder")
                           : "\(Course.flag(filterCountry)) \(countryName(filterCountry))",
                           systemImage: "globe.europe.africa", active: !filterCountry.isEmpty)
            }
            if shapes.count > 1 {
                Menu {
                    Picker(selection: $filterShape) {
                        Text("Alle Formen").tag("")
                        ForEach(shapes) { s in Text(Self.shapeTitle(s)).tag(s.rawValue) }
                    } label: { EmptyView() }
                } label: {
                    filterChip(CourseShape(rawValue: filterShape).map(Self.shapeTitle) ?? String(localized: "Alle Formen"),
                               systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                               active: !filterShape.isEmpty)
                }
            }
            if filter.isActive {
                Button { filterCountry = ""; filterShape = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(Theme.text2)
                }
                .accessibilityLabel(Text("Filter zurücksetzen"))
            }
            Spacer(minLength: 0)
        }
    }

    static func shapeTitle(_ s: CourseShape) -> String {
        switch s {
        case .outAndBack: return String(localized: "Hin und zurück")
        case .loop: return String(localized: "Rundkurs")
        case .oneWay: return String(localized: "Eine Richtung")
        }
    }

    private func filterChip(_ title: String, systemImage: String, active: Bool) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, DS.Space.m)
            .frame(minHeight: 44)
            .foregroundStyle(active ? Theme.accent : Theme.text)
            .background(Capsule().fill(active ? Theme.accent.opacity(0.18) : Theme.card))
            .overlay(Capsule().strokeBorder(active ? Theme.accent.opacity(0.6) : Theme.cardStroke))
            .contentShape(Capsule())
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
