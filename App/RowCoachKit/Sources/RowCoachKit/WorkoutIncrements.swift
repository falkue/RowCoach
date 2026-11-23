import Foundation

/// Zuwachs an Distanz und Energie in einem Zeitabschnitt eines Trainings (für Apple Health beim Nachtragen).
public struct WorkoutIncrement: Equatable, Sendable {
    /// Beginn und Ende in Sekunden seit Start des Trainings
    public var start: TimeInterval
    public var end: TimeInterval
    /// Meter in diesem Abschnitt
    public var distance: Double
    /// kcal in diesem Abschnitt
    public var energy: Double

    public init(start: TimeInterval, end: TimeInterval, distance: Double, energy: Double) {
        self.start = start
        self.end = end
        self.distance = distance
        self.energy = energy
    }
}

public enum WorkoutIncrements {
    /// Teilt die Zeitreihe eines Trainings in Abschnitte von etwa `blockLength` Sekunden und gibt je Abschnitt den
    /// Zuwachs an Distanz und Energie zurück.
    /// - Distanz: aus der Zeitreihe; was die Zusammenfassung (`totalDistance`) über das letzte Sample hinaus hat,
    ///   kommt in den letzten Abschnitt. Die Summe ist damit `max(totalDistance, letzte Sample-Distanz)`.
    /// - Energie: Die Zeitreihe hat keine Kalorien. `totalEnergy` wird nach geleisteter Arbeit (Watt × Zeit) verteilt,
    ///   ohne Leistungswerte nach Distanz, ohne beides gleichmässig über die Zeit. Die Summe ist `totalEnergy`.
    /// - Abschnitte ohne Distanz und ohne Energie (Pausen) fallen weg.
    /// Ein Abschnitt reicht vom Ende des vorigen bis zum letzten Sample im Raster `floor(t / blockLength)`.
    public static func blocks(samples: [WorkoutSample], totalDistance: Double, totalEnergy: Double,
                              blockLength: TimeInterval = 10) -> [WorkoutIncrement] {
        let block = max(blockLength, 1)
        let sorted = samples.filter { $0.time.isFinite && $0.distance.isFinite }.sorted { $0.time < $1.time }

        struct Group {
            var index: Int
            var start: TimeInterval
            var end: TimeInterval
            var distance: Double
            var work: Double
            var duration: Double
        }
        var groups: [Group] = []
        var prevTime: TimeInterval = 0
        var prevDistance = 0.0
        for s in sorted {
            let t = max(s.time, prevTime)
            let dt = t - prevTime
            let dd = max(s.distance - prevDistance, 0)
            let work = Double(max(s.power, 0)) * dt
            let index = Int((t / block).rounded(.down))
            if var last = groups.last, last.index == index {
                last.end = t
                last.distance += dd
                last.work += work
                last.duration += dt
                groups[groups.count - 1] = last
            } else {
                groups.append(Group(index: index, start: prevTime, end: t, distance: dd, work: work, duration: dt))
            }
            prevTime = t
            prevDistance = max(prevDistance, s.distance)
        }

        // Rest der Distanz (Zusammenfassung weiter als das letzte Sample)
        let rest = totalDistance.isFinite ? totalDistance - prevDistance : 0
        if rest > 1e-6 {
            if groups.isEmpty {
                groups.append(Group(index: 0, start: 0, end: max(prevTime, 1), distance: rest, work: 0, duration: max(prevTime, 1)))
            } else {
                groups[groups.count - 1].distance += rest
            }
        }

        // Energie verteilen
        let energy = totalEnergy.isFinite ? max(totalEnergy, 0) : 0
        var energies = Array(repeating: 0.0, count: groups.count)
        if energy > 0 {
            let totalWork: Double = groups.reduce(0) { $0 + $1.work }
            let totalDist: Double = groups.reduce(0) { $0 + $1.distance }
            let totalDur: Double = groups.reduce(0) { $0 + $1.duration }
            let weights: [Double]
            if totalWork > 0 {
                weights = groups.map { $0.work / totalWork }
            } else if totalDist > 0 {
                weights = groups.map { $0.distance / totalDist }
            } else if totalDur > 0 {
                weights = groups.map { $0.duration / totalDur }
            } else {
                weights = []
            }
            if weights.isEmpty {
                // keine Zeitreihe: ein Abschnitt für die ganze Energie
                groups = [Group(index: 0, start: 0, end: max(prevTime, 1), distance: groups.reduce(0.0) { $0 + $1.distance },
                                work: 0, duration: max(prevTime, 1))]
                energies = [energy]
            } else {
                energies = weights.map { $0 * energy }
            }
        }

        var result: [WorkoutIncrement] = []
        for (i, g) in groups.enumerated() where g.distance > 0 || energies[i] > 0 {
            result.append(WorkoutIncrement(start: g.start, end: max(g.end, g.start), distance: g.distance, energy: energies[i]))
        }
        return result
    }
}
