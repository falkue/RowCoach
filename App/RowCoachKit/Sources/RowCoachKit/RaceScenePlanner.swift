import Foundation

// Wer in einem grossen Rennen wie gezeigt wird: wenige Boote im direkten Umfeld voll, weitere vereinfacht, ferne als
// günstige Impostoren bzw. „Pulk“, der Rest nur im HUD (Platz, Abstände, Dichte, Führende). Reine Rechnung ohne
// Szene; die Szene (RaceRowers) setzt die Ausgabe um. Regeln, Budgets und Schnittstelle: docs/MULTIPLAYER.md,
// Abschnitt „Grosse Felder“.

/// Darstellungsstufe eines Boots
public enum RaceRenderTier: Int, Comparable, Sendable, CaseIterable {
    /// nicht als Einzelboot (nur HUD, Minikarte, Pulk)
    case hidden = 0
    /// Punkt/Silhouette in der Ferne (instanziert, keine Animation, kein Schatten)
    case impostor = 1
    /// vereinfachtes Boot: Low-Poly, vereinfachte Ruderanimation, kein Schild, kein Schatten
    case lite = 2
    /// volle Figur mit Erscheinung, Animation, Namensschild, Flagge, Schatten
    case full = 3

    public static func < (a: RaceRenderTier, b: RaceRenderTier) -> Bool { a.rawValue < b.rawValue }
}

/// Höchstzahl je Stufe für eine Gerätestufe
public struct RaceRenderBudget: Equatable, Sendable {
    public var full: Int
    public var lite: Int
    public var impostors: Int
    /// Pulk-Gruppen (je eine Instanz mit mehreren Silhouetten)
    public var clusters: Int

    public init(full: Int, lite: Int, impostors: Int, clusters: Int) {
        self.full = max(full, 0)
        self.lite = max(lite, 0)
        self.impostors = max(impostors, 0)
        self.clusters = max(clusters, 0)
    }

    /// iPad mit A12X/A12Z (Untergrenze), iPhone XS/11-Klasse
    public static let a12x = RaceRenderBudget(full: 6, lite: 12, impostors: 48, clusters: 12)
    /// A13–A16, M1-iPads ohne ProMotion-Ziel
    public static let standard = RaceRenderBudget(full: 10, lite: 16, impostors: 96, clusters: 16)
    /// M2 und neuer, A17 Pro und neuer
    public static let high = RaceRenderBudget(full: 12, lite: 20, impostors: 160, clusters: 20)

    /// Budget für ein Gerät aus der Modellkennung (`uname().machine`, z. B. "iPad8,1"; im Simulator
    /// `SIMULATOR_MODEL_IDENTIFIER`) und notfalls dem Arbeitsspeicher. A12/A12X/A12Z und älter → `.a12x`,
    /// A13–A16 und M1 → `.standard`, M2+ und A17 Pro+ → `.high`. Mit `override` ("a12x", "standard", "high") fest.
    public static func forDevice(machine: String, physicalMemory: UInt64, override: String? = nil) -> RaceRenderBudget {
        switch override?.lowercased() {
        case "a12x": return .a12x
        case "standard": return .standard
        case "high": return .high
        default: break
        }
        let letters = machine.prefix { $0.isLetter }
        let numbers = machine.dropFirst(letters.count).split(separator: ",").compactMap { Int($0) }
        if numbers.count == 2 {
            let (major, minor) = (numbers[0], numbers[1])
            switch letters {
            case "iPad":
                if major <= 11 { return .a12x }                                // bis A12X/A12Z bzw. A12
                if major <= 13 { return .standard }                            // A13, A14, M1
                if major == 14 { return minor <= 2 ? .standard : .high }       // A15 mini 6; M2
                if major == 15 && (minor == 7 || minor == 8) { return .standard } // A16
                return .high                                                   // M3, M4, A17 Pro und neuer
            case "iPhone":
                if major <= 11 { return .a12x }                                // XS/XR und älter
                if major <= 15 { return .standard }                            // A13–A16
                return .high                                                   // A17 Pro und neuer
            default:
                break
            }
        }
        let gb = Double(physicalMemory) / 1_073_741_824
        if gb < 4.5 { return .a12x }
        if gb < 7 { return .standard }
        return .high
    }

    public subscript(tier: RaceRenderTier) -> Int {
        switch tier {
        case .full: return full
        case .lite: return lite
        case .impostor: return impostors
        case .hidden: return .max
        }
    }
}

/// Rückkopplung von der gemessenen Bildrate: unter `lowFPS` (über `lowFor` s) eine Stufe weniger, über `highFPS`
/// (über `highFor` s) eine Stufe mehr, dazwischen bleibt alles. Je Stufe −1 voll, −2 vereinfacht, −25 % Impostoren.
public struct RaceFrameRateGovernor: Equatable, Sendable {
    public var lowFPS: Double = 50
    public var highFPS: Double = 57
    public var lowFor: TimeInterval = 2
    public var highFor: TimeInterval = 10
    /// nach einem Wechsel so lange nichts ändern (Wirkung abwarten)
    public var cooldown: TimeInterval = 4
    public var maxLevel = 4
    public var minFull = 3
    public var minLite = 4
    public private(set) var level = 0
    /// geglättete Bildrate
    public private(set) var fps: Double?
    private var lowSince: TimeInterval?
    private var highSince: TimeInterval?
    private var lastChange: TimeInterval = -.infinity

