import Foundation

/// Alle Schwellen, Fenster und Abstände des Sprachcoachs an einem Ort. Standardwerte nach docs/coach/SPEC.md;
/// neue Werte aus der Recherche (docs/coach/RECHERCHE.md) hier nachziehen, ohne die Regeln anzufassen.
/// Zeiten in Sekunden, Tempo in s/500 m, Schlagzahl in /min, Anteile 0…1 einer Phase.
public struct CoachConfig: Equatable, Sendable {
    // MARK: Planer
    /// Globaler Mindestabstand zwischen zwei Ansagen (Info und Phasenwechsel dürfen näher)
    public var minGap: Double = 12
    /// Ruhezone vor einem Phasenwechsel: dort nur Information (Töne 3-2-1)
    public var quietBeforeChange: Double = 4
    /// Sicherheitsabstand vor dem Countdown, damit eine Ansage nicht in ihn hineinläuft
    public var countdownGuard: Double = 1
    /// Sprechgeschwindigkeit für die Schätzung der Dauer einer Ansage (Wörter je Sekunde)
    public var wordsPerSecond: Double = 2.6
    /// Geschätzte Dauer einer Info-Ansage, deren Text die App bildet
    public var infoDuration: Double = 3.5
    /// Budget in Belastung und Pausen: höchstens so viele Ansagen je 60 s (wenig / normal / viel)
    public var budgetPerMinute: [CoachFrequency: Int] = [.low: 1, .normal: 2, .high: 3]
    /// Budget in Grundlage (leichte Phasen) und beim freien Rudern: Mindestabstand (wenig / normal / viel)
    public var easyInterval: [CoachFrequency: Double] = [.low: 360, .normal: 180, .high: 120]
    /// Abklingzeit je Gruppe (gleiches Szenario frühestens wieder nach …)
    public var cooldownByCategory: [CoachCategory: Double] = [
        .praise: 90, .correction: 30, .endPush: 20, .prep: 30, .technique: 240, .safety: 15, .phase: 0, .info: 0,
    ]
    /// Abweichende Abklingzeiten einzelner Szenarien
    public var cooldownByScenario: [CoachScenario: Double] = [.hrHighEasy: 120, .paceLineAhead: 120,
                                                              .paceLineBehind: 120, .restTooHard: 45]
    /// Lob in Grundlage und beim freien Rudern: gleiches Szenario frühestens wieder nach …
    public var easyPraiseCooldown: Double = 360
    /// Korrekturen (gleiches Szenario) höchstens so oft je Phase
    public var maxCorrectionsPerPhase: Int = 3
    /// Eskalation: Stufe 2 frühestens so lange nach Stufe 1, wenn die Lage anhält oder wiederkehrt
    public var escalationDelay: Double = 10
    /// Zufallsauswahl: die letzten k Varianten je Szenario nicht wiederholen
    public var phraseHistory: Int = 3

    // MARK: Messwerte
    /// Glättung (Zeitkonstante, s) für Schlagzahl, Tempo, Watt, Puls
    public var smoothingTau: Double = 4
    /// Basiswert einer Phase: Mittel über dieses Fenster nach Phasenbeginn (s)
    public var baselineWindow: ClosedRange<Double> = 10...40
    /// Kurzes Mittel für Abflachen und Tempo-Vergleiche (letzte … s)
    public var recentWindow: Double = 6
    /// Phasenmittel ohne die letzten … s (damit das Abflachen das Mittel nicht mitzieht)
    public var meanExcludesLast: Double = 10
    /// Anlaufzeit nach Phasenbeginn ohne Korrekturen
    public var settleTime: Double = 15

    // MARK: Struktur
    /// `prep_hard`: Fenster (s bis zum Wechsel) vor einer harten Phase
    public var prepWindow: ClosedRange<Double> = 15...30
    /// `rest_prepare`: Fenster (s bis zum Wechsel) vor dem Ende einer Pause
    public var restPrepareWindow: ClosedRange<Double> = 14...22
    /// `rest_prepare` nur in Pausen ab dieser Länge
    public var restPrepareMinRest: Double = 45
    /// `rest_recover`: Fenster (s nach Pausenbeginn) und Mindestlänge der Pause
    public var restRecoverWindow: ClosedRange<Double> = 12...40
    public var restRecoverMinRest: Double = 60
    /// `interval_done` und Vergleiche: Fenster (s nach Ende der Belastung)
    public var intervalDoneWindow: ClosedRange<Double> = 2...30
    /// `first_strokes`: Fenster (s nach Start) und Mindestlänge der Phase
    public var firstStrokesWindow: ClosedRange<Double> = 10...20
    public var firstStrokesMinPhase: Double = 60
    /// `phase_half`: Fenster (Anteil) und Mindestlänge
    public var phaseHalfWindow: ClosedRange<Double> = 0.5...0.6
    public var phaseHalfMinPhase: Double = 90
    /// `last_quarter`: Fenster (Anteil) und Mindestlänge
    public var lastQuarterWindow: ClosedRange<Double> = 0.75...0.85
    public var lastQuarterMinPhase: Double = 120
    /// `last_30s`: ab so viel Restzeit (Fenster bis 18 s) in harten Zeitphasen ab `last30MinPhase`
    public var last30Window: ClosedRange<Double> = 18...31
    public var last30MinPhase: Double = 60
    /// `last_250m` / `last_100m` in harten Distanzphasen (Fenster Restmeter, Mindestlänge)
    public var last250Window: ClosedRange<Double> = 180...251
    public var last250MinPhase: Double = 500
    public var last100Window: ClosedRange<Double> = 60...101
    public var last100MinPhase: Double = 300
    /// `last_10s` ersetzt in harten Phasen den Countdown, wenn danach eine Pause, das Ausrudern oder das Ende kommt
    public var last10ReplacesCountdown: Bool = true
    /// `workout_final`: letzte 2 min bzw. 500 m des ganzen Trainings (nur in Belastung, Training ab 10 min)
    public var workoutFinalSeconds: Double = 120
    public var workoutFinalMinWorkout: Double = 600

