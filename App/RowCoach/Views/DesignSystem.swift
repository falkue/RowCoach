import SwiftUI
import RowCoachKit

// Gestaltungssystem von RowCoach (UX-Überarbeitung, docs/design/ux-synthese.md).
//
// Grundsätze
// - Durchgehend dunkel; das Farbschema wird an der Wurzel erzwungen (RootView), nicht je Karte.
// - Farben nur über `Theme` (Tokens). Abendorange `Theme.accent` nur für die Hauptaktion einer Ansicht.
// - Am Ruderer feste, grosse Schriftstufen (`DS.HUD`); auf Lesebildschirmen Textstile mit Dynamic Type.
// - 8-pt-Raster (`DS.Space`), Eckradien `DS.Radius`, Tastflächen mindestens 64 pt, Hauptaktion 88 pt (iPad).
//
// Glossar (überall gleich; neue Texte so schreiben, dass sie lokalisierbar sind: `Text("…")`,
// `String(localized:)`, ganze Sätze statt Fragmenten, Zahlen und Einheiten über FormatStyle bzw. Measurement):
// - „Tempo /500 m“ (nicht Pace), Ziel relativ: „2000-m-Tempo + 3 s“ (nicht 2k)
// - „Schlagzahl /min“ (nicht SPM; in Tabellen kurz „SZ“)
// - „Leistung“ mit Einheit „W“
// - „Intervall“ und „Pause“ für Phasen (nicht „Belastung“); dazu „Einrudern“, „Ausrudern“
// - „Anstrengung“ (1–10, wie Apple Health) für die Abfrage nach der Fahrt
// - „Split“ nur für 500-m-Abschnitte; „2000 m“ statt „2k“
// - Phasenleiste nach Härte: leicht (blau), mittel (grün), hart (orange), Pause (grau)

enum DS {
    /// Abstände im 8-pt-Raster
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
        /// Seitenrand: iPad 32, iPhone 16
        static func margin(compact: Bool) -> CGFloat { compact ? 16 : 32 }
    }

    /// Eckradien
    enum Radius {
        static let card: CGFloat = 24
        static let tile: CGFloat = 18
        static let chip: CGFloat = 12
    }

    /// Mindesthöhen von Tasten
    enum Touch {
        static let minimum: CGFloat = 64
        static let primaryLarge: CGFloat = 88
        static let primaryCompact: CGFloat = 64
    }

    /// Schriftstufen am Ruderer (feste Grössen; Ziffern fest breit)
    enum HUD {
        /// Hauptwert: Tempo, im Training zusätzlich die Restzeit der Phase
        static func main(compact: Bool) -> CGFloat { compact ? 64 : 120 }
        /// Kachelwert (Schlagzahl, Puls, Leistung)
        static func tile(compact: Bool) -> CGFloat { compact ? 40 : 72 }
        /// Kopfleiste (Zeit, Distanz, Rest)
        static func top(compact: Bool) -> CGFloat { compact ? 26 : 44 }
        /// Beschriftung (Versalien); Untergrenze am Ruderer 16 pt
        static func label(compact: Bool) -> CGFloat { compact ? 13 : 16 }
        /// Nebentext (Ziel, Zone)
        static func detail(compact: Bool) -> CGFloat { compact ? 15 : 22 }
    }
}

// MARK: - Karte

/// Karte: `Theme.card`, Radius 24, feiner Rand
struct DSCard: ViewModifier {
    var padding: CGFloat = DS.Space.l
    var cornerRadius: CGFloat = DS.Radius.card
    var fillsHeight = false

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Theme.cardStroke))
    }
}

extension View {
    func dsCard(padding: CGFloat = DS.Space.l, cornerRadius: CGFloat = DS.Radius.card,
                fillsHeight: Bool = false) -> some View {
        modifier(DSCard(padding: padding, cornerRadius: cornerRadius, fillsHeight: fillsHeight))
    }

    /// Seitengrund der App
    func dsPageBackground() -> some View {
        background(Theme.bg.ignoresSafeArea())
    }

