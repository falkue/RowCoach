import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import RowCoachKit

// Firestore (REST v1) und Realtime Database (REST + Server-Sent Events) mit dem Dienstkonto des Cloud-Run-Jobs.
// Zugang: Token vom Metadaten-Server (Cloud Run) bzw. ROWCOACH_ACCESS_TOKEN (lokal: `gcloud auth print-access-token`).
// Admin-Zugriff: die Sicherheitsregeln gelten nicht (nur dieser Server schreibt endgültige Ergebnisse, virtuelle
// Teilnehmende, Übersichten und die Rotation).

public struct GoogleServerConfig: Sendable {
    public var projectId: String
    /// z. B. https://rowcoach-prod-default-rtdb.europe-west1.firebasedatabase.app
    public var databaseURL: String
    /// Region und Name des Aggregator-Jobs (Cloud Run Jobs)
    public var region: String
    public var aggregatorJob: String

    public init(projectId: String, databaseURL: String, region: String = "europe-west1",
                aggregatorJob: String = "rowcoach-aggregate") {
        self.projectId = projectId
        self.databaseURL = databaseURL
        self.region = region
        self.aggregatorJob = aggregatorJob
    }

    /// Aus Umgebungsvariablen: ROWCOACH_PROJECT, ROWCOACH_DATABASE_URL, ROWCOACH_REGION, ROWCOACH_AGGREGATOR_JOB
    public static func fromEnvironment(_ env: [String: String] = ProcessInfo.processInfo.environment) -> GoogleServerConfig? {
        guard let p = env["ROWCOACH_PROJECT"] ?? env["GOOGLE_CLOUD_PROJECT"] else { return nil }
        let db = env["ROWCOACH_DATABASE_URL"] ?? "https://\(p)-default-rtdb.europe-west1.firebasedatabase.app"
        return GoogleServerConfig(projectId: p, databaseURL: db, region: env["ROWCOACH_REGION"] ?? "europe-west1",
                                  aggregatorJob: env["ROWCOACH_AGGREGATOR_JOB"] ?? "rowcoach-aggregate")
    }
}

public enum GoogleAPIError: Error, CustomStringConvertible {
    case http(Int, String)
    case badResponse(String)
    case noToken

    public var description: String {
        switch self {
        case .http(let c, let b): return "HTTP \(c): \(b.prefix(400))"
        case .badResponse(let s): return "Antwort unlesbar: \(s)"
        case .noToken: return "kein Zugangstoken (Metadaten-Server bzw. ROWCOACH_ACCESS_TOKEN)"
        }
    }
}

