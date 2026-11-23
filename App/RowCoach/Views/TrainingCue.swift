import AudioToolbox
import Foundation
import Observation
import RowCoachKit

/// Einstellungen für den Trainingsbereich (UserDefaults bzw. @AppStorage)
enum TrainingSettings {
    /// 2000-m-Bestzeit in Sekunden (Einstellungen → Profil); Grundlage der Tempo-Ziele
    static let best2kKey = "profile.best2k"
    /// Ton beim Countdown (Einstellungen → Training)
    static let countdownSoundKey = "training.countdownSound"
    /// Gesprochene Ansagen (Einstellungen → Training)
    static let spokenCuesKey = "training.spokenCues"

    static var best2k: Double {
        let v = UserDefaults.standard.double(forKey: best2kKey)
        return v > 0 ? v : PaceTargets.defaultBest2k
    }

    static var countdownSound: Bool {
        UserDefaults.standard.object(forKey: countdownSoundKey) as? Bool ?? true
    }

    static var spokenCues: Bool {
        UserDefaults.standard.object(forKey: spokenCuesKey) as? Bool ?? true
    }

    /// Programme, deren Tempo-Ziele nur abgeleitet sind (laut docs/trainings-recherche.md: Grundlage, Schwelle,
    /// Technik, Frequenzleiter); dort zeigt die Detailansicht „Tempo-Ziele sind Richtwerte“.
    static func paceTargetsAreGuides(_ plan: WorkoutPlan) -> Bool {
        ["grundlage-", "schwelle-", "technik-", "frequenzleiter-"].contains { plan.id.hasPrefix($0) }
    }
}

/// Begleitet eine Fahrt im Ruderbildschirm: Töne im Countdown und beim Phasenwechsel, gesprochene Ansagen
/// (`SpeechCoach`, Zeitpunkte aus `CoachCueDetector`), Tor in der 3D-Szene (bei vorausberechneten Zeitphasen
/// geglättet, damit es nicht springt).
@MainActor
@Observable
final class TrainingCue {
    /// Tor an der Stelle, an der die nächste Phase beginnt (bzw. das Training endet)
    private(set) var gate: GateMarker?

    @ObservationIgnored private var lastPhaseIndex: Int?
    @ObservationIgnored private var lastTickSecond: Int?
    @ObservationIgnored private var wasFinished = false
    @ObservationIgnored private var gateDistance: Double?
    @ObservationIgnored private var gateId: String?
    @ObservationIgnored private var lastUpdate: Date?
    @ObservationIgnored private var detector = CoachCueDetector()
    private var speech: SpeechCoach { SpeechCoach.shared }
    /// Programm des Trainings (für „Intervall 2“ in den Ansagen)
    @ObservationIgnored var plan: WorkoutPlan?

    /// Systemtöne (AudioToolbox). Die IDs sind nicht dokumentiert, aber seit Jahren stabil: 1103 = „Tink“ (kurz, leise),
    /// 1113 = „begin_record“ (Wechsel). Lautstärke folgt der Systemlautstärke.
    private static let tickSound: SystemSoundID = 1103
    private static let changeSound: SystemSoundID = 1113
    /// Glättung des vorausberechneten Tors (s)
    private static let gateTau = 1.5

    init() {}

    func reset() {
        gate = nil
        lastPhaseIndex = nil
        lastTickSecond = nil
        wasFinished = false
        gateDistance = nil
        gateId = nil
        lastUpdate = nil
        detector = CoachCueDetector()
        speech.stop()
    }

    /// Freies Rudern: Stand auf der Strecke (Halbzeit, „Noch 500 Meter“)
    func updateFree(distance: Double, total: Double) {
        for cue in detector.update(distance: distance, total: total) { announce(cue) }
    }

    /// Ansage sprechen (wenn eingeschaltet)
    private func announce(_ cue: CoachCue) {
        guard TrainingSettings.spokenCues else { return }
        speech.say(CueText.text(for: cue, plan: plan, best2k: TrainingSettings.best2k))
    }

    /// Neuer Stand des Trainings (bei jeder Änderung von `SessionController.planStatus`).
    func update(status: PlanStatus, laps: LapTrack, now: Date = Date()) {
        let sound = TrainingSettings.countdownSound
        // Töne: 3, 2, 1 und beim Wechsel
        if let last = lastPhaseIndex, status.phaseIndex != last {
            if sound { AudioServicesPlaySystemSound(Self.changeSound) }
            lastTickSecond = nil
        } else if status.finished && !wasFinished {
            if sound { AudioServicesPlaySystemSound(Self.changeSound) }
        } else if status.countdownActive, let secs = status.secondsToChange {
            let sec = Int(secs.rounded(.up))
            // geschätzte Countdowns (Distanzphasen) können zurückspringen: jede Zahl nur einmal, nur abwärts
            if (1...3).contains(sec), sec < (lastTickSecond ?? Int.max) {
                if sound { AudioServicesPlaySystemSound(Self.tickSound) }
                lastTickSecond = sec
            }
        }
        lastPhaseIndex = status.phaseIndex
        wasFinished = status.finished
        for cue in detector.update(status: status) { announce(cue) }

        // Tor
        let dt = lastUpdate.map { min(max(now.timeIntervalSince($0), 0), 2) } ?? 0
        lastUpdate = now
        guard !status.finished, let target = status.nextChangeDistance else {
            gate = nil
            gateDistance = nil
            gateId = nil
            return
        }
        let id = "gate-\(status.phaseIndex + 1)"
        var d = target
        if id == gateId, !status.nextChangeIsExact, let prev = gateDistance {
            d = prev + (target - prev) * (1 - exp(-dt / Self.gateTau))
        }
        gateId = id
        gateDistance = d
        let p = laps.pose(atDistance: d)
        gate = GateMarker(id: id, x: p.x, z: p.z, heading: p.heading, kind: status.nextPhase?.kind)
    }
}
