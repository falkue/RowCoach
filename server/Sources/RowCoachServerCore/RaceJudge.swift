import Foundation
import RowCoachKit

/// Plausibilitätsprüfung eines Laufs (docs/MULTIPLAYER.md „Fairness und Missbrauch“). Der PM5 liefert die Werte, die
/// App ist manipulierbar; der Server schreibt ein Ergebnis nur fest, wenn die Frames zusammenpassen:
/// - Tempo nie schneller als 1:10/500 m (`minPace`), weder gemeldet noch zwischen zwei Frames,
/// - keine Sprünge: Abweichung von der Voraussage des vorigen Frames > 15 m binnen 5 s,
/// - Distanz nie rückwärts,
/// - Zielzeit passt zum Verlauf (nicht vor dem letzten Frame, nicht schneller als erlaubt) und zum gemeldeten
///   Ergebnis (der Frame zählt).
public struct RaceJudge: Sendable {
    public var minPace: TimeInterval = 70
    public var jumpDistance: Double = 15
    public var jumpWindow: TimeInterval = 5
    /// Spielraum für Rundung und Laufzeit (Faktor auf die Höchstgeschwindigkeit)
    public var speedSlack: Double = 1.1
    public var finishTolerance: TimeInterval = 0.05

    public init() {}

    public var maxSpeed: Double { 500 / minPace }

    public struct Verdict: Equatable, Sendable {
        /// Ergebnis aus den Frames (Platz 0 = noch nicht gereiht); nil = nichts Verwertbares
        public var result: RaceResult?
        public var flags: [String]
        /// verwerfende Hinweise (ohne „mismatch“ und „unverified“)
        public var blocking: [String] { flags.filter { $0 != "mismatch" && $0 != "unverified" } }
        public var valid: Bool { blocking.isEmpty }
    }

    /// - Parameters:
    ///   - frames: alle Frames einer Person in Empfangsreihenfolge (Aggregator) oder nur der letzte (ohne Aggregator)
    ///   - claimed: selbst gemeldetes vorläufiges Ergebnis
    public func check(id: String, frames raw: [LiveFrame], claimed: OnlineRaceResult?, target: RaceTarget) -> Verdict {
        var flags: Set<String> = []
        let frames = raw.sorted { $0.seq < $1.seq }
        guard let last = frames.last else {
            // kein einziger Frame: nur die eigene Meldung, nicht prüfbar
            guard let c = claimed else { return Verdict(result: nil, flags: ["noFrames"]) }
            return Verdict(result: RaceResult(participantId: id, place: 0, distance: c.distance, time: c.time,
                                              finished: c.finished), flags: ["unverified"])
        }
        for f in frames where f.pace > 0 && f.pace < minPace { flags.insert("pace"); break }
        for (a, b) in zip(frames, frames.dropFirst()) {
            let dt = b.raceTime - a.raceTime
            if b.distance < a.distance - 0.05 { flags.insert("backwards") }
            if dt > 0, (b.distance - a.distance) / dt > maxSpeed * speedSlack { flags.insert("pace") }
            if dt > 0, dt <= jumpWindow, !b.finished,
               abs(b.distance - RaceDeadReckoning.predict(a, at: b.raceTime)) > jumpDistance {
                flags.insert("jump")
            }
            if dt < -0.01 { flags.insert("backwards") }
        }
        var result = RaceResult(participantId: id, place: 0, distance: last.distance, time: nil, finished: last.finished)
        switch target {
        case .distance(let m):
            if last.finished {
                let ft = last.finishTime ?? last.raceTime
                result.time = ft
                result.distance = m
                if last.distance < m - 0.5 { flags.insert("finish") }
                if ft * maxSpeed * speedSlack < m { flags.insert("pace") }
                if let prev = frames.dropLast().last(where: { !$0.finished }) {
                    if ft < prev.raceTime - 0.01 { flags.insert("finish") }
                    let dt = ft - prev.raceTime
                    if dt > 0, (m - prev.distance) / dt > maxSpeed * speedSlack { flags.insert("pace") }
                }
            }
        case .time(let s):
            result.time = s
            result.finished = last.finished || last.raceTime >= s - 0.5
            if last.distance > s * maxSpeed * speedSlack { flags.insert("pace") }
        case .plan:
            break
        }
        if let c = claimed {
            if c.finished != result.finished || abs(c.distance - result.distance) > 1
                || (c.time != nil && result.time != nil && abs(c.time! - result.time!) > finishTolerance) {
                flags.insert("mismatch")
            }
        }
        // „mismatch“ allein verwirft nicht: die Frames zählen, die Meldung war nur vorläufig
        return Verdict(result: result, flags: flags.sorted())
    }
}

/// Endgültige Ergebnisse eines Rennens: echte aus den Frames (geprüft), virtuelle aus der Simulation (wie auf den
/// Geräten, bitgleich). Verworfene Läufe kommen ohne Zeit ans Ende.
public enum RaceFinalizer {
    /// - Parameters:
    ///   - frames: je uid alle bekannten Frames (Aggregator) bzw. nur der letzte
    ///   - claimed: vorläufige Meldungen der Clients
    public static func finalize(race: OnlineRace, entries: [OnlineRaceEntry], frames: [String: [LiveFrame]],
                                claimed: [OnlineRaceResult], pool: VirtualRowerPool?,
                                judge: RaceJudge = RaceJudge()) -> [OnlineRaceResult] {
        let participants = OnlineRoster.filled(entries, race: race, pool: pool).participants
        let claims = Dictionary(claimed.filter(\.provisional).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var valid: [(RaceResult, [String], RaceParticipant.Source)] = []
        var rejected: [(RaceResult, [String], RaceParticipant.Source)] = []
        let context = VirtualRaceContext(raceId: race.id, startsAt: race.startsAt, target: race.target)
        for p in participants {
            if p.isVirtual {
                guard let r = pool?.rower(id: p.id) else { continue }
                let run = VirtualRaceSimulator.run(r, context: context)
                let res = VirtualRaceSimulator.results(runs: [run], real: [], target: race.target)[0]
                valid.append((res, [], .virtual))
                continue
            }
            let v = judge.check(id: p.id, frames: frames[p.id] ?? [], claimed: claims[p.id], target: race.target)
            guard let res = v.result else { continue }   // nie gestartet: nicht in der Wertung
            if v.valid {
                valid.append((res, v.flags, .human))
            } else {
                var r = res
                r.time = nil
                r.finished = false
                rejected.append((r, v.flags, .human))
            }
        }
        let order = RaceCoordinator.ranking(entries: valid.map { ($0.0.participantId, $0.0.distance, $0.0.finished, $0.0.time) },
                                            target: race.target)
        let byId = Dictionary(valid.map { ($0.0.participantId, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [OnlineRaceResult] = []
        for (i, id) in order.enumerated() {
            guard let (r, flags, source) = byId[id] else { continue }
            var res = r
            res.place = i + 1
            out.append(OnlineRaceResult(res, provisional: false, flags: flags, source: source))
        }
        for (k, item) in rejected.sorted(by: { $0.0.participantId < $1.0.participantId }).enumerated() {
            var res = item.0
            res.place = out.count + k + 1
            out.append(OnlineRaceResult(res, provisional: false, flags: item.1, source: item.2))
        }
        return out
    }
}
