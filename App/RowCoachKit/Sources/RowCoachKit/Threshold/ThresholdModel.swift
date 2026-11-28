import Foundation

// Schwellenprofil: Schätzungen der Schwellenleistung T (Watt, etwa 30 min haltbar) mit Quelle, Datum und
// Unsicherheit, dazu Pulsprofil und persönliche Kalibrierung (docs/schwelle/SPEC.md, Abschnitt 1). Nur Foundation.

/// Woher eine Schätzung stammt (als Text gespeichert, unbekannte Werte bleiben lesbar)
public enum ThresholdSourceKind: String, Codable, Sendable, CaseIterable {
    /// Eingabe Watt
    case manualPower
    /// Eingabe Tempo /500 m an der Schwelle
    case manualPace
    /// Eingabe 2k-Bestzeit (Profil)
    case manual2k
    /// Altwert aus `TrainingSettings.best2k` bei der Migration
    case legacy2k
    /// Zeitfahren mit fester Zeit oder Distanz (2000 m, 20/30/60 min, 5000 m …)
    case timeTrial
    /// Rampentest
    case ramp
    /// 3-min-All-out (Endleistung ≈ CP)
    case allOut3min
    /// Stufentest: Leistung beim Schwellenpuls
    case stepHR
    /// Stufentest: DFA-α1 (experimentell)
    case stepDFA
    /// CP aus 2–3 maximalen Efforts (Fahrten)
    case criticalPowerFit
    /// beste maximale 8–60-min-Leistung aus Fahrten
    case ridesAuto

    /// Eingabe der Person (wird nie automatisch abgelöst)
    public var isManual: Bool { self == .manualPower || self == .manualPace || self == .manual2k }

    /// Ergebnis eines Testprogramms
    public var isTest: Bool {
        switch self {
        case .timeTrial, .ramp, .allOut3min, .stepHR, .stepDFA: return true
        default: return false
        }
    }

    /// Anzeigename der Quelle
    public var title: String {
        switch self {
        case .manualPower: return String(localized: "Eingabe Watt")
        case .manualPace: return String(localized: "Eingabe Tempo")
        case .manual2k: return String(localized: "Eingabe 2000-m-Bestzeit")
        case .legacy2k: return String(localized: "2000-m-Bestzeit (bisher)")
        case .timeTrial: return String(localized: "Zeitfahren")
        case .ramp: return String(localized: "Rampentest")
        case .allOut3min: return String(localized: "3 min All-out")
        case .stepHR: return String(localized: "Stufentest mit Puls")
        case .stepDFA: return String(localized: "Stufentest DFA-alpha1 (experimentell)")
        case .criticalPowerFit: return String(localized: "Critical Power aus Fahrten")
        case .ridesAuto: return String(localized: "aus deinen Fahrten")
        }
    }
}

/// Prüfhinweis einer Auswertung (als Text gespeichert)
public enum EvaluationNote: String, Codable, Sendable, CaseIterable {
    /// zu wenige auswertbare Stufen oder Werte
    case notEvaluable
    /// Testphase unterbrochen oder mehr als 15 s ohne Schlag
    case interrupted
    /// zu kurz für eine Schwelle (500 m, 100 m, 1 min): nur Bestmarke
    case noThreshold
    /// 20 min: erste 5 min deutlich schneller als der Rest
    case tooFastStart
    /// 3 min: eingeteilt statt all-out
    case notAllOut
    /// Rampe kürzer als 6 min (Start zu hoch)
    case rampTooShort
    /// Rampe länger als 20 min (Start zu tief)
    case rampTooLong
    /// Stufentest: Puls-Leistungs-Gerade unregelmässig (r² < 0,9 oder Steigung ≤ 0)
    case irregularHeartRate
    /// Stufentest: Schwellenpuls mehr als 15 Schläge über der höchsten Stufe
    case extrapolatedTooFar
    /// Stufentest: Schwellenpuls 5–15 Schläge über der höchsten Stufe
    case extrapolated
    /// Puls fehlt oder lückenhaft
    case heartRateMissing
    /// Maximalpuls nur geschätzt (Alter oder Standard)
    case maxHREstimated
    /// Talk-Test passt nicht zum Puls
    case talkMismatch
    /// Puls und DFA-α1 weichen um mehr als 10 % ab
    case dfaDisagrees
    /// Maximalität nur aus dem Puls erkannt (Fahrten-Automatik)
    case maximalFromHeartRate

    /// Ergebnis darf nie automatisch aktiv werden
    public var blocksActivation: Bool {
        switch self {
        case .notEvaluable, .interrupted, .noThreshold, .notAllOut, .rampTooShort, .extrapolatedTooFar: return true
        default: return false
        }
    }

