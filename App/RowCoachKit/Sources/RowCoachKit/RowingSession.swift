import Foundation

/// Zähler relativ zum Start der Session (Distanz, Schläge, Kalorien des PM5).
/// - Der erste Wert ist nur die Grundlinie (der PM5 kann schon Meter auf der Uhr haben).
/// - Fällt der Wert (Neustart am PM5, Wert springt auf 0), zählt der neue Wert ab 0 weiter.
/// - Unplausibel grosse Sprünge nach oben (z. B. anderes Training geladen) setzen nur die Grundlinie neu.
public struct RelativeCounter: Equatable, Sendable {
    public private(set) var total: Double = 0
    private var last: Double?

    public init() {}

    /// Übernimmt einen Rohwert und gibt den Zuwachs zurück. `limit` = grösster plausibler Zuwachs.
    @discardableResult
    public mutating func update(_ raw: Double, limit: Double) -> Double {
        guard raw.isFinite else { return 0 }
        defer { self.last = raw }
        guard let prev = last else { return 0 }
        var delta = raw - prev
        if delta < 0 {
            // Neustart: was seit dem Zurücksetzen dazukam, zählt
            delta = raw >= 0 && raw <= limit ? raw : 0
        } else if delta > limit {
            delta = 0
        }
        total += delta
        return delta
    }

    /// Nächster Wert wird wieder als Grundlinie genommen.
    public mutating func rebaseline() { last = nil }
}

public enum RowingEvent: Equatable, Sendable {
    case started
    case paused
    case resumed
    case turnReached
    case splitCompleted(SplitTime)
    case finished
}

/// Zustandsmaschine einer Fahrt auf einer Strecke: bereit → rudert ⇄ Pause → Ziel.
///
/// Eingang sind die laufenden `RowingSnapshot`s des PM5 (bzw. Simulators) mit Zeitstempel; `update` sollte auch
/// ohne neue Daten etwa jede Sekunde aufgerufen werden, damit die Pause erkannt wird.
/// - Start: erster Schlag (bzw. erste Distanz, falls der PM5 keine Schläge zählt)
/// - Pause: länger als `pauseAfter` Sekunden kein Schlag; weiter mit dem nächsten Schlag
/// - Ziel: Distanz erreicht die Streckenlänge (oder `finish(at:)` von Hand)
/// Zeiten sind Uhrzeit (Date); die Ruderzeit `activeTime` zählt Pausen nicht mit.
public struct RowingSession: Sendable {
    public enum State: String, Codable, Sendable { case ready, rowing, paused, finished }

    public let track: CourseTrack
    /// Sekunden ohne Schlag bis zur Pause
    public var pauseAfter: TimeInterval
    /// Länge eines Splits (m)
    public let splitLength: Double

    public private(set) var state: State = .ready
    /// Distanz seit Start der Session (m)
    public private(set) var distance: Double = 0
    /// Ruderzeit ohne Pausen (s)
    public private(set) var activeTime: TimeInterval = 0
    public private(set) var startDate: Date?
    public private(set) var endDate: Date?
    public private(set) var pose: TrackPose
    public private(set) var splits: [SplitTime] = []
    public private(set) var samples: [WorkoutSample] = []
    public private(set) var rrIntervals: [Double] = []
    public private(set) var strokeCount: Int = 0
    public private(set) var calories: Int = 0
    public private(set) var pauseCount: Int = 0
    public private(set) var maxPower: Int = 0
    public private(set) var maxHeartRate: Int?
    /// letzter Snapshot (für HUD-Werte wie Tempo, Schlagzahl, Puls)
    public private(set) var snapshot = RowingSnapshot()

    private var distanceCounter = RelativeCounter()
    private var strokeCounter = RelativeCounter()
    private var calorieCounter = RelativeCounter()
    private var strokeCountSeen = false
    private var lastUpdate: Date?
    private var lastStrokeAt: Date?
    private var nextSampleTime: TimeInterval = 0
    private var turnPassed = false
    // zeitgewichtete Summen über die Ruderzeit
    private var spmSum = 0.0, powerSum = 0.0, rowTime = 0.0
    private var hrSum = 0.0, hrTime = 0.0
    // laufender Split
    private var splitStartTime: TimeInterval = 0
    private var splitStartDistance: Double = 0
    private var splitSpm = 0.0, splitPower = 0.0, splitTime = 0.0, splitHR = 0.0, splitHRTime = 0.0

    public init(track: CourseTrack, pauseAfter: TimeInterval = 6, splitLength: Double = 500) {
        self.track = track
        self.pauseAfter = pauseAfter
        self.splitLength = max(splitLength, 1)
        self.pose = track.pose(atDistance: 0)
    }

    // MARK: Abgeleitete Werte

