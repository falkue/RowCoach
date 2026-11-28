import SwiftUI
import RowCoachKit

/// Zahleneingabe per Drehrad statt Zifferntastatur (Falk 28.11.2026: Gewicht über die Tastatur ging schlecht).
///
/// Die Zeile zeigt den Wert (Markenfarbe `Theme.link`); Antippen öffnet ein kleines Popover mit Drehrad – auf dem
/// iPad an der Zeile, auf dem iPhone ebenfalls als Popover (`presentationCompactAdaptation`), nie als grosse Fläche.
/// Für feste Spannen: Puls, Gewicht, Geburtsjahr, Watt. Zeiten (Minuten : Sekunden) mit `MinuteSecondWheel`.
struct WheelValueRow: View {
    let label: Text
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    /// Nachkommastellen der Anzeige (0 bei ganzen Schritten)
    let decimals: Int

    @State private var open = false

    init(label: Text, value: Binding<Double>, range: ClosedRange<Double>, step: Double, unit: String,
         decimals: Int = 0) {
        self.label = label
        self._value = value
        self.range = range
        self.step = step
        self.unit = unit
        self.decimals = decimals
    }

    private var values: [Double] {
        let n = Int(((range.upperBound - range.lowerBound) / step).rounded())
        return (0...max(n, 0)).map { range.lowerBound + Double($0) * step }
    }

    /// nächster Wert auf dem Raster (auch für Werte ausserhalb der Spanne)
    private var snapped: Double {
        let v = min(max(value, range.lowerBound), range.upperBound)
        return range.lowerBound + ((v - range.lowerBound) / step).rounded() * step
    }

    private func text(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(decimals)).grouping(.never))
    }

    var body: some View {
        WheelRowChrome(label: label, valueText: text(snapped), unit: unit, open: $open) {
            Picker(selection: Binding(get: { snapped }, set: { value = $0 })) {
                ForEach(values, id: \.self) { v in
                    Text(unit.isEmpty ? text(v) : "\(text(v)) \(unit)").monospacedDigit().tag(v)
                }
            } label: { label }
            .pickerStyle(.wheel)
        }
    }
}

/// Wie `WheelValueRow` für ganze Zahlen; optional (`Int?`): leer zeigt „–“, das Drehrad beginnt bei `fallback`,
/// „Leeren“ setzt den Wert zurück.
struct WheelIntRow: View {
    let label: Text
    @Binding var value: Int?
    let range: ClosedRange<Int>
    let step: Int
    let unit: String
    /// Startwert im Drehrad, solange kein Wert gesetzt ist
    let fallback: Int
    /// „Leeren“ anbieten (nur optionale Werte)
    let clearable: Bool

    @State private var open = false

    init(label: Text, value: Binding<Int?>, range: ClosedRange<Int>, step: Int = 1, unit: String, fallback: Int,
         clearable: Bool = true) {
        self.label = label
        self._value = value
        self.range = range
        self.step = max(step, 1)
        self.unit = unit
        self.fallback = fallback
        self.clearable = clearable
    }

    private var current: Int {
        let v = min(max(value ?? fallback, range.lowerBound), range.upperBound)
        return range.lowerBound + ((v - range.lowerBound) / step) * step
    }

    var body: some View {
        WheelRowChrome(label: label, valueText: value.map { String($0) } ?? "–", unit: value == nil ? "" : unit,
                       open: $open, onClear: clearable && value != nil ? { value = nil } : nil) {
            Picker(selection: Binding(get: { current }, set: { value = $0 })) {
                ForEach(Array(stride(from: range.lowerBound, through: range.upperBound, by: step)), id: \.self) { v in
                    Text(unit.isEmpty ? String(v) : "\(v) \(unit)").monospacedDigit().tag(v)
                }
            } label: { label }
            .pickerStyle(.wheel)
        }
        .onChange(of: open) { _, isOpen in
            // Öffnen ohne Wert übernimmt den Startwert, damit das Drehrad sofort gilt
            if isOpen, value == nil { value = current }
        }
    }
}

extension WheelIntRow {
    /// nicht optionale Ganzzahl (z. B. @AppStorage)
    init(label: Text, value: Binding<Int>, range: ClosedRange<Int>, step: Int = 1, unit: String) {
        self.init(label: label, value: Binding<Int?>(get: { value.wrappedValue }, set: { if let v = $0 { value.wrappedValue = v } }),
                  range: range, step: step, unit: unit, fallback: value.wrappedValue, clearable: false)
    }
}

/// Minuten : Sekunden als zweispaltiges Drehrad, auf `range` begrenzt
struct MinuteSecondWheel: View {
    @Binding var seconds: Double
    let range: ClosedRange<Double>

    private var total: Int { Int(min(max(seconds, range.lowerBound), range.upperBound).rounded()) }

    private func set(minutes: Int? = nil, secs: Int? = nil) {
        let v = Double((minutes ?? total / 60) * 60 + (secs ?? total % 60))
        seconds = min(max(v, range.lowerBound), range.upperBound)
    }

    var body: some View {
        HStack(spacing: 0) {
            Picker(selection: Binding(get: { total / 60 }, set: { set(minutes: $0) })) {
                ForEach(Int(range.lowerBound) / 60...Int(range.upperBound) / 60, id: \.self) { Text("\($0) min").tag($0) }
            } label: { Text("Minuten") }
            Picker(selection: Binding(get: { total % 60 }, set: { set(secs: $0) })) {
                ForEach(0..<60, id: \.self) { Text(String(format: "%02d s", $0)).tag($0) }
            } label: { Text("Sekunden") }
        }
        .pickerStyle(.wheel)
        .accessibilityElement(children: .contain)
    }
}

/// Gemeinsame Zeile: Bezeichnung links, Wert rechts als Schaltfläche, Popover mit Drehrad und „Fertig“
private struct WheelRowChrome<Wheel: View>: View {
    let label: Text
    let valueText: String
    let unit: String
    @Binding var open: Bool
    var onClear: (() -> Void)?
    @ViewBuilder let wheel: () -> Wheel

    var body: some View {
        Button {
            open = true
        } label: {
            LabeledContent {
                HStack(spacing: 4) {
                    Text(verbatim: valueText).monospacedDigit().foregroundStyle(Theme.link)
                    if !unit.isEmpty { Text(verbatim: unit).foregroundStyle(Theme.text2) }
                }
            } label: {
                label.foregroundStyle(Theme.text)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(Text(verbatim: unit.isEmpty ? valueText : "\(valueText) \(unit)"))
        .accessibilityHint(Text("Auswahlrad öffnen"))
        .popover(isPresented: $open, arrowEdge: .trailing) {
            VStack(spacing: 0) {
                HStack {
                    label.font(.headline).foregroundStyle(Theme.text)
                    Spacer()
                    if let onClear {
                        Button("Leeren") {
                            onClear()
                            open = false
                        }
                        .foregroundStyle(Theme.link)
                    }
                    Button("Fertig") { open = false }
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.link)
                }
                .padding(.horizontal, DS.Space.m)
                .padding(.top, DS.Space.m)
                wheel()
                    .frame(height: 180)
                    .padding(.horizontal, DS.Space.s)
            }
            .frame(width: 300)
            .padding(.bottom, DS.Space.s)
            .background(Theme.card)
            .preferredColorScheme(.dark)
            .presentationCompactAdaptation(.popover)
        }
    }
}
