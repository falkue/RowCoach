import Foundation
import Metal
import Observation
import SwiftUI
import RowCoachKit

/// Qualitätsstufe der 3D-Szene (KONZEPT.md Abschnitt 5). Der Rohwert entspricht dem Platzhalter
/// `{quality}` in `course.json` ("standard" → `scene-standard.usdz`).
enum SceneQuality: String, CaseIterable, Identifiable, Sendable {
    case standard
    case hoch

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: return "Standard"
        case .hoch: return "Hoch"
        }
    }

    /// Schlüssel in UserDefaults. Werte: "auto" (Standard), "standard", "hoch".
    /// Team A kann in den Einstellungen direkt `@AppStorage(SceneQuality.storageKey)` verwenden.
    static let storageKey = "scene.quality"
    static let automaticValue = "auto"

    /// Erkennung nach Gerät: GPU-Familie Apple7 oder höher (A14/M1 und neuer) und mindestens ca. 6 GB RAM → hoch,
    /// sonst standard (z. B. iPad Pro A12X = Apple5). Die RAM-Schwelle hält iPhones mit A14/A15 und 4 GB
    /// bei standard, weil die hohe Stufe (162 MB USDZ, 4,1 Mio. Dreiecke) dort knapp würde.
    static var detected: SceneQuality {
        guard let device = MTLCreateSystemDefaultDevice() else { return .standard }
        let ramGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        return device.supportsFamily(.apple7) && ramGB >= 5.5 ? .hoch : .standard
    }

    /// Gespeicherte Wahl auflösen: "standard"/"hoch" übersteuern, alles andere heisst automatisch.
    static func resolve(setting: String) -> SceneQuality {
        SceneQuality(rawValue: setting) ?? detected
    }
}

/// Alle fahrbaren Strecken: aus dem App-Bundle (`Courses/<strecke>/course.json`, gefüllt von
/// tools/coursebuilder/install_courses.py) und geladene Strecken (Application Support/Courses, gleiche Struktur,
/// `CourseInstaller`). Szenenpfade in course.json sind relativ zum jeweiligen Kartenordner.
/// Dazu der Katalog (`Courses/catalog.json` bzw. der zuletzt vom Server geladene): Strecken, die noch nicht
/// geladen sind, erscheinen ausgegraut in der Auswahl (`catalogOnly`).
@Observable
final class CourseLibrary {
    /// fahrbare Strecken (Bundle und geladen)
    private(set) var courses: [Course] = []
    /// Katalog aller Strecken (Bundle-Katalog oder neuerer vom Server)
    private(set) var catalog: CourseCatalog?
    /// Strecken im App-Bundle
    private(set) var bundledIds: Set<String> = []
    /// geladene Strecken und ihre Fassung
    private(set) var installedVersions: [String: Int] = [:]
    /// Kartenordner je fahrbarer Strecke
    @ObservationIgnored private var rootById: [String: URL] = [:]
    /// Fehler beim Lesen einzelner Strecken (für die Diagnose in der Oberfläche)
    private(set) var loadErrors: [String] = []

    /// "auto", "standard" oder "hoch"; dieselbe Einstellung wie `@AppStorage(SceneQuality.storageKey)`.
    @ObservationIgnored
    @AppStorage(SceneQuality.storageKey) private var qualitySetting: String = SceneQuality.automaticValue

    private let baseURL: URL?
    /// Ordner für geladene Strecken (Application Support/Courses); nil in Tests
    let downloadsURL: URL?

    /// - Parameter baseURL: Ordner mit den Kartenpaketen; Standard ist `Courses/` im App-Bundle.
    init(baseURL: URL? = Bundle.main.url(forResource: "Courses", withExtension: nil),
         downloadsURL: URL? = CourseLibrary.defaultDownloadsURL) {
        self.baseURL = baseURL
        self.downloadsURL = downloadsURL
        reload()
    }

