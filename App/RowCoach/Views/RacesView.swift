import SwiftUI
import os
import RowCoachKit

// Online-Rennen (docs/MULTIPLAYER.md „Umsetzung Firebase“): Liste kommender Rennen, Rennen erstellen, mit Code
// beitreten, Warteraum mit Teilnehmenden und Countdown, Start der Fahrt, Ergebnis. Erreichbar über „Rennen“ im Tab
// Strecken. Ohne Konto nur der Hinweis „Für Online-Rennen anmelden“ – dann geht keine Anfrage hinaus.

/// Was der Ruderbildschirm für ein Online-Rennen braucht
struct OnlineRaceLaunch: Equatable {
    let race: OnlineRace
    let entries: [OnlineRaceEntry]
}

// MARK: - Liste

struct RacesView: View {
    @Environment(AppRouter.self) private var router
    @State private var store = OnlineRaceStore.shared
    @State private var showCreate = false
    @State private var showCode = false
    @State private var code = ""
    @State private var codeError: String?

    var body: some View {
        List {
            switch store.access {
            case .unavailable:
                Section {
                    DSEmptyState(title: String(localized: "Kein Server eingerichtet"), systemImage: "icloud.slash",
                                 text: String(localized: "Diese Ausgabe der App hat keine Verbindung zu einem Server. Rennen gegen die eigene Bestfahrt gibt es auf jeder Streckenseite."))
                }
            case .needsAccount:
                Section {
                    DSEmptyState(title: String(localized: "Für Online-Rennen anmelden"), systemImage: "person.crop.circle.badge.plus",
                                 text: String(localized: "Online-Rennen brauchen ein Konto (mit bestätigter E-Mail). Ohne Konto funktioniert alles andere wie gewohnt – auch offline."),
                                 actionTitle: String(localized: "Anmelden"), action: { router.showSettings = true })
                }
            case .needsSubscription:
                Section {
                    DSEmptyState(title: String(localized: "Online-Rennen kommen bald"), systemImage: "flag.checkered",
                                 text: String(localized: "Rennen gegen andere gibt es mit dem Rennen-Abo, das bald startet."))
                }
            case .allowed:
                allowedContent
            }
        }
        .scrollContentBackground(.hidden)
        .dsPageBackground()
        .navigationTitle(Text("Rennen"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if store.access == .allowed {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showCreate = true } label: { Label("Rennen erstellen", systemImage: "plus") }
                        Button { code = ""; codeError = nil; showCode = true } label: {
                            Label("Mit Code beitreten", systemImage: "number")
                        }
                    } label: {
                        Label("Neu", systemImage: "plus.circle")
                    }
                }
            }
        }
        .refreshable { await store.refresh() }
        .task { await store.refresh() }
        .sheet(isPresented: $showCreate) {
            CreateRaceView { created in open(created) }
        }
        .alert("Mit Code beitreten", isPresented: $showCode) {
            TextField("Einladungscode", text: $code)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Button("Suchen") { Task { await join() } }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text(codeError ?? String(localized: "8 Zeichen, z. B. K7MP-2QXA"))
        }
    }

    @ViewBuilder
    private var allowedContent: some View {
        if let e = store.errorMessage {
            Section { Text(e).foregroundStyle(Theme.warn) }
        }
        if !store.mine.isEmpty {
            Section("Meine Rennen") {
                ForEach(store.mine) { r in row(r) }
            }
        }
        Section {
            if store.upcoming.isEmpty {
                Text(store.loading ? String(localized: "Lädt …") : String(localized: "Gerade sind keine öffentlichen Rennen geplant. Erstelle eins!"))
                    .foregroundStyle(Theme.text2)
            }
            ForEach(store.upcoming.filter { r in !store.mine.contains { $0.id == r.id } }) { r in row(r) }
        } header: {
            Text("Kommende Rennen")
        }
        Section {
            Button { showCreate = true } label: { Label("Rennen erstellen", systemImage: "plus") }
            Button { code = ""; codeError = nil; showCode = true } label: { Label("Mit Code beitreten", systemImage: "number") }
        }
    }

    private func row(_ r: OnlineRace) -> some View {
        NavigationLink(value: RowingRoute.race(r.id)) {
            RaceRow(race: r, serverNow: store.serverNow)
        }
    }

    private func open(_ r: OnlineRace) {
        store.cache(r)
        router.coursesPath.append(.race(r.id))
    }

    private func join() async {
        let c = RaceInviteCode.normalize(code)
        guard RaceInviteCode.isValid(c) else {
            codeError = String(localized: "Der Code hat 8 Zeichen.")
            showCode = true
            return
        }
        do {
            if let r = try await store.race(inviteCode: c) {
                open(r)
            } else {
                codeError = String(localized: "Kein Rennen mit diesem Code.")
                showCode = true
            }
        } catch {
            codeError = OnlineRaceStore.message(error)
            showCode = true
        }
    }
}

