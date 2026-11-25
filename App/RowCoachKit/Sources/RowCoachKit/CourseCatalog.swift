import Foundation

// Strecken zum Herunterladen (Grundlage für den späteren Server, z. B. Firebase Hosting/Storage).
//
// Auf dem Server liegt ein statischer Katalog (`catalog.json`) und je Strecke ein Paket-Manifest
// (`packages/<id>/manifest.json`) mit allen Dateien relativ zum Kartenordner `Courses/` – so wie im App-Bundle.
// Mehrere Strecken können sich Dateien teilen (z. B. eine Szene für Utoquai und Mythenquai); beim Herunterladen
// werden vorhandene, identische Dateien übersprungen. Erzeugt von tools/coursebuilder/publish_catalog.py.
// Ins App-Bundle kommen nur die Standardstrecken (`bundled`, courses/bundled.json); alle anderen erscheinen in
// der Auswahl ausgegraut und müssen vor der ersten Fahrt geladen werden. Ein Turnier verlangt seine Strecke
// (`CourseRequirement`).

/// Katalog aller Strecken des Servers (bzw. des App-Bundles)
public struct CourseCatalog: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var generatedAt: Date
    public var courses: [CourseCatalogEntry]

    public init(generatedAt: Date = Date(), courses: [CourseCatalogEntry]) {
        self.formatVersion = Self.currentFormatVersion
        self.generatedAt = generatedAt
        self.courses = courses
    }

    public func entry(id: String) -> CourseCatalogEntry? { courses.first { $0.id == id } }

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version", generatedAt = "generated_at", courses
    }

    public static func decode(_ data: Data) throws -> CourseCatalog {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try d.decode(CourseCatalog.self, from: data)
    }

    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(self)
    }
}

/// Eintrag im Katalog: genug, um die Strecke ausgegraut in der Auswahl zu zeigen, ohne sie zu laden
public struct CourseCatalogEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    /// steigt mit jeder neu gebauten Fassung der Strecke (Datum als JJJJMMTTNN)
    public var version: Int
    public var title: String
    public var region: String
    public var country: String?
    public var city: String?
    /// "out_and_back", "loop" oder "one_way"
    public var shape: String
    /// Länge der ganzen Strecke (m)
    public var lengthM: Double
    /// Gesamtgrösse des Pakets in der Stufe "standard" (Bytes, ohne geteilte Dateien abzuziehen)
    public var totalBytes: Int64
    /// Grösse je Qualitätsstufe (Bytes), optional
    public var bytesByQuality: [String: Int64]?
    /// Pfad des Manifests relativ zum Katalog, mit Platzhalter `{quality}` (je Stufe ein Paket)
    public var manifest: String
    /// Kleines Vorschaubild relativ zum Katalog (für die ausgegraute Kachel), optional
    public var preview: String?
    /// true = Standardstrecke, immer im App-Bundle
    public var bundled: Bool
    /// kleinste App-Version, die das Paketformat lesen kann (z. B. "0.2.0"), optional
    public var minAppVersion: String?

    public init(id: String, version: Int, title: String, region: String, country: String? = nil, city: String? = nil,
                shape: String = "out_and_back", lengthM: Double, totalBytes: Int64, manifest: String,
                preview: String? = nil, bundled: Bool = false, minAppVersion: String? = nil) {
        self.id = id
        self.version = version
        self.title = title
        self.region = region
        self.country = country
        self.city = city
        self.shape = shape
        self.lengthM = lengthM
        self.totalBytes = totalBytes
        self.manifest = manifest
        self.preview = preview
        self.bundled = bundled
        self.minAppVersion = minAppVersion
    }

    enum CodingKeys: String, CodingKey {
        case id, version, title, region, country, city, shape, manifest, preview, bundled
        case lengthM = "length_m", totalBytes = "total_bytes", minAppVersion = "min_app_version"
        case bytesByQuality = "bytes_by_quality"
    }

    public func manifestPath(quality: String) -> String { manifest.replacingOccurrences(of: "{quality}", with: quality) }

    public func bytes(quality: String) -> Int64 { bytesByQuality?[quality] ?? totalBytes }

    public var courseShape: CourseShape {
        switch shape {
        case "loop": return .loop
        case "one_way": return .oneWay
        default: return .outAndBack
        }
    }

    /// Kann diese App-Version das Paket lesen?
    public func isSupported(byAppVersion app: String) -> Bool {
        guard let min = minAppVersion else { return true }
        return AppVersion.compare(app, min) != .orderedAscending
    }
}

extension CourseCatalogEntry {
    /// Platzhalter für Gruppierung und Filter der Streckenauswahl (ohne Linie und Szene, nicht fahrbar)
    public var placeholderCourse: Course {
        let s = courseShape
        let leg = s == .outAndBack ? lengthM / 2 : lengthM
        var c = Course(id: id, title: title, region: region, oneWayM: leg, totalM: lengthM,
                       turns: s == .outAndBack ? 1 : 0, pathXZ: [], country: country, city: city)
        c.loop = s == .loop ? true : nil
        return c
    }
}

/// Paket einer Strecke: alle Dateien relativ zu `Courses/`
public struct CoursePackageManifest: Codable, Equatable, Sendable {
    public var courseId: String
    public var version: Int
    public var files: [File]

