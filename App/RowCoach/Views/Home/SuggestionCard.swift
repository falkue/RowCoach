import SwiftUI
import RowCoachKit

/// Texte für den Startbildschirm
enum HomeFormat {
    /// „4 km“ bzw. „3,1 km“ im Format der Sprache
    static func km(_ meters: Double) -> String { DSFormat.km(meters) }

    /// „24 km“ ab 10 km ohne Nachkommastelle, sonst „6,2 km“
    static func kmShort(_ meters: Double) -> String { DSFormat.kmShort(meters) }

    static func minutes(_ m: Double) -> String { Int(m.rounded()).formatted() }

    /// Kalender in der Sprache und Zeitzone des Geräts (Woche ab Montag wie im Training)
    private static func localCalendar(_ calendar: Calendar) -> Calendar {
        var c = calendar
        c.locale = .current
        return c
    }

    /// „Heute, 11:27“, „Gestern, 11:27“, „Montag, 11:27“ (letzte 6 Tage), sonst „12. Nov., 11:27“ – in der Sprache
    /// des Geräts
    static func relativeDate(_ date: Date, now: Date = Date(), calendar: Calendar = TrainingCalendar.swiss()) -> String {
        let cal = localCalendar(calendar)
        let t = date.formatted(.dateTime.hour().minute())
        if cal.isDate(date, inSameDayAs: now) { return String(localized: "Heute, \(t)") }
        if let y = cal.date(byAdding: .day, value: -1, to: now), cal.isDate(date, inSameDayAs: y) {
            return String(localized: "Gestern, \(t)")
        }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: now)).day ?? 99
        let day = days < 7 && days > 0 ? date.formatted(.dateTime.weekday(.wide))
            : date.formatted(.dateTime.day().month(.abbreviated))
        return "\(day), \(t)"
    }

    /// „Heute“, „Gestern“, „Montag“ (letzte 6 Tage), sonst „12. Nov.“
    static func relativeDay(_ date: Date, now: Date = Date(), calendar: Calendar = TrainingCalendar.swiss()) -> String {
        let cal = localCalendar(calendar)
        if cal.isDate(date, inSameDayAs: now) { return String(localized: "Heute") }
        if let y = cal.date(byAdding: .day, value: -1, to: now), cal.isDate(date, inSameDayAs: y) {
            return String(localized: "Gestern")
        }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: now)).day ?? 99
        return days < 7 && days > 0 ? date.formatted(.dateTime.weekday(.wide))
            : date.formatted(.dateTime.day().month(.abbreviated))
    }

    /// „Stein am Rhein · 32 min“ (Kurzname der Strecke und Dauer)
    static func shortPlanLine(plan: WorkoutPlan?, course: Course?, best2k: Double) -> String {
        var parts: [String] = []
        if let course { parts.append(courseShort(course.title)) }
        if let plan {
            parts.append(PlanFormat.planLength(plan, best2k: best2k))
        } else if let course {
            parts.append(DSFormat.courseLength(course))
        }
        return parts.joined(separator: " · ")
    }

    /// Kurzname der Strecke: Teil vor „ – “ („Utoquai – Seefeld“ → „Utoquai“)
    /// Kurzname einer Strecke in der Sprache der App (Teil vor „ – “); nimmt den deutschen Titel aus course.json
    /// bzw. den gespeicherten Titel einer Fahrt
    static func courseShort(_ title: String) -> String {
        let t = CourseText.localized(title)
        return t.components(separatedBy: " – ").first ?? t
    }

    /// Titel einer Wahl („Lockere Grundlage 30 min“, „Frei rudern · Utoquai“)
    static func optionTitle(_ option: DailySuggestion.Option, courses: [Course]) -> String {
        switch option {
        case .plan(let id, _):
            return PlanLibrary.plan(id: id)?.shortName ?? id
        case .free(let courseId):
            if let c = courses.first(where: { $0.id == courseId }) { return String(localized: "Frei rudern · \(courseShort(c.title))") }
            return String(localized: "Frei rudern")
        }
    }

    /// „Rhein Basel – Rheinweg Kleinbasel · 32 min · Intervalle“
    static func planLine(plan: WorkoutPlan?, course: Course?, best2k: Double) -> String {
        var parts: [String] = []
        if let course { parts.append(course.titleText) }
        if let plan {
            parts.append(PlanFormat.planLength(plan, best2k: best2k))
            if !plan.category.isEmpty { parts.append(plan.category) }
        } else if let course {
            parts.append(DSFormat.courseLength(course))
        }
        return parts.joined(separator: " · ")
    }
}


/// Hauptaktion des Startbildschirms (Variante C „ruhig“, docs/design/startscreen-ux-review.md): Luftbild mit Route,
/// Kicker, Programm einzeilig, „Strecke · Dauer“, Phasenleiste ohne Beschriftung, Begründung in einem Satz, „Los“
/// und „Anders wählen“. Zielwerte und Phasen zeigt die Vorschau beim Tippen auf die Karte.
struct SuggestionCard: View {
    let suggestion: DailySuggestion
    let course: Course?
    /// noch keine Fahrt im Verlauf
    let isNewUser: Bool
    /// Strecke noch nie gefahren → Hinweis „Neu für deinen Seen-Pass“
    let isNewCourse: Bool
    let best2k: Double
    var layout: Layout = .landscape
    let onStart: (DailySuggestion.Option) -> Void
    let onChoose: () -> Void
    let onPreview: () -> Void

