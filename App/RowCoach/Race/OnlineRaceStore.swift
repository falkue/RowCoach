import Foundation
import os
import RowCoachKit

/// Online-Rennen in der App (docs/MULTIPLAYER.md „Umsetzung Firebase“): Zugang (Konto, später Abo), kommende Rennen,
/// eigene Rennen, Anlegen, Beitreten mit Code, Anmelden/Abmelden, Verbindung für die Fahrt und das vorläufige
/// Ergebnis danach. Ohne Konto stellt er keine einzige Anfrage (docs/SYNC.md „Offline zuerst“).
@MainActor
@Observable
final class OnlineRaceStore {
    static let shared = OnlineRaceStore()
    private static let log = Logger(subsystem: "com.falkue.RowCoach", category: "Race")

    private(set) var upcoming: [OnlineRace] = []
    /// selbst angelegte oder beigetretene (auch private), neueste zuerst
    private(set) var mine: [OnlineRace] = []
    private(set) var loading = false
    var errorMessage: String?
    /// Serverzeit − Gerätezeit (s), aus der Realtime Database
    private(set) var serverOffset: TimeInterval = 0

    @ObservationIgnored private var liveBackend: FirebaseRaceLiveBackend?
    @ObservationIgnored private var firestore: FirestoreRaceDirectory?
    /// Rennabo (später StoreKit + Server, docs/SYNC.md „Rennen-Abo“); heute immer inaktiv
    @ObservationIgnored private let entitlements: EntitlementProvider = NoopEntitlementProvider()
    private var entitled = false

    /// laufendes Online-Rennen (für die Wertung nach dem Speichern)
    @ObservationIgnored private(set) var active: (race: OnlineRace, link: RaceLink, transport: RaceLiveTransport)?
    @ObservationIgnored private var submitted: Set<String> = []

    private static let mineKey = "onlineRaces.mine"

    private init() {}

    // MARK: Zugang

    var uid: String? { SyncController.shared.user?.uid }

    /// Angemeldet mit bestätigter E-Mail bzw. Google/Apple (die Regeln verlangen das fürs Schreiben)
    private var accountReady: Bool {
        guard let u = SyncController.shared.user else { return false }
        return u.emailVerified || u.providers.contains("google.com") || u.providers.contains("apple.com")
    }

    var access: OnlineRaceAccess {
        #if DEBUG
        let debug = true
        #else
        let debug = false
        #endif
        return OnlineRaceAccess.check(serverConfigured: FirebaseBootstrap.isAvailable, signedIn: accountReady,
                                      entitled: entitled, debugBuild: debug)
    }

    /// Verzeichnis und Datenbank nur mit Konto (sonst nil → keine Anfrage)
    var directory: RaceDirectory? { access == .allowed ? ensureBackends().directory : nil }

    private func ensureBackends() -> (live: FirebaseRaceLiveBackend, directory: FirestoreRaceDirectory) {
        if let liveBackend, let firestore { return (liveBackend, firestore) }
        FirebaseBootstrap.configureIfNeeded()
        let live = FirebaseRaceLiveBackend()
        let dir = FirestoreRaceDirectory(live: live)
        liveBackend = live
        firestore = dir
        return (live, dir)
    }

    var serverNow: TimeInterval { Date().timeIntervalSince1970 + serverOffset }

    // MARK: Listen

    func refresh() async {
        entitled = await entitlements.status(.races).isActive(at: Date())
        guard access == .allowed else {
            upcoming = []
            mine = []
            return
        }
        let (live, dir) = ensureBackends()
        loading = true
        defer { loading = false }
        if let off = try? await live.serverTimeOffset() { serverOffset = off }
        do {
            upcoming = try await dir.upcoming(serverNow: serverNow, limit: 50)
            var list: [OnlineRace] = []
            for id in Self.mineIds() {
                if let r = upcoming.first(where: { $0.id == id }) {
                    list.append(r)
                } else if let r = try await dir.race(id: id) {
                    list.append(r)
                }
            }
            // vorbei seit mehr als einem Tag → aus „Meine Rennen“ streichen
            let keep = list.filter { $0.startsAt + $0.maxDuration + 86400 > serverNow }
            Self.setMineIds(keep.map(\.id))
            mine = keep.sorted { $0.startsAt < $1.startsAt }
            errorMessage = nil
        } catch {
            errorMessage = Self.message(error)
            Self.log.error("Rennen laden: \(String(describing: error), privacy: .public)")
        }
    }

