import Foundation

/// Schweizer Landeskoordinaten LV95 (EPSG:2056) → WGS84.
///
/// Quelle: swisstopo, „Näherungslösungen für die direkte Transformation CH1903 ⇔ WGS84“
/// (Formeln und Konstanten für die Berechnung der Schweizerischen schiefachsigen Zylinderprojektion und der
/// Transformation zwischen Koordinatensystemen, Kap. 4 Näherungsformeln; swisstopo, Wabern).
/// Genauigkeit laut swisstopo ca. 1 m. Geprüft gegen den Dienst REFRAME von swisstopo
/// (geodesy.geo.admin.ch, strenge Transformation): in Zürich, Basel, Luzern, Stein am Rhein und Bern < 1 m.
public enum SwissProjection {
    public struct Geographic: Equatable, Sendable {
        /// Breite in Grad (WGS84)
        public var latitude: Double
        /// Länge in Grad (WGS84)
        public var longitude: Double
        /// ellipsoidische Höhe über dem WGS84-Ellipsoid (m), aus der Gebrauchshöhe über Meer genähert
        public var ellipsoidalHeight: Double

        public init(latitude: Double, longitude: Double, ellipsoidalHeight: Double) {
            self.latitude = latitude
            self.longitude = longitude
            self.ellipsoidalHeight = ellipsoidalHeight
        }
    }

    /// - Parameters:
    ///   - east: E (m), z. B. 2 600 000
    ///   - north: N (m), z. B. 1 200 000
    ///   - height: Gebrauchshöhe über Meer (LN02, m)
    public static func wgs84(east: Double, north: Double, height: Double = 0) -> Geographic {
        // Hilfsgrössen in 1000 km, bezogen auf Bern (alte Sternwarte)
        let y = (east - 2_600_000) / 1_000_000
        let x = (north - 1_200_000) / 1_000_000
        // Länge und Breite in der Einheit 10000″
        let lam = 2.6779094
            + 4.728982 * y
            + 0.791484 * y * x
            + 0.1306 * y * x * x
            - 0.0436 * y * y * y
        let phi = 16.9023892
            + 3.238272 * x
            - 0.270978 * y * y
            - 0.002528 * x * x
            - 0.0447 * y * y * x
            - 0.0140 * x * x * x
        let h = height + 49.55 - 12.60 * y - 22.64 * x
        // 10000″ → Grad
        return Geographic(latitude: phi * 100 / 36, longitude: lam * 100 / 36, ellipsoidalHeight: h)
    }
}

/// Ein Punkt der Route für Apple Health (HKWorkoutRoute bzw. CLLocation).
public struct RoutePoint: Equatable, Sendable {
    /// Sekunden seit Start des Trainings (Uhrzeit, einschliesslich Pausen; wie `WorkoutSample.time`)
    public var time: TimeInterval
    /// Grad WGS84
    public var latitude: Double
    public var longitude: Double
    /// Höhe über Meer (m): Seehöhe der Strecke
    public var altitude: Double
    /// Fahrtrichtung in Grad gegenüber geografisch Nord, im Uhrzeigersinn (0 ≤ course < 360)
    public var course: Double
    /// m/s
    public var speed: Double
    /// geruderte Distanz an diesem Punkt (m)
    public var distance: Double

    public init(time: TimeInterval, latitude: Double, longitude: Double, altitude: Double, course: Double,
                speed: Double, distance: Double) {
        self.time = time
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.course = course
        self.speed = speed
        self.distance = distance
    }
}

/// Rechnet ein gespeichertes Training in eine Route (Punkte auf der Karte) um – als reine Funktion.
///
/// - Position aus der geruderten Distanz mit derselben Logik wie während der Fahrt (`SessionController`):
///   frei gerudert → `CourseTrack(course:)` (Distanz endet an der Streckenlänge); mit Trainingsprogramm
///   (`header.workoutPlanId`) → `LapTrack(course:endDistance:)` mit Runden, `endDistance` = Gesamtdistanz des
///   Programms (nur bei reinen Distanzprogrammen, sonst nil).
/// - Szenenkoordinaten → LV95: E = E0 + x, N = N0 − z (`course.originLV95` = [E0, N0]) → WGS84 (`SwissProjection`).
/// - Etwa ein Punkt je `interval` Sekunden; steht das Boot (Pause), nur alle `pauseInterval` Sekunden ein Punkt.
/// - Strecken ohne `origin_lv95` (Teststrecke) und Trainings ohne Zeitreihe ergeben keine Route (leere Liste).
public enum RoutePoints {
    /// Hat die Strecke einen Bezug zu Landeskoordinaten?
    public static func hasGeoreference(_ course: Course) -> Bool {
        course.originLV95.count >= 2 && course.originLV95[0] > 2_000_000 && course.originLV95[1] > 1_000_000
    }

    /// Szenenkoordinaten (x = Ost, z = −Nord) der Strecke → WGS84
    public static func geographic(x: Double, z: Double, course: Course) -> SwissProjection.Geographic? {
        guard hasGeoreference(course) else { return nil }
        return SwissProjection.wgs84(east: course.originLV95[0] + x, north: course.originLV95[1] - z,
                                     height: course.lakeLevelM)
    }

