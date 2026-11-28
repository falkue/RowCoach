import Foundation

// Online-Rennen über Firebase (docs/MULTIPLAYER.md, „Umsetzung Firebase“): Form der Dokumente in Firestore und der
// Einträge in der Realtime Database, unabhängig vom SDK. Die App (Firebase-iOS-SDK), der Server (REST) und später
// Android setzen nur `RaceDocValue` in ihre eigenen Typen um; Logik und Tests liegen hier.
//
// Firestore                                         Realtime Database (europe-west1)
//   races/{raceId}            OnlineRace              meta/{raceId}            {startsAt, createdBy}
//     participants/{uid}      OnlineRaceEntry         members/{raceId}/{uid}   true (Lesen/Schreiben in live/)
//     results/{uid}           OnlineRaceResult        live/{raceId}/f/{uid}    RaceWireFrame {b, n, at}
//   raceCodes/{code}          {raceId}                live/{raceId}/online/{uid}  true, onDisconnect → entfernt
//   virtualHistory/{rowerId}  (nur Server)            live/{raceId}/field, fieldFull  (nur Server/Aggregator)

/// Feste Grenzen der Online-Rennen (gleich in den Regeln, firebase/*.rules*)
public enum OnlineRaceLimits {
    /// bis zu so vielen echten Teilnehmenden hören alle alle (kein Aggregator nötig, Spark-Tarif)
    public static let smallFieldMax = 30
    /// Meldeschluss vor dem Start (s): danach steht die Teilnehmerliste fest (Regeln: kein Anmelden/Abmelden mehr)
    public static let registrationCloseLead: TimeInterval = 60
    /// frühestens so lange vor dem Start dürfen Frames geschrieben werden (s)
    public static let liveLead: TimeInterval = 120
    /// so weit voraus darf ein Rennen angesetzt werden (s)
    public static let maxScheduleAhead: TimeInterval = 30 * 86400
    /// frühester Start beim Anlegen (s ab jetzt)
    public static let minScheduleAhead: TimeInterval = 120
    /// Ziel: Distanz 100 m … 42 195 m, Zeit 60 s … 2 h
    public static let distanceRange: ClosedRange<Double> = 100...42_195
    public static let timeRange: ClosedRange<Double> = 60...7200
    /// Anzeigename höchstens so lang (wie `RowerProfile`)
    public static let displayNameMax = 24
    public static let titleMax = 60
    /// Erscheinung als JSON-Text höchstens so lang (Regeln)
    public static let appearanceMax = 1500
    /// Einladungscode: Länge und Alphabet ohne verwechselbare Zeichen (0/O, 1/I/L)
    public static let inviteCodeLength = 8
    public static let inviteAlphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
}

// MARK: - Neutrale Dokumentwerte

/// Wert eines Dokumentfelds, unabhängig vom SDK (Firestore-Typen; Zeitstempel als Sekunden seit 1970)
public indirect enum RaceDocValue: Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case timestamp(TimeInterval)
    case map([String: RaceDocValue])
    case null
    /// Platzhalter „Serverzeit“ (Firestore `FieldValue.serverTimestamp()` bzw. REST `REQUEST_TIME`)
    case serverTimestamp

    public var string: String? { if case .string(let s) = self { return s }; return nil }
    public var bool: Bool? { if case .bool(let b) = self { return b }; return nil }
    public var map: [String: RaceDocValue]? { if case .map(let m) = self { return m }; return nil }
    public var int: Int? {
        switch self {
        case .int(let i): return i
        case .double(let d) where d.rounded() == d && abs(d) < 9e15: return Int(d)
        default: return nil
        }
    }
    public var double: Double? {
        switch self {
        case .int(let i): return Double(i)
        case .double(let d): return d
        default: return nil
        }
    }
    public var timestamp: TimeInterval? { if case .timestamp(let t) = self { return t }; return nil }
}

public typealias RaceDocument = [String: RaceDocValue]

extension RaceTarget {
    /// Dokumentform `{kind: "distance"|"time", value}` (Rennen über ein Programm gibt es online nicht)
    public var docValue: RaceDocValue {
        switch self {
        case .distance(let m): return .map(["kind": .string("distance"), "value": .double(m)])
        case .time(let s): return .map(["kind": .string("time"), "value": .double(s)])
        case .plan(let id): return .map(["kind": .string("plan"), "planId": .string(id)])
        }
    }

