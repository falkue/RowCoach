import Foundation

// Rennen und Turniere gegen andere Ruderer (Grundlage für einen späteren Server, voraussichtlich Firebase).
// Nur Modelle: plattformunabhängig, Codable (JSON wie auf dem Server), keine Abhängigkeit vom Transport.
// Ablauf und Aufbau: docs/MULTIPLAYER.md.

/// Turnier: mehrere Rennen auf einer Strecke (z. B. Vorläufe und Finale)
public struct Tournament: Codable, Equatable, Sendable, Identifiable {
    public enum Format: String, Codable, Sendable {
        /// ein Rennen für alle
        case singleRace
        /// Vorläufe, danach Finale der Besten
        case heats
    }

    public var id: String
    public var title: String
    public var courseId: String
    /// Fassung des Kartenpakets, auf der gerudert wird (nil = jede); alle brauchen dieselbe Strecke
    public var courseVersion: Int?
    /// geplanter Beginn (Serverzeit, Sekunden seit 1970)
    public var startsAt: TimeInterval
    public var format: Format
    public var raceIds: [String]

    public init(id: String, title: String, courseId: String, courseVersion: Int? = nil, startsAt: TimeInterval,
                format: Format = .singleRace, raceIds: [String] = []) {
        self.id = id
        self.title = title
        self.courseId = courseId
        self.courseVersion = courseVersion
        self.startsAt = startsAt
        self.format = format
        self.raceIds = raceIds
    }
}

/// Ziel eines Rennens
public enum RaceTarget: Codable, Equatable, Sendable {
    /// feste Distanz (m): gewinnt, wer zuerst ankommt
    case distance(Double)
    /// feste Zeit (s): gewinnt, wer am weitesten kommt
    case time(TimeInterval)
    /// Trainingsprogramm (`WorkoutPlan.id`), gewertet nach Gesamtdistanz bzw. Zeit des Programms
    case plan(String)

    enum CodingKeys: String, CodingKey { case kind, value, planId }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "distance": self = .distance(try c.decode(Double.self, forKey: .value))
        case "time": self = .time(try c.decode(Double.self, forKey: .value))
        default: self = .plan(try c.decode(String.self, forKey: .planId))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .distance(let m):
            try c.encode("distance", forKey: .kind)
            try c.encode(m, forKey: .value)
        case .time(let s):
            try c.encode("time", forKey: .kind)
            try c.encode(s, forKey: .value)
        case .plan(let id):
            try c.encode("plan", forKey: .kind)
            try c.encode(id, forKey: .planId)
        }
    }
}

/// Ein Rennen: Strecke, Ziel, gemeinsamer Start
public struct Race: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var tournamentId: String?
    public var courseId: String
    /// Fassung des Kartenpakets (nil = jede)
    public var courseVersion: Int?
    public var target: RaceTarget
    /// gemeinsamer Start (Serverzeit, Sekunden seit 1970); nil = Start mit dem ersten Schlag (z. B. gegen die Bestfahrt)
    public var scheduledStart: TimeInterval?
    /// Anzahl Bahnen (Teilnehmende je Rennen)
    public var lanes: Int

    public init(id: String, tournamentId: String? = nil, courseId: String, courseVersion: Int? = nil,
                target: RaceTarget, scheduledStart: TimeInterval? = nil, lanes: Int = 6) {
        self.id = id
        self.tournamentId = tournamentId
        self.courseId = courseId
        self.courseVersion = courseVersion
        self.target = target
        self.scheduledStart = scheduledStart
        self.lanes = lanes
    }
}

/// Teilnehmende eines Rennens
public struct RaceParticipant: Codable, Equatable, Hashable, Sendable, Identifiable {
    public enum Source: String, Codable, Sendable {
        /// echte Person an ihrem Gerät
        case human
        /// Wiedergabe einer gespeicherten Fahrt (z. B. die eigene Bestfahrt)
        case ghost
        /// computergesteuert (gleichmässiges Tempo)
        case bot
        /// virtuelle Teilnehmende aus dem festen Pool (`VirtualRowerPool`), immer gekennzeichnet
        /// (docs/MULTIPLAYER.md „Virtuelle Teilnehmende“)
        case virtual

        /// Unbekannte Werte (neuere Absender) gelten als `bot`, damit ältere Clients die Teilnehmerliste weiter lesen
        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Source(rawValue: raw) ?? .bot
        }
    }

    public var id: String
    public var displayName: String
    /// Bahn 1…lanes
    public var lane: Int
    public var source: Source
    /// Figur, Boot und Flaggen (`RowerProfile.publicAppearance`), beim Beitritt einmal gesendet, nicht in jedem
    /// LiveFrame. nil = ältere Absender ohne Erscheinung (die Szene wählt dann `RowerAppearance.random(seed: id)`).
    public var appearance: RowerAppearance?

    public init(id: String, displayName: String, lane: Int, source: Source = .human,
                appearance: RowerAppearance? = nil) {
        self.id = id
        self.displayName = displayName
        self.lane = lane
        self.source = source
        self.appearance = appearance
    }

    /// Virtuelle Teilnehmende (Quelle `virtual`): in Szene, Feld-Anzeige, Ergebnissen und Ranglisten gekennzeichnet
    public var isVirtual: Bool { source == .virtual }

    /// Zeichen für virtuelle Teilnehmende (Namensschild, Listen); VoiceOver sagt stattdessen „virtuell“
    public static let virtualMark = "✦"

    /// Name mit Länderkürzel, z. B. „Lea · SE“ (Ländercode nur, wenn eine Flagge gezeigt wird)
    public var nameWithCountry: String {
        guard let a = appearance, a.flagOnBoat || a.flagOnShirt, let c = a.nationality else { return displayName }
        return "\(displayName) · \(c)"
    }

    /// Erscheinung für die Szene: die gesendete, sonst eine je Teilnehmer stabile zufällige
    public func resolvedAppearance(catalog: AppearanceCatalog = .current) -> RowerAppearance {
        appearance ?? RowerAppearance.random(seed: id, catalog: catalog)
    }
}