/// Zeile: Titel, Strecke, Ziel, Start
struct RaceRow: View {
    let race: OnlineRace
    let serverNow: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(race.title).font(.headline).lineLimit(1)
                if race.visibility == .invite {
                    Image(systemName: "lock.fill").font(.caption).foregroundStyle(Theme.text2)
                        .accessibilityLabel(Text("privat"))
                }
                Spacer()
                Text(RaceTexts.phase(race, serverNow: serverNow))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(race.phase(serverNow: serverNow) == .running ? Theme.accent : Theme.text2)
            }
            Text("\(RaceTexts.target(race.target)) · \(RaceTexts.start(race.startsAt))")
                .font(.subheadline)
                .foregroundStyle(Theme.text2)
        }
        .accessibilityElement(children: .combine)
    }
}

enum RaceTexts {
    static func target(_ t: RaceTarget) -> String {
        switch t {
        case .distance(let m): return m >= 1000 ? DSFormat.km(m) : "\(Int(m)) m"
        case .time(let s): return Format.duration(s)
        case .plan: return String(localized: "Programm")
        }
    }

    static func start(_ t: TimeInterval) -> String {
        Date(timeIntervalSince1970: t).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
    }

    static func phase(_ r: OnlineRace, serverNow: TimeInterval) -> String {
        if r.status == .cancelled { return String(localized: "abgesagt") }
        switch r.phase(serverNow: serverNow) {
        case .open, .closing: return countdown(r.startsAt - serverNow)
        case .running: return String(localized: "läuft")
        case .over: return String(localized: "vorbei")
        }
    }

    /// „in 4:59“, „in 2 h 10 min“, „in 3 Tagen“
    static func countdown(_ s: TimeInterval) -> String {
        let s = max(s, 0)
        if s < 3600 { return String(localized: "in \(Format.duration(s.rounded(.up)))") }
        if s < 86400 { return String(localized: "in \(Int(s / 3600)) h \(Int(s.truncatingRemainder(dividingBy: 3600) / 60)) min") }
        return String(localized: "in \(Int(s / 86400)) Tagen")
    }

    static func flag(_ code: String?) -> String {
        guard let code, code.count == 2 else { return "" }
        return code.uppercased().unicodeScalars.compactMap { UnicodeScalar(127_397 + $0.value) }.map(String.init).joined()
    }
}

// MARK: - Rennen erstellen

struct CreateRaceView: View {
    var onCreated: (OnlineRace) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(CourseLibrary.self) private var library
    @Environment(DeviceManager.self) private var devices
    @State private var courseId = ""
    @State private var start = Date().addingTimeInterval(15 * 60)
    @State private var distance = 2000.0
    @State private var maxParticipants = 8
    @State private var isPrivate = false
    @State private var fillVirtual = false
    @State private var title = ""
    @State private var busy = false
    @State private var error: String?
    @State private var createdCode: String?
    @State private var created: OnlineRace?

