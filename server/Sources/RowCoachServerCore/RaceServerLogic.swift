import Foundation
import RowCoachKit

// Reine Logik des Servers (ohne Netz, getestet): Aggregator der Übersicht, Auffüllen mit virtuellen, Abo-Prüfung,
// Entscheidungen des minütlichen Takts. Die Ein-/Ausgabe (Firestore, Realtime Database) steckt in `RaceServerStore`.

/// Aggregator eines grossen Rennens: nimmt alle Frames (`live/{raceId}/f`), simuliert die virtuellen selbst und
/// liefert alle 10 s ein Delta (Zielzone 5 s, 1 m), voll beim Start und alle 300 s (`RaceFieldAggregator` im Kit).
/// Kurzindex aus derselben Teilnehmerliste wie auf den Geräten (`OnlineRoster.filled`), also gleicher `rosterHash`.
public struct FieldAggregatorCore: Sendable {
    public let race: OnlineRace
    public let participants: [RaceParticipant]
    public let roster: RaceRosterIndex
    public private(set) var history: [String: [LiveFrame]] = [:]
    private var aggregator: RaceFieldAggregator
    private let virtualField: RaceBotField?
    private let humans: Set<String>
    private var virtualSeq = 0

    public init(race: OnlineRace, entries: [OnlineRaceEntry], pool: VirtualRowerPool?) {
        self.race = race
        let list = OnlineRoster.filled(entries, race: race, pool: pool).participants
        participants = list
        roster = RaceRosterIndex(participants: list)
        humans = Set(list.filter { !$0.isVirtual }.map(\.id))
        aggregator = RaceFieldAggregator(finishDistance: race.target.finishDistance)
        let context = VirtualRaceContext(raceId: race.id, startsAt: race.startsAt, target: race.target)
        let runs = list.filter(\.isVirtual).compactMap { p in pool?.rower(id: p.id).map { VirtualRaceSimulator.run($0, context: context) } }
        virtualField = runs.isEmpty ? nil : RaceBotField(virtual: runs, participants: list,
                                                         finishDistance: race.target.finishDistance)
    }

    /// Frame einer echten Person aufnehmen (uid aus dem Pfad); unbekannte uids und alte Nummern werden verworfen
    @discardableResult
    public mutating func receive(uid: String, wire: RaceWireFrame) -> Bool {
        guard humans.contains(uid), let f = RaceLiveWire.decode(wire, raceId: race.id, participantId: uid) else { return false }
        if let l = history[uid]?.last, f.seq <= l.seq { return false }
        history[uid, default: []].append(f)
        aggregator.receive(f)
        return true
    }

    /// Übersicht zur Serverzeit `serverNow`, wenn fällig (`full` = auch nach `fieldFull` schreiben)
    public mutating func tick(serverNow: TimeInterval) -> RaceFieldSnapshot? {
        let rt = serverNow - race.startsAt
        guard rt >= 0 else { return nil }
        if let field = virtualField {
            virtualSeq += 1
            for i in field.bots.indices {
                aggregator.receive(field.frame(of: i, raceId: race.id, seq: virtualSeq, raceTime: rt, sentAt: serverNow))
            }
        }
        return aggregator.tick(raceId: race.id, raceTime: rt, sentAt: serverNow, roster: roster)
    }

    /// Alle echten mit Frames im Ziel (bzw. Zeitrennen abgelaufen)?
    public func allHumansDone(serverNow: TimeInterval) -> Bool {
        if serverNow > race.startsAt + race.maxDuration { return true }
        let started = humans.filter { history[$0] != nil }
        guard !started.isEmpty else { return false }
        if case .time(let s) = race.target { return serverNow - race.startsAt > s + 10 }
        return started.allSatisfy { history[$0]?.last?.finished == true }
    }
}

/// Auffüllen beim Meldeschluss (`fill == .server`): Mindestfeld und Auswahl mit zentraler Rotation
/// (`VirtualRowerHistory`), Ergebnis als Anmeldungen mit Bahn.
public enum ServerFieldFill {
    public static func entries(race: OnlineRace, humans: [OnlineRaceEntry], pool: VirtualRowerPool,
                               history: VirtualRowerHistory, catalog: AppearanceCatalog = .current) -> (entries: [OnlineRaceEntry], field: TournamentField) {
        let real = OnlineRoster.participants(humans.filter { $0.source != .virtual })
        var config = TournamentFieldFiller.Config()
        config.defaultLevel = race.fillLevel
        let field = TournamentFieldFiller.fill(tournamentId: race.tournamentId ?? race.id, raceId: race.id,
                                               seed: UInt64(max(race.seed, 0)), real: real, pool: pool,
                                               startsAt: race.startsAt, history: history, config: config, catalog: catalog)
        let virtual = field.participants.filter(\.isVirtual).map {
            OnlineRaceEntry(id: $0.id, displayName: $0.displayName, source: .virtual, appearance: $0.appearance,
                            joinedAt: race.registrationCloses, lane: $0.lane)
        }
        return (virtual, field)
    }
}

/// Abo-Prüfung (Platzhalter, docs/SYNC.md „Rennen-Abo“): ohne Durchsetzung dürfen alle; mit Durchsetzung nur
/// Konten mit aktivem `users/{uid}/entitlements/races`.
public struct EntitlementPolicy: Sendable {
    public var enforce: Bool
    public init(enforce: Bool = false) { self.enforce = enforce }

    public func allows(_ status: EntitlementStatus?, at date: Date) -> Bool {
        guard enforce else { return true }
        return status?.isActive(at: date) ?? false
    }
}

/// Was der minütliche Takt mit einem Rennen tut
public enum TickAction: Equatable, Sendable {
    /// virtuelle auffüllen (Meldeschluss erreicht, `fill == .server`, noch keine virtuellen)
    case fill
    /// Abo prüfen und Anmeldungen ohne Berechtigung entfernen (beim Meldeschluss)
    case checkEntitlements
    /// Status „live“ setzen; bei grossen Feldern den Aggregator starten
    case goLive(startAggregator: Bool)
    /// Ergebnisse festschreiben (Kleinfeld nach dem Ende; grosses Feld nur, wenn der Aggregator es nicht tat)
    case finalize
}

public enum TickPlanner {
    /// Nachlauf nach dem Ende, bevor der Takt statt des Aggregators festschreibt (s)
    public static let aggregatorGrace: TimeInterval = 600

    public static func actions(race r: OnlineRace, serverNow t: TimeInterval, hasVirtualEntries: Bool,
                               entitlementsChecked: Bool, allHumansFinished: Bool) -> [TickAction] {
        guard r.status != .cancelled, r.status != .finished else { return [] }
        var out: [TickAction] = []
        if t >= r.registrationCloses && t < r.startsAt + r.maxDuration {
            if !entitlementsChecked { out.append(.checkEntitlements) }
            if r.fill == .server && !hasVirtualEntries { out.append(.fill) }
        }
        if r.status == .scheduled && t >= r.startsAt - OnlineRaceLimits.liveLead {
            out.append(.goLive(startAggregator: !r.isSmallField))
        }
        let end = r.startsAt + r.maxDuration
        if r.isSmallField {
            if t >= r.startsAt && (allHumansFinished || t >= end) { out.append(.finalize) }
        } else if t >= end + aggregatorGrace {
            out.append(.finalize)
        }
        return out
    }
}
