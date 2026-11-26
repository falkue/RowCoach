import Foundation

/// Erholungs-Wächter (docs/motivation/RECHERCHE.md Katalog #12, Ton und Ethik 4): eine Querschnittsregel für alle
/// Motivationsfunktionen. Solange Erholung empfohlen ist, schweigen Bestfahrt-Angebote und Herausforderungen,
/// Erinnerungen schlagen nichts Hartes vor, und die Startseite lobt den Ruhetag statt zu drängen. Nie sperren,
/// immer begründen.
///
/// Erholung empfohlen, wenn (erste zutreffende Regel):
/// 1. eine harte oder mittlere Einheit vor weniger als 48 h (wie `DailySuggestion` Regel 1) bzw. eine harte vor
///    weniger als `hardGapHours` (Masters-Pläne 72 h),
/// 2. die letzte Fahrt mit Anstrengung ≥ 9 vor weniger als 48 h,
/// 3. lockere Einheiten zu hart empfunden (RPE-Regel 5.5: die letzten 3 leichten mit Anstrengung ≥ 7 oder die letzten
///    2 mit ≥ 9, die letzte davon vor höchstens 7 Tagen),
/// 4. der Trainingsplan Erholung oder Pause vorschlägt (`planRecovery`, aus den Hinweisen des Plans),
/// 5. heute laut Plan Ruhetag ist (`planRestDay`).
public struct RecoveryState: Equatable, Sendable {
    public enum Reason: String, Sendable {
        case recentHard, recentModerate, highEffort, easyFeltHard, planRecovery, planRestDay
    }

    public var reason: Reason?
    /// bis wann die Regel gilt (bei 1 und 2); nil = offen
    public var until: Date?

    public var recoveryRecommended: Bool { reason != nil }
    /// Bestfahrt-Angebote, Herausforderungen und Rekord-Hinweise schweigen
    public var silencesChallenges: Bool { reason != nil }

    public static let none = RecoveryState(reason: nil, until: nil)

    /// Kurze Begründung für die Startseite („Erholung gehört zum Training“), ohne Vorwurf
    public var text: String? {
        switch reason {
        case .recentHard, .recentModerate:
            return String(localized: "Nach der harten Einheit ist heute Erholung dran – sie gehört zum Training.")
        case .highEffort:
            return String(localized: "Die letzte Fahrt war sehr anstrengend. Heute locker oder Ruhetag.")
        case .easyFeltHard:
            return String(localized: "Lockere Fahrten fühlten sich zuletzt hart an. Ein Ruhetag tut jetzt gut.")
        case .planRecovery:
            return String(localized: "Dein Plan empfiehlt gerade Erholung.")
        case .planRestDay:
            return String(localized: "Heute ist Ruhetag laut Plan – Erholung gehört zum Training.")
        case nil:
            return nil
        }
    }
}

public enum RecoveryGuard {
    public static func state(sessions all: [TrainingSession], now: Date,
                             calendar cal: Calendar = TrainingCalendar.swiss(),
                             best2k: Double = PaceTargets.defaultBest2k, hardGapHours: Int = 48,
                             planRecovery: Bool = false, planRestDay: Bool = false) -> RecoveryState {
        let sessions = all.filter { $0.countsInStats && $0.start <= now }.sorted { $0.start < $1.start }
        let h: TimeInterval = 3600
        // 1. harte bzw. mittlere Einheit
        if let hard = sessions.last(where: { $0.intensity(best2k: best2k) == .hard }) {
            let gap = Double(max(hardGapHours, 48)) * h
            if now.timeIntervalSince(hard.start) < gap {
                return RecoveryState(reason: .recentHard, until: hard.start.addingTimeInterval(gap))
            }
        }
        if let mid = sessions.last(where: { $0.intensity(best2k: best2k) == .moderate }),
           now.timeIntervalSince(mid.start) < 48 * h {
            return RecoveryState(reason: .recentModerate, until: mid.start.addingTimeInterval(48 * h))
        }
        // 2. sehr hohe Anstrengung
        if let last = sessions.last, (last.effortScore ?? 0) >= 9, now.timeIntervalSince(last.start) < 48 * h {
            return RecoveryState(reason: .highEffort, until: last.start.addingTimeInterval(48 * h))
        }
        // 3. leichte Einheiten zu hart empfunden
        let easy = sessions.filter { $0.intensity(best2k: best2k) == .easy && $0.effortScore != nil }
        if let last = easy.last, now.timeIntervalSince(last.start) <= 7 * 86400 {
            let three = easy.suffix(3), two = easy.suffix(2)
            if (three.count == 3 && three.allSatisfy { ($0.effortScore ?? 0) >= 7 })
                || (two.count == 2 && two.allSatisfy { ($0.effortScore ?? 0) >= 9 }) {
                // gilt am Tag der letzten dieser Fahrten und am Folgetag
                let until = cal.date(byAdding: .day, value: 2, to: cal.startOfDay(for: last.start))
                if until.map({ now < $0 }) ?? true {
                    return RecoveryState(reason: .easyFeltHard, until: until)
                }
            }
        }
        if planRecovery { return RecoveryState(reason: .planRecovery, until: nil) }
        if planRestDay { return RecoveryState(reason: .planRestDay, until: nil) }
        return .none
    }

    /// Lob für einen gehaltenen Ruhetag: gestern keine Fahrt, aber vorgestern eine harte Einheit (oder gestern laut
    /// Plan Ruhetag), heute noch keine Fahrt. nil sonst.
    public static func restDayPraise(sessions all: [TrainingSession], now: Date,
                                     calendar cal: Calendar = TrainingCalendar.swiss(),
                                     best2k: Double = PaceTargets.defaultBest2k,
                                     yesterdayWasPlanRest: Bool = false) -> String? {
        let sessions = all.filter { $0.countsInStats && $0.start <= now }
        let today = cal.startOfDay(for: now)
        guard let yesterday = cal.date(byAdding: .day, value: -1, to: today),
              let before = cal.date(byAdding: .day, value: -2, to: today) else { return nil }
        let onDay = { (d: Date) in sessions.filter { cal.isDate($0.start, inSameDayAs: d) } }
        guard onDay(today).isEmpty, onDay(yesterday).isEmpty else { return nil }
        let hardBefore = onDay(before).contains { $0.intensity(best2k: best2k) >= .moderate }
        guard hardBefore || (yesterdayWasPlanRest && !sessions.isEmpty) else { return nil }
        return String(localized: "Ruhetag gehalten – so wirkt das Training. Heute bist du wieder frisch.")
    }
}
