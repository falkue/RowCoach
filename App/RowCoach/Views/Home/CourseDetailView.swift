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

    private var lengthText: String {
        course.turns > 0
            ? "\(HomeFormat.km(course.oneWayM)) hin und zurück, \(HomeFormat.km(PaceLineSettings.courseLength(course)))"
            : HomeFormat.km(course.oneWayM)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                CourseMapPreview(course: course, coverWithImage: true)
                    .frame(height: 340)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .accessibilityLabel("Luftbild mit Route, Start grün, Wende orange")
                header
                actions
                highlights
                facts
                yourRides
                if !course.attribution.isEmpty {
                    Text("Quellen: \(course.attribution)")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.homeBackground.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .navigationTitle(HomeFormat.courseShort(course.title))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $openWorkout) { WorkoutSheet(item: $0) }
    }

    // MARK: Abschnitte

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(course.title).font(.system(size: 34, weight: .bold)).fixedSize(horizontal: false, vertical: true)
            Text("\(course.region) · \(lengthText)")
                .font(.system(size: 18))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let d = course.description?.text, !d.isEmpty {
                Text(d).font(.system(size: 18)).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
            }
            Group {
                if let r = record, r.rides > 0 {
                    let best = r.bestTime.map { " · Bestzeit \(Format.duration($0))" } ?? ""
                    Text("\(r.rides) \(r.rides == 1 ? "Fahrt" : "Fahrten") · \(HomeFormat.kmShort(r.distance))\(best)")
                } else {
                    Label("Noch nie gefahren – neu für deinen Seen-Pass", systemImage: "scope")
                        .foregroundStyle(Theme.open)
                }
            }
            .font(.system(size: 18, weight: .semibold))
            .padding(.top, 6)
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Tempo-Linie wie in „Frei rudern“; gilt für die nächste freie Fahrt
            PaceLineSetupCard()
            HStack(spacing: 14) {
                Button { launch?.callAsFunction(.free(courseId: course.id)) } label: {
                    HStack(spacing: 12) { Image(systemName: "play.fill"); Text("Frei rudern") }
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.85))
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(Theme.evening, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                NavigationLink(value: RowingRoute.coursePlans(courseId: course.id)) {
                    HStack(spacing: 10) { Image(systemName: "chart.bar.xaxis"); Text("Mit Training") }
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(Color.white.opacity(0.10), in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.25)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            if let s = model.suggestion, let plan = PlanLibrary.plan(id: s.planId) {
                Button { launch?.callAsFunction(.plan(planId: plan.id, courseId: course.id)) } label: {
                    HStack(spacing: 8) {
                        Text("Heutiger Vorschlag hier: \(plan.shortName)")
                            .fixedSize(horizontal: false, vertical: true)
                        Image(systemName: "play.circle")
                    }
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var highlights: some View {
        if let list = course.highlights, !list.isEmpty {
            section("Unterwegs") {
                ForEach(Array(list.enumerated()), id: \.offset) { i, h in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: sideIcon(h.side))
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(h.name.text).font(.system(size: 18, weight: .semibold))
                            let side = h.side.map { "\($0.title) auf der Hinfahrt" }
                            let note = h.note?.text
                            if let line = [side, note].compactMap({ $0 }).filter({ !$0.isEmpty }).joined(separator: " · ").nilIfEmpty {
                                Text(line).font(.system(size: 16)).foregroundStyle(Theme.secondaryText)
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
            factRow("Länge", course.turns > 0
                    ? "hin \(HomeFormat.km(course.oneWayM)), zurück \(HomeFormat.km(course.oneWayM)), gesamt \(HomeFormat.km(PaceLineSettings.courseLength(course)))"
                    : HomeFormat.km(course.oneWayM))
            factRow("Gewässer", course.region)
            if let b = course.bridges, !b.isEmpty {
                factRow(b.count == 1 ? "Brücke" : "\(b.count) Brücken", b.joined(separator: ", "))
            }
            if course.lakeLevelM > 0 {
                factRow("Wasserhöhe", "\(Int(course.lakeLevelM.rounded())) m ü. M.")
            }
            let vessels = (course.traffic?.vessels ?? []).compactMap(Self.vesselName)
            if !vessels.isEmpty {
                factRow("Schiffsverkehr", vessels.joined(separator: ", "))
            }
        }
    }

    /// Deutsche Namen der Schiffsarten (Rohwerte von `VesselKind`); unbekannte Arten mit ihrem Rohwert
    private static func vesselName(_ raw: String) -> String? {
        let names = ["motorboot": "Motorboote", "segelboot": "Segelboote", "kursschiff": "Kursschiffe",
                     "raddampfer": "Raddampfer", "rheinschiff": "Rheinschiffe", "weidling": "Weidlinge",
                     "faehre": "Fähren"]
        let r = raw.trimmingCharacters(in: .whitespaces)
        return r.isEmpty ? nil : (names[r] ?? r.capitalized)
    }

    @ViewBuilder
    private var yourRides: some View {
        let list = rides
        if !list.isEmpty {
            section("Deine Fahrten hier") {
                if let best = record?.bestTime {
                    factRow("Bestzeit", Format.duration(best))
                }
                ForEach(list.prefix(3)) { s in
                    Button { open(s.id) } label: {
                        HStack {
                            Text(HomeFormat.relativeDate(s.start)).font(.system(size: 17, weight: .medium))
                            Spacer(minLength: 12)
                            Text("\(Format.duration(s.activeDuration)) · \(Format.duration(s.displayPace)) /500 m")
                                .font(.system(size: 17).monospacedDigit())
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

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 22, weight: .semibold))
            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func factRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label).font(.system(size: 16)).foregroundStyle(Theme.secondaryText).frame(width: 130, alignment: .leading)
            Text(value).font(.system(size: 17)).fixedSize(horizontal: false, vertical: true)
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
