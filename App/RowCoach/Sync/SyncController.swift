import Foundation
import Observation
import SwiftData
import RowCoachKit

/// Mitteilungen der Synchronisation
enum SyncNotifications {
    /// Einstellungen vom Server wurden in UserDefaults übernommen (Stores mit eigenem Zwischenstand neu laden)
    static let settingsApplied = Notification.Name("RowCoachSync.settingsApplied")
}

/// Schlüssel und Textfassungen der Online-Funktion „Konto & Synchronisation“ (docs/SYNC.md)
enum SyncSettings {
    /// Synchronisation an (Standard aus)
    static let enabledKey = "sync.enabled"
    /// Auf diesem Gerät ist jemand angemeldet: nur dann richtet die App Firebase beim Start ein
    static let accountActiveKey = "sync.accountActive"
    /// Geräte-Id der Hybrid Logical Clock
    static let nodeKey = "sync.node"
    /// Lokaler Spiegel der Forschungs-Einwilligung (Standard aus) und Zeitpunkt
    static let researchKey = "sync.researchConsent"
    static let researchAtKey = "sync.researchConsentAt"
    /// Anmelden/Registrieren heisst „ich will synchronisieren“: sobald das Konto schreiben darf (E-Mail bestätigt),
    /// schaltet die App die Synchronisation selbst ein – kein zweiter Schritt nötig (Falk, 27.11.2026)
    static let autoEnableKey = "sync.autoEnableAfterSignIn"

    /// Fassungen der Einwilligungstexte (ändert sich der Text, steigt die Fassung; gespeichert wird die gezeigte)
    static let syncConsentVersion = "sync-2026-11"
    static let researchConsentVersion = "research-2026-11"

    static var syncConsentText: String {
        String(localized: "Mit dem Einschalten speichert RowCoach deine Fahrten (mit Puls, Tempo und Leistung), dein Profil und deine Trainingseinstellungen in deinem Konto, damit sie auf all deinen Geräten gleich sind. Die Daten liegen bei Google Firebase in Zürich; die Anmeldedaten (E-Mail-Adresse) verwaltet Firebase Authentication, auch ausserhalb der Schweiz. Pulsdaten sind Gesundheitsdaten: Du willigst ein, dass sie dafür gespeichert werden. Ausschalten und alle Server-Daten löschen geht jederzeit.")
    }

    static var researchConsentText: String {
        String(localized: "Ich willige ein, dass meine auf dem Server gespeicherten Trainingsdaten (Fahrten mit Tempo, Leistung, Schlagzahl und Puls, Belastung, Trainingsplan) für Forschung zu Training und Motivation ausgewertet werden. Veröffentlicht werden nur anonymisierte oder zusammengefasste Ergebnisse, nie Angaben, die auf mich schliessen lassen. Die Einwilligung ist freiwillig, ändert nichts an der App und lässt sich hier jederzeit widerrufen.")
    }

    static var node: String {
        if let n = UserDefaults.standard.string(forKey: nodeKey) { return n }
        let n = HybridTimestamp.randomNode()
        UserDefaults.standard.set(n, forKey: nodeKey)
        return n
    }
}

/// Steuert Konto und Synchronisation für die Oberfläche. Ohne Anmeldung tut er nichts: Firebase wird nicht
/// eingerichtet, die Engine meldet `signedOut`, es geht keine Anfrage hinaus. Die Logik steckt im Kit
/// (`SyncEngine`); hier nur Auslöser (App aktiv, Fahrt gespeichert, Einstellungen geändert), Anmeldung und Texte.
@MainActor
@Observable
final class SyncController {
    static let shared = SyncController()

    private(set) var user: SyncUser?
    private(set) var isWorking = false
    private(set) var lastSync: Date?
    private(set) var pendingRides = 0
    private(set) var statusText: String?
    var errorMessage: String?
    var infoMessage: String?

    /// Spiegel der UserDefaults-Schalter (beobachtbar für die Oberfläche); geschrieben nur über `setFlag`
    private(set) var syncEnabled = UserDefaults.standard.bool(forKey: SyncSettings.enabledKey)
    private(set) var researchConsent = UserDefaults.standard.bool(forKey: SyncSettings.researchKey)
    private(set) var researchConsentAt: Date? = {
        let t = UserDefaults.standard.double(forKey: SyncSettings.researchAtKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }()

    private func setSyncFlag(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: SyncSettings.enabledKey)
        syncEnabled = on
    }

