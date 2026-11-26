import Foundation

/// Eine Zeile „Was heute gut war“ in der Auswertung (docs/motivation/RECHERCHE.md Katalog #1): immer wahr, aus
/// festen Regeln, höchstens drei, nach Rangfolge. Rückmeldung zur Kompetenz, nie ein Vergleich nach unten.
public struct RideHighlight: Equatable, Sendable {
    public enum Kind: String, Sendable, CaseIterable {
        case courseBest, personalRecord, milestone, fastestInterval, steadyIntervals, comeback, heartRateLower,
             weeklyGoal, zoneHeld, restRule, effort, presence
    }

    public var kind: Kind
    public var text: String

    /// Rekord oder Meilenstein (Coach-Satz Stufe 2)
    public var isRecord: Bool { kind == .courseBest || kind == .personalRecord || kind == .milestone }

    public init(kind: Kind, text: String) {
        self.kind = kind
        self.text = text
    }
}

/// Regeln für „Was heute gut war“ in dieser Rangfolge (die ersten drei zutreffenden):
/// 1. neue Bestzeit auf der Strecke (ganze freie Fahrt, schneller als alle früheren ganzen Fahrten)
/// 2. neue Bestmarken je Distanz oder Zeit (auch als Teilstück; nur wenn es vorher schon einen Wert gab)
/// 3. Meilenstein erreicht
/// 4. schnellstes Intervall dieses Programms (gegenüber allen früheren Fahrten mit demselben Programm)
/// 5. Intervalle gleichmässig (mindestens 3, alle innerhalb von 3 s/500 m, also ±1,5 s)
/// 6. wieder da nach mindestens 7 Tagen ohne Fahrt (ohne die Tage zu nennen)
/// 7. Puls tiefer bei gleichem Tempo als vor 4–8 Wochen (lockere Fahrten ab 15 min, Tempo ±2 s, mindestens
///    4 Schläge tiefer als der Schnitt der Vergleichsfahrten)
/// 8. Wochenziel mit dieser Fahrt erreicht
/// 9. Zielbereich gehalten: lockere Fahrt ab 15 min mit Puls, mindestens 85 % der Zeit bis Zone 2
/// 10. Erholungsregel eingehalten: locker nach einer harten oder mittleren Einheit vor weniger als 48 h
/// Gibt es nichts davon: Anstrengung ab 7 würdigen, sonst das Dabeisein (Minuten auf dem Wasser).
public enum RideHighlights {
    public static let maxLines = 3