    private var courses: [Course] { RideCourses.all(library: library, simulatorActive: devices.simulatorActive) }
    private var course: Course? { courses.first { $0.id == courseId } ?? courses.first }
    private var courseLength: Double { course.map { $0.turns > 0 ? 2 * $0.oneWayM : $0.oneWayM } ?? 2000 }
    private var distances: [Double] {
        let list = [500.0, 1000, 2000, 5000, 6000, 10000].filter { $0 <= courseLength + 0.5 }
        return list.isEmpty ? [courseLength.rounded(.down)] : list
    }

    var body: some View {
        NavigationStack {
            if let created {
                createdView(created)
            } else {
                form
            }
        }
        .preferredColorScheme(.dark)
    }

    private var form: some View {
        Form {
            Section("Strecke") {
                Picker("Strecke", selection: $courseId) {
                    ForEach(courses) { c in Text(c.titleText).tag(c.id) }
                }
                Picker("Distanz", selection: $distance) {
                    ForEach(distances, id: \.self) { d in Text(RaceTexts.target(.distance(d))).tag(d) }
                }
            }
            Section {
                DatePicker("Start", selection: $start, in: Date().addingTimeInterval(180)...Date().addingTimeInterval(30 * 86400))
                Stepper("Höchstens \(maxParticipants) Teilnehmende", value: $maxParticipants, in: 2...OnlineRaceLimits.smallFieldMax)
            } footer: {
                Text("Anmeldeschluss ist eine Minute vor dem Start. Alle starten gleichzeitig.")
            }
            Section {
                Toggle("Privat (nur mit Einladungscode)", isOn: $isPrivate)
                #if DEBUG
                Toggle("Mit virtuellen Teilnehmenden auffüllen (Test)", isOn: $fillVirtual)
                #endif
                TextField("Titel (optional)", text: $title)
            } footer: {
                Text(isPrivate ? String(localized: "Nach dem Erstellen bekommst du einen Code zum Weitergeben.")
                     : String(localized: "Öffentliche Rennen sehen alle angemeldeten Ruderer in der Liste."))
            }
            if let error {
                Section { Text(error).foregroundStyle(Theme.warn) }
            }
        }
        .navigationTitle(Text("Rennen erstellen"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Erstellen") { Task { await create() } }.disabled(busy || course == nil)
            }
        }
        .onAppear {
            if courseId.isEmpty { courseId = courses.first?.id ?? "" }
            if !distances.contains(distance) { distance = distances.last ?? 2000 }
        }
        .onChange(of: courseId) { _, _ in
            if !distances.contains(distance) { distance = distances.last ?? 2000 }
        }
    }

    private func createdView(_ r: OnlineRace) -> some View {
        VStack(spacing: DS.Space.l) {
            Image(systemName: "flag.checkered").font(.system(size: 48)).foregroundStyle(Theme.accent)
            Text("Rennen erstellt").font(.title2.bold())
            Text("\(RaceTexts.target(r.target)) · \(RaceTexts.start(r.startsAt))").foregroundStyle(Theme.text2)
            if let code = createdCode {
                VStack(spacing: DS.Space.s) {
                    Text("Einladungscode").dsLabelStyle()
                    Text(String(code.prefix(4)) + "-" + String(code.suffix(4)))
                        .font(.system(size: 40, weight: .bold, design: .monospaced))
                        .textSelection(.enabled)
                    ShareLink(item: String(localized: "Rudere mit mir in RowCoach: „\(r.title)“, Code \(code)")) {
                        Label("Code teilen", systemImage: "square.and.arrow.up")
                    }
                }
                .dsCard()
            }
            Button("Zum Warteraum") {
                onCreated(r)
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle(compact: true))
        }
        .padding(DS.Space.l)
        .frame(maxWidth: 560)
    }

    private func create() async {
        guard let course else { return }
        busy = true
        defer { busy = false }
        let name = title.trimmingCharacters(in: .whitespaces).isEmpty
            ? "\(course.titleText) · \(RaceTexts.target(.distance(distance)))" : title
        do {
            let (r, code) = try await OnlineRaceStore.shared.create(
                title: String(name.prefix(OnlineRaceLimits.titleMax)), course: course,
                courseVersion: library.installedVersions[course.id], target: .distance(distance), startsAt: start,
                maxParticipants: maxParticipants, visibility: isPrivate ? .invite : .open, fillVirtual: fillVirtual)
            createdCode = code
            created = r
        } catch {
            self.error = OnlineRaceStore.message(error)
        }
    }
}

