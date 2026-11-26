import Foundation

/// Wiedergabe einer gespeicherten Fahrt (Zeitreihe `WorkoutSample`, ca. 1 Hz) durch `PlanEngine` und
/// `CoachEngine`: Welche Ansagen wären wann gekommen? Für Tests und zum Einstellen der Parameter
/// (Ansagen je Minute zählen). Die Ruderzeit wird aus den Messpunkten geschätzt (Schlagzahl > 0 = gerudert).
public enum CoachReplay {
    public struct Entry: Equatable, Sendable {
        public var utterance: CoachUtterance
        public var phaseIndex: Int?
        public var phaseKind: WorkoutPhase.Kind?
        public var phaseIntensity: PhaseIntensity?
        /// Sekunden bis zum nächsten Wechsel zum Zeitpunkt der Ansage
        public var secondsToChange: Double?
        public var phaseProgress: Double?
    }

    public struct Result: Equatable, Sendable {
        public var entries: [Entry]
        /// Dauer der Fahrt (s)
        public var duration: Double

        public var utterances: [CoachUtterance] { entries.map(\.utterance) }

        /// Ansagen je angefangene Minute (Coach-Phrasen; mit `includeInfo` auch Info-Ansagen)
        public func perMinute(includeInfo: Bool = false) -> [Int] {
            var out = [Int](repeating: 0, count: max(Int((duration / 60).rounded(.up)), 1))
            for e in entries where includeInfo || !e.utterance.isInfo {
                let m = min(Int(e.utterance.time / 60), out.count - 1)
                out[m] += 1
            }
            return out
        }

        /// Anzahl je Szenario (Info-Ansagen unter "info")
        public var countByScenario: [String: Int] {
            entries.reduce(into: [:]) { $0[$1.utterance.scenario?.rawValue ?? "info", default: 0] += 1 }
        }

        /// Lesbares Protokoll: „12:34  [fade_end/1] Halt die Schlagzahl!“
        public var log: String {
            entries.map { e in
                let u = e.utterance
                let tag = u.scenario.map { "\($0.rawValue)/\(u.level)" } ?? "info"
                let text = u.cue.map { "\($0)" } ?? u.text
                return "\(Format.duration(u.time))  [\(tag)] \(text)"
            }.joined(separator: "\n")
        }
    }

    /// - Parameters:
    ///   - plan: gefahrenes Programm; nil = freies Rudern (dann `courseLength` für Halbzeit/„Noch 500 m“)
    ///   - paceLine: Tempo der Tempo-Linie beim freien Rudern (s/500 m), optional
    public static func run(samples: [WorkoutSample], plan: WorkoutPlan?, courseLength: Double? = nil,
                           paceLine: Double? = nil, settings: CoachSettings = CoachSettings(),
                           config: CoachConfig = CoachConfig(), phrases: CoachPhraseBank?,
                           best2k: Double = PaceTargets.defaultBest2k, zones: HeartRateZones? = nil,
                           seed: UInt64 = 1) -> Result {
        var planEngine = plan.map { PlanEngine(plan: $0, best2k: best2k) }
        var coach = CoachEngine(plan: plan, settings: settings, config: config, phrases: phrases, best2k: best2k,
                                zones: zones, seed: seed)
        let line = paceLine.map { PaceLine(pace: $0) }
        var entries: [Entry] = []
        var active = 0.0
        var prevTime: Double? = 0
        var started = false
        for s in samples.sorted(by: { $0.time < $1.time }) {
            let rowing = s.strokeRate > 0
            if !started {
                // wie in der App: der Coach beginnt mit dem ersten Schlag
                guard rowing else { prevTime = s.time; continue }
                started = true
            }
            let dt = prevTime.map { min(max(s.time - $0, 0), 5) } ?? 0
            prevTime = s.time
            if rowing { active += dt }
            var status: PlanStatus?
            if var pe = planEngine {
                status = pe.update(activeTime: active, elapsedTime: s.time, distance: s.distance,
                                   speed: rowing && s.pace > 0 ? 500 / s.pace : 0)
                planEngine = pe
            }
            var free: CoachFreeRide?
            if plan == nil, let total = courseLength {
                let gap = line.map { $0.gap(boatDistance: s.distance, activeTime: active, total: total) }
                let remaining = s.pace > 0 ? max(total - s.distance, 0) / 500 * s.pace : nil
                free = CoachFreeRide(distance: s.distance, total: total, paceLineGap: gap?.meters,
                                     paceLineGapSeconds: gap?.seconds, estimatedRemaining: remaining)
            }
            let input = CoachInput(time: s.time, status: status, free: free, distance: s.distance, strokeRate: Double(s.strokeRate),
                                   pace: s.pace, power: s.power > 0 ? s.power : nil, heartRate: s.heartRate,
                                   isRowing: rowing)
            for u in coach.update(input) {
                entries.append(Entry(utterance: u, phaseIndex: status?.phaseIndex, phaseKind: status?.phase?.kind,
                                     phaseIntensity: status?.phase?.intensity(),
                                     secondsToChange: status?.secondsToChange, phaseProgress: status?.phaseProgress))
            }
            if status?.finished == true, entries.contains(where: { $0.utterance.cue == .finished
                || $0.utterance.scenario == .workoutDone }) {
                break
            }
        }
        return Result(entries: entries, duration: samples.last?.time ?? 0)
    }

    public static func run(record: WorkoutRecord, plan: WorkoutPlan?, courseLength: Double? = nil,
                           settings: CoachSettings = CoachSettings(), config: CoachConfig = CoachConfig(),
                           phrases: CoachPhraseBank?, best2k: Double = PaceTargets.defaultBest2k,
                           zones: HeartRateZones? = nil, seed: UInt64 = 1) -> Result {
        run(samples: record.samples, plan: plan, courseLength: courseLength, settings: settings, config: config,
            phrases: phrases, best2k: best2k, zones: zones, seed: seed)
    }
}