    /// Beschriftung über Werten: Versalien, gesperrt, `text2`
    func dsLabelStyle() -> some View {
        font(.caption.weight(.bold)).textCase(.uppercase).tracking(1.2).foregroundStyle(Theme.text2)
    }
}

// MARK: - Tasten

/// Haupttaste: Kapsel in Abendorange, dunkler Text. Eine je Ansicht.
struct PrimaryButtonStyle: ButtonStyle {
    var compact = false
    var fullWidth = true

    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonBody(configuration: configuration, compact: compact, fullWidth: fullWidth)
    }

    private struct PrimaryButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let compact: Bool
        let fullWidth: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(compact ? .title3.weight(.bold) : .title2.weight(.bold))
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, DS.Space.l)
                .frame(maxWidth: fullWidth ? .infinity : nil,
                       minHeight: compact ? DS.Touch.minimum : DS.Touch.primaryLarge)
                .background(Theme.accent.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.35),
                            in: Capsule())
                .contentShape(Capsule())
        }
    }
}

/// Nebentaste: Kapsel mit Kartenfläche, weisser Text, feiner Rand
struct SecondaryButtonStyle: ButtonStyle {
    var compact = true
    var fullWidth = true
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        SecondaryButtonBody(configuration: configuration, compact: compact, fullWidth: fullWidth,
                            destructive: destructive)
    }

    private struct SecondaryButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let compact: Bool
        let fullWidth: Bool
        let destructive: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(compact ? .title3.weight(.semibold) : .title2.weight(.semibold))
                .foregroundStyle(destructive ? Theme.bad : Theme.text)
                .opacity(isEnabled ? 1 : 0.4)
                .padding(.horizontal, DS.Space.l)
                .frame(maxWidth: fullWidth ? .infinity : nil,
                       minHeight: compact ? DS.Touch.minimum : DS.Touch.primaryLarge)
                .background(Color.white.opacity(configuration.isPressed ? 0.16 : 0.08), in: Capsule())
                .overlay(Capsule().strokeBorder(destructive ? Theme.bad.opacity(0.6) : Color.white.opacity(0.22)))
                .contentShape(Capsule())
        }
    }
}

// MARK: - Kennzahl-Kachel (Lesebildschirme)

/// Kennzahl-Kachel für Lesebildschirme: Beschriftung oben, Wert mit kleiner Einheit, optional Nebentext.
/// Skaliert mit Dynamic Type.
struct MetricTile: View {
    let title: String
    let value: String
    var unit: String? = nil
    var detail: String? = nil

    init(_ title: String, value: String, unit: String? = nil, detail: String? = nil) {
        self.title = title
        self.value = value
        self.unit = unit
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text(title).dsLabelStyle().lineLimit(1).minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.xs) {
                Text(value).font(.title.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                if let unit { Text(unit).font(.footnote).foregroundStyle(Theme.text2) }
            }
            Text(detail ?? " ").font(.caption).foregroundStyle(Theme.text2).lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(DS.Space.m)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous).strokeBorder(Theme.cardStroke))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Listenzeile

/// Listenzeile: Titel und Untertitel links, Wert rechts, mindestens 72 pt hoch
struct DSListRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    init(title: String, subtitle: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(Theme.text)
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(Theme.text2)
                }
            }
            Spacer(minLength: DS.Space.s)
            trailing()
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

// MARK: - Chip

/// Text-Chip für Zustände („Simulator“, „Nicht in Health“) statt rätselhafter Symbole
struct DSChip: View {
    enum Tone { case neutral, hint, ok, warn, bad }
    let text: String
    var tone: Tone = .neutral
    var systemImage: String? = nil

    init(_ text: String, tone: Tone = .neutral, systemImage: String? = nil) {
        self.text = text
        self.tone = tone
        self.systemImage = systemImage
    }

    private var color: Color {
        switch tone {
        case .neutral: return Theme.text2
        case .hint: return Theme.link
        case .ok: return Theme.ok
        case .warn: return Theme.warn
        case .bad: return Theme.bad
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.14), in: Capsule())
        .lineLimit(1)
    }
}

// MARK: - Banner