    /// - Parameters:
    ///   - record: gespeichertes Training (Zeitreihe `samples` mit `time` und `distance`)
    ///   - course: die Strecke des Trainings (`record.header.courseId`)
    ///   - planEndDistance: Gesamtdistanz des Trainingsprogramms (`WorkoutPlan.totalDistance`), falls bekannt
    ///   - interval: Abstand der Punkte (s)
    ///   - pauseInterval: Abstand der Punkte, solange das Boot steht (s)
    public static func make(record: WorkoutRecord, course: Course, planEndDistance: Double? = nil,
                            interval: TimeInterval = 1, pauseInterval: TimeInterval = 10) -> [RoutePoint] {
        guard hasGeoreference(course), interval > 0 else { return [] }
        if let id = record.header.courseId, id != course.id { return [] }

        // Zeitreihe ordnen: Zeit aufsteigend, Distanz nie abnehmend; Start bei (0, 0)
        var times: [Double] = []
        var dists: [Double] = []
        for s in record.samples.sorted(by: { $0.time < $1.time }) {
            guard s.time.isFinite, s.distance.isFinite, s.time >= 0 else { continue }
            let d = max(s.distance, dists.last ?? 0)
            if let t = times.last, s.time <= t + 1e-6 {
                dists[dists.count - 1] = d
                continue
            }
            times.append(s.time)
            dists.append(d)
        }
        guard !times.isEmpty else { return [] }
        if times[0] > 1e-6 {
            times.insert(0, at: 0)
            dists.insert(0, at: 0)
        }
        // Endstand aus der Zusammenfassung, falls die Zeitreihe vorher aufhört
        let lastT = times[times.count - 1], lastD = dists[dists.count - 1]
        if record.summary.distance > lastD + 0.5 {
            let endT = max(record.summary.totalDuration, lastT + interval)
            times.append(endT)
            dists.append(record.summary.distance)
        }
        guard (dists.last ?? 0) > 0 else { return [] }

        func distance(at t: Double) -> Double {
            if t <= times[0] { return dists[0] }
            if t >= times[times.count - 1] { return dists[dists.count - 1] }
            var lo = 0, hi = times.count - 1
            while hi - lo > 1 {
                let mid = (lo + hi) / 2
                if times[mid] <= t { lo = mid } else { hi = mid }
            }
            let span = times[hi] - times[lo]
            let u = span > 0 ? (t - times[lo]) / span : 1
            return dists[lo] + (dists[hi] - dists[lo]) * u
        }

        // dieselbe Positionslogik wie während der Fahrt
        let pose: (Double) -> TrackPose
        if record.header.workoutPlanId != nil {
            let laps = LapTrack(course: course, endDistance: planEndDistance)
            pose = { laps.pose(atDistance: $0) }
        } else {
            let track = CourseTrack(course: course)
            pose = { track.pose(atDistance: $0) }
        }

        let endT = times[times.count - 1]
        let steps = Int((endT / interval).rounded(.up))
        var result: [RoutePoint] = []
        result.reserveCapacity(min(steps + 1, 100_000))
        var lastEmitted: (t: Double, d: Double)?
        for i in 0...steps {
            let t = min(Double(i) * interval, endT)
            let d = distance(at: t)
            let isLast = i == steps
            if let last = lastEmitted, !isLast, abs(d - last.d) < 0.5, t - last.t < pauseInterval { continue }
            if let last = lastEmitted, isLast, t - last.t < 1e-6 { break }
            let speed: Double
            if t >= interval {
                speed = max(d - distance(at: t - interval), 0) / interval
            } else {
                speed = max(distance(at: t + interval) - d, 0) / interval
            }
            result.append(point(at: pose(d), time: t, distance: d, speed: speed, course: course))
            lastEmitted = (t, d)
        }
        return result
    }

    /// Länge der Route auf der Kugel (m), Summe der Abstände aufeinanderfolgender Punkte
    public static func length(_ points: [RoutePoint]) -> Double {
        guard points.count >= 2 else { return 0 }
        var sum = 0.0
        for i in 1..<points.count { sum += groundDistance(points[i - 1], points[i]) }
        return sum
    }

    /// Abstand zweier Punkte (m, Haversine mit mittlerem Erdradius)
    public static func groundDistance(_ a: RoutePoint, _ b: RoutePoint) -> Double {
        groundDistance(lat1: a.latitude, lon1: a.longitude, lat2: b.latitude, lon2: b.longitude)
    }

    public static func groundDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let r = 6_371_008.8
        let p1 = lat1 * .pi / 180, p2 = lat2 * .pi / 180
        let dp = p2 - p1, dl = (lon2 - lon1) * .pi / 180
        let h = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * r * asin(min(1, sqrt(h)))
    }

    // MARK: intern

    private static func point(at p: TrackPose, time: Double, distance: Double, speed: Double,
                              course: Course) -> RoutePoint {
        let e0 = course.originLV95[0], n0 = course.originLV95[1]
        let east = e0 + p.x, north = n0 - p.z
        let g = SwissProjection.wgs84(east: east, north: north, height: course.lakeLevelM)
        // Richtung: Punkt 10 m voraus ebenfalls umrechnen (berücksichtigt die Meridiankonvergenz des Gitters)
        let dx = -sin(p.heading), dz = -cos(p.heading)
        let ahead = SwissProjection.wgs84(east: east + 10 * dx, north: north - 10 * dz, height: course.lakeLevelM)
        let phi = g.latitude * .pi / 180
        let dLat = ahead.latitude - g.latitude
        let dLon = (ahead.longitude - g.longitude) * cos(phi)
        var bearing = atan2(dLon, dLat) * 180 / .pi
        if bearing < 0 { bearing += 360 }
        if bearing >= 360 { bearing -= 360 }
        // Höhe über Meer: Seehöhe (CLLocation.altitude ist auf Meereshöhe bezogen)
        return RoutePoint(time: time, latitude: g.latitude, longitude: g.longitude, altitude: course.lakeLevelM,
                          course: bearing, speed: speed, distance: distance)
    }
}