    public var remaining: Double { max(track.totalLength - distance, 0) }
    public var progress: Double { track.totalLength > 0 ? min(distance / track.totalLength, 1) : 0 }
    public var isFinished: Bool { state == .finished }
    public var completedCourse: Bool { distance >= track.totalLength - 0.01 }
    /// s pro 500 m über die Ruderzeit
    public var averagePace: TimeInterval { distance > 1 ? activeTime / distance * 500 : 0 }
    public var averageSpeed: Double { activeTime > 0 ? distance / activeTime : 0 }
    public var averagePower: Int { rowTime > 0 ? Int((powerSum / rowTime).rounded()) : 0 }
    public var averageStrokeRate: Double {
        if strokeCount > 0, activeTime > 0 { return Double(strokeCount) / (activeTime / 60) }
        return rowTime > 0 ? spmSum / rowTime : 0
    }
    public var averageHeartRate: Int? { hrTime > 0 ? Int((hrSum / hrTime).rounded()) : nil }
    /// Uhrzeit seit Start (einschliesslich Pausen)
    public func totalTime(at now: Date) -> TimeInterval {
        guard let startDate else { return 0 }
        return max((endDate ?? now).timeIntervalSince(startDate), 0)
    }

    // MARK: Eingang

    /// Neuer Zustand vom PM5 (oder nur ein Takt mit dem letzten Zustand). Gibt die ausgelösten Ereignisse zurück.
    @discardableResult
    public mutating func update(_ s: RowingSnapshot, at now: Date) -> [RowingEvent] {
        guard state != .finished else { return [] }
        snapshot = s
        var events: [RowingEvent] = []
        let rawDt = lastUpdate.map { max(now.timeIntervalSince($0), 0) } ?? 0
        let dt = min(rawDt, 10)
        lastUpdate = now

        let dDist = distanceCounter.update(s.distance, limit: 50 + 15 * rawDt)
        let dStrokes = strokeCounter.update(Double(s.strokeCount), limit: 5 + 2 * rawDt)
        let dCal = calorieCounter.update(Double(s.calories), limit: 20 + rawDt)
        if s.strokeCount > 0 { strokeCountSeen = true }
        let activity = dStrokes > 0 || (!strokeCountSeen && dDist > 0.5)

        // Zeit des vergangenen Intervalls dem bisherigen Zustand zurechnen
        let wasRowing = state == .rowing
        if wasRowing {
            activeTime += dt
            rowTime += dt
            spmSum += Double(s.strokeRate) * dt
            powerSum += Double(s.power) * dt
            splitTime += dt
            splitSpm += Double(s.strokeRate) * dt
            splitPower += Double(s.power) * dt
        }
        if state != .ready, let hr = s.heartRate, hr > 0 {
            hrSum += Double(hr) * dt; hrTime += dt
            if wasRowing { splitHR += Double(hr) * dt; splitHRTime += dt }
        }

        // Zustandswechsel
        switch state {
        case .ready:
            if activity || dDist > 0.5 {
                state = .rowing
                startDate = now
                lastStrokeAt = now
                events.append(.started)
            }
        case .rowing:
            if activity {
                lastStrokeAt = now
            } else if let last = lastStrokeAt, now.timeIntervalSince(last) > pauseAfter {
                state = .paused
                pauseCount += 1
                events.append(.paused)
            }
        case .paused:
            if activity {
                state = .rowing
                lastStrokeAt = now
                events.append(.resumed)
            }
        case .finished:
            break
        }

        guard state != .ready else { return events }

        // Distanz und Zähler
        let prevDistance = distance
        let prevTime = wasRowing ? activeTime - dt : activeTime
        distance += max(dDist, 0)
        strokeCount += Int(max(dStrokes, 0).rounded())
        calories += Int(max(dCal, 0).rounded())
        if state == .rowing || wasRowing {
            maxPower = max(maxPower, s.power)
        }
        if let hr = s.heartRate, hr > 0 { maxHeartRate = max(maxHeartRate ?? 0, hr) }

        /// Zeitpunkt (Ruderzeit), an dem die Distanz `mark` erreicht wurde
        func timeAt(_ mark: Double) -> TimeInterval {
            let dd = distance - prevDistance
            guard dd > 0 else { return activeTime }
            let f = min(max((mark - prevDistance) / dd, 0), 1)
            return prevTime + f * (activeTime - prevTime)
        }

        let total = track.totalLength
        let reached = min(distance, total)

        // Wende
        if track.course.turns > 0, !turnPassed, reached >= track.oneWayLength, track.oneWayLength > 0 {
            turnPassed = true
            events.append(.turnReached)
        }

        // Splits je 500 m (nur volle; der Rest kommt beim Ziel)
        while splitStartDistance + splitLength <= reached + 1e-9 {
            let end = splitStartDistance + splitLength
            let t = timeAt(end)
            let split = closeSplit(endDistance: end, at: t)
            splits.append(split)
            events.append(.splitCompleted(split))
        }

        // Ziel
        if total > 0, distance >= total {
            let t = timeAt(total)
            distance = total
            activeTime = t
            finishInternal(at: now, events: &events)
        }

        // Zeitreihe ca. 1 Hz
        if let startDate {
            let wall = now.timeIntervalSince(startDate)
            if wall + 1e-9 >= nextSampleTime || state == .finished {
                appendSample(time: wall, snapshot: s)
                nextSampleTime = floor(wall) + 1
            }
        }

        pose = track.pose(atDistance: distance)
        return events
    }

