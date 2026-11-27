import Foundation

// Persistente Ranglisten über Rennen: Ergebnisse je Teilnehmendem (echt und virtuell), Bestzeiten je Strecke und
// Distanz, Saisonwertung, Filter „Alle“ / „Nur echte Teilnehmende“. Virtuelle sammeln Ergebnisse wie echte; ihr
// Ergebnis stammt aus `VirtualRaceSimulator` (auf allen Geräten gleich). docs/MULTIPLAYER.md „Virtuelle Teilnehmende“.

/// Filter für Ergebnis- und Ranglisten
public enum RankingFilter: String, Codable, Sendable, CaseIterable {
    /// alle Teilnehmenden (Standard: so sah das Rennen aus)
    case all
    /// nur echte Teilnehmende (Plätze neu gezählt)
    case realOnly
}

/// Rudersaison wie bei Concept2: 1. Mai bis 30. April (UTC), Kennung „2026/27“
public enum RowingSeason {
    public static func id(at t: TimeInterval) -> String {
        let c = DetMath.civil(days: DetMath.dayIndex(t))
        let start = c.month >= 5 ? c.year : c.year - 1
        let next = (start + 1) % 100
        return "\(start)/\(next < 10 ? "0" : "")\(next)"
    }
}

/// Ein Ergebnis einer Person in einem Rennen
public struct RaceRecordEntry: Codable, Equatable, Sendable, Identifiable {
    public var raceId: String
    public var tournamentId: String?
    public var courseId: String
    /// Start (UTC)
    public var date: TimeInterval
    public var target: RaceTarget
    public var participantId: String
    public var displayName: String
    /// ISO 3166-1 alpha-2, nur wenn eine Flagge gezeigt wird
    public var country: String?
    public var isVirtual: Bool
    public var place: Int
    public var fieldSize: Int
    /// Zielzeit (Distanzrennen) bzw. nil
    public var time: TimeInterval?
    public var distance: Double
    public var finished: Bool

    public var id: String { raceId + "|" + participantId }

    public init(raceId: String, tournamentId: String?, courseId: String, date: TimeInterval, target: RaceTarget,
                participantId: String, displayName: String, country: String?, isVirtual: Bool, place: Int,
                fieldSize: Int, time: TimeInterval?, distance: Double, finished: Bool) {
        self.raceId = raceId
        self.tournamentId = tournamentId
        self.courseId = courseId
        self.date = date
        self.target = target
        self.participantId = participantId
        self.displayName = displayName
        self.country = country
        self.isVirtual = isVirtual
        self.place = place
        self.fieldSize = fieldSize
        self.time = time
        self.distance = distance
        self.finished = finished
    }

    /// Punkte der Saisonwertung: 100 für den Sieg, linear bis 1 für den letzten Platz
    public var points: Double {
        guard fieldSize > 1 else { return 100 }
        return 1 + 99 * Double(fieldSize - place) / Double(fieldSize - 1)
    }
}

/// Eine Zeile einer Rangliste
public struct RankingRow: Equatable, Sendable, Identifiable {
    public var rank: Int
    public var participantId: String
    public var displayName: String
    public var country: String?
    public var isVirtual: Bool
    /// Bestzeit (Distanz-Ranglisten) bzw. Punkte (Saison)
    public var value: Double
    public var races: Int
    public var id: String { participantId }
}

/// Alle bekannten Ergebnisse (App: lokal gespeichert; Server: Firestore `results`)
public struct RaceRankingBook: Codable, Equatable, Sendable {
    public var entries: [RaceRecordEntry]
    /// Saisonwertung: nur die besten N Ergebnisse je Person zählen (virtuelle fahren häufiger als echte)
    public static let seasonBestOf = 10

    public init(entries: [RaceRecordEntry] = []) { self.entries = entries }