    public init?(doc: RaceDocValue?) {
        guard let m = doc?.map, let kind = m["kind"]?.string else { return nil }
        switch kind {
        case "distance": guard let v = m["value"]?.double else { return nil }; self = .distance(v)
        case "time": guard let v = m["value"]?.double else { return nil }; self = .time(v)
        case "plan": guard let id = m["planId"]?.string else { return nil }; self = .plan(id)
        default: return nil
        }
    }

    /// Zieldistanz (Distanzrennen)
    public var finishDistance: Double? { if case .distance(let m) = self { return m }; return nil }
}

// MARK: - Rennen

public enum OnlineRaceVisibility: String, Codable, Sendable, CaseIterable {
    /// in der Liste kommender Rennen für alle Angemeldeten
    case open = "public"
    /// nur mit Einladungscode auffindbar
    case invite = "private"
}

public enum OnlineRaceStatus: String, Codable, Sendable {
    case scheduled, live, finished, cancelled
}

/// Wer füllt das Feld mit virtuellen Teilnehmenden auf (docs/MULTIPLAYER.md „Virtuelle Teilnehmende“)
public enum OnlineRaceFill: String, Codable, Sendable {
    /// keine virtuellen
    case none
    /// jedes Gerät rechnet beim Meldeschluss dasselbe Feld (Spark-Tarif, ohne Server; ohne zentrale Rotation)
    case client
    /// die Server-Funktion schreibt die virtuellen nach `participants/` (Blaze)
    case server
}

