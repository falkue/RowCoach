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
    /// Fahrt starten (Vorschlag)
    let onStart: (DailySuggestion.Option) -> Void
    /// „Anders wählen“: Tab Strecken
    let onChoose: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(WorkoutRecovery.self) private var recovery
    @Environment(AppRouter.self) private var router
    @Query(sort: \StoredWorkout.startDate, order: .reverse) private var workouts: [StoredWorkout]
    @AppStorage(TrainingSettings.best2kKey) private var best2k = PaceTargets.defaultBest2k
    @AppStorage(ProfileState.maxHRKey) private var maxHR = 185
    @AppStorage(ProfileState.restHRKey) private var restHR = 55
    @AppStorage(HomeSettings.profileBannerDismissedKey) private var profileBannerDismissed = false
    @State private var showProfile = false
    @State private var showPreview = false
    @State private var showWeek = false
    @State private var openWorkout: StoredWorkout?
    /// zählt hoch, wenn das Profil bestätigt wurde (Banner neu prüfen)
    @State private var tick = 0

    init(model: HomeModel, courses: [Course], onStart: @escaping (DailySuggestion.Option) -> Void,
         onChoose: @escaping () -> Void) {
        self.model = model
        self.courses = courses
        self.onStart = onStart
        self.onChoose = onChoose
    }

    private enum Layout { case landscape, portrait, phone }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let layout: Layout = size.width >= 900 && size.width > size.height ? .landscape
                : (size.width >= 700 ? .portrait : .phone)
            Group {
                if layout == .landscape {
                    // Querformat ohne Scrollen: die Karten teilen sich die Höhe, nichts wird abgeschnitten
                    content(layout, size: size)
                        .frame(maxHeight: .infinity, alignment: .top)
                } else {
                    ScrollView { content(layout, size: size) }
                        .scrollIndicators(.hidden)
                }
            }
            .overlay(alignment: .top) {
                // Abdunklung unter Statuszeile und schwebender Tab-Leiste
                LinearGradient(stops: [.init(color: Theme.bg, location: 0),
                                       .init(color: Theme.bg.opacity(0.92), location: 0.7),
                                       .init(color: Theme.bg.opacity(0), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: geo.safeAreaInsets.top + 20)
                    .offset(y: -geo.safeAreaInsets.top)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .dsPageBackground()
        .sheet(isPresented: $showProfile) {
            ProfileSheet { tick += 1 }
        }
        .sheet(isPresented: $showPreview) {
            if let s = model.suggestion {
                SuggestionPreviewSheet(suggestion: s, course: course(s.courseId), best2k: best2k, onStart: onStart)
            }
        }
        .sheet(isPresented: $showWeek) {
            if let stats = model.stats {
                WeekDetailSheet(stats: stats) {
                    showWeek = false
                    router.openHistory()
                }
            }
        }
        .sheet(item: $openWorkout) { item in
            WorkoutSheet(item: item)
        }
    }

    // MARK: Anordnung

    @ViewBuilder
    private func content(_ layout: Layout, size: CGSize) -> some View {
        let margin = DS.Space.margin(compact: layout == .phone)
        VStack(alignment: .leading, spacing: layout == .phone ? 14 : 20) {
            header(compact: layout == .phone)
            notices
            if let s = model.suggestion, let stats = model.stats {
                switch layout {
                case .landscape:
                    HStack(alignment: .top, spacing: DS.Space.l) {
                        card(s, stats: stats, layout: .landscape)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        VStack(spacing: 20) {
                            WeekSummaryCard(stats: stats) { showWeek = true }
                                .frame(maxHeight: .infinity)
                            secondCard(stats, compact: false)
                                .frame(maxHeight: .infinity)
                        }
                        .frame(width: min(480, size.width * 0.32))
                    }
                    .frame(maxHeight: .infinity)
                case .portrait:
                    card(s, stats: stats, layout: .portrait)
                        .frame(height: max(560, size.height * 0.55))
                    HStack(alignment: .top, spacing: 20) {
                        WeekSummaryCard(stats: stats) { showWeek = true }
                            .frame(maxHeight: .infinity)
                        secondCard(stats, compact: false)
                            .frame(maxHeight: .infinity)
                    }
                    .frame(height: max(380, size.height * 0.45 - 140))
                case .phone:
                    card(s, stats: stats, layout: .phone)
                        .frame(height: max(440, min(540, size.height - 280)))
                    WeekSummaryCard(stats: stats, compact: true) { showWeek = true }
                    secondCard(stats, compact: true)
                }
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, minHeight: 420)
            }
        }
        .padding(.horizontal, margin)
        .padding(.top, layout == .phone ? 8 : 12)
        .padding(.bottom, layout == .landscape ? 16 : 24)
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
                              onChoose: onChoose, onPreview: { showPreview = true })
    }

    /// Zweite Nebenkarte: letzte Fahrt; ohne Fahrten „Deine Strecken“ (Seen-Pass mit Mini-Luftbildern)
    @ViewBuilder
    private func secondCard(_ stats: TrainingStats, compact: Bool) -> some View {
        if stats.lastRide != nil {
            LastRideSummaryCard(stats: stats, course: course(stats.lastRide?.session.courseId), compact: compact) {
                openLastRide(stats)
            }
        } else {
            CoursesTeaserCard(courses: courses, compact: compact, onOpen: onChoose)
        }
    }

    private func openLastRide(_ stats: TrainingStats) {
        guard let id = stats.lastRide?.session.id else { return }
        openWorkout = workouts.first { $0.id == id }
    }

    /// Kopf: grosser Titel „Heute“ mit Datum, rechts Gerätestatus (öffnet Geräte) und Einstellungen
    private func header(compact: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Heute").font(compact ? .largeTitle.bold() : .system(.largeTitle, weight: .bold))
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.subheadline)
                    .foregroundStyle(Theme.text2)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            DeviceStatusButton(compact: compact)
            Button { router.showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .frame(width: compact ? 38 : 46, height: compact ? 38 : 46)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Einstellungen"))
        }
    }

    /// Hinweise, nur wenn nötig: unterbrochene Fahrt (nicht bei Simulator) und einmalig „Profil prüfen“
    @ViewBuilder
    private var notices: some View {
        if let notice = recovery.notice, !(workouts.first(where: { $0.interrupted })?.simulated ?? false) {
            DSBanner(systemImage: "bolt.slash", text: notice, tone: .warn, onClose: { recovery.notice = nil })
        }
        if profileIsDefault && !profileBannerDismissed {
            DSBanner(systemImage: "person.crop.circle.badge.questionmark",
                     text: String(localized: "Pulszonen und Tempo beruhen noch auf Standardwerten."),
                     actionTitle: String(localized: "Profil prüfen"), action: { showProfile = true },
                     onClose: { profileBannerDismissed = true })
        }
    }

    /// liest die Profilwerte, damit eine Änderung neu zeichnet
    private var profileIsDefault: Bool {
        _ = (maxHR, restHR, best2k, tick)
        return ProfileState.isDefault
    }
}

