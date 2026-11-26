import AVFoundation
import Foundation
import os
import RowCoachKit

/// Gesprochene Ansagen während der Fahrt: Tonkonserve `Coach/<de|en>/<phraseId>.m4a` aus dem Bundle (AVAudioPlayer),
/// wenn es sie gibt und die Phrase statisch ist, sonst AVSpeechSynthesizer. Die Audio-Session nutzt `.playback` mit
/// `.spokenAudio` und `.duckOthers`: Musik wird während der Ansage leiser statt abzubrechen und danach wieder
/// lauter (`setActive(false, options: .notifyOthersOnDeactivation)`). Die Stimme folgt der Sprache der App.
///
/// Unterbrechung nach Priorität (`CoachPriority`, für beide Wege gleich): Läuft eine Ansage, bricht eine neue sie nur
/// ab, wenn sie wichtiger ist oder gleich wichtig und unterbrechen darf (z. B. Info ersetzt Info); sonst fällt die
/// neue weg (der Coach-Planer spricht ohnehin nicht in eine laufende Ansage hinein).
@MainActor
final class SpeechCoach: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    /// Eine Stimme für die ganze App (der Ruderbildschirm wird oft neu aufgebaut)
    static let shared = SpeechCoach()

    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    /// Priorität der laufenden Ansage
    private var currentPriority = 0
    private let log = Logger(subsystem: "com.falkue.RowCoach", category: "Session")

    /// Priorität der bisherigen Info-Ansagen (wie `CoachPriority.info`)
    static let infoPriority = 100

    /// Spricht oder spielt gerade etwas
    var isSpeaking: Bool { synthesizer.isSpeaking || (player?.isPlaying ?? false) }

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Info-Ansage (ersetzt eine laufende)
    func say(_ text: String) {
        say(text, phraseId: nil, language: AppLanguage.code, priority: Self.infoPriority, interrupting: true)
    }

    /// Ansage mit Priorität; mit `phraseId` zuerst die Tonkonserve, sonst die Systemstimme
    func say(_ text: String, phraseId: String?, language: String, priority: Int, interrupting: Bool) {
        guard !text.isEmpty else { return }
        if isSpeaking {
            guard priority > currentPriority || (interrupting && priority >= currentPriority) else {
                log.info("Ansage verworfen (läuft noch, Priorität \(priority) ≤ \(self.currentPriority)): \(text, privacy: .public)")
                return
            }
            stopCurrent()
        }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            log.error("Audio-Session für Ansage: \(error.localizedDescription, privacy: .public)")
        }
        currentPriority = priority
        if let phraseId, let url = Self.audioURL(phraseId: phraseId, language: language) {
            do {
                let p = try AVAudioPlayer(contentsOf: url)
                p.delegate = self
                if p.play() {
                    player = p
                    log.info("Tonkonserve \(language, privacy: .public)/\(phraseId, privacy: .public): \(text, privacy: .public)")
                    return
                }
            } catch {
                log.error("Tonkonserve \(phraseId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.preUtteranceDelay = 0.05
        let voiceLanguage = utterance.voice?.language ?? "?"
        log.info("Ansage (\(voiceLanguage, privacy: .public)): \(text, privacy: .public)")
        synthesizer.speak(utterance)
    }

    /// Laufende Ansage beenden (ohne die Audio-Session abzugeben; die nächste Ansage folgt sofort)
    private func stopCurrent() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        player?.stop()
        player = nil
    }

    /// Tonkonserve im Bundle (Ordnerreferenz `Coach/<sprache>/`); nil, wenn es keine gibt
    private static func audioURL(phraseId: String, language: String) -> URL? {
        Bundle.main.url(forResource: phraseId, withExtension: "m4a", subdirectory: "Coach/\(language)")
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        player?.stop()
        player = nil
        deactivate()
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.deactivateIfIdle() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.deactivateIfIdle() }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in self?.deactivateIfIdle() }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in self?.deactivateIfIdle() }
    }

    private func deactivateIfIdle() {
        guard !isSpeaking else { return }
        player = nil
        deactivate()
    }

    private func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Stimme in der Sprache der App: zuerst mit der Region des Geräts (de-CH), sonst die erste passende Stimme
    private static var voice: AVSpeechSynthesisVoice? {
        let code = AppLanguage.code
        if let region = Locale.current.region?.identifier,
           let v = AVSpeechSynthesisVoice(language: "\(code)-\(region)") {
            return v
        }
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(code) }
        return voices.first(where: { $0.language == "\(code)-DE" || $0.language == "\(code)-US" }) ?? voices.first
    }
}

/// Texte der Ansagen (lokalisierbar: ganze Sätze, Zahlen über Formate)
enum CueText {
    static func text(for cue: CoachCue, plan: WorkoutPlan?, best2k: Double) -> String {
        switch cue {
        case .countdown(let seconds, let next, let nextIndex):
            guard let next else { return String(localized: "Noch \(seconds) Sekunden – gleich geschafft.") }
            switch next.kind {
            case .work:
                let number = plan?.workNumber(at: nextIndex)
                if let pace = next.paceRange(best2k: best2k) {
                    let mid = DSFormat.spokenDuration((pace.lowerBound + pace.upperBound) / 2)
                    if let number {
                        return String(localized: "Noch \(seconds) Sekunden – gleich Intervall \(number), Tempo \(mid) pro 500 Meter.")
                    }
                    return String(localized: "Noch \(seconds) Sekunden – gleich Intervall, Tempo \(mid) pro 500 Meter.")
                }
                if let spm = next.spmRange {
                    let rate = spm.lowerBound == spm.upperBound ? "\(spm.lowerBound)"
                        : String(localized: "\(spm.lowerBound) bis \(spm.upperBound)")
                    if let number {
                        return String(localized: "Noch \(seconds) Sekunden – gleich Intervall \(number), Schlagzahl \(rate).")
                    }
                    return String(localized: "Noch \(seconds) Sekunden – gleich Intervall, Schlagzahl \(rate).")
                }
                if let number { return String(localized: "Noch \(seconds) Sekunden – gleich Intervall \(number).") }
                return String(localized: "Noch \(seconds) Sekunden – gleich Intervall.")
            case .rest:
                return String(localized: "Noch \(seconds) Sekunden – gleich Pause.")
            case .cooldown:
                return String(localized: "Noch \(seconds) Sekunden – gleich Ausrudern.")
            case .warmup, .other:
                return String(localized: "Noch \(seconds) Sekunden – gleich \(next.kind.title).")
            }
        case .phaseStarted(let phase, _):
            switch phase.kind {
            case .work:
                return String(localized: "Los!")
            case .rest:
                if let d = phase.durationS {
                    return String(localized: "Pause, \(DSFormat.spokenDuration(d)).")
                }
                if let m = phase.distanceM {
                    return String(localized: "Pause, \(Int(m)) Meter.")
                }
                return String(localized: "Pause.")
            case .cooldown:
                if let d = phase.durationS {
                    return String(localized: "Ausrudern, \(DSFormat.spokenDuration(d)).")
                }
                return String(localized: "Ausrudern.")
            case .warmup:
                if let d = phase.durationS {
                    return String(localized: "Einrudern, \(DSFormat.spokenDuration(d)).")
                }
                if let m = phase.distanceM {
                    return String(localized: "Einrudern, \(Int(m)) Meter.")
                }
                return String(localized: "Einrudern.")
            case .other:
                return phase.title
            }
        case .halfway:
            return String(localized: "Halbzeit.")
        case .remaining(let meters):
            return String(localized: "Noch \(meters) Meter.")
        case .finished:
            return String(localized: "Geschafft!")
        }
    }
}
