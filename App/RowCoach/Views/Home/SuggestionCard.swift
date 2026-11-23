import SwiftUI
import RowCoachKit

/// Texte für den Startbildschirm
enum HomeFormat {
    private static let locale = Locale(identifier: "de_CH")

    /// „4,0 km“ (Komma wie in den Entwürfen)
    static func km(_ meters: Double) -> String {
        String(format: "%.1f", meters / 1000).replacingOccurrences(of: ".", with: ",") + " km"
    }

    /// „24 km“ ab 10 km ohne Nachkommastelle, sonst „6,2 km“
    static func kmShort(_ meters: Double) -> String {
        meters >= 10_000 ? "\(Int((meters / 1000).rounded())) km" : km(meters)
    }

    static func minutes(_ m: Double) -> String { "\(Int(m.rounded()))" }

    /// „Heute, 11:27“, „Gestern, 11:27“, „Montag, 11:27“ (letzte 6 Tage), sonst „12. Nov., 11:27“
    static func relativeDate(_ date: Date, now: Date = Date(), calendar: Calendar = TrainingCalendar.swiss()) -> String {
        let time = DateFormatter()
        time.locale = locale
        time.calendar = calendar
        time.timeZone = calendar.timeZone
        time.dateFormat = "HH:mm"
        let t = time.string(from: date)
        if calendar.isDate(date, inSameDayAs: now) { return "Heute, \(t)" }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: y) {
            return "Gestern, \(t)"
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? 99
        let f = DateFormatter()
        f.locale = locale
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = days < 7 && days > 0 ? "EEEE" : "d. MMM"
        return "\(f.string(from: date)), \(t)"
    }

    /// Kurzname der Strecke: Teil vor „ – “ („Utoquai – Seefeld“ → „Utoquai“)
    static func courseShort(_ title: String) -> String {
        title.components(separatedBy: " – ").first ?? title
    }

    /// Titel einer Wahl („Lockere Grundlage 30 min“, „Frei rudern · Utoquai“)
    static func optionTitle(_ option: DailySuggestion.Option, courses: [Course]) -> String {
        switch option {
        case .plan(let id, _):
            return PlanLibrary.plan(id: id)?.shortName ?? id
        case .free(let courseId):
            if let c = courses.first(where: { $0.id == courseId }) { return "Frei rudern · \(courseShort(c.title))" }
            return "Frei rudern"
        }
    }

    /// „Rhein Basel – Rheinweg Kleinbasel · 32 min · Intervalle“
    static func planLine(plan: WorkoutPlan?, course: Course?, best2k: Double) -> String {
        var parts: [String] = []
        if let course { parts.append(course.title) }
        if let plan {
            parts.append(PlanFormat.planLength(plan, best2k: best2k))
            if !plan.category.isEmpty { parts.append(plan.category) }
        } else if let course {
            parts.append(Format.distance(PaceLineSettings.courseLength(course)))
        }
        return parts.joined(separator: " · ")
    }
}

/// Grosse Karte „Vorschlag für heute“: Luftbild der Strecke mit Route, Programm, Phasenleiste, Zielwerte,
/// Begründung, „Los“, „Anders wählen“ und zwei Alternativen.
struct SuggestionCard: View {
    let suggestion: DailySuggestion
    let course: Course?
    /// alle Strecken (für die Titel der Alternativen)
    let courses: [Course]
    /// noch keine Fahrt im Verlauf
    let isNewUser: Bool
    let best2k: Double
    /// Maximalpuls, Ruhepuls oder 2000-m-Bestzeit noch Voreinstellung
    let profileIsDefault: Bool
    var compact = false
    let onStart: (DailySuggestion.Option) -> Void
    let onChoose: () -> Void
    let onProfile: () -> Void

    private var plan: WorkoutPlan? { PlanLibrary.plan(id: suggestion.planId) }
    private var mainOption: DailySuggestion.Option {
        plan == nil ? .free(courseId: course?.id) : suggestion.option
    }

