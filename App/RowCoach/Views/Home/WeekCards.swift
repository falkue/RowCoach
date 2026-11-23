import SwiftUI
import RowCoachKit

/// Ruhige dunkle Karte des Startbildschirms
struct HomeCard: ViewModifier {
    var padding: CGFloat = 28
    var cornerRadius: CGFloat = 26
    /// Karte nimmt die ganze angebotene Höhe (rechte Spalte auf dem iPad)
    var fillsHeight = false

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(Theme.cardStroke))
    }
}

extension View {
    func homeCard(padding: CGFloat = 28, cornerRadius: CGFloat = 26, fillsHeight: Bool = false) -> some View {
        modifier(HomeCard(padding: padding, cornerRadius: cornerRadius, fillsHeight: fillsHeight))
    }
}

/// Kopf des Startbildschirms rechts: „PM5 bereit“ bzw. „PM5 nicht verbunden“ und der Puls, falls verbunden.
/// Eigene Ansicht, damit nur sie mit jedem Pulswert neu zeichnet.
struct DeviceStatusChips: View {
    var compact = false
    @Environment(DeviceManager.self) private var devices

    init(compact: Bool = false) {
        self.compact = compact
    }

    private var pm5Text: String {
        if devices.simulatorActive { return "Simulator" }
        switch devices.pm5State {
        case .connected: return compact ? "PM5" : "PM5 bereit"
        case .scanning, .connecting: return compact ? "PM5 …" : "PM5 verbindet …"
        case .idle: return compact ? "PM5 aus" : "PM5 nicht verbunden"
        }
    }

    private var pm5Ready: Bool { devices.simulatorActive || devices.pm5State == .connected }

    private var heartRate: Int? {
        guard devices.strapState == .connected || devices.simulatorActive else { return nil }
        return devices.snapshot.heartRate
    }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(pm5Ready ? Color.green : Color.white.opacity(0.35)).frame(width: 10, height: 10)
                Text(pm5Text)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: compact ? 38 : 46)
            .background(Color.white.opacity(0.08), in: Capsule())
            if let hr = heartRate {
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill").foregroundStyle(Color(red: 0.95, green: 0.30, blue: 0.40))
                    Text("\(hr)").monospacedDigit()
                }
                .padding(.horizontal, 16)
                .frame(minHeight: compact ? 38 : 46)
                .background(Color.white.opacity(0.08), in: Capsule())
                .accessibilityLabel("Puls \(hr)")
            }
        }
        .font(.system(size: compact ? 15 : 18, weight: .semibold))
        .foregroundStyle(.white)
    }
}

/// „Diese Woche“: Tage Mo–So nach Stufe, Minuten und km mit dem Schnitt der 4 Vorwochen, Wochenserie mit Joker,
/// Balken leicht/mittel/hart über 28 Tage.
struct WeekCard: View {
    let stats: TrainingStats
    var compact = false

