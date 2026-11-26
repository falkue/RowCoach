import Foundation

/// Eine Ansage des Coachs (Ausgang von `CoachEngine`).
///
/// - Coach-Phrase: `scenario`, `text` und `phraseId` sind gesetzt. Ist `isDynamic` false, darf die App statt der
///   Systemstimme die Tonkonserve `Coach/<sprache>/<phraseId>.m4a` abspielen.
/// - Info-Ansage: `cue` ist gesetzt und `text` leer; die App bildet den Text wie bisher (`CueText`).
public struct CoachUtterance: Equatable, Sendable {
    public var text: String
    /// `<szenario>.<stufe>.<stil>.<index>` (Index = Position ab 0 in der Liste der Sprache); nil bei Info-Ansagen
    public var phraseId: String?
    public var scenario: CoachScenario?
    public var cue: CoachCue?
    public var level: Int
    /// true = enthält eingesetzte Werte (immer Systemstimme)
    public var isDynamic: Bool
    public var priority: CoachPriority
    /// darf eine laufende Ansage mit niedrigerer Priorität abbrechen
    public var interrupting: Bool
    /// Zeitpunkt (Zeitbasis von `CoachInput.time`)
    public var time: Double

    public init(text: String, phraseId: String?, scenario: CoachScenario?, cue: CoachCue?, level: Int,
                isDynamic: Bool, priority: CoachPriority, interrupting: Bool, time: Double) {
        self.text = text
        self.phraseId = phraseId
        self.scenario = scenario
        self.cue = cue
        self.level = level
        self.isDynamic = isDynamic
        self.priority = priority
        self.interrupting = interrupting
        self.time = time
    }

    public var category: CoachCategory { scenario?.category ?? .info }
    public var isInfo: Bool { cue != nil }
}
