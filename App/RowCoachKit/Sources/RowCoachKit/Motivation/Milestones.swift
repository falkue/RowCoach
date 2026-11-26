import Foundation

// Meilensteine (docs/motivation/RECHERCHE.md Katalog #5): wenige, bedeutsame Schwellen, ruhige Feier, keine Punkte,
// keine Sperren, Simulatorfahrten zählen nie.

/// Ort einer Strecke für Meilensteine je Gewässer und je Land (die App liefert ihn aus den Kartenpaketen)
public struct CoursePlace: Equatable, Sendable {
    public var courseId: String
    /// Schlüssel des Gewässers (klein, ohne Zusatz), z. B. „zürichsee“
    public var waterKey: String
    /// angezeigter Name des Gewässers, z. B. „Zürichsee“
    public var waterName: String
    public var countryCode: String?
    /// angezeigter Name des Landes (in der Sprache der App)
    public var countryName: String?

    public init(courseId: String, waterKey: String, waterName: String, countryCode: String?, countryName: String?) {
        self.courseId = courseId
        self.waterKey = waterKey
        self.waterName = waterName
        self.countryCode = countryCode
        self.countryName = countryName
    }

    /// Aus dem Feld `region` einer Strecke: Teil vor dem ersten Komma ohne Klammerzusatz
    /// („Zürichsee, unteres Seebecken“ → „Zürichsee“, „Rhein, Basel (Rheinknie)“ → „Rhein“)
    public init(courseId: String, region: String, countryCode: String?, countryName: String?) {
        var name = region.components(separatedBy: ",").first ?? region
        if let p = name.firstIndex(of: "(") { name = String(name[..<p]) }
        name = name.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { name = courseId }
        self.init(courseId: courseId, waterKey: name.lowercased(), waterName: name, countryCode: countryCode,
                  countryName: countryName)
    }
}

public struct Milestone: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        /// Lebens-Kilometer
        case lifetimeDistance(km: Int)
        /// Fahrten insgesamt
        case rides(Int)
        /// Kilometer auf einem Gewässer
        case water(key: String, name: String, km: Int)
        /// alle Strecken eines Landes mindestens einmal gefahren (Seen-Pass)
        case country(code: String, name: String, courses: Int)
    }

    public var kind: Kind
    public var reachedAt: Date
    /// Fahrt, mit der die Schwelle überschritten wurde
    public var workoutId: UUID

    public var id: String {
        switch kind {
        case .lifetimeDistance(let km): return "km-\(km)"
        case .rides(let n): return "rides-\(n)"
        case .water(let key, _, let km): return "water-\(key)-\(km)"
        case .country(let code, _, _): return "country-\(code)"
        }
    }

    /// „1000 km – eine Million Meter“, „100 Fahrten“, „Zürichsee: 100 km“, „Seen-Pass Schweiz komplett“
    public var title: String {
        switch kind {
        case .lifetimeDistance(let km):
            if km == 1000 { return String(localized: "1000 km – eine Million Meter") }
            return String(localized: "\(Int(km)) km gerudert")
        case .rides(let n):
            return String(localized: "\(n) Fahrten")
        case .water(_, let name, let km):
            return String(localized: "\(name): \(Int(km)) km")
        case .country(_, let name, _):
            return String(localized: "Seen-Pass \(name) komplett")
        }
    }

    /// Eine ruhige Zeile für die Feier
    public var detail: String {
        switch kind {
        case .lifetimeDistance(let km):
            return km == 1000 ? String(localized: "So viel wie der Million-Meter-Club von Concept2.")
                : String(localized: "Kilometer für Kilometer zusammengekommen.")
        case .rides:
            return String(localized: "Jede einzelne Fahrt hat dazu beigetragen.")
        case .water:
            return String(localized: "Dieses Gewässer kennst du inzwischen gut.")
        case .country(_, _, let courses):
            return String(localized: "Alle \(Int(courses)) Strecken mindestens einmal gerudert.")
        }
    }
}

