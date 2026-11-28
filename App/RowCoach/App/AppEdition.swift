import Foundation

/// Fassung der App (docs/APPSTORE.md „Editionen“). Zwei Targets in project.yml teilen sich die Quellen:
/// - `RowCoach` (Kompilier-Bedingung `EDITION_BASIC`): Store-Fassung 1.0 „Basis“, kostenlos, ohne Server. Firebase und
///   GoogleSignIn sind nicht gelinkt, die Ordner `Sync/` und `Race/` sowie `RacesView.swift` nicht kompiliert. Die
///   App stellt keine einzige Netzanfrage (ausser Apple-Diensten wie HealthKit).
/// - `RowCoachDev` (`EDITION_FULL`): voller Entwicklungsstand mit Konto, Synchronisation, Online-Rennen und
///   Strecken-Download.
///
/// Jede Online- oder Bezahlfunktion hängt an genau einem Schalter. Später kommt eine Funktion einzeln zurück
/// (Strecken-Paket, Abo, Rennen, Sync): Schalter hier auf eine Bedingung (z. B. Kauf) setzen, abhängige Dateien im
/// Basis-Target wieder aufnehmen (project.yml, `excludes`) und `#if EDITION_FULL` an den Aufrufstellen lösen.
enum AppEdition {
    #if EDITION_FULL
    static let isFull = true
    #else
    static let isFull = false
    #endif

    /// Name für Diagnose und Protokoll
    static var name: String { isFull ? "Dev" : "Basis" }

    /// Online-Rennen (Firebase Realtime Database) und Turniere mit virtuellen Teilnehmenden; Taste „Rennen“ im Tab
    /// Strecken. Basis: aus (die Rennen-Dateien sind dort gar nicht kompiliert).
    static let racesEnabled = isFull

    /// Konto, Anmeldung, Synchronisation, Forschungs-Einwilligung (Firebase Auth/Firestore). Basis: aus.
    static let syncEnabled = isFull

    /// Strecken vom Server: Katalog laden, ausgegraute „ladbar“-Kacheln, Download, Strecken-Server in den
    /// Entwicklereinstellungen. Basis: aus – die Streckenauswahl zeigt nur die mitgelieferten Strecken.
    static let courseDownloadsEnabled = isFull

    /// Käufe und Abo (StoreKit). Heute in keiner Fassung aktiv; Platzhalter für die Freischaltung später.
    static let purchasesEnabled = false

    /// „Ohne Rudergerät ausprobieren (Demo)“ im Geräte-Bereich: eingebauter Simulator, auch im Release (App Review
    /// ohne PM5). Demofahrten zählen nie in Statistik, Bestzeiten, Plan oder Apple Health (Gerätequelle Simulator).
    static let demoModeAvailable = true

    /// Testbetrieb über Startargumente (`-demoCourse`, `-demoRace`, `-seedDemoHistory`, `-simulateFTMS` …):
    /// in Debug-Builds und in der Dev-Fassung. Im Basis-Release nur `-photoMode` (Screenshots).
    static var testArgumentsEnabled: Bool {
        #if DEBUG || EDITION_FULL
        return true
        #else
        return false
        #endif
    }

    /// Startargumente, die auch im Basis-Release gelten
    static let releaseArguments: Set<String> = ["photoMode"]

    /// Basis-Release: alle Testbetriebs-Startargumente verwerfen (sie landen sonst über die Argument-Domäne in
    /// `UserDefaults.standard`), nur `releaseArguments` behalten. Ganz am Anfang von `RowCoachApp.init` aufrufen.
    /// Store-Nutzer können keine Startargumente übergeben; das hier hält auch Builds aus Xcode sauber.
    static func applyLaunchArgumentPolicy() {
        guard !testArgumentsEnabled else { return }
        let defaults = UserDefaults.standard
        let domain = UserDefaults.argumentDomain
        let current = defaults.volatileDomain(forName: domain)
        guard !current.isEmpty else { return }
        let kept = current.filter { releaseArguments.contains($0.key) }
        defaults.removeVolatileDomain(forName: domain)
        if !kept.isEmpty { defaults.setVolatileDomain(kept, forName: domain) }
    }
}

/// Öffentliche Seiten der App (GitHub Pages aus `docs/site/`, docs/APPSTORE.md). Dieselben Adressen stehen in App
/// Store Connect (Datenschutz-URL, Support-URL). Öffnen im Browser, keine Netzanfrage der App selbst.
enum AppLinks {
    static let site = URL(string: "https://falkue.github.io/RowCoach/")!
    static let privacy = URL(string: "https://falkue.github.io/RowCoach/privacy.html")!
    static let support = URL(string: "https://falkue.github.io/RowCoach/support.html")!
}