    public init() {}

    /// Gemessene Bildrate melden (z. B. jede Sekunde den Mittelwert); liefert true, wenn sich die Stufe änderte
    @discardableResult
    public mutating func report(fps measured: Double, now: TimeInterval) -> Bool {
        guard measured.isFinite, measured > 0 else { return false }
        let f = fps.map { $0 + (measured - $0) * 0.3 } ?? measured
        fps = f
        if f < lowFPS { lowSince = lowSince ?? now } else { lowSince = nil }
        if f > highFPS { highSince = highSince ?? now } else { highSince = nil }
        guard now - lastChange >= cooldown else { return false }
        if let s = lowSince, now - s >= lowFor, level < maxLevel {
            level += 1
        } else if let s = highSince, now - s >= highFor, level > 0 {
            level -= 1
        } else {
            return false
        }
        lastChange = now
        lowSince = nil
        highSince = nil
        return true
    }

    public func apply(to b: RaceRenderBudget) -> RaceRenderBudget {
        let l = Double(level)
        return RaceRenderBudget(full: max(b.full - level, min(minFull, b.full)),
                                lite: max(b.lite - 2 * level, min(minLite, b.lite)),
                                impostors: Int(Double(b.impostors) * max(1 - 0.25 * l, 0.25)),
                                clusters: b.clusters)
    }
}

/// Seitliche Plätze („visuelle Bahnen“) relativ zum eigenen Boot. Platz k > 0 liegt k × `spacing` rechts (in
/// Fahrtrichtung, weg von der Gegenbahn wie `RaceLanes`), k < 0 links (nur auf breiten Strecken ohne Gegenbahn),
/// k = 0 ist die eigene Linie (nur für Boote, die immer mindestens `ownLineMinGap` vor oder hinter mir bleiben).
public struct RaceVisualLanes: Equatable, Sendable {
    public var spacing: Double = 7
    public var right: Int = 4
    public var left: Int = 0
    public var useOwnLine = true
    public var ownLineMinGap: Double = 30
    /// Mindestabstand in Fahrtrichtung auf derselben Bahn (Skiff 8,2 m + Luft)
    public var minGap: Double = 13
    /// so weit wird der Abstand vorausgerechnet (Überholen auf derselben Bahn früh erkennen)
    public var horizon: TimeInterval = 6
    /// Wechselgeschwindigkeit zur Seite (m/s), damit nichts springt
    public var lateralSpeed: Double = 1.5

    public init(spacing: Double = 7, right: Int = 4, left: Int = 0, useOwnLine: Bool = true) {
        self.spacing = spacing
        self.right = max(right, 1)
        self.left = max(left, 0)
        self.useOwnLine = useOwnLine
    }

    /// Aus der Strecke: rechts so viele Plätze, wie die Ruderbahnen des Verkehrs Wasser zeigen (Hinfahrt, negativer
    /// Versatz, inkl. Ausweichen vor der Wende), 2…6; links nur auf Strecken ohne Wende und ohne Gegenverkehrslinie.
    public static func forCourse(_ course: Course, spacing: Double = 7) -> RaceVisualLanes {
        let lanes = course.traffic?.rowerLanes ?? (course.turns == 0 ? TrafficDefaults.openRowerLanes : TrafficDefaults.rowerLanes)
        let rightWidth = lanes.filter { !($0.reverse ?? false) }
            .map { max(-$0.outM, -($0.turnOutM ?? 0)) }.max() ?? 28
        let right = min(max(Int((rightWidth + 3) / spacing), 2), 6)
        var left = 0
        if course.turns == 0 {
            let counter = lanes.filter { $0.reverse ?? false }.map(\.outM).filter { $0 > 0 }.min()
            if let c = counter { left = min(max(Int((c - spacing) / spacing), 0), 2) } else { left = 2 }
        }
        return RaceVisualLanes(spacing: spacing, right: right, left: left)
    }

    /// Plätze in Vorzugsreihenfolge (nah an mir zuerst, rechts vor links)
    public var slots: [Int] {
        var s: [Int] = []
        for k in 1...max(right, left) {
            if k <= right { s.append(k) }
            if k <= left { s.append(-k) }
        }
        if useOwnLine { s.append(0) }
        return s
    }

    /// Seitlicher Versatz des Platzes (m, positiv = links der Fahrtrichtung wie `RemoteRowerState.lateral`)
    public func lateral(slot: Int) -> Double { -Double(slot) * spacing }
}

/// Ein Boot, wie es der Planer kennt (volle Frames oder grob aus der Übersicht)
public struct RaceFieldMember: Equatable, Sendable {
    public var id: String
    public var distance: Double
    /// m/s, 0 = unbekannt
    public var speed: Double
    public var strokeRate: Int
    public var finished: Bool
    public var stale: Bool
    public var source: RaceParticipant.Source
    /// volle Frames vorhanden (Nachbarschaft) statt nur Übersicht
    public var precise: Bool
    /// Freund bzw. markierte Person
    public var marked: Bool