    public var title: String {
        switch self {
        case .notEvaluable: return String(localized: "Nicht auswertbar: zu wenige gültige Werte.")
        case .interrupted: return String(localized: "Die Testphase wurde unterbrochen.")
        case .noThreshold: return String(localized: "Zu kurz für eine Schwelle – zählt als Bestmarke.")
        case .tooFastStart: return String(localized: "Zu schnell gestartet: die ersten 5 Minuten waren deutlich stärker als der Rest.")
        case .notAllOut: return String(localized: "Eingeteilt statt all-out – Ergebnis unsicher.")
        case .rampTooShort: return String(localized: "Rampe zu kurz – der Start war zu hoch. Die nächste Rampe beginnt 10 % tiefer.")
        case .rampTooLong: return String(localized: "Rampe sehr lang – die nächste beginnt 10 % höher.")
        case .irregularHeartRate: return String(localized: "Puls unregelmässig – Ergebnis unsicherer.")
        case .extrapolatedTooFar: return String(localized: "Zu weit hochgerechnet – nur als Hinweis.")
        case .extrapolated: return String(localized: "Etwas hochgerechnet – Ergebnis unsicherer.")
        case .heartRateMissing: return String(localized: "Puls fehlt oder ist lückenhaft.")
        case .maxHREstimated: return String(localized: "Maximalpuls nur geschätzt.")
        case .talkMismatch: return String(localized: "Puls und Gefühl passen nicht zusammen.")
        case .dfaDisagrees: return String(localized: "Puls und Herzfrequenzvariabilität weichen voneinander ab.")
        case .maximalFromHeartRate: return String(localized: "Maximale Belastung nur am Puls erkannt.")
        }
    }
}

/// Eine Schätzung der Schwellenleistung
public struct ThresholdEstimate: Codable, Equatable, Sendable, Identifiable {
    public enum Status: String, Sendable {
        case active, candidate, rejected, superseded
    }

    public var id: UUID
    /// `ThresholdSourceKind.rawValue`
    public var kind: String
    /// Datum der Messung bzw. Eingabe
    public var date: Date
    /// T in Watt
    public var powerW: Double
    /// Grundunsicherheit in % (1 Standardabweichung) einschliesslich Aufschlägen
    public var sigmaPct: Double
    /// Testprogramm
    public var planId: String?
    /// Fahrt
    public var workoutId: UUID?
    /// Rohwerte: "p", "t", "t2k", "map", "ep", "cp", "wPrime", "hrT", "slope", "r2", "b" …
    public var details: [String: Double]
    /// `Status.rawValue`
    public var status: String
    /// erster Test dieser Art (Lerneffekt, +2 %)
    public var firstOfKind: Bool
    /// Prüfhinweise (`EvaluationNote.rawValue`)
    public var notes: [String]

    public init(id: UUID = UUID(), kind: ThresholdSourceKind, date: Date, powerW: Double, sigmaPct: Double,
                planId: String? = nil, workoutId: UUID? = nil, details: [String: Double] = [:],
                status: Status = .candidate, firstOfKind: Bool = false, notes: [EvaluationNote] = []) {
        self.id = id
        self.kind = kind.rawValue
        self.date = date
        self.powerW = powerW
        self.sigmaPct = sigmaPct
        self.planId = planId
        self.workoutId = workoutId
        self.details = details
        self.status = status.rawValue
        self.firstOfKind = firstOfKind
        self.notes = notes.map(\.rawValue)
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, date, powerW, sigmaPct, planId, workoutId, details, status, firstOfKind, notes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        kind = (try? c.decode(String.self, forKey: .kind)) ?? ThresholdSourceKind.manualPower.rawValue
        date = try c.decode(Date.self, forKey: .date)
        powerW = try c.decode(Double.self, forKey: .powerW)
        sigmaPct = (try? c.decode(Double.self, forKey: .sigmaPct)) ?? 10
        planId = try? c.decodeIfPresent(String.self, forKey: .planId)
        workoutId = try? c.decodeIfPresent(UUID.self, forKey: .workoutId)
        details = (try? c.decodeIfPresent([String: Double].self, forKey: .details)) ?? [:]
        status = (try? c.decode(String.self, forKey: .status)) ?? Status.candidate.rawValue
        firstOfKind = (try? c.decodeIfPresent(Bool.self, forKey: .firstOfKind)) ?? false
        notes = (try? c.decodeIfPresent([String].self, forKey: .notes)) ?? []
    }

