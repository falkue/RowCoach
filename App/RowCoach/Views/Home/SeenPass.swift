import SwiftUI
import RowCoachKit

/// Seen-Pass: je Strecke eine Kachel mit Luftbild, Name, Region, Fahrten, km und Bestzeit. Ungefahrene Strecken
/// heissen „noch offen“ – ohne Sperren, ohne Prozent-Sammelzwang (startscreen-gamification.md 3d).
struct SeenPassTile: View {
    let course: Course
    let record: TrainingStats.CourseRecord?
    /// „Heute“: Strecke des Vorschlags
    let isSuggested: Bool
    /// „Zuletzt“: Strecke der letzten Fahrt
    let isLast: Bool
    var width: CGFloat? = 250

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CourseMapPreview(course: course, coverWithImage: true, showsMarkers: false)
                .frame(height: 120)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(alignment: .topLeading) { badge.padding(10) }
            VStack(alignment: .leading, spacing: 4) {
                Text(HomeFormat.courseShort(course.title))
                    .font(.headline)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(course.regionText)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer().frame(height: 4)
                Text(DSFormat.courseLength(course))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.text2)
                if let r = record, r.rides > 0 {
                    // Summe aller Fahrten klar beschriftet („2 Fahrten · 20 km gesamt“)
                    Text(r.rides == 1 ? String(localized: "1 Fahrt · \(DSFormat.kmShort(r.distance)) gesamt")
                         : String(localized: "\(r.rides) Fahrten · \(DSFormat.kmShort(r.distance)) gesamt"))
                        .font(.subheadline.weight(.medium).monospacedDigit())
                    Text(r.bestTime.map { String(localized: "Bestzeit \(Format.duration($0))") }
                         ?? String(localized: "noch keine ganze Strecke"))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(Theme.text2)
                } else {
                    Text("noch offen")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.link)
                    Text(verbatim: " ").font(.footnote)   // gleiche Höhe wie Kacheln mit Bestzeit
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(isSuggested ? Theme.evening : Theme.cardStroke, lineWidth: isSuggested ? 2.5 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Strecke wählen")
    }

    @ViewBuilder
    private var badge: some View {
        if isSuggested {
            BadgeText(text: String(localized: "Heute"), fill: Theme.evening, foreground: Theme.onAccent)
        } else if isLast {
            BadgeText(text: String(localized: "Zuletzt"), fill: Color.black.opacity(0.65), foreground: .white)
        }
    }
}

private struct BadgeText: View {
    let text: String
    let fill: Color
    let foreground: Color

    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(fill, in: Capsule())
    }
}
