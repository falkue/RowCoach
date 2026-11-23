import SwiftUI
import RowCoachKit

/// Programme aus `plans.json` im App-Bundle (Kopie von docs/trainings-recherche.json)
enum PlanLibrary {
    static let plans: [WorkoutPlan] = WorkoutPlanCatalog.loadBundled()

    static func plan(id: String) -> WorkoutPlan? { plans.first { $0.id == id } }
}

/// Navigation im Tab „Rudern“
enum RowingRoute: Hashable {
    /// Streckenwahl zum freien Rudern
    case free
    /// Liste der Trainingsprogramme
    case plans
    /// Detailansicht eines Programms
    case plan(String)
    /// Streckenwahl für ein Programm
    case courses(planId: String)
}

/// Erste Seite im Tab „Rudern“: frei rudern oder ein Training wählen.
struct RowingModeView: View {
    init() {}

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                NavigationLink(value: RowingRoute.free) {
                    ModeCard(title: "Frei rudern", text: "Strecke wählen und losrudern – ohne Vorgaben.",
                             systemImage: "figure.rower", tint: Theme.accent)
                }
                NavigationLink(value: RowingRoute.plans) {
                    ModeCard(title: "Training",
                             text: "Programm mit Phasen, Zielen und Countdown wählen, dann eine Strecke.",
                             systemImage: "chart.bar.xaxis", tint: Theme.phaseColor(.work))
                }
            }
            .buttonStyle(.plain)
            .padding()
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct ModeCard: View {
    let title: String
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 64, height: 64)
                .background(Circle().fill(tint.opacity(0.15)))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title2.bold())
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").foregroundStyle(.secondary)
        }
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Kacheln der Trainingsprogramme
struct PlanListView: View {
    let plans: [WorkoutPlan]
    @AppStorage(TrainingSettings.best2kKey) private var best2k = PaceTargets.defaultBest2k
    private let columns = [GridItem(.adaptive(minimum: 320), spacing: 16)]

    init(plans: [WorkoutPlan]) {
        self.plans = plans
    }

    var body: some View {
        ScrollView {
            if plans.isEmpty {
                ContentUnavailableView("Keine Programme", systemImage: "list.bullet.rectangle",
                                       description: Text("plans.json fehlt im App-Bundle oder ist nicht lesbar."))
                    .padding(.top, 60)
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(plans) { plan in
                        NavigationLink(value: RowingRoute.plan(plan.id)) {
                            PlanTile(plan: plan, best2k: best2k)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Training")
    }
}

private struct PlanTile: View {
    let plan: WorkoutPlan
    let best2k: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(plan.name).font(.headline).lineLimit(2)
                Spacer(minLength: 8)
                if !plan.level.isEmpty { LevelBadge(level: plan.level) }
            }
            Label(PlanFormat.planLength(plan, best2k: best2k), systemImage: "clock")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(plan.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3, reservesSpace: true)
            PhaseBar(plan: plan, best2k: best2k, height: 28)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Programm ansehen")
    }
}

private struct LevelBadge: View {
    let level: String

    var body: some View {
        Text(level)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.secondary.opacity(0.2)))
    }
}

/// Kleine Balkengrafik der Phasen: Breite nach geschätzter Dauer, Höhe und Farbe nach Phasenart.
/// `progress` (0…1) und `currentIndex` heben im HUD den erledigten Teil hervor.
struct PhaseBar: View {
    let shares: [Double]
    let kinds: [WorkoutPhase.Kind]
    var height: CGFloat = 24
    var progress: Double? = nil