/// Rennen in Firestore (`races/{id}`)
public struct OnlineRace: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var courseId: String
    /// mindestens diese Fassung des Kartenpakets (nil = jede)
    public var courseVersion: Int?
    public var target: RaceTarget
    /// gemeinsamer Start (Serverzeit, s seit 1970)
    public var startsAt: TimeInterval
    /// höchstens so viele echte Teilnehmende
    public var maxParticipants: Int
    public var visibility: OnlineRaceVisibility
    public var status: OnlineRaceStatus
    public var createdBy: String
    /// Saat für Mindestfeld und Auswahl der virtuellen (0 ≤ seed < 2³¹, in JSON/JS ohne Rundung)
    public var seed: Int
    public var fill: OnlineRaceFill
    /// Niveau für die virtuellen (2000-m-Zeit in s), sonst Median des Pools
    public var fillLevel: Double?
    public var tournamentId: String?
    /// Anlagezeit (Serverzeit), beim Lesen gesetzt
    public var createdAt: TimeInterval?

    public init(id: String = "", title: String, courseId: String, courseVersion: Int? = nil, target: RaceTarget,
                startsAt: TimeInterval, maxParticipants: Int = 8, visibility: OnlineRaceVisibility = .open,
                status: OnlineRaceStatus = .scheduled, createdBy: String, seed: Int = 1, fill: OnlineRaceFill = .none,
                fillLevel: Double? = nil, tournamentId: String? = nil, createdAt: TimeInterval? = nil) {
        self.id = id
        self.title = title
        self.courseId = courseId
        self.courseVersion = courseVersion
        self.target = target
        self.startsAt = startsAt
        self.maxParticipants = maxParticipants
        self.visibility = visibility
        self.status = status
        self.createdBy = createdBy
        self.seed = seed
        self.fill = fill
        self.fillLevel = fillLevel
        self.tournamentId = tournamentId
        self.createdAt = createdAt
    }

    /// Rennen für Koordinator und Szene. `lanes` = Platz für echte und (beim Auffüllen) virtuelle Teilnehmende.
    public var race: Race {
        Race(id: id, tournamentId: tournamentId, courseId: courseId, courseVersion: courseVersion, target: target,
             scheduledStart: startsAt,
             lanes: maxParticipants + (fill == .none ? 0 : TournamentFieldFiller.Config().maxField))
    }

    /// Alle echten hören alle (≤ 30); darüber Nachbarschafts-Abo und Übersicht vom Aggregator
    public var isSmallField: Bool { maxParticipants <= OnlineRaceLimits.smallFieldMax }

    public var registrationCloses: TimeInterval { startsAt - OnlineRaceLimits.registrationCloseLead }

    public func registrationOpen(serverNow: TimeInterval) -> Bool {
        status == .scheduled && serverNow < registrationCloses
    }

    /// grobe Obergrenze der Renndauer (s): danach gilt das Rennen als vorbei (Liste, Server)
    public var maxDuration: TimeInterval {
        switch target {
        case .distance(let m): return m / 500 * 240 + 300   // 4:00/500 m + 5 min
        case .time(let s): return s + 300
        case .plan: return 3 * 3600
        }
    }

    public enum Phase: Equatable, Sendable {
        /// Anmeldung offen
        case open
        /// Meldeschluss bis Start (Countdown)
        case closing
        /// Rennen läuft
        case running
        /// vorbei (oder abgesagt)
        case over
    }

    public func phase(serverNow t: TimeInterval) -> Phase {
        if status == .cancelled || status == .finished { return .over }
        if t < registrationCloses { return .open }
        if t < startsAt { return .closing }
        return t < startsAt + maxDuration ? .running : .over
    }

    // MARK: Dokument

    public var document: RaceDocument {
        var d: RaceDocument = [
            "title": .string(title), "courseId": .string(courseId), "target": target.docValue,
            "startsAt": .timestamp(startsAt), "maxParticipants": .int(maxParticipants),
            "visibility": .string(visibility.rawValue), "status": .string(status.rawValue),
            "createdBy": .string(createdBy), "seed": .int(seed), "fill": .string(fill.rawValue),
            "createdAt": createdAt.map { .timestamp($0) } ?? .serverTimestamp,
        ]
        if let v = courseVersion { d["courseVersion"] = .int(v) }
        if let l = fillLevel { d["fillLevel"] = .double(l) }
        if let t = tournamentId { d["tournamentId"] = .string(t) }
        return d
    }

    public init?(id: String, document d: RaceDocument) {
        guard let title = d["title"]?.string, let courseId = d["courseId"]?.string,
              let target = RaceTarget(doc: d["target"]), let startsAt = d["startsAt"]?.timestamp,
              let maxP = d["maxParticipants"]?.int, let createdBy = d["createdBy"]?.string else { return nil }
        self.init(id: id, title: title, courseId: courseId, courseVersion: d["courseVersion"]?.int, target: target,
                  startsAt: startsAt, maxParticipants: maxP,
                  visibility: d["visibility"]?.string.flatMap(OnlineRaceVisibility.init(rawValue:)) ?? .invite,
                  status: d["status"]?.string.flatMap(OnlineRaceStatus.init(rawValue:)) ?? .scheduled,
                  createdBy: createdBy, seed: d["seed"]?.int ?? 1,
                  fill: d["fill"]?.string.flatMap(OnlineRaceFill.init(rawValue:)) ?? .none,
                  fillLevel: d["fillLevel"]?.double, tournamentId: d["tournamentId"]?.string,
                  createdAt: d["createdAt"]?.timestamp)
    }

    /// Prüft ein neues Rennen wie die Regeln (für eine verständliche Meldung vor dem Absenden)
    public func validationError(serverNow: TimeInterval) -> String? {
        if title.isEmpty || title.count > OnlineRaceLimits.titleMax { return "title" }
        switch target {
        case .distance(let m): if !OnlineRaceLimits.distanceRange.contains(m) { return "distance" }
        case .time(let s): if !OnlineRaceLimits.timeRange.contains(s) { return "time" }
        case .plan: return "target"
        }
        if startsAt < serverNow + OnlineRaceLimits.minScheduleAhead - 5 { return "tooSoon" }
        if startsAt > serverNow + OnlineRaceLimits.maxScheduleAhead { return "tooLate" }
        if maxParticipants < 2 || maxParticipants > OnlineRaceLimits.smallFieldMax { return "participants" }
        if fill == .server { return "fill" }
        return nil
    }

    /// Neue Saat für ein Rennen (0 < seed < 2³¹)
    public static func randomSeed<G: RandomNumberGenerator>(using g: inout G) -> Int { Int.random(in: 1..<(1 << 31), using: &g) }
}

/// Einladungscode für private Rennen: 8 Zeichen ohne verwechselbare Zeichen (≈ 8,5 · 10¹¹ Möglichkeiten).
/// `raceCodes/{code}` = `{raceId}`; nur einzeln lesbar (keine Liste), damit sich Codes nicht aufzählen lassen.
public enum RaceInviteCode {
    public static func make<G: RandomNumberGenerator>(using g: inout G) -> String {
        String((0..<OnlineRaceLimits.inviteCodeLength).map { _ in OnlineRaceLimits.inviteAlphabet.randomElement(using: &g)! })
    }

