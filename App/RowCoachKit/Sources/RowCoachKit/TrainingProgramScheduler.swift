import Foundation

// Verteilung der Einheiten einer Planwoche auf die Wunschtage (docs/trainingsplaene/RECHERCHE.md 5.1).

extension PlanIntensity: Codable {}

/// Wochentag nach ISO (Montag = 1 … Sonntag = 7)
public enum Weekday: Int, Codable, CaseIterable, Sendable, Comparable, Identifiable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday

    public var id: Int { rawValue }

    public static func < (a: Weekday, b: Weekday) -> Bool { a.rawValue < b.rawValue }

    public static func of(_ date: Date, calendar: Calendar) -> Weekday {
        let wd = calendar.component(.weekday, from: date) // 1 = Sonntag … 7 = Samstag
        return Weekday(rawValue: (wd + 5) % 7 + 1) ?? .monday
    }

    /// „Mo“, „Di“, …
    public var shortLabel: String {
        switch self {
        case .monday: return String(localized: "Mo")
        case .tuesday: return String(localized: "Di")
        case .wednesday: return String(localized: "Mi")
        case .thursday: return String(localized: "Do")
        case .friday: return String(localized: "Fr")
        case .saturday: return String(localized: "Sa")
        case .sunday: return String(localized: "So")
        }
    }

    /// „Montag“, …
    public var label: String {
        switch self {
        case .monday: return String(localized: "Montag")
        case .tuesday: return String(localized: "Dienstag")
        case .wednesday: return String(localized: "Mittwoch")
        case .thursday: return String(localized: "Donnerstag")
        case .friday: return String(localized: "Freitag")
        case .saturday: return String(localized: "Samstag")
        case .sunday: return String(localized: "Sonntag")
        }
    }
}

/// Warum ein Plan nicht startbar ist
public enum ProgramStartProblem: Error, Equatable, Sendable {
    /// weniger Wunschtage als Pflicht-Einheiten pro Woche
    case tooFewDays(needed: Int)
    /// Plan ohne Wochen
    case emptyProgram

    public var message: String {
        switch self {
        case .tooFewDays(let n):
            return String(localized: "Bitte mindestens \(n) Tage wählen. Weniger Zeit? Ein Plan mit weniger Einheiten passt besser, z. B. „Form halten“ mit 2 Einheiten.")
        case .emptyProgram:
            return String(localized: "Dieser Plan hat keine Wochen.")
        }
    }
}

/// Reine Funktionen für die Verteilung auf Tage. Tage sind fortlaufende Tagesnummern (siehe `ProgramDays`).
public enum TrainingProgramScheduler {
    /// Vorschlag für die Wunschtage je nach Zahl der Einheiten (Einsteiger mit Ruhetag dazwischen)
    public static func suggestedWeekdays(count: Int, maxConsecutiveDays: Int = 2) -> [Weekday] {
        switch count {
        case ...1: return [.saturday]
        case 2: return [.tuesday, .saturday]
        case 3: return [.monday, .wednesday, .friday]
        case 4: return maxConsecutiveDays >= 2 ? [.monday, .wednesday, .friday, .saturday]
            : [.monday, .wednesday, .friday, .sunday]
        case 5: return [.monday, .tuesday, .thursday, .friday, .sunday]
        case 6: return [.monday, .tuesday, .wednesday, .thursday, .saturday, .sunday]
        default: return Weekday.allCases
        }
    }

    /// Prüft die Wunschtage für einen Plan (RECHERCHE 5.1, Punkt 1)
    public static func check(weekdays: Set<Weekday>, program: TrainingProgram) -> ProgramStartProblem? {
        guard program.weeks > 0 else { return .emptyProgram }
        let need = max(1, program.sessionsPerWeek.lowerBound)
        return weekdays.count < need ? .tooFewDays(needed: need) : nil
    }

    /// Eine zu verteilende Einheit
    struct Item: Equatable {
        var key: Int
        var hard: Bool
        var event: Bool
    }

