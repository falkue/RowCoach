import SwiftUI
import RowCoachKit

/// Texte zu Phasen im Ruderbildschirm
enum PhaseText {
    /// „Intervall 2 von 4“, sonst die Phasenart („Pause“, „Einrudern“)
    static func kind(plan: WorkoutPlan, index: Int) -> String {
        guard plan.phases.indices.contains(index) else { return String(localized: "Training") }
        if let n = plan.workNumber(at: index), plan.workCount > 1 {
            return String(localized: "Intervall \(n) von \(plan.workCount)")
        }
        return plan.phases[index].kind.title
    }

    /// Beschriftung der Restzeit-Kachel: „Intervall noch“, „Pause noch“ …
    static func remainingTitle(_ phase: WorkoutPhase?) -> String {
        switch phase?.kind {
        case .work: return String(localized: "Intervall noch")
        case .rest: return String(localized: "Pause noch")
        case .warmup: return String(localized: "Einrudern noch")
        case .cooldown: return String(localized: "Ausrudern noch")
        case .other, .none: return String(localized: "Phase noch")
        }
    }

    /// Restzeit bzw. Restdistanz der Phase
    static func remaining(_ status: PlanStatus) -> String {
        if status.finished { return "0:00" }
        if let t = status.remainingTime { return Format.duration(t.rounded(.up)) }
        if let d = status.remainingDistance { return Format.distance(d.rounded(.up)) }
        return "–"
    }
}

/// Phasenanzeige während eines Trainings (links oben): Art mit Nummer, Bezeichnung, Fortschritt der Phase und was
/// als Nächstes kommt. Restzeit sowie Ziele und Ampeln stehen in den grossen Kacheln unten.
struct PhasePanel: View {
    let plan: WorkoutPlan
    let status: PlanStatus
    var compact = false

    init(plan: WorkoutPlan, status: PlanStatus, compact: Bool = false) {
        self.plan = plan
        self.status = status
        self.compact = compact
    }

    private var phase: WorkoutPhase? { status.phase }
    private var tint: Color { Theme.phaseColor(phase) }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            HStack(spacing: 8) {
                Text(PhaseText.kind(plan: plan, index: status.phaseIndex))
                    .font(.system(size: DS.HUD.label(compact: compact) + 2, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(tint))
                    .foregroundStyle(Color.black.opacity(0.85))
                if let p = phase, p.kind != .rest {
                    Text(p.intensity().title)
                        .font(.system(size: DS.HUD.label(compact: compact), weight: .semibold))
                        .foregroundStyle(Theme.text2)
                }
                Spacer(minLength: 0)
            }
            Text(phase?.title ?? "")
                .font(.system(size: compact ? 16 : 22, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            ProgressView(value: min(max(status.phaseProgress, 0), 1))
                .tint(tint)
            if let next = status.nextPhase {
                HStack(spacing: 6) {
                    Circle().fill(Theme.phaseColor(next)).frame(width: 10, height: 10)
                    Text("Als Nächstes: \(PhaseText.kind(plan: plan, index: status.phaseIndex + 1)) · \(PlanFormat.length(next))")
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .font(.system(size: compact ? 15 : 20, weight: .semibold))
                .foregroundStyle(Theme.text.opacity(0.92))
            } else if !status.finished {
                Text("Als Nächstes: Ende des Trainings")
                    .font(.system(size: compact ? 15 : 20, weight: .semibold))
                    .foregroundStyle(Theme.text.opacity(0.92))
            }
        }
        .padding(.horizontal, compact ? 12 : 18)
        .padding(.vertical, compact ? 10 : 14)
        .hudPanel()
        .accessibilityElement(children: .combine)
    }
}

/// Gesamtfortschritt des Trainings: Phasenleiste (nach Härte gefärbt) mit Markierung, darunter Programm und –
/// erst ab der zweiten Runde – die Runde. Die Restzeit des Trainings steht nur in der Kopfleiste.
struct TrainingProgressPanel: View {
    let plan: WorkoutPlan
    let status: PlanStatus
    let best2k: Double
    /// Runde ab 0
    let lap: Int
    var height: CGFloat = 22
    var compact = false

    init(plan: WorkoutPlan, status: PlanStatus, best2k: Double, lap: Int, height: CGFloat = 22, compact: Bool = false) {
        self.plan = plan
        self.status = status
        self.best2k = best2k
        self.lap = lap
        self.height = height
        self.compact = compact
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PhaseBar(plan: plan, best2k: best2k, height: height, progress: status.overallProgress)
            HStack {
                Text(plan.shortName).lineLimit(1)
                Spacer()
                if lap >= 1 { Text("Runde \(lap + 1)") }
            }
            .font(.system(size: DS.HUD.label(compact: compact), weight: .semibold))
            .foregroundStyle(Theme.text2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Trainingsfortschritt"))
        .accessibilityValue(Text("\(Int((status.overallProgress * 100).rounded())) Prozent"))
    }
}

/// Grosser Countdown 10 … 1 vor dem Phasenwechsel (oben in der Mitte; die Ruderfigur bleibt frei).
struct CountdownOverlay: View {
    let plan: WorkoutPlan
    let status: PlanStatus

    init(plan: WorkoutPlan, status: PlanStatus) {
        self.plan = plan
        self.status = status
    }

    var body: some View {
        if status.countdownActive, let secs = status.secondsToChange {
            let n = max(Int(secs.rounded(.up)), 1)
            let next = status.nextPhase
            VStack(spacing: 2) {
                Text("\(n)")
                    .font(.system(size: 110, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.phaseColor(next))
                    .contentTransition(.numericText(countsDown: true))
                    .shadow(color: .black.opacity(0.6), radius: 8)
                Text(next != nil ? String(localized: "Gleich: \(PhaseText.kind(plan: plan, index: status.phaseIndex + 1))")
                     : String(localized: "Gleich geschafft"))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
            }
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
        }
    }
}