/// Banner: eine Zeile mit Symbol, Satz und optional Aktion; schliessbar
struct DSBanner: View {
    let systemImage: String
    let text: String
    var tone: DSChip.Tone = .neutral
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var onClose: (() -> Void)? = nil

    private var iconColor: Color {
        switch tone {
        case .neutral: return Theme.text2
        case .hint: return Theme.link
        case .ok: return Theme.ok
        case .warn: return Theme.warn
        case .bad: return Theme.bad
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.m) {
            Image(systemName: systemImage).foregroundStyle(iconColor).font(.body.weight(.semibold))
                .accessibilityHidden(true)
            Text(text).font(.body).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: DS.Space.s)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.link)
                    .buttonStyle(.borderless)
            }
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.footnote.weight(.bold)).foregroundStyle(Theme.text2)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Hinweis schliessen"))
            }
        }
        .padding(.horizontal, DS.Space.m)
        .padding(.vertical, 12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: DS.Radius.chip + 2, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.chip + 2, style: .continuous).strokeBorder(Theme.cardStroke))
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Leer-Zustand

/// Leer-Zustand: Symbol, ein Satz, optional eine Taste
struct DSEmptyState: View {
    let title: String
    let systemImage: String
    var text: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let text { Text(text) }
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(SecondaryButtonStyle(compact: true, fullWidth: false))
            }
        }
        .foregroundStyle(Theme.text)
    }
}

// MARK: - Sheet-Kopf

/// Sheet-Kopf: Titel, „Schliessen“ links (cancellationAction), dunkler Grund
struct DSSheetChrome: ViewModifier {
    let title: String
    let onClose: () -> Void

    func body(content: Content) -> some View {
        content
            .dsPageBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.bg, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onClose) {
                        Label("Schliessen", systemImage: "xmark")
                    }
                    .labelStyle(.titleAndIcon)
                }
            }
    }
}

extension View {
    func dsSheetChrome(_ title: String, onClose: @escaping () -> Void) -> some View {
        modifier(DSSheetChrome(title: title, onClose: onClose))
    }
}

/// Fussleiste eines Sheets bzw. einer Seite: dunkle Fläche mit feiner Linie oben
struct DSFooterBar<Content: View>: View {
    @ViewBuilder var content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        VStack(spacing: DS.Space.s) { content() }
            .padding(.horizontal, DS.Space.l)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Theme.bg.opacity(0.96))
            .overlay(alignment: .top) { Rectangle().fill(Theme.cardStroke).frame(height: 1) }
    }
}

// MARK: - Ampel mit Form

/// Ampel mit Symbol (nicht nur Farbe): im Ziel Haken, sonst Pfeil in die Richtung, in die es gehen soll
/// (nach oben = mehr: schneller bzw. höhere Schlagzahl; nach unten = weniger).
struct LightSymbol: View {
    let light: TargetLight
    /// true = Wert soll steigen (zu langsam bzw. Schlagzahl zu niedrig), false = sinken, nil = unbekannt
    var shouldIncrease: Bool? = nil
    var size: CGFloat = 18

    private var symbol: String {
        switch light {
        case .green: return "checkmark.circle.fill"
        case .yellow, .red:
            switch shouldIncrease {
            case .some(true): return "arrow.up.circle.fill"
            case .some(false): return "arrow.down.circle.fill"
            case .none: return "exclamationmark.circle.fill"
            }
        case .none: return "circle.dashed"
        }
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(Theme.lightColor(light))
            .accessibilityLabel(Text(Self.name(light, shouldIncrease: shouldIncrease)))
    }

    static func name(_ light: TargetLight, shouldIncrease: Bool? = nil) -> String {
        switch light {
        case .green: return String(localized: "im Ziel")
        case .yellow:
            if shouldIncrease == true { return String(localized: "knapp darunter") }
            if shouldIncrease == false { return String(localized: "knapp darüber") }
            return String(localized: "knapp daneben")
        case .red:
            if shouldIncrease == true { return String(localized: "deutlich darunter") }
            if shouldIncrease == false { return String(localized: "deutlich darüber") }
            return String(localized: "ausserhalb des Ziels")
        case .none: return String(localized: "kein Messwert")
        }
    }