    public init(id: String, distance: Double, speed: Double, strokeRate: Int = 0, finished: Bool = false,
                stale: Bool = false, source: RaceParticipant.Source = .human, precise: Bool = false, marked: Bool = false) {
        self.id = id
        self.distance = distance
        self.speed = speed
        self.strokeRate = strokeRate
        self.finished = finished
        self.stale = stale
        self.source = source
        self.precise = precise
        self.marked = marked
    }

    /// Volle Stände (`RaceCoordinator.states`) und grobe (`RaceFieldTracker.states`) zusammenführen; volle haben Vorrang,
    /// ausser sie sind veraltet und die Übersicht kennt das Boot (Boot hat die Nachbarschaft verlassen, seine
    /// Verfolgung steht still).
    /// - Parameter speeds: Geschwindigkeit der vollen (m/s, z. B. aus `RaceCoordinator.trackers[id].latest.speed`);
    ///   fehlt sie, gilt die aus der Übersicht.
    public static func merge(precise: [RemoteRowerState], coarse: [RaceCoarseState], roster: [RaceParticipant],
                             me: String, marked: Set<String> = [], speeds: [String: Double] = [:]) -> [RaceFieldMember] {
        var out: [RaceFieldMember] = []
        out.reserveCapacity(max(precise.count, coarse.count))
        var preciseIndex: [String: Int] = [:]
        var source: [String: RaceParticipant.Source] = [:]
        for p in roster { source[p.id] = p.source }
        let coarseIds = Set(coarse.map(\.id))
        for s in precise where s.id != me && !(s.stale && coarseIds.contains(s.id)) {
            preciseIndex[s.id] = out.count
            out.append(RaceFieldMember(id: s.id, distance: s.distance, speed: speeds[s.id] ?? 0, strokeRate: s.strokeRate,
                                       finished: s.finished, stale: s.stale, source: s.participant.source,
                                       precise: true, marked: marked.contains(s.id)))
        }
        for c in coarse where c.id != me {
            if let i = preciseIndex[c.id] {
                if speeds[c.id] == nil { out[i].speed = c.speed }
                continue
            }
            out.append(RaceFieldMember(id: c.id, distance: c.distance, speed: c.speed, strokeRate: c.strokeRate,
                                       finished: c.finished, stale: c.stale, source: source[c.id] ?? .human,
                                       precise: false, marked: marked.contains(c.id)))
        }
        return out
    }
}

/// Eigener Stand für den Planer
public struct RaceSelf: Equatable, Sendable {
    public var id: String
    public var distance: Double
    public var speed: Double

    public init(id: String, distance: Double, speed: Double) {
        self.id = id
        self.distance = distance
        self.speed = speed
    }
}

/// Warum ein Boot gezeigt wird (Rangklasse, kleiner = wichtiger); für Szene/HUD und Fehlersuche
public enum RacePriority: Int, Comparable, Sendable {
    /// überholt mich, wird überholt oder ist gleich dran; eigene Bestfahrt in Sichtweite
    case overtaking = 0
    /// unmittelbarer Gegner (± `immediateRange`)
    case immediate = 1
    /// Freund bzw. markiert
    case marked = 2
    /// sonst nach Abstand
    case near = 3

    public static func < (a: RacePriority, b: RacePriority) -> Bool { a.rawValue < b.rawValue }
}

/// Ausgabe je gezeigtem Boot – genau das, was RaceRowers konsumiert
public struct RaceSceneItem: Equatable, Sendable, Identifiable {
    public var participantId: String
    public var tier: RaceRenderTier
    /// visuelle Bahn (`RaceVisualLanes`): Ziel-Platz
    public var visualLane: Int
    /// Distanz entlang der Strecke (m), wie übergeben (nie verschoben: Abstände bleiben wahr)
    public var distance: Double
    /// seitlicher Versatz jetzt (m, positiv = links), mit `lateralSpeed` zum Ziel unterwegs
    public var lateral: Double
    public var lateralTarget: Double
    /// Sichtbarkeit 0…1 (Ein-/Ausblenden), Ziel 1 bzw. 0 beim Ausblenden
    public var fade: Double
    public var fadingOut: Bool
    public var priority: RacePriority
    /// Schlagzahl (Ruderbewegung der Szene) und im Ziel
    public var strokeRate: Int = 0
    public var finished = false

    public var id: String { participantId }
}

/// Mehrere ausgeblendete Boote in der Ferne als eine Gruppe („Pulk“)
public struct RaceCrowdCluster: Equatable, Sendable {
    /// Mitte der Gruppe (m entlang der Strecke)
    public var distance: Double
    public var count: Int
    /// Ausdehnung in Fahrtrichtung (m)
    public var length: Double
}

/// Was das HUD braucht (alle Teilnehmenden, auch die nicht gezeigten)
public struct RaceFieldSummary: Equatable, Sendable {
    public struct Neighbour: Equatable, Sendable {
        public var id: String
        /// m, positiv = vor mir
        public var gapMeters: Double
        /// s, nil ohne Tempo
        public var gapSeconds: TimeInterval?
    }

