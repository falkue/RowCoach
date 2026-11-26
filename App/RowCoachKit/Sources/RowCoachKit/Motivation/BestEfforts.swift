import Foundation

// Persönliche Rekorde je Distanz und Zeit, auch als schnellste Teilstücke beliebiger Fahrten (wie Strava „Best
// Efforts“), docs/motivation/RECHERCHE.md Katalog #2 und docs/motivation/UMSETZUNG.md. Nur Foundation.

/// Ziel einer Bestmarke: feste Distanz (schnellste Zeit) oder feste Zeit (weiteste Distanz).
public enum EffortTarget: Hashable, Sendable, Comparable {
    /// Meter
    case distance(Double)
    /// Sekunden
    case time(Double)

    public static let halfMarathon = 21_097.5
    public static let marathon = 42_195.0

    /// 500, 1000, 2000, 5000, 6000, 10 000 m, Halbmarathon, Marathon
    public static let distances: [EffortTarget] = [500, 1000, 2000, 5000, 6000, 10_000, halfMarathon, marathon]
        .map { .distance($0) }
    /// 30 und 60 min
    public static let times: [EffortTarget] = [1800, 3600].map { .time($0) }
    public static let standard: [EffortTarget] = distances + times

    /// Stabile Kennung („d2000“, „t1800“)
    public var id: String {
        switch self {
        case .distance(let m): return "d\(Int(m))"
        case .time(let s): return "t\(Int(s))"
        }
    }

    public init?(id: String) {
        guard let first = id.first, let v = Double(id.dropFirst()) else { return nil }
        switch first {
        case "d": self = Self.distances.first { $0.id == id } ?? .distance(v)
        case "t": self = .time(v)
        default: return nil
        }
    }

    /// „2000 m“, „Halbmarathon“, „30 min“
    public var title: String {
        switch self {
        case .distance(let m):
            if m == Self.halfMarathon { return String(localized: "Halbmarathon") }
            if m == Self.marathon { return String(localized: "Marathon") }
            return "\(Int(m)) m"
        case .time(let s):
            return "\(Int(s / 60)) min"
        }
    }

    public var isDistance: Bool {
        if case .distance = self { return true }
        return false
    }

    /// Wert für die Anzeige: Zeit (Distanz-Ziel) bzw. Meter (Zeit-Ziel)
    public func formatted(_ value: Double) -> String {
        isDistance ? Format.duration(value) : "\(Int(value.rounded())) m"
    }

    /// true, wenn `a` besser ist als `b` (kürzere Zeit bzw. weitere Distanz)
    public func isBetter(_ a: Double, than b: Double) -> Bool {
        isDistance ? a < b : a > b
    }

    private var sortKey: (Int, Double) {
        switch self {
        case .distance(let m): return (0, m)
        case .time(let s): return (1, s)
        }
    }

    public static func < (a: EffortTarget, b: EffortTarget) -> Bool { a.sortKey < b.sortKey }
}

/// Sucht in der Zeitreihe einer Fahrt das schnellste Teilstück je Distanz und das weiteste je Zeit
/// (Zwei-Zeiger-Suche, linear interpoliert zwischen den Messpunkten).
///
/// - Gemessen wird Uhrzeit (`WorkoutSample.time`, einschliesslich Pausen): Ein Teilstück über eine Pause oder die
///   Pausen eines Intervalltrainings ist entsprechend langsamer. So werden kurze Intervalle nie zu einem
///   2000-m-Rekord.
/// - Springt die Distanz zurück (PM5 neu gestartet), beginnt ein neuer Abschnitt; Teilstücke reichen nie darüber.
/// - Teilstücke schneller als `minimumPace` gelten als Messfehler und zählen nicht.
public enum BestEffortFinder {
    /// s/500 m; schneller als jeder Weltrekord (500 m ≈ 1:13) gilt als Messfehler
    public static let minimumPace: Double = 65