    /// - Parameters:
    ///   - ride: die Fahrt
    ///   - history: andere Fahrten (nur frühere zählen; Simulator nie)
    ///   - milestones: Meilensteine, die diese Fahrt erreicht hat (leer, wenn Meilensteine aus sind)
    ///   - goal: Wochenziel (nil = ohne Zeile zum Wochenziel)
    public static func make(ride: RideDigest, history: [RideDigest], milestones: [Milestone] = [],
                            goal: WeeklyGoal? = nil, pauses: [GoalPause] = [],
                            calendar cal: Calendar = TrainingCalendar.swiss(),
                            best2k: Double = PaceTargets.defaultBest2k) -> [RideHighlight] {
        let s = ride.session
        guard s.countsInStats else { return [] }
        let earlier = history.filter { $0.id != ride.id && $0.session.countsInStats && $0.session.start < s.start }
            .sorted { $0.session.start < $1.session.start }
        let earlierSessions = earlier.map(\.session)
        var out: [RideHighlight] = []
        func add(_ kind: RideHighlight.Kind, _ text: String) {
            guard out.count < maxLines, !out.contains(where: { $0.kind == kind }) else { return }
            out.append(RideHighlight(kind: kind, text: text))
        }

        // 1. Bestzeit auf der Strecke
        if s.isFullCourseRun, let key = s.courseKey,
           let prev = earlierSessions.filter({ $0.courseKey == key && $0.isFullCourseRun }).map(\.activeDuration).min(),
           s.activeDuration < prev - 0.5 {
            let faster = max(Int((prev - s.activeDuration).rounded()), 1)
            let place = s.courseTitle ?? String(localized: "dieser Strecke")
            add(.courseBest, String(localized: "Neue Bestzeit auf \(place): \(Format.duration(s.activeDuration)), \(faster) s schneller."))
        }
        // 2. Bestmarken je Distanz und Zeit (die volle Strecke steht schon in 1)
        let records = PersonalRecords.improvements(in: ride, history: earlier)
        if !records.isEmpty {
            let shown = Array(records.prefix(3))
            if shown.count == 1, let r = shown.first {
                let target = r.target.title, value = r.target.formatted(r.value)
                add(.personalRecord, r.target.isDistance
                    ? String(localized: "Neue Bestmarke über \(target): \(value).")
                    : String(localized: "Neue Bestmarke in \(target): \(value)."))
            } else {
                let list = shown.map { "\($0.target.title) (\($0.target.formatted($0.value)))" }.joined(separator: ", ")
                add(.personalRecord, String(localized: "Neue Bestmarken: \(list)."))
            }
        }
        // 3. Meilenstein
        if let m = milestones.first {
            let title = m.title
            add(.milestone, String(localized: "Meilenstein: \(title)."))
        }
        // 4. schnellstes Intervall dieses Programms
        if let planId = s.planId, let best = ride.workPaces.min() {
            let before = earlier.filter { $0.session.planId == planId }.flatMap(\.workPaces).min()
            if let before, best < before - 0.2 {
                let name = s.planName ?? planId
                add(.fastestInterval, String(localized: "Schnellstes Intervall in \(name) bisher: \(Format.pace(best)) /500 m."))
            }
        }
        // 5. gleichmässige Intervalle
        if ride.workPaces.count >= 3, let lo = ride.workPaces.min(), let hi = ride.workPaces.max(), hi - lo <= 3 {
            let n = ride.workPaces.count
            let spread = decimal(hi - lo)
            add(.steadyIntervals, String(localized: "Gleichmässig: alle \(n) Intervalle innerhalb von \(spread) s/500 m."))
        }
        // 6. wieder da
        if let last = earlierSessions.last, s.start.timeIntervalSince(last.start) >= 7 * 86400 {
            add(.comeback, String(localized: "Wieder drin – schön, dass du auf dem Wasser bist."))
        }
        // 7. Puls tiefer bei gleichem Tempo
        if let line = heartRateLine(s, earlier: earlierSessions, best2k: best2k) { add(.heartRateLower, line) }
        // 8. Wochenziel erreicht
        if let goal {
            let weekStart = TrainingStats.weekStart(of: s.start, cal)
            let inWeek = earlierSessions.filter { $0.start >= weekStart }
            let target = goal.target(freeDays: pauses.freeDays(weekStart: weekStart, calendar: cal))
            let before = goal.progress(sessions: inWeek.count, minutes: inWeek.reduce(0) { $0 + $1.activeDuration } / 60)
            let after = goal.progress(sessions: inWeek.count + 1,
                                      minutes: (inWeek.reduce(0) { $0 + $1.activeDuration } + s.activeDuration) / 60)
            if target > 0, before < target, after >= target {
                let title = goal.title
                add(.weeklyGoal, String(localized: "Wochenziel erreicht: \(title)."))
            }
        }
        let level = s.intensity(best2k: best2k)
        // 9. Zielbereich gehalten
        if level == .easy, let z = s.zoneSeconds, z.count >= 6, s.activeDuration >= 900 {
            let total = z.reduce(0, +)
            if total >= 600 {
                let share = (z[0] + z[1] + z[2]) / total
                if share >= 0.85 {
                    let pct = Int((share * 100).rounded())
                    add(.zoneHeld, String(localized: "Locker geblieben: \(pct) % der Zeit bis Zone 2."))
                }
            }
        }
        // 10. Erholung eingehalten
        if level == .easy, let prev = earlierSessions.last, prev.intensity(best2k: best2k) >= .moderate,
           s.start.timeIntervalSince(prev.start) < 48 * 3600 {
            add(.restRule, String(localized: "Nach der harten Einheit locker gefahren – genau richtig für die Erholung."))
        }
        // Rückfall: Anstrengung oder Dabeisein
        if out.isEmpty {
            if let effort = s.effortScore, effort >= 7 {
                add(.effort, String(localized: "Viel gegeben: Anstrengung \(effort) von 10."))
            } else {
                let minutes = max(Int((s.activeDuration / 60).rounded()), 1)
                add(.presence, String(localized: "\(minutes) min auf dem Wasser – Dranbleiben zählt."))
            }
        }
        return out
    }

    /// Regel 7
    static func heartRateLine(_ s: TrainingSession, earlier: [TrainingSession], best2k: Double) -> String? {
        guard s.intensity(best2k: best2k) == .easy, let hr = s.averageHeartRate, s.averagePace > 0,
              s.activeDuration >= 900 else { return nil }
        let from = s.start.addingTimeInterval(-56 * 86400), to = s.start.addingTimeInterval(-28 * 86400)
        let similar = earlier.filter {
            $0.start >= from && $0.start <= to && $0.intensity(best2k: best2k) == .easy && $0.averageHeartRate != nil
                && $0.averagePace > 0 && abs($0.averagePace - s.averagePace) <= 2 && $0.activeDuration >= 900
        }
        guard !similar.isEmpty else { return nil }
        let mean = Double(similar.compactMap(\.averageHeartRate).reduce(0, +)) / Double(similar.count)
        let n = Int((mean - Double(hr)).rounded())
        guard n >= 4, let newest = similar.map(\.start).max() else { return nil }
        let weeks = max(Int((s.start.timeIntervalSince(newest) / (7 * 86400)).rounded()), 4)
        return String(localized: "Gleiches Tempo wie vor \(weeks) Wochen, Puls \(n) Schläge tiefer.")
    }

    /// Eine Nachkommastelle mit dem Dezimaltrennzeichen der Sprache
    static func decimal(_ v: Double) -> String {
        String(format: "%.1f", v).replacingOccurrences(of: ".", with: Locale.current.decimalSeparator ?? ".")
    }
}

/// Coach-Satz nach der Fahrt (Szenario `post_ride` in coach_phrases.json): Stufe 2 nach einem Rekord oder
/// Meilenstein, sonst Stufe 1 (Anstrengung und Dabeisein würdigen). Nur statische Varianten, damit es immer eine
/// Tonkonserve gibt.
public enum PostRideCoach {
    public static func level(for highlights: [RideHighlight]) -> Int {
        highlights.contains(where: \.isRecord) ? 2 : 1
    }

    public static func phrase(highlights: [RideHighlight], bank: CoachPhraseBank, style: CoachStyle,
                              language: String, seed: UInt64) -> CoachPhrase? {
        guard style != .off else { return nil }
        var picker = CoachPhrasePicker(bank: bank, seed: seed)
        return picker.pick(.postRide, level: level(for: highlights), style: style, language: language)
    }
}