    public struct Leader: Equatable, Sendable {
        public var id: String
        public var place: Int
        public var gapMeters: Double
        public var finished: Bool
    }

    /// eigener Platz (1 = vorne) und Anzahl (inkl. mir), z. B. „143 von 300“
    public var place: Int
    public var total: Int
    public var ahead: Neighbour?
    public var behind: Neighbour?
    /// Boote im Pulk um mich (± `packRange`)
    public var packAhead: Int
    public var packBehind: Int
    public var leaders: [Leader]
    /// markierte Personen mit Platz und Abstand
    public var marked: [Leader]
    /// Anzahl je Abschnitt entlang der Strecke (Minikarte), `histogramBin` m je Fach ab 0
    public var histogram: [Int]
    public var histogramBin: Double
    /// Boote, die gerade als Einzelboot gezeigt werden (voll + vereinfacht + Impostor)
    public var shown: Int
}

/// Ergebnis eines Planungsschritts
public struct RaceScenePlan: Equatable, Sendable {
    public var items: [RaceSceneItem]
    public var clusters: [RaceCrowdCluster]
    public var summary: RaceFieldSummary
    /// geltendes Budget (nach Bildraten-Rückkopplung)
    public var budget: RaceRenderBudget
    /// ids mit vollen Frames (Nachbarschafts-Abo); nur bei `interestChanged` an den Transport geben
    public var interest: RaceInterest
    public var interestChanged: Bool
}

/// Der Planer: entscheidet alle `decisionInterval` Sekunden über Stufen, Bahnen und Nachbarschaft und glättet bei
/// jedem Aufruf Ein-/Ausblenden und Seitenwechsel. Aufruf aus dem Bild-Takt (oder 10–20×/s) mit allen bekannten
/// Booten; Kosten bei 300 Booten weit unter 1 ms.
public struct RaceScenePlanner: Sendable {
    public struct Config: Equatable, Sendable {
        public var budget: RaceRenderBudget = .a12x
        public var lanes = RaceVisualLanes()
        public var decisionInterval: TimeInterval = 0.5
        /// Boote hinter mir zählen so viel weiter (die Kamera schaut nach vorn)
        public var behindWeight: Double = 1.5
        /// unmittelbare Gegner
        public var immediateRange: Double = 30
        /// „gleich überholt“: so nah und schneller/langsamer als `closingSpeed`
        public var approachRange: Double = 25
        public var closingSpeed: Double = 0.3
        /// wer mich überholt hat (oder den ich überholt habe), bleibt so lange vorn, bis er weiter weg ist als
        /// `overtakeRelease` oder `overtakeHold` s vergangen sind
        public var overtakeRelease: Double = 40
        public var overtakeHold: TimeInterval = 120
        public var markedRange: Double = 300
        public var ghostRange: Double = 300
        /// Reichweiten je Stufe (vor mir / hinter mir, m)
        public var fullAhead: Double = 200, fullBehind: Double = 60
        public var liteAhead: Double = 600, liteBehind: Double = 150
        public var impostorAhead: Double = 1500, impostorBehind: Double = 250
        /// Bonus für die aktuelle Stufe (Hysterese): Anteil und Mindestwert in Metern
        public var stickyFraction: Double = 0.3
        public var stickyMeters: Double = 30
        /// so lange wird eine neue Stufe nicht abgegeben (solange das Boot in Reichweite der Stufe ist)
        public var minDwell: TimeInterval = 3
        public var fadeTime: TimeInterval = 0.6
        /// Nachbarschafts-Abo (volle Frames): ausserhalb der Zielzone K, in der Zielzone (letzte `finishZone` m) mehr
        public var interestCount: Int = 8
        public var interestCountFinish: Int = 16
        public var finishDistance: Double?
        public var finishZone: Double = 250
        public var interestMinInterval: TimeInterval = 2
        /// Pulk um mich für das HUD
        public var packRange: Double = 25
        public var clusterBin: Double = 25
        public var histogramBin: Double = 50
        /// Streckenlänge für die Minikarte (nil = aus den Distanzen)
        public var courseLength: Double?
        public var leaderCount = 3

        public init(budget: RaceRenderBudget = .a12x, lanes: RaceVisualLanes = RaceVisualLanes()) {
            self.budget = budget
            self.lanes = lanes
        }
    }

    private struct Track {
        var tier: RaceRenderTier = .hidden
        var since: TimeInterval = 0
        var slot: Int?
        var lateral: Double = 0
        var fade: Double = 0
        var fadingOut = false
        var priority: RacePriority = .near
        var lastGap: Double?
        var passedAt: TimeInterval?
    }

    public var config: Config
    public var governor = RaceFrameRateGovernor()
    private var tracks: [String: Track] = [:]
    private var lastDecision: TimeInterval?
    private var lastCall: TimeInterval?
    private var interest = RaceInterest.everything
    private var interestAt: TimeInterval = -.infinity
    private var summary = RaceFieldSummary(place: 1, total: 1, ahead: nil, behind: nil, packAhead: 0, packBehind: 0,
                                           leaders: [], marked: [], histogram: [], histogramBin: 50, shown: 0)
    private var clusters: [RaceCrowdCluster] = []
    /// Stufenwechsel seit Beginn (für Tests und Protokoll)
    public private(set) var tierChanges = 0

