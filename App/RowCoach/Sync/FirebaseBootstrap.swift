import Foundation
import FirebaseCore
import FirebaseAppCheck
import FirebaseFirestore

/// Richtet Firebase erst ein, wenn jemand ein Konto benutzt (docs/SYNC.md, „Offline zuerst“):
/// - beim Tippen auf „Anmelden“/„Registrieren“ in Einstellungen → Konto & Synchronisation,
/// - beim Start nur, wenn auf diesem Gerät schon jemand angemeldet ist (`SyncSettings.accountActiveKey`).
/// Ohne Konto wird `configure` nie aufgerufen; dann stellt die App keine Anfrage an Firebase.
///
/// Die Konfiguration kommt aus `GoogleService-Info.plist` im App-Bundle. Die Build-Phase „Firebase-Konfiguration“
/// (project.yml) kopiert sie je Build-Konfiguration aus App/Firebase/dev (Debug) bzw. App/Firebase/prod (Release);
/// die Dateien liegen nicht im Repo. Fehlt die Datei, läuft die App normal, nur ohne Konto.
enum FirebaseBootstrap {
    static let plistName = "GoogleService-Info"

    /// Nur auf dem Hauptthread gesetzt
    private(set) static var isConfigured = false

    static var plistPath: String? { Bundle.main.path(forResource: plistName, ofType: "plist") }

    /// Ist in diesem Build ein Server eingerichtet?
    static var isAvailable: Bool { plistPath != nil }

    /// OAuth-Client für „Mit Google anmelden“ (fehlt, solange die plist vor dem Einschalten von Google geladen wurde)
    static var googleClientID: String? {
        guard let path = plistPath, let dict = NSDictionary(contentsOfFile: path) else { return nil }
        return dict["CLIENT_ID"] as? String
    }

    /// Firebase einrichten (einmal). false = keine Konfiguration im Bundle.
    @MainActor
    @discardableResult
    static func configureIfNeeded() -> Bool {
        if isConfigured { return true }
        if FirebaseApp.app() != nil {
            isConfigured = true
            return true
        }
        guard let path = plistPath, let options = FirebaseOptions(contentsOfFile: path) else { return false }
        // App Check: im Debug-Build der Debug-Anbieter (Token erscheint im Xcode-Protokoll und wird in der
        // Firebase-Konsole eingetragen), sonst DeviceCheck. App Attest später (braucht eine eigene Berechtigung).
        #if DEBUG
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #else
        AppCheck.setAppCheckProviderFactory(DeviceCheckProviderFactory())
        #endif
        FirebaseApp.configure(options: options)
        // Die App hat ihren eigenen lokalen Speicher (SwiftData); Firestore braucht keinen zweiten auf der Platte.
        let db = Firestore.firestore()
        let settings = db.settings
        settings.cacheSettings = MemoryCacheSettings()
        db.settings = settings
        isConfigured = true
        return true
    }
}
