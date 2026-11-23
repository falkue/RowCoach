import SwiftUI
import RowCoachKit

/// Farbtokens der App (einzige Quelle; Gestaltungssystem in `DesignSystem.swift`, Herleitung in
/// docs/design/ux-review-rowing.md Abschnitt 4). Die ganze App ist dunkel (`.preferredColorScheme(.dark)` an der
/// Wurzel). Abendorange (`accent`) nur für Hauptaktionen und Kicker; Blau, Pink und Grün sind keine Tastenfarben.
enum Theme {
    // MARK: Flächen

    /// Grund aller Seiten (#080F1A)
    static let bg = Color(red: 0.031, green: 0.059, blue: 0.102)
    /// Karten, Listen, Sheets (#121A29)
    static let card = Color(red: 0.071, green: 0.102, blue: 0.161)
    /// etwas hellere Fläche in Karten (Chips, Zeilen)
    static let cardRaised = Color(red: 0.11, green: 0.15, blue: 0.22)
    static let cardStroke = Color.white.opacity(0.07)
    /// Kacheln über der 3D-Szene
    static let hud = Color.black.opacity(0.55)
    static let hudStroke = Color.white.opacity(0.08)

    // MARK: Text

    static let text = Color.white
    static let text2 = Color.white.opacity(0.65)
    static let text3 = Color.white.opacity(0.40)

    // MARK: Aktionen und Zustände

    /// Abendorange (#F29C4D): Hauptaktion (Los, Frei rudern, Speichern, Weiterrudern) und Kicker
    static let accent = Color(red: 0.949, green: 0.612, blue: 0.302)
    /// Text auf `accent`
    static let onAccent = Color.black.opacity(0.85)
    /// Textlinks und Nebenaktionen als Text (#66CCF2)
    static let link = Color(red: 0.40, green: 0.80, blue: 0.95)
    /// Ampel grün, Health-Status ok (#4DD973)
    static let ok = Color(red: 0.302, green: 0.851, blue: 0.451)
    /// Ampel gelb, Hinweis (#FACC40)
    static let warn = Color(red: 0.980, green: 0.800, blue: 0.251)
    /// Ampel rot, Verwerfen (#F24D4D)
    static let bad = Color(red: 0.949, green: 0.302, blue: 0.302)
    /// Tempo-Linie (#FA52BD): nur die Linie in der Szene und ihre Kachel, nie als Tastenfarbe
    static let paceLine = Color(red: 0.98, green: 0.32, blue: 0.74)

    // MARK: Ältere Namen (zeigen auf die Tokens)

    static var background: Color { bg }
    static var homeBackground: Color { bg }
    static var evening: Color { accent }
    static var secondaryText: Color { text2 }
    static var panel: Color { hud }
    static var panelStroke: Color { hudStroke }
    /// „noch offen“ im Seen-Pass
    static var open: Color { link }
    /// Abstand zur Tempo-Linie: voraus grün, zurück gelb
    static var paceAhead: Color { ok }
    static var paceBehind: Color { warn }

    // MARK: Pulszonen (ein einziger Satz für Puls, Phasenleiste, Zonenbänder und Wochenpunkte)

    /// Farbe der Pulszone 0…5 (0 = unter Zone 1: neutral)
    static func zoneColor(_ zone: Int) -> Color {
        switch zone {
        case 1: return Color(red: 0.549, green: 0.651, blue: 0.749)   // #8CA6BF grau-blau
        case 2: return Color(red: 0.302, green: 0.651, blue: 0.949)   // #4DA6F2 blau
        case 3: return Color(red: 0.302, green: 0.800, blue: 0.451)   // #4DCC73 grün
        case 4: return Color(red: 0.980, green: 0.651, blue: 0.200)   // #FAA633 orange
        case 5: return Color(red: 0.949, green: 0.302, blue: 0.302)   // #F24D4D rot
        default: return Color.white.opacity(0.55)
        }
    }

    /// „Zone 2“; unter Zone 1 „locker“ (statt „unter Zone 1“, das wie ein Fehler wirkt)
    static func zoneName(_ zone: Int) -> String {
        zone == 0 ? String(localized: "locker") : String(localized: "Zone \(zone)")
    }

    /// Stufe einer Einheit (Wochenpunkte, Verteilung): leicht = Zone 2, mittel = Zone 3, hart = Zone 4
    static func levelColor(_ level: IntensityLevel) -> Color {
        switch level {
        case .easy: return zoneColor(2)
        case .moderate: return zoneColor(3)
        case .hard: return zoneColor(4)
        }
    }

    /// Härte einer Phase (Phasenleiste, Tore, Countdown): wie die Stufen, Pause ruhig grau
    static func intensityColor(_ intensity: PhaseIntensity) -> Color {
        switch intensity {
        case .easy: return zoneColor(2)
        case .moderate: return zoneColor(3)
        case .hard: return zoneColor(4)
        case .rest: return Color(red: 0.42, green: 0.48, blue: 0.56)
        }
    }

    /// Farbe einer Phase nach ihrer Härte
    static func phaseColor(_ phase: WorkoutPhase?) -> Color {
        guard let phase else { return text }
        return intensityColor(phase.intensity())
    }

    /// relative Höhe einer Phase in der Phasenleiste (Arbeit hoch, Pause niedrig)
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
        case .green: return ok
        case .yellow: return warn
        case .red: return bad
        case .none: return Color.white.opacity(0.25)
        }
    }

    /// Zahlen mit fester Ziffernbreite, damit nichts springt (Ruderbildschirm: feste Grössen)
    static func number(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

/// Hintergrund-Kachel des HUD (deckend genug für Luftbild und Wasser)
struct HUDPanel: ViewModifier {
    var cornerRadius: CGFloat = DS.Radius.tile
    var stroke: Color = Theme.hudStroke
    var lineWidth: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .background(Theme.hud, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(stroke, lineWidth: lineWidth))
    }
}

extension View {
    func hudPanel(cornerRadius: CGFloat = DS.Radius.tile, stroke: Color = Theme.hudStroke,
                  lineWidth: CGFloat = 1) -> some View {
        modifier(HUDPanel(cornerRadius: cornerRadius, stroke: stroke, lineWidth: lineWidth))
    }
}