    public init(config: Config = Config()) {
        self.config = config
    }

    public var budget: RaceRenderBudget { governor.apply(to: config.budget) }

    /// Gemessene Bildrate melden (siehe `RaceFrameRateGovernor`)
    public mutating func reportFrameRate(_ fps: Double, now: TimeInterval) {
        if governor.report(fps: fps, now: now) { lastDecision = nil }
    }

    /// Stufe eines Boots (hidden, wenn unbekannt)
    public func tier(of id: String) -> RaceRenderTier { tracks[id]?.tier ?? .hidden }

    public mutating func plan(members: [RaceFieldMember], me: RaceSelf, now: TimeInterval) -> RaceScenePlan {
        var interestChanged = false
        if lastDecision == nil || now - lastDecision! >= config.decisionInterval || now < lastDecision! {
            interestChanged = decide(members: members, me: me, now: now)
            lastDecision = now
        }
        let dt = lastCall.map { min(max(now - $0, 0), 1) } ?? 0
        lastCall = now
        return output(members: members, dt: dt, now: now, interestChanged: interestChanged)
    }

    // MARK: Entscheidung

    private struct Candidate {
        let index: Int
        let priority: RacePriority
        let score: Double
        let gap: Double
    }

    private mutating func decide(members: [RaceFieldMember], me: RaceSelf, now: TimeInterval) -> Bool {
        let c = config
        let budget = self.budget
        var cands: [Candidate] = []
        cands.reserveCapacity(members.count)
        var indexById: [String: Int] = [:]
        indexById.reserveCapacity(members.count)
        for (i, m) in members.enumerated() where m.id != me.id {
            indexById[m.id] = i
            let gap = m.distance - me.distance
            var t = tracks[m.id] ?? Track()
            if let lg = t.lastGap, (lg < 0) != (gap < 0), abs(gap - lg) < 60 { t.passedAt = now }
            t.lastGap = gap
            let eff = gap >= 0 ? gap : -gap * c.behindWeight
            let closing = gap >= 0 ? me.speed - m.speed : m.speed - me.speed
            var p = RacePriority.near
            if let pa = t.passedAt, now - pa <= c.overtakeHold, abs(gap) <= c.overtakeRelease, !m.stale {
                p = .overtaking
            } else if abs(gap) <= c.approachRange, closing > c.closingSpeed, m.speed > 0, !m.stale {
                p = .overtaking
            } else if m.source == .ghost, eff <= c.ghostRange {
                p = .overtaking
            } else if abs(gap) <= c.immediateRange {
                p = .immediate
            } else if m.marked, eff <= c.markedRange {
                p = .marked
            }
            var score = eff + (m.stale ? 50 : 0)
            if t.tier > .hidden && !t.fadingOut {
                score -= max(c.stickyMeters, eff * c.stickyFraction)
            }
            t.priority = p
            tracks[m.id] = t
            cands.append(Candidate(index: i, priority: p, score: score, gap: gap))
        }
        // Verschwundene (Teilnehmerliste) sofort entfernen
        if tracks.count > indexById.count {
            for id in Array(tracks.keys) where indexById[id] == nil {
                if tracks[id]?.tier != .hidden { tierChanges += 1 }
                tracks[id] = nil
            }
        }
        cands.sort { ($0.priority, $0.score) < ($1.priority, $1.score) }

        // 1. Ziel: Stufen nach Rang und Reichweite; wer keinen freien Platz auf einer Bahn fände, wird übersprungen
        //    (das Budget geht an die nächsten, statt im dichten Pulk zu verfallen). Nahe Boote nie als Punkt.
        var basePlaced: [(slot: Int, distance: Double, speed: Double)] = [(0, me.distance, me.speed)]
        for (id, t) in tracks where t.fadingOut && t.tier >= .lite {
            if let s = t.slot, let i = indexById[id] { basePlaced.append((s, members[i].distance, members[i].speed)) }
        }
        func isNear(_ gap: Double) -> Bool { gap >= 0 ? gap <= c.fullAhead : -gap <= c.fullBehind }
        /// Platz auf einer Bahn: mit Vorausschau; Sichtbare dürfen notfalls nur nach jetzigem Abstand bleiben
        let slots = c.lanes.slots
        func lane(_ m: RaceFieldMember, _ current: Int?, _ placed: [(slot: Int, distance: Double, speed: Double)],
                  relaxed: Bool) -> Int? {
            freeSlot(for: m, current: current, placed: placed, slots: slots, horizon: c.lanes.horizon)
                ?? (relaxed ? freeSlot(for: m, current: current, placed: placed, slots: slots, horizon: 0) : nil)
        }
        // Sichtbare Boote (voll/vereinfacht) und Überholende belegen ihre Bahn zuerst, nach Rang – Neue fügen sich ein
        var simPlaced = basePlaced
        var visibleLane: [String: Int] = [:]
        for cand in cands {
            let m = members[cand.index]
            guard let t = tracks[m.id], !t.fadingOut, t.tier >= .lite || cand.priority == .overtaking,
                  let s = lane(m, t.tier >= .lite ? t.slot : nil, simPlaced, relaxed: true) else { continue }
            simPlaced.append((s, m.distance, m.speed))
            visibleLane[m.id] = s
        }
        var wantedById: [String: [RaceRenderTier]] = [:]
        var ideal: [String: RaceRenderTier] = [:]
        var idealUsed: [RaceRenderTier: Int] = [:]
        for cand in cands {
            let m = members[cand.index]
            let ahead = cand.gap >= 0
            let d = abs(cand.gap)
            var wanted: [RaceRenderTier] = []
            if d <= (ahead ? c.fullAhead : c.fullBehind) || cand.priority == .overtaking { wanted.append(.full) }
            if d <= (ahead ? c.liteAhead : c.liteBehind) { wanted.append(.lite) }
            if d <= (ahead ? c.impostorAhead : c.impostorBehind) { wanted.append(.impostor) }
            wantedById[m.id] = wanted
            let t = tracks[m.id]!
            if t.fadingOut { continue }
            let near = isNear(cand.gap)
            for tier in wanted where idealUsed[tier, default: 0] < budget[tier] {
                if tier == .impostor {
                    if near { break }
                } else if visibleLane[m.id] == nil {
                    guard let s = lane(m, t.slot, simPlaced, relaxed: false) else { continue }
                    simPlaced.append((s, m.distance, m.speed))
                }
                idealUsed[tier, default: 0] += 1
                ideal[m.id] = tier
                break
            }
        }

        // 2. Stufen umsetzen, Budget exakt: Ausblendende zählen in ihrer Stufe; jede bisher sichtbare Stufe ist
        //    reserviert, bis ihr Boot an der Reihe war. Abstiege von unten nach oben (machen Platz für die nächste
        //    Stufe), dann Aufstiege, dann Neue – je nach Rang. Nahe Boote werden nie zum Punkt.
        var count: [RaceRenderTier: Int] = [:]
        var reserved: [RaceRenderTier: Int] = [:]
        var placed = basePlaced
        for (_, t) in tracks where t.tier != .hidden {
            if t.fadingOut {
                count[t.tier, default: 0] += 1
            } else {
                reserved[t.tier, default: 0] += 1
            }
        }
        func free(_ tier: RaceRenderTier) -> Bool {
            count[tier, default: 0] + reserved[tier, default: 0] < budget[tier]
        }
        var assigned: [String: RaceRenderTier] = [:]
        var fadeOuts: [String] = []
        var removals: [String] = []
        var down: [(cand: Candidate, old: RaceRenderTier, target: RaceRenderTier)] = []
        var up: [(cand: Candidate, old: RaceRenderTier, target: RaceRenderTier)] = []
        var newcomers: [Candidate] = []
        for cand in cands {
            let m = members[cand.index]
            var t = tracks[m.id]!
            if t.fadingOut {
                if t.fade <= 0.001 {
                    t = Track(lastGap: t.lastGap, passedAt: t.passedAt)
                    t.priority = cand.priority
                    tracks[m.id] = t
                }
                continue
            }
            if t.tier == .hidden { newcomers.append(cand); continue }
            var target = ideal[m.id] ?? .hidden
            // Mindestdauer: frisch gewechselte Stufe nicht gleich wieder abgeben (solange sie in Reichweite liegt)
            if target < t.tier, now - t.since < c.minDwell, (wantedById[m.id] ?? []).contains(t.tier) { target = t.tier }
            if target > t.tier { up.append((cand, t.tier, target)) } else { down.append((cand, t.tier, target)) }
        }
        for d in down.sorted(by: { $0.target < $1.target }) {   // stabil: innerhalb gleicher Stufe nach Rang
            let id = members[d.cand.index].id
            reserved[d.old, default: 0] -= 1
            let near = isNear(d.cand.gap)
            let tiers = d.target == .hidden ? [] : [d.target] + (wantedById[id] ?? []).filter { $0 < d.target }
            if let tier = tiers.first(where: { free($0) && !(near && $0 == .impostor) }) {
                count[tier, default: 0] += 1
                assigned[id] = tier
            } else if free(d.old) {
                count[d.old, default: 0] += 1
                fadeOuts.append(id)
            } else {
                // Stufe über dem Budget (gerade gesenkt): sofort weg statt ausblenden
                removals.append(id)
            }
        }
        for u in up {
            let id = members[u.cand.index].id
            reserved[u.old, default: 0] -= 1
            let tier = free(u.target) ? u.target : u.old
            count[tier, default: 0] += 1
            assigned[id] = tier
        }
        for cand in newcomers {
            let m = members[cand.index]
            guard let target = ideal[m.id] else { continue }
            let near = isNear(cand.gap)
            if let tier = (wantedById[m.id] ?? []).first(where: { $0 <= target && free($0) && !(near && $0 == .impostor) }) {
                count[tier, default: 0] += 1
                assigned[m.id] = tier
            }
        }

        // 3. Bahnen nach Rang: bisherigen Platz behalten, wenn frei (mit Vorausschau, sonst nach jetzigem Abstand),
        //    sonst den nächstgelegenen freien. Ohne Platz: fern → Impostor, sonst ausblenden bzw. nicht aufnehmen.
        var final: [String: (RaceRenderTier, Int?)] = [:]
        for cand in cands {
            let m = members[cand.index]
            guard let tier = assigned[m.id] else { continue }
            let t = tracks[m.id]!
            if tier == .impostor { final[m.id] = (.impostor, t.slot ?? stableSlot(m.id)); continue }
            if let s = lane(m, t.slot, placed, relaxed: t.tier >= .lite || cand.priority == .overtaking) {
                placed.append((s, m.distance, m.speed))
                final[m.id] = (tier, s)
                continue
            }
            count[tier, default: 0] -= 1
            if !isNear(cand.gap) && count[.impostor, default: 0] < budget.impostors {
                count[.impostor, default: 0] += 1
                final[m.id] = (.impostor, t.slot ?? stableSlot(m.id))
            } else if t.tier != .hidden {
                // in der zugewiesenen Stufe ausblenden (dort ist das Budget gebucht)
                count[tier, default: 0] += 1
                var tt = t
                tt.tier = tier
                tracks[m.id] = tt
                fadeOuts.append(m.id)
            }
        }
        for (id, (tier, slot)) in final {
            var t = tracks[id]!
            if tier != t.tier {
                if t.tier == .hidden { t.fade = 0; t.lateral = config.lanes.lateral(slot: slot ?? 1) }
                t.tier = tier
                t.since = now
                tierChanges += 1
            }
            t.slot = slot
            tracks[id] = t
        }
        for id in fadeOuts {
            tracks[id]!.fadingOut = true
            tracks[id]!.since = now
            tierChanges += 1
        }
        for id in removals {
            let t = tracks[id]!
            tracks[id] = Track(lastGap: t.lastGap, passedAt: t.passedAt)
            tierChanges += 1
        }
        summarize(members: members, me: me, cands: cands, budget: budget)
        return updateInterest(members: members, cands: cands, me: me, now: now)
    }