    private var kicker: String {
        if suggestion.doneToday { return "Heute erledigt · Vorschlag für morgen" }
        if isNewUser { return "Willkommen · Erste Fahrt" }
        return "Vorschlag für heute"
    }

    private var footnote: String {
        isNewUser ? "Ein ruhiger Einstieg. Fühlst du dich anders, wähle frei."
            : "Vorschlag aus deinen letzten Fahrten. Fühlst du dich anders, wähle frei."
    }

    var body: some View {
        if compact { compactBody } else { wideBody }
    }

    // MARK: iPad quer

    private var wideBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(kicker.uppercased())
                .font(.system(size: 15, weight: .bold))
                .tracking(2.5)
                .foregroundStyle(Theme.evening)
            VStack(alignment: .leading, spacing: 8) {
                Text(plan?.shortName ?? "Frei rudern")
                    .font(.system(size: 46, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
                Text(HomeFormat.planLine(plan: plan, course: course, best2k: best2k))
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let plan {
                PhaseBar(plan: plan, best2k: best2k, height: 40)
                    .frame(maxWidth: 560)
            }
            targets(size: 34, spacing: 34)
            profileHint
            reasonBox(size: 18)
            HStack(spacing: 16) {
                goButton(height: 72, font: 28)
                chooseButton(title: "Anders wählen", height: 72)
            }
            alternativesRow
            Text(footnote)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: 600, alignment: .leading)
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            GeometryReader { g in
                ZStack {
                    Theme.card
                    if let course {
                        CourseMapPreview(course: course,
                                         trackInsets: EdgeInsets(top: 40, leading: g.size.width * 0.55, bottom: 40,
                                                                 trailing: 36),
                                         coverWithImage: true, showsMarkers: false)
                    }
                    LinearGradient(stops: [.init(color: .black.opacity(0.88), location: 0),
                                           .init(color: .black.opacity(0.70), location: 0.45),
                                           .init(color: .black.opacity(0.15), location: 0.78),
                                           .init(color: .clear, location: 1)],
                                   startPoint: .leading, endPoint: .trailing)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Theme.cardStroke))
    }

    // MARK: iPhone hoch

    private var compactBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(kicker.uppercased())
                .font(.system(size: 13, weight: .bold))
                .tracking(2)
                .foregroundStyle(Theme.evening)
            Text(plan?.shortName ?? "Frei rudern")
                .font(.system(size: 30, weight: .bold))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
            Text(HomeFormat.planLine(plan: plan, course: course, best2k: best2k))
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
            if let plan { PhaseBar(plan: plan, best2k: best2k, height: 30) }
            targets(size: 24, spacing: 20)
            profileHint
            Text(suggestion.reason)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                goButton(height: 58, font: 24)
                chooseButton(title: "Andere Wahl", height: 58)
            }
            alternativesRow
        }
        .padding(20)
        .padding(.top, 150)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                Theme.card
                if let course {
                    // Luftbild oben, Route rechts oben; nach unten in die Kartenfarbe auslaufend
                    CourseMapPreview(course: course,
                                     trackInsets: EdgeInsets(top: 20, leading: 130, bottom: 70, trailing: 20),
                                     coverWithImage: true, showsMarkers: false)
                        .frame(height: 300)
                        .overlay {
                            LinearGradient(stops: [.init(color: .black.opacity(0.05), location: 0),
                                                   .init(color: .black.opacity(0.45), location: 0.45),
                                                   .init(color: Theme.card, location: 1)],
                                           startPoint: .top, endPoint: .bottom)
                        }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.cardStroke))
    }

    // MARK: Bausteine

    @ViewBuilder
    private func targets(size: CGFloat, spacing: CGFloat) -> some View {
        if let plan {
            let t = PlanTargetSummary(plan: plan, best2k: best2k)
            // Zahlen nie abschneiden: nebeneinander, sonst Tempo über Schlagzahl und Puls, sonst untereinander
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: spacing) {
                    paceTarget(t, size: size); strokeTarget(t, size: size); zoneTarget(t, size: size)
                }
                VStack(alignment: .leading, spacing: 10) {
                    paceTarget(t, size: size)
                    HStack(alignment: .top, spacing: spacing) { strokeTarget(t, size: size); zoneTarget(t, size: size) }
                }
                VStack(alignment: .leading, spacing: 10) {
                    paceTarget(t, size: size); strokeTarget(t, size: size); zoneTarget(t, size: size)
                }
            }
        }
    }

    /// Ohne Verlauf kein Tempo; mit Standard-Bestzeit „ca.“ in der Überschrift
    @ViewBuilder
    private func paceTarget(_ t: PlanTargetSummary, size: CGFloat) -> some View {
        if !isNewUser, let pace = t.pace {
            TargetValue(title: ProfileState.best2kIsDefault ? "Tempo ca." : "Tempo",
                        value: PlanFormat.paceRange(pace), unit: "/500 m", size: size)
        }
    }

    @ViewBuilder
    private func strokeTarget(_ t: PlanTargetSummary, size: CGFloat) -> some View {
        if let spm = t.strokeRate {
            TargetValue(title: "Schlagzahl",
                        value: spm.lowerBound == spm.upperBound ? "\(spm.lowerBound)"
                            : "\(spm.lowerBound)–\(spm.upperBound)",
                        unit: "/min", size: size)
        }
    }

    @ViewBuilder
    private func zoneTarget(_ t: PlanTargetSummary, size: CGFloat) -> some View {
        if let z = t.zone {
            TargetValue(title: "Puls", value: "Zone \(z)", unit: nil, size: size)
        }
    }

    @ViewBuilder
    private var profileHint: some View {
        if profileIsDefault {
            Button(action: onProfile) {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                    Text("Zonen und Tempo geschätzt – Profil prüfen")
                        .underline()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                }
                .font(.system(size: compact ? 14 : 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
    }

    private func reasonBox(size: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Capsule().fill(Theme.evening).frame(width: 4)
            Text(suggestion.reason)
                .font(.system(size: size))
                .foregroundStyle(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .fixedSize(horizontal: false, vertical: true)
    }

    private func goButton(height: CGFloat, font: CGFloat) -> some View {
        Button { onStart(mainOption) } label: {
            HStack(spacing: 14) {
                Image(systemName: "play.fill")
                Text("Los")
            }
            .font(.system(size: font, weight: .bold))
            .foregroundStyle(Color.black.opacity(0.85))
            .frame(maxWidth: compact ? .infinity : 240, minHeight: height)
            .background(Theme.evening, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Los: \(plan?.name ?? "Frei rudern") auf \(course?.title ?? "der Strecke") starten")
    }

    private func chooseButton(title: String, height: CGFloat) -> some View {
        Button(action: onChoose) {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2")
                Text(title).lineLimit(1).fixedSize()
            }
            .font(.system(size: compact ? 19 : 24, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 18 : 28)
            .frame(minHeight: height)
            .background(Color.white.opacity(0.10), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.25)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Strecke oder Programm selbst wählen")
    }

    private var alternativesRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                Text("Oder:").foregroundStyle(.white.opacity(0.65))
                chips
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Oder:").foregroundStyle(.white.opacity(0.65))
                chips
            }
        }
        .font(.system(size: compact ? 15 : 17, weight: .medium))
    }

    @ViewBuilder
    private var chips: some View {
        ForEach(suggestion.alternatives, id: \.self) { option in
            Button { onStart(option) } label: {
                Text(HomeFormat.optionTitle(option, courses: courses))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, compact ? 8 : 10)
                    .background(Color.white.opacity(0.08), in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.18)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

/// Zielwert auf der Vorschlagskarte: kleine Überschrift, grosse Zahl, Einheit
struct TargetValue: View {
    let title: String
    let value: String
    let unit: String?
    var size: CGFloat = 34

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 13, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.65))
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(Theme.number(size, weight: .bold))
                    .lineLimit(1)
                    .fixedSize()
                if let unit {
                    Text(unit).font(.system(size: 15)).foregroundStyle(.white.opacity(0.7)).fixedSize()
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