    public static func find(samples: [WorkoutSample],
                            targets: [EffortTarget] = EffortTarget.standard) -> [EffortTarget: Double] {
        var result: [EffortTarget: Double] = [:]
        for run in runs(samples) {
            for target in targets {
                let value: Double?
                switch target {
                case .distance(let d): value = fastestTime(over: d, t: run.t, d: run.d)
                case .time(let s): value = farthestDistance(in: s, t: run.t, d: run.d)
                }
                if let v = value, result[target].map({ target.isBetter(v, than: $0) }) ?? true {
                    result[target] = v
                }
            }
        }
        return result
    }

    /// Abschnitte mit nicht fallender Distanz. Der erste beginnt bei (0 s, 0 m), wenn die Zeitreihe erst nach dem
    /// Start einsetzt und das Anfangsstück plausibel ist.
    static func runs(_ samples: [WorkoutSample]) -> [(t: [Double], d: [Double])] {
        let sorted = samples.filter { $0.time.isFinite && $0.distance.isFinite && $0.time >= 0 }
            .sorted { $0.time < $1.time }
        guard let first = sorted.first else { return [] }
        var out: [(t: [Double], d: [Double])] = []
        var t: [Double] = [], d: [Double] = []
        if first.distance > 0, first.time > 0, first.distance / first.time <= 8 {
            t.append(0); d.append(0)
        }
        for s in sorted {
            if let last = d.last, s.distance < last {
                if last - s.distance >= 5 {
                    if t.count >= 2 { out.append((t, d)) }
                    t = []; d = []
                } else {
                    // Rundung: nie rückwärts
                    t.append(s.time); d.append(last)
                    continue
                }
            }
            if let lt = t.last, s.time <= lt { continue }
            t.append(s.time); d.append(s.distance)
        }
        if t.count >= 2 { out.append((t, d)) }
        return out
    }

    /// Schnellste Zeit (s) für `meters`; nil, wenn der Abschnitt kürzer ist
    static func fastestTime(over meters: Double, t: [Double], d: [Double]) -> Double? {
        guard meters > 0, let dEnd = d.last, dEnd - d[0] >= meters else { return nil }
        var best: Double?
        var i = 0
        for j in 1..<d.count where d[j] - d[0] >= meters {
            while i + 1 < j && d[j] - d[i + 1] >= meters { i += 1 }
            let s = d[j] - meters
            let ts: Double
            if d[i + 1] > d[i] {
                ts = t[i] + (s - d[i]) / (d[i + 1] - d[i]) * (t[i + 1] - t[i])
            } else {
                ts = t[i]
            }
            let dur = t[j] - ts
            guard dur > 0, dur / meters * 500 >= minimumPace else { continue }
            if best.map({ dur < $0 }) ?? true { best = dur }
        }
        return best
    }

    /// Weiteste Distanz (m) in `seconds`; nil, wenn der Abschnitt kürzer dauert
    static func farthestDistance(in seconds: Double, t: [Double], d: [Double]) -> Double? {
        guard seconds > 0, let tEnd = t.last, tEnd - t[0] >= seconds else { return nil }
        var best: Double?
        var i = 0
        for j in 1..<t.count where t[j] - t[0] >= seconds {
            while i + 1 < j && t[j] - t[i + 1] >= seconds { i += 1 }
            let s = t[j] - seconds
            let ds: Double
            if t[i + 1] > t[i] {
                ds = d[i] + (s - t[i]) / (t[i + 1] - t[i]) * (d[i + 1] - d[i])
            } else {
                ds = d[i]
            }
            let dist = d[j] - ds
            guard dist > 0, seconds / dist * 500 >= minimumPace else { continue }
            if best.map({ dist > $0 }) ?? true { best = dist }
        }
        return best
    }
}

/// Verdichtete Fahrt für die Motivationsfunktionen: die schlanke `TrainingSession`, dazu die Bestmarken der Fahrt
/// und das Tempo je Belastungsphase. Wird einmal je Fahrt (im Hintergrund) gebaut und zwischengespeichert.
public struct RideDigest: Equatable, Sendable, Identifiable {
    public var session: TrainingSession
    /// Bestmarken dieser Fahrt (Zeit in s für Distanzen, Meter für Zeiten)
    public var efforts: [EffortTarget: Double]
    /// Tempo (s/500 m) je vollständig gefahrener Belastungsphase ab 100 m, in Reihenfolge
    public var workPaces: [Double]