    /// Richtung beim Tempo (s/500 m): grösserer Wert = langsamer → schneller werden
    static func paceDirection(_ pace: Double, target: ClosedRange<Double>?) -> Bool? {
        guard let target, pace > 0 else { return nil }
        if pace > target.upperBound { return true }
        if pace < target.lowerBound { return false }
        return nil
    }

    /// Richtung bei Schlagzahl bzw. anderen Werten, bei denen „mehr“ = grösser ist
    static func valueDirection(_ value: Double, target: ClosedRange<Double>?) -> Bool? {
        guard let target, value > 0 else { return nil }
        if value < target.lowerBound { return true }
        if value > target.upperBound { return false }
        return nil
    }
}

// MARK: - Formate

/// Zahlen und Längen über die Systemformate (Locale.current); Tempo wie am PM5 als m:ss bzw. m:ss,z
enum DSFormat {
    /// „3,1 km“ (bis 2 Nachkommastellen, ohne überflüssige Nullen)
    static func km(_ meters: Double) -> String {
        Measurement(value: meters / 1000, unit: UnitLength.kilometers)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided,
                                    numberFormatStyle: .number.precision(.fractionLength(0...2))))
    }

    /// „24 km“ ab 10 km ohne Nachkommastelle, sonst eine
    static func kmShort(_ meters: Double) -> String {
        Measurement(value: meters / 1000, unit: UnitLength.kilometers)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided,
                                    numberFormatStyle: .number.precision(.fractionLength(meters >= 10_000 ? 0 : 1))))
    }

    /// Dezimalzahl mit einer Nachkommastelle („21,8“ bzw. „21.8“ je nach Sprache)
    static func decimal(_ v: Double, digits: Int = 1) -> String {
        v.formatted(.number.precision(.fractionLength(digits)))
    }

    /// Länge einer Strecke einheitlich in allen Ansichten: „3,1 km (2 × 1,55 km)“ bzw. „1,9 km“
    static func courseLength(_ c: Course) -> String {
        if c.isLoop { return String(localized: "\(km(c.oneWayM)) Rundkurs") }
        guard c.turns > 0 else { return String(localized: "\(km(c.oneWayM)) eine Richtung") }
        let total = km(PaceLineSettings.courseLength(c)), leg = km(c.oneWayM)
        return String(localized: "\(total) (2 × \(leg))")
    }

    /// Gesprochene Dauer („1 Minute, 58 Sekunden“)
    static func spokenDuration(_ seconds: Double) -> String {
        let s = Int(max(seconds, 0).rounded())
        return Duration.seconds(s).formatted(.units(allowed: [.minutes, .seconds], width: .wide))
    }
}

/// Sprache der App (nicht des Geräts): bestimmt Streckentexte und Ansagen. Solange es nur deutsche Texte gibt,
/// ist das Deutsch (CFBundleDevelopmentRegion de); mit dem String Catalog folgt sie der gewählten App-Sprache.
enum AppLanguage {
    static var code: String {
        let first = Bundle.main.preferredLocalizations.first ?? "de"
        return Locale(identifier: first).language.languageCode?.identifier ?? "de"
    }
}

extension LocalizedText {
    /// Text in der Sprache der App (damit Beschriftung und Streckentext nicht gemischt erscheinen)
    var appText: String { resolved(languageCode: AppLanguage.code) }
}

/// Feste Texte aus course.json, die nur deutsch vorliegen (Region, Teile der Quellenangabe): über den String
/// Catalog übersetzt (Einträge von Hand, siehe App/l10n/en_strings.py); unbekannte Texte bleiben, wie sie sind.
enum CourseText {
    static func localized(_ text: String) -> String {
        Bundle.main.localizedString(forKey: text, value: text, table: nil)
    }

    /// Quellenangabe Teil für Teil („…; …“)
    static func attribution(_ text: String) -> String {
        text.components(separatedBy: ";")
            .map { localized($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.isEmpty }
            .joined(separator: "; ")
    }
}

extension Course {
    /// Region in der Sprache der App
    var regionText: String { CourseText.localized(region) }
}