    /// Eingabe vereinheitlichen (Gross, ohne Leer- und Trennzeichen, O→0 entfällt: 0 ist nicht im Alphabet)
    public static func normalize(_ s: String) -> String {
        String(s.uppercased().filter { OnlineRaceLimits.inviteAlphabet.contains($0) })
    }

    public static func isValid(_ s: String) -> Bool {
        s.count == OnlineRaceLimits.inviteCodeLength && s.allSatisfy { OnlineRaceLimits.inviteAlphabet.contains($0) }
    }
}

// MARK: - Anmeldung

/// Anmeldung in `races/{id}/participants/{uid}`. Echte Personen schreiben ihre eigene (ohne Bahn – die Bahn folgt
/// aus der Reihenfolge der Anmeldung, damit zwei gleichzeitige Anmeldungen nie um dieselbe Bahn streiten);
/// virtuelle schreibt der Server mit fester Bahn.
public struct OnlineRaceEntry: Equatable, Sendable, Identifiable {
    public var id: String
    public var displayName: String
    public var source: RaceParticipant.Source
    public var appearance: RowerAppearance?
    /// Anmeldezeit (Serverzeit); fehlt kurz nach dem eigenen Schreiben (Serverzeit noch ausstehend)
    public var joinedAt: TimeInterval?
    /// nur virtuelle (vom Server)
    public var lane: Int?

    public init(id: String, displayName: String, source: RaceParticipant.Source = .human,
                appearance: RowerAppearance? = nil, joinedAt: TimeInterval? = nil, lane: Int? = nil) {
        self.id = id
        self.displayName = displayName
        self.source = source
        self.appearance = appearance
        self.joinedAt = joinedAt
        self.lane = lane
    }

    /// Eigene Anmeldung aus dem Profil (Erscheinung nach der Datenschutzregel: `RowerProfile.publicAppearance`)
    public static func mine(uid: String, profile: RowerProfile) -> OnlineRaceEntry {
        OnlineRaceEntry(id: uid, displayName: String(profile.displayName.prefix(OnlineRaceLimits.displayNameMax)),
                        appearance: profile.publicAppearance)
    }

    public var document: RaceDocument {
        var d: RaceDocument = ["displayName": .string(String(displayName.prefix(OnlineRaceLimits.displayNameMax))),
                               "source": .string(source.rawValue),
                               "joinedAt": joinedAt.map { .timestamp($0) } ?? .serverTimestamp]
        if let a = appearance, let json = Self.encodeAppearance(a) { d["appearance"] = .string(json) }
        if let l = lane { d["lane"] = .int(l) }
        return d
    }

    public init?(id: String, document d: RaceDocument) {
        guard let name = d["displayName"]?.string else { return nil }
        let source = d["source"]?.string.map { RaceParticipant.Source(rawValue: $0) ?? .bot } ?? .human
        self.init(id: id, displayName: name, source: source,
                  appearance: d["appearance"]?.string.flatMap(Self.decodeAppearance),
                  joinedAt: d["joinedAt"]?.timestamp, lane: d["lane"]?.int)
    }

    /// Erscheinung als kompakter JSON-Text (≤ 1500 Zeichen, sonst ohne)
    public static func encodeAppearance(_ a: RowerAppearance) -> String? {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        guard let data = try? enc.encode(a), let s = String(data: data, encoding: .utf8),
              s.count <= OnlineRaceLimits.appearanceMax else { return nil }
        return s
    }

    public static func decodeAppearance(_ s: String) -> RowerAppearance? {
        try? JSONDecoder().decode(RowerAppearance.self, from: Data(s.utf8))
    }
}

