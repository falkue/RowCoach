import Foundation
import os
import RowCoachKit

private let demoLog = Logger(subsystem: "com.falkue.RowCoach", category: "Session")

/// Beispieltrainings für den Testbetrieb (Startbildschirm im Simulator, Bildschirmfotos).
///
/// - `-seedDemoHistory 1`: legt beim Start, falls noch keine Beispieltrainings da sind, 14 plausible Fahrten der
///   letzten gut 5 Wochen auf verschiedenen Strecken an (frei und mit Programm, mit Puls und Phasen).
/// - `-clearDemoHistory 1`: entfernt alle Beispieltrainings (läuft vor dem Anlegen).
///
/// Kennzeichnung: `WorkoutRecord.demo = true` und `device.source = simulator`. Damit zählen sie in den Kennzahlen des
/// Startbildschirms (`TrainingSession.Origin.demo`), aber nie in Apple Health: Nachtragen und Routen-Nachtrag
/// überspringen Simulatorfahrten, und der Verlauf bietet für Beispieltrainings kein Speichern in Health an.
/// Beispieltrainings entstehen nur mit dem Startargument.
@MainActor
enum DemoHistory {
    static let seedKey = "seedDemoHistory"
    static let clearKey = "clearDemoHistory"

    /// Startargumente auswerten (in `RowCoachApp.init`, vor dem ersten Bildschirm)
    static func applyLaunchArguments(store: WorkoutStore, courses: [Course]) {
        let d = UserDefaults.standard
        if d.bool(forKey: clearKey) { clear(store: store) }
        if d.bool(forKey: seedKey) { seedIfNeeded(store: store, courses: courses) }
    }

    static func clear(store: WorkoutStore) {
        let demo = store.items(since: .distantPast).filter { $0.simulated && ($0.record?.isDemo ?? false) }
        for item in demo { store.delete(item) }
        demoLog.info("Beispieltrainings entfernt: \(demo.count, privacy: .public)")
    }

    static func seedIfNeeded(store: WorkoutStore, courses: [Course], now: Date = Date()) {
        let existing = store.items(since: .distantPast).contains { $0.simulated && ($0.record?.isDemo ?? false) }
        guard !existing else {
            demoLog.info("Beispieltrainings schon vorhanden, nichts angelegt")
            return
        }
        let records = makeRecords(courses: courses, now: now)
        for r in records { store.save(r) }
        demoLog.info("Beispieltrainings angelegt: \(records.count, privacy: .public)")
    }

    /// Eine Fahrt im Plan der Beispieldaten
    private struct Ride {
        let daysAgo: Int
        let hour: Int
        let minute: Int
        let courseId: String
        /// nil = frei gerudert (ganze Strecke)
        let planId: String?
        /// Tempo beim freien Rudern (s/500 m)
        var pace: Double = 142
    }

    /// Ablauf: Test vor gut 5 Wochen, danach Grundlage, Schwelle und Intervalle im Wechsel, freie Fahrten auf
    /// Utoquai mit einer neuen Bestzeit gestern. Rhein Stein am Rhein bleibt „noch offen“.
    private static let plan: [Ride] = [
        Ride(daysAgo: 38, hour: 18, minute: 10, courseId: "rhein-basel", planId: "test-2000m"),
        Ride(daysAgo: 33, hour: 11, minute: 27, courseId: "zuerichsee-utoquai", planId: nil, pace: 144),
        Ride(daysAgo: 31, hour: 18, minute: 0, courseId: "zuerichsee-mythenquai", planId: "grundlage-locker-30"),
        Ride(daysAgo: 29, hour: 7, minute: 45, courseId: "rhein-basel", planId: "schwelle-4x6"),
        Ride(daysAgo: 26, hour: 17, minute: 30, courseId: "luzern-nationalquai", planId: nil, pace: 146),
        Ride(daysAgo: 24, hour: 11, minute: 0, courseId: "zuerichsee-utoquai", planId: "technik-locker-25"),
        Ride(daysAgo: 22, hour: 18, minute: 15, courseId: "zuerichsee-mythenquai", planId: "langintervalle-4x4"),
        Ride(daysAgo: 19, hour: 7, minute: 30, courseId: "zuerichsee-utoquai", planId: "grundlage-3x10-r20"),
        Ride(daysAgo: 16, hour: 11, minute: 27, courseId: "zuerichsee-mythenquai", planId: nil, pace: 139),
        Ride(daysAgo: 12, hour: 18, minute: 0, courseId: "luzern-nationalquai", planId: "kurzintervalle-8x2"),
        Ride(daysAgo: 9, hour: 7, minute: 40, courseId: "rhein-basel", planId: "grundlage-locker-30"),
        Ride(daysAgo: 6, hour: 18, minute: 20, courseId: "zuerichsee-utoquai", planId: "schwelle-4x6"),
        Ride(daysAgo: 3, hour: 11, minute: 27, courseId: "zuerichsee-utoquai", planId: nil, pace: 143),
        Ride(daysAgo: 1, hour: 11, minute: 27, courseId: "zuerichsee-utoquai", planId: nil, pace: 141.4),
    ]