/// Noch nicht erreichter Meilenstein, der nah ist (für die Startseite)
public struct MilestoneProgress: Equatable, Sendable {
    public var kind: Milestone.Kind
    /// fehlende Meter (Distanz) bzw. Fahrten (Zählung) bzw. Strecken (Land)
    public var remaining: Double
    /// geschätzte Fahrten bis dahin (1 oder 2)
    public var ridesNeeded: Int

    /// „Noch 6 km bis Zürichsee: 100 km“
    public var text: String {
        let target = Milestone(kind: kind, reachedAt: .distantPast, workoutId: UUID()).title
        switch kind {
        case .lifetimeDistance, .water:
            let km = remaining >= 10_000 ? String(Int((remaining / 1000).rounded()))
                : String(format: "%.1f", remaining / 1000).replacingOccurrences(of: ".", with: decimalSeparator)
            return String(localized: "Noch \(km) km bis „\(target)“")
        case .rides:
            return ridesNeeded == 1 ? String(localized: "Mit der nächsten Fahrt: „\(target)“")
                : String(localized: "Noch zwei Fahrten bis „\(target)“")
        case .country:
            return String(localized: "Noch eine neue Strecke bis „\(target)“")
        }
    }

    private var decimalSeparator: String { Locale.current.decimalSeparator ?? "." }
}

public enum Milestones {
    public static let lifetimeKm = [100, 250, 500, 1000, 2500, 5000, 10_000, 25_000]
    public static let rideCounts = [10, 25, 50, 100, 250, 500, 1000]
    public static let waterKm = [25, 100, 250, 500, 1000]
    /// Länder mit weniger Strecken zählen nicht (eine einzige Strecke ist noch kein Seen-Pass)
    public static let minimumCoursesPerCountry = 2

    /// Alle erreichten Meilensteine in zeitlicher Reihenfolge.
    /// - Parameter places: Orte der verfügbaren Strecken (je Gewässer und Land); Strecken ohne Ort zählen nur für
    ///   Lebens-Kilometer und Fahrten
    public static func reached(sessions all: [TrainingSession], places: [CoursePlace]) -> [Milestone] {
        let sessions = all.filter { $0.countsInStats }.sorted { $0.start < $1.start }
        let byCourse = Dictionary(places.map { ($0.courseId, $0) }, uniquingKeysWith: { a, _ in a })
        var countryCourses: [String: Set<String>] = [:]
        var countryNames: [String: String] = [:]
        for p in places {
            guard let c = p.countryCode else { continue }
            countryCourses[c, default: []].insert(p.courseId)
            if let n = p.countryName { countryNames[c] = n }
        }
        var out: [Milestone] = []
        var total = 0.0, rides = 0
        var water: [String: Double] = [:]
        var rowed: [String: Set<String>] = [:]
        for s in sessions {
            let before = total
            total += s.distance
            rides += 1
            for km in lifetimeKm where before < Double(km) * 1000 && total >= Double(km) * 1000 {
                out.append(Milestone(kind: .lifetimeDistance(km: km), reachedAt: s.start, workoutId: s.id))
            }
            if rideCounts.contains(rides) {
                out.append(Milestone(kind: .rides(rides), reachedAt: s.start, workoutId: s.id))
            }
            guard let cid = s.courseId, let place = byCourse[cid] else { continue }
            let wBefore = water[place.waterKey] ?? 0
            let wAfter = wBefore + s.distance
            water[place.waterKey] = wAfter
            for km in waterKm where wBefore < Double(km) * 1000 && wAfter >= Double(km) * 1000 {
                out.append(Milestone(kind: .water(key: place.waterKey, name: place.waterName, km: km),
                                     reachedAt: s.start, workoutId: s.id))
            }
            if let c = place.countryCode, let all = countryCourses[c], all.count >= minimumCoursesPerCountry {
                let had = rowed[c, default: []]
                let now = had.union([cid])
                rowed[c] = now
                if had.count < all.count, now.isSuperset(of: all), !had.isSuperset(of: all) {
                    out.append(Milestone(kind: .country(code: c, name: countryNames[c] ?? c, courses: all.count),
                                         reachedAt: s.start, workoutId: s.id))
                }
            }
        }
        return out
    }

