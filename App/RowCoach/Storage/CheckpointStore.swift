import Foundation
import os
import RowCoachKit

private let checkpointLog = Logger(subsystem: "com.falkue.RowCoach", category: "Session")

/// Datei mit dem Sicherungspunkt der laufenden Fahrt (`active-workout.json` unter Application Support).
///
/// - `save` und `clear` laufen der Reihe nach auf einer eigenen seriellen Warteschlange, damit der Hauptthread
///   nicht auf die Platte wartet und ein `clear` nach dem letzten `save` sicher zuletzt kommt.
/// - Geschrieben wird atomar (`Data.write(options: .atomic)`): Bei einem Absturz mitten im Schreiben bleibt die alte
///   Datei vollständig erhalten.
/// - Beim App-Start übernimmt `claimPending()` eine vorhandene Datei: Sie wird umbenannt
///   (`active-workout.recovering-<UUID>.json`), damit eine neue Fahrt sie nicht überschreibt, und erst nach der
///   Wiederherstellung gelöscht. Bleibt sie liegen (Absturz während der Wiederherstellung), kommt sie beim nächsten
///   Start wieder dran.
final class CheckpointStore: @unchecked Sendable {
    static let activeName = "active-workout.json"
    static let recoveringPrefix = "active-workout.recovering-"

    let directory: URL
    var activeURL: URL { directory.appendingPathComponent(Self.activeName) }

    // Nur von der Warteschlange benutzt; FileManager.default ist threadsicher.
    private let queue = DispatchQueue(label: "com.falkue.RowCoach.checkpoint", qos: .utility)

    init(directory: URL? = nil) {
        self.directory = directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    /// Schreibt den Sicherungspunkt im Hintergrund (Kodieren und Schreiben nicht auf dem Hauptthread).
    func save(_ checkpoint: WorkoutCheckpoint) {
        let url = activeURL
        let dir = directory
        queue.async {
            do {
                let data = try checkpoint.jsonData()
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try data.write(to: url, options: [.atomic])
                checkpointLog.debug("Sicherungspunkt geschrieben (\(data.count, privacy: .public) Bytes)")
            } catch {
                checkpointLog.error("Sicherungspunkt schreiben fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Löscht den Sicherungspunkt der laufenden Fahrt (normales Ende: gespeichert oder verworfen).
    func clear() {
        let url = activeURL
        queue.async {
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            do {
                try FileManager.default.removeItem(at: url)
                checkpointLog.info("Sicherungspunkt gelöscht")
            } catch {
                checkpointLog.error("Sicherungspunkt löschen fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Beim App-Start (synchron, vor der ersten Fahrt): offene Sicherungspunkte zur Wiederherstellung übernehmen.
    /// Gibt die umbenannten Dateien zurück (ältere Reste zuerst).
    func claimPending() -> [URL] {
        queue.sync {}  // ausstehende Schreibvorgänge abwarten (beim Start normalerweise keine)
        let fm = FileManager.default
        var urls = ((try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix(Self.recoveringPrefix) && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let active = activeURL
        if fm.fileExists(atPath: active.path) {
            let target = directory.appendingPathComponent("\(Self.recoveringPrefix)\(UUID().uuidString).json")
            do {
                try fm.moveItem(at: active, to: target)
                urls.append(target)
            } catch {
                checkpointLog.error("Sicherungspunkt übernehmen fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            }
        }
        return urls
    }

    /// Liest einen übernommenen Sicherungspunkt; nil, wenn die Datei fehlt oder beschädigt ist.
    func load(_ url: URL) -> WorkoutCheckpoint? {
        do {
            return try WorkoutCheckpoint(jsonData: Data(contentsOf: url))
        } catch {
            checkpointLog.error("Sicherungspunkt \(url.lastPathComponent, privacy: .public) nicht lesbar: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Beschädigte Datei beiseitelegen (Endung `.broken`), statt sie zu löschen oder bei jedem Start neu zu versuchen.
    func quarantine(_ url: URL) {
        let target = url.appendingPathExtension("broken")
        try? FileManager.default.removeItem(at: target)
        try? FileManager.default.moveItem(at: url, to: target)
    }

    /// Löscht eine übernommene Datei nach der Wiederherstellung.
    func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
