import Foundation
import os
import Observation
import RowCoachKit

private let thresholdLog = Logger(subsystem: "com.falkue.RowCoach", category: "Threshold")

/// Schlüssel und Lesezugriff ohne Hauptthread (Coach, Pulszonen, Hintergrundrechnungen)
enum ThresholdSettings {
    /// Schwellenprofil als JSON (docs/schwelle/SPEC.md 1); wird synchronisiert (Profil-Dokument, Feld „threshold“)
    static let storageKey = "threshold.profile.v1"
    /// Auswahl des Pulszonenmodells (`HeartRateZones.ModelKind.rawValue`; leer = automatisch)
    static let heartModelKey = "threshold.heartModel"

    /// Gespeichertes Profil (nil vor der Migration)
    static var storedProfile: ThresholdProfile? {
        ThresholdProfile.decode(UserDefaults.standard.data(forKey: storageKey))
    }

    /// Pulsprofil: Maximal- und Ruhepuls aus den Profilfeldern (eine Wahrheit), der Rest aus dem Schwellenprofil
    static func heart(_ p: ThresholdProfile?) -> HeartProfile {
        var h = p?.heart ?? HeartProfile()
        let d = UserDefaults.standard
        if let m = d.object(forKey: ProfileState.maxHRKey) as? Int, m > 0 { h.maxHR = m }
        if let r = d.object(forKey: ProfileState.restHRKey) as? Int, r > 0 { h.restHR = r }
        return h
    }

    static var preferredHeartModel: HeartRateZones.ModelKind? {
        UserDefaults.standard.string(forKey: heartModelKey).flatMap(HeartRateZones.ModelKind.init(rawValue:))
    }

    /// Pulszonen nach dem gewählten bzw. automatischen Modell (SPEC 4.2)
    static func zones(now: Date = Date()) -> (zones: HeartRateZones, source: TrainingZones.HeartModelSource) {
        TrainingZones.heartZones(heart(storedProfile), now: now, preferred: preferredHeartModel)
    }

    /// Werte für die Testansagen des Coachs
    static var coachTestContext: CoachTestContext? {
        guard let p = storedProfile, let t = p.thresholdW else { return nil }
        return CoachTestContext(thresholdW: t, exponentB: p.exponentB, rampFactor: p.rampFactor)
    }
}

/// Schwellenprofil der App (UserDefaults, JSON). Einzige Quelle der Schwelle; schreibt bei jeder Änderung der aktiven
/// Schwelle die gleichwertige 2000-m-Zeit nach `TrainingSettings.best2kKey` (Spiegel für alle bisherigen Tempoziele,
/// SPEC 8.1) und setzt `ThresholdMath.activeExponent`. Beim ersten Start wird aus der bisherigen 2000-m-Bestzeit eine
/// Schätzung `legacy2k` (Migration). Änderungen kommen über `didChange` (NotificationCenter).
@MainActor
@Observable
final class ThresholdStore {
    static let shared = ThresholdStore()
    static let didChange = Notification.Name("ThresholdStore.didChange")