    /// Strecken, falls das Kartenpaket fehlt (Titel und Länge wie in den course.json)
    private static let fallbackCourses: [String: (title: String, length: Double)] = [
        "rhein-basel": ("Rhein Basel – Rheinweg Kleinbasel", 3100),
        "zuerichsee-utoquai": ("Utoquai – Seefeld", 4000),
        "zuerichsee-mythenquai": ("Mythenquai – Enge", 4000),
        "luzern-nationalquai": ("Luzern – Schweizerhofquai, Nationalquai und Lido", 3800),
    ]

    static func makeRecords(courses: [Course], now: Date) -> [WorkoutRecord] {
        let cal = TrainingCalendar.swiss()
        let zones = HeartRateZones(maxHR: 185, restHR: 55)
        let best2k = PaceTargets.defaultBest2k
        var out: [WorkoutRecord] = []
        for (n, ride) in plan.enumerated() {
            guard let day = cal.date(byAdding: .day, value: -ride.daysAgo, to: cal.startOfDay(for: now)),
                  let start = cal.date(bySettingHour: ride.hour, minute: ride.minute, second: 0, of: day),
                  start < now else { continue }
            let course = courses.first { $0.id == ride.courseId }
            let title = course?.title ?? fallbackCourses[ride.courseId]?.title ?? ride.courseId
            let length = course.map { $0.turns > 0 ? 2 * $0.oneWayM : $0.oneWayM }
                ?? fallbackCourses[ride.courseId]?.length ?? 4000
            let wp = ride.planId.flatMap { PlanLibrary.plan(id: $0) }

            // Abschnitte: (Sekunden, Tempo s/500 m oder 0, Schlagzahl, Puls, Phasenindex)
            var segments: [(secs: Double, pace: Double, spm: Int, hr: Int, phase: Int?)] = []
            if let wp {
                var lastHR = zones.lowerBound(zone: 2)
                for (i, ph) in wp.phases.enumerated() {
                    let secs = ph.estimatedSeconds(best2k: best2k)
                    let pace = ph.kind == .rest && ph.activeRest == false ? 0 : ph.estimatedPace(best2k: best2k)
                    let spm = ph.spmRange.map { ($0.lowerBound + $0.upperBound) / 2 } ?? (ph.kind == .rest ? 16 : 20)
                    let hr: Int
                    switch ph.kind {
                    case .rest: hr = max(lastHR - 14, zones.lowerBound(zone: 2))
                    case .cooldown: hr = zones.lowerBound(zone: 1) + 6
                    case .warmup: hr = zones.lowerBound(zone: 2) - 2
                    default:
                        let z = ph.hrZone ?? 2
                        // Schwelle liegt real an der Grenze Zone 3/4: knapp darunter, damit sie „mittel“ bleibt
                        hr = wp.category == "Schwelle" ? zones.lowerBound(zone: 4) - 3 : zones.lowerBound(zone: z) + 4
                    }
                    lastHR = hr
                    segments.append((secs, pace, spm, hr, i))
                }
            } else {
                segments.append((length / (500 / ride.pace), ride.pace, 20, zones.lowerBound(zone: 2) + 5, nil))
            }

            // 5-s-Messpunkte mit leichtem, festem Schwanken
            var samples: [WorkoutSample] = []
            var phaseMarks: [(index: Int, start: Double, startDist: Double)] = []
            var t = 0.0, d = 0.0, active = 0.0, strokes = 0.0
            for seg in segments {
                if let p = seg.phase { phaseMarks.append((p, t, d)) }
                var left = seg.secs
                while left > 0 {
                    let dt = min(5, left)
                    let wobble = Int((sin((t + Double(n) * 37) / 23) * 3).rounded())
                    let pace = seg.pace > 0 ? seg.pace + Double(wobble) * 0.4 : 0
                    samples.append(WorkoutSample(time: t, distance: d, pace: pace, strokeRate: pace > 0 ? seg.spm : 0,
                                                 power: RowingSnapshot.watts(pace500: pace), heartRate: seg.hr + wobble))
                    if pace > 0 {
                        d += dt * 500 / pace
                        active += dt
                        strokes += dt * Double(seg.spm) / 60
                    }
                    t += dt
                    left -= dt
                }
            }
            samples.append(WorkoutSample(time: t, distance: d, pace: 0, strokeRate: 0, power: 0,
                                         heartRate: segments.last?.hr))

            // Splits je 500 m (Uhrzeit zwischen den Marken)
            var splits: [SplitTime] = []
            var lastT = 0.0, lastD = 0.0, nextMark = 500.0
            for s in samples where s.distance >= nextMark {
                splits.append(SplitTime(index: splits.count + 1, endDistance: nextMark, length: nextMark - lastD,
                                        duration: s.time - lastT, averageStrokeRate: Double(s.strokeRate),
                                        averagePower: s.power, averageHeartRate: s.heartRate))
                lastT = s.time; lastD = nextMark; nextMark += 500
            }

            var phases: [PlanPhaseResult]?
            if let wp {
                phases = phaseMarks.enumerated().map { j, m in
                    let endT = j + 1 < phaseMarks.count ? phaseMarks[j + 1].start : t
                    let endD = j + 1 < phaseMarks.count ? phaseMarks[j + 1].startDist : d
                    let ph = wp.phases[m.index]
                    return PlanPhaseResult(index: m.index, kind: ph.kind.rawValue, label: ph.title, startTime: m.start,
                                           endTime: endT, startDistance: m.startDist, endDistance: endD,
                                           averageStrokeRate: ph.spmRange.map { Double($0.lowerBound + $0.upperBound) / 2 },
                                           averageHeartRate: segments[j].hr, completed: true)
                }
            }

            let hrs = samples.compactMap(\.heartRate)
            let summary = WorkoutSummary(
                distance: d, activeDuration: active, totalDuration: t,
                averagePace: d > 0 ? active / d * 500 : 0, averageSpeed: active > 0 ? d / active : 0,
                averageStrokeRate: active > 0 ? strokes / active * 60 : 0, strokeCount: Int(strokes),
                averagePower: RowingSnapshot.watts(pace500: d > 0 ? active / d * 500 : 0),
                maxPower: samples.map(\.power).max() ?? 0, calories: Int(active / 60 * 11),
                averageHeartRate: hrs.isEmpty ? nil : hrs.reduce(0, +) / hrs.count, maxHeartRate: hrs.max(),
                heartRateZoneSeconds: zones.secondsPerZone(samples), completedCourse: wp == nil, pauseCount: 0)
            var header = WorkoutHeader(startDate: start, endDate: start.addingTimeInterval(t), courseId: ride.courseId,
                                       courseTitle: title, courseLength: length,
                                       device: WorkoutDevice(source: .simulator, pm5Name: "Beispiel",
                                                             heartRateSource: "strap"),
                                       appVersion: "demo", workoutPlanId: wp?.id)
            header.workoutPlanName = wp?.name
            var rec = WorkoutRecord(header: header, summary: summary, samples: samples, splits: splits,
                                    planPhases: phases, demo: true)
            rec.ensureEffortEstimate(maxHR: zones.maxHR, best2k: best2k, plan: wp)
            out.append(rec)
        }
        return out
    }
}
