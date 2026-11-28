import Foundation
import Observation
import os
import RowCoachKit

/// Laden von Strecken vom Server (Katalog aktualisieren, Paket laden, entfernen). Ohne konfigurierten Server
/// (heute) meldet jeder Versuch „Server noch nicht verfügbar“; die Strecken im Katalog bleiben ausgegraut.
/// Server-Adresse: `UserDefaults` "courseServerURL" (Entwicklereinstellungen), sonst `defaultServer`.
@MainActor
@Observable
final class CourseDownloads {
    enum State: Equatable {
        case idle
        case downloading(Double)
        case failed(String)
    }

    static let serverKey = "courseServerURL"

    /// Standard-Server ohne Eintrag in den Entwicklereinstellungen: Testversionen laden vom Staging auf
    /// Firebase Hosting (rowcoach-dev), die Store-Version später von rowcoach-prod (noch nicht eingerichtet).
    /// Öffentliche statische Dateien, kein Konto nötig (docs/STRECKEN-SERVER.md).
    static let defaultServer: URL? = {
        #if DEBUG
        return URL(string: "https://rowcoach-dev.web.app")
        #else
        return nil
        #endif
    }()

    private(set) var states: [String: State] = [:]
    private(set) var catalogError: String?
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private let library: CourseLibrary
    private let log = Logger(subsystem: "com.falkue.RowCoach", category: "Courses")

    init(library: CourseLibrary) {
        self.library = library
    }

    /// nil = kein Server; in der Basis-Fassung immer (AppEdition.courseDownloadsEnabled), dann keine Netzanfrage
    var serverURL: URL? {
        guard AppEdition.courseDownloadsEnabled else { return nil }
        let s = UserDefaults.standard.string(forKey: Self.serverKey)?.trimmingCharacters(in: .whitespaces) ?? ""
        return s.isEmpty ? Self.defaultServer : URL(string: s)
    }

    var hasServer: Bool { serverURL != nil }

    private var source: CoursePackageSource {
        serverURL.map { HTTPCoursePackageSource(baseURL: $0) } ?? NoCoursePackageSource()
    }

    func state(_ id: String) -> State { states[id] ?? .idle }

    /// Katalog vom Server holen (beim Öffnen der Streckenauswahl)
    func refreshCatalog() async {
        guard hasServer else { return }
        do {
            let c = try await source.fetchCatalog()
            library.storeCatalog(c)
            catalogError = nil
            log.info("Katalog geladen: \(c.courses.count, privacy: .public) Strecken")
        } catch {
            catalogError = Self.message(for: error)
            log.error("Katalog laden fehlgeschlagen: \(String(describing: error), privacy: .public)")
        }
    }

    /// Strecke laden (bzw. aktualisieren); danach ist sie fahrbar
    func download(_ entry: CourseCatalogEntry, quality: SceneQuality) {
        guard tasks[entry.id] == nil else { return }
        guard let root = library.downloadsURL else { return }
        guard hasServer else {
            states[entry.id] = .failed(String(localized: "Der Strecken-Server ist noch nicht verfügbar."))
            return
        }
        states[entry.id] = .downloading(0)
        let installer = CourseInstaller(root: root, source: source)
        let id = entry.id
        // Stufe des Geräts, sofern der Server sie anbietet
        let q = entry.bytesByQuality?[quality.rawValue] != nil ? quality.rawValue : SceneQuality.standard.rawValue
        tasks[id] = Task { [weak self] in
            do {
                try await installer.install(entry, quality: q) { p in
                    Task { @MainActor in self?.states[id] = .downloading(p.fraction) }
                }
                await MainActor.run {
                    self?.states[id] = .idle
                    self?.library.reload()
                }
            } catch is CancellationError {
                await MainActor.run { self?.states[id] = .idle }
            } catch {
                let msg = Self.message(for: error)
                await MainActor.run { self?.states[id] = .failed(msg) }
            }
            await MainActor.run { self?.tasks[id] = nil }
        }
    }

    func cancel(_ id: String) {
        tasks[id]?.cancel()
    }

    /// Geladene Strecke entfernen (Standardstrecken lassen sich nicht entfernen)
    func remove(_ id: String) async {
        guard let root = library.downloadsURL, !library.bundledIds.contains(id) else { return }
        try? await CourseInstaller(root: root, source: source).remove(courseId: id)
        library.reload()
    }

    private static func message(for error: Error) -> String {
        switch error as? CoursePackageError {
        case .noServer?: return String(localized: "Der Strecken-Server ist noch nicht verfügbar.")
        case .checksumMismatch?, .sizeMismatch?: return String(localized: "Die Datei kam beschädigt an. Bitte erneut laden.")
        case .http(let status, _)?: return String(localized: "Server-Fehler \(Int(status)).")
        default: return String(localized: "Laden fehlgeschlagen. Bitte Internetverbindung prüfen.")
        }
    }
}
