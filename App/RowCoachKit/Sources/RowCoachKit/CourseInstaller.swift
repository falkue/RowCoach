import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Woher Katalog und Pakete kommen. Heute: kein Server (nur Bundle). Später: `HTTPCoursePackageSource` mit der
/// Basis-URL des Servers (Firebase Hosting oder Storage liefern statische Dateien; signierte URLs ebenso).
public protocol CoursePackageSource: Sendable {
    func fetchCatalog() async throws -> CourseCatalog
    func fetchManifest(for entry: CourseCatalogEntry) async throws -> CoursePackageManifest
    /// Lädt eine Datei des Pakets (Pfad relativ zu `Courses/`) in eine temporäre Datei und gibt deren URL zurück
    func download(path: String) async throws -> URL
}

public enum CoursePackageError: Error, Equatable, Sendable {
    case noServer
    case http(status: Int, path: String)
    case unsafePath(String)
    case sizeMismatch(path: String, expected: Int64, actual: Int64)
    case checksumMismatch(path: String)
    case manifestMismatch(courseId: String)
}

/// Statischer Dateiserver: `<base>/catalog.json`, `<base>/<manifest>`, `<base>/files/<pfad>`
public struct HTTPCoursePackageSource: CoursePackageSource {
    public let baseURL: URL
    public init(baseURL: URL) { self.baseURL = baseURL }

    private func get(_ relative: String) async throws -> Data {
        let url = baseURL.appendingPathComponent(relative)
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CoursePackageError.http(status: http.statusCode, path: relative)
        }
        return data
    }

    public func fetchCatalog() async throws -> CourseCatalog {
        try CourseCatalog.decode(try await get("catalog.json"))
    }

    public func fetchManifest(for entry: CourseCatalogEntry) async throws -> CoursePackageManifest {
        let m = try JSONDecoder().decode(CoursePackageManifest.self, from: try await get(entry.manifest))
        guard m.courseId == entry.id else { throw CoursePackageError.manifestMismatch(courseId: entry.id) }
        return m
    }

    public func download(path: String) async throws -> URL {
        let url = baseURL.appendingPathComponent("files").appendingPathComponent(path)
        let (tmp, response) = try await URLSession.shared.download(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CoursePackageError.http(status: http.statusCode, path: path)
        }
        // Die Datei von URLSession verschwindet nach der Rückkehr: an einen eigenen Ort verschieben
        let own = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.moveItem(at: tmp, to: own)
        return own
    }
}

/// Fortschritt beim Laden einer Strecke
public struct CourseDownloadProgress: Equatable, Sendable {
    public var courseId: String
    public var bytesDone: Int64
    public var bytesTotal: Int64
    public var fraction: Double { bytesTotal > 0 ? min(1, Double(bytesDone) / Double(bytesTotal)) : 1 }
}

/// Installiert Pakete in einen Kartenordner (z. B. Application Support/Courses) mit derselben Struktur wie
/// `Courses/` im Bundle. Ablauf: Manifest prüfen, fehlende Dateien laden, Grösse und SHA-256 prüfen, an ihren Platz
/// verschieben, zuletzt `installed.json` schreiben – erst dann gilt die Strecke als geladen (ein Abbruch hinterlässt
/// höchstens geprüfte Einzeldateien, die der nächste Versuch weiterverwendet).
public actor CourseInstaller {
    public let root: URL
    private let source: CoursePackageSource
    private let fm = FileManager.default

    /// Liste der geladenen Strecken (`installed.json`): id → Manifest
    public struct Registry: Codable, Equatable, Sendable {
        public var manifests: [String: CoursePackageManifest] = [:]
        public init() {}
        public var versions: [String: Int] { manifests.mapValues(\.version) }
    }

    public init(root: URL, source: CoursePackageSource) {
        self.root = root
        self.source = source
    }

    private var registryURL: URL { root.appendingPathComponent("installed.json") }

    public func registry() -> Registry {
        guard let data = try? Data(contentsOf: registryURL),
              let r = try? JSONDecoder().decode(Registry.self, from: data) else { return Registry() }
        return r
    }

    private func save(_ r: Registry) throws {
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let tmp = registryURL.appendingPathExtension("tmp")
        try JSONEncoder().encode(r).write(to: tmp, options: .atomic)
        if fm.fileExists(atPath: registryURL.path) { try fm.removeItem(at: registryURL) }
        try fm.moveItem(at: tmp, to: registryURL)
    }

    /// Lädt und installiert eine Strecke; `progress` wird nach jeder Datei aufgerufen
    @discardableResult
    public func install(_ entry: CourseCatalogEntry,
                        progress: @Sendable (CourseDownloadProgress) -> Void = { _ in }) async throws -> CoursePackageManifest {
        let manifest = try await source.fetchManifest(for: entry)
        guard manifest.hasSafePaths else {
            throw CoursePackageError.unsafePath(manifest.files.first { $0.path.contains("..") }?.path ?? "?")
        }
        var existing: [String: (size: Int64, sha256: String?)] = [:]
        for f in manifest.files {
            let url = root.appendingPathComponent(f.path)
            if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? NSNumber {
                // Grösse stimmt: Prüfsumme nur rechnen, wenn nötig (grosse Szenen)
                let sha = size.int64Value == f.size ? (try? SHA256.hex(ofFileAt: url)) : nil
                existing[f.path] = (size.int64Value, sha)
            }
        }
        let missing = CourseDownloadPlanner.missingFiles(manifest, existing: existing)
        let total = missing.reduce(Int64(0)) { $0 + $1.size }
        var done: Int64 = 0
        progress(CourseDownloadProgress(courseId: entry.id, bytesDone: 0, bytesTotal: total))
        for f in missing {
            try Task.checkCancellation()
            let tmp = try await source.download(path: f.path)
            defer { try? fm.removeItem(at: tmp) }
            let size = ((try? fm.attributesOfItem(atPath: tmp.path))?[.size] as? NSNumber)?.int64Value ?? -1
            guard size == f.size else {
                throw CoursePackageError.sizeMismatch(path: f.path, expected: f.size, actual: size)
            }
            guard try SHA256.hex(ofFileAt: tmp) == f.sha256.lowercased() else {
                throw CoursePackageError.checksumMismatch(path: f.path)
            }
            let dest = root.appendingPathComponent(f.path)
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.moveItem(at: tmp, to: dest)
            done += f.size
            progress(CourseDownloadProgress(courseId: entry.id, bytesDone: done, bytesTotal: total))
        }
        var r = registry()
        r.manifests[entry.id] = manifest
        try save(r)
        return manifest
    }

    /// Entfernt eine geladene Strecke; Dateien, die andere geladene Strecken brauchen, bleiben
    public func remove(courseId: String) throws {
        var r = registry()
        guard let m = r.manifests[courseId] else { return }
        let others = r.manifests.filter { $0.key != courseId }.map(\.value)
        for path in CourseDownloadPlanner.removableFiles(removing: m, keeping: others) {
            try? fm.removeItem(at: root.appendingPathComponent(path))
        }
        r.manifests[courseId] = nil
        try save(r)
    }
}