    /// RR-Intervalle vom Pulsgurt anhängen (nur während der Fahrt).
    public mutating func record(rrIntervals rr: [Double]) {
        guard state == .rowing || state == .paused else { return }
        rrIntervals.append(contentsOf: rr.filter { $0 > 0.2 && $0 < 3 })
    }

    /// Beendet die Fahrt von Hand (vor dem Ziel). Ein angefangener Split wird als kurzer Split übernommen.
    @discardableResult
    public mutating func finish(at now: Date) -> [RowingEvent] {
        guard state != .finished else { return [] }
        var events: [RowingEvent] = []
        if state == .ready { startDate = now }
        finishInternal(at: now, events: &events)
        pose = track.pose(atDistance: distance)
        return events
    }

    /// PM5-Werte beim nächsten Update wieder als Grundlinie nehmen (z. B. nach einem Gerätewechsel).
    public mutating func rebaseline() {
        distanceCounter.rebaseline()
        strokeCounter.rebaseline()
        calorieCounter.rebaseline()
    }

    // MARK: Ergebnis

    public func makeRecord(id: UUID = UUID(), device: WorkoutDevice, zones: HeartRateZones?, appVersion: String? = nil,
                           workoutPlanId: String? = nil, weather: SceneWeather? = nil, season: SceneSeason? = nil,
                           raceId: String? = nil, serverId: String? = nil, now: Date = Date()) -> WorkoutRecord {
        let start = startDate ?? now
        let end = endDate ?? now
        let header = WorkoutHeader(startDate: start, endDate: end, courseId: track.course.id,
                                   courseTitle: track.course.title, courseLength: track.totalLength, device: device,
                                   appVersion: appVersion, workoutPlanId: workoutPlanId, weather: weather,
                                   season: season, raceId: raceId, serverId: serverId)
        let hasHR = samples.contains { $0.heartRate != nil }
        let summary = WorkoutSummary(
            distance: distance, activeDuration: activeTime, totalDuration: max(end.timeIntervalSince(start), 0),
            averagePace: averagePace, averageSpeed: averageSpeed, averageStrokeRate: averageStrokeRate,
            strokeCount: strokeCount, averagePower: averagePower, maxPower: maxPower, calories: calories,
            averageHeartRate: averageHeartRate, maxHeartRate: maxHeartRate,
            heartRateZoneSeconds: hasHR ? zones?.secondsPerZone(samples) : nil,
            completedCourse: completedCourse, pauseCount: pauseCount)
        return WorkoutRecord(id: id, header: header, summary: summary, samples: samples, splits: splits,
                             rrIntervals: rrIntervals.isEmpty ? nil : rrIntervals)
    }

    // MARK: intern

    private mutating func finishInternal(at now: Date, events: inout [RowingEvent]) {
        // angefangenen Split (Rest) übernehmen
        if distance - splitStartDistance > 1 {
            let split = closeSplit(endDistance: distance, at: activeTime)
            splits.append(split)
            events.append(.splitCompleted(split))
        }
        state = .finished
        endDate = now
        events.append(.finished)
    }

    private mutating func closeSplit(endDistance: Double, at t: TimeInterval) -> SplitTime {
        let split = SplitTime(
            index: splits.count + 1, endDistance: endDistance, length: endDistance - splitStartDistance,
            duration: max(t - splitStartTime, 0),
            averageStrokeRate: splitTime > 0 ? splitSpm / splitTime : 0,
            averagePower: splitTime > 0 ? Int((splitPower / splitTime).rounded()) : 0,
            averageHeartRate: splitHRTime > 0 ? Int((splitHR / splitHRTime).rounded()) : nil)
        splitStartDistance = endDistance
        splitStartTime = t
        splitSpm = 0; splitPower = 0; splitTime = 0; splitHR = 0; splitHRTime = 0
        return split
    }

    private mutating func appendSample(time: TimeInterval, snapshot s: RowingSnapshot) {
        let rowingNow = state == .rowing || state == .finished
        samples.append(WorkoutSample(time: (time * 10).rounded() / 10, distance: (distance * 10).rounded() / 10,
                                     pace: rowingNow ? s.pace : 0, strokeRate: rowingNow ? s.strokeRate : 0,
                                     power: rowingNow ? s.power : 0, heartRate: s.heartRate))
    }
}