    private(set) var profile: ThresholdProfile
    /// Zähler für `onChange` in SwiftUI
    private(set) var revision = 0
    /// Rückgängig nach automatischer Übernahme (Testergebnis höher): vorher aktive Schätzung
    struct UndoTarget: Equatable {
        var estimate: UUID
        var previous: UUID
    }
    private(set) var undoTarget: UndoTarget?

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let p = ThresholdProfile.decode(defaults.data(forKey: ThresholdSettings.storageKey)) {
            profile = p
        } else {
            let best = defaults.object(forKey: TrainingSettings.best2kKey) as? Double
            let maxHR = defaults.object(forKey: ProfileState.maxHRKey) as? Int
            let restHR = defaults.object(forKey: ProfileState.restHRKey) as? Int
            profile = ThresholdProfile.migrated(best2k: best.flatMap { $0 > 0 ? $0 : nil }, maxHR: maxHR,
                                                restHR: restHR, now: Date())
            thresholdLog.info("Schwellenprofil angelegt (Migration aus best2k \(best ?? 0, privacy: .public))")
            defaults.set(profile.encoded(), forKey: ThresholdSettings.storageKey)
        }
        ThresholdMath.activeExponent = profile.exponentB
    }

    /// Nach einer Synchronisation neu lesen
    func reload() {
        guard let p = ThresholdProfile.decode(defaults.data(forKey: ThresholdSettings.storageKey)), p != profile else { return }
        profile = p
        changed(mirror: true)
    }

    // MARK: Abfragen

    var active: ThresholdEstimate? { profile.active }
    var heart: HeartProfile { ThresholdSettings.heart(profile) }

    /// Tage ohne Fahrt bis heute (für σ + 3 % nach ≥ 14 Tagen Pause); gesetzt vom Startbildschirm
    var pauseDays = 0

    func sigma(_ e: ThresholdEstimate, now: Date = Date()) -> Double {
        ThresholdSelector.sigma(e, now: now, pauseDays: pauseDays)
    }

    var activeSigma: Double? { active.map { sigma($0) } }
    var confidence: ThresholdConfidence? { activeSigma.map(ThresholdConfidence.init(sigma:)) }

    /// Die aktive Schwelle stammt aus dem Standardwert (nie eingegeben oder getestet)
    var isDefault: Bool { active?.details["default"] == 1 }

    /// Vorschlag, eine sicherere Schätzung statt der Eingabe zu verwenden
    var proposal: ThresholdProposal? { ThresholdSelector.proposal(profile, now: Date(), pauseDays: pauseDays) }

    /// Offene Rückfragen (Testergebnis niedriger bzw. aktive Eingabe)
    var pendingCandidates: [ThresholdEstimate] {
        profile.estimates.filter { $0.statusValue == .candidate && !$0.isHintOnly && $0.source?.isTest == true }
    }

    // MARK: Eingabe

    /// Eingabe Watt (40–600 W)
    func enterPower(_ watts: Double, date: Date = Date()) {
        guard (40...600).contains(watts) else { return }
        addManual(ThresholdEstimate(kind: .manualPower, date: date, powerW: watts, sigmaPct: 4))
    }

    /// Eingabe Tempo an der Schwelle (1:15–4:00 /500 m)
    func enterPace(_ pace: Double, date: Date = Date()) {
        guard (75...240).contains(pace) else { return }
        addManual(ThresholdEstimate(kind: .manualPace, date: date, powerW: ThresholdMath.watts(pace: pace), sigmaPct: 4,
                                    details: ["pace": pace]))
    }

    /// Eingabe 2000-m-Bestzeit (5:20–15:00); auch aus dem Profilfeld „2000-m-Bestzeit“
    func enter2k(_ seconds: Double, date: Date = Date()) {
        guard (320...900).contains(seconds) else { return }
        // gleiche Zeit wie die aktive 2k-Eingabe: nichts tun (Auswahlrad meldet jede Bewegung)
        if let a = active, a.source == .manual2k, abs((a.details["t2k"] ?? 0) - seconds) < 0.05 { return }
        // Auswahlrad: dieselbe Eingabe von heute fortschreiben statt viele Einträge anzulegen
        if let a = active, a.source == .manual2k, Calendar.current.isDate(a.date, inSameDayAs: date) {
            profile.estimates.removeAll { $0.id == a.id }
        }
        addManual(ThresholdEstimate(kind: .manual2k, date: date,
                                    powerW: ThresholdMath.threshold(fromBest2k: seconds, b: profile.exponentB),
                                    sigmaPct: 6, details: ["t2k": seconds]))
    }

    private func addManual(_ e: ThresholdEstimate) {
        profile.insert(e)
        profile.activate(id: e.id)
        undoTarget = nil
        changed(mirror: true)
    }

    /// Schwelle um 3 % senken (Hinweis „Ziele zu hoch?“, R4)
    func lowerByThreePercent() {
        guard let t = profile.thresholdW else { return }
        var e = ThresholdEstimate(kind: .manualPower, date: Date(), powerW: t * 0.97, sigmaPct: 6)
        e.details["lowered"] = 1
        addManual(e)
    }

    // MARK: Puls

    func setHeart(maxHR: Int?, restHR: Int?, lthr: Int?, birthYear: Int?) {
        if let m = maxHR, (120...230).contains(m) {
            defaults.set(m, forKey: ProfileState.maxHRKey)
            profile.heart.maxHR = m
            profile.heart.maxHRSource = "manual"
        }
        if let r = restHR, (30...110).contains(r) {
            defaults.set(r, forKey: ProfileState.restHRKey)
            profile.heart.restHR = r
        }
        if lthr != profile.heart.lthr {
            profile.heart.lthr = lthr.flatMap { (100...220).contains($0) ? $0 : nil }
            profile.heart.lthrSource = profile.heart.lthr == nil ? nil : "manual"
            profile.heart.lthrDate = profile.heart.lthr == nil ? nil : Date()
        }
        profile.heart.birthYear = birthYear.flatMap { (1920...2020).contains($0) ? $0 : nil }
        changed(mirror: false)
    }

    /// Schwellenpuls aus einem Test übernehmen
    func acceptLTHR(_ bpm: Int, source: String, date: Date = Date()) {
        profile.heart.lthr = bpm
        profile.heart.lthrSource = source
        profile.heart.lthrDate = date
        changed(mirror: false)
    }

    /// Gemessenen Maximalpuls übernehmen
    func acceptMaxHR(_ bpm: Int) {
        guard (120...230).contains(bpm) else { return }
        defaults.set(bpm, forKey: ProfileState.maxHRKey)
        profile.heart.maxHR = bpm
        profile.heart.maxHRSource = "measured"
        changed(mirror: false)
    }

    // MARK: Verlauf

    func activate(id: UUID) {
        profile.activate(id: id)
        undoTarget = nil
        changed(mirror: true)
    }

    func reject(id: UUID) {
        profile.reject(id: id, now: Date())
        if undoTarget?.estimate == id { undoTarget = nil }
        changed(mirror: true)
    }

    func setPreferredTest(_ id: String?) {
        profile.preferredTest = id
        changed(mirror: false)
    }

    func setHealthScreen(_ s: HealthScreen?) {
        profile.healthScreen = s
        changed(mirror: false)
    }

    // MARK: Testergebnisse

    /// Auswertung einer Testfahrt eintragen. Höher → sofort aktiv (mit „Rückgängig“), niedriger → Rückfrage,
    /// Prüfhinweis → nur Hinweis. Dieselbe Fahrt wird nur einmal eingetragen.
    @discardableResult
    func submit(_ evaluation: ThresholdEvaluation) -> ThresholdDecision? {
        guard let e = evaluation.estimate else { return nil }
        if let w = e.workoutId, let old = profile.estimates.first(where: { $0.workoutId == w && $0.kind == e.kind }) {
            // schon eingetragen: Entscheidung wie damals
            switch old.statusValue {
            case .active, .superseded: return .adopt(changePct: 0)
            case .rejected: return .hintOnly
            case .candidate: return old.isHintOnly ? .hintOnly : ThresholdSelector.decide(old, profile: profile)
            }
        }
        let previous = profile.active?.id
        let d = ThresholdSelector.submit(e, to: &profile)
        if let c = evaluation.comparison, !profile.estimates.contains(where: { $0.workoutId == c.workoutId && $0.kind == c.kind }) {
            var cc = c
            cc.status = ThresholdEstimate.Status.candidate.rawValue
            profile.insert(cc)
        }
        if let r = evaluation.rampStartAdjust { profile.rampStartAdjust = r }
        if case .adopt = d, let prev = previous, let now = profile.active?.id, prev != now {
            undoTarget = UndoTarget(estimate: now, previous: prev)
        }
        ThresholdSelector.applyCalibration(&profile)
        changed(mirror: true)
        return d
    }

    /// Rückfrage beantworten: Ergebnis übernehmen
    func accept(id: UUID) { activate(id: id) }

    /// Rückfrage beantworten: alte Schwelle behalten
    func keep(id: UUID) { reject(id: id) }

    /// Automatische Übernahme rückgängig machen
    func undo() {
        guard let u = undoTarget else { return }
        profile.activate(id: u.previous)
        if let i = profile.estimates.firstIndex(where: { $0.id == u.estimate }) {
            profile.estimates[i].status = ThresholdEstimate.Status.rejected.rawValue
        }
        undoTarget = nil
        changed(mirror: true)
    }

    /// Neue Referenz aus einem Test im Trainingsplan (ProgramStore): als Zeitfahren eintragen bzw. die schon
    /// ausgewertete Fahrt aktiv setzen
    func applyProgramReference(best2k: Double, planId: String, workoutId: UUID?, date: Date) {
        if let w = workoutId, let e = profile.estimates.first(where: { $0.workoutId == w && $0.source?.isTest == true }) {
            profile.activate(id: e.id)
        } else {
            var e = ThresholdEstimate(kind: .timeTrial, date: date,
                                      powerW: ThresholdMath.threshold(fromBest2k: best2k, b: profile.exponentB),
                                      sigmaPct: 6, planId: planId, workoutId: workoutId, details: ["fromProgram": 1])
            if planId == "test-2000m" { e.details["t2k"] = best2k }
            profile.insert(e)
            profile.activate(id: e.id)
        }
        changed(mirror: true)
    }

    // MARK: Fahrten-Vorschlag (R2)

    /// Kandidat aus Fahrten übernehmen
    func acceptRideCandidate(_ c: ThresholdDetector.Candidate) {
        var e = c.estimate
        e.status = ThresholdEstimate.Status.candidate.rawValue
        profile.insert(e)
        profile.activate(id: e.id)
        profile.lastRideProposalDate = Date()
        undoTarget = nil
        changed(mirror: true)
    }

    /// Kandidat ablehnen: derselbe Wert wird nicht erneut vorgeschlagen (erst ab weiteren + 2 %)
    func rejectRideCandidate(_ c: ThresholdDetector.Candidate) {
        var e = c.estimate
        e.status = ThresholdEstimate.Status.rejected.rawValue
        profile.insert(e)
        profile.lastRideProposalW = c.estimate.powerW
        profile.lastRideProposalDate = Date()
        changed(mirror: false)
    }

    // MARK: Retest (R1)

    /// Eingang für Regel 4 des Tagesvorschlags
    func retestInput(hasHeartRateStrap: Bool, isBeginner: Bool, tested2k: Bool, now: Date = Date()) -> ThresholdRetestInput {
        let test = ThresholdRetest.preferredTest(profile: profile, hasHeartRateStrap: hasHeartRateStrap,
                                                 isBeginner: isBeginner, tested2k: tested2k, now: now)
        return ThresholdRetestInput(activeDate: isDefault ? nil : active?.date,
                                    sigma: active.map { sigma($0, now: now) } ?? 15, preferredTest: test,
                                    maximalBlocked: profile.healthScreen?.blocksMaximalTests ?? false)
    }

    // MARK: Speichern

    private func changed(mirror: Bool) {
        defaults.set(profile.encoded(), forKey: ThresholdSettings.storageKey)
        ThresholdMath.activeExponent = profile.exponentB
        // Spiegel: nur eine echte Schwelle (nicht der Standardwert), damit „Profil prüfen“ weiter erscheint
        if mirror, !isDefault, let t2k = profile.mirrorBest2k {
            let rounded = (t2k * 10).rounded() / 10
            if abs((defaults.object(forKey: TrainingSettings.best2kKey) as? Double ?? 0) - rounded) >= 0.05 {
                defaults.set(rounded, forKey: TrainingSettings.best2kKey)
            }
        }
        revision += 1
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}
