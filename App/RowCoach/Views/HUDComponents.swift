import SwiftUI
import RowCoachKit

/// Messwert-Kachel im HUD: Beschriftung, grosse Zahl mit kleiner Einheit, darunter optional das Ziel
/// („Ziel 1:58–2:02“) mit Ampel als Symbol; der Rand färbt sich nach der Ampel. Feste Grössen (Blickabstand 1–1,5 m).
struct HUDTile: View {
    let title: String
    let value: String
    var unit: String? = nil
    /// Nebenzeile (Ziel, Zone); immer reserviert, damit alle Kacheln einer Reihe gleich hoch sind
    var detail: String? = nil
    var light: TargetLight? = nil
    /// Richtung für das Ampel-Symbol (true = Wert soll steigen)
    var shouldIncrease: Bool? = nil
    /// Farbbalken links (z. B. Pulszone); die Zahl bleibt weiss
    var accentBar: Color? = nil
    var size: CGFloat = 72
    var compact = false

    var body: some View {
        // Farbbalken als Overlay, damit er die Kachel nicht in die Höhe zieht
        VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: DS.HUD.label(compact: compact), weight: .bold))
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.text2)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    // nie abschneiden: lieber kleiner (die Zahl hat Vorrang vor der Einheit)
                    Text(value)
                        .font(Theme.number(size))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.3)
                        .allowsTightening(true)
                        .layoutPriority(1)
                    if let unit {
                        Text(unit)
                            .font(.system(size: DS.HUD.label(compact: compact) + 2, weight: .medium))
                            .foregroundStyle(Theme.text2)
                            .fixedSize()
                    }
                }
                HStack(spacing: 6) {
                    if let light, light != .none {
                        LightSymbol(light: light, shouldIncrease: shouldIncrease, size: DS.HUD.detail(compact: compact))
                    }
                    Text(detail ?? " ")
                        .font(.system(size: DS.HUD.detail(compact: compact), weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.text2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
        }
        .padding(.leading, accentBar == nil ? 0 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, compact ? 12 : 18)
        .padding(.vertical, compact ? 8 : 12)
        .overlay(alignment: .leading) {
            if let accentBar {
                RoundedRectangle(cornerRadius: 3).fill(accentBar)
                    .frame(width: 6)
                    .padding(.vertical, compact ? 10 : 16)
                    .padding(.leading, compact ? 10 : 14)
            }
        }
        .hudPanel(stroke: borderColor, lineWidth: borderWidth)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(accessibilityValue))
    }

    private var borderWidth: CGFloat {
        guard let light, light != .none else { return 1 }
        return 3
    }

    private var borderColor: Color {
        guard let light, light != .none else { return Theme.hudStroke }
        return Theme.lightColor(light)
    }

    private var accessibilityValue: String {
        var parts = [unit.map { "\(value) \($0)" } ?? value]
        if let detail { parts.append(detail) }
        if let light, light != .none { parts.append(LightSymbol.name(light, shouldIncrease: shouldIncrease)) }
        return parts.joined(separator: ", ")
    }
}

/// Wert in der oberen Leiste
struct HUDStat: View {
    let title: String
    let value: String
    var size: CGFloat = 44
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: DS.HUD.label(compact: compact), weight: .bold))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(Theme.text2)
            Text(value).font(Theme.number(size)).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Fortschritt über die ganze Strecke: Marke am Wendepunkt, Bootssymbol an der aktuellen Position.
struct CourseProgressBar: View {
    /// 0…1
    let progress: Double
    /// Lage der Wende 0…1 (nil = keine Wende)
    var turnAt: Double? = 0.5
    var height: CGFloat = 10

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let w = geo.size.width
                let p = min(max(progress, 0), 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15))
                        .frame(height: height)
                    Capsule().fill(Color.white.opacity(0.85))
                        .frame(width: max(height, w * p), height: height)
                    if let turnAt {
                        Rectangle().fill(Color.white.opacity(0.85))
                            .frame(width: 2, height: height + 10)
                            .offset(x: w * turnAt - 1)
                    }
                    Image(systemName: "figure.rower")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.bg)
                        .padding(5)
                        .background(Circle().fill(Color.white))
                        .offset(x: min(max(w * p - 14, 0), w - 28))
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 30)
            HStack {
                Text("Start")
                Spacer()
                if turnAt != nil { Text("Wende") }
                Spacer()
                Text("Ziel")
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.secondaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fortschritt")
        .accessibilityValue("\(Int((progress * 100).rounded())) Prozent")
    }
}

/// Kompakte Anzeige der Tempo-Linie beim freien Rudern: Zieltempo und Abstand („+12 m voraus“, „−8 m zurück“).
struct PaceLinePanel: View {
    let pace: Double
    let gap: PaceLineGap
    var compact = false

    init(pace: Double, gap: PaceLineGap, compact: Bool = false) {
        self.pace = pace
        self.gap = gap
        self.compact = compact
    }

    private var tint: Color {
        switch gap.standing {
        case .ahead: return Theme.paceAhead
        case .behind: return Theme.paceBehind
        case .level: return .white
        }
    }

