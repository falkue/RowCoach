import Foundation
import os
import Observation
import RowCoachKit

private let profileLog = Logger(subsystem: "com.falkue.RowCoach", category: "Profile")

/// Profil und Figur des Ruderers (Anzeigename, Nationalität, Geschlecht, Erscheinung), gespeichert als JSON in
/// UserDefaults unter `RowerProfile.storageKey` ("profile.rower"). Die übrigen `profile.*`-Schlüssel (Puls,
/// Bestzeit) bleiben getrennt.
///
/// Schnittstelle für die 3D-Szene: `RowerProfileStore.shared.appearance` (was andere sehen, gilt auch fürs eigene
/// Boot), `.resolved` (Farben und Boot aufgelöst) und `.catalog`. Ändert sich die Erscheinung, steigt
/// `appearanceRevision` (beobachtbar) und es kommt `didChangeAppearance` über das NotificationCenter, damit die
/// Szene Figur und Boot neu aufbauen kann. Anzeigename, Geschlecht und Nationalität ohne Flagge lösen das nicht aus.
@MainActor
@Observable
final class RowerProfileStore {
    static let shared = RowerProfileStore()

    /// Erscheinung hat sich geändert (object: der Store)
    static let didChangeAppearance = Notification.Name("RowerProfileStore.didChangeAppearance")

    /// Katalog aus appearance.json (Ersatz: eingebauter Katalog); setzt beim Laden `AppearanceCatalog.current`
    private(set) var catalog: AppearanceCatalog

    /// Gespeichertes Profil; Setzen normalisiert (ohne Nationalität keine Flaggen), speichert und meldet
    /// Änderungen der Erscheinung
    var profile: RowerProfile {
        get { stored }
        set { apply(newValue) }
    }

    private var stored: RowerProfile

    private func apply(_ newValue: RowerProfile) {
        var p = newValue
        // ohne Nationalität keine Flaggen (die Schalter sind dann auch in der Oberfläche aus)
        if p.nationality == nil {
            p.appearance.flagOnShirt = false
            p.appearance.flagOnBoat = false
        }
        // die Nationalität der Erscheinung setzt erst `publicAppearance`
        p.appearance.nationality = nil
        let old = stored
        guard p != old else { return }
        stored = p
        defaults.set(p.encoded(), forKey: RowerProfile.storageKey)
        if p.publicAppearance != old.publicAppearance {
            appearanceRevision += 1
            NotificationCenter.default.post(name: Self.didChangeAppearance, object: self)
        }
    }

    /// Zähler für Änderungen der Erscheinung (für `onChange` in SwiftUI)
    private(set) var appearanceRevision = 0

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, bundle: Bundle = .main) {
        self.defaults = defaults
        let catalog = Self.loadCatalog(bundle: bundle)
        AppearanceCatalog.current = catalog
        self.catalog = catalog
        var p = RowerProfile.decode(defaults.data(forKey: RowerProfile.storageKey))
        p.appearance = catalog.normalized(p.appearance)
        p.appearance.nationality = nil
        if p.nationality == nil {
            p.appearance.flagOnShirt = false
            p.appearance.flagOnBoat = false
        }
        stored = p
    }

    /// Was andere in Rennen und Turnieren sehen; auch die eigene Szene zeigt genau das
    var appearance: RowerAppearance { profile.publicAppearance }

    /// Farben, Figurtyp und Boot der eigenen Erscheinung
    var resolved: AppearanceCatalog.Resolved { catalog.resolve(appearance) }

    /// Anzeigename für Rennen (leer → „Ich“)
    var displayName: String { profile.resolvedDisplayName(fallback: String(localized: "Ich")) }

    private static func loadCatalog(bundle: Bundle) -> AppearanceCatalog {
        guard let url = bundle.url(forResource: "appearance", withExtension: "json") else {
            profileLog.error("appearance.json fehlt im App-Bundle, eingebauter Katalog")
            return .builtin
        }
        do {
            let c = try AppearanceCatalog.load(from: Data(contentsOf: url))
            let issues = c.validate()
            if !issues.isEmpty {
                profileLog.error("appearance.json: \(issues.joined(separator: "; "), privacy: .public)")
            }
            return c
        } catch {
            profileLog.error("appearance.json unlesbar: \(error.localizedDescription, privacy: .public)")
            return .builtin
        }
    }
}
