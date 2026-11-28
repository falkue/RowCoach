import Foundation
import HealthKit
import Observation
import os
import RowCoachKit

private let weightLog = Logger(subsystem: "com.falkue.RowCoach", category: "Health")

/// Körpergewicht aus Apple Health (nur lesend) ins Profil übernehmen (docs/HEALTH.md, Abschnitt Körpergewicht).
/// - Liest nur, wenn Apple Health verbunden ist (`HealthService.status == .authorized`) und die Lese-Freigabe für
///   das Gewicht schon angefragt wurde; sonst keine Abfrage. Kein Netzverkehr.
/// - HealthKit verrät nicht, ob Lesen abgelehnt wurde: Ein leeres Ergebnis heisst einfach „kein Wert“.
/// - Übernahme an (Standard): neuere Messungen ersetzen den Profilwert (`BodyWeightRule`), der dann wie eine
///   Eingabe von Hand synchronisiert wird. Aus: Eingabe von Hand, neuere abweichende Messung wird angeboten.
@MainActor
@Observable
final class BodyWeightService {
    static let shared = BodyWeightService()

    /// neueste plausible Messung aus Apple Health (nil = keine, nicht freigegeben oder nicht gelesen)
    private(set) var latest: BodyWeightRule.Reading?
    /// Angebot bei ausgeschalteter Übernahme („Apple Health: 78,4 kg – übernehmen?“)
    private(set) var offer: BodyWeightRule.Reading?
    /// Die Lese-Freigabe fürs Gewicht wurde noch nie angefragt (z. B. Health vor diesem Update verbunden)
    private(set) var needsPermission = false
    /// zählt hoch, wenn sich der lokale Stand ändert (Anzeige „aus Apple Health, 12.11.“)
    private(set) var revision = 0

    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private var refreshing = false
    private let massType = HKQuantityType(.bodyMass)

    private init() {}

    // MARK: Lokaler Stand (UserDefaults, nicht synchronisiert)

    private var defaults: UserDefaults { .standard }

    var fromHealth: Bool {
        get { defaults.object(forKey: ProfileState.weightFromHealthKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: ProfileState.weightFromHealthKey); revision += 1 }
    }

    /// Datum der übernommenen Messung, solange der Profilwert aus Apple Health dieses Geräts stammt
    var appliedHealthDate: Date? {
        let t = defaults.double(forKey: ProfileState.weightHealthDateKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    private var currentKg: Double { defaults.object(forKey: ProfileState.weightKey) as? Double ?? 75 }

    private var tracking: BodyWeightRule.Tracking {
        get {
            let a = defaults.double(forKey: ProfileState.weightAsOfKey)
            let s = defaults.object(forKey: ProfileState.weightSeenKey) as? Double
            return BodyWeightRule.Tracking(asOf: a > 0 ? Date(timeIntervalSince1970: a) : nil, seen: s)
        }
        set {
            if let a = newValue.asOf { defaults.set(a.timeIntervalSince1970, forKey: ProfileState.weightAsOfKey) }
            else { defaults.removeObject(forKey: ProfileState.weightAsOfKey) }
            if let s = newValue.seen { defaults.set(s, forKey: ProfileState.weightSeenKey) }
            else { defaults.removeObject(forKey: ProfileState.weightSeenKey) }
        }
    }

    // MARK: Ablauf

    /// Beim App-Start und beim Öffnen des Profils. `force`: Übernahme gerade eingeschaltet.
    func refresh(health: HealthService, force: Bool = false) async {
        guard HKHealthStore.isHealthDataAvailable(), health.status == .authorized else {
            latest = nil; offer = nil; needsPermission = false
            return
        }
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        // Wurde die Lese-Freigabe fürs Gewicht schon angefragt? (sagt nichts darüber, ob sie erteilt wurde)
        let request = try? await store.statusForAuthorizationRequest(toShare: [], read: [massType])
        needsPermission = request == .shouldRequest
        guard request == .unnecessary else { latest = nil; offer = nil; return }
        latest = await readLatest()
        evaluate(force: force)
    }

    /// Profilwert mit der neuesten Messung abgleichen (Übernahme oder Angebot)
    private func evaluate(force: Bool) {
        let t = BodyWeightRule.observe(current: currentKg, tracking: tracking, now: Date())
        if t.seen != tracking.seen {
            // von aussen geändert (Synchronisation): stammt nicht mehr aus Apple Health dieses Geräts
            defaults.removeObject(forKey: ProfileState.weightHealthDateKey)
        }
        tracking = t
        offer = nil
        switch BodyWeightRule.action(current: currentKg, reading: latest, fromHealth: fromHealth, tracking: t,
                                     force: force) {
        case .none:
            break
        case .apply:
            if let r = latest { apply(r) }
        case .offer:
            offer = latest
        }
        revision += 1
    }

    /// Messung ins Profil übernehmen (auch „Übernehmen“ beim Angebot)
    func apply(_ r: BodyWeightRule.Reading) {
        let kg = min(max(r.roundedKg, BodyWeightRule.plausibleKg.lowerBound), BodyWeightRule.plausibleKg.upperBound)
        if abs(currentKg - kg) > 0.001 { defaults.set(kg, forKey: ProfileState.weightKey) }
        tracking = BodyWeightRule.applied(r)
        defaults.set(r.date.timeIntervalSince1970, forKey: ProfileState.weightHealthDateKey)
        offer = nil
        revision += 1
        weightLog.info("Gewicht aus Apple Health übernommen (Messung \(r.date.formatted(.iso8601), privacy: .public))")
    }

    /// Angebot verwerfen: diese Messung nicht mehr anbieten
    func dismissOffer() {
        guard let r = offer else { return }
        var t = tracking
        t.asOf = max(t.asOf ?? r.date, r.date)
        tracking = t
        offer = nil
        revision += 1
    }

    /// Eingabe von Hand (Drehrad)
    func noteManualChange(_ kg: Double) {
        tracking = BodyWeightRule.manual(kg, now: Date())
        defaults.removeObject(forKey: ProfileState.weightHealthDateKey)
        offer = nil
        revision += 1
    }

    /// Übernahme ein- oder ausschalten; beim Einschalten gilt die neueste Messung sofort
    func setFromHealth(_ on: Bool, health: HealthService) async {
        fromHealth = on
        if on { await refresh(health: health, force: true) } else { evaluate(force: false) }
    }

    /// Neueste Messung (nach Enddatum), nur plausible 30–250 kg; Fehler und fehlende Freigabe → nil
    private func readLatest() async -> BodyWeightRule.Reading? {
        let descriptor = HKSampleQueryDescriptor(predicates: [.quantitySample(type: massType, predicate: nil)],
                                                 sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
                                                 limit: 1)
        do {
            guard let s = try await descriptor.result(for: store).first else { return nil }
            let kg = s.quantity.doubleValue(for: .gramUnit(with: .kilo))
            guard kg.isFinite, BodyWeightRule.plausibleKg.contains(kg) else { return nil }
            return BodyWeightRule.Reading(kg: kg, date: s.endDate, source: s.sourceRevision.source.name)
        } catch {
            weightLog.info("Gewicht nicht lesbar: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
