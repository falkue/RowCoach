import Foundation
import SwiftData
import RowCoachKit

/// Schreibt Trainings in den SwiftData-Verlauf. Nutzt den Hauptkontext, damit `@Query` in der
/// Verlaufsansicht neue Einträge sofort zeigt.
@MainActor
final class WorkoutStore {
    let container: ModelContainer
    private(set) var lastError: String?

    init(container: ModelContainer) {
        self.container = container
    }

    /// Container für die App; fällt bei einem Fehler auf einen Speicher nur im Arbeitsspeicher zurück.
    static func makeContainer() -> ModelContainer {
        // SwiftData legt den Store unter Application Support an; beim allerersten Start fehlt der Ordner noch.
        if let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        do {
            return try ModelContainer(for: StoredWorkout.self)
        } catch {
            // TODO: Fehler anzeigen; ohne Container kann die App nichts speichern
            let memory = ModelConfiguration(isStoredInMemoryOnly: true)
            return try! ModelContainer(for: StoredWorkout.self, configurations: memory)
        }
    }

    private var context: ModelContext { container.mainContext }

    @discardableResult
    func save(_ record: WorkoutRecord) -> StoredWorkout {
        let item = StoredWorkout(record: record)
        context.insert(item)
        persist()
        return item
    }

    /// Training mit dieser ID im Verlauf (z. B. schon gespeichert, bevor der Sicherungspunkt gelöscht war)
    func item(id: UUID) -> StoredWorkout? {
        var descriptor = FetchDescriptor<StoredWorkout>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// Trainings seit `date` (neueste zuerst)
    func items(since date: Date) -> [StoredWorkout] {
        let descriptor = FetchDescriptor<StoredWorkout>(predicate: #Predicate { $0.startDate >= date },
                                                        sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func markSavedToHealth(_ item: StoredWorkout, _ saved: Bool) {
        item.savedToHealth = saved
        persist()
    }

    func delete(_ item: StoredWorkout) {
        context.delete(item)
        persist()
    }

    private func persist() {
        do {
            try context.save()
            lastError = nil
        } catch {
            lastError = "Speichern fehlgeschlagen: \(error.localizedDescription)"
        }
    }
}