// MARK: - Warteraum

/// Anmeldungen und Ergebnisse eines Rennens live (Firestore-Listener, nur solange die Ansicht offen ist)
@MainActor
@Observable
final class OnlineRaceRoom {
    let raceId: String
    /// nil, bis das Rennen geladen ist
    private(set) var loaded: OnlineRace?
    private(set) var entries: [OnlineRaceEntry] = [] {
        didSet { participants = OnlineRoster.filled(entries, race: race, pool: VirtualTournamentStore.shared.pool).participants }
    }
    /// Teilnehmerliste wie im Rennen (echte nach Anmeldung, dann virtuelle); neu gerechnet, wenn sich Anmeldungen ändern
    private(set) var participants: [RaceParticipant] = []
    private(set) var results: [OnlineRaceResult] = []
    private(set) var missing = false
    @ObservationIgnored private var observations: [any RaceLiveObservation] = []

    init(raceId: String, race: OnlineRace? = nil) {
        self.raceId = raceId
        loaded = race
    }

    /// Platzhalter, solange nichts geladen ist
    var race: OnlineRace {
        loaded ?? OnlineRace(id: raceId, title: "…", courseId: "", target: .distance(0), startsAt: 0, createdBy: "")
    }

    func start() async {
        guard observations.isEmpty, let dir = OnlineRaceStore.shared.directory else { return }
        if let fresh = try? await dir.race(id: raceId) {
            loaded = fresh
            OnlineRaceStore.shared.cache(fresh)
        } else if loaded == nil {
            missing = true
        }
        observations.append(dir.observeEntries(raceId: raceId) { [weak self] list in
            Task { @MainActor in self?.entries = list }
        })
        observations.append(dir.observeResults(raceId: raceId) { [weak self] list in
            Task { @MainActor in self?.results = list }
        })
    }

    func stop() {
        for o in observations { o.cancel() }
        observations = []
    }

    func reload() async {
        if let dir = OnlineRaceStore.shared.directory, let fresh = try? await dir.race(id: raceId) { loaded = fresh }
    }

    func isRegistered(_ uid: String?) -> Bool { uid.map { u in entries.contains { $0.id == u } } ?? false }
}

struct RaceRoomView: View {
    @Environment(\.rowingLaunch) private var launch
    @Environment(CourseLibrary.self) private var library
    @Environment(CourseDownloads.self) private var downloads
    @State private var room: OnlineRaceRoom
    @State private var busy = false
    @State private var error: String?
    @State private var autoStarted = false
    @State private var showResults = false
    @State private var confirmCancel = false
    private let store = OnlineRaceStore.shared

    init(raceId: String) {
        _room = State(initialValue: OnlineRaceRoom(raceId: raceId, race: OnlineRaceStore.shared.cached(raceId)))
    }

    private var race: OnlineRace { room.race }
    private var uid: String? { store.uid }
    private var registered: Bool { room.isRegistered(uid) }

    /// Strecke installiert (mindestens die verlangte Fassung)?
    private var eligibility: RaceEligibility {
        RaceEligibility.check(race.race) { id, version in
            if library.course(id: id) == nil && id != RideCourses.testCourse.id { return false }
            guard let v = version, let have = library.installedVersions[id] else { return true }
            return have >= v
        }
    }

    private var course: Course? {
        library.course(id: race.courseId) ?? (race.courseId == RideCourses.testCourse.id ? RideCourses.testCourse : nil)
    }

