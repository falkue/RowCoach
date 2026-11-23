import SwiftUI
import RowCoachKit

/// Seen-Pass: je Strecke eine Kachel mit Luftbild, Name, Region, Fahrten, km und Bestzeit. Ungefahrene Strecken
/// heissen „noch offen“ – ohne Sperren, ohne Prozent-Sammelzwang (startscreen-gamification.md 3d).
struct SeenPassTile: View {
    let course: Course
    let record: TrainingStats.CourseRecord?
    /// „Heute“: Strecke des Vorschlags
    let isSuggested: Bool
    /// „Zuletzt“: Strecke der letzten Fahrt
    let isLast: Bool
    var width: CGFloat? = 250

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CourseMapPreview(course: course, coverWithImage: true, showsMarkers: false)
                .frame(height: 120)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(alignment: .topLeading) { badge.padding(10) }
            VStack(alignment: .leading, spacing: 4) {
                Text(HomeFormat.courseShort(course.title))
                    .font(.system(size: 18, weight: .semibold))
                    .lineLimit(1)
                Text(course.region)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                Spacer().frame(height: 4)
                if let r = record, r.rides > 0 {
                    Text("\(r.rides) \(r.rides == 1 ? "Fahrt" : "Fahrten") · \(HomeFormat.kmShort(r.distance))")
                        .font(.system(size: 15, weight: .medium).monospacedDigit())
                    Text(r.bestTime.map { "Bestzeit \(Format.duration($0))" } ?? "noch keine ganze Strecke")
                        .font(.system(size: 14).monospacedDigit())
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    Text("noch offen")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.open)
                    Text("\(HomeFormat.km(PaceLineSettings.courseLength(course))) Strecke")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(14)
        }
        .frame(width: width)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(isSuggested ? Theme.evening : Theme.cardStroke, lineWidth: isSuggested ? 2.5 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Strecke wählen")
    }

    @ViewBuilder
    private var badge: some View {
        if isSuggested {
            BadgeText(text: "Heute", fill: Theme.evening, foreground: .black.opacity(0.85))
        } else if isLast {
            BadgeText(text: "Zuletzt", fill: Color.black.opacity(0.65), foreground: .white)
        }
    }
}

private struct BadgeText: View {
    let text: String
    let fill: Color
    let foreground: Color

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(fill, in: Capsule())
    }
}

/// Schmale Vorschau-Zeile des Seen-Passes (wenn der Platz für die Kacheln nicht reicht)
struct SeenPassChip: View {
    let course: Course
    let record: TrainingStats.CourseRecord?
    let isSuggested: Bool
    let isLast: Bool

    var body: some View {
        HStack(spacing: 10) {
            CourseMapPreview(course: course, coverWithImage: true, showsMarkers: false)
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(HomeFormat.courseShort(course.title)).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    if isSuggested {
                        Text("Heute").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.evening)
                    } else if isLast {
                        Text("Zuletzt").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                    }
                }
                if let r = record, r.rides > 0 {
                    Text("\(r.rides) × · \(HomeFormat.kmShort(r.distance))")
                        .font(.system(size: 14).monospacedDigit())
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    Text("noch offen").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.open)
                }
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 14)
        .padding(.vertical, 6)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(isSuggested ? Theme.evening : Theme.cardStroke, lineWidth: isSuggested ? 2 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Strecke wählen")
    }
}

/// Band „Deine Strecken“ über die ganze Breite, horizontal scrollbar. `compact` = schmale Vorschau-Zeile.
struct SeenPassStrip: View {
    let courses: [Course]
    let stats: TrainingStats?
    let suggestion: DailySuggestion?
    var compact = false
    let onSelect: (Course) -> Void
    let onShowAll: () -> Void

