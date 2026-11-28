import SwiftUI
import SwiftData
import UIKit
import RowCoachKit

// Ansichten der Motivationsfunktionen (docs/motivation/UMSETZUNG.md). Logik in RowCoachKit (Motivation/…), hier nur
// Darstellung: Einstellungen → Motivation, „Was heute gut war“ in der Auswertung, eine ruhige Zeile auf der
// Startseite, Bestmarken und Meilensteine, „Gegen meine Bestfahrt“ auf der Streckenseite.

// MARK: - Einstellungen → Motivation

/// Abschnitt „Motivation“ in den Einstellungen: Erfolgszeilen, Meilensteine, „Wann ruderst du?“, Wochenziel und Pause
struct MotivationSettingsSection: View {
    @AppStorage(MotivationSettings.successLinesKey) private var successLines = true
    @AppStorage(MotivationSettings.milestonesKey) private var milestones = true
    @AppStorage(MotivationSettings.goalKindKey) private var goalKind = WeeklyGoal.Kind.rides.rawValue
    @AppStorage(HomeSettings.weeklyGoalKey) private var rides = HomeSettings.defaultWeeklyGoal
    @AppStorage(MotivationSettings.goalMinutesKey) private var minutes = MotivationSettings.defaultGoalMinutes
    @AppStorage(MotivationSettings.intentionKey) private var intentionData: Data?
    @AppStorage(MotivationSettings.pausesKey) private var pausesData: Data?

    private var goalValue: String {
        _ = (goalKind, rides, minutes, pausesData)
        let g = MotivationSettings.goal
        if let p = MotivationSettings.pauses.active(at: Date()) {
            let day = p.end.formatted(.dateTime.day().month(.abbreviated))
            return String(localized: "Pause bis \(day)")
        }
        return g.title
    }

    private var intentionValue: String {
        _ = intentionData
        guard let i = MotivationSettings.intention else { return String(localized: "Aus") }
        if i.days.isEmpty && !i.usePlanDays { return String(localized: "Aus") }
        return i.remindersOn ? String(localized: "Mit Erinnerung") : String(localized: "Ohne Erinnerung")
    }

    var body: some View {
        Section {
            Toggle("Was heute gut war", isOn: $successLines)
            Toggle("Meilensteine", isOn: $milestones)
            NavigationLink { RowingIntentionView() } label: {
                LabeledContent("Wann ruderst du?", value: intentionValue)
            }
            NavigationLink { WeeklyGoalSettingsView() } label: {
                LabeledContent("Wochenziel", value: goalValue)
            }
        } header: {
            Text("Motivation")
        } footer: {
            Text("„Was heute gut war“: bis zu drei wahre Zeilen nach jeder Fahrt und ein Satz vom Coach. Alles bleibt auf diesem Gerät, ohne Konto. Bei Erholungsbedarf schweigen Bestfahrt-Angebote und Meilenstein-Hinweise.")
        }
    }
}

/// Wochenziel (Fahrten oder Minuten) und Pause für Krankheit oder Ferien
struct WeeklyGoalSettingsView: View {
    @AppStorage(MotivationSettings.goalKindKey) private var goalKind = WeeklyGoal.Kind.rides.rawValue
    @AppStorage(HomeSettings.weeklyGoalKey) private var rides = HomeSettings.defaultWeeklyGoal
    @AppStorage(MotivationSettings.goalMinutesKey) private var minutes = MotivationSettings.defaultGoalMinutes
    @AppStorage(MotivationSettings.pausesKey) private var pausesData: Data?
    @State private var pauseDays = 7
    @State private var reason = GoalPause.Reason.ill

    private var activePause: GoalPause? {
        _ = pausesData
        return MotivationSettings.pauses.active(at: Date())
    }