    enum Layout { case landscape, portrait, phone }

    private var plan: WorkoutPlan? { PlanLibrary.plan(id: suggestion.planId) }
    private var mainOption: DailySuggestion.Option {
        plan == nil ? .free(courseId: course?.id) : suggestion.option
    }
    private var phone: Bool { layout == .phone }

    private var kicker: String {
        // Trainingsplan: „Heute laut Plan“ bzw. „Ruhetag laut Plan“ (Woche und Einheit stehen in der Begründung)
        if let p = suggestion.program {
            switch (suggestion.rule, suggestion.doneToday) {
            case (.planRest, false): return String(localized: "Ruhetag laut Plan")
            case (.planRest, true): return String(localized: "Heute erledigt · morgen Ruhetag laut Plan")
            case (.plan, false): return p.isEvent ? String(localized: "Heute: Ziel deines Plans") : String(localized: "Heute laut Plan")
            case (.plan, true): return String(localized: "Heute erledigt · morgen laut Plan")
            default: break
            }
        }
        if suggestion.doneToday { return String(localized: "Heute erledigt · Vorschlag für morgen") }
        if isNewUser { return String(localized: "Erste Fahrt") }
        return String(localized: "Vorschlag für heute")
    }

    /// Titel: Programmname ohne Schema in Ziffern („Zeit-Pyramide 1-2-3-4-3-2-1“ → „Zeit-Pyramide“), das zeigt die
    /// Phasenleiste
    private var title: String {
        guard let plan else { return String(localized: "Frei rudern") }
        var words = plan.shortName.split(separator: " ").map(String.init)
        if let last = words.last, words.count > 1, last.allSatisfy({ $0.isNumber || $0 == "-" }), last.contains("-") {
            words.removeLast()
        }
        // Dauer steht in der Zeile darunter („Lockere Grundlage 30 min“ → „Lockere Grundlage“)
        if words.count > 2, words.last == "min", Int(words[words.count - 2]) != nil {
            words.removeLast(2)
        }
        return words.joined(separator: " ")
    }

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .bottomLeading) {
                background(g.size)
                content
                    .padding(phone ? 22 : 40)
            }
            .overlay(alignment: .topTrailing) {
                if isNewCourse && course != nil {
                    Label("Neu für deinen Seen-Pass", systemImage: "scope")
                        .font(.system(size: phone ? 15 : 18, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(.ultraThinMaterial, in: Capsule())
                        .environment(\.colorScheme, .dark)
                        .padding(phone ? 16 : 28)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: phone ? 24 : 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: phone ? 24 : 30, style: .continuous).stroke(Theme.cardStroke))
        .contentShape(RoundedRectangle(cornerRadius: phone ? 24 : 30, style: .continuous))
        .onTapGesture(perform: onPreview)
        .accessibilityAction(named: "Vorschau mit Zielwerten", onPreview)
    }

    /// Ungefähre Höhe des Textblocks unten; die Route bleibt darüber bzw. rechts davon
    private var textHeight: CGFloat {
        switch layout {
        case .landscape: return 470
        case .portrait: return 400
        case .phone: return 330
        }
    }

    @ViewBuilder
    private func background(_ size: CGSize) -> some View {
        ZStack {
            Theme.card
            if let course {
                // Route nie unter dem Text: oben über dem Textblock, quer zusätzlich rechts
                let insets = EdgeInsets(top: phone ? 64 : 90,
                                        leading: layout == .landscape ? size.width * 0.38 : 30,
                                        bottom: min(textHeight, size.height * 0.62),
                                        trailing: phone ? 24 : 40)
                CourseMapPreview(course: course, trackInsets: insets, coverWithImage: true, showsMarkers: false)
            }
            LinearGradient(stops: [.init(color: .black.opacity(0.10), location: 0),
                                   .init(color: .black.opacity(0.25), location: 0.35),
                                   .init(color: .black.opacity(0.80), location: 0.75),
                                   .init(color: .black.opacity(0.90), location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: phone ? 12 : 18) {
            Text(kicker.uppercased())
                .font(.system(size: phone ? 14 : 16, weight: .bold))
                .tracking(2.5)
                .foregroundStyle(Theme.evening)
            Text(title)
                .font(.system(size: phone ? 40 : 60, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(HomeFormat.shortPlanLine(plan: plan, course: course, best2k: best2k))
                .font(.system(size: phone ? 19 : 24, weight: .medium))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let plan {
                PhaseBar(plan: plan, best2k: best2k, height: phone ? 30 : 44)
                    .frame(maxWidth: 620)
            }
            Text(suggestion.reason)
                .font(.system(size: phone ? 16 : 19))
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 620, alignment: .leading)
            HStack(spacing: phone ? 12 : 20) {
                Button { onStart(mainOption) } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "play.fill")
                        Text("Los")
                    }
                    .font(.system(size: phone ? 26 : 34, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.85))
                    .frame(maxWidth: phone ? .infinity : 280, minHeight: phone ? 64 : 88)
                    .background(Theme.evening, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Los: \(plan?.name ?? String(localized: "Frei rudern")) auf \(course?.titleText ?? String(localized: "der Strecke"))"))
                Button(action: onChoose) {
                    (phone ? Text("Andere Wahl") : Text("Anders wählen"))
                        .font(.system(size: phone ? 19 : 24, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, phone ? 20 : 36)
                        .frame(minHeight: phone ? 64 : 88)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.22)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .environment(\.colorScheme, .dark)
                .accessibilityHint("Strecke, freies Rudern oder anderes Training wählen")
            }
            .padding(.top, phone ? 4 : 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Vorschau beim Tippen auf die Vorschlagskarte: Programm mit Zielwerten und Phasen, Begründung, Hinweis (ⓘ) und
/// „Los“.
struct SuggestionPreviewSheet: View {
    let suggestion: DailySuggestion
    let course: Course?
    let best2k: Double
    let onStart: (DailySuggestion.Option) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showInfo = false

    private var plan: WorkoutPlan? { PlanLibrary.plan(id: suggestion.planId) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let course {
                        CourseMapPreview(course: course, coverWithImage: true)
                            .frame(height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(plan?.shortName ?? String(localized: "Frei rudern")).font(.system(size: 32, weight: .bold))
                        Text(HomeFormat.planLine(plan: plan, course: course, best2k: best2k))
                            .font(.system(size: 18)).foregroundStyle(Theme.secondaryText)
                    }
                    if let plan {
                        PhaseBar(plan: plan, best2k: best2k, height: 40)
                        targets(plan)
                    }
                    HStack(alignment: .top, spacing: 10) {
                        Text(suggestion.reason).font(.system(size: 18))
                        Spacer(minLength: 0)
                        Button { showInfo.toggle() } label: {
                            Image(systemName: "info.circle").font(.system(size: 20))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Wie der Vorschlag entsteht")
                    }
                    if showInfo && suggestion.program != nil {
                        Text("Vorschlag aus deinem Trainingsplan. Nach einer harten Einheit vor weniger als 48 Stunden schlägt die App locker vor und verschiebt die geplante Einheit. Wählst du eine Alternative, rückt die geplante Einheit wenn möglich auf einen späteren Tag.")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if showInfo {
                        Text("Vorschlag aus deinen letzten Fahrten: nach harten Einheiten locker, insgesamt etwa 80 % leicht, harte Programme im Wechsel. Fühlst du dich anders, wähle frei.")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let plan {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Phasen").font(.system(size: 20, weight: .semibold)).padding(.bottom, 6)
                            ForEach(Array(plan.phases.enumerated()), id: \.offset) { i, p in
                                PhaseRow(number: i + 1, phase: p, best2k: best2k, workNumber: plan.workNumber(at: i),
                                         workCount: plan.workCount)
                                if i + 1 < plan.phases.count { Divider() }
                            }
                        }
                    }
                }
                .padding(24)
            }
            .safeAreaInset(edge: .bottom) {
                DSFooterBar {
                    Button {
                        dismiss()
                        onStart(plan == nil ? .free(courseId: course?.id) : suggestion.option)
                    } label: {
                        Label("Los", systemImage: "play.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle(compact: true))
                    .keyboardShortcut(.defaultAction)
                }
            }
            .dsSheetChrome(String(localized: "Vorschau")) { dismiss() }
        }
    }

    private func targets(_ plan: WorkoutPlan) -> some View {
        let t = PlanTargetSummary(plan: plan, best2k: best2k)
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 30) { targetItems(t) }
            VStack(alignment: .leading, spacing: 12) { targetItems(t) }
        }
    }

    @ViewBuilder
    private func targetItems(_ t: PlanTargetSummary) -> some View {
        if let pace = t.pace {
            TargetValue(title: ProfileState.best2kIsDefault ? String(localized: "Tempo ca.") : String(localized: "Tempo"),
                        value: PlanFormat.paceRange(pace), unit: "/500 m", size: 30)
        }
        if let spm = t.strokeRate {
            TargetValue(title: String(localized: "Schlagzahl"),
                        value: spm.lowerBound == spm.upperBound ? "\(spm.lowerBound)" : "\(spm.lowerBound)–\(spm.upperBound)",
                        unit: "/min", size: 30)
        }
        if let z = t.zone {
            TargetValue(title: String(localized: "Puls"), value: String(localized: "Zone \(z)"), unit: nil, size: 30)
        }
    }
}

/// Zielwert: kleine Überschrift, grosse Zahl (nie abgeschnitten), Einheit
struct TargetValue: View {
    let title: String
    let value: String
    let unit: String?
    var size: CGFloat = 34

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 14, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.65))
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value).font(Theme.number(size, weight: .bold)).lineLimit(1).fixedSize()
                if let unit {
                    Text(unit).font(.system(size: 15)).foregroundStyle(.white.opacity(0.7)).fixedSize()
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
