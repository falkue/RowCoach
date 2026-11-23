import SwiftUI
import SwiftData
import RowCoachKit

/// Verlauf: frühere Trainings nach Datum (neueste zuerst), nach Monat gruppiert, mit Details.
struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \StoredWorkout.startDate, order: .reverse) private var workouts: [StoredWorkout]
    @Environment(WorkoutRecovery.self) private var recovery

    init() {}

    var body: some View {
        NavigationStack {
            Group {
                if workouts.isEmpty {
                    ContentUnavailableView("Noch keine Trainings", systemImage: "figure.rower",
                                           description: Text("Nach jeder Fahrt erscheint hier ein Eintrag."))
                } else {
                    List {
                        if let notice = recovery.notice {
                            Section {
                                RecoveryNoticeRow(text: notice) { recovery.notice = nil }
                            }
                        }
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
                    if item.interrupted {
                        Image(systemName: "bolt.slash").accessibilityLabel("Unterbrochen")
                    } else if !item.completedCourse {
                        Image(systemName: "flag.slash").accessibilityLabel("Vorzeitig beendet")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

/// Hinweis nach einer wiederhergestellten Fahrt (Verlauf und Startseite)
struct RecoveryNoticeRow: View {
    let text: String
    let onClose: () -> Void

    init(text: String, onClose: @escaping () -> Void) {
        self.text = text
        self.onClose = onClose
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "bolt.slash").foregroundStyle(.orange)
            Text(text).font(.subheadline)
            Spacer(minLength: 8)
            Button(action: onClose) {
                Image(systemName: "xmark").font(.caption.bold())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Hinweis schliessen")
        }
    }
}

private struct HistoryDetailView: View {
    let item: StoredWorkout

    @Environment(HealthService.self) private var health
    @Environment(WorkoutRecovery.self) private var recovery
    @State private var busy = false
    @State private var resultText: String?
    @State private var confirmSimulator = false

    var body: some View {
        if let record = item.record {
            SummaryView(record: record, health: item.savedToHealth ? .saved : .notSaved)
                .safeAreaInset(edge: .bottom) { healthBar }
                .confirmationDialog("Simulator-Training in Apple Health speichern?", isPresented: $confirmSimulator,
                                    titleVisibility: .visible) {
                    Button("Trotzdem speichern") { save() }
                    Button("Abbrechen", role: .cancel) {}
                } message: {
                    Text("Dieses Training stammt vom Simulator, nicht vom Rudergerät.")
                }
        } else {
            ContentUnavailableView("Daten nicht lesbar", systemImage: "exclamationmark.triangle",
                                   description: Text("Dieses Training kann nicht angezeigt werden."))
        }
    }

    @ViewBuilder
    private var healthBar: some View {
        if health.status != .unavailable {
            VStack(spacing: 6) {
                Button {
                    if item.simulated { confirmSimulator = true } else { save() }
                } label: {
                    HStack(spacing: 8) {
                        if busy { ProgressView() } else { Image(systemName: "heart.text.square") }
                        Text(item.savedToHealth ? "Erneut prüfen und nachtragen" : "In Apple Health speichern")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(busy)
                if let resultText {
                    Text(resultText).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    private func save() {
        guard !busy else { return }
        busy = true
        resultText = nil
        Task {
            if health.status != .authorized { await health.connect() }
            let result = await recovery.saveToHealth(item)
            resultText = result.message
            busy = false
        }
    }
}