    static var defaultDownloadsURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Courses", isDirectory: true)
    }

    /// Version der App (für `min_app_version` im Katalog)
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Wirksame Qualitätsstufe (Einstellung oder Geräteerkennung).
    var quality: SceneQuality {
        get {
            access(keyPath: \.quality)
            return SceneQuality.resolve(setting: qualitySetting)
        }
        set {
            withMutation(keyPath: \.quality) { qualitySetting = newValue.rawValue }
        }
    }

    /// Zurück zur automatischen Erkennung.
    func useAutomaticQuality() {
        withMutation(keyPath: \.quality) { qualitySetting = SceneQuality.automaticValue }
    }

    func reload() {
        var found: [String: Course] = [:]
        var roots: [String: URL] = [:]
        var errors: [String] = []
        var bundled: Set<String> = []
        if let baseURL {
            for c in Self.scan(baseURL, errors: &errors) {
                found[c.id] = c
                roots[c.id] = baseURL
                bundled.insert(c.id)
            }
        } else {
            errors.append("Ordner Courses fehlt im App-Bundle (install_courses.py ausführen).")
        }
        // Geladene Strecken: nur, was installed.json als vollständig führt
        var versions: [String: Int] = [:]
        if let dl = downloadsURL, let data = try? Data(contentsOf: dl.appendingPathComponent("installed.json")),
           let reg = try? JSONDecoder().decode(CourseInstaller.Registry.self, from: data) {
            versions = reg.versions
            for c in Self.scan(dl, errors: &errors) where versions[c.id] != nil && !bundled.contains(c.id) {
                found[c.id] = c
                roots[c.id] = dl
            }
        }
        courses = found.values.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        rootById = roots
        bundledIds = bundled
        installedVersions = versions.filter { found[$0.key] != nil }
        catalog = Self.loadCatalog(bundle: baseURL, downloads: downloadsURL)
        loadErrors = errors
    }

    private static func scan(_ root: URL, errors: inout [String]) -> [Course] {
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                                options: [.skipsHiddenFiles])) ?? []
        var out: [Course] = []
        let decoder = JSONDecoder()
        for dir in dirs {
            let file = dir.appendingPathComponent("course.json")
            guard fm.fileExists(atPath: file.path) else { continue }  // z. B. reiner Szenenordner
            do {
                out.append(try decoder.decode(Course.self, from: Data(contentsOf: file)))
            } catch {
                errors.append("\(dir.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return out
    }

    /// Neuerer der beiden Kataloge: mitgelieferter oder zuletzt vom Server geladener (Application Support)
    private static func loadCatalog(bundle: URL?, downloads: URL?) -> CourseCatalog? {
        let candidates = [bundle, downloads].compactMap { $0?.appendingPathComponent("catalog.json") }
            .compactMap { try? CourseCatalog.decode(Data(contentsOf: $0)) }
        return candidates.max { $0.generatedAt < $1.generatedAt }
    }

    /// Vom Server geladenen Katalog merken (überschreibt den mitgelieferten, wenn neuer)
    func storeCatalog(_ c: CourseCatalog) {
        guard let dl = downloadsURL else { return }
        try? FileManager.default.createDirectory(at: dl, withIntermediateDirectories: true)
        if let data = try? c.encoded() { try? data.write(to: dl.appendingPathComponent("catalog.json"), options: .atomic) }
        reload()
    }

    /// Stand einer Strecke (fahrbar, ausgegraut, Update)
    func availability(courseId: String) -> CourseAvailability? {
        CourseAvailability.resolve(entry: catalog?.entry(id: courseId), bundledIds: bundledIds,
                                   installedVersions: installedVersions, courseId: courseId,
                                   appVersion: Self.appVersion)
    }

    /// Strecken aus dem Katalog, die noch nicht fahrbar sind (ausgegraut anzeigen, vor der Fahrt laden)
    var catalogOnly: [CourseCatalogEntry] {
        let have = Set(courses.map(\.id))
        return (catalog?.courses ?? []).filter { !have.contains($0.id) }
    }

    /// Prüfung vor dem Start und bei der Anmeldung zu einem Turnier
    func readiness(courseId: String, requiredVersion: Int? = nil) -> CourseReadiness {
        CourseRequirement.check(courseId: courseId, availability: availability(courseId: courseId),
                                entry: catalog?.entry(id: courseId), requiredVersion: requiredVersion)
    }

    /// Vorschaubild einer noch nicht geladenen Strecke (mitgeliefert unter `Courses/_previews/`)
    func catalogPreviewURL(for entry: CourseCatalogEntry) -> URL? {
        guard let rel = entry.preview else { return nil }
        for url in [baseURL?.appendingPathComponent("_previews/\(entry.id).jpg"),
                    downloadsURL?.appendingPathComponent(rel)].compactMap({ $0 })
        where FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return nil
    }

    /// Kartenordner einer Strecke (Bundle oder geladen)
    private func root(for course: Course) -> URL? { rootById[course.id] ?? baseURL }

    func course(id: String) -> Course? { courses.first { $0.id == id } }

    /// Vorschaubild für die Streckenkachel: `preview-<stufe>-1.jpg`, sonst irgendein `preview*.jpg`.
    /// Übersichtsbild für die Streckenauswahl (weiter gefasst), sonst die Navigatorkarte
    func overviewImage(for course: Course) -> (url: URL, bounds: [Double])? {
        for m in [course.overview, course.minimap].compactMap({ $0 }) where m.boundsXZ.count == 4 {
            if let url = root(for: course)?.appendingPathComponent(course.id, isDirectory: true).appendingPathComponent(m.image),
               FileManager.default.fileExists(atPath: url.path) {
                return (url, m.boundsXZ)
            }
        }
        return nil
    }

    /// Luftbildkarte für den Navigator, falls das Kartenpaket eine mitbringt
    func minimapImageURL(for course: Course) -> URL? {
        guard let name = course.minimap?.image,
              let url = root(for: course)?.appendingPathComponent(course.id, isDirectory: true).appendingPathComponent(name),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    func previewImageURL(for course: Course) -> URL? {
        guard let dir = root(for: course)?.appendingPathComponent(course.id, isDirectory: true) else { return nil }
        let fm = FileManager.default
        for q in [quality.rawValue] + SceneQuality.allCases.map(\.rawValue) {
            let url = dir.appendingPathComponent("preview-\(q)-1.jpg")
            if fm.fileExists(atPath: url.path) { return url }
        }
        let files = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        guard let name = files.filter({ $0.hasPrefix("preview") && $0.hasSuffix(".jpg") }).sorted().first else {
            return nil
        }
        return dir.appendingPathComponent(name)
    }

    /// Licht-Variante `id` (course.json "light_variants", z. B. "ambient") passend zur Szene, die
    /// `sceneURL(for:quality:)` liefert: die Atlanten gehören zur Geometrie genau einer Stufe, deshalb dieselbe
    /// Stufe wie die geladene Szene. nil, wenn es sie dort nicht gibt oder der Ordner fehlt.
    func lightVariant(_ id: String, for course: Course, quality: SceneQuality) -> LightVariantRequest? {
        guard let baseURL = root(for: course), let scene = sceneURL(for: course, quality: quality),
              let variant = course.lightVariants?[id] else { return nil }
        // Stufe der tatsächlich gefundenen Szene (sceneURL fällt auf die andere Stufe zurück)
        guard let q = SceneQuality.allCases.first(where: {
            baseURL.appendingPathComponent(course.scenePath(quality: $0.rawValue)).standardizedFileURL
                == scene.standardizedFileURL
        }), let path = course.lightVariantPath(id, quality: q.rawValue) else { return nil }
        let folder = baseURL.appendingPathComponent(path, isDirectory: true)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else { return nil }
        return LightVariantRequest(folder: folder, replaces: variant.replaces)
    }

    /// USDZ-Datei der Szene in der gewünschten Stufe. Fehlt diese Stufe im Paket oder im Bundle, wird die
    /// andere Stufe versucht (zuerst standard). nil, wenn gar keine Szene installiert ist.
    func sceneURL(for course: Course, quality: SceneQuality) -> URL? {
        guard let baseURL = root(for: course) else { return nil }
        var order = [quality.rawValue]
        for q in [SceneQuality.standard.rawValue, SceneQuality.hoch.rawValue] where !order.contains(q) {
            order.append(q)
        }
        let fm = FileManager.default
        for q in order where course.qualities.contains(q) {
            let url = baseURL.appendingPathComponent(course.scenePath(quality: q))
            if fm.fileExists(atPath: url.path) { return url }
        }
        return nil
    }
}