    var body: some View {
        if room.loaded == nil {
            Group {
                if room.missing {
                    DSEmptyState(title: String(localized: "Rennen nicht gefunden"), systemImage: "flag.slash")
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .dsPageBackground()
            .task { await room.start() }
        } else {
            roomBody
        }
    }

    private var roomBody: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date.timeIntervalSince1970 + store.serverOffset
            List {
                header(now: now)
                actions(now: now)
                participantsSection
                if let error { Section { Text(error).foregroundStyle(Theme.warn) } }
            }
            .onChange(of: Int(now)) { _, _ in autoStart(now: now) }
        }
        .scrollContentBackground(.hidden)
        .dsPageBackground()
        .navigationTitle(Text(race.title))
        .navigationBarTitleDisplayMode(.inline)
        .task { await room.start() }
        .onDisappear { room.stop() }
        .refreshable { await room.reload() }
        .sheet(isPresented: $showResults) { OnlineRaceResultsView(race: race) }
        .confirmationDialog("Rennen absagen?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Absagen", role: .destructive) { Task { await run { try await store.cancel(race); await room.reload() } } }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    private func header(now: TimeInterval) -> some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Text("\(RaceTexts.target(race.target)) · \(course?.titleText ?? race.courseId)").font(.headline)
                Text(RaceTexts.start(race.startsAt)).foregroundStyle(Theme.text2)
                switch race.phase(serverNow: now) {
                case .open, .closing:
                    Text(Format.duration(max(race.startsAt - now, 0).rounded(.up)))
                        .font(.system(size: 56, weight: .bold, design: .rounded)).monospacedDigit()
                        .accessibilityLabel(Text("Start \(RaceTexts.countdown(race.startsAt - now))"))
                    if race.phase(serverNow: now) == .closing {
                        Text("Anmeldung geschlossen").font(.caption).foregroundStyle(Theme.text2)
                    }
                case .running:
                    Text("Das Rennen läuft").font(.title2.bold()).foregroundStyle(Theme.accent)
                case .over:
                    Text(race.status == .cancelled ? String(localized: "Abgesagt") : String(localized: "Vorbei"))
                        .font(.title2.bold())
                }
            }
            .padding(.vertical, DS.Space.s)
        }
    }

    @ViewBuilder
    private func actions(now: TimeInterval) -> some View {
        let phase = race.phase(serverNow: now)
        Section {
            if case .needsCourse = eligibility {
                courseDownload
            }
            if phase == .open && !registered {
                Button { Task { await run { try await store.register(race) } } } label: {
                    Label("Anmelden", systemImage: "person.badge.plus")
                }
                .disabled(busy || room.entries.filter { $0.source != .virtual }.count >= race.maxParticipants)
            }
            if registered && (phase == .open || phase == .closing || phase == .running) {
                Button {
                    startRow()
                } label: {
                    Label(phase == .running ? String(localized: "Jetzt einsteigen (Zeit läuft)") : String(localized: "Zum Start"),
                          systemImage: "figure.rowing")
                }
                .disabled(eligibility != .ready || course == nil || race.startsAt - now > 600)
                if race.startsAt - now > 600 && phase != .running {
                    Text("Der Ruderbildschirm öffnet sich 30 Sekunden vor dem Start von selbst, solange diese Seite offen ist.")
                        .font(.footnote).foregroundStyle(Theme.text2)
                }
            }
            if registered && phase == .open {
                Button(role: .destructive) { Task { await run { try await store.unregister(race) } } } label: {
                    Label("Abmelden", systemImage: "person.badge.minus")
                }
            }
            if phase == .running || phase == .over || !room.results.isEmpty {
                Button { showResults = true } label: { Label("Ergebnis", systemImage: "list.number") }
            }
            if race.createdBy == uid && race.status == .scheduled && now < race.startsAt {
                Button(role: .destructive) { confirmCancel = true } label: { Label("Rennen absagen", systemImage: "xmark.circle") }
            }
        } footer: {
            if race.visibility == .invite {
                Text("Privates Rennen – nur mit Einladungscode auffindbar.")
            }
        }
    }

    @ViewBuilder
    private var courseDownload: some View {
        if let entry = library.catalog?.courses.first(where: { $0.id == race.courseId }) {
            switch downloads.state(entry.id) {
            case .downloading(let p):
                ProgressView(value: p) { Text("Strecke wird geladen …") }
            case .failed(let msg):
                Text(msg).foregroundStyle(Theme.warn)
                Button("Erneut laden") { downloads.download(entry, quality: library.quality) }
            case .idle:
                Button {
                    downloads.download(entry, quality: library.quality)
                } label: {
                    Label(String(localized: "Strecke laden (\(DSFormat.bytes(entry.bytes(quality: library.quality.rawValue))))"),
                          systemImage: "arrow.down.circle")
                }
                Text("Alle rudern dieselbe Landschaft – die Strecke muss vor dem Start auf dem Gerät sein.")
                    .font(.footnote).foregroundStyle(Theme.text2)
            }
        } else {
            Text("Diese Strecke ist auf dem Gerät nicht vorhanden und im Katalog nicht zu finden.")
                .foregroundStyle(Theme.warn)
        }
    }

    private var participantsSection: some View {
        let list = room.participants
        let humans = list.filter { !$0.isVirtual }
        return Section {
            ForEach(humans) { p in participantRow(p) }
            let virtuals = list.filter(\.isVirtual)
            if !virtuals.isEmpty {
                DisclosureGroup {
                    ForEach(virtuals.prefix(400)) { p in participantRow(p) }
                } label: {
                    Text("\(virtuals.count) virtuelle Teilnehmende \(RaceParticipant.virtualMark)")
                        .foregroundStyle(Theme.text2)
                }
            }
        } header: {
            Text("Teilnehmende \(humans.count)/\(race.maxParticipants)")
        }
    }

    private func participantRow(_ p: RaceParticipant) -> some View {
        let look = AppearanceCatalog.current.resolve(p.resolvedAppearance())
        let flag = RaceTexts.flag(look.boatFlag != nil || look.shirtFlag != nil ? p.appearance?.nationality : nil)
        return HStack(spacing: DS.Space.s) {
            Image(systemName: "figure.rowing")
                .foregroundStyle(Color(red: look.shirt.red, green: look.shirt.green, blue: look.shirt.blue))
                .frame(width: 28)
            if !flag.isEmpty { Text(flag) }
            Text(p.displayName.isEmpty ? String(localized: "Ruderer") : p.displayName)
                .fontWeight(p.id == uid ? .bold : .regular)
            if p.isVirtual { Text(RaceParticipant.virtualMark).foregroundStyle(Theme.text2) }
            Spacer()
            if p.id == race.createdBy { Text("Veranstalter").font(.caption).foregroundStyle(Theme.text2) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(p.isVirtual ? "\(p.displayName), \(String(localized: "virtuell"))" : p.displayName))
    }

    private func run(_ work: () async throws -> Void) async {
        busy = true
        defer { busy = false }
        do {
            try await work()
            error = nil
        } catch {
            self.error = OnlineRaceStore.message(error)
        }
    }

    private func startRow() {
        guard let course else { return }
        launch?.startRace?(course, OnlineRaceLaunch(race: race, entries: room.entries))
    }

    /// 30 s vor dem Start selbst in den Ruderbildschirm (angemeldet, Strecke da, Seite offen)
    private func autoStart(now: TimeInterval) {
        guard !autoStarted, registered, eligibility == .ready, race.status == .scheduled else { return }
        let left = race.startsAt - now
        if left <= 30 && left > 0 {
            autoStarted = true
            startRow()
        }
    }
}

