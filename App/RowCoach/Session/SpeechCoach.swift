import AVFoundation
import Foundation
import os
import RowCoachKit

/// Gesprochene Ansagen während der Fahrt (AVSpeechSynthesizer). Die Audio-Session nutzt `.playback` mit
/// `.spokenAudio` und `.duckOthers`: Musik wird während der Ansage leiser statt abzubrechen und danach wieder
/// lauter (`setActive(false, options: .notifyOthersOnDeactivation)`). Die Stimme folgt der Sprache der App.
@MainActor
final class SpeechCoach: NSObject, AVSpeechSynthesizerDelegate {
    /// Eine Stimme für die ganze App (der Ruderbildschirm wird oft neu aufgebaut)
    static let shared = SpeechCoach()

    private let synthesizer = AVSpeechSynthesizer()
    private let log = Logger(subsystem: "com.falkue.RowCoach", category: "Session")

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func say(_ text: String) {
        guard !text.isEmpty else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            log.error("Audio-Session für Ansage: \(error.localizedDescription, privacy: .public)")
        }
        // Eine neue Ansage ersetzt eine noch laufende (z. B. Countdown direkt vor dem Wechsel)
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .word) }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.preUtteranceDelay = 0.05
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        deactivate()
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.deactivateIfIdle() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.deactivateIfIdle() }
    }

    private func deactivateIfIdle() {
        guard !synthesizer.isSpeaking else { return }
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
                        return String(localized: "Noch \(seconds) Sekunden – gleich Intervall \(number), Tempo \(mid).")
                    }
                    return String(localized: "Noch \(seconds) Sekunden – gleich Intervall, Tempo \(mid).")
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
                return String(localized: "Ausrudern.")
            case .warmup, .other:
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