    /// Quelle; nil bei einer unbekannten Art aus einer neueren Version
    public var source: ThresholdSourceKind? { ThresholdSourceKind(rawValue: kind) }
    public var statusValue: Status { Status(rawValue: status) ?? .candidate }
    public var isManual: Bool { source?.isManual ?? false }
    public var evaluationNotes: [EvaluationNote] { notes.compactMap(EvaluationNote.init(rawValue:)) }
    /// Darf nie automatisch aktiv werden (Prüfhinweis wie „nicht all-out“)
    public var isHintOnly: Bool { evaluationNotes.contains { $0.blocksActivation } }
    /// Tempo an der Schwelle (s/500 m)
    public var pace: Double { ThresholdMath.pace(watts: powerW) }
}

/// Pulsprofil (Maximalpuls, Ruhepuls, Schwellenpuls)
public struct HeartProfile: Codable, Equatable, Sendable {
    /// gemessen oder eingegeben
    public var maxHR: Int?
    /// "manual" | "measured" | "tanaka"
    public var maxHRSource: String?
    public var restHR: Int?
    /// Schwellenpuls
    public var lthr: Int?
    /// "manual" | "test30" | "stepDFA"
    public var lthrSource: String?
    public var lthrDate: Date?
    /// nur für den Tanaka-Startwert, optional
    public var birthYear: Int?

    public init(maxHR: Int? = nil, maxHRSource: String? = nil, restHR: Int? = nil, lthr: Int? = nil,
                lthrSource: String? = nil, lthrDate: Date? = nil, birthYear: Int? = nil) {
        self.maxHR = maxHR
        self.maxHRSource = maxHRSource
        self.restHR = restHR
        self.lthr = lthr
        self.lthrSource = lthrSource
        self.lthrDate = lthrDate
        self.birthYear = birthYear
    }

    /// Maximalpuls nach Tanaka (208 − 0,7 × Alter); nil ohne Geburtsjahr
    public func tanakaMaxHR(now: Date, calendar: Calendar = TrainingCalendar.swiss()) -> Int? {
        guard let y = birthYear else { return nil }
        let age = calendar.component(.year, from: now) - y
        guard (10...100).contains(age) else { return nil }
        return Int((208 - 0.7 * Double(age)).rounded())
    }

    /// Alter in Jahren (nil ohne Geburtsjahr)
    public func age(now: Date, calendar: Calendar = TrainingCalendar.swiss()) -> Int? {
        birthYear.map { calendar.component(.year, from: now) - $0 }
    }

    /// Schwellenpuls, wenn vorhanden und höchstens 12 Monate alt (ohne Datum gilt eine Eingabe als aktuell)
    public func currentLTHR(now: Date) -> Int? {
        guard let l = lthr, l > 0 else { return nil }
        if let d = lthrDate, now.timeIntervalSince(d) > 365 * 86400 { return nil }
        return l
    }
}

/// Antworten auf die Gesundheitsfragen vor dem ersten maximalen Test (angelehnt an PAR-Q+, SPEC Abschnitt 9).
/// Bleiben lokal.
public struct HealthScreen: Codable, Equatable, Sendable {
    /// Fragen (ids fest)
    public static let questionIds = ["heart", "chestPain", "dizziness", "chronic", "medication", "supervision",
                                     "pregnancy"]

    public var answeredAt: Date
    /// id → Ja
    public var answers: [String: Bool]
    /// „Ärztliche Freigabe liegt vor“ (Datum); hebt ein Ja auf
    public var clearanceDate: Date?

    public init(answeredAt: Date, answers: [String: Bool], clearanceDate: Date? = nil) {
        self.answeredAt = answeredAt
        self.answers = answers
        self.clearanceDate = clearanceDate
    }

    public var anyYes: Bool { answers.values.contains(true) }
    /// Maximale Tests nicht vorschlagen und vor dem Start „Bitte zuerst ärztlich abklären“
    public var blocksMaximalTests: Bool { anyYes && clearanceDate == nil }
}

/// Schwellenprofil (gespeichert als JSON, `formatVersion`)
public struct ThresholdProfile: Codable, Equatable, Sendable {
    public static let formatVersion = 1
    /// höchstens so viele Schätzungen im Verlauf
    public static let maxEstimates = 100
    public static let defaultExponent = 0.15
    public static let defaultRampFactor = 0.75