    /// Meilensteine, die genau diese Fahrt erreicht hat
    public static func reached(by workoutId: UUID, sessions: [TrainingSession], places: [CoursePlace]) -> [Milestone] {
        reached(sessions: sessions, places: places).filter { $0.workoutId == workoutId }
    }

    /// Höchstens ein naher Meilenstein, der in 1–2 Fahrten erreichbar ist (Länge einer typischen Fahrt: Median der
    /// letzten 5). Vorrang: weniger Fahrten nötig, dann Land, Gewässer (auf der vorgeschlagenen Strecke),
    /// Lebens-Kilometer, Fahrten. nil, wenn nichts nah ist oder es weniger als 3 Fahrten gibt.
    public static func next(sessions all: [TrainingSession], places: [CoursePlace],
                            suggestedCourseId: String? = nil) -> MilestoneProgress? {
        let sessions = all.filter { $0.countsInStats }.sorted { $0.start < $1.start }
        guard sessions.count >= 3 else { return nil }
        let recent = sessions.suffix(5).map(\.distance).sorted()
        let typical = max(recent[recent.count / 2], 1000)
        func rides(for meters: Double) -> Int? {
            let n = Int((meters / typical).rounded(.up))
            return n <= 2 ? max(n, 1) : nil
        }
        var candidates: [(rank: Int, MilestoneProgress)] = []
        let total = sessions.reduce(0) { $0 + $1.distance }
        if let km = lifetimeKm.first(where: { Double($0) * 1000 > total }), let n = rides(for: Double(km) * 1000 - total) {
            candidates.append((2, MilestoneProgress(kind: .lifetimeDistance(km: km), remaining: Double(km) * 1000 - total,
                                                    ridesNeeded: n)))
        }
        if let count = rideCounts.first(where: { $0 > sessions.count }), count - sessions.count <= 2 {
            candidates.append((3, MilestoneProgress(kind: .rides(count), remaining: Double(count - sessions.count),
                                                    ridesNeeded: count - sessions.count)))
        }
        let byCourse = Dictionary(places.map { ($0.courseId, $0) }, uniquingKeysWith: { a, _ in a })
        if let cid = suggestedCourseId, let place = byCourse[cid] {
            let done = sessions.filter { $0.courseId.flatMap { byCourse[$0]?.waterKey } == place.waterKey }
                .reduce(0) { $0 + $1.distance }
            if done > 0, let km = waterKm.first(where: { Double($0) * 1000 > done }),
               let n = rides(for: Double(km) * 1000 - done) {
                candidates.append((1, MilestoneProgress(kind: .water(key: place.waterKey, name: place.waterName, km: km),
                                                        remaining: Double(km) * 1000 - done, ridesNeeded: n)))
            }
            if let c = place.countryCode {
                let all = Set(places.filter { $0.countryCode == c }.map(\.courseId))
                let rowed = Set(sessions.compactMap(\.courseId)).intersection(all)
                if all.count >= minimumCoursesPerCountry, all.count - rowed.count == 1, !rowed.contains(cid) {
                    candidates.append((0, MilestoneProgress(kind: .country(code: c, name: place.countryName ?? c,
                                                                            courses: all.count),
                                                            remaining: 1, ridesNeeded: 1)))
                }
            }
        }
        return candidates.min { a, b in
            a.1.ridesNeeded != b.1.ridesNeeded ? a.1.ridesNeeded < b.1.ridesNeeded : a.rank < b.rank
        }?.1
    }
}