    /// Abstand als Zahl: „+12 m“, „−8 m“, „±0 m“
    private var mainText: String {
        let m = Int(abs(gap.meters).rounded())
        switch gap.standing {
        case .ahead: return "+\(m) m"
        case .behind: return "−\(m) m"
        case .level: return "±0 m"
        }
    }

    private var standingText: String {
        switch gap.standing {
        // ab ca. 4 m voraus liegt die Linie hinter der Kamera
        case .ahead: return abs(gap.meters) >= 4 ? String(localized: "voraus · Linie hinter dir")
            : String(localized: "voraus")
        case .behind: return String(localized: "zurück")
        case .level: return String(localized: "gleichauf")
        }
    }

    private var secondsText: String {
        guard gap.standing != .level else { return " " }
        return String(localized: "\(Self.decimal(abs(gap.seconds))) s")
    }

    /// eine Nachkommastelle im Format der Sprache
    static func decimal(_ v: Double) -> String { DSFormat.decimal(v) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Capsule().fill(Theme.paceLine).frame(width: 18, height: 6)
                Text("Tempo-Linie \(Format.duration(pace)) /500 m")
                    .font(.system(size: DS.HUD.label(compact: compact), weight: .bold))
                    .foregroundStyle(Theme.text2)
                    .lineLimit(1)
                if gap.lineFinished {
                    Text("im Ziel").font(.system(size: DS.HUD.label(compact: compact), weight: .bold))
                        .foregroundStyle(Theme.text2)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(mainText)
                    .font(Theme.number(compact ? 34 : 56, weight: .bold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                Text(secondsText)
                    .font(.system(size: DS.HUD.detail(compact: compact), weight: .semibold).monospacedDigit())
                    .foregroundStyle(tint.opacity(0.9))
                    .lineLimit(1)
            }
            Text(standingText)
                .font(.system(size: DS.HUD.detail(compact: compact) - 2, weight: .semibold))
                .foregroundStyle(Theme.text2)
        }
        .padding(.horizontal, compact ? 12 : 18)
        .padding(.vertical, compact ? 8 : 12)
        .hudPanel()
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Tempo-Linie \(Format.duration(pace)) pro 500 Meter"))
        .accessibilityValue(Text(gap.standing == .level ? standingText
            : "\(mainText) \(standingText), \(secondsText)"))
    }
}

/// Dialog „Fahrt beenden“ als eigene dunkle Ansicht über dem Ruderbildschirm (statt confirmationDialog, das auf
/// dem iPad „Weiterrudern“ weglässt). Die Fahrt ist angehalten, solange er offen ist. Drei grosse Ziele:
/// „Weiterrudern“ (Standard), „Beenden und speichern“, „Verwerfen“ (destruktiv, mit Rückfrage).
struct EndRideDialog: View {
    /// Fahrt lang genug zum Speichern (mindestens 100 m und 1 min)
    let canSave: Bool
    /// schon gerudert (sonst gibt es nichts zu speichern)
    let hasStarted: Bool
    let onContinue: () -> Void
    let onSave: () -> Void
    let onDiscard: () -> Void

    @State private var confirmDiscard = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture(perform: onContinue)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Space.m) {
                (confirmDiscard ? Text("Fahrt wirklich verwerfen?") : Text("Fahrt beenden?"))
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text(message)
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                if confirmDiscard {
                    Button(role: .destructive, action: onDiscard) {
                        Label("Verwerfen", systemImage: "trash")
                    }
                    .buttonStyle(SecondaryButtonStyle(compact: false, destructive: true))
                    Button("Zurück") { confirmDiscard = false }
                        .buttonStyle(SecondaryButtonStyle(compact: false))
                } else {
                    Button(action: onContinue) {
                        Label("Weiterrudern", systemImage: "play.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle(compact: false))
                    .keyboardShortcut(.cancelAction)
                    if hasStarted {
                        Button(action: onSave) {
                            Label("Beenden und speichern", systemImage: "checkmark")
                        }
                        .buttonStyle(SecondaryButtonStyle(compact: false))
                        .disabled(!canSave)
                    }
                    Button(role: .destructive) {
                        if hasStarted { confirmDiscard = true } else { onDiscard() }
                    } label: {
                        hasStarted ? Text("Verwerfen") : Text("Schliessen")
                    }
                    .buttonStyle(SecondaryButtonStyle(compact: true, destructive: hasStarted))
                }
            }
            .padding(DS.Space.xl)
            .frame(maxWidth: 560)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).strokeBorder(Theme.cardStroke))
            .padding(DS.Space.l)
        }
        .accessibilityAddTraits(.isModal)
    }

    private var message: String {
        if confirmDiscard { return String(localized: "Die Fahrt wird nicht gespeichert, auch nicht in Apple Health.") }
        if !hasStarted { return String(localized: "Es wurde noch nicht gerudert.") }
        if !canSave {
            return String(localized: "Die Zeit ist angehalten. Fahrten unter 100 m oder 1 min werden nicht gespeichert.")
        }
        return String(localized: "Die Zeit ist angehalten. Beim Beenden wird die Fahrt bis hierher gespeichert.")
    }
}