/// Ohne Fahrten statt „Letzte Fahrt“: die Strecken des Seen-Passes mit Mini-Luftbildern
struct CoursesTeaserCard: View {
    let courses: [Course]
    var compact = false
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                HStack {
                    Text("DEINE STRECKEN").font(.footnote.weight(.bold)).tracking(2).foregroundStyle(Theme.text2)
                    Spacer()
                    Image(systemName: "chevron.right").font(.body.weight(.semibold)).foregroundStyle(Theme.text2)
                }
                Text("\(courses.count) Strecken offen").font(compact ? .title3.bold() : .title.bold())
                HStack(spacing: DS.Space.s) {
                    ForEach(courses.prefix(compact ? 4 : 5)) { c in
                        CourseMapPreview(course: c, coverWithImage: true, showsMarkers: false)
                            .frame(maxWidth: .infinity)
                            .frame(height: compact ? 56 : 72)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
                    }
                }
                if !compact { Spacer(minLength: 0) }
            }
            .dsCard(padding: compact ? DS.Space.m : DS.Space.xl, cornerRadius: compact ? 22 : 28, fillsHeight: !compact)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Alle Strecken zeigen"))
    }
}

/// Fahrt aus dem Verlauf als Sheet (Antippen von „Letzte Fahrt“ bzw. einer Fahrt auf der Streckenseite)
struct WorkoutSheet: View {
    let item: StoredWorkout
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            HistoryDetailView(item: item)
                .dsSheetChrome(item.courseTitle ?? String(localized: "Training")) { dismiss() }
        }
    }
}
