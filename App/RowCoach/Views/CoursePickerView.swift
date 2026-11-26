import SwiftUI
import RowCoachKit

/// Tab „Strecken“: der Seen-Pass mit allen Strecken, gruppiert nach Land (mit Flagge, Städte im Untertitel). Tippen öffnet die Streckenseite
/// (dort „Frei rudern“ mit Tempo-Linie und „Mit Training“).
struct CourseGridView: View {
    @Environment(HomeModel.self) private var model
    @Environment(CourseLibrary.self) private var library
    @Environment(DeviceManager.self) private var devices
    @Environment(CourseDownloads.self) private var downloads
    /// Strecke, für die der Laden-Dialog offen ist
    @State private var pendingDownload: CourseCatalogEntry?
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
        // Fahrbare Strecken und (ausgegraut) die noch nicht geladenen aus dem Katalog
        let all = courses + library.catalogOnly.map(\.placeholderCourse)
        return CourseGrouping.byCountryAndCity(
            filter.apply(all),
            countryName: { locale.localizedString(forRegionCode: $0) ?? $0 },
            cityName: { CourseText.localized($0) },
            otherName: String(localized: "Weitere Strecken"))
    }

    /// „3 Strecken · Basel, Luzern, Zürich“
    private func countrySubtitle(_ g: CourseCountryGroup) -> String {
        let count = g.courseCount == 1 ? String(localized: "1 Strecke") : String(localized: "\(g.courseCount) Strecken")
        let other = String(localized: "Weitere Strecken")
        let cities = g.cities.map(\.city).filter { !$0.isEmpty && $0 != other }
        return cities.isEmpty ? count : count + " · " + cities.joined(separator: ", ")
    }

    @ViewBuilder
    private func tile(_ c: Course) -> some View {
        if let entry = library.catalogOnly.first(where: { $0.id == c.id }) {
            Button { pendingDownload = entry } label: {
                CatalogCourseTile(entry: entry, state: downloads.state(entry.id))
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: RowingRoute.course(c.id)) {
                SeenPassTile(course: c, record: record(c),
                             isSuggested: model.suggestion?.courseId == c.id,
                             isLast: model.stats?.lastRide?.session.courseId == c.id, width: nil)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .buttonStyle(.plain)
        }
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
                        HStack(alignment: .center, spacing: DS.Space.m) {
                            if !country.flag.isEmpty {
                                Text(country.flag).font(.largeTitle).accessibilityHidden(true)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(country.countryName).font(.title2.bold())
                                Text(countrySubtitle(country))
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.text2)
                                    .lineLimit(1)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isHeader)
                        LazyVGrid(columns: columns, alignment: .leading, spacing: DS.Space.m) {
                            ForEach(country.cities.flatMap(\.courses)) { c in tile(c) }
                        }
                    }
                    .padding(DS.Space.m)
                    .background(Theme.card.opacity(0.35), in: RoundedRectangle(cornerRadius: DS.Radius.tile + 6, style: .continuous))
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
        .task { await downloads.refreshCatalog() }
        .confirmationDialog(pendingDownload.map { String(localized: "„\($0.title)“ laden?") } ?? "",
                            isPresented: Binding(get: { pendingDownload != nil }, set: { if !$0 { pendingDownload = nil } }),
                            titleVisibility: .visible, presenting: pendingDownload) { entry in
            Button(String(localized: "Laden (\(DSFormat.bytes(entry.bytes(quality: library.quality.rawValue))))")) {
                downloads.download(entry, quality: library.quality)
            }
            Button("Abbrechen", role: .cancel) {}
        } message: { _ in
            Text("Die Strecke wird einmal geladen und ist danach auch ohne Internet fahrbar.")
        }
    }
}

/// Ausgegraute Kachel einer Strecke aus dem Katalog: Vorschaubild, Name, Länge, Grösse, Laden-Zustand
private struct CatalogCourseTile: View {
    let entry: CourseCatalogEntry
    let state: CourseDownloads.State
    @Environment(CourseLibrary.self) private var library

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Rectangle().fill(Theme.card)
                if let url = library.catalogPreviewURL(for: entry), let img = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: img).resizable().scaledToFill()
                }
            }
            .frame(height: 120)
            .frame(maxWidth: .infinity)
            .clipped()
            .saturation(0)
            .opacity(0.55)
            .overlay {
                Image(systemName: "icloud.and.arrow.down").font(.largeTitle).foregroundStyle(.white.opacity(0.9))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(HomeFormat.courseShort(entry.title)).font(.headline).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(CourseText.localized(entry.region)).font(.footnote).foregroundStyle(Theme.secondaryText).lineLimit(2)
                Spacer().frame(height: 4)
                Text(DSFormat.courseLength(entry.placeholderCourse))
                    .font(.subheadline.monospacedDigit()).foregroundStyle(Theme.text2)
                switch state {
                case .downloading(let f):
                    ProgressView(value: f).tint(Theme.accent)
                    Text("Wird geladen … \(Int(f * 100)) %").font(.footnote.monospacedDigit()).foregroundStyle(Theme.text2)
                case .failed(let msg):
                    Text(msg).font(.footnote).foregroundStyle(Theme.warn).lineLimit(3)
                case .idle:
                    Label(String(localized: "Laden · \(DSFormat.bytes(entry.bytes(quality: library.quality.rawValue)))"),
                          systemImage: "arrow.down.circle")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.link)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(0.85)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.card.opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.cardStroke, style: StrokeStyle(lineWidth: 1, dash: [6, 4])))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Strecke laden, um sie zu fahren"))
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
