import SwiftUI
import SwiftData
import RowCoachKit

/// Streckenseite (Tippen auf eine Strecke unter „Anders wählen“): oben das Luftbild mit Route (Start, Wende), Name,
/// Region, Länge, Kurzbeschreibung, deine Werte; dann zwei klare Wege – „Frei rudern“ (mit Tempo-Linie auf der
/// Seite) und „Mit Training“ (Programmliste für diese Strecke, Programm wählen startet direkt) – und leise der
/// heutige Vorschlag auf dieser Strecke. Darunter „Unterwegs“ (Sehenswertes in Fahrreihenfolge), Fakten, deine
/// letzten Fahrten und die Quellen. Fehlende Angaben in der course.json lassen ihren Abschnitt einfach weg.
struct CourseDetailView: View {
    let course: Course
    let model: HomeModel

    @Environment(\.rowingLaunch) private var launch
    @Environment(\.modelContext) private var context
    @State private var openWorkout: StoredWorkout?

    init(course: Course, model: HomeModel) {
        self.course = course
        self.model = model
    }

    private var record: TrainingStats.CourseRecord? {
        model.stats?.courses[course.id] ?? model.stats?.courses[course.title]
    }

    private var rides: [TrainingSession] {
        _ = model.stats   // neu zeichnen, wenn neu gerechnet wurde
        return model.sessions(courseId: course.id, title: course.title)
    }