    private func setResearchFlag(_ granted: Bool, at date: Date?) {
        UserDefaults.standard.set(granted, forKey: SyncSettings.researchKey)
        UserDefaults.standard.set(date?.timeIntervalSince1970 ?? 0, forKey: SyncSettings.researchAtKey)
        researchConsent = granted
        researchConsentAt = date
    }

    var serverAvailable: Bool { FirebaseBootstrap.isAvailable }
    var googleAvailable: Bool { FirebaseAuthProvider.googleAvailable }

    @ObservationIgnored private let auth = FirebaseAuthProvider()
    @ObservationIgnored private let backend = FirestoreSyncBackend()
    @ObservationIgnored private var localStore: AppSyncStore?
    @ObservationIgnored private var engine: SyncEngine?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var noteTask: Task<Void, Never>?
    @ObservationIgnored private var syncTask: Task<Void, Never>?

    private init() {}

    /// Beim Start (RowCoachApp): nur wenn hier schon jemand angemeldet ist, Firebase einrichten und abgleichen
    func attach(store: WorkoutStore) {
        guard localStore == nil else { return }
        localStore = AppSyncStore(store: store)
        if UserDefaults.standard.bool(forKey: SyncSettings.accountActiveKey) {
            Task { await self.activate() }
        }
    }

    /// Firebase einrichten und Engine bauen (erst bei einer Kontoaktion oder mit bestehendem Konto)
    @discardableResult
    private func ensureEngine() -> SyncEngine? {
        if let engine { return engine }
        guard let localStore, FirebaseBootstrap.configureIfNeeded() else { return nil }
        let e = SyncEngine(auth: auth, backend: backend, store: localStore, node: SyncSettings.node,
                           isEnabled: { UserDefaults.standard.bool(forKey: SyncSettings.enabledKey) })
        engine = e
        startObserving()
        return e
    }

    private func activate() async {
        guard ensureEngine() != nil else { return }
        await refreshUser()
        if user == nil {
            UserDefaults.standard.set(false, forKey: SyncSettings.accountActiveKey)
            return
        }
        await syncNow()
    }

    func refreshUser() async {
        user = await auth.currentUser()
        await refreshStatus()
    }

    private func refreshStatus() async {
        guard let engine, let s = await engine.status() else {
            lastSync = nil
            pendingRides = 0
            return
        }
        lastSync = s.lastSync
        pendingRides = s.pendingRides
    }

    // MARK: Auslöser

