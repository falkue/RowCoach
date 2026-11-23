import SwiftUI
import RowCoachKit

/// Ruhiges, dunkles Erscheinungsbild für Ruderbildschirm und Zusammenfassung.
enum Theme {
    static let background = Color(red: 0.04, green: 0.06, blue: 0.08)
    static let panel = Color.black.opacity(0.48)
    static let panelStroke = Color.white.opacity(0.08)
    static let accent = Color(red: 0.40, green: 0.80, blue: 0.95)
    static let secondaryText = Color.white.opacity(0.62)
    /// Tempo-Linie (wie das Band in der 3D-Szene, `PaceLineEntity.color`)
    static let paceLine = Color(red: 0.98, green: 0.32, blue: 0.74)
    /// Abstand zur Tempo-Linie: voraus grün, zurück orange
    static let paceAhead = Color(red: 0.30, green: 0.85, blue: 0.45)
    static let paceBehind = Color(red: 0.98, green: 0.62, blue: 0.20)

    // Startbildschirm: dunkel und ruhig, nur „Los“ farbig
    /// Abendorange wie im Logo (Taste „Los“, Überschrift der Vorschlagskarte)
    static let evening = Color(red: 0.95, green: 0.61, blue: 0.30)
    /// Grund des Startbildschirms (Nachtblau)
    static let homeBackground = Color(red: 0.03, green: 0.06, blue: 0.10)
    /// ruhige Karte auf dem Startbildschirm
    static let card = Color(red: 0.07, green: 0.10, blue: 0.16)
    static let cardStroke = Color.white.opacity(0.07)
    /// „noch offen“ im Seen-Pass
    static let open = Color(red: 0.45, green: 0.75, blue: 1.00)

    /// Farbe der Intensitätsstufe: leicht blau, mittel grün, hart orange (wie die Pulszonen 2, 3, 4)
    static func levelColor(_ level: IntensityLevel) -> Color {
        switch level {
        case .easy: return zoneColor(2)
        case .moderate: return zoneColor(3)
        case .hard: return zoneColor(4)
        }
    }

    /// Zahlen mit fester Ziffernbreite, damit nichts springt
    static func number(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }

    /// Farbe der Pulszone 0…5
    static func zoneColor(_ zone: Int) -> Color {
        switch zone {
        case 1: return Color(red: 0.55, green: 0.65, blue: 0.75)   // grau-blau: sehr leicht
        case 2: return Color(red: 0.30, green: 0.65, blue: 0.95)   // blau: leicht
        case 3: return Color(red: 0.30, green: 0.80, blue: 0.45)   // grün: mittel
        case 4: return Color(red: 0.98, green: 0.65, blue: 0.20)   // orange: hart
        case 5: return Color(red: 0.95, green: 0.30, blue: 0.30)   // rot: maximal
        default: return Color.white                                  // unter Zone 1: neutral
        }
    }

    static func zoneName(_ zone: Int) -> String {
        zone == 0 ? "unter Zone 1" : "Zone \(zone)"
    }

    /// Farbe einer Trainingsphase: Belastung warm, Pause kühl (wie die Tore in der 3D-Szene)
    static func phaseColor(_ kind: WorkoutPhase.Kind?) -> Color {
        switch kind {
        case .work: return Color(red: 0.98, green: 0.45, blue: 0.18)
        case .rest: return Color(red: 0.30, green: 0.72, blue: 1.00)
        case .warmup: return Color(red: 0.80, green: 0.88, blue: 0.35)
        case .cooldown: return Color(red: 0.55, green: 0.55, blue: 0.98)
        case .other: return Color(white: 0.75)
        case .none: return Color.white
        }
    }

    /// relative Höhe einer Phase in der Phasenleiste (Belastung hoch, Pause niedrig)
    static func phaseHeight(_ kind: WorkoutPhase.Kind) -> CGFloat {
        switch kind {
        case .work: return 1
        case .warmup, .cooldown: return 0.55
        case .rest: return 0.3
        case .other: return 0.6
        }
    }

    /// Ampelfarbe
    static func lightColor(_ light: TargetLight) -> Color {
        switch light {
        case .green: return Color(red: 0.30, green: 0.85, blue: 0.45)
        case .yellow: return Color(red: 0.98, green: 0.80, blue: 0.25)
        case .red: return Color(red: 0.95, green: 0.30, blue: 0.30)
        case .none: return Color.white.opacity(0.25)
        }
    }
}

/// Hintergrund-Kachel des HUD
struct HUDPanel: ViewModifier {
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(Theme.panelStroke))
    }
}

extension View {
    func hudPanel(cornerRadius: CGFloat = 16) -> some View { modifier(HUDPanel(cornerRadius: cornerRadius)) }
}
