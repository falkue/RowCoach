import XCTest
@testable import RowCoachKit

final class CourseCatalogTests: XCTestCase {
    func testSHA256Vectors() {
        XCTAssertEqual(SHA256.hex(Data()), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(SHA256.hex(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        let long = Data(String(repeating: "a", count: 1_000_00).utf8)
        var h = SHA256.Hasher()
        h.update(long.prefix(33_333)); h.update(long.dropFirst(33_333))
        XCTAssertEqual(h.finalize(), SHA256.hex(long))
    }

    private func entry(_ id: String, version: Int = 2026112601, bundled: Bool = false, min: String? = nil) -> CourseCatalogEntry {
        CourseCatalogEntry(id: id, version: version, title: id, region: "R", lengthM: 3000, totalBytes: 1000,
                           manifest: "packages/\(id)/manifest.json", bundled: bundled, minAppVersion: min)
    }

    func testAvailabilityAndReadiness() {
        let e = entry("alster")
        func av(_ installed: [String: Int], bundled: Set<String> = [], entry: CourseCatalogEntry? = nil, app: String = "0.2.0") -> CourseAvailability? {
            CourseAvailability.resolve(entry: entry ?? e, bundledIds: bundled, installedVersions: installed, courseId: "alster", appVersion: app)
        }
        XCTAssertEqual(av([:], bundled: ["alster"]), .bundled)
        XCTAssertEqual(av([:]), .notInstalled(bytes: 1000))
        XCTAssertEqual(av(["alster": 2026112601]), .installed(version: 2026112601))
        XCTAssertEqual(av(["alster": 2026010101]), .updateAvailable(installed: 2026010101, latest: 2026112601))
        XCTAssertEqual(av([:], entry: entry("alster", min: "0.9")), .unsupported(minAppVersion: "0.9"))
        XCTAssertFalse(av([:])!.isRideable)

        XCTAssertEqual(CourseRequirement.check(courseId: "alster", availability: av([:]), entry: e), .needsDownload(e))
        XCTAssertEqual(CourseRequirement.check(courseId: "alster", availability: av(["alster": 2026112601]), entry: e), .ready)
        // Turnier verlangt die neue Fassung
        XCTAssertEqual(CourseRequirement.check(courseId: "alster", availability: av(["alster": 2026010101]), entry: e,
                                               requiredVersion: 2026112601), .needsDownload(e))
        XCTAssertEqual(CourseRequirement.check(courseId: "x", availability: nil, entry: nil), .unknownCourse)
    }

    func testPlannerAndRemoval() {
        let shared = CoursePackageManifest.File(path: "zsee/scene-standard.usdz", size: 10, sha256: "aa")
        let a = CoursePackageManifest(courseId: "utoquai", version: 1, files: [shared, .init(path: "utoquai/course.json", size: 2, sha256: "bb")])
        let b = CoursePackageManifest(courseId: "mythenquai", version: 1, files: [shared, .init(path: "mythenquai/course.json", size: 3, sha256: "cc")])
        let missing = CourseDownloadPlanner.missingFiles(b, existing: ["zsee/scene-standard.usdz": (10, "aa")])
        XCTAssertEqual(missing.map(\.path), ["mythenquai/course.json"])
        XCTAssertEqual(CourseDownloadPlanner.missingFiles(b, existing: ["zsee/scene-standard.usdz": (10, "zz")]).count, 2)
        XCTAssertEqual(CourseDownloadPlanner.removableFiles(removing: a, keeping: [b]), ["utoquai/course.json"])
        XCTAssertTrue(a.hasSafePaths)
        XCTAssertFalse(CoursePackageManifest(courseId: "x", version: 1, files: [.init(path: "../etc", size: 1, sha256: "")]).hasSafePaths)
    }

    func testCatalogRoundTripAndVersions() throws {
        let c = CourseCatalog(generatedAt: Date(timeIntervalSince1970: 1_800_000_000), courses: [entry("a", bundled: true), entry("b")])
        let back = try CourseCatalog.decode(try c.encoded())
        XCTAssertEqual(back, c)
        XCTAssertEqual(AppVersion.compare("0.10.0", "0.9.9"), .orderedDescending)
        XCTAssertEqual(AppVersion.compare("1.0", "1.0.0"), .orderedSame)
    }

    /// Quelle aus einem lokalen Ordner (wie der spätere statische Server)
    struct FolderSource: CoursePackageSource {
        let base: URL
        func fetchCatalog() async throws -> CourseCatalog { try CourseCatalog.decode(Data(contentsOf: base.appendingPathComponent("catalog.json"))) }
        func fetchManifest(for entry: CourseCatalogEntry) async throws -> CoursePackageManifest {
            try JSONDecoder().decode(CoursePackageManifest.self, from: Data(contentsOf: base.appendingPathComponent(entry.manifest)))
        }
        func download(path: String) async throws -> URL {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.copyItem(at: base.appendingPathComponent("files").appendingPathComponent(path), to: tmp)
            return tmp
        }
    }

    func testInstallerInstallsVerifiesAndRemoves() async throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("cc-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: tmp) }
        let server = tmp.appendingPathComponent("server"), root = tmp.appendingPathComponent("Courses")
        let files = ["zsee/scene-standard.usdz": Data(repeating: 7, count: 5000), "utoquai/course.json": Data("{}".utf8)]
        var mf: [CoursePackageManifest.File] = []
        for (p, d) in files.sorted(by: { $0.key < $1.key }) {
            let u = server.appendingPathComponent("files").appendingPathComponent(p)
            try fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try d.write(to: u)
            mf.append(.init(path: p, size: Int64(d.count), sha256: SHA256.hex(d)))
        }
        let manifest = CoursePackageManifest(courseId: "utoquai", version: 3, files: mf)
        let mURL = server.appendingPathComponent("packages/utoquai/manifest.json")
        try fm.createDirectory(at: mURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(manifest).write(to: mURL)
        let e = entry("utoquai", version: 3)
        let installer = CourseInstaller(root: root, source: FolderSource(base: server))
        try await installer.install(e)
        let reg = await installer.registry()
        XCTAssertEqual(reg.versions, ["utoquai": 3])
        XCTAssertTrue(fm.fileExists(atPath: root.appendingPathComponent("zsee/scene-standard.usdz").path))
        // beschädigte Datei auf dem Server → Prüfsummenfehler
        try Data(repeating: 8, count: 5000).write(to: server.appendingPathComponent("files/zsee/scene-standard.usdz"))
        try fm.removeItem(at: root.appendingPathComponent("zsee/scene-standard.usdz"))
        do { try await installer.install(e); XCTFail("Prüfsumme hätte fehlschlagen müssen") }
        catch let err as CoursePackageError { XCTAssertEqual(err, .checksumMismatch(path: "zsee/scene-standard.usdz")) }
        try await installer.remove(courseId: "utoquai")
        let after = await installer.registry()
        XCTAssertTrue(after.manifests.isEmpty)
        XCTAssertFalse(fm.fileExists(atPath: root.appendingPathComponent("utoquai/course.json").path))
    }
}
