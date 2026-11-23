import SwiftUI
import SwiftData
import RowCoachKit

/// Startbildschirm im Tab „Rudern“, Variante A „Heute-Karte“ mit Seen-Pass (docs/design/startscreen.md).
///
/// iPad quer: Kopf (Logo, Gerätestatus), links die grosse Vorschlagskarte, rechts „Diese Woche“ und „Letzte Fahrt“,
/// darunter der Seen-Pass über die ganze Breite (bei wenig Höhe als schmale Vorschau-Zeile; die ganze Sammlung steht
/// hinter „Anders wählen“). iPhone hoch und iPad hoch: alles in einer Spalte, „Los“ ohne Scrollen sichtbar.
struct HomeView: View {
    let model: HomeModel
    /// verfügbare Strecken (Kartenpakete; ohne Pakete die Teststrecke)
    let courses: [Course]
    /// Fahrt starten (Vorschlag, Alternative, Strecke aus dem Seen-Pass)
    let onStart: (DailySuggestion.Option) -> Void
    /// Navigation im Tab (Anders wählen, Training auf einer Strecke)
    let onRoute: (RowingRoute) -> Void
    /// Strecke für den Vorschlag wählen (nil = automatisch)
    let onPick: (String?) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(WorkoutRecovery.self) private var recovery
    @Query(sort: \StoredWorkout.startDate, order: .reverse) private var workouts: [StoredWorkout]
    @AppStorage(TrainingSettings.best2kKey) private var best2k = PaceTargets.defaultBest2k
    @AppStorage(ProfileState.maxHRKey) private var maxHR = 185
    @AppStorage(ProfileState.restHRKey) private var restHR = 55
    @AppStorage(HomeSettings.weeklyGoalKey) private var weeklyGoal = HomeSettings.defaultWeeklyGoal
    @State private var selectedCourse: Course?
    @State private var showProfile = false
    /// zählt hoch, wenn das Profil bestätigt wurde oder die App wieder aktiv wird (neu rechnen, neuer Tag)
    @State private var tick = 0

    init(model: HomeModel, courses: [Course], onStart: @escaping (DailySuggestion.Option) -> Void,
         onRoute: @escaping (RowingRoute) -> Void, onPick: @escaping (String?) -> Void) {
        self.model = model
        self.courses = courses
        self.onStart = onStart
        self.onRoute = onRoute
        self.onPick = onPick
    }

    private struct RefreshID: Equatable {
        let keys: [HomeWorkoutKey]
        let courseIds: [String]
        let best2k: Double
        let weeklyGoal: Int
        let tick: Int
    }

    private var keys: [HomeWorkoutKey] {
        workouts.map { HomeWorkoutKey(id: $0.id, effort: $0.effortScore ?? $0.effortEstimate) }
    }

    /// Hinweis „Profil prüfen“ (liest die Profilwerte, damit eine Änderung neu zeichnet)
    private var profileIsDefault: Bool {
        _ = (maxHR, restHR, best2k, tick)
        return ProfileState.isDefault
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let wide = size.width >= 1000 || (size.width >= 800 && size.width > size.height)
            ScrollView {
                if wide {
                    wideLayout(size)
                } else {
                    stackedLayout
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.homeBackground.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .task(id: RefreshID(keys: keys, courseIds: courses.map(\.id), best2k: best2k, weeklyGoal: weeklyGoal,
                            tick: tick)) {
            await model.refresh(container: context.container, keys: keys, courseIds: courses.map(\.id),
                                best2k: best2k, weeklyGoal: weeklyGoal)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { tick += 1 }
        }
        .sheet(isPresented: $showProfile) {
            ProfileSheet { tick += 1 }
        }
        .courseActions(course: $selectedCourse, suggestion: model.suggestion,
                       preferredCourseId: model.preferredCourseId, onPick: onPick, onStart: onStart,
                       onRoute: onRoute)
    }

    // MARK: Anordnung

    private func wideLayout(_ size: CGSize) -> some View {
        // Volle Seen-Pass-Kacheln nur, wenn die Höhe reicht (iPad 13" quer); sonst die schmale Vorschau-Zeile
        let fullStrip = size.height >= 900
        let mainHeight = max(560, size.height - 80 - (fullStrip ? 300 : 110) - 40)
        return VStack(alignment: .leading, spacing: 20) {
            header(compact: false)
            recoveryNotice
            if let s = model.suggestion, let stats = model.stats {
                HStack(alignment: .top, spacing: 20) {
                    suggestionCard(s, stats: stats, compact: false)
                        .frame(maxWidth: .infinity, minHeight: mainHeight, maxHeight: .infinity)
                    VStack(spacing: 20) {
                        WeekCard(stats: stats)
                        LastRideCard(stats: stats, course: course(stats.lastRide?.session.courseId))
                            .frame(maxHeight: .infinity)
                    }
                    .frame(width: min(450, size.width * 0.36))
                    .frame(maxHeight: .infinity)
                }
                .fixedSize(horizontal: false, vertical: true)
                seenPass(stats: stats, suggestion: s, compact: !fullStrip)
            } else {
                loading.frame(height: mainHeight)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 12)
        .padding(.bottom, 24)
    }

    private var stackedLayout: some View {
        VStack(alignment: .leading, spacing: 16) {
            header(compact: true)
            recoveryNotice
            if let s = model.suggestion, let stats = model.stats {
                suggestionCard(s, stats: stats, compact: true)
                WeekCard(stats: stats, compact: true)
                LastRideCard(stats: stats, course: course(stats.lastRide?.session.courseId), compact: true)
                seenPass(stats: stats, suggestion: s, compact: true)
            } else {
                loading.frame(height: 420)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 20)
    }

    // MARK: Bausteine

    private func course(_ id: String?) -> Course? {
        guard let id else { return nil }
        return courses.first { $0.id == id }
    }

    private func header(compact: Bool) -> some View {
        HStack(spacing: 12) {
            Image("Logo")
                .resizable()
                .frame(width: compact ? 40 : 48, height: compact ? 40 : 48)
                .clipShape(RoundedRectangle(cornerRadius: compact ? 9 : 11, style: .continuous))
                .accessibilityHidden(true)
            Text("RowCoach")
                .font(.system(size: compact ? 24 : 28, weight: .semibold))
            Spacer(minLength: 8)
            DeviceStatusChips(compact: compact)
        }
        .accessibilityElement(children: .contain)
    }

    /// Hinweis nach einer unterbrochenen Fahrt (Akku leer, App beendet oder abgestürzt), nur dann
    @ViewBuilder
    private var recoveryNotice: some View {
        if let notice = recovery.notice {
            RecoveryNoticeRow(text: notice) { recovery.notice = nil }
                .padding(14)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func suggestionCard(_ s: DailySuggestion, stats: TrainingStats, compact: Bool) -> some View {
        SuggestionCard(suggestion: s, course: course(s.courseId), courses: courses, isNewUser: stats.isEmpty,
                       best2k: best2k, profileIsDefault: profileIsDefault, compact: compact,
                       onStart: onStart, onChoose: { onRoute(.choose) }, onProfile: { showProfile = true })
    }

    private func seenPass(stats: TrainingStats, suggestion: DailySuggestion, compact: Bool) -> some View {
        SeenPassStrip(courses: courses, stats: stats, suggestion: suggestion, compact: compact,
                      onSelect: { selectedCourse = $0 }, onShowAll: { onRoute(.choose) })
    }

    private var loading: some View {
        ProgressView()
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .homeCard()
    }
}
