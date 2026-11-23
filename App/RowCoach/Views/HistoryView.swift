import SwiftUI
import SwiftData
import RowCoachKit

/// Verlauf: frühere Trainings nach Datum (neueste zuerst), nach Monat gruppiert, mit Details.
struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \StoredWorkout.startDate, order: .reverse) private var workouts: [StoredWorkout]

    init() {}

    var body: some View {
        NavigationStack {
            Group {
                if workouts.isEmpty {
                    ContentUnavailableView("Noch keine Trainings", systemImage: "figure.rower",
                                           description: Text("Nach jeder Fahrt erscheint hier ein Eintrag."))
                } else {
                    List {
                        ForEach(monthGroups, id: \.title) { group in
                            Section(group.title) {
                                ForEach(group.items) { w in
                                    NavigationLink {
                                        HistoryDetailView(item: w)
                                    } label: {
                                        HistoryRow(item: w)
                                    }
                                }
                                .onDelete { offsets in delete(offsets, in: group.items) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Verlauf")
        }
    }

    private struct MonthGroup {
        let title: String
        let items: [StoredWorkout]
    }

    /// Gruppen in der Reihenfolge der Abfrage (neueste zuerst)
    private var monthGroups: [MonthGroup] {
        var groups: [MonthGroup] = []
        for w in workouts {
            let title = w.startDate.formatted(.dateTime.month(.wide).year())
            if let last = groups.last, last.title == title {
                groups[groups.count - 1] = MonthGroup(title: title, items: last.items + [w])
            } else {
                groups.append(MonthGroup(title: title, items: [w]))
            }
        }
        return groups
    }

    private func delete(_ offsets: IndexSet, in items: [StoredWorkout]) {
        for i in offsets { context.delete(items[i]) }
        try? context.save()
    }
}

private struct HistoryRow: View {
    let item: StoredWorkout

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.courseTitle ?? "Training").font(.headline)
                Text(item.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Format.distance(item.distance)) · \(Format.duration(item.duration))")
                    .font(.subheadline.monospacedDigit())
                HStack(spacing: 6) {
                    Text("\(Format.pace(item.averagePace)) /500 m").monospacedDigit()
                    if item.simulated { Image(systemName: "desktopcomputer").accessibilityLabel("Simulator") }
                    if item.savedToHealth {
                        Image(systemName: "heart.fill").foregroundStyle(.red).accessibilityLabel("In Apple Health")
                    }
                    if !item.completedCourse {
                        Image(systemName: "flag.slash").accessibilityLabel("Vorzeitig beendet")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct HistoryDetailView: View {
    let item: StoredWorkout

    var body: some View {
        if let record = item.record {
            SummaryView(record: record, health: item.savedToHealth ? .saved : .notSaved)
        } else {
            ContentUnavailableView("Daten nicht lesbar", systemImage: "exclamationmark.triangle",
                                   description: Text("Dieses Training kann nicht angezeigt werden."))
        }
    }
}