    public struct File: Codable, Equatable, Sendable {
        /// relativ zu `Courses/`, z. B. "zuerichsee-unteres-becken/scene-standard.usdz"
        public var path: String
        public var size: Int64
        /// SHA-256 als Hex (klein)
        public var sha256: String
        public init(path: String, size: Int64, sha256: String) {
            self.path = path
            self.size = size
            self.sha256 = sha256
        }
    }

    public init(courseId: String, version: Int, files: [File]) {
        self.courseId = courseId
        self.version = version
        self.files = files
    }

    enum CodingKeys: String, CodingKey { case courseId = "course_id", version, files }

    public var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }

    /// Pfade sicher? (keine absoluten Pfade, kein „..“ – ein Paket darf nur in den Kartenordner schreiben)
    public var hasSafePaths: Bool {
        files.allSatisfy { f in
            !f.path.isEmpty && !f.path.hasPrefix("/") && !f.path.contains("\\")
                && !f.path.split(separator: "/").contains("..")
        }
    }
}

/// Stand einer Strecke auf diesem Gerät
public enum CourseAvailability: Equatable, Sendable {
    /// im App-Bundle (Standardstrecke), sofort fahrbar
    case bundled
    /// geladen und aktuell
    case installed(version: Int)
    /// geladen, auf dem Server gibt es eine neuere Fassung (fahrbar)
    case updateAvailable(installed: Int, latest: Int)
    /// nur im Katalog: ausgegraut, vor der ersten Fahrt laden
    case notInstalled(bytes: Int64)
    /// Paket braucht eine neuere App
    case unsupported(minAppVersion: String)

    public var isRideable: Bool {
        switch self {
        case .bundled, .installed, .updateAvailable: return true
        case .notInstalled, .unsupported: return false
        }
    }

    /// Stand aus Katalog, Bundle und geladenen Paketen bestimmen
    public static func resolve(entry: CourseCatalogEntry?, bundledIds: Set<String>,
                               installedVersions: [String: Int], courseId: String,
                               appVersion: String) -> CourseAvailability? {
        if bundledIds.contains(courseId) { return .bundled }
        if let v = installedVersions[courseId] {
            if let e = entry, e.version > v, e.isSupported(byAppVersion: appVersion) {
                return .updateAvailable(installed: v, latest: e.version)
            }
            return .installed(version: v)
        }
        guard let e = entry else { return nil }
        if !e.isSupported(byAppVersion: appVersion) { return .unsupported(minAppVersion: e.minAppVersion ?? "") }
        return .notInstalled(bytes: e.totalBytes)
    }
}

/// Darf mit einer Strecke gefahren werden (freie Fahrt, Training, Turnier)?
public enum CourseReadiness: Equatable, Sendable {
    case ready
    /// erst laden (bei der Turnier-Anmeldung: Aufforderung zum Download)
    case needsDownload(CourseCatalogEntry)
    /// Paket braucht eine neuere App
    case needsAppUpdate(minAppVersion: String)
    /// Strecke weder installiert noch im Katalog
    case unknownCourse
}

public enum CourseRequirement {
    /// Prüfung vor dem Start und bei der Anmeldung zu einem Turnier. `requiredVersion`: das Turnier verlangt
    /// mindestens diese Fassung (alle sehen dieselbe Strecke); ältere geladene Fassungen müssen aktualisiert werden.
    public static func check(courseId: String, availability: CourseAvailability?, entry: CourseCatalogEntry?,
                             requiredVersion: Int? = nil) -> CourseReadiness {
        switch availability {
        case .bundled:
            return .ready
        case .installed(let v):
            if let r = requiredVersion, v < r, let e = entry { return .needsDownload(e) }
            return .ready
        case .updateAvailable(let v, _):
            if let r = requiredVersion, v < r, let e = entry { return .needsDownload(e) }
            return .ready
        case .notInstalled:
            return entry.map { .needsDownload($0) } ?? .unknownCourse
        case .unsupported(let min):
            return .needsAppUpdate(minAppVersion: min)
        case nil:
            return .unknownCourse
        }
    }
}

/// Was beim Laden einer Strecke noch fehlt: Dateien, die lokal fehlen oder anders sind (Grösse/Prüfsumme)
public enum CourseDownloadPlanner {
    /// - Parameter existing: lokal vorhandene Dateien (Pfad → Grösse, SHA-256 falls bekannt)
    public static func missingFiles(_ manifest: CoursePackageManifest,
                                    existing: [String: (size: Int64, sha256: String?)]) -> [CoursePackageManifest.File] {
        manifest.files.filter { f in
            guard let e = existing[f.path], e.size == f.size else { return true }
            if let sha = e.sha256 { return sha.lowercased() != f.sha256.lowercased() }
            return false
        }
    }

    /// Dateien, die nach dem Entfernen einer Strecke gelöscht werden dürfen (von keiner anderen geladenen Strecke
    /// und keiner Bundle-Strecke gebraucht)
    public static func removableFiles(removing: CoursePackageManifest,
                                      keeping others: [CoursePackageManifest]) -> [String] {
        let used = Set(others.flatMap { $0.files.map(\.path) })
        return removing.files.map(\.path).filter { !used.contains($0) }
    }
}

/// Vergleich von Versionsnummern „1.2.3“
public enum AppVersion {
    public static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }, pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}
