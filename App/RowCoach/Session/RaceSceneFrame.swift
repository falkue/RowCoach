import Foundation
import RowCoachKit

/// Ein Planungsschritt des `RaceScenePlanner` für Szene und HUD (docs/MULTIPLAYER.md „Grosse Felder“, „Umsetzung App“):
/// welche Boote wie gezeigt werden (`items`), Gruppen in der Ferne (`clusters`), Platz und Abstände (`summary`) und die
/// Teilnehmenden für Namen und Erscheinung.
struct RaceSceneFrame: Equatable {
    var items: [RaceSceneItem]
    var clusters: [RaceCrowdCluster]
    var summary: RaceFieldSummary
    /// Teilnehmende nach id (Name, Erscheinung, Quelle)
    var participants: [String: RaceParticipant]
    /// eigene Distanz (m) und Streckenlänge des Rennens (für die Dichteleiste)
    var myDistance: Double
    var raceLength: Double?

    func name(_ id: String) -> String { participants[id]?.displayName ?? id }

    /// Anzeigename mit Kennzeichnung: virtuelle Teilnehmende mit Länderkürzel und ✦ („Lea · SE ✦“)
    func label(_ id: String) -> String {
        guard let p = participants[id] else { return id }
        return p.isVirtual ? "\(p.nameWithCountry) \(RaceParticipant.virtualMark)" : p.displayName
    }

    /// Für VoiceOver: Name, bei virtuellen mit „virtuell“ statt des Zeichens
    func spokenName(_ id: String) -> String {
        guard let p = participants[id] else { return id }
        return p.isVirtual ? String(localized: "\(p.displayName), virtuell") : p.displayName
    }
}

/// Gerätestufe → Budget des Planers. Modellkennung über `uname` (im Simulator `SIMULATOR_MODEL_IDENTIFIER`),
/// Zuordnung im Kit (`RaceRenderBudget.forDevice`, getestet). Zum Testen fest: Startargument `-raceBudget a12x`
/// (bzw. `standard`, `high`).
enum RaceDeviceProfile {
    static var machine: String {
        if let sim = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return sim }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    static var budget: RaceRenderBudget {
        RaceRenderBudget.forDevice(machine: machine, physicalMemory: ProcessInfo.processInfo.physicalMemory,
                                   override: UserDefaults.standard.string(forKey: "raceBudget"))
    }
}