    /// Ergebnisse eines Rennens eintragen (vorhandene Einträge desselben Rennens werden ersetzt)
    public mutating func add(results: [RaceResult], race: Race, startsAt: TimeInterval,
                             participants: [RaceParticipant]) {
        let byId = Dictionary(participants.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        entries.removeAll { $0.raceId == race.id }
        for r in results {
            let p = byId[r.participantId]
            let a = p?.appearance
            entries.append(RaceRecordEntry(raceId: race.id, tournamentId: race.tournamentId, courseId: race.courseId,
                                           date: startsAt, target: race.target, participantId: r.participantId,
                                           displayName: p?.displayName ?? r.participantId,
                                           country: (a?.flagOnBoat ?? false) || (a?.flagOnShirt ?? false) ? a?.nationality : nil,
                                           isVirtual: p?.isVirtual ?? VirtualRowerPool.isVirtualId(r.participantId),
                                           place: r.place, fieldSize: results.count, time: r.time,
                                           distance: r.distance, finished: r.finished))
        }
    }

    /// Ergebnisliste eines Rennens; bei `realOnly` ohne virtuelle, Plätze neu gezählt
    public func results(raceId: String, filter: RankingFilter = .all) -> [RaceRecordEntry] {
        let list = entries.filter { $0.raceId == raceId && (filter == .all || !$0.isVirtual) }.sorted { $0.place < $1.place }
        guard filter == .realOnly else { return list }
        return list.enumerated().map { i, e in var c = e; c.place = i + 1; return c }
    }

    /// Bestzeiten über eine Distanz (optional je Strecke und Saison), je Person die beste
    public func leaderboard(distance: Double, courseId: String? = nil, season: String? = nil,
                            filter: RankingFilter = .all) -> [RankingRow] {
        var best: [String: (e: RaceRecordEntry, n: Int)] = [:]
        for e in entries {
            guard case .distance(let m) = e.target, m == distance, e.finished, let t = e.time else { continue }
            if let c = courseId, e.courseId != c { continue }
            if let s = season, RowingSeason.id(at: e.date) != s { continue }
            if filter == .realOnly, e.isVirtual { continue }
            if let b = best[e.participantId] {
                best[e.participantId] = (t < (b.e.time ?? .infinity) ? e : b.e, b.n + 1)
            } else {
                best[e.participantId] = (e, 1)
            }
        }
        let sorted = best.values.sorted { a, b in
            let ta = a.e.time ?? .infinity, tb = b.e.time ?? .infinity
            return ta != tb ? ta < tb : a.e.participantId < b.e.participantId
        }
        return sorted.enumerated().map { i, x in
            RankingRow(rank: i + 1, participantId: x.e.participantId, displayName: x.e.displayName,
                       country: x.e.country, isVirtual: x.e.isVirtual, value: x.e.time ?? 0, races: x.n)
        }
    }

    /// Saisonwertung: Summe der besten `seasonBestOf` Punktzahlen je Person
    public func seasonStandings(season: String, courseId: String? = nil, filter: RankingFilter = .all) -> [RankingRow] {
        var byPerson: [String: [RaceRecordEntry]] = [:]
        for e in entries where RowingSeason.id(at: e.date) == season {
            if let c = courseId, e.courseId != c { continue }
            if filter == .realOnly, e.isVirtual { continue }
            byPerson[e.participantId, default: []].append(e)
        }
        let rows = byPerson.map { id, list -> (String, Double, RaceRecordEntry, Int) in
            let pts = list.map(\.points).sorted(by: >).prefix(Self.seasonBestOf)
            var sum = 0.0
            for p in pts { sum += p }
            return (id, (sum * 10).rounded() / 10, list.max { $0.date < $1.date }!, list.count)
        }.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
        return rows.enumerated().map { i, r in
            RankingRow(rank: i + 1, participantId: r.0, displayName: r.2.displayName, country: r.2.country,
                       isVirtual: r.2.isVirtual, value: r.1, races: r.3)
        }
    }

    /// Verlauf einer Person (neueste zuerst)
    public func history(participantId: String) -> [RaceRecordEntry] {
        entries.filter { $0.participantId == participantId }.sorted { $0.date > $1.date }
    }

    /// Rotation: wann virtuelle Personen zuletzt gefahren sind
    public var virtualHistory: VirtualRowerHistory {
        var h = VirtualRowerHistory()
        for e in entries where e.isVirtual { h.record([e.participantId], at: e.date) }
        return h
    }

    // MARK: Speichern

    public func encoded() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return try enc.encode(self)
    }

    public static func decode(_ data: Data) -> RaceRankingBook? { try? JSONDecoder().decode(RaceRankingBook.self, from: data) }
}