/// Teilnehmerliste aus den Anmeldungen: echte nach (Anmeldezeit, uid) auf die Bahnen 1…n, danach die virtuellen
/// (Bahn vom Server bzw. vom Auffüllen auf dem Gerät). Auf allen Geräten gleich.
public enum OnlineRoster {
    public static func participants(_ entries: [OnlineRaceEntry]) -> [RaceParticipant] {
        let humans = entries.filter { $0.source != .virtual }
            .sorted { ($0.joinedAt ?? .infinity, $0.id) < ($1.joinedAt ?? .infinity, $1.id) }
        var list = humans.enumerated().map { i, e in
            RaceParticipant(id: e.id, displayName: e.displayName, lane: i + 1, source: e.source == .virtual ? .human : e.source,
                            appearance: e.appearance)
        }
        var next = list.count + 1
        let virtuals = entries.filter { $0.source == .virtual }
            .sorted { ($0.lane ?? Int.max, $0.id) < ($1.lane ?? Int.max, $1.id) }
        for v in virtuals {
            let lane = max(v.lane ?? next, next)
            list.append(RaceParticipant(id: v.id, displayName: v.displayName, lane: lane, source: .virtual,
                                        appearance: v.appearance))
            next = lane + 1
        }
        return list
    }

    /// Mit virtuellen aufgefüllte Liste, wenn das Rennen auf dem Gerät auffüllt (`fill == .client`): jedes Gerät
    /// rechnet aus Rennen, Saat und den echten Anmeldungen dasselbe Feld (ohne zentrale Rotation, also mit leerem
    /// Verlauf). Vom Server geschriebene virtuelle gehen vor.
    public static func filled(_ entries: [OnlineRaceEntry], race: OnlineRace, pool: VirtualRowerPool?) -> (participants: [RaceParticipant], field: TournamentField?) {
        let list = participants(entries)
        guard race.fill == .client, let pool, !list.contains(where: \.isVirtual) else { return (list, nil) }
        var config = TournamentFieldFiller.Config()
        config.defaultLevel = race.fillLevel
        let field = TournamentFieldFiller.fill(tournamentId: race.tournamentId ?? race.id, raceId: race.id,
                                               seed: UInt64(max(race.seed, 0)), real: list, pool: pool,
                                               startsAt: race.startsAt, config: config)
        return (field.participants, field)
    }
}

// MARK: - Ergebnisse

/// Ergebnis in `races/{id}/results/{uid}`. Im Kleinfeld-Modus schreibt jede Person ihr eigenes **vorläufiges**
/// (`provisional == true`); endgültig (`provisional == false`, mit Platz) schreibt nur der Server nach der
/// Plausibilitätsprüfung – die Regeln lassen Clients nichts anderes zu.
public struct OnlineRaceResult: Equatable, Sendable, Identifiable {
    public var id: String
    public var distance: Double
    /// Zielzeit (Distanzrennen) bzw. Renndauer (Zeitrennen)
    public var time: TimeInterval?
    public var finished: Bool
    public var provisional: Bool
    /// nur endgültig: Platz und Hinweise der Prüfung (z. B. „pace“, „jump“, „backwards“)
    public var place: Int?
    public var flags: [String]
    public var source: RaceParticipant.Source
    public var submittedAt: TimeInterval?

    public init(id: String, distance: Double, time: TimeInterval?, finished: Bool, provisional: Bool = true,
                place: Int? = nil, flags: [String] = [], source: RaceParticipant.Source = .human,
                submittedAt: TimeInterval? = nil) {
        self.id = id
        self.distance = distance
        self.time = time
        self.finished = finished
        self.provisional = provisional
        self.place = place
        self.flags = flags
        self.source = source
        self.submittedAt = submittedAt
    }

    public init(_ r: RaceResult, provisional: Bool = true, flags: [String] = [], source: RaceParticipant.Source = .human) {
        self.init(id: r.participantId, distance: r.distance, time: r.time, finished: r.finished,
                  provisional: provisional, place: provisional ? nil : r.place, flags: flags, source: source)
    }

    public var document: RaceDocument {
        var d: RaceDocument = ["distance": .double((distance * 10).rounded() / 10), "finished": .bool(finished),
                               "provisional": .bool(provisional), "source": .string(source.rawValue),
                               "at": submittedAt.map { .timestamp($0) } ?? .serverTimestamp]
        if let t = time { d["time"] = .double((t * 1000).rounded() / 1000) }
        if let p = place { d["place"] = .int(p) }
        if !flags.isEmpty { d["flags"] = .string(flags.joined(separator: ",")) }
        return d
    }

    public init?(id: String, document d: RaceDocument) {
        guard let distance = d["distance"]?.double, let finished = d["finished"]?.bool else { return nil }
        self.init(id: id, distance: distance, time: d["time"]?.double, finished: finished,
                  provisional: d["provisional"]?.bool ?? true, place: d["place"]?.int,
                  flags: d["flags"]?.string.map { $0.split(separator: ",").map(String.init) } ?? [],
                  source: d["source"]?.string.map { RaceParticipant.Source(rawValue: $0) ?? .bot } ?? .human,
                  submittedAt: d["at"]?.timestamp)
    }

