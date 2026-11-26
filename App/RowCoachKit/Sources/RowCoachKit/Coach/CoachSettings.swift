import Foundation

/// Stil des Sprachcoachs (Einstellungen → Training → „Coach“). `off` = nur die Informationsansagen
/// (Phasenwechsel, Countdown, Halbzeit, Ziel) wie vor dem Coach.
public enum CoachStyle: String, Codable, Sendable, CaseIterable {
    case off, calm, motivating, cox

    /// Reihenfolge, in der die Phrasendatei nach einem Stil gefragt wird, wenn der gewählte fehlt
    var fallbacks: [CoachStyle] {
        switch self {
        case .off: return []
        case .calm: return [.calm, .motivating, .cox]
        case .motivating: return [.motivating, .calm, .cox]
        case .cox: return [.cox, .motivating, .calm]
        }
    }
}

/// Häufigkeit der Coach-Ansagen (Budget, siehe `CoachConfig`)
public enum CoachFrequency: String, Codable, Sendable, CaseIterable {
    case low, normal, high
}

/// Einstellungen einer Fahrt (werden beim Start festgehalten)
public struct CoachSettings: Equatable, Sendable {
    public var style: CoachStyle
    public var frequency: CoachFrequency
    /// Sprache der Ansagen: "de" oder "en"
    public var language: String

    public init(style: CoachStyle = .motivating, frequency: CoachFrequency = .normal, language: String = "de") {
        self.style = style
        self.frequency = frequency
        self.language = language == "de" ? "de" : "en"
    }
}