/// Kein Server konfiguriert: jeder Zugriff meldet `noServer` (heutiger Zustand)
public struct NoCoursePackageSource: CoursePackageSource {
    public init() {}
    public func fetchCatalog() async throws -> CourseCatalog { throw CoursePackageError.noServer }
    public func fetchManifest(for entry: CourseCatalogEntry) async throws -> CoursePackageManifest {
        throw CoursePackageError.noServer
    }
    public func download(path: String) async throws -> URL { throw CoursePackageError.noServer }
}

/// SHA-256 ohne CryptoKit (läuft auch unter Linux/Android)
public enum SHA256 {
    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    /// Fortlaufende Berechnung (grosse Dateien in Stücken)
    public struct Hasher {
        private var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                                   0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
        private var buffer: [UInt8] = []
        private var length: UInt64 = 0
        public init() {}

        public mutating func update(_ data: Data) {
            length += UInt64(data.count)
            buffer.append(contentsOf: data)
            var offset = 0
            while buffer.count - offset >= 64 {
                block(buffer, offset)
                offset += 64
            }
            if offset > 0 { buffer.removeFirst(offset) }
        }

        public mutating func finalize() -> String {
            var tail = buffer
            tail.append(0x80)
            while tail.count % 64 != 56 { tail.append(0) }
            let bits = length &* 8
            for i in (0..<8).reversed() { tail.append(UInt8((bits >> (UInt64(i) * 8)) & 0xff)) }
            var offset = 0
            while offset < tail.count { block(tail, offset); offset += 64 }
            return h.map { String(format: "%08x", $0) }.joined()
        }

        private mutating func block(_ b: [UInt8], _ o: Int) {
            var w = [UInt32](repeating: 0, count: 64)
            for i in 0..<16 {
                w[i] = UInt32(b[o + 4 * i]) << 24 | UInt32(b[o + 4 * i + 1]) << 16
                    | UInt32(b[o + 4 * i + 2]) << 8 | UInt32(b[o + 4 * i + 3])
            }
            func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }
            for i in 16..<64 {
                let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var a = h[0], bb = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7]
            for i in 0..<64 {
                let S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let ch = (e & f) ^ (~e & g)
                let t1 = hh &+ S1 &+ ch &+ SHA256.k[i] &+ w[i]
                let S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let maj = (a & bb) ^ (a & c) ^ (bb & c)
                let t2 = S0 &+ maj
                hh = g; g = f; f = e; e = d &+ t1; d = c; c = bb; bb = a; a = t1 &+ t2
            }
            h[0] = h[0] &+ a; h[1] = h[1] &+ bb; h[2] = h[2] &+ c; h[3] = h[3] &+ d
            h[4] = h[4] &+ e; h[5] = h[5] &+ f; h[6] = h[6] &+ g; h[7] = h[7] &+ hh
        }
    }

    public static func hex(_ data: Data) -> String {
        var hasher = Hasher()
        hasher.update(data)
        return hasher.finalize()
    }

    public static func hex(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        #if canImport(CryptoKit)
        // Apple: CryptoKit ist um ein Vielfaches schneller (Szenen haben einige hundert MB)
        var fast = CryptoKit.SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { fast.update(data: chunk) }
        return fast.finalize().map { String(format: "%02x", $0) }.joined()
        #else
        var hasher = Hasher()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(chunk)
        }
        return hasher.finalize()
        #endif
    }
}