    public var raceResult: RaceResult {
        RaceResult(participantId: id, place: place ?? 0, distance: distance, time: time, finished: finished)
    }
}

/// Zeile der Ergebnisliste nach einem Online-Rennen
public struct OnlineRaceStanding: Equatable, Sendable, Identifiable {
    public enum Status: String, Sendable {
        /// vom Server festgeschrieben
        case final
        /// selbst gemeldet bzw. auf dem Gerät simuliert, noch nicht bestätigt
        case provisional
        /// nur aus den letzten empfangenen Frames (keine Meldung eingegangen)
        case estimated
    }

    public var participant: RaceParticipant
    public var place: Int
    public var distance: Double
    public var time: TimeInterval?
    public var finished: Bool
    public var status: Status
    public var flags: [String]
    public var id: String { participant.id }
}

public enum OnlineRaceResults {
    /// Ergebnisliste: endgültige Ergebnisse des Servers vor gemeldeten vorläufigen vor dem, was das Gerät gesehen hat
    /// (`local`, z. B. `RaceCoordinator.standings()`), dazu die auf dem Gerät simulierten virtuellen (`virtualRuns`).
    /// Ist alles endgültig, gelten die Plätze des Servers; sonst wird nach `RaceCoordinator.ranking` neu gereiht.
    public static func merge(target: RaceTarget, roster: [RaceParticipant], submitted: [OnlineRaceResult],
                             local: [RaceResult] = [], virtualRuns: [VirtualRaceRun] = []) -> [OnlineRaceStanding] {
        var rows: [String: (RaceResult, OnlineRaceStanding.Status, [String])] = [:]
        for r in local { rows[r.participantId] = (r, .estimated, []) }
        let timeRace: Bool
        if case .time = target { timeRace = true } else { timeRace = false }
        for v in virtualRuns where rows[v.rowerId] == nil || rows[v.rowerId]?.1 == .estimated {
            let time: TimeInterval?
            if case .time(let s) = target { time = s } else { time = v.finishTime }
            rows[v.rowerId] = (RaceResult(participantId: v.rowerId, place: 0, distance: v.finalDistance, time: time,
                                          finished: timeRace || v.finished), .provisional, [])
        }
        for s in submitted {
            if let existing = rows[s.id], existing.1 == .final, s.provisional { continue }
            rows[s.id] = (s.raceResult, s.provisional ? .provisional : .final, s.flags)
        }
        let byId = Dictionary(roster.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let allFinal = !rows.isEmpty && rows.values.allSatisfy { $0.1 == .final && $0.0.place > 0 }
        let order: [String]
        if allFinal {
            order = rows.values.sorted { ($0.0.place, $0.0.participantId) < ($1.0.place, $1.0.participantId) }.map(\.0.participantId)
        } else {
            order = RaceCoordinator.ranking(entries: rows.values.map { ($0.0.participantId, $0.0.distance, $0.0.finished, $0.0.time) },
                                            target: target)
        }
        return order.enumerated().compactMap { i, id in
            guard let (r, status, flags) = rows[id] else { return nil }
            let p = byId[id] ?? RaceParticipant(id: id, displayName: id, lane: 0,
                                                source: VirtualRowerPool.isVirtualId(id) ? .virtual : .human)
            return OnlineRaceStanding(participant: p, place: allFinal ? r.place : i + 1, distance: r.distance,
                                      time: r.time, finished: r.finished, status: status, flags: flags)
        }
    }

    /// Gesamtstatus einer Liste: endgültig nur, wenn jede Zeile endgültig ist
    public static func isFinal(_ rows: [OnlineRaceStanding]) -> Bool {
        !rows.isEmpty && rows.allSatisfy { $0.status == .final }
    }
}

// MARK: - Realtime Database: Frames

/// Ein Frame in `live/{raceId}/f/{uid}`: Binärframe (`RaceCompactFrame`) als Base64 in `b`, die laufende Nummer
/// noch einmal lesbar in `n` (die Regeln verlangen `n` > bisheriges `n`, Binärdaten können sie nicht lesen) und die
/// Serverzeit in `at` (Millisekunden, `ServerValue.timestamp`). ≈ 24–32 + 20 Byte JSON.
public struct RaceWireFrame: Equatable, Sendable {
    public var b: String
    public var n: Int
    /// Serverzeit des Schreibens (s seit 1970); beim Senden nil = Platzhalter `{".sv": "timestamp"}`
    public var at: TimeInterval?