    var body: some View {
        Form {
            Section {
                Picker("Ziel in", selection: $goalKind) {
                    Text("Fahrten").tag(WeeklyGoal.Kind.rides.rawValue)
                    Text("Minuten").tag(WeeklyGoal.Kind.minutes.rawValue)
                }
                .pickerStyle(.segmented)
                if goalKind == WeeklyGoal.Kind.minutes.rawValue {
                    Stepper("\(minutes) min pro Woche", value: $minutes,
                            in: WeeklyGoal.minuteRange, step: WeeklyGoal.minuteStep)
                } else {
                    Stepper("\(rides) Fahrten pro Woche", value: $rides, in: WeeklyGoal.rideRange)
                }
            } header: {
                Text("Wochenziel")
            } footer: {
                Text("Eine Woche zählt für die Serie, wenn das Ziel erreicht ist; ein Joker überbrückt eine Woche. Ruhetage gehören zum Training, deshalb höchstens 6 Fahrten. Nach einigen Wochen schlägt die App vor, das Ziel anzupassen.")
            }
            Section {
                if let p = activePause {
                    LabeledContent("Pause bis", value: p.end.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    LabeledContent("Grund", value: p.reason.title)
                    Button("Pause beenden") { endPause(p) }
                        .foregroundStyle(Theme.link)
                } else {
                    Picker("Grund", selection: $reason) {
                        ForEach(GoalPause.Reason.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Stepper(pauseDays == 1 ? String(localized: "1 Tag") : String(localized: "\(Int(pauseDays)) Tage"),
                            value: $pauseDays, in: 1...GoalPause.maxDays)
                    Button("Pause ab heute") { startPause() }
                        .foregroundStyle(Theme.link)
                }
            } header: {
                Text("Pause")
            } footer: {
                Text("Krank oder in den Ferien: Serie und Wochenziel ruhen, der Joker bleibt. In der Pause gibt es keine Erinnerungen. Höchstens 4 Wochen.")
            }
        }
        .scrollContentBackground(.hidden)
        .dsPageBackground()
        .navigationTitle(Text("Wochenziel"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // ältere Einstellung bis 7 Fahrten: höchstens 6
            if rides > WeeklyGoal.rideRange.upperBound { rides = WeeklyGoal.rideRange.upperBound }
        }
        .onChange(of: goalKind) { _, _ in MotivationSettings.markGoalChanged() }
        .onChange(of: rides) { _, _ in MotivationSettings.markGoalChanged() }
        .onChange(of: minutes) { _, _ in MotivationSettings.markGoalChanged() }
    }

    private func startPause() {
        var list = MotivationSettings.pauses
        list.append(GoalPause(start: Date(), days: pauseDays, reason: reason))
        MotivationSettings.pauses = list
    }

    private func endPause(_ p: GoalPause) {
        var list = MotivationSettings.pauses.filter { $0.id != p.id }
        if let ended = p.ended(at: Date()) { list.append(ended) }
        MotivationSettings.pauses = list
    }
}

/// „Wann ruderst du?“: Tage, Uhrzeit, Anlass, Hindernisplan und (optional) Erinnerung
struct RowingIntentionView: View {
    @Environment(ProgramStore.self) private var programs
    @Environment(\.openURL) private var openURL
    @State private var intention = MotivationSettings.intention ?? RowingIntention()
    @State private var denied = false

    private var planDays: [Weekday]? {
        guard let a = programs.active, !a.isFinished else { return nil }
        return a.weekdays
    }

    private var usesPlan: Bool { intention.usePlanDays && planDays != nil }

    private var time: Binding<Date> {
        Binding(get: {
            Calendar.current.date(bySettingHour: intention.hour, minute: intention.minute, second: 0, of: Date()) ?? Date()
        }, set: { d in
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            intention.hour = c.hour ?? intention.hour
            intention.minute = c.minute ?? intention.minute
        })
    }

    private var reminders: Binding<Bool> {
        Binding(get: { intention.remindersOn }, set: { on in
            guard on else {
                intention.remindersOn = false
                Task { await ReminderService.shared.removeAll() }
                return
            }
            // Berechtigung erst jetzt erfragen
            Task {
                let ok = await ReminderService.shared.requestPermission()
                denied = !ok
                intention.remindersOn = ok
            }
        })
    }

    var body: some View {
        Form {
            Section {
                if let planDays {
                    Toggle("Tage aus dem Trainingsplan", isOn: $intention.usePlanDays)
                    if intention.usePlanDays {
                        LabeledContent("Tage", value: planDays.map(\.shortLabel).joined(separator: ", "))
                    }
                }
                if !usesPlan { dayPicker }
                Picker("Anlass", selection: $intention.cue) {
                    ForEach(RowingIntention.Cue.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                DatePicker("Uhrzeit", selection: time, displayedComponents: .hourAndMinute)
                Toggle("Wenn ich müde bin: kurz und locker", isOn: $intention.obstaclePlan)
            } header: {
                Text("Dein Plan")
            } footer: {
                Text("Wer Tag, Zeit und Anlass festlegt, bleibt nachweislich eher dran („Wenn es Dienstag nach der Arbeit ist, rudere ich“). Die Tage nutzt die App auch für den sanften Wiedereinstieg: Fällt ein Tag aus, schlägt sie am nächsten eine kurze Einheit vor.")
            }
            Section {
                Toggle("Erinnerung", isOn: reminders)
                if denied {
                    Text("Mitteilungen sind für RowCoach nicht erlaubt.").foregroundStyle(Theme.warn)
                    Button("Einstellungen öffnen") {
                        if let u = URL(string: UIApplication.openSettingsURLString) { openURL(u) }
                    }
                    .foregroundStyle(Theme.link)
                }
            } footer: {
                Text("Höchstens eine Mitteilung am Tag, nur an deinen Tagen, nie an Ruhetagen laut Plan und nie in einer Pause. Nach zwei unbeachteten Erinnerungen eine Woche Ruhe. Standardmässig aus.")
            }
        }
        .scrollContentBackground(.hidden)
        .dsPageBackground()
        .navigationTitle(Text("Wann ruderst du?"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: intention) { _, new in MotivationSettings.intention = new }
        .onChange(of: intention.cue) { _, cue in
            intention.hour = cue.defaultHour
            intention.minute = 0
        }
    }

    private var dayPicker: some View {
        HStack(spacing: 6) {
            ForEach(Weekday.allCases) { day in
                let on = intention.days.contains(day)
                Button {
                    if on { intention.days.remove(day) } else { intention.days.insert(day) }
                } label: {
                    Text(day.shortLabel)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .foregroundStyle(on ? Theme.onBrand : Theme.text)
                        .background(on ? Theme.brand : Color.white.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(day.label))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Auswertung: „Was heute gut war“

/// Oben in der Auswertung: 1–3 wahre Zeilen, darunter ruhig ein erreichter Meilenstein. Direkt nach der Fahrt spricht
/// der Coach einmal einen Satz (`post_ride`), wenn Ansagen und Coach an sind.
struct RideHighlightsCard: View {
    let record: WorkoutRecord
    /// direkt nach der Fahrt (nicht im Verlauf)
    let live: Bool

    @Environment(HomeModel.self) private var home
    @AppStorage(MotivationSettings.successLinesKey) private var successLines = true
    @State private var lines: [RideHighlight] = []
    @State private var milestones: [Milestone] = []

    /// Fahrten, zu denen der Coach-Satz schon gesprochen wurde (die Auswertung wird mehrmals aufgebaut)
    @MainActor private static var spoken = Set<UUID>()

    var body: some View {
        Group {
            if successLines && !lines.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Text("Was heute gut war").dsLabelStyle()
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Label {
                            Text(line.text).font(.headline).fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: icon(line.kind)).foregroundStyle(Theme.accent)
                        }
                    }
                    ForEach(milestones) { m in
                        HStack(alignment: .top, spacing: DS.Space.s) {
                            Image(systemName: "flag.checkered").foregroundStyle(Theme.warn)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.title).font(.subheadline.weight(.semibold))
                                Text(m.detail).font(.footnote).foregroundStyle(Theme.text2)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .dsCard(padding: DS.Space.m, cornerRadius: DS.Radius.tile)
                .accessibilityElement(children: .combine)
            }
        }
        .task(id: record.id) {
            guard successLines else { return }
            let result = await home.highlights(for: record)
            lines = result.lines
            milestones = result.milestones
            if live { await speak() }
        }
    }

    private func icon(_ kind: RideHighlight.Kind) -> String {
        switch kind {
        case .courseBest, .personalRecord: return "trophy"
        case .milestone: return "flag.checkered"
        case .fastestInterval, .steadyIntervals: return "metronome"
        case .comeback: return "arrow.uturn.backward"
        case .heartRateLower: return "heart"
        case .weeklyGoal: return "star"
        case .zoneHeld, .restRule: return "leaf"
        case .effort, .presence: return "hand.thumbsup"
        }
    }

    /// Coach-Satz einmal je Fahrt, nach einer laufenden Ansage (z. B. „Training geschafft“)
    private func speak() async {
        guard !Self.spoken.contains(record.id), TrainingSettings.spokenCues, TrainingSettings.coachStyle != .off,
              let bank = CoachPhrases.bank else { return }
        Self.spoken.insert(record.id)
        let language = AppLanguage.code == "de" ? "de" : "en"
        guard let phrase = PostRideCoach.phrase(highlights: lines, bank: bank, style: TrainingSettings.coachStyle,
                                                language: language,
                                                seed: UInt64(max(record.header.startDate.timeIntervalSince1970, 0)))
        else { return }
        for _ in 0..<12 where SpeechCoach.shared.isSpeaking {
            try? await Task.sleep(for: .milliseconds(500))
        }
        try? await Task.sleep(for: .milliseconds(600))
        SpeechCoach.shared.say(phrase.text, phraseId: phrase.isDynamic ? nil : phrase.phraseId, language: language,
                               priority: CoachCategory.praise.priority.value, interrupting: false)
    }
}

// MARK: - Startseite

/// Eine ruhige Zeile unter dem Vorschlag: Ruhetag-Lob, Vorschlag zum Wochenziel (mit „Ja“/„Passt so“),
/// „Heute nach der Arbeit“ oder ein naher Meilenstein. Nichts, wenn es nichts zu sagen gibt.
struct HomeMotivationLine: View {
    let motivation: HomeMotivation?
    var compact = false
    @State private var hiddenReview = false

    var body: some View {
        if let line = motivation?.line {
            switch line {
            case .restPraise(let text):
                row("leaf", text)
            case .intention(let text):
                row("calendar.badge.clock", text)
            case .milestone(let m):
                row("flag", m.text)
            case .goalReview(let review):
                if !hiddenReview { reviewRow(review) }
            }
        }
    }

    private func row(_ icon: String, _ text: String) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon).foregroundStyle(Theme.link)
        }
        .font(compact ? .subheadline : .body)
        .foregroundStyle(Theme.text)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, compact ? 14 : 18)
        .padding(.vertical, compact ? 10 : 12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func reviewRow(_ review: GoalReview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(review.text).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "slider.horizontal.3").foregroundStyle(Theme.link)
            }
            HStack(spacing: 12) {
                Button("Ja, anpassen") {
                    MotivationSettings.setGoal(review.proposed)
                    hiddenReview = true
                }
                .buttonStyle(SecondaryButtonStyle(compact: true, fullWidth: false))
                Button("Passt so") {
                    MotivationSettings.dismissReview()
                    hiddenReview = true
                }
                .foregroundStyle(Theme.link)
                .buttonStyle(.borderless)
            }
        }
        .font(compact ? .subheadline : .body)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, compact ? 14 : 18)
        .padding(.vertical, compact ? 10 : 12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Bestmarken und Meilensteine

/// Persönliche Rekorde je Distanz und Zeit (auch als Teilstücke) und erreichte Meilensteine (Verlauf)
struct RecordsView: View {
    @Environment(HomeModel.self) private var home
    @AppStorage(MotivationSettings.milestonesKey) private var milestonesOn = true

    var body: some View {
        List {
            Section {
                let records = home.records
                if records.isEmpty {
                    Text("Bestmarken erscheinen nach den ersten Fahrten.").foregroundStyle(Theme.text2)
                }
                ForEach(EffortTarget.standard, id: \.self) { target in
                    if let r = records[target] {
                        LabeledContent {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(target.formatted(r.value)).font(.body.monospacedDigit().weight(.semibold))
                                Text(r.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption).foregroundStyle(Theme.text2)
                            }
                        } label: {
                            Text(target.title)
                        }
                    }
                }
            } header: {
                Text("Bestmarken")
            } footer: {
                Text("Schnellste Zeit je Distanz bzw. weiteste Strecke je Zeit, auch als Teilstück einer längeren Fahrt. Pausen zählen mit, Simulatorfahrten nie.")
            }
            .listRowBackground(Theme.card)
            if milestonesOn {
                Section {
                    if home.milestones.isEmpty {
                        Text("Noch kein Meilenstein – der erste kommt nach zehn Fahrten oder 100 km.")
                            .foregroundStyle(Theme.text2)
                    }
                    ForEach(home.milestones.reversed()) { m in
                        LabeledContent(m.title, value: m.reachedAt.formatted(date: .abbreviated, time: .omitted))
                    }
                } header: {
                    Text("Meilensteine")
                }
                .listRowBackground(Theme.card)
            }
        }
        .scrollContentBackground(.hidden)
        .dsPageBackground()
        .navigationTitle(Text("Bestmarken"))
    }
}

// MARK: - Streckenseite: „Gegen meine Bestfahrt“

/// Taste auf der Streckenseite: Rennen gegen die eigene beste ganze Fahrt auf dieser Strecke (Geisterboot). Nur mit
/// einer vollständigen freien Fahrt und nie, solange der Erholungs-Wächter Erholung empfiehlt.
struct GhostRaceButton: View {
    let course: Course
    let model: HomeModel

    @Environment(\.rowingLaunch) private var launch
    @Environment(\.modelContext) private var context

    private var best: TrainingSession? {
        _ = model.stats
        let sessions = model.sessions(courseId: course.id, title: course.title)
        guard let key = sessions.first?.courseKey else { return nil }
        return PersonalRecords.bestCourseRun(sessions, courseKey: key)
    }

    var body: some View {
        if model.motivation?.recovery.silencesChallenges != true, let best {
            Button { start(best.id) } label: {
                Label("Gegen meine Bestfahrt (\(Format.duration(best.activeDuration)))", systemImage: "figure.rower")
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .buttonStyle(SecondaryButtonStyle(compact: true))
        }
    }

    private func start(_ id: UUID) {
        var d = FetchDescriptor<StoredWorkout>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        guard let record = (try? context.fetch(d))?.first?.record else { return }
        launch?.startGhost?(course.id, record)
    }
}

extension RowingView {
    /// Rennen gegen die eigene Bestfahrt: Geisterboot aus der Zeitreihe (ab dem ersten Schlag), Ziel = Länge der
    /// Strecke, Start mit dem ersten eigenen Schlag. Ohne Netz (GhostRaceTransport).
    static func ghostRace(course: Course, record: WorkoutRecord) -> RaceLink {
        let length = course.turns > 0 ? 2 * course.oneWayM : course.oneWayM
        let race = Race(id: "ghost-\(UUID().uuidString.prefix(8))", courseId: course.id, target: .distance(length),
                        lanes: 2)
        let profile = RowerProfileStore.shared
        let me = RaceParticipant(id: "me", displayName: profile.displayName, lane: 2, appearance: profile.appearance)
        let ghost = GhostRower(participant: RaceParticipant(id: "ghost-best", displayName: String(localized: "Bestfahrt"),
                                                            lane: 1, source: .ghost, appearance: profile.appearance),
                               samples: PersonalRecords.ghostSamples(record.samples), finishDistance: length)
        let mark = RaceStartMark()
        let transport = GhostRaceTransport(ghosts: [ghost]) { mark.raceTime(local: Date().timeIntervalSince1970) }
        return RaceLink(coordinator: RaceCoordinator(race: race, me: me), transports: [transport], start: mark)
    }
}
