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

/// Alle Strecken aus dem App-Bundle (`Courses/<strecke>/course.json`, gefüllt von
/// tools/coursebuilder/install_courses.py). Szenenpfade in course.json sind relativ zu `Courses/`.
@Observable
final class CourseLibrary {
    private(set) var courses: [Course] = []
    /// Fehler beim Lesen einzelner Strecken (für die Diagnose in der Oberfläche)
    private(set) var loadErrors: [String] = []

    /// "auto", "standard" oder "hoch"; dieselbe Einstellung wie `@AppStorage(SceneQuality.storageKey)`.
    @ObservationIgnored
    @AppStorage(SceneQuality.storageKey) private var qualitySetting: String = SceneQuality.automaticValue

    private let baseURL: URL?

    /// - Parameter baseURL: Ordner mit den Kartenpaketen; Standard ist `Courses/` im App-Bundle.
    init(baseURL: URL? = Bundle.main.url(forResource: "Courses", withExtension: nil)) {
        self.baseURL = baseURL
        reload()
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
        guard let baseURL else {
            courses = []
            loadErrors = ["Ordner Courses fehlt im App-Bundle (install_courses.py ausführen)."]
            return
        }
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: [.isDirectoryKey],
                                                options: [.skipsHiddenFiles])) ?? []
        var found: [Course] = []
        var errors: [String] = []
        let decoder = JSONDecoder()
        for dir in dirs {
            let file = dir.appendingPathComponent("course.json")
            guard fm.fileExists(atPath: file.path) else { continue }  // z. B. reiner Szenenordner
            do {
                let data = try Data(contentsOf: file)
                found.append(try decoder.decode(Course.self, from: data))
            } catch {
                errors.append("\(dir.lastPathComponent): \(error.localizedDescription)")
            }
        }
        courses = found.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        loadErrors = errors
    }

    func course(id: String) -> Course? { courses.first { $0.id == id } }

    /// Vorschaubild für die Streckenkachel: `preview-<stufe>-1.jpg`, sonst irgendein `preview*.jpg`.
    /// Übersichtsbild für die Streckenauswahl (weiter gefasst), sonst die Navigatorkarte
    func overviewImage(for course: Course) -> (url: URL, bounds: [Double])? {
        for m in [course.overview, course.minimap].compactMap({ $0 }) where m.boundsXZ.count == 4 {
            if let url = baseURL?.appendingPathComponent(course.id, isDirectory: true).appendingPathComponent(m.image),
               FileManager.default.fileExists(atPath: url.path) {
                return (url, m.boundsXZ)
            }
        }
        return nil
    }

    /// Luftbildkarte für den Navigator, falls das Kartenpaket eine mitbringt
    func minimapImageURL(for course: Course) -> URL? {
        guard let name = course.minimap?.image,
              let url = baseURL?.appendingPathComponent(course.id, isDirectory: true).appendingPathComponent(name),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    func previewImageURL(for course: Course) -> URL? {
        guard let dir = baseURL?.appendingPathComponent(course.id, isDirectory: true) else { return nil }
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

    /// USDZ-Datei der Szene in der gewünschten Stufe. Fehlt diese Stufe im Paket oder im Bundle, wird die
    /// andere Stufe versucht (zuerst standard). nil, wenn gar keine Szene installiert ist.
    func sceneURL(for course: Course, quality: SceneQuality) -> URL? {
        guard let baseURL else { return nil }
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