    /// zuletzt gesehene Rennen (Navigation per id)
    @ObservationIgnored private var known: [String: OnlineRace] = [:]

    func cache(_ r: OnlineRace) { known[r.id] = r }

    func cached(_ id: String) -> OnlineRace? {
        known[id] ?? mine.first { $0.id == id } ?? upcoming.first { $0.id == id }
    }

    private static func mineIds() -> [String] { UserDefaults.standard.stringArray(forKey: mineKey) ?? [] }
    private static func setMineIds(_ ids: [String]) { UserDefaults.standard.set(Array(ids.prefix(50)), forKey: mineKey) }
    private func remember(_ id: String) {
        var ids = Self.mineIds().filter { $0 != id }
        ids.insert(id, at: 0)
        Self.setMineIds(ids)
    }

    // MARK: Anlegen, Beitreten, Anmelden

    /// Neues Rennen; die anlegende Person ist gleich angemeldet. Private Rennen bekommen einen Einladungscode.
    func create(title: String, course: Course, courseVersion: Int?, target: RaceTarget, startsAt: Date,
                maxParticipants: Int, visibility: OnlineRaceVisibility, fillVirtual: Bool) async throws -> (OnlineRace, String?) {
        guard access == .allowed, let uid, let dir = directory else { throw RaceDirectoryError.notSignedIn }
        var g = SystemRandomNumberGenerator()
        let best2k = UserDefaults.standard.double(forKey: TrainingSettings.best2kKey)
        let race = OnlineRace(title: String(title.prefix(OnlineRaceLimits.titleMax)), courseId: course.id,
                              courseVersion: courseVersion, target: target,
                              startsAt: startsAt.timeIntervalSince1970, maxParticipants: maxParticipants,
                              visibility: visibility, createdBy: uid, seed: OnlineRace.randomSeed(using: &g),
                              fill: fillVirtual ? .client : .none,
                              fillLevel: fillVirtual && best2k >= 300 && best2k <= 900 ? best2k : nil)
        if let e = race.validationError(serverNow: serverNow) { throw RaceDirectoryError.invalid(e) }
        let code = visibility == .invite ? RaceInviteCode.make(using: &g) : nil
        let created = try await dir.create(race, inviteCode: code)
        remember(created.id)
        try await register(created)
        Self.log.info("Rennen \(created.id, privacy: .public) angelegt (\(visibility.rawValue, privacy: .public)), Start \(Date(timeIntervalSince1970: created.startsAt), privacy: .public)")
        await refresh()
        return (created, code)
    }

    func race(inviteCode: String) async throws -> OnlineRace? {
        guard let dir = directory else { throw RaceDirectoryError.notSignedIn }
        guard let id = try await dir.raceId(inviteCode: inviteCode) else { return nil }
        return try await dir.race(id: id)
    }

    func register(_ race: OnlineRace) async throws {
        guard let uid, let dir = directory else { throw RaceDirectoryError.notSignedIn }
        try await dir.register(raceId: race.id, entry: OnlineRaceEntry.mine(uid: uid, profile: RowerProfileStore.shared.profile))
        remember(race.id)
        if !mine.contains(where: { $0.id == race.id }) { mine.append(race); mine.sort { $0.startsAt < $1.startsAt } }
    }

    func unregister(_ race: OnlineRace) async throws {
        guard let uid, let dir = directory else { throw RaceDirectoryError.notSignedIn }
        try await dir.unregister(raceId: race.id, uid: uid)
        if race.createdBy != uid {
            Self.setMineIds(Self.mineIds().filter { $0 != race.id })
            mine.removeAll { $0.id == race.id }
        }
    }

    func cancel(_ race: OnlineRace) async throws {
        guard let dir = directory else { throw RaceDirectoryError.notSignedIn }
        try await dir.cancel(raceId: race.id)
        await refresh()
    }

    // MARK: Fahrt