// MARK: - Ergebnis

/// Ergebnisliste eines Online-Rennens: endgültig (Server) bzw. vorläufig (selbst gemeldet, auf dem Gerät simuliert)
/// bzw. geschätzt (letzte empfangene Frames). Virtuelle mit ✦, Filter „Alle“ / „Nur echte“.
struct OnlineRaceResultsView: View {
    let race: OnlineRace
    @Environment(\.dismiss) private var dismiss
    @State private var room: OnlineRaceRoom
    @State private var filter: RankingFilter = .all
    @State private var showInfo = false

    init(race: OnlineRace) {
        self.race = race
        _room = State(initialValue: OnlineRaceRoom(raceId: race.id, race: race))
    }

    private var rows: [OnlineRaceStanding] {
        let local = OnlineRaceStore.shared.localStandings(raceId: race.id)
        var roster = room.participants
        for p in local?.roster ?? [] where !roster.contains(where: { $0.id == p.id }) { roster.append(p) }
        let virtual = local?.virtual ?? []
        let all = OnlineRaceResults.merge(target: race.target, roster: roster, submitted: room.results,
                                          local: local?.results ?? [], virtualRuns: virtual)
        guard filter == .realOnly else { return all }
        return all.filter { !$0.participant.isVirtual }.enumerated().map { i, r in
            var r = r
            if !OnlineRaceResults.isFinal(all) { r.place = i + 1 }
            return r
        }
    }