    /// Freier Platz: zuerst der bisherige, sonst nach Nähe zum bisherigen, dann nach Vorzug
    /// Freier Platz: der bisherige, wenn frei, sonst der freie, der ihm am nächsten liegt (bei Gleichstand nach
    /// Vorzug in `slots`). `placed[0]` ist immer das eigene Boot (Platz 0, braucht `ownLineMinGap`).
    private func freeSlot(for m: RaceFieldMember, current: Int?, placed: [(slot: Int, distance: Double, speed: Double)],
                          slots: [Int], horizon: TimeInterval) -> Int? {
        let lanes = config.lanes
        var blocked: [Int] = []
        for (i, p) in placed.enumerated() where !blocked.contains(p.slot) {
            let need = i == 0 ? lanes.ownLineMinGap : lanes.minGap
            if Self.minSeparation(m.distance - p.distance, m.speed - p.speed, horizon) < need { blocked.append(p.slot) }
        }
        if let cur = current, slots.contains(cur), !blocked.contains(cur) { return cur }
        var best: Int?
        var bestKey = Int.max
        for (rank, s) in slots.enumerated() where !blocked.contains(s) {
            let key = (current.map { abs(s - $0) } ?? 0) * 100 + rank
            if key < bestKey { bestKey = key; best = s }
        }
        return best
    }

