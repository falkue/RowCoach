import RowCoachKit
import SwiftUI

/// Rennanzeige im HUD (grosse Felder, docs/MULTIPLAYER.md „Umsetzung App“): Platz „143 von 300“, Abstand zum nächsten
/// Boot vorne und hinten (m, s), Boote im Pulk um mich, die drei Führenden und eine Dichteleiste entlang der Strecke
/// (wo das Feld liegt, weisser Strich = ich). Alles aus `RaceFieldSummary`, also über alle Teilnehmenden, auch die
/// nicht gezeigten.
struct RaceFieldPanel: View {
    let frame: RaceSceneFrame
    var compact = false

    private var summary: RaceFieldSummary { frame.summary }
    private var labelSize: CGFloat { DS.HUD.label(compact: compact) }
    private var detailSize: CGFloat { DS.HUD.detail(compact: compact) }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Platz")
                    .font(.system(size: labelSize, weight: .bold))
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.text2)
                Text("\(summary.place)")
                    .font(Theme.number(compact ? 30 : 48, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text("von \(summary.total)")
                    .font(.system(size: detailSize, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.text2)
                Spacer(minLength: 8)
                if summary.packAhead + summary.packBehind > 0 {
                    Text("Pulk \(summary.packAhead + summary.packBehind)")
                        .font(.system(size: labelSize, weight: .bold).monospacedDigit())
                        .foregroundStyle(Theme.text2)
                }
            }
            HStack(spacing: compact ? 10 : 16) {
                gapLabel(summary.ahead, symbol: "arrowtriangle.up.fill")
                gapLabel(summary.behind, symbol: "arrowtriangle.down.fill")
            }
            if !summary.leaders.isEmpty {
                leaders
            }
            DensityStrip(histogram: summary.histogram, bin: summary.histogramBin, myDistance: frame.myDistance,
                         length: frame.raceLength)
                .frame(height: compact ? 8 : 12)
        }
        .padding(.horizontal, compact ? 12 : 18)
        .padding(.vertical, compact ? 8 : 12)
        .hudPanel()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Platz \(summary.place) von \(summary.total)"))
        .accessibilityValue(Text(accessibilityText))
    }

    @ViewBuilder
    private func gapLabel(_ n: RaceFieldSummary.Neighbour?, symbol: String) -> some View {
        if let n {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: labelSize - 2, weight: .bold))
                Text(gapText(n))
                    .font(.system(size: detailSize - (compact ? 1 : 4), weight: .semibold).monospacedDigit())
                    .lineLimit(1)
            }
            .foregroundStyle(Theme.text)
        }
    }

    /// Abstand: „gleichauf“ unter 1 m (in grossen Feldern häufig), unter 10 m mit Nachkommastelle
    private func gapText(_ n: RaceFieldSummary.Neighbour) -> String {
        if n.isLevel { return String(localized: "gleichauf") }
        let d = n.displayMeters
        let m = "\(DSFormat.decimal(d.value, digits: d.decimals)) m"
        guard let s = n.gapSeconds else { return m }
        return "\(m) · \(DSFormat.decimal(abs(s))) s"
    }

    /// Führende: im Hochformat nur der erste, sonst die drei ersten mit Abstand zu mir
    private var leaders: some View {
        let list = compact ? Array(summary.leaders.prefix(1)) : summary.leaders
        return VStack(alignment: .leading, spacing: 1) {
            ForEach(list, id: \.id) { l in
                HStack(spacing: 6) {
                    Text("\(l.place).")
                        .monospacedDigit()
                        .frame(minWidth: compact ? 18 : 24, alignment: .trailing)
                    Text(frame.name(l.id)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(l.finished ? String(localized: "angekommen") : "+\(Int(max(l.gapMeters, 0).rounded())) m")
                        .monospacedDigit()
                }
                .font(.system(size: labelSize, weight: .semibold))
                .foregroundStyle(Theme.text2)
            }
        }
    }

    private var accessibilityText: String {
        var parts: [String] = []
        if let a = summary.ahead { parts.append(String(localized: "vorne \(Int(abs(a.gapMeters).rounded())) Meter")) }
        if let b = summary.behind { parts.append(String(localized: "hinten \(Int(abs(b.gapMeters).rounded())) Meter")) }
        if let l = summary.leaders.first { parts.append(String(localized: "Führend: \(frame.name(l.id))")) }
        return parts.joined(separator: ", ")
    }
}

/// Dichte des Feldes entlang der Strecke (Histogramm des Planers), eigene Position als weisser Strich
private struct DensityStrip: View {
    let histogram: [Int]
    let bin: Double
    let myDistance: Double
    let length: Double?

    var body: some View {
        Canvas { ctx, size in
            guard !histogram.isEmpty else { return }
            let total = max(length ?? bin * Double(histogram.count), 1)
            let maxCount = Double(histogram.max() ?? 1)
            for (i, c) in histogram.enumerated() where c > 0 {
                let x0 = CGFloat(Double(i) * bin / total) * size.width
                let w = max(CGFloat(bin / total) * size.width, 1)
                let h = max(CGFloat(Double(c) / max(maxCount, 1)) * size.height, 1)
                ctx.fill(Path(CGRect(x: x0, y: size.height - h, width: w, height: h)),
                         with: .color(Theme.accent.opacity(0.85)))
            }
            let x = CGFloat(min(max(myDistance / total, 0), 1)) * size.width
            ctx.fill(Path(CGRect(x: x - 1, y: 0, width: 2, height: size.height)), with: .color(.white))
        }
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 2))
        .accessibilityHidden(true)
    }
}
