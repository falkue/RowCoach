import SwiftUI
import RowCoachKit

/// Grosse Messwert-Kachel im HUD
struct HUDTile: View {
    let title: String
    let value: String
    var unit: String? = nil
    var detail: String? = nil
    var tint: Color = .white
    var size: CGFloat = 52

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(Theme.secondaryText)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(Theme.number(size))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if let unit {
                    Text(unit).font(.callout.weight(.medium)).foregroundStyle(Theme.secondaryText)
                }
            }
            if let detail {
                Text(detail).font(.caption).foregroundStyle(tint.opacity(0.85))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .hudPanel()
        .accessibilityElement(children: .combine)
    }
}

/// Kleiner Wert in der oberen Leiste
struct HUDStat: View {
    let title: String
    let value: String
    var size: CGFloat = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption2.weight(.semibold)).textCase(.uppercase).foregroundStyle(Theme.secondaryText)
            Text(value).font(Theme.number(size)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
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
                    Capsule().fill(Theme.accent)
                        .frame(width: max(height, w * p), height: height)
                    if let turnAt {
                        Rectangle().fill(Color.white.opacity(0.85))
                            .frame(width: 2, height: height + 10)
                            .offset(x: w * turnAt - 1)
                    }
                    Image(systemName: "figure.rower")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(Circle().fill(Theme.accent))
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
            .font(.caption2.weight(.medium))
            .foregroundStyle(Theme.secondaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fortschritt")
        .accessibilityValue("\(Int((progress * 100).rounded())) Prozent")
    }
}