/// Zugangstoken mit Zwischenspeicher (≈ 1 h gültig, 5 min vorher erneuert)
public final class GoogleAccessToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cached: (token: String, until: Date)?
    static let scopes = ["https://www.googleapis.com/auth/cloud-platform",
                         "https://www.googleapis.com/auth/firebase.database",
                         "https://www.googleapis.com/auth/userinfo.email"]

    public init() {}

    public func token() async throws -> String {
        if let env = ProcessInfo.processInfo.environment["ROWCOACH_ACCESS_TOKEN"], !env.isEmpty { return env }
        if let c = lock.withLock({ cached }), c.until > Date() { return c.token }
        var req = URLRequest(url: URL(string: "http://metadata.google.internal/computeMetadata/v1/instance/service-account/default/token?scopes=\(Self.scopes.joined(separator: ","))")!)
        req.setValue("Google", forHTTPHeaderField: "Metadata-Flavor")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = obj["access_token"] as? String else { throw GoogleAPIError.noToken }
        let secs = (obj["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        lock.withLock { cached = (token, Date().addingTimeInterval(secs - 300)) }
        return token
    }
}

// MARK: - Firestore-Werte (REST)

public enum FirestoreREST {
    static let rfc3339: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    public static func encode(_ v: RaceDocValue) -> [String: Any] {
        switch v {
        case .string(let s): return ["stringValue": s]
        case .int(let i): return ["integerValue": String(i)]
        case .double(let d): return ["doubleValue": d]
        case .bool(let b): return ["booleanValue": b]
        case .timestamp(let t): return ["timestampValue": rfc3339.string(from: Date(timeIntervalSince1970: t))]
        case .map(let m): return ["mapValue": ["fields": m.mapValues(encode)]]
        case .null, .serverTimestamp: return ["nullValue": NSNull()]
        }
    }

    public static func decode(_ v: [String: Any]) -> RaceDocValue {
        if let s = v["stringValue"] as? String { return .string(s) }
        if let s = v["integerValue"] as? String, let i = Int(s) { return .int(i) }
        if let n = v["integerValue"] as? NSNumber { return .int(n.intValue) }
        if let d = v["doubleValue"] as? NSNumber { return .double(d.doubleValue) }
        if let b = v["booleanValue"] as? Bool { return .bool(b) }
        if let t = v["timestampValue"] as? String {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            if let d = rfc3339.date(from: t) ?? f.date(from: t) { return .timestamp(d.timeIntervalSince1970) }
        }
        if let m = v["mapValue"] as? [String: Any] {
            return .map(((m["fields"] as? [String: Any]) ?? [:]).compactMapValues { ($0 as? [String: Any]).map(decode) })
        }
        return .null
    }

    /// Felder eines Dokuments; Serverzeit-Platzhalter werden zu Transformationen
    public static func fields(_ d: RaceDocument) -> (fields: [String: Any], serverTimes: [String]) {
        var f: [String: Any] = [:]
        var times: [String] = []
        for (k, v) in d {
            if v == .serverTimestamp { times.append(k) } else { f[k] = encode(v) }
        }
        return (f, times)
    }

    public static func document(_ json: [String: Any]) -> (id: String, doc: RaceDocument)? {
        guard let name = json["name"] as? String else { return nil }
        let fields = (json["fields"] as? [String: Any]) ?? [:]
        return (String(name.split(separator: "/").last ?? ""), fields.compactMapValues { ($0 as? [String: Any]).map(decode) })
    }
}

// MARK: - Server-Sent Events der Realtime Database

/// Zerlegt den Ereignisstrom (`event: put|patch|keep-alive|cancel|auth_revoked`, `data: {"path", "data"}`)
public struct RTDBEventParser: Sendable {
    public struct Event: Equatable, Sendable {
        public var name: String
        public var path: String
        public var data: String
    }

    private var buffer = ""
    public init() {}

    public mutating func feed(_ chunk: String) -> [Event] {
        buffer += chunk.replacingOccurrences(of: "\r\n", with: "\n")
        var out: [Event] = []
        while let r = buffer.range(of: "\n\n") {
            let block = String(buffer[..<r.lowerBound])
            buffer = String(buffer[r.upperBound...])
            var name = "", data = ""
            for line in block.split(separator: "\n", omittingEmptySubsequences: true) {
                if line.hasPrefix("event:") { name = line.dropFirst(6).trimmingCharacters(in: .whitespaces) }
                if line.hasPrefix("data:") { data += line.dropFirst(5).trimmingCharacters(in: .whitespaces) }
            }
            guard !name.isEmpty else { continue }
            if (name == "put" || name == "patch"),
               let obj = try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any],
               let path = obj["path"] as? String {
                let inner = obj["data"].flatMap { v -> String? in
                    if v is NSNull { return "null" }
                    guard JSONSerialization.isValidJSONObject(v), let d = try? JSONSerialization.data(withJSONObject: v) else { return nil }
                    return String(data: d, encoding: .utf8)
                } ?? "null"
                out.append(Event(name: name, path: path, data: inner))
            } else {
                out.append(Event(name: name, path: "", data: data))
            }
        }
        return out
    }

    /// Ereignisse unter `live/{raceId}/f` → (uid, Frame). put "/" = ganzer Knoten, put "/{uid}" = ein Frame,
    /// patch "/" = mehrere uids.
    public static func frames(_ e: Event) -> [(String, RaceWireFrame)] {
        guard e.name == "put" || e.name == "patch",
              let any = try? JSONSerialization.jsonObject(with: Data(e.data.utf8), options: [.fragmentsAllowed]) else { return [] }
        let parts = e.path.split(separator: "/").map(String.init)
        if parts.isEmpty, let all = any as? [String: Any] {
            return all.compactMap { uid, v in RaceWireFrame(value: v).map { (uid, $0) } }
        }
        if parts.count == 1, let w = RaceWireFrame(value: any) { return [(parts[0], w)] }
        return []
    }
}

/// Liest einen SSE-Strom über URLSession (Delegat, auch unter Linux)
final class SSEReader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private var parser = RTDBEventParser()
    private let onEvent: (RTDBEventParser.Event) -> Void
    private let onEnd: (Error?) -> Void
    private var session: URLSession?

    init(onEvent: @escaping (RTDBEventParser.Event) -> Void, onEnd: @escaping (Error?) -> Void) {
        self.onEvent = onEvent
        self.onEnd = onEnd
    }

    func start(_ req: URLRequest) {
        let s = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        session = s
        s.dataTask(with: req).resume()
    }

    func stop() { session?.invalidateAndCancel() }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        for e in parser.feed(String(decoding: data, as: UTF8.self)) { onEvent(e) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        onEnd(error)
    }
}

// MARK: - Store