    private static let dayNames = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]

    var body: some View {
        if compact { compactBody } else { wideBody }
    }

    private var wideBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("Diese Woche").font(.system(size: 30, weight: .semibold))
                Spacer()
                Text("KW \(stats.week.number)").font(.system(size: 18)).foregroundStyle(Theme.secondaryText)
            }
            dayDots(size: 40)
            if stats.isEmpty {
                Text("Hier siehst du deine Woche, sobald du gerudert hast.")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    if stats.week.isFreshWeek {
                        // nach dem Wochenwechsel freundlich statt „0 min“
                        Text("Neue Woche").font(.system(size: 34, weight: .bold))
                        Text(lastWeekLine).font(.system(size: 17)).foregroundStyle(.white.opacity(0.85))
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(HomeFormat.minutes(stats.week.minutes)).font(Theme.number(54, weight: .bold))
                            Text("min").font(.system(size: 22, weight: .medium)).foregroundStyle(Theme.secondaryText)
                            Spacer().frame(width: 24)
                            Text(HomeFormat.km(stats.week.distance)).font(Theme.number(26, weight: .semibold))
                        }
                    }
                    if let avg = stats.week.previousAverageMinutes {
                        Text("Ø der 4 Wochen davor: \(HomeFormat.minutes(avg)) min pro Woche")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                streakBox(size: 18)
            }
            Divider().overlay(Color.white.opacity(0.1))
            distribution(compact: false)
        }
        .homeCard()
    }

    private var compactBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Diese Woche").font(.system(size: 22, weight: .semibold))
                Spacer()
                if stats.week.isFreshWeek {
                    Text("Neue Woche · letzte: \(HomeFormat.minutes(stats.week.lastWeekMinutes)) min")
                        .font(.system(size: 17).monospacedDigit())
                        .foregroundStyle(Theme.secondaryText)
                } else if !stats.isEmpty {
                    let avg = stats.week.previousAverageMinutes.map { " · Ø \(HomeFormat.minutes($0))" } ?? ""
                    Text("\(HomeFormat.minutes(stats.week.minutes)) min\(avg)")
                        .font(.system(size: 17).monospacedDigit())
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            dayDots(size: 32)
            if stats.isEmpty {
                Text("Hier siehst du deine Woche, sobald du gerudert hast.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.secondaryText)
            } else {
                streakBox(size: 15)
            }
            distribution(compact: true)
        }
        .homeCard(padding: 18, cornerRadius: 22)
    }

    private func dayDots(size: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(stats.week.days.enumerated()), id: \.offset) { i, day in
                VStack(spacing: 8) {
                    ZStack {
                        if let level = day.level {
                            Circle().fill(Theme.levelColor(level))
                        } else {
                            Circle().stroke(Color.white.opacity(0.22), lineWidth: 2)
                        }
                        if day.isToday {
                            // heute umrandet (gestrichelt, solange noch keine Fahrt)
                            Circle()
                                .stroke(Color.white.opacity(0.9),
                                        style: StrokeStyle(lineWidth: 2.5, dash: day.level == nil ? [5, 4] : []))
                                .padding(day.level == nil ? 0 : -5)
                        }
                    }
                    .frame(width: size, height: size)
                    Text(Self.dayNames[i])
                        .font(.system(size: size > 36 ? 17 : 14, weight: day.isToday ? .bold : .regular))
                        .foregroundStyle(day.isToday ? Color.white : Theme.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(dayLabel(i, day))
            }
        }
    }

    /// „Letzte Woche: 3 Fahrten, 70 min“ (ohne Fahrt neutral „Letzte Woche: Pause“)
    private var lastWeekLine: String {
        let w = stats.week
        guard w.lastWeekSessions > 0 else { return "Letzte Woche: Pause" }
        let rides = w.lastWeekSessions == 1 ? "1 Fahrt" : "\(w.lastWeekSessions) Fahrten"
        return "Letzte Woche: \(rides), \(HomeFormat.minutes(w.lastWeekMinutes)) min"
    }

    private func dayLabel(_ i: Int, _ day: TrainingStats.Day) -> String {
        let name = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"][i]
        guard let level = day.level else { return "\(name): keine Fahrt" }
        return "\(name): \(level.title), \(HomeFormat.minutes(day.minutes)) Minuten"
    }

    /// Wochenserie ohne Schuldgefühl: nie „Serie verloren“, nur was läuft
    private func streakBox(size: CGFloat) -> some View {
        let s = stats.streak
        let main: String
        if s.weeks >= 2 {
            main = "\(s.weeks) Wochen in Folge mit \(s.goal) Fahrten"
        } else if s.weeks == 1 {
            main = s.thisWeekMet ? "Wochenziel erreicht: \(s.goal) Fahrten" : "1 Woche mit \(s.goal) Fahrten"
        } else {
            main = "Wochenziel: \(s.goal) Fahrten · diese Woche \(s.thisWeekSessions)"
        }
        let joker: String? = s.jokerUsedLastWeek ? "Joker hat letzte Woche gezählt"
            : (s.weeks > 0 ? (s.jokerAvailable ? "Joker frei" : "Joker eingesetzt") : nil)
        return HStack(spacing: 12) {
            Image(systemName: s.weeks > 0 ? "star.fill" : "star")
                .foregroundStyle(Color(red: 0.98, green: 0.80, blue: 0.25))
            VStack(alignment: .leading, spacing: 2) {
                Text(main).font(.system(size: size, weight: .semibold))
                if let joker {
                    Text(joker).font(.system(size: size - 3)).foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func distribution(compact: Bool) -> some View {
        let d = stats.distribution
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            if !compact {
                HStack(alignment: .firstTextBaseline) {
                    Text("Leicht und hart").font(.system(size: 22, weight: .semibold))
                    Spacer()
                    Text("letzte 28 Tage").font(.system(size: 16)).foregroundStyle(Theme.secondaryText)
                }
            }
            if d.isMeaningful {
                GeometryReader { g in
                    HStack(spacing: 2) {
                        Capsule().fill(Theme.levelColor(.easy)).frame(width: max(g.size.width * d.easyShare - 2, 0))
                        if d.moderateShare > 0 {
                            Rectangle().fill(Theme.levelColor(.moderate)).frame(width: max(g.size.width * d.moderateShare - 2, 2))
                        }
                        if d.hardShare > 0 {
                            Capsule().fill(Theme.levelColor(.hard)).frame(width: max(g.size.width * d.hardShare - 2, 2))
                        }
                    }
                }
                .frame(height: compact ? 10 : 16)
                .accessibilityHidden(true)
                if !compact {
                    HStack(spacing: 18) {
                        legend(.easy, d.easyShare)
                        legend(.moderate, d.moderateShare)
                        legend(.hard, d.hardShare)
                    }
                    .font(.system(size: 17, weight: .medium))
                    Text("\(d.hardSessions) von \(d.sessions) Einheiten hart · Ziel etwa 80/20")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    Text("28 Tage: \(pct(d.easyShare)) leicht · \(pct(d.hardShare)) hart")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.secondaryText)
                }
            } else {
                Text("Noch zu wenig Daten – ab \(TrainingStats.Distribution.minimumSessions) Fahrten mit Puls.")
                    .font(.system(size: compact ? 14 : 16))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func pct(_ share: Double) -> String { "\(Int((share * 100).rounded())) %" }

    private func legend(_ level: IntensityLevel, _ share: Double) -> some View {
        HStack(spacing: 6) {
            Circle().fill(Theme.levelColor(level)).frame(width: 10, height: 10)
            Text("\(pct(share)) \(level.title)")
        }
    }
}

/// „Letzte Fahrt“: Mini-Luftbild, Datum relativ, Strecke, Distanz, Zeit, Tempo, Ø Puls, Bestzeit-Hinweis
struct LastRideCard: View {
    let stats: TrainingStats
    let course: Course?
    var compact = false

    var body: some View {
        if let last = stats.lastRide {
            if compact { compactRow(last) } else { wide(last) }
        } else {
            empty
        }
    }

    private func routeLine(_ s: TrainingSession) -> String {
        let place = s.courseTitle.map(HomeFormat.courseShort) ?? "Strecke"
        let kind = s.planId.flatMap { PlanLibrary.plan(id: $0)?.shortName } ?? s.planName ?? "frei"
        return "\(place) · \(kind)"
    }

    private var thumbnail: some View {
        Group {
            if let course {
                CourseMapPreview(course: course, showsMarkers: false)
            } else {
                Theme.background
            }
        }
    }

    private func wide(_ last: TrainingStats.LastRide) -> some View {
        let s = last.session
        return VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 18) {
                thumbnail
                    .frame(width: 130, height: 130)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    Text("LETZTE FAHRT")
                        .font(.system(size: 14, weight: .bold)).tracking(2)
                        .foregroundStyle(Theme.secondaryText)
                    Text(HomeFormat.relativeDate(s.start, now: stats.now))
                        .font(.system(size: 28, weight: .bold))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(routeLine(s))
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(2)
                }
            }
            // Zahlen nie abschneiden: vier nebeneinander, sonst zwei mal zwei
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 18) { metrics(s) }
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                    let m = metricItems(s)
                    GridRow { metricView(m[0]); metricView(m[1]) }
                    if m.count > 2 {
                        GridRow {
                            metricView(m[2])
                            if m.count > 3 { metricView(m[3]) } else { Color.clear.frame(width: 1, height: 1) }
                        }
                    }
                }
            }
            if last.isCourseBest {
                bestLine(last, size: 17)
            }
        }
        .homeCard(fillsHeight: true)
        .accessibilityElement(children: .combine)
    }

    private func compactRow(_ last: TrainingStats.LastRide) -> some View {
        let s = last.session
        let hr = s.averageHeartRate.map { " · Ø \($0)" } ?? ""
        return HStack(spacing: 14) {
            thumbnail
                .frame(width: 70, height: 70)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text("\(HomeFormat.relativeDate(s.start, now: stats.now)) · \(s.courseTitle.map(HomeFormat.courseShort) ?? "Fahrt")")
                    .font(.system(size: 17, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(Format.distance(s.distance)) · \(Format.duration(s.activeDuration)) · \(Format.duration(s.displayPace)) /500 m\(hr)")
                    .font(.system(size: 15).monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if last.isCourseBest { bestLine(last, size: 14) }
            }
            Spacer(minLength: 0)
        }
        .homeCard(padding: 14, cornerRadius: 22)
        .accessibilityElement(children: .combine)
    }

    private func bestLine(_ last: TrainingStats.LastRide, size: CGFloat) -> some View {
        let faster = last.improvement.map { ", \(Int($0.rounded())) s schneller" } ?? ""
        return Label {
            Text("Bestzeit auf dieser Strecke\(faster)")
        } icon: {
            Image(systemName: "star.fill").foregroundStyle(Color(red: 0.98, green: 0.80, blue: 0.25))
        }
        .font(.system(size: size, weight: .medium))
    }

    private struct MetricItem {
        let value: String
        let unit: String?
        let label: String
    }

    private func metricItems(_ s: TrainingSession) -> [MetricItem] {
        let dist = s.distance >= 10_000
            ? MetricItem(value: Format.distance(s.distance), unit: nil, label: "Distanz")
            : MetricItem(value: String(format: "%.0f", s.distance), unit: "m", label: "Distanz")
        var items = [dist,
                     MetricItem(value: Format.duration(s.activeDuration), unit: nil, label: "Zeit"),
                     // Einheit in der Beschriftung, damit die Zahl Platz hat
                     MetricItem(value: Format.duration(s.displayPace), unit: nil,
                                label: s.workPace == nil ? "Tempo /500 m" : "Belastung /500 m")]
        if let hr = s.averageHeartRate {
            items.append(MetricItem(value: "\(hr)", unit: nil, label: "Ø Puls"))
        }
        return items
    }

    @ViewBuilder
    private func metrics(_ s: TrainingSession) -> some View {
        ForEach(Array(metricItems(s).enumerated()), id: \.offset) { _, m in metricView(m) }
    }

    private func metricView(_ m: MetricItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(m.value).font(Theme.number(28, weight: .bold)).lineLimit(1).fixedSize()
                if let unit = m.unit {
                    Text(unit).font(.system(size: 13)).foregroundStyle(Theme.secondaryText).fixedSize()
                }
            }
            Text(m.label).font(.system(size: 14)).foregroundStyle(Theme.secondaryText).lineLimit(1).fixedSize()
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LETZTE FAHRT")
                .font(.system(size: compact ? 12 : 14, weight: .bold)).tracking(2)
                .foregroundStyle(Theme.secondaryText)
            Text("Noch keine Fahrt")
                .font(.system(size: compact ? 20 : 26, weight: .bold))
            Text("Nach der ersten Fahrt steht sie hier, mit Zeit, Tempo und Puls.")
                .font(.system(size: compact ? 14 : 16))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .homeCard(padding: compact ? 16 : 28, cornerRadius: compact ? 22 : 26, fillsHeight: !compact)
    }
}