    /// Ergebnis der Verteilung einer Woche
    struct WeekPlacement: Equatable {
        /// Einheit (key) → Tagesnummer
        var days: [Int: Int] = [:]
        /// harte Einheiten, die durch die leichte Variante ersetzt werden müssen
        var replaced: Set<Int> = []
        /// Pflicht-Einheiten ohne Tag (weniger Tage als Einheiten)
        var dropped: Set<Int> = []
    }

    /// Gilt die Belegung für die Tage in `focus`? Belegung: Tagesnummer → hart.
    /// - harte Einheiten mindestens `hardGapDays` auseinander (48 h → 2 Tage, 72 h → 3), auch über die Wochengrenze
    /// - höchstens `maxConsecutive` Trainingstage hintereinander
    static func valid(_ map: [Int: Bool], focus: [Int], gapDays: Int, maxConsecutive: Int) -> Bool {
        for d in focus {
            if map[d] == true {
                for (e, h) in map where h && e != d && abs(e - d) < gapDays { return false }
            }
            var len = 1
            var x = d - 1
            while map[x] != nil { len += 1; x -= 1 }
            x = d + 1
            while map[x] != nil { len += 1; x += 1 }
            if len > maxConsecutive { return false }
        }
        return true
    }

    /// Verteilt `required` (in Slot-Reihenfolge) und danach `optional` auf `candidates` (Tagesnummern, freie Wunschtage).
    /// `fixed` sind schon belegte Tage (erledigte oder geplante Einheiten, auch der Vorwoche).
    ///
    /// Vorgehen (RECHERCHE 5.1, Punkt 2): Pflicht-Einheiten in Slot-Reihenfolge auf die frühesten Wunschtage; verletzt
    /// das eine Regel, zuerst innerhalb derselben Tage tauschen (wenigste Vertauschungen), dann spätere Wunschtage,
    /// dann harte Einheiten durch die leichte Variante ersetzen (spätere zuerst), zuletzt die Regel „höchstens n Tage
    /// hintereinander“ lockern. Freiwillige Einheiten kommen auf übrige Tage, wenn die Regeln es erlauben, sonst
    /// entfallen sie. Gibt es weniger Tage als Pflicht-Einheiten, fallen leichte Einheiten vom Ende weg (nie die
    /// Zieleinheit).
    static func placeWeek(required: [Item], optional: [Item], candidates: [Int], fixed: [Int: Bool],
                          rules: ProgramRules) -> WeekPlacement {
        let days = Array(Set(candidates).subtracting(fixed.keys)).sorted()
        var result = WeekPlacement()
        var req = required
        while req.count > days.count {
            guard let i = req.lastIndex(where: { !$0.event && !$0.hard }) ?? req.lastIndex(where: { !$0.event })
                    ?? req.indices.last else { break }
            result.dropped.insert(req[i].key)
            req.remove(at: i)
        }
        let gap = rules.hardGapDays
        var chosen: [Int]?
        chosen = assign(req, days: days, fixed: fixed, gapDays: gap, maxConsecutive: rules.maxConsecutiveDays)
        if chosen == nil {
            // harte Einheiten (ohne Zieleinheit) ersetzen: erst eine, dann zwei …, spätere zuerst
            let hardIdx = req.indices.filter { req[$0].hard && !req[$0].event }.reversed().map { $0 }
            search: for size in stride(from: 1, through: hardIdx.count, by: 1) {
                for combo in combinations(hardIdx, size) {
                    var trial = req
                    for i in combo { trial[i].hard = false }
                    if let c = assign(trial, days: days, fixed: fixed, gapDays: gap,
                                      maxConsecutive: rules.maxConsecutiveDays) {
                        chosen = c
                        result.replaced = Set(combo.map { req[$0].key })
                        req = trial
                        break search
                    }
                }
            }
        }
        if chosen == nil {
            var trial = req
            var replaced = Set<Int>()
            for i in trial.indices where trial[i].hard && !trial[i].event {
                trial[i].hard = false
                replaced.insert(trial[i].key)
            }
            if let c = assign(trial, days: days, fixed: fixed, gapDays: gap, maxConsecutive: 99) {
                chosen = c
                result.replaced = replaced
                req = trial
            } else {
                // letzter Ausweg: der Reihe nach auf die ersten Tage
                chosen = Array(days.prefix(trial.count))
                result.replaced = replaced
                req = trial
            }
        }
        var map = fixed
        for (i, item) in req.enumerated() {
            guard let d = chosen?[i] else { continue }
            result.days[item.key] = d
            map[d] = item.hard
        }
        for item in optional {
            for d in days where map[d] == nil {
                var trial = map
                trial[d] = item.hard
                if valid(trial, focus: [d], gapDays: gap, maxConsecutive: rules.maxConsecutiveDays) {
                    map = trial
                    result.days[item.key] = d
                    break
                }
            }
        }
        return result
    }

