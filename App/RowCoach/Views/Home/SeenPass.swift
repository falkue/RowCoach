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
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(course.region)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
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

/// „Anders wählen“: Alternativen zum Vorschlag, die beiden Wege „Frei rudern“ (Streckenwahl mit Tempo-Linie) und
/// „Training“ (Programmliste mit Filtern) und der ganze Seen-Pass. Tippen auf eine Strecke öffnet ihre Streckenseite.
struct CourseChoiceView: View {
    let model: HomeModel
    let courses: [Course]

    @Environment(\.rowingLaunch) private var launch
    private let columns = [GridItem(.adaptive(minimum: 250), spacing: 16)]

    init(model: HomeModel, courses: [Course]) {
        self.model = model
        self.courses = courses
    }

    private func record(_ c: Course) -> TrainingStats.CourseRecord? {
        model.stats?.courses[c.id] ?? model.stats?.courses[c.title]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let s = model.suggestion, !s.alternatives.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Statt des Vorschlags").font(.system(size: 22, weight: .semibold))
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) { alternativeButtons(s) }
                            VStack(alignment: .leading, spacing: 10) { alternativeButtons(s) }
                        }
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { modeCards }
                    VStack(spacing: 16) { modeCards }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Deine Strecken").font(.system(size: 26, weight: .semibold))
                    Text("Tippe auf eine Strecke: Route, Sehenswertes und deine Fahrten, dann frei rudern oder mit Training.")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(courses) { c in
                        NavigationLink(value: RowingRoute.course(c.id)) {
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
    }

    @ViewBuilder
    private func alternativeButtons(_ s: DailySuggestion) -> some View {
        ForEach(s.alternatives, id: \.self) { option in
            Button { launch?.callAsFunction(option) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "play.fill").font(.system(size: 15))
                    Text(HomeFormat.optionTitle(option, courses: courses))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .frame(minHeight: 54)
                .background(Color.white.opacity(0.08), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.18)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
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
