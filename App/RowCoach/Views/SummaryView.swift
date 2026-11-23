import SwiftUI
import Charts
import RowCoachKit

/// Zusammenfassung eines Trainings: Werte, Pulsverlauf (Swift Charts), Zonen, Splits, Apple-Health-Status.
/// Wird nach dem Ziel und in der Verlaufsansicht verwendet.
struct SummaryView: View {
    enum HealthState { case pending, saved, notSaved }

    let record: WorkoutRecord
    var health: HealthState
    var healthNote: String? = nil

    @AppStorage("profile.maxHR") private var maxHR = 185
    @AppStorage("profile.restHR") private var restHR = 55

    private var zones: HeartRateZones { HeartRateZones(maxHR: maxHR, restHR: restHR) }
    private var summary: WorkoutSummary { record.summary }
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    init(record: WorkoutRecord, health: HealthState, healthNote: String? = nil) {
        self.record = record
        self.health = health
        self.healthNote = healthNote
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                healthRow
                LazyVGrid(columns: columns, spacing: 12) {
                    value("Zeit", Format.duration(summary.activeDuration))
                    value("Distanz", Format.distance(summary.distance))
                    value("Ø Tempo", Format.pace(summary.averagePace), unit: "/500 m")
                    value("Ø Schlagzahl", summary.averageStrokeRate > 0 ? String(format: "%.1f", summary.averageStrokeRate) : "–",
                          unit: "/min")
                    value("Ø Leistung", summary.averagePower > 0 ? "\(summary.averagePower)" : "–", unit: "W")
                    value("Ø Puls", summary.averageHeartRate.map { "\($0)" } ?? "–", unit: "bpm",
                          detail: summary.maxHeartRate.map { "max. \($0)" })
                    value("Kalorien", "\(summary.calories)", unit: "kcal")
                    value("Schläge", "\(summary.strokeCount)",
                          detail: summary.pauseCount > 0 ? "\(summary.pauseCount) Pause(n)" : nil)
                }
                heartRateSection
                splitsSection
            }
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(record.header.courseTitle ?? "Training")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Kopf

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.isInterrupted ? "Fahrt unterbrochen" : summary.completedCourse ? "Ziel erreicht" : "Vorzeitig beendet")
                .font(.largeTitle.bold())
            HStack(spacing: 8) {
                Text(record.header.startDate.formatted(date: .complete, time: .shortened))
                if record.header.device.source == .simulator {
                    Text("Simulator").font(.caption.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.purple.opacity(0.7)))
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var healthRow: some View {
        switch health {
        case .pending:
            HStack(spacing: 8) {
                ProgressView()
                Text("Speichere in Apple Health …")
            }
            .foregroundStyle(.secondary)
        case .saved:
            Label("In Apple Health gespeichert", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.headline)
        case .notSaved:
            VStack(alignment: .leading, spacing: 2) {
                Label("Nicht in Apple Health gespeichert", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.orange)
                    .font(.headline)
                if let healthNote {
                    Text(healthNote).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func value(_ title: String, _ value: String, unit: String? = nil, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(Theme.number(30)).lineLimit(1).minimumScaleFactor(0.6)
                if let unit { Text(unit).font(.footnote).foregroundStyle(.secondary) }
            }
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .hudPanel(cornerRadius: 12)
    }

    // MARK: Puls

    private struct HRPoint: Identifiable {
        let id: Int
        let minute: Double
        let bpm: Int
    }

    private var hrPoints: [HRPoint] {
        record.samples.enumerated().compactMap { i, s in
            s.heartRate.map { HRPoint(id: i, minute: s.time / 60, bpm: $0) }
        }
    }

    @ViewBuilder
    private var heartRateSection: some View {
        let points = hrPoints
        if !points.isEmpty {
            let lo = max((points.map(\.bpm).min() ?? 60) - 10, 30)
            let hi = (points.map(\.bpm).max() ?? 180) + 10
            VStack(alignment: .leading, spacing: 10) {
                Text("Pulsverlauf").font(.title3.bold())
                Chart {
                    ForEach(1...HeartRateZones.count, id: \.self) { z in
                        let bound = zones.lowerBound(zone: z)
                        if bound > lo && bound < hi {
                            RuleMark(y: .value("Zone \(z)", bound))
                                .foregroundStyle(Theme.zoneColor(z).opacity(0.5))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        }
                    }
                    ForEach(points) { p in
                        LineMark(x: .value("Minute", p.minute), y: .value("Puls", p.bpm))
                            .foregroundStyle(Color.red)
                            .interpolationMethod(.monotone)
                    }
                }
                .chartYScale(domain: lo...hi)
                .chartXAxisLabel("Minuten")
                .chartYAxisLabel("bpm")
                .frame(height: 220)
                zoneBar
            }
            .padding()
            .hudPanel(cornerRadius: 12)
        }
    }

    @ViewBuilder
    private var zoneBar: some View {
        if let secs = summary.heartRateZoneSeconds, secs.reduce(0, +) > 0 {
            let total = secs.reduce(0, +)
            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geo in
                    HStack(spacing: 1) {
                        ForEach(Array(secs.enumerated()), id: \.offset) { z, s in
                            if s > 0 {
                                Rectangle().fill(Theme.zoneColor(z))
                                    .frame(width: max(geo.size.width * s / total - 1, 1))
                            }
                        }
                    }
                }
                .frame(height: 14)
                .clipShape(Capsule())
                HStack(spacing: 12) {
                    ForEach(Array(secs.enumerated()), id: \.offset) { z, s in
                        if s > 0 {
                            HStack(spacing: 4) {
                                Circle().fill(Theme.zoneColor(z)).frame(width: 8, height: 8)
                                Text("\(z == 0 ? "<1" : "Z\(z)") \(Format.duration(s))")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Splits

    @ViewBuilder
    private var splitsSection: some View {
        if !record.splits.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Splits").font(.title3.bold())
                Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        Text("Strecke").gridColumnAlignment(.leading)
                        Text("Zeit")
                        Text("/500 m")
                        Text("SPM")
                        Text("Watt")
                        Text("Puls")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    Divider()
                    ForEach(record.splits) { s in
                        GridRow {
                            Text(Format.distance(s.endDistance))
                            Text(Format.duration(s.duration, tenths: true))
                            Text(Format.pace(s.pace))
                            Text(s.averageStrokeRate > 0 ? String(format: "%.0f", s.averageStrokeRate) : "–")
                            Text(s.averagePower > 0 ? "\(s.averagePower)" : "–")
                            Text(s.averageHeartRate.map { "\($0)" } ?? "–")
                        }
                        .font(.body.monospacedDigit())
                    }
                }
            }
            .padding()
            .hudPanel(cornerRadius: 12)
        }
    }
}