    /// Kleinster Abstand in [0, h] bei gleichförmiger Bewegung
    static func minSeparation(_ d0: Double, _ dv: Double, _ h: Double) -> Double {
        let d1 = d0 + dv * h
        if (d0 < 0) != (d1 < 0) { return 0 }
        return min(abs(d0), abs(d1))
    }

    private func stableSlot(_ id: String) -> Int {
        let s = config.lanes.slots.filter { $0 != 0 }
        guard !s.isEmpty else { return 1 }
        let h = Int(RaceRosterIndex.fnv1a([id]) % UInt32(s.count))
        return s[h]
    }

    private mutating func updateInterest(members: [RaceFieldMember], cands: [Candidate], me: RaceSelf,
                                         now: TimeInterval) -> Bool {
        guard now - interestAt >= config.interestMinInterval || interest.fullIds == nil else { return false }
        // Alle vollen Boote, dann nach Rang; bisherige zählen 20 m näher (Hysterese)
        let current = interest.fullIds ?? []
        var ranked = cands.map { cand -> (String, RacePriority, Double) in
            let id = members[cand.index].id
            return (id, cand.priority, cand.score - (current.contains(id) ? 20 : 0))
        }
        ranked.sort { ($0.1, $0.2) < ($1.1, $1.2) }
        var k = config.interestCount
        if let fd = config.finishDistance, fd - me.distance <= config.finishZone { k = max(k, config.interestCountFinish) }
        var ids = Set<String>()
        for (id, t) in tracks where t.tier == .full && ids.count < k { ids.insert(id) }
        for r in ranked where ids.count < k { ids.insert(r.0) }
        guard ids != current || interest.fullIds == nil else { return false }
        interest = RaceInterest(fullIds: ids, distance: me.distance)
        interestAt = now
        return true
    }

    // MARK: HUD

