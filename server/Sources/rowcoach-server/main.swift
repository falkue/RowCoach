import Foundation
import RowCoachKit
import RowCoachServerCore

// rowcoach-server – Server-Aufgaben der Online-Rennen als Cloud-Run-Job (docs/MULTIPLAYER.md „Server (Blaze)“).
//   rowcoach-server tick                 minütlich (Cloud Scheduler): auffüllen, Abo prüfen, live, festschreiben
//   rowcoach-server aggregate <raceId>   Feldübersicht eines grossen Rennens über die Renndauer, danach festschreiben
//   rowcoach-server finalize <raceId>    Ergebnisse sofort festschreiben (Hilfe bei Störungen)
//   rowcoach-server fill <raceId>        virtuelle Teilnehmende sofort auffüllen
// Umgebung: ROWCOACH_PROJECT (bzw. GOOGLE_CLOUD_PROJECT), ROWCOACH_DATABASE_URL, ROWCOACH_POOL (Pfad zu
// virtual-rowers-v1.bin), ROWCOACH_ENFORCE_ENTITLEMENTS=1 (Abo durchsetzen; Standard aus), lokal ROWCOACH_ACCESS_TOKEN.

let env = ProcessInfo.processInfo.environment
let args = Array(CommandLine.arguments.dropFirst())

func fail(_ s: String) -> Never {
    FileHandle.standardError.write(Data((s + "\n").utf8))
    exit(1)
}

guard let command = args.first else {
    fail("Aufruf: rowcoach-server tick | aggregate <raceId> | finalize <raceId> | fill <raceId>")
}
guard let config = GoogleServerConfig.fromEnvironment(env) else { fail("ROWCOACH_PROJECT fehlt") }

let poolPath = env["ROWCOACH_POOL"] ?? "/app/virtual-rowers-v1.bin"
let pool = (try? Data(contentsOf: URL(fileURLWithPath: poolPath))).flatMap { try? VirtualRowerPool.decode($0) }
if pool == nil { print("Warnung: Pool \(poolPath) fehlt – keine virtuellen Teilnehmenden") }

let server = RaceServer(store: GoogleRaceServerStore(config: config), pool: pool)
server.entitlements = EntitlementPolicy(enforce: env["ROWCOACH_ENFORCE_ENTITLEMENTS"] == "1")

do {
    switch command {
    case "tick":
        try await server.tick()
    case "aggregate":
        guard args.count > 1 else { fail("aggregate <raceId>") }
        try await server.aggregate(raceId: args[1])
    case "finalize":
        guard args.count > 1, let r = try await server.store.race(id: args[1]) else { fail("finalize <raceId>: Rennen fehlt") }
        let frames = try await server.store.lastFrames(raceId: r.id)
        var history: [String: [LiveFrame]] = [:]
        for (uid, w) in frames {
            if let f = RaceLiveWire.decode(w, raceId: r.id, participantId: uid) { history[uid] = [f] }
        }
        try await server.finalize(r, history: history)
    case "fill":
        guard args.count > 1, let r = try await server.store.race(id: args[1]) else { fail("fill <raceId>: Rennen fehlt") }
        try await server.fill(r)
    default:
        fail("unbekannter Befehl \(command)")
    }
} catch {
    fail("Fehler: \(error)")
}