    /// Verbindung für die Fahrt: Transport (Realtime Database), Dead-Reckoning-Sender und -Empfänger, Pool für
    /// virtuelle Teilnehmende. Die Fahrt hängt sie mit `attachRace(_:holdUntilStart: true)` an.
    func makeLink(race: OnlineRace, entries: [OnlineRaceEntry]) -> RaceLink? {
        guard access == .allowed, let uid else { return nil }
        let (live, dir) = ensureBackends()
        let transport = RaceLiveTransport(race: race, uid: uid, backend: live, directory: dir, initialEntries: entries,
                                          pool: VirtualTournamentStore.shared.pool)
        let profile = RowerProfileStore.shared
        let me = RaceParticipant(id: uid, displayName: profile.displayName, lane: 1, appearance: profile.appearance)
        let finish = race.target.finishDistance
        var coordinator = RaceCoordinator(race: race.race, me: me, tracker: .deadReckoning(finishDistance: finish))
        coordinator.deadReckoning = RaceDeadReckoningPublisher(finishDistance: finish)
        let link = RaceLink(coordinator: coordinator, transports: [transport])
        active = (race, link, transport)
        Self.log.info("Rennen \(race.id, privacy: .public): Verbindung vorbereitet, \(entries.count, privacy: .public) Anmeldungen, \(race.isSmallField ? "Kleinfeld (alle hören alle)" : "grosses Feld", privacy: .public)")
        return link
    }

    func isOnlineRace(_ raceId: String?) -> Bool {
        guard let raceId else { return false }
        return active?.race.id == raceId
    }

    /// Nach dem Speichern: eigenes Ergebnis vorläufig melden (einmal je Rennen). Zeit aus dem Rennen (ab dem
    /// gemeinsamen Start, exakt interpolierte Zielzeit des Senders), nicht aus der Fahrt.
    func submitResult(raceId: String?) async {
        guard let raceId, let active, active.race.id == raceId, !submitted.contains(raceId), let uid,
              let dir = directory else { return }
        let mine = active.link.coordinator.standings().first { $0.participantId == uid }
        guard let mine else {
            Self.log.info("Rennen \(raceId, privacy: .public): kein eigener Stand, kein Ergebnis gemeldet")
            return
        }
        submitted.insert(raceId)
        do {
            try await dir.submitResult(raceId: raceId, result: OnlineRaceResult(mine))
            Self.log.info("Rennen \(raceId, privacy: .public): vorläufiges Ergebnis gemeldet (\(Int(mine.distance), privacy: .public) m, Zeit \(mine.time ?? -1, privacy: .public))")
        } catch {
            submitted.remove(raceId)
            errorMessage = Self.message(error)
            Self.log.error("Ergebnis melden: \(String(describing: error), privacy: .public)")
        }
    }

    /// Stand des Geräts nach dem Rennen (für die Ergebnisliste, solange nichts gemeldet ist)
    func localStandings(raceId: String) -> (roster: [RaceParticipant], results: [RaceResult], virtual: [VirtualRaceRun])? {
        guard let active, active.race.id == raceId else { return nil }
        return (active.link.coordinator.roster, active.link.coordinator.standings(), active.transport.virtualRuns)
    }

    // MARK: Texte

    static func message(_ error: Error) -> String {
        switch error as? RaceDirectoryError {
        case .notSignedIn: return String(localized: "Für Online-Rennen anmelden.")
        case .notFound: return String(localized: "Rennen nicht gefunden.")
        case .registrationClosed: return String(localized: "Die Anmeldung ist geschlossen.")
        case .raceFull: return String(localized: "Das Rennen ist voll.")
        case .notAllowed: return String(localized: "Das ist nicht erlaubt (Konto bestätigt?).")
        case .invalid(let what):
            switch what {
            case "tooSoon": return String(localized: "Der Start muss mindestens 2 Minuten in der Zukunft liegen.")
            case "tooLate": return String(localized: "Der Start darf höchstens 30 Tage in der Zukunft liegen.")
            case "participants": return String(localized: "2 bis 30 Teilnehmende.")
            default: return String(localized: "Angaben unvollständig.")
            }
        case .network: return String(localized: "Keine Verbindung zum Server.")
        case .server(let m): return m
        case nil: return error.localizedDescription
        }
    }
}