    public var id: UUID { session.id }

    public init(session: TrainingSession, efforts: [EffortTarget: Double] = [:], workPaces: [Double] = []) {
        self.session = session
        self.efforts = efforts
        self.workPaces = workPaces
    }

    public init(record: WorkoutRecord, plan: WorkoutPlan?) {
        let session = TrainingSession(record: record, plan: plan)
        let efforts = session.countsInStats ? BestEffortFinder.find(samples: record.samples) : [:]
        let paces = (record.planPhases ?? [])
            .filter { $0.phaseKind == .work && $0.completed && $0.distance >= 100 }
            .compactMap(\.averagePace)
            .filter { $0 >= BestEffortFinder.minimumPace }
        self.init(session: session, efforts: efforts, workPaces: paces)
    }
}

/// Persönliche Rekorde über alle Fahrten (ohne Simulator)
public enum PersonalRecords {
    public struct Record: Equatable, Sendable {
        public var target: EffortTarget
        public var value: Double
        public var workoutId: UUID
        public var date: Date
    }

    /// Verbesserung in einer Fahrt gegenüber allen früheren
    public struct Improvement: Equatable, Sendable {
        public var target: EffortTarget
        public var value: Double
        public var previous: Double
    }

    /// Bester Wert je Ziel; bei Gleichstand gilt die frühere Fahrt
    public static func best(_ rides: [RideDigest]) -> [EffortTarget: Record] {
        var out: [EffortTarget: Record] = [:]
        for r in rides.filter({ $0.session.countsInStats }).sorted(by: { $0.session.start < $1.session.start }) {
            for (target, v) in r.efforts where out[target].map({ target.isBetter(v, than: $0.value) }) ?? true {
                out[target] = Record(target: target, value: v, workoutId: r.id, date: r.session.start)
            }
        }
        return out
    }

    /// Neue Rekorde dieser Fahrt: nur, wenn es vorher schon einen Wert gab (die erste Messung ist noch kein Rekord),
    /// sortiert nach Ziel
    public static func improvements(in ride: RideDigest, history: [RideDigest]) -> [Improvement] {
        guard ride.session.countsInStats else { return [] }
        let earlier = best(history.filter { $0.id != ride.id && $0.session.start < ride.session.start })
        return ride.efforts.compactMap { target, v -> Improvement? in
            guard let prev = earlier[target]?.value, target.isBetter(v, than: prev) else { return nil }
            // Messrauschen: mindestens 0,5 s bzw. 1 m besser
            guard abs(v - prev) >= (target.isDistance ? 0.5 : 1) else { return nil }
            return Improvement(target: target, value: v, previous: prev)
        }
        .sorted { $0.target < $1.target }
    }

    /// Beste ganze freie Fahrt auf einer Strecke (für „Gegen meine Bestfahrt“); nil ohne vollständige Fahrt
    public static func bestCourseRun(_ sessions: [TrainingSession], courseKey: String) -> TrainingSession? {
        sessions.filter { $0.countsInStats && $0.courseKey == courseKey && $0.isFullCourseRun }
            .min { $0.activeDuration != $1.activeDuration ? $0.activeDuration < $1.activeDuration : $0.start < $1.start }
    }

    /// Zeitreihe einer Bestfahrt als Geisterboot: Zeit ab dem ersten Schlag (erster Messpunkt mit Distanz > 0)
    public static func ghostSamples(_ samples: [WorkoutSample]) -> [WorkoutSample] {
        let sorted = samples.sorted { $0.time < $1.time }
        guard let firstMoving = sorted.firstIndex(where: { $0.distance > 0 }) else { return sorted }
        let t0 = firstMoving > 0 ? sorted[firstMoving - 1].time : 0
        return sorted[max(firstMoving - 1, 0)...].map {
            var s = $0
            s.time = max($0.time - t0, 0)
            return s
        }
    }
}