    var body: some View {
        GeometryReader { geo in
            if geo.size.width >= 900 {
                // iPad quer: links Luftbild und Text, rechts eine feste Aktionsspalte (nichts unter dem Falz)
                HStack(alignment: .top, spacing: 0) {
                    ScrollView { info(compact: false).padding(DS.Space.l) }
                    actionColumn
                        .frame(width: min(420, geo.size.width * 0.34))
                        .padding(.vertical, DS.Space.l)
                        .padding(.trailing, DS.Space.l)
                }
            } else {
                // iPhone und iPad hoch: Tempo-Linie im Inhalt, die beiden Tasten in einer festen Fussleiste
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.l) {
                        info(compact: geo.size.width < 600)
                        PaceLineSetupCard()
                        GhostRaceButton(course: course, model: model)
                        suggestionLink
                    }
                    .padding(geo.size.width < 600 ? DS.Space.m : DS.Space.l)
                    .frame(maxWidth: 900, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .safeAreaInset(edge: .bottom) {
                    DSFooterBar {
                        HStack(spacing: DS.Space.m) { freeButton; trainingButton }
                            .frame(maxWidth: 900)
                    }
                }
            }
        }
        .dsPageBackground()
        .navigationTitle(HomeFormat.courseShort(course.title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Theme.bg, for: .navigationBar)
        .sheet(item: $openWorkout) { WorkoutSheet(item: $0) }
    }

    private func info(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? DS.Space.l : 28) {
            CourseMapPreview(course: course, coverWithImage: true)
                .frame(height: compact ? 240 : 340)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .accessibilityLabel(Text("Luftbild mit Route, Start grün, Wende orange"))
            header
            highlights
            facts
            yourRides
            if !course.attribution.isEmpty {
                Text("Quellen: \(CourseText.attribution(course.attribution))")
                    .font(.footnote)
                    .foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Abschnitte

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text(course.titleText).font(DSFont.pageTitle).fixedSize(horizontal: false, vertical: true)
            Text("\(course.regionText) · \(DSFormat.courseLength(course))")
                .font(.title3)
                .foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
            if let d = course.description?.appText, !d.isEmpty {
                Text(d).font(.body).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
            }
            Group {
                if let r = record, r.rides > 0 {
                    let best = r.bestTime.map { String(localized: " · Bestzeit \(Format.duration($0))") } ?? ""
                    Text(r.rides == 1 ? String(localized: "1 Fahrt · \(DSFormat.kmShort(r.distance)) gesamt\(best)")
                         : String(localized: "\(r.rides) Fahrten · \(DSFormat.kmShort(r.distance)) gesamt\(best)"))
                } else {
                    Label("Noch nie gefahren – neu für deinen Seen-Pass", systemImage: "scope")
                        .foregroundStyle(Theme.link)
                }
            }
            .font(.headline)
            .padding(.top, 6)
        }
    }

    /// Feste Aktionsspalte (iPad quer): Tempo-Linie, „Frei rudern“, „Mit Training“, heutiger Vorschlag
    private var actionColumn: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            PaceLineSetupCard()
            freeButton
            trainingButton
            GhostRaceButton(course: course, model: model)
            suggestionLink
            Spacer(minLength: 0)
        }
    }

    private var freeButton: some View {
        Button { launch?.callAsFunction(.free(courseId: course.id)) } label: {
            Label("Frei rudern", systemImage: "play.fill").lineLimit(1).minimumScaleFactor(0.7)
        }
        .buttonStyle(PrimaryButtonStyle(compact: true))
        .keyboardShortcut(.defaultAction)
    }

    private var trainingButton: some View {
        NavigationLink(value: RowingRoute.coursePlans(courseId: course.id)) {
            Label("Mit Training", systemImage: "list.bullet.rectangle").lineLimit(1).minimumScaleFactor(0.7)
        }
        .buttonStyle(SecondaryButtonStyle(compact: true))
    }

    @ViewBuilder
    private var suggestionLink: some View {
        if let s = model.suggestion, let plan = PlanLibrary.plan(id: s.planId) {
            Button { launch?.callAsFunction(.plan(planId: plan.id, courseId: course.id)) } label: {
                Label("Heutiger Vorschlag hier: \(plan.shortName)", systemImage: "play.circle")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.link)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var highlights: some View {
        if let list = course.highlights, !list.isEmpty {
            section("Unterwegs") {
                ForEach(Array(list.enumerated()), id: \.offset) { i, h in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: sideIcon(h.side))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.text2)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(h.name.appText).font(.headline)
                            let side = h.side.map { String(localized: "\($0.title) auf der Hinfahrt") }
                            let note = h.note?.appText
                            if let line = [side, note].compactMap({ $0 }).filter({ !$0.isEmpty }).joined(separator: " · ").nilIfEmpty {
                                Text(line).font(.subheadline).foregroundStyle(Theme.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 8)
                    if i + 1 < list.count { Divider().overlay(Color.white.opacity(0.08)) }
                }
            }
        }
    }

    private func sideIcon(_ side: CourseHighlight.Side?) -> String {
        switch side {
        case .left: return "arrow.left"
        case .right: return "arrow.right"
        case .ahead: return "arrow.up"
        case nil: return "mappin"
        }
    }

    private var facts: some View {
        section("Fakten") {
            // Länge einheitlich: hin, zurück, gesamt
            factRow(String(localized: "Länge"), course.turns > 0
                    ? String(localized: "hin \(DSFormat.km(course.oneWayM)) · zurück \(DSFormat.km(course.oneWayM)) · gesamt \(DSFormat.km(PaceLineSettings.courseLength(course)))")
                    : DSFormat.km(course.oneWayM))
            factRow(String(localized: "Gewässer"), course.regionText)
            // Gezählt werden nur die Brücken, unter denen die Strecke hindurchführt (Feld `bridges`);
            // weitere Brücken in Sichtweite stehen nur unter „Unterwegs“.
            if let b = course.bridges, !b.isEmpty {
                factRow(String(localized: "Durchfahrene Brücken"), "\(b.count) (" + b.joined(separator: ", ") + ")")
            }
            if course.lakeLevelM > 0 {
                factRow(String(localized: "Wasserhöhe"), String(localized: "\(Int(course.lakeLevelM.rounded())) m ü. M."))
            }
            let vessels = (course.traffic?.vessels ?? []).compactMap { Self.vesselName($0, course: course) }
            if !vessels.isEmpty {
                factRow(String(localized: "Schiffsverkehr"), vessels.joined(separator: ", "))
            }
        }
    }

    /// Namen der Schiffsarten (Rohwerte von `VesselKind`); unbekannte Arten mit ihrem Rohwert.
    /// `rheinschiff` ist das Modell für Frachtschiffe allgemein: „Rheinschiffe“ nur am Rhein, sonst „Frachtschiffe“.
    private static func vesselName(_ raw: String, course: Course) -> String? {
        let onRhine = course.region.contains("Rhein") || course.title.contains("Rhein") || course.id.contains("rhein")
        let names = ["motorboot": String(localized: "Motorboote"), "segelboot": String(localized: "Segelboote"),
                     "kursschiff": String(localized: "Kursschiffe"), "raddampfer": String(localized: "Raddampfer"),
                     "rheinschiff": onRhine ? String(localized: "Rheinschiffe") : String(localized: "Frachtschiffe"),
                     "weidling": String(localized: "Weidlinge"), "faehre": String(localized: "Fähren"),
                     "alsterdampfer": String(localized: "Alsterdampfer"), "tretboot": String(localized: "Tretboote")]
        let r = raw.trimmingCharacters(in: .whitespaces)
        return r.isEmpty ? nil : (names[r] ?? r.capitalized)
    }

    @ViewBuilder
    private var yourRides: some View {
        let list = rides
        if !list.isEmpty {
            section("Deine Fahrten hier") {
                if let best = record?.bestTime {
                    factRow(String(localized: "Bestzeit"), Format.duration(best))
                }
                ForEach(list.prefix(3)) { s in
                    Button { open(s.id) } label: {
                        HStack {
                            Text(HomeFormat.relativeDate(s.start)).font(.body.weight(.medium))
                            Spacer(minLength: 12)
                            Text("\(Format.duration(s.activeDuration)) · \(Format.duration(s.displayPace)) /500 m")
                                .font(.body.monospacedDigit())
                                .foregroundStyle(Theme.secondaryText)
                            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.secondaryText)
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Bausteine

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title2.weight(.semibold))
            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func factRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label).font(.subheadline).foregroundStyle(Theme.secondaryText).frame(minWidth: 130, alignment: .leading)
            Text(value).font(.body).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
    }

    private func open(_ id: UUID) {
        var d = FetchDescriptor<StoredWorkout>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        openWorkout = (try? context.fetch(d))?.first
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