    init(plan: WorkoutPlan, best2k: Double, height: CGFloat = 24, progress: Double? = nil) {
        let secs = plan.phases.map { max($0.estimatedSeconds(best2k: best2k), 1) }
        let total = secs.reduce(0, +)
        self.shares = secs.map { total > 0 ? $0 / total : 0 }
        self.kinds = plan.phases.map(\.kind)
        self.height = height
        self.progress = progress
    }

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = shares.count > 40 ? 0.5 : 1
            let usable = max(geo.size.width - gap * CGFloat(max(shares.count - 1, 0)), 1)
            ZStack(alignment: .bottomLeading) {
                HStack(alignment: .bottom, spacing: gap) {
                    ForEach(Array(shares.enumerated()), id: \.offset) { i, share in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Theme.phaseColor(kinds[i]).opacity(progress == nil ? 0.9 : 0.45))
                            .frame(width: max(usable * share, 1), height: geo.size.height * Theme.phaseHeight(kinds[i]))
                    }
                }
                if let progress {
                    // erledigter Teil kräftig: dieselbe Leiste, auf die Breite des Fortschritts beschnitten
                    HStack(alignment: .bottom, spacing: gap) {
                        ForEach(Array(shares.enumerated()), id: \.offset) { i, share in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Theme.phaseColor(kinds[i]))
                                .frame(width: max(usable * share, 1), height: geo.size.height * Theme.phaseHeight(kinds[i]))
                        }
                    }
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: geo.size.width * min(max(progress, 0), 1))
                    }
                    Rectangle().fill(Color.white)
                        .frame(width: 2, height: geo.size.height + 6)
                        .offset(x: min(max(geo.size.width * progress - 1, 0), geo.size.width - 2), y: 3)
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Detailansicht eines Programms: Zweck, Phasen mit Zielen, Quellen; weiter zur Streckenwahl.
struct PlanDetailView: View {
    let plan: WorkoutPlan
    @AppStorage(TrainingSettings.best2kKey) private var best2k = PaceTargets.defaultBest2k

    init(plan: WorkoutPlan) {
        self.plan = plan
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                NavigationLink(value: RowingRoute.courses(planId: plan.id)) {
                    Label("Strecke wählen", systemImage: "map")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                phases
                sources
            }
            .padding()
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(plan.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(plan.name).font(.largeTitle.bold())
                Spacer(minLength: 8)
                if !plan.level.isEmpty { LevelBadge(level: plan.level) }
            }
            Label(PlanFormat.planLength(plan, best2k: best2k), systemImage: "clock")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.secondary)
            if !plan.summary.isEmpty { Text(plan.summary).font(.body) }
            if !plan.purpose.isEmpty {
                Label(plan.purpose, systemImage: "target").font(.subheadline).foregroundStyle(.secondary)
            }
            PhaseBar(plan: plan, best2k: best2k, height: 40)
                .padding(.top, 4)
        }
    }

    private var phases: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Phasen").font(.title3.bold())
            Text("Tempo bezogen auf deine 2000-m-Bestzeit von \(Format.duration(best2k)) (\(Format.pace(PaceTargets.basePace500(best2k: best2k))) /500 m; ändern unter Einstellungen → Profil).")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if TrainingSettings.paceTargetsAreGuides(plan) {
                Label("Tempo-Ziele sind Richtwerte", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(plan.phases.enumerated()), id: \.offset) { i, p in
                    PhaseRow(number: i + 1, phase: p, best2k: best2k)
                    if i + 1 < plan.phases.count { Divider() }
                }
            }
            .padding(.horizontal, 12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    @ViewBuilder
    private var sources: some View {
        if !plan.sources.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Quellen").font(.title3.bold())
                ForEach(Array(plan.sources.enumerated()), id: \.offset) { _, s in
                    VStack(alignment: .leading, spacing: 2) {
                        if let u = s.url, let url = URL(string: u) {
                            Link(s.title.isEmpty ? u : s.title, destination: url)
                        } else {
                            Text(s.title)
                        }
                        let meta = [s.publisher, s.published].compactMap { $0 }.filter { !$0.isEmpty }
                        if !meta.isEmpty {
                            Text(meta.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline)
                }
            }
        }
    }
}

private struct PhaseRow: View {
    let number: Int
    let phase: WorkoutPhase
    let best2k: Double

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Theme.phaseColor(phase.kind))
                .frame(width: 6)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(number). \(phase.kind.title)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text(PlanFormat.length(phase)).font(.headline.monospacedDigit())
                }
                Text(phase.title).font(.subheadline)
                targets
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private var targets: some View {
        HStack(spacing: 14) {
            if let r = phase.spmRange {
                Label(PlanFormat.strokeRate(r), systemImage: "metronome")
            }
            if let r = phase.paceRange(best2k: best2k) {
                Label(PlanFormat.paceRange(r) + " /500 m", systemImage: "speedometer")
            }
            if let z = phase.hrZone {
                Label("Zone \(z)", systemImage: "heart.fill").foregroundStyle(Theme.zoneColor(z))
            }
            if phase.kind == .rest {
                Text(phase.activeRest == false ? "Stillstand" : "locker weiterrudern")
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }
}