    /// Tag je Einheit (gleiche Reihenfolge wie `items`) oder nil, wenn keine Belegung alle Regeln einhält.
    /// Untermengen der Tage in lexikografischer Reihenfolge (früheste zuerst); je Untermenge die Anordnung mit den
    /// wenigsten Vertauschungen gegenüber der Slot-Reihenfolge.
    static func assign(_ items: [Item], days: [Int], fixed: [Int: Bool], gapDays: Int, maxConsecutive: Int) -> [Int]? {
        let n = items.count
        guard n > 0 else { return [] }
        guard n <= days.count else { return nil }
        let perms = permutationsByInversions(n)
        for subset in combinations(days, n) {
            for perm in perms {
                var map = fixed
                for i in 0..<n { map[subset[i]] = items[perm[i]].hard }
                if valid(map, focus: subset, gapDays: gapDays, maxConsecutive: maxConsecutive) {
                    var out = [Int](repeating: 0, count: n)
                    for i in 0..<n { out[perm[i]] = subset[i] }
                    return out
                }
            }
        }
        return nil
    }

    /// Alle k-Teilmengen in lexikografischer Reihenfolge
    static func combinations<T>(_ list: [T], _ k: Int) -> [[T]] {
        guard k > 0 else { return [[]] }
        guard k <= list.count else { return [] }
        var out: [[T]] = []
        var idx = Array(0..<k)
        while true {
            out.append(idx.map { list[$0] })
            var i = k - 1
            while i >= 0 && idx[i] == list.count - k + i { i -= 1 }
            if i < 0 { break }
            idx[i] += 1
            for j in (i + 1)..<k { idx[j] = idx[j - 1] + 1 }
        }
        return out
    }

    /// Alle Permutationen von 0..<n, sortiert nach Zahl der Vertauschungen (Identität zuerst)
    static func permutationsByInversions(_ n: Int) -> [[Int]] {
        var out: [[Int]] = []
        func rec(_ prefix: [Int], _ rest: [Int]) {
            if rest.isEmpty { out.append(prefix); return }
            for (i, x) in rest.enumerated() {
                var r = rest
                r.remove(at: i)
                rec(prefix + [x], r)
            }
        }
        rec([], Array(0..<n))
        func inversions(_ p: [Int]) -> Int {
            var c = 0
            for i in 0..<p.count { for j in (i + 1)..<p.count where p[i] > p[j] { c += 1 } }
            return c
        }
        return out.enumerated().sorted { a, b in
            let ia = inversions(a.element), ib = inversions(b.element)
            return ia != ib ? ia < ib : a.offset < b.offset
        }.map(\.element)
    }
}

/// Tagesnummern im Kalender (fortlaufend, unabhängig von Sommerzeit)
public struct ProgramDays: Sendable {
    public let calendar: Calendar
    private let reference: Date

    public init(calendar: Calendar) {
        self.calendar = calendar
        reference = calendar.startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))
    }

    public func number(_ date: Date) -> Int {
        calendar.dateComponents([.day], from: reference, to: calendar.startOfDay(for: date)).day ?? 0
    }

    public func date(_ number: Int) -> Date {
        calendar.date(byAdding: .day, value: number, to: reference) ?? reference.addingTimeInterval(Double(number) * 86400)
    }

    public func startOfDay(_ date: Date) -> Date { calendar.startOfDay(for: date) }

    public func weekday(_ number: Int) -> Weekday { Weekday.of(date(number), calendar: calendar) }
}