    public var version: Int
    /// Verlauf, neueste zuerst; höchstens 100
    public var estimates: [ThresholdEstimate]
    public var heart: HeartProfile
    /// Standard 0,15; persönlich kalibriert
    public var exponentB: Double
    /// "default" | "calibrated"
    public var exponentBSource: String?
    /// Standard 0,75; persönlich kalibriert
    public var rampFactor: Double
    /// Plan-id, z. B. "schwelle-test-20min"; nil = nach Profil
    public var preferredTest: String?
    /// Antworten Gesundheitsfragen (Abschnitt 9)
    public var healthScreen: HealthScreen?
    /// Zuletzt abgelehnter Fahrten-Vorschlag (Watt) und Datum des letzten Vorschlags (höchstens einer je 7 Tage)
    public var lastRideProposalW: Double?
    public var lastRideProposalDate: Date?
    /// Fahrten-Vorschlag mit „Nicht jetzt“ zurückgestellt (Fenster beim App-Start): Watt und Datum. Kein Ablehnen –
    /// das Fenster kommt wieder ab + 2 % oder nach 7 Tagen (`ThresholdDetector.shouldPrompt`); synchronisiert mit dem
    /// Profil, damit ein zweites Gerät nicht erneut fragt.
    public var rideProposalDeferredW: Double?
    public var rideProposalDeferredDate: Date?
    /// Nächste Rampe 10 % tiefer (−1) bzw. höher (+1)
    public var rampStartAdjust: Int?

    public init(estimates: [ThresholdEstimate] = [], heart: HeartProfile = HeartProfile(),
                exponentB: Double = ThresholdProfile.defaultExponent, exponentBSource: String? = "default",
                rampFactor: Double = ThresholdProfile.defaultRampFactor, preferredTest: String? = nil,
                healthScreen: HealthScreen? = nil) {
        version = Self.formatVersion
        self.estimates = estimates
        self.heart = heart
        self.exponentB = exponentB
        self.exponentBSource = exponentBSource
        self.rampFactor = rampFactor
        self.preferredTest = preferredTest
        self.healthScreen = healthScreen
    }

