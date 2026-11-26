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
    /// Gesprochene Ansagen (Einstellungen → Training); Hauptschalter für Info-Ansagen und Coach
    static let spokenCuesKey = "training.spokenCues"
    /// Stil des Sprachcoachs (`CoachStyle.rawValue`, Einstellungen → Training → Coach)
    static let coachStyleKey = "training.coachStyle"
    /// Häufigkeit der Coach-Ansagen (`CoachFrequency.rawValue`)
    static let coachFrequencyKey = "training.coachFrequency"

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

    static var coachStyle: CoachStyle {
        UserDefaults.standard.string(forKey: coachStyleKey).flatMap(CoachStyle.init(rawValue:)) ?? .motivating
    }

    static var coachFrequency: CoachFrequency {
        UserDefaults.standard.string(forKey: coachFrequencyKey).flatMap(CoachFrequency.init(rawValue:)) ?? .normal
    }

    /// Pulszonen aus dem Profil (wie `SessionController.currentZones`)
    static var zones: HeartRateZones {
        let d = UserDefaults.standard
        let maxHR = d.integer(forKey: "profile.maxHR"), restHR = d.integer(forKey: "profile.restHR")
        return HeartRateZones(maxHR: maxHR > 0 ? maxHR : 185, restHR: restHR > 0 ? restHR : 55)
    }

    /// Programme, deren Tempo-Ziele nur abgeleitet sind (laut docs/trainings-recherche.md: Grundlage, Schwelle,
    /// Technik, Frequenzleiter); dort zeigt die Detailansicht „Tempo-Ziele sind Richtwerte“.
    static func paceTargetsAreGuides(_ plan: WorkoutPlan) -> Bool {
        ["grundlage-", "schwelle-", "technik-", "frequenzleiter-"].contains { plan.id.hasPrefix($0) }
    }
}

/// Phrasen des Sprachcoachs aus dem Bundle (`coach_phrases.json`); nil, wenn die Datei fehlt oder unlesbar ist
/// (dann bleiben nur die Info-Ansagen wie vor dem Coach).
enum CoachPhrases {
    static let bank: CoachPhraseBank? = {
        guard let url = Bundle.main.url(forResource: "coach_phrases", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? CoachPhraseBank(data: data)
    }()
}

/// Begleitet eine Fahrt im Ruderbildschirm: Töne im Countdown und beim Phasenwechsel, gesprochene Ansagen
/// (`SpeechCoach`; Zeitpunkte und Coach-Phrasen aus `CoachEngine`, die auch die Info-Ansagen von
/// `CoachCueDetector` plant), Tor in der 3D-Szene (bei vorausberechneten Zeitphasen geglättet, damit es nicht
/// springt). Der Coach wird je Tick gefüttert (`coachTick`, etwa 1 Hz und bei jeder Änderung des Trainingsstands),
/// auch beim freien Rudern; Stil und Häufigkeit gelten ab der nächsten Fahrt.
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
    /// Sprachcoach der Fahrt (beim ersten Tick angelegt, mit den Einstellungen zu diesem Zeitpunkt)
    @ObservationIgnored private var coach: CoachEngine?
    @ObservationIgnored private var rideStart: Date?
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
        coach = nil
        rideStart = nil
        speech.stop()
    }

    /// Sprachcoach füttern: Planstand (nil beim freien Rudern), Stand auf der Strecke (nur freies Rudern) und
    /// Messwerte. Ansagen nur, wenn „Gesprochene Ansagen“ an ist (der Coach rechnet trotzdem weiter, damit
    /// einmalige Ansagen nach dem Einschalten nicht nachgeholt werden).
    func coachTick(status: PlanStatus?, free: CoachFreeRide?, snapshot: RowingSnapshot, isRowing: Bool,
                   distance: Double, now: Date = Date()) {
        if coach == nil {
            let settings = CoachSettings(style: TrainingSettings.coachStyle, frequency: TrainingSettings.coachFrequency,
                                         language: AppLanguage.code)
            coach = CoachEngine(plan: plan, settings: settings, phrases: CoachPhrases.bank,
                                best2k: TrainingSettings.best2k, zones: TrainingSettings.zones,
                                seed: UInt64(max(now.timeIntervalSince1970, 0)))
        }
        let start = rideStart ?? now
        rideStart = start
        let input = CoachInput(time: max(now.timeIntervalSince(start), 0), status: status, free: free,
                               distance: distance, strokeRate: isRowing ? Double(snapshot.strokeRate) : 0,
                               strokeCount: snapshot.strokeCount > 0 ? snapshot.strokeCount : nil,
                               pace: snapshot.pace, power: snapshot.power > 0 ? snapshot.power : nil,
                               heartRate: snapshot.heartRate, isRowing: isRowing, isSpeaking: speech.isSpeaking)
        guard let utterances = coach?.update(input), TrainingSettings.spokenCues else { return }
        for u in utterances { speak(u) }
    }

    /// Ansage sprechen: Info-Ansagen mit dem Text aus `CueText`, Coach-Phrasen mit ihrem Text bzw. der Tonkonserve
    private func speak(_ u: CoachUtterance) {
        let text = u.cue.map { CueText.text(for: $0, plan: plan, best2k: TrainingSettings.best2k) } ?? u.text
        speech.say(text, phraseId: u.isDynamic ? nil : u.phraseId, language: AppLanguage.code == "de" ? "de" : "en",
                   priority: u.priority.value, interrupting: u.interrupting)
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
