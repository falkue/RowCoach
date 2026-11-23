import SwiftUI
import SwiftData
import RowCoachKit

/// Startbildschirm im Tab „Rudern“, Variante C „ruhig“ (docs/design/startscreen-ux-review.md): eine Hauptaktion
/// (Vorschlag für heute) und zwei ruhige Nebenkarten (Diese Woche, Letzte Fahrt).
///
/// - iPad quer: Vorschlag links, rechts übereinander Woche und letzte Fahrt; nichts muss gescrollt werden.
/// - iPad hoch: Vorschlag oben über die volle Breite, darunter Woche und letzte Fahrt nebeneinander.
/// - iPhone hoch: Vorschlag mit „Los“, darunter Woche als Punktreihe und letzte Fahrt als eine Zeile.
/// Eine Ebene tiefer: Vorschau mit Zielwerten (Tippen auf die Karte), Wochenansicht (Tippen auf „Diese Woche“),
/// Fahrt im Verlauf (Tippen auf „Letzte Fahrt“), Seen-Pass und Alternativen hinter „Anders wählen“.
struct HomeView: View {
    let model: HomeModel
    /// verfügbare Strecken (Kartenpakete; ohne Pakete die Teststrecke)
    let courses: [Course]
    /// Fahrt starten (Vorschlag, Alternative)
    let onStart: (DailySuggestion.Option) -> Void
    /// Navigation im Tab (Anders wählen)
    let onRoute: (RowingRoute) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(WorkoutRecovery.self) private var recovery
    @Query(sort: \StoredWorkout.startDate, order: .reverse) private var workouts: [StoredWorkout]
    @AppStorage(TrainingSettings.best2kKey) private var best2k = PaceTargets.defaultBest2k
    @AppStorage(ProfileState.maxHRKey) private var maxHR = 185
    @AppStorage(ProfileState.restHRKey) private var restHR = 55
    @AppStorage(HomeSettings.weeklyGoalKey) private var weeklyGoal = HomeSettings.defaultWeeklyGoal
    @AppStorage(HomeSettings.profileBannerDismissedKey) private var profileBannerDismissed = false
    @State private var showProfile = false
    @State private var showPreview = false
    @State private var showWeek = false
    @State private var openWorkout: StoredWorkout?
    /// zählt hoch, wenn das Profil bestätigt wurde oder die App wieder aktiv wird (neu rechnen, neuer Tag)
    @State private var tick = 0