    private mutating func summarize(members: [RaceFieldMember], me: RaceSelf, cands: [Candidate], budget: RaceRenderBudget) {
        let c = config
        var ahead: RaceFieldSummary.Neighbour?, behind: RaceFieldSummary.Neighbour?
        var packA = 0, packB = 0, place = 1
        var maxD = me.distance
        for cand in cands {
            let m = members[cand.index]
            maxD = max(maxD, m.distance)
            let g = cand.gap
            if g > 0 || (g == 0 && m.id < me.id) { place += 1 }
            if g >= 0 {
                if g <= c.packRange { packA += 1 }
                if ahead == nil || g < ahead!.gapMeters { ahead = .init(id: m.id, gapMeters: g, gapSeconds: nil) }
            } else {
                if -g <= c.packRange { packB += 1 }
                if behind == nil || g > behind!.gapMeters { behind = .init(id: m.id, gapMeters: g, gapSeconds: nil) }
            }
        }
        if me.speed > 0.5 {
            if let g = ahead?.gapMeters { ahead?.gapSeconds = g / me.speed }
            if let g = behind?.gapMeters { behind?.gapSeconds = g / me.speed }
        }
        // Führende und Markierte: Platz über alle (Teilsortierung genügt für die Führenden)
        let order = cands.sorted { a, b in
            let ma = members[a.index], mb = members[b.index]
            if ma.finished != mb.finished { return ma.finished }
            return a.gap != b.gap ? a.gap > b.gap : ma.id < mb.id
        }
        var leaders: [RaceFieldSummary.Leader] = []
        var marked: [RaceFieldSummary.Leader] = []
        var p = 0
        var meCounted = false
        for cand in order {
            p += 1
            if !meCounted && cand.gap < 0 { meCounted = true; p += 1 }
            let m = members[cand.index]
            let l = RaceFieldSummary.Leader(id: m.id, place: p, gapMeters: cand.gap, finished: m.finished)
            if leaders.count < c.leaderCount { leaders.append(l) }
            if m.marked { marked.append(l) }
        }
        let length = max(c.courseLength ?? maxD, 1)
        let bins = max(Int((length / c.histogramBin).rounded(.up)), 1)
        var hist = [Int](repeating: 0, count: bins)
        func bin(_ d: Double) -> Int { min(max(Int(d / c.histogramBin), 0), bins - 1) }
        for cand in cands { hist[bin(members[cand.index].distance)] += 1 }
        hist[bin(me.distance)] += 1
        // Pulk: ausgeblendete Boote vor mir in Sichtweite, nach Abschnitten
        var groups: [Int: (count: Int, minD: Double, maxD: Double)] = [:]
        for cand in cands where cand.gap > 0 && cand.gap <= c.impostorAhead {
            let m = members[cand.index]
            guard (tracks[m.id]?.tier ?? .hidden) == .hidden else { continue }
            let k = Int(m.distance / c.clusterBin)
            var g = groups[k] ?? (0, m.distance, m.distance)
            g.count += 1
            g.minD = min(g.minD, m.distance)
            g.maxD = max(g.maxD, m.distance)
            groups[k] = g
        }
        clusters = groups.values.filter { $0.count >= 2 }
            .map { RaceCrowdCluster(distance: ($0.minD + $0.maxD) / 2, count: $0.count, length: $0.maxD - $0.minD) }
            .sorted { $0.distance < $1.distance }
        if clusters.count > budget.clusters { clusters = Array(clusters.prefix(budget.clusters)) }
        let shown = tracks.values.filter { $0.tier != .hidden }.count
        summary = RaceFieldSummary(place: place, total: cands.count + 1, ahead: ahead, behind: behind, packAhead: packA,
                                   packBehind: packB, leaders: leaders, marked: marked, histogram: hist,
                                   histogramBin: c.histogramBin, shown: shown)
    }

    // MARK: Ausgabe (jeder Aufruf: Glätten)

    private mutating func output(members: [RaceFieldMember], dt: Double, now: TimeInterval, interestChanged: Bool) -> RaceScenePlan {
        var items: [RaceSceneItem] = []
        items.reserveCapacity(64)
        let lanes = config.lanes
        let fadeStep = config.fadeTime > 0 ? dt / config.fadeTime : 1
        for m in members {
            guard var t = tracks[m.id], t.tier != .hidden else { continue }
            let target = lanes.lateral(slot: t.slot ?? 1)
            let maxStep = lanes.lateralSpeed * dt
            t.lateral += min(max(target - t.lateral, -maxStep), maxStep)
            // Übergänge beginnen mit der Entscheidung (Zeit davor zählt nicht)
            let step = t.since >= now ? 0 : fadeStep
            t.fade = t.fadingOut ? max(t.fade - step, 0) : min(t.fade + step, 1)
            tracks[m.id] = t
            items.append(RaceSceneItem(participantId: m.id, tier: t.tier, visualLane: t.slot ?? 1, distance: m.distance,
                                       lateral: t.lateral, lateralTarget: target, fade: t.fade, fadingOut: t.fadingOut,
                                       priority: t.priority, strokeRate: m.strokeRate, finished: m.finished))
        }
        return RaceScenePlan(items: items, clusters: clusters, summary: summary, budget: budget, interest: interest,
                             interestChanged: interestChanged)
    }
}