    // MARK: Adaptive Regeln
    /// Abflachen: Schlagzahl ≥ … unter Ziel bzw. Basiswert, oder Tempo ≥ … langsamer als das Phasenmittel
    public var fadeRateDrop: Double = 2
    public var fadePaceDrop: Double = 2.5
    /// … anhaltend (Hysterese)
    public var fadeHold: Double = 4
    /// `fade_end`: letztes Drittel bzw. letzte 60 s / 300 m einer harten Phase
    public var fadeEndFraction: Double = 2.0 / 3.0
    public var fadeEndSeconds: Double = 60
    public var fadeEndMeters: Double = 300
    /// `fade_mid`: ab diesem Anteil (bis `fadeEndFraction`)
    public var fadeMidStart: Double = 0.25
    /// `rate_low` / `rate_high`: Abweichung vom Zielbereich (Belastung / Grundlage), anhaltend
    public var rateTolerance: Double = 1
    public var rateToleranceEasy: Double = 3
    public var rateHold: Double = 6
    /// `pace_on_target`: so lange im Zieltempo und in der Schlagzahl
    public var onTargetHold: Double = 45
    /// `pace_too_fast_early`: erste 25 % einer langen Phase, ≥ 3 s schneller als das Ziel
    public var tooFastFraction: Double = 0.25
    public var tooFastDelta: Double = 3
    public var tooFastHold: Double = 8
    public var longPhaseSeconds: Double = 180
    public var longPhaseMeters: Double = 1000
    /// `pace_slow`: langsamer als Zielbereich + Toleranz, anhaltend
    public var paceSlowTolerance: Double = 1
    public var paceSlowHold: Double = 15
    /// `strong_finish`: letzte 20 %, kurzes Mittel ≥ … schneller als das Phasenmittel, anhaltend
    public var strongFinishFraction: Double = 0.2
    public var strongFinishDelta: Double = 1
    public var strongFinishHold: Double = 5
    /// Intervallvergleich: `consistent` innerhalb ±…, `slower_than_prev` ab …, `best_interval` ab n Intervallen
    public var consistentTolerance: Double = 1.5
    public var slowerThreshold: Double = 3
    public var bestIntervalMinCount: Int = 3
    /// nur Intervalle ähnlicher Länge vergleichen (Verhältnis höchstens …)
    public var compareLengthRatio: Double = 1.25
    /// `hr_high_easy`: Puls ≥ … Zonen über Ziel, anhaltend
    public var hrZoneOver: Int = 1
    public var hrHold: Double = 60
    /// `stopped`: so lange kein Schlag in einer Belastungsphase; nach Stufe 2 Wiederholung höchstens alle … s
    public var stoppedAfter: Double = 5
    public var stoppedRepeat: Double = 60
    /// `rest_too_hard`: in der Pause schneller als 2k-Tempo + … oder Schlagzahl ≥ …, anhaltend
    public var restTooHardPaceOffset: Double = 20
    public var restTooHardRate: Double = 26
    public var restTooHardHold: Double = 10
    /// `technique`: Abstand (zufällig im Bereich), erster Impuls frühestens nach …, nur in Phasen ab …
    public var techniqueInterval: ClosedRange<Double> = 240...420
    public var techniqueFirstAfter: Double = 180
    public var techniqueMinPhase: Double = 480
    /// Tempo-Linie: Abstand (m) für vorn/hinten, anhaltend
    public var paceLineMeters: Double = 10
    public var paceLineHold: Double = 20

    public init() {}

    func cooldown(_ s: CoachScenario) -> Double {
        cooldownByScenario[s] ?? cooldownByCategory[s.category] ?? 30
    }
}