public final class GoogleRaceServerStore: RaceServerStore, @unchecked Sendable {
    public let config: GoogleServerConfig
    private let token: GoogleAccessToken

    public init(config: GoogleServerConfig, token: GoogleAccessToken = GoogleAccessToken()) {
        self.config = config
        self.token = token
    }

    private var docsBase: String { "https://firestore.googleapis.com/v1/projects/\(config.projectId)/databases/(default)/documents" }
    private func docName(_ path: String) -> String { "projects/\(config.projectId)/databases/(default)/documents/\(path)" }

    private func request(_ method: String, _ url: String, body: Any? = nil) async throws -> Any? {
        var req = URLRequest(url: URL(string: url)!)
        req.httpMethod = method
        req.setValue("Bearer \(try await token.token())", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 && method == "GET" { return nil }
        guard (200..<300).contains(code) else { throw GoogleAPIError.http(code, String(decoding: data, as: UTF8.self)) }
        if data.isEmpty { return nil }
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    // Firestore

    private func list(_ collection: String) async throws -> [(id: String, doc: RaceDocument)] {
        var out: [(String, RaceDocument)] = []
        var pageToken: String?
        repeat {
            var url = "\(docsBase)/\(collection)?pageSize=300"
            if let t = pageToken { url += "&pageToken=\(t)" }
            let obj = try await request("GET", url) as? [String: Any]
            for d in (obj?["documents"] as? [[String: Any]]) ?? [] { if let x = FirestoreREST.document(d) { out.append(x) } }
            pageToken = obj?["nextPageToken"] as? String
        } while pageToken != nil
        return out
    }

    private func commit(_ writes: [[String: Any]]) async throws {
        for chunk in stride(from: 0, to: writes.count, by: 400).map({ Array(writes[$0..<min($0 + 400, writes.count)]) }) {
            _ = try await request("POST", "\(docsBase):commit", body: ["writes": chunk])
        }
    }

    private func setWrite(_ path: String, _ doc: RaceDocument, merge: Bool = false) -> [String: Any] {
        let (fields, times) = FirestoreREST.fields(doc)
        var w: [String: Any] = ["update": ["name": docName(path), "fields": fields]]
        if merge { w["updateMask"] = ["fieldPaths": Array(fields.keys)] }
        if !times.isEmpty {
            w["updateTransforms"] = times.map { ["fieldPath": $0, "setToServerValue": "REQUEST_TIME"] }
        }
        return w
    }

    public func activeRaces(startsFrom from: TimeInterval, to: TimeInterval) async throws -> [OnlineRace] {
        let ts = { (t: TimeInterval) in FirestoreREST.encode(.timestamp(t)) }
        let query: [String: Any] = ["structuredQuery": [
            "from": [["collectionId": "races"]],
            "where": ["compositeFilter": ["op": "AND", "filters": [
                ["fieldFilter": ["field": ["fieldPath": "startsAt"], "op": "GREATER_THAN_OR_EQUAL", "value": ts(from)]],
                ["fieldFilter": ["field": ["fieldPath": "startsAt"], "op": "LESS_THAN_OR_EQUAL", "value": ts(to)]],
            ]]],
            "limit": 500,
        ]]
        let rows = try await request("POST", "\(docsBase):runQuery", body: query) as? [[String: Any]] ?? []
        return rows.compactMap { ($0["document"] as? [String: Any]).flatMap(FirestoreREST.document) }
            .compactMap { OnlineRace(id: $0.id, document: $0.doc) }
            .filter { $0.status == .scheduled || $0.status == .live }
    }

    public func race(id: String) async throws -> OnlineRace? {
        guard let obj = try await request("GET", "\(docsBase)/races/\(id)") as? [String: Any],
              let d = FirestoreREST.document(obj) else { return nil }
        return OnlineRace(id: id, document: d.doc)
    }

    public func entries(raceId: String) async throws -> [OnlineRaceEntry] {
        try await list("races/\(raceId)/participants").compactMap { OnlineRaceEntry(id: $0.id, document: $0.doc) }
    }

    public func results(raceId: String) async throws -> [OnlineRaceResult] {
        try await list("races/\(raceId)/results").compactMap { OnlineRaceResult(id: $0.id, document: $0.doc) }
    }

    public func writeEntries(raceId: String, _ entries: [OnlineRaceEntry]) async throws {
        try await commit(entries.map { setWrite("races/\(raceId)/participants/\($0.id)", $0.document) })
    }

    public func removeEntry(raceId: String, uid: String) async throws {
        try await commit([["delete": docName("races/\(raceId)/participants/\(uid)")]])
    }

    public func writeResults(raceId: String, _ results: [OnlineRaceResult]) async throws {
        try await commit(results.map { setWrite("races/\(raceId)/results/\($0.id)", $0.document) })
    }

    public func updateRace(raceId: String, status: OnlineRaceStatus?, fields: RaceDocument) async throws {
        var d = fields
        if let status { d["status"] = .string(status.rawValue) }
        var w = setWrite("races/\(raceId)", d, merge: true)
        w["currentDocument"] = ["exists": true]
        try await commit([w])
    }

    public func raceFlag(raceId: String, _ name: String) async throws -> Bool {
        guard let obj = try await request("GET", "\(docsBase)/races/\(raceId)") as? [String: Any],
              let d = FirestoreREST.document(obj) else { return false }
        return d.doc[name]?.bool ?? false
    }

    /// Rotation als ein Dokument (`virtualHistory/v{Pool-Version}`, JSON-Text; 5000 Personen ≈ 300 KB)
    private var historyPath: String { "virtualHistory/v\(VirtualRowerPool.currentVersion)" }

    public func virtualHistory() async throws -> VirtualRowerHistory {
        guard let obj = try await request("GET", "\(docsBase)/\(historyPath)") as? [String: Any],
              let d = FirestoreREST.document(obj), let json = d.doc["h"]?.string,
              let h = try? JSONDecoder().decode(VirtualRowerHistory.self, from: Data(json.utf8)) else { return VirtualRowerHistory() }
        return h
    }

    public func saveVirtualHistory(_ h: VirtualRowerHistory) async throws {
        var pruned = h
        let cutoff = Date().timeIntervalSince1970 - 14 * 86400
        pruned.recent = h.recent.mapValues { $0.filter { $0 >= cutoff } }.filter { !$0.value.isEmpty }
        let json = String(decoding: try JSONEncoder().encode(pruned), as: UTF8.self)
        try await commit([setWrite(historyPath, ["h": .string(json), "updatedAt": .serverTimestamp])])
    }

    public func entitlement(uid: String) async throws -> EntitlementStatus? {
        guard let obj = try await request("GET", "\(docsBase)/users/\(uid)/entitlements/races") as? [String: Any],
              let d = FirestoreREST.document(obj) else { return nil }
        return EntitlementStatus(entitlement: .races, active: d.doc["active"]?.bool ?? false,
                                 expiresAt: d.doc["expiresAt"]?.timestamp.map { Date(timeIntervalSince1970: $0) })
    }

    // Realtime Database

    private func rtdb(_ path: String) -> String { "\(config.databaseURL)/\(path).json" }

    public func lastFrames(raceId: String) async throws -> [String: RaceWireFrame] {
        let obj = try await request("GET", rtdb("live/\(raceId)/f")) as? [String: Any] ?? [:]
        return obj.compactMapValues { RaceWireFrame(value: $0) }
    }

    public func writeField(raceId: String, _ s: RaceFieldSnapshot, full: Bool) async throws {
        let value: [String: Any] = ["r": s.raceId, "at": s.sentAt, "b": Data(s.encodeBinary()).base64EncodedString()]
        _ = try await request("PUT", rtdb(RaceLiveWire.fieldPath(raceId: raceId)), body: value)
        if full { _ = try await request("PUT", rtdb(RaceLiveWire.fieldFullPath(raceId: raceId)), body: value) }
    }

    public func frameStream(raceId: String) -> AsyncThrowingStream<(String, RaceWireFrame), Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var req = URLRequest(url: URL(string: self.rtdb("live/\(raceId)/f"))!)
                req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                do {
                    req.setValue("Bearer \(try await self.token.token())", forHTTPHeaderField: "Authorization")
                } catch {
                    continuation.finish(throwing: error)
                    return
                }
                let reader = SSEReader(onEvent: { e in
                    if e.name == "cancel" || e.name == "auth_revoked" {
                        continuation.finish(throwing: GoogleAPIError.badResponse("SSE \(e.name)"))
                        return
                    }
                    for f in RTDBEventParser.frames(e) { continuation.yield(f) }
                }, onEnd: { error in
                    if let error { continuation.finish(throwing: error) } else { continuation.finish() }
                })
                reader.start(req)
                continuation.onTermination = { _ in reader.stop() }
            }
            _ = task
        }
    }

    public func startAggregator(raceId: String) async throws {
        let url = "https://run.googleapis.com/v2/projects/\(config.projectId)/locations/\(config.region)/jobs/\(config.aggregatorJob):run"
        let body: [String: Any] = ["overrides": ["containerOverrides": [["args": ["aggregate", raceId]]],
                                                 "taskCount": 1, "timeout": "\(Int(4 * 3600))s"]]
        _ = try await request("POST", url, body: body)
    }
}