    public init(b: String, n: Int, at: TimeInterval? = nil) {
        self.b = b
        self.n = n
        self.at = at
    }

    /// Wert für die Datenbank (`at` als Serverzeit-Platzhalter); `serverTimestamp` ist je SDK verschieden
    public func value(serverTimestamp: Any) -> [String: Any] {
        ["b": b, "n": n, "at": serverTimestamp]
    }

    /// Aus einem gelesenen Wert (Dictionary mit b, n, at in ms)
    public init?(value: Any?) {
        guard let d = value as? [String: Any], let b = d["b"] as? String else { return nil }
        let n = (d["n"] as? NSNumber)?.intValue ?? (d["n"] as? Int) ?? 0
        let at = (d["at"] as? NSNumber)?.doubleValue ?? (d["at"] as? Double)
        self.init(b: b, n: n, at: at.map { $0 / 1000 })
    }
}

public enum RaceLiveWire {
    public static func framePath(raceId: String, uid: String) -> String { "live/\(raceId)/f/\(uid)" }
    public static func presencePath(raceId: String, uid: String) -> String { "live/\(raceId)/online/\(uid)" }
    public static func presenceRoot(raceId: String) -> String { "live/\(raceId)/online" }
    public static func fieldPath(raceId: String) -> String { "live/\(raceId)/field" }
    public static func fieldFullPath(raceId: String) -> String { "live/\(raceId)/fieldFull" }
    public static func memberPath(raceId: String, uid: String) -> String { "members/\(raceId)/\(uid)" }
    public static func metaPath(raceId: String) -> String { "meta/\(raceId)" }

    /// Frame → Draht. Der Kurzindex im Binärframe bleibt 0: die uid steht im Pfad.
    public static func encode(_ f: LiveFrame) -> RaceWireFrame {
        RaceWireFrame(b: Data(RaceCompactFrame.encode(f, index: 0)).base64EncodedString(), n: f.seq)
    }

    /// Draht → Frame (uid aus dem Pfad); nil bei unlesbaren Daten
    public static func decode(_ w: RaceWireFrame, raceId: String, participantId: String) -> LiveFrame? {
        guard let data = Data(base64Encoded: w.b),
              var f = RaceCompactFrame.decode([UInt8](data), raceId: raceId, participantId: participantId,
                                              sentAt: w.at ?? 0) else { return nil }
        // die lesbare Nummer ist massgeblich (die Regeln prüfen sie)
        if w.n > 0 { f.seq = w.n }
        return f
    }

    /// Länge des Base64-Texts, die die Regeln zulassen (18 bzw. 22 Byte → 24 bzw. 32 Zeichen)
    public static let allowedLengths: Set<Int> = [24, 32]
}

extension RaceCompactFrame {
    /// Binärframe lesen, wenn die uid bekannt ist (Pfad in der Datenbank) – ohne Teilnehmerliste
    public static func decode(_ b: [UInt8], raceId: String, participantId: String, sentAt: TimeInterval = 0) -> LiveFrame? {
        decode(b, raceId: raceId, roster: RaceRosterIndex(participants: [RaceParticipant(id: participantId, displayName: "", lane: 0)]),
               sentAt: sentAt).map { f in
            var f = f
            f.participantId = participantId
            return f
        }
    }
}

// MARK: - Zugang

/// Wer darf online rennen? Konto nötig; das Abo prüft später `EntitlementProvider` (heute No-op). Im Debug-Build
/// (rowcoach-dev) sind alle Rennen erlaubt.
public enum OnlineRaceAccess: Equatable, Sendable {
    case allowed
    case needsAccount
    case needsSubscription
    case unavailable

    public static func check(serverConfigured: Bool, signedIn: Bool, entitled: Bool, debugBuild: Bool) -> OnlineRaceAccess {
        guard serverConfigured else { return .unavailable }
        guard signedIn else { return .needsAccount }
        return entitled || debugBuild ? .allowed : .needsSubscription
    }
}