    init(model: HomeModel, courses: [Course], onStart: @escaping (DailySuggestion.Option) -> Void,
         onRoute: @escaping (RowingRoute) -> Void) {
        self.model = model
        self.courses = courses
        self.onStart = onStart
        self.onRoute = onRoute
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

    private enum Layout { case landscape, portrait, phone }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let layout: Layout = size.width >= 900 && size.width > size.height ? .landscape
                : (size.width >= 700 ? .portrait : .phone)
            ScrollView {
                content(layout, size: size)
            }
            .scrollIndicators(.hidden)
            .overlay(alignment: .top) {
                // Abdunklung unter Statuszeile und schwebender Tab-Leiste
                LinearGradient(stops: [.init(color: Theme.homeBackground, location: 0),
                                       .init(color: Theme.homeBackground.opacity(0.92), location: 0.7),
                                       .init(color: Theme.homeBackground.opacity(0), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: geo.safeAreaInsets.top + 20)
                    .offset(y: -geo.safeAreaInsets.top)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
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
        .sheet(isPresented: $showPreview) {
            if let s = model.suggestion {
                SuggestionPreviewSheet(suggestion: s, course: course(s.courseId), best2k: best2k, onStart: onStart)
            }
        }
        .sheet(isPresented: $showWeek) {
            if let stats = model.stats { WeekDetailSheet(stats: stats) }
        }
        .sheet(item: $openWorkout) { item in
            WorkoutSheet(item: item)
        }
    }

    // MARK: Anordnung

    @ViewBuilder
    private func content(_ layout: Layout, size: CGSize) -> some View {
        let margin: CGFloat = layout == .phone ? 16 : 32
        VStack(alignment: .leading, spacing: layout == .phone ? 14 : 20) {
            header(compact: layout == .phone)
            notices
            if let s = model.suggestion, let stats = model.stats {
                switch layout {
                case .landscape:
                    // Höhe ohne Scrollen: sichtbare Höhe minus Kopf, Hinweise und Ränder
                    let h = max(560, size.height - 110)
                    HStack(alignment: .top, spacing: 24) {
                        card(s, stats: stats, layout: .landscape)
                            .frame(maxWidth: .infinity)
                        VStack(spacing: 20) {
                            WeekSummaryCard(stats: stats) { showWeek = true }
                                .frame(maxHeight: .infinity)
                            LastRideSummaryCard(stats: stats, course: course(stats.lastRide?.session.courseId)) {
                                openLastRide(stats)
                            }
                            .frame(maxHeight: .infinity)
                        }
                        .frame(width: min(480, size.width * 0.32))
                    }
                    .frame(height: h)
                case .portrait:
                    card(s, stats: stats, layout: .portrait)
                        .frame(height: max(560, size.height * 0.55))
                    HStack(alignment: .top, spacing: 20) {
                        WeekSummaryCard(stats: stats) { showWeek = true }
                            .frame(maxHeight: .infinity)
                        LastRideSummaryCard(stats: stats, course: course(stats.lastRide?.session.courseId)) {
                            openLastRide(stats)
                        }
                        .frame(maxHeight: .infinity)
                    }
                    .frame(height: max(380, size.height * 0.45 - 140))
                case .phone:
                    card(s, stats: stats, layout: .phone)
                        .frame(height: max(440, min(540, size.height - 280)))
                    WeekSummaryCard(stats: stats, compact: true) { showWeek = true }
                    LastRideSummaryCard(stats: stats, course: course(stats.lastRide?.session.courseId),
                                        compact: true) { openLastRide(stats) }
                }
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, minHeight: 420)
            }
        }
        .padding(.horizontal, margin)
        .padding(.top, layout == .phone ? 8 : 12)
        .padding(.bottom, 24)
    }

    // MARK: Bausteine

    private func course(_ id: String?) -> Course? {
        guard let id else { return nil }
        return courses.first { $0.id == id }
    }

    private func card(_ s: DailySuggestion, stats: TrainingStats, layout: SuggestionCard.Layout) -> some View {
        // „Neu für deinen Seen-Pass“ erst, wenn es schon Fahrten gibt (beim Einstieg ist alles neu)
        let isNewCourse = !stats.isEmpty && (s.courseId.map { stats.courses[$0] == nil } ?? false)
        return SuggestionCard(suggestion: s, course: course(s.courseId), isNewUser: stats.isEmpty,
                              isNewCourse: isNewCourse, best2k: best2k, layout: layout, onStart: onStart,
                              onChoose: { onRoute(.choose) }, onPreview: { showPreview = true })
    }

    private func openLastRide(_ stats: TrainingStats) {
        guard let id = stats.lastRide?.session.id else { return }
        openWorkout = workouts.first { $0.id == id }
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

    /// Hinweise, nur wenn nötig: unterbrochene Fahrt (nicht bei Simulator) und einmalig „Profil prüfen“
    @ViewBuilder
    private var notices: some View {
        if let notice = recovery.notice, !(workouts.first(where: { $0.interrupted })?.simulated ?? false) {
            RecoveryNoticeRow(text: notice) { recovery.notice = nil }
                .padding(14)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        if profileIsDefault && !profileBannerDismissed {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.questionmark").foregroundStyle(Theme.secondaryText)
                Text("Pulszonen und Tempo beruhen noch auf Standardwerten.")
                    .font(.system(size: 16))
                    .fixedSize(horizontal: false, vertical: true)
                Button("Profil prüfen") { showProfile = true }
                    .font(.system(size: 16, weight: .semibold))
                Spacer(minLength: 8)
                Button {
                    profileBannerDismissed = true
                } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Hinweis schliessen")
            }
            .padding(14)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    /// liest die Profilwerte, damit eine Änderung neu zeichnet
    private var profileIsDefault: Bool {
        _ = (maxHR, restHR, best2k, tick)
        return ProfileState.isDefault
    }
}

/// Fahrt aus dem Verlauf als Sheet (Antippen von „Letzte Fahrt“ bzw. einer Fahrt auf der Streckenseite)
struct WorkoutSheet: View {
    let item: StoredWorkout
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            HistoryDetailView(item: item)
                .navigationTitle(item.courseTitle ?? "Training")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Schliessen") { dismiss() } }
                }
        }
    }
}