/// Stand eines Teilnehmenden, wie er über das Netz geht (2–4 pro Sekunde und bei jedem Schlag).
/// Kurze JSON-Schlüssel halten die Datenmenge klein (Firebase rechnet nach Volumen).
public struct LiveFrame: Codable, Equatable, Sendable {
    public var participantId: String
    public var raceId: String
    /// fortlaufende Nummer je Teilnehmendem (ältere oder doppelte Frames werden verworfen)
    public var seq: Int
    /// Sendezeitpunkt (Serverzeit, Sekunden seit 1970)
    public var sentAt: TimeInterval
    /// Rennzeit seit dem Start (s)
    public var raceTime: TimeInterval
    /// Distanz seit dem Start (m)
    public var distance: Double
    /// aktuelles Tempo (s/500 m), 0 = unbekannt
    public var pace: TimeInterval
    public var strokeRate: Int
    public var heartRate: Int?
    public var finished: Bool
    /// Rennzeit im Ziel (s), sobald `finished`
    public var finishTime: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case participantId = "p", raceId = "r", seq = "n", sentAt = "at", raceTime = "t", distance = "d", pace = "pc"
        case strokeRate = "spm", heartRate = "hr", finished = "f", finishTime = "ft"
    }

    public init(participantId: String, raceId: String, seq: Int, sentAt: TimeInterval, raceTime: TimeInterval,
                distance: Double, pace: TimeInterval, strokeRate: Int, heartRate: Int? = nil, finished: Bool = false,
                finishTime: TimeInterval? = nil) {
        self.participantId = participantId
        self.raceId = raceId
        self.seq = seq
        self.sentAt = sentAt
        self.raceTime = raceTime
        self.distance = distance
        self.pace = pace
        self.strokeRate = strokeRate
        self.heartRate = heartRate
        self.finished = finished
        self.finishTime = finishTime
    }

    /// Geschwindigkeit aus dem Tempo (m/s), 0 = unbekannt
    public var speed: Double { pace > 0 && pace.isFinite ? 500 / pace : 0 }
}

/// Ergebnis eines Teilnehmenden (am Ende vom Server bestätigt)
public struct RaceResult: Codable, Equatable, Sendable {
    public var participantId: String
    public var place: Int
    public var distance: Double
    /// Rennzeit im Ziel (Distanzrennen) bzw. Renndauer (Zeitrennen)
    public var time: TimeInterval?
    public var finished: Bool

    public init(participantId: String, place: Int, distance: Double, time: TimeInterval?, finished: Bool) {
        self.participantId = participantId
        self.place = place
        self.distance = distance
        self.time = time
        self.finished = finished
    }
}

/// Angezeigter Stand eines anderen Teilnehmenden (für Szene und Anzeige)
public struct RemoteRowerState: Equatable, Sendable, Identifiable {
    public var participant: RaceParticipant
    /// Distanz, an der das Boot gezeigt wird (interpoliert bzw. vorausgerechnet)
    public var distance: Double
    public var strokeRate: Int
    /// Abstand zu mir in Metern (positiv = vor mir)
    public var gapMeters: Double
    /// Abstand zu mir in Sekunden (positiv = vor mir), nil ohne Tempo
    public var gapSeconds: TimeInterval?
    public var finished: Bool
    public var finishTime: TimeInterval?
    /// Platz im Rennen (1 = vorne), über alle einschliesslich mir
    public var place: Int
    /// seit einiger Zeit keine Daten mehr (Verbindung weg)
    public var stale: Bool
    /// seitlicher Versatz zur eigenen Linie in Metern (positiv = links der Fahrtrichtung), siehe `RaceLanes`
    public var lateral: Double

    public var id: String { participant.id }

    public init(participant: RaceParticipant, distance: Double, strokeRate: Int, gapMeters: Double,
                gapSeconds: TimeInterval?, finished: Bool, finishTime: TimeInterval?, place: Int, stale: Bool,
                lateral: Double) {
        self.participant = participant
        self.distance = distance
        self.strokeRate = strokeRate
        self.gapMeters = gapMeters
        self.gapSeconds = gapSeconds
        self.finished = finished
        self.finishTime = finishTime
        self.place = place
        self.stale = stale
        self.lateral = lateral
    }
}

/// Darf man sich für ein Rennen anmelden? Die Strecke muss auf dem Gerät installiert sein (alle rudern dieselbe
/// Landschaft); fehlt sie, bietet die Anmeldung den Download an. Die Prüfung der Installation selbst liegt im
/// Streckenkatalog (CourseCatalog.swift); hier nur über eine Funktion, damit Rennen nicht vom Katalog abhängen.
public enum RaceEligibility: Equatable, Sendable {
    case ready
    /// Strecke fehlt (bzw. Fassung passt nicht): erst herunterladen
    case needsCourse(courseId: String, version: Int?)

    public static func check(_ race: Race, isCourseInstalled: (_ courseId: String, _ version: Int?) -> Bool) -> RaceEligibility {
        isCourseInstalled(race.courseId, race.courseVersion) ? .ready : .needsCourse(courseId: race.courseId, version: race.courseVersion)
    }
}
