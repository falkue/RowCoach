import SwiftUI
import RowCoachKit

/// Ruhiges, dunkles Erscheinungsbild für Ruderbildschirm und Zusammenfassung.
enum Theme {
    static let background = Color(red: 0.04, green: 0.06, blue: 0.08)
    static let panel = Color.black.opacity(0.48)
    static let panelStroke = Color.white.opacity(0.08)
    static let accent = Color(red: 0.40, green: 0.80, blue: 0.95)
    static let secondaryText = Color.white.opacity(0.62)

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
        default: return Color.white.opacity(0.7)
        }
    }

    static func zoneName(_ zone: Int) -> String {
        zone == 0 ? "unter Zone 1" : "Zone \(zone)"
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