    enum CodingKeys: String, CodingKey {
        case version, estimates, heart, exponentB, exponentBSource, rampFactor, preferredTest, healthScreen
        case lastRideProposalW, lastRideProposalDate, rampStartAdjust
        case rideProposalDeferredW, rideProposalDeferredDate
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? c.decodeIfPresent(Int.self, forKey: .version)) ?? Self.formatVersion
        // einzelne unlesbare Schätzungen überspringen
        estimates = ((try? c.decodeIfPresent([Lossy<ThresholdEstimate>].self, forKey: .estimates)) ?? [])
            .compactMap(\.value)
        heart = (try? c.decodeIfPresent(HeartProfile.self, forKey: .heart)) ?? HeartProfile()
        let b = (try? c.decodeIfPresent(Double.self, forKey: .exponentB)) ?? Self.defaultExponent
        exponentB = (0.05...0.3).contains(b) ? b : Self.defaultExponent
        exponentBSource = try? c.decodeIfPresent(String.self, forKey: .exponentBSource)
        let r = (try? c.decodeIfPresent(Double.self, forKey: .rampFactor)) ?? Self.defaultRampFactor
        rampFactor = (0.6...0.9).contains(r) ? r : Self.defaultRampFactor
        preferredTest = try? c.decodeIfPresent(String.self, forKey: .preferredTest)
        healthScreen = try? c.decodeIfPresent(HealthScreen.self, forKey: .healthScreen)
        lastRideProposalW = try? c.decodeIfPresent(Double.self, forKey: .lastRideProposalW)
        lastRideProposalDate = try? c.decodeIfPresent(Date.self, forKey: .lastRideProposalDate)
        rampStartAdjust = try? c.decodeIfPresent(Int.self, forKey: .rampStartAdjust)
        rideProposalDeferredW = try? c.decodeIfPresent(Double.self, forKey: .rideProposalDeferredW)
        rideProposalDeferredDate = try? c.decodeIfPresent(Date.self, forKey: .rideProposalDeferredDate)
    }

    // MARK: Abfragen

    /// Die aktive Schätzung (nil = noch keine)
    public var active: ThresholdEstimate? { estimates.first { $0.statusValue == .active } }

    /// Schwelle in Watt (nil = noch keine)
    public var thresholdW: Double? { active?.powerW }

    /// 2000-m-Referenz für alle Tempoziele (Spiegel nach `TrainingSettings.best2k`): Stammt die aktive Schwelle aus
    /// einer 2k-Zeit (Eingabe, Altwert, 2000-m-Test), genau diese Zeit, sonst die gleichwertige 2k-Zeit.
    public var mirrorBest2k: Double? {
        guard let a = active else { return nil }
        if let t2k = a.details["t2k"], t2k > 0 { return t2k }
        return ThresholdMath.equivalentBest2k(threshold: a.powerW, b: exponentB)
    }

    public func estimate(id: UUID) -> ThresholdEstimate? { estimates.first { $0.id == id } }

    // MARK: Ändern

    /// Neue Schätzung vorne einfügen (höchstens 100; die älteste nicht aktive fällt weg)
    public mutating func insert(_ e: ThresholdEstimate) {
        estimates.removeAll { $0.id == e.id }
        estimates.insert(e, at: 0)
        estimates.sort { $0.date > $1.date }
        while estimates.count > Self.maxEstimates {
            if let i = estimates.lastIndex(where: { $0.statusValue != .active }) {
                estimates.remove(at: i)
            } else {
                estimates.removeLast()
            }
        }
    }

    /// Schätzung aktiv setzen; die bisher aktive wird `superseded`
    public mutating func activate(id: UUID) {
        guard estimates.contains(where: { $0.id == id }) else { return }
        for i in estimates.indices {
            if estimates[i].id == id {
                estimates[i].status = ThresholdEstimate.Status.active.rawValue
            } else if estimates[i].statusValue == .active {
                estimates[i].status = ThresholdEstimate.Status.superseded.rawValue
            }
        }
    }

    /// Schätzung verwerfen; war sie aktiv, wird die beste übrige aktiv
    public mutating func reject(id: UUID, now: Date) {
        guard let i = estimates.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = estimates[i].statusValue == .active
        estimates[i].status = ThresholdEstimate.Status.rejected.rawValue
        if wasActive, let best = ThresholdSelector.best(in: self, now: now) {
            activate(id: best.id)
        }
    }

    /// Profil beim ersten Start nach dem Update (SPEC 8.1): Schätzung `legacy2k` aus der bisherigen 2000-m-Bestzeit
    /// (Standard 8:00 und nie geändert → σ 15 %), Puls aus dem Profil.
    public static func migrated(best2k: Double?, maxHR: Int?, restHR: Int?, now: Date) -> ThresholdProfile {
        var p = ThresholdProfile()
        let isDefault = best2k == nil || !(best2k! > 0)
        let t2k = isDefault ? PaceTargets.defaultBest2k : best2k!
        var e = ThresholdEstimate(kind: .legacy2k, date: now, powerW: ThresholdMath.threshold(fromBest2k: t2k, b: p.exponentB),
                                  sigmaPct: isDefault ? 15 : 6, details: ["t2k": t2k], status: .active)
        if isDefault { e.details["default"] = 1 }
        p.insert(e)
        p.heart.maxHR = maxHR
        p.heart.maxHRSource = maxHR == nil ? nil : "manual"
        p.heart.restHR = restHR
        return p
    }

    // MARK: Speichern

    public func encoded() -> Data {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = [.sortedKeys]
        return (try? e.encode(self)) ?? Data()
    }

    /// Für die Synchronisation: höchstens `maxBytes` (Feldgrenze der Server-Regeln 16 000 Zeichen); fällt die
    /// Grenze, werden die ältesten nicht aktiven Schätzungen weggelassen (lokal bleibt der ganze Verlauf).
    public func encodedForSync(maxBytes: Int = 15_000) -> Data {
        var p = self
        var data = p.encoded()
        while data.count > maxBytes, let i = p.estimates.lastIndex(where: { $0.statusValue != .active }) {
            p.estimates.remove(at: i)
            data = p.encoded()
        }
        return data
    }

    /// Stand eines anderen Geräts übernehmen: Einstellungen und Status von dort, Verlauf vereinigt (gleiche id →
    /// Fassung von dort; nur hier vorhandene ältere Schätzungen bleiben, aber nie als aktive)
    public func merged(withRemote remote: ThresholdProfile) -> ThresholdProfile {
        var out = remote
        let remoteIds = Set(remote.estimates.map(\.id))
        let hasActive = remote.active != nil
        for var e in estimates where !remoteIds.contains(e.id) {
            if hasActive, e.statusValue == .active { e.status = ThresholdEstimate.Status.superseded.rawValue }
            out.estimates.append(e)
        }
        out.estimates.sort { $0.date > $1.date }
        if out.estimates.count > Self.maxEstimates { out.estimates = Array(out.estimates.prefix(Self.maxEstimates)) }
        return out
    }

    public static func decode(_ data: Data?) -> ThresholdProfile? {
        guard let data, !data.isEmpty else { return nil }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return try? d.decode(ThresholdProfile.self, from: data)
    }
}