    private func record(_ c: Course) -> TrainingStats.CourseRecord? { stats?.courses[c.id] ?? stats?.courses[c.title] }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 14) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text("Deine Strecken").font(.system(size: compact ? 20 : 24, weight: .semibold))
                if !compact {
                    Text("Tippen wählt die Strecke für den Vorschlag oder zum freien Rudern")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
                Spacer()
                Button(action: onShowAll) {
                    HStack(spacing: 4) {
                        Text("Alle Wege")
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Seen-Pass, Frei rudern und alle Trainings")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: compact ? 10 : 16) {
                    ForEach(courses) { c in
                        Button { onSelect(c) } label: {
                            if compact {
                                SeenPassChip(course: c, record: record(c), isSuggested: suggestion?.courseId == c.id,
                                             isLast: stats?.lastRide?.session.courseId == c.id)
                            } else {
                                SeenPassTile(course: c, record: record(c), isSuggested: suggestion?.courseId == c.id,
                                             isLast: stats?.lastRide?.session.courseId == c.id)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

/// Auswahl nach Tippen auf eine Strecke: für den Vorschlag wählen, Vorschlag hier starten, frei rudern oder ein
/// anderes Training auf dieser Strecke.
struct CourseActionsModifier: ViewModifier {
    @Binding var course: Course?
    let suggestion: DailySuggestion?
    let preferredCourseId: String?
    let onPick: (String?) -> Void
    let onStart: (DailySuggestion.Option) -> Void
    let onRoute: (RowingRoute) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(Text(course?.title ?? "Strecke"),
                                   isPresented: Binding(get: { course != nil }, set: { if !$0 { course = nil } }),
                                   titleVisibility: .visible, presenting: course) { c in
            if suggestion?.courseId != c.id {
                Button("Für den Vorschlag wählen") { onPick(c.id) }
            }
            if let s = suggestion, let plan = PlanLibrary.plan(id: s.planId) {
                Button("\(plan.shortName) hier starten") { onStart(.plan(planId: s.planId, courseId: c.id)) }
            }
            Button("Frei rudern hier") { onStart(.free(courseId: c.id)) }
            Button("Anderes Training hier …") { onRoute(.coursePlans(courseId: c.id)) }
            if preferredCourseId != nil {
                Button("Strecke wieder automatisch wählen") { onPick(nil) }
            }
            Button("Abbrechen", role: .cancel) {}
        }
    }
}

extension View {
    func courseActions(course: Binding<Course?>, suggestion: DailySuggestion?, preferredCourseId: String?,
                       onPick: @escaping (String?) -> Void, onStart: @escaping (DailySuggestion.Option) -> Void,
                       onRoute: @escaping (RowingRoute) -> Void) -> some View {
        modifier(CourseActionsModifier(course: course, suggestion: suggestion, preferredCourseId: preferredCourseId,
                                       onPick: onPick, onStart: onStart, onRoute: onRoute))
    }
}

/// „Anders wählen“: Frei rudern (Streckenwahl mit Tempo-Linie), Training (Programmliste mit Filtern) und der ganze
/// Seen-Pass.
struct CourseChoiceView: View {
    let model: HomeModel
    let courses: [Course]
    let onPick: (String?) -> Void
    let onRoute: (RowingRoute) -> Void

    @Environment(\.rowingLaunch) private var launch
    @State private var selected: Course?
    private let columns = [GridItem(.adaptive(minimum: 250), spacing: 16)]

    init(model: HomeModel, courses: [Course], onPick: @escaping (String?) -> Void,
         onRoute: @escaping (RowingRoute) -> Void) {
        self.model = model
        self.courses = courses
        self.onPick = onPick
        self.onRoute = onRoute
    }

    private func record(_ c: Course) -> TrainingStats.CourseRecord? {
        model.stats?.courses[c.id] ?? model.stats?.courses[c.title]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { modeCards }
                    VStack(spacing: 16) { modeCards }
                }
                Text("Deine Strecken").font(.system(size: 26, weight: .semibold))
                Text("Tippe auf eine Strecke: für den Vorschlag wählen, frei rudern oder ein Training auf ihr starten.")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.secondaryText)
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(courses) { c in
                        Button { selected = c } label: {
                            SeenPassTile(course: c, record: record(c), isSuggested: model.suggestion?.courseId == c.id,
                                         isLast: model.stats?.lastRide?.session.courseId == c.id, width: nil)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 1200)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.homeBackground.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .navigationTitle("Anders wählen")
        .navigationBarTitleDisplayMode(.inline)
        .courseActions(course: $selected, suggestion: model.suggestion, preferredCourseId: model.preferredCourseId,
                       onPick: onPick, onStart: { launch?.callAsFunction($0) }, onRoute: onRoute)
    }

    @ViewBuilder
    private var modeCards: some View {
        NavigationLink(value: RowingRoute.free) {
            ModeCard(title: "Frei rudern", text: "Strecke wählen und losrudern, auf Wunsch mit Tempo-Linie.",
                     systemImage: "figure.rower", tint: Theme.accent)
        }
        .buttonStyle(.plain)
        NavigationLink(value: RowingRoute.plans) {
            ModeCard(title: "Training", text: "Alle Programme mit Filtern, dann eine Strecke.",
                     systemImage: "chart.bar.xaxis", tint: Theme.phaseColor(.work))
        }
        .buttonStyle(.plain)
    }
}

/// Profil prüfen (Hinweis auf der Vorschlagskarte): Maximalpuls, Ruhepuls, 2000-m-Bestzeit. „Werte stimmen“
/// speichert die angezeigten Werte, auch wenn sie den Voreinstellungen entsprechen; dann verschwindet der Hinweis.
struct ProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ProfileState.maxHRKey) private var maxHR = 185
    @AppStorage(ProfileState.restHRKey) private var restHR = 55
    @AppStorage(TrainingSettings.best2kKey) private var best2k = PaceTargets.defaultBest2k
    let onDone: () -> Void

    init(onDone: @escaping () -> Void = {}) {
        self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("Maximalpuls: \(maxHR)", value: $maxHR, in: 120...220)
                    Stepper("Ruhepuls: \(restHR)", value: $restHR, in: 30...100)
                    Stepper("2000 m Bestzeit: \(Format.duration(best2k))", value: $best2k, in: 330...720, step: 1)
                } footer: {
                    Text("Pulszonen richten sich nach der Herzfrequenzreserve (Maximalpuls − Ruhepuls), die Tempo-Ziele der Trainings nach der 2000-m-Bestzeit. Dieselben Werte stehen unter Einstellungen → Profil.")
                }
                Section {
                    Button("Werte stimmen") {
                        let d = UserDefaults.standard
                        d.set(maxHR, forKey: ProfileState.maxHRKey)
                        d.set(restHR, forKey: ProfileState.restHRKey)
                        d.set(best2k, forKey: TrainingSettings.best2kKey)
                        onDone()
                        dismiss()
                    }
                    .font(.headline)
                }
            }
            .navigationTitle("Profil prüfen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schliessen") { dismiss() }
                }
            }
        }
    }
}
