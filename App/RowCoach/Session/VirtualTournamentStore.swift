import Foundation
import os
import RowCoachKit

/// Virtuelle Teilnehmende in der App (docs/MULTIPLAYER.md „Virtuelle Teilnehmende“): Pool aus dem Bundle
/// (`virtual-rowers-v1.bin`), das laufende Demo-Turnier (`-demoTournament 1`) und die lokale Rangliste
/// (Application Support/race-rankings.json). Später schreibt der Server Ergebnisse und Ranglisten; die App liest sie.
@MainActor
final class VirtualTournamentStore {
    static let shared = VirtualTournamentStore()
    private static let log = Logger(subsystem: "com.falkue.RowCoach", category: "Race")

    /// Pool v1 aus dem Bundle; nil, wenn die Datei fehlt oder beschädigt ist (dann gibt es kein Demo-Turnier)
    private(set) lazy var pool: VirtualRowerPool? = {
        let name = VirtualRowerPool.fileName()
        guard let url = Bundle.main.url(forResource: (name as NSString).deletingPathExtension, withExtension: "bin") else {
            Self.log.error("Pool \(name, privacy: .public) fehlt im Bundle")
            return nil
        }
        do {
            let pool = try VirtualRowerPool.decode(Data(contentsOf: url))
            Self.log.info("Pool v\(pool.version, privacy: .public): \(pool.rowers.count, privacy: .public) virtuelle Teilnehmende")
            return pool
        } catch {
            Self.log.error("Pool nicht lesbar: \(String(describing: error), privacy: .public)")
            return nil
        }
    }()

    /// Laufendes Turnier-Rennen (Demo) mit den Ergebnissen der übrigen „echten“ Demo-Boote
    private(set) var pending: VirtualTournamentRace?
    private var pendingOthers: [RaceResult] = []
    /// Ergebnisse je Rennen, sobald gewertet (für die Ergebnisansicht)
    private(set) var finishedRaces: [String: [RaceResult]] = [:]

    private(set) var book: RaceRankingBook

    private static var bookURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("race-rankings.json")
    }

    private init() {
        book = Self.bookURL.flatMap { try? Data(contentsOf: $0) }.flatMap(RaceRankingBook.decode) ?? RaceRankingBook()
        // Testbetrieb `-resetVirtualInfo 1`: Info-Blatt wieder zeigen (einmal je Programmstart)
        if UserDefaults.standard.bool(forKey: "resetVirtualInfo") {
            UserDefaults.standard.removeObject(forKey: Self.infoSeenKey)
            Self.log.info("Info-Blatt virtuelle Teilnehmende zurückgesetzt (\(Self.infoSeenKey, privacy: .public))")
        }
    }

    /// UserDefaults-Schlüssel „Info-Blatt zu virtuellen Teilnehmenden gesehen“ (Bool, in den Standard-Einstellungen
    /// der App; zurücksetzen mit `-resetVirtualInfo 1`, siehe BUILD.md)
    static let infoSeenKey = "virtualParticipantsInfoSeen"

    /// Info-Blatt schon gesehen? (direkt aus UserDefaults, nicht über @AppStorage, damit ein Zurücksetzen beim Start
    /// sofort gilt)
    var infoSeen: Bool {
        get { UserDefaults.standard.bool(forKey: Self.infoSeenKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.infoSeenKey)
            Self.log.info("Info-Blatt virtuelle Teilnehmende: gesehen = \(newValue, privacy: .public)")
        }
    }

    /// Soll das Info-Blatt jetzt kommen? (protokolliert die Entscheidung)
    func shouldShowInfo() -> Bool {
        let seen = infoSeen
        Self.log.info("Info-Blatt virtuelle Teilnehmende: \(seen ? "schon gesehen, nicht gezeigt" : "wird vor dem Start gezeigt", privacy: .public) (\(Self.infoSeenKey, privacy: .public))")
        return !seen
    }

    func begin(_ race: VirtualTournamentRace, others: [RaceResult]) {
        pending = race
        pendingOthers = others
        Self.log.info("Turnier \(race.race.tournamentId ?? "-", privacy: .public): Mindestfeld \(race.field.minimumField, privacy: .public), echt \(race.field.realCount, privacy: .public), virtuell \(race.field.virtualCount, privacy: .public)")
    }

    /// Gehört diese gespeicherte Fahrt zu einem Turnier-Rennen (laufend oder schon gewertet)?
    func isTournamentRace(_ raceId: String?) -> Bool {
        guard let raceId else { return false }
        return pending?.race.id == raceId || finishedRaces[raceId] != nil || book.entries.contains { $0.raceId == raceId }
    }

    /// Wertet das laufende Rennen mit der eigenen Fahrt (einmal je Rennen) und speichert die Rangliste
    @discardableResult
    func finish(record: WorkoutRecord, myId: String = "me") -> [RaceResult]? {
        guard let race = pending, race.race.id == record.header.raceId else {
            return record.header.raceId.flatMap { finishedRaces[$0] }
        }
        let mine = RaceResult.fromSamples(participantId: myId, samples: record.samples, target: race.race.target)
        let results = race.results(real: [mine] + pendingOthers)
        finishedRaces[race.race.id] = results
        book.add(results: results, race: race.race, startsAt: race.startsAt, participants: race.field.participants)
        pending = nil
        pendingOthers = []
        save()
        let place = results.first { $0.participantId == myId }?.place ?? 0
        Self.log.info("Turnier-Rennen \(race.race.id, privacy: .public) gewertet: Platz \(place, privacy: .public) von \(results.count, privacy: .public)")
        return results
    }

    private func save() {
        guard let url = Self.bookURL else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try book.encoded().write(to: url, options: .atomic)
        } catch {
            Self.log.error("Rangliste nicht gespeichert: \(error.localizedDescription, privacy: .public)")
        }
    }
}