    private func startObserving() {
        guard observers.isEmpty else { return }
        let nc = NotificationCenter.default
        // neue/geänderte/gelöschte Fahrt (jeder SwiftData-Kontext)
        observers.append(nc.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.localChange(ride: true) }
        })
        observers.append(nc.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.localChange(ride: false) }
        })
    }

    private func localChange(ride: Bool) {
        guard user != nil, localStore?.isApplying == false, let engine else { return }
        noteTask?.cancel()
        noteTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await engine.noteLocalChanges()
        }
        // Fahrten nach 15 s, Einstellungen/Profil nach 5 s hochladen (vorher wurden Einstellungen erst beim
        // nächsten App-Start oder der nächsten Fahrt übertragen – Mac-Test 27.11.)
        if syncEnabled { scheduleSync(after: ride ? 15 : 5) }
    }

    private func scheduleSync(after seconds: Double) {
        syncTask?.cancel()
        syncTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self.syncNow()
        }
    }

    /// App kommt in den Vordergrund (z. B. zurück aus der Mail nach dem Bestätigungslink)
    func appBecameActive() {
        if user != nil, user?.canWrite == false, autoEnablePending {
            Task { await checkVerification(silent: true) }
            return
        }
        guard user != nil, syncEnabled else { return }
        scheduleSync(after: 1)
    }

    // MARK: Automatisch einschalten nach Anmeldung

    private var autoEnablePending: Bool { UserDefaults.standard.bool(forKey: SyncSettings.autoEnableKey) }
    @ObservationIgnored private var verifyPoll: Task<Void, Never>?

    /// Nach Anmeldung: darf das Konto schreiben, Synchronisation einschalten; sonst auf die Bestätigung warten
    private func autoEnableIfReady() async {
        guard autoEnablePending, let user else { return }
        if user.canWrite {
            verifyPoll?.cancel()
            verifyPoll = nil
            UserDefaults.standard.set(false, forKey: SyncSettings.autoEnableKey)
            if !syncEnabled {
                await setSyncEnabled(true)
                if errorMessage == nil {
                    infoMessage = String(localized: "E-Mail bestätigt – die Synchronisation ist eingeschaltet.")
                }
            }
        } else {
            startVerifyPoll()
        }
    }

    /// Solange die App offen ist, alle 5 s nachsehen, ob der Bestätigungslink geöffnet wurde (höchstens 30 min)
    private func startVerifyPoll() {
        guard verifyPoll == nil else { return }
        verifyPoll = Task { [weak self] in
            for _ in 0..<360 {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled, let self else { return }
                guard self.user != nil, self.autoEnablePending else { break }
                await self.checkVerification(silent: true)
                if self.user?.canWrite == true { break }
            }
            self?.verifyPoll = nil
        }
    }

    func handleOpenURL(_ url: URL) {
        _ = auth.handle(url: url)
    }

    // MARK: Abgleich

    func syncNow() async {
        guard let engine, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        let outcome = await engine.sync()
        switch outcome {
        case .synced:
            statusText = nil
            errorMessage = nil
        case .failed(let e):
            statusText = Self.message(e)
        case .notVerified:
            statusText = String(localized: "E-Mail-Adresse noch nicht bestätigt.")
        case .disabled, .signedOut, .busy:
            break
        }
        await refreshStatus()
    }

    /// Synchronisation ein- oder ausschalten; die Einwilligung (Text und Fassung) wird auf dem Server gespeichert
    func setSyncEnabled(_ on: Bool) async {
        guard let engine else { return }
        let consent = ConsentRecord(kind: .sync, granted: on, textVersion: SyncSettings.syncConsentVersion,
                                    locale: AppLanguage.code, decidedAt: Date())
        if on {
            do {
                try await engine.recordConsent(consent)
            } catch {
                errorMessage = Self.message(error)
                return
            }
            setSyncFlag(true)
            await syncNow()
        } else {
            setSyncFlag(false)
            try? await engine.recordConsent(consent)
        }
    }

    /// Forschungs-Einwilligung erteilen oder widerrufen (unabhängig von der Synchronisation)
    func setResearchConsent(_ granted: Bool) async {
        guard let engine else { return }
        let now = Date()
        let consent = ConsentRecord(kind: .research, granted: granted, textVersion: SyncSettings.researchConsentVersion,
                                    locale: AppLanguage.code, decidedAt: now)
        do {
            try await engine.recordConsent(consent)
            setResearchFlag(granted, at: now)
        } catch {
            errorMessage = Self.message(error)
        }
    }

    // MARK: Anmeldung

    private func perform(_ work: () async throws -> SyncUser?) async {
        errorMessage = nil
        infoMessage = nil
        guard ensureEngine() != nil else {
            errorMessage = String(localized: "In diesem Build ist kein Server eingerichtet.")
            return
        }
        isWorking = true
        do {
            user = try await work()
            if user != nil {
                UserDefaults.standard.set(true, forKey: SyncSettings.accountActiveKey)
                UserDefaults.standard.set(true, forKey: SyncSettings.autoEnableKey)
            }
        } catch {
            errorMessage = Self.message(error)
        }
        isWorking = false
        await refreshUser()
        await restoreResearchConsent()
        await autoEnableIfReady()
    }

    func signIn(email: String, password: String) async {
        await perform { try await auth.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password) }
    }

    func register(email: String, password: String) async {
        await perform { try await auth.register(email: email.trimmingCharacters(in: .whitespaces), password: password) }
        if user != nil {
            infoMessage = String(localized: "Wir haben dir einen Bestätigungslink geschickt. Sobald du ihn geöffnet hast, schaltet sich die Synchronisation von selbst ein.")
        }
    }

    func signInWithGoogle() async {
        await perform { try await auth.signInWithGoogle() }
    }

    func resetPassword(email: String) async {
        errorMessage = nil
        guard ensureEngine() != nil else { return }
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            errorMessage = String(localized: "Bitte gib zuerst deine E-Mail-Adresse ein.")
            return
        }
        do {
            try await auth.sendPasswordReset(email: trimmed)
            infoMessage = String(localized: "Falls ein Konto mit dieser Adresse besteht, kommt gleich eine E-Mail zum Zurücksetzen.")
        } catch {
            errorMessage = Self.message(error)
        }
    }

    func resendVerification() async {
        do {
            try await auth.sendEmailVerification()
            infoMessage = String(localized: "Bestätigungslink erneut gesendet.")
        } catch {
            errorMessage = Self.message(error)
        }
    }

    func checkVerification(silent: Bool = false) async {
        do {
            user = try await auth.reload()
            if user?.canWrite == false {
                if !silent {
                    infoMessage = String(localized: "Noch nicht bestätigt. Öffne den Link in der E-Mail und versuche es dann noch einmal.")
                }
            } else {
                if !silent { infoMessage = nil }
                await autoEnableIfReady()
            }
        } catch {
            if !silent { errorMessage = Self.message(error) }
        }
    }

    /// Forschungs-Einwilligung vom Server übernehmen (anderes Gerät, Neuinstallation)
    private func restoreResearchConsent() async {
        guard user?.canWrite == true, let consents = try? await backend.fetchConsents(),
              let research = consents.first(where: { $0.kind == .research }) else { return }
        setResearchFlag(research.granted, at: research.decidedAt)
    }

    func signOut() async {
        verifyPoll?.cancel()
        verifyPoll = nil
        UserDefaults.standard.set(false, forKey: SyncSettings.autoEnableKey)
        try? await auth.signOut()
        UserDefaults.standard.set(false, forKey: SyncSettings.accountActiveKey)
        setSyncFlag(false)
        setResearchFlag(false, at: nil)
        user = nil
        lastSync = nil
        pendingRides = 0
        statusText = nil
    }

    // MARK: Daten

    /// Alle Server-Daten als JSON-Datei im temporären Ordner (zum Teilen)
    func exportServerData() async -> URL? {
        guard let engine else { return nil }
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            let export = try await engine.exportServerData()
            let day = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("RowCoach-Export-\(day).json")
            try export.jsonData().write(to: url, options: .atomic)
            return url
        } catch {
            errorMessage = Self.message(error)
            return nil
        }
    }

    /// Alle Server-Daten löschen; die Synchronisation geht aus, die Daten auf dem Gerät bleiben
    func deleteServerData() async {
        guard let engine else { return }
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            setSyncFlag(false)
            try await engine.deleteServerData()
            setResearchFlag(false, at: nil)
            infoMessage = String(localized: "Alle Server-Daten sind gelöscht. Auf diesem Gerät bleibt alles erhalten.")
        } catch {
            errorMessage = Self.message(error)
        }
        await refreshStatus()
    }

    /// Server-Daten löschen und das Konto selbst entfernen
    func deleteAccount() async {
        await deleteServerData()
        guard errorMessage == nil else { return }
        do {
            try await auth.deleteAccount()
            await signOut()
            infoMessage = String(localized: "Dein Konto ist gelöscht. Auf diesem Gerät bleibt alles erhalten.")
        } catch {
            errorMessage = Self.message(error)
        }
    }

    // MARK: Texte

    static func message(_ error: Error) -> String {
        guard let e = error as? SyncError else { return error.localizedDescription }
        switch e {
        case .notSignedIn: return String(localized: "Nicht angemeldet.")
        case .unavailable: return String(localized: "In diesem Build ist kein Server eingerichtet.")
        case .invalidCredentials: return String(localized: "E-Mail-Adresse oder Passwort stimmt nicht.")
        case .emailInUse: return String(localized: "Für diese E-Mail-Adresse gibt es schon ein Konto.")
        case .weakPassword: return String(localized: "Das Passwort ist zu kurz (mindestens 6 Zeichen).")
        case .emailNotVerified: return String(localized: "E-Mail-Adresse noch nicht bestätigt.")
        case .needsAppUpdate: return String(localized: "Auf dem Server liegen Daten einer neueren App-Version. Bitte RowCoach aktualisieren.")
        case .network: return String(localized: "Keine Verbindung. Der Abgleich läuft beim nächsten Mal.")
        case .server(let s): return s
        }
    }
}