    var body: some View {
        NavigationStack {
            List {
                let list = rows
                Section {
                    Picker("Teilnehmende", selection: $filter) {
                        Text("Alle").tag(RankingFilter.all)
                        Text("Nur echte").tag(RankingFilter.realOnly)
                    }
                    .pickerStyle(.segmented)
                    Label(OnlineRaceResults.isFinal(list) ? String(localized: "Endgültig – vom Server geprüft")
                          : String(localized: "Vorläufig – endgültig erst nach der Prüfung durch den Server"),
                          systemImage: OnlineRaceResults.isFinal(list) ? "checkmark.seal" : "hourglass")
                        .font(.footnote).foregroundStyle(Theme.text2)
                }
                Section {
                    if list.isEmpty { Text("Noch kein Ergebnis.").foregroundStyle(Theme.text2) }
                    ForEach(list) { r in row(r) }
                }
                Section {
                    Text("✦ = virtuelle Teilnehmende: erfundene Ruderer, die Turniere auffüllen. Ihre Ergebnisse entstehen aus einem Leistungsmodell.")
                        .font(.footnote).foregroundStyle(Theme.text2)
                }
            }
            .navigationTitle(Text("Ergebnis"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showInfo = true } label: { Image(systemName: "info.circle") }
                        .accessibilityLabel(Text("Was sind virtuelle Teilnehmende?"))
                }
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
            .sheet(isPresented: $showInfo) { VirtualParticipantsInfoView() }
            .task { await room.start() }
            .onDisappear { room.stop() }
        }
        .preferredColorScheme(.dark)
    }

    private func row(_ r: OnlineRaceStanding) -> some View {
        let isMe = r.participant.id == OnlineRaceStore.shared.uid
        let value = r.finished ? (r.time.map { Format.duration($0, tenths: true) } ?? "\(Int(r.distance.rounded())) m")
            : "\(Int(r.distance.rounded())) m"
        return HStack(spacing: 10) {
            Text("\(r.place).").monospacedDigit().frame(minWidth: 40, alignment: .trailing).foregroundStyle(Theme.text2)
            Text(r.participant.displayName.isEmpty ? String(localized: "Ruderer") : r.participant.displayName)
                .fontWeight(isMe ? .bold : .regular).lineLimit(1)
            if r.participant.isVirtual { Text(RaceParticipant.virtualMark).foregroundStyle(Theme.text2) }
            Spacer(minLength: 8)
            if r.status != .final {
                Image(systemName: r.status == .estimated ? "questionmark.circle" : "hourglass")
                    .font(.caption).foregroundStyle(Theme.text2)
                    .accessibilityLabel(Text(r.status == .estimated ? "geschätzt" : "vorläufig"))
            }
            if !r.flags.isEmpty {
                Image(systemName: "exclamationmark.triangle").font(.caption).foregroundStyle(Theme.warn)
                    .accessibilityLabel(Text("auffällig"))
            }
            Text(value).monospacedDigit()
        }
        .listRowBackground(isMe ? Theme.accent.opacity(0.18) : nil)
        .accessibilityElement(children: .combine)
    }
}
