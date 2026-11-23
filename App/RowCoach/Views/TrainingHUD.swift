import SwiftUI
import RowCoachKit

/// Phasenanzeige während eines Trainings: aktuelle Phase mit Zielen und Ampeln, Fortschritt, Rest, nächste Phase.
struct PhasePanel: View {
    let status: PlanStatus
    let best2k: Double
    let snapshot: RowingSnapshot
    let zones: HeartRateZones
    var compact = false

    init(status: PlanStatus, best2k: Double, snapshot: RowingSnapshot, zones: HeartRateZones, compact: Bool = false) {
        self.status = status
        self.best2k = best2k
        self.snapshot = snapshot
        self.zones = zones
        self.compact = compact
    }

    private var phase: WorkoutPhase? { status.phase }
    private var tint: Color { Theme.phaseColor(phase?.kind) }

    private var remainingText: String {
        if status.finished { return "fertig" }
        if let t = status.remainingTime { return Format.duration(t.rounded(.up)) }
        if let d = status.remainingDistance { return Format.distance(d.rounded(.up)) }
        return "–"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            HStack(spacing: 8) {
                Text(phase?.kind.title ?? "Training")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(tint.opacity(0.9)))
                    .foregroundStyle(.black)
                Text("Phase \(min(status.phaseIndex + 1, max(status.phaseCount, 1))) von \(status.phaseCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                Spacer(minLength: 0)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(phase?.title ?? "")
                    .font(compact ? .subheadline.weight(.semibold) : .headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Text(remainingText)
                    .font(Theme.number(compact ? 26 : 36))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
            }
            ProgressView(value: min(max(status.phaseProgress, 0), 1))
                .tint(tint)
            targets
            if let next = status.nextPhase {
                HStack(spacing: 6) {
                    Circle().fill(Theme.phaseColor(next.kind)).frame(width: 8, height: 8)
                    Text("Als Nächstes: \(next.title) · \(PlanFormat.length(next))")
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .font(compact ? .footnote.weight(.semibold) : .subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
            } else if !status.finished {
                Text("Als Nächstes: Ende des Trainings")
                    .font(compact ? .footnote.weight(.semibold) : .subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }
        }
        .padding(.horizontal, compact ? 12 : 16)
        .padding(.vertical, compact ? 10 : 12)
        .hudPanel()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var targets: some View {
        if let p = phase {
            let spm = p.spmRange
            let pace = p.paceRange(best2k: best2k)
            HStack(spacing: compact ? 10 : 14) {
                if let spm {
                    TargetItem(text: PlanFormat.strokeRate(spm),
                               light: TargetLight.strokeRate(snapshot.strokeRate, target: spm))
                }
                if let pace {
                    TargetItem(text: PlanFormat.paceRange(pace),
                               light: TargetLight.pace(snapshot.pace, target: pace))
                }
                if let z = p.hrZone {
                    TargetItem(text: "Zone \(z)",
                               light: TargetLight.heartRate(zone: snapshot.heartRate.map { zones.zone(for: $0) },
                                                            target: z))
                }
            }
            .font((compact ? Font.caption : Font.subheadline).weight(.semibold).monospacedDigit())
            .foregroundStyle(.white)
        }
    }
}

/// Ziel mit Ampelpunkt
private struct TargetItem: View {
    let text: String
    let light: TargetLight

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Theme.lightColor(light))
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 0.5))
            Text(text).lineLimit(1)
        }
        .accessibilityLabel("\(text), \(Self.lightName(light))")
    }

    private static func lightName(_ l: TargetLight) -> String {
        switch l {
        case .green: return "im Zielbereich"
        case .yellow: return "knapp daneben"
        case .red: return "ausserhalb"
        case .none: return "kein Messwert"
        }
    }
}

/// Gesamtfortschritt des Trainings: Phasenleiste mit Markierung, darunter Runde und Restzeit.
struct TrainingProgressPanel: View {
    let plan: WorkoutPlan
    let status: PlanStatus
    let best2k: Double
    /// Runde ab 0
    let lap: Int
    var height: CGFloat = 22

    init(plan: WorkoutPlan, status: PlanStatus, best2k: Double, lap: Int, height: CGFloat = 22) {
        self.plan = plan
        self.status = status
        self.best2k = best2k
        self.lap = lap
        self.height = height
    }

    var body: some View {
        VStack(spacing: 4) {
            PhaseBar(plan: plan, best2k: best2k, height: height, progress: status.overallProgress)
            HStack {
                Text(plan.name).lineLimit(1)
                Spacer()
                Text("Runde \(lap + 1)")
                Spacer()
                Text(status.finished ? "geschafft" : "noch ca. \(Format.duration(status.estimatedRemaining))")
            }
            .font(.caption2.weight(.medium).monospacedDigit())
            .foregroundStyle(Theme.secondaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Trainingsfortschritt")
        .accessibilityValue("\(Int((status.overallProgress * 100).rounded())) Prozent, Runde \(lap + 1)")
    }
}

/// Grosser Countdown 10 … 1 vor dem Phasenwechsel (oben in der Mitte; die Ruderfigur bleibt frei).
struct CountdownOverlay: View {
    let status: PlanStatus

    init(status: PlanStatus) {
        self.status = status
    }

    var body: some View {
        if status.countdownActive, let secs = status.secondsToChange {
            let n = max(Int(secs.rounded(.up)), 1)
            let next = status.nextPhase
            VStack(spacing: 2) {
                Text("\(n)")
                    .font(.system(size: 96, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.phaseColor(next?.kind))
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy, value: n)
                    .shadow(color: .black.opacity(0.6), radius: 8)
                Text(next.map { "Gleich: \($0.title)" } ?? "Gleich geschafft")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
            }
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
        }
    }
}
