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

/// ETRS89/UTM (EPSG:25832, EPSG:25833) → WGS84, z. B. für Kartenpakete aus Berlin und Brandenburg (UTM-Zone 33).
///
/// Inverse transversale Mercatorprojektion auf dem GRS80-Ellipsoid nach Krüger in der Reihenform von Karney
/// (C. F. F. Karney, „Transverse Mercator with an accuracy of a few nanometers“, J. Geodesy 85, 2011, Gl. 15–19,
/// Reihen bis n³: innerhalb der Zone genauer als 1 mm). ETRS89 und WGS84 unterscheiden sich in Mitteleuropa um
/// weniger als 1 m; das reicht für Route und Sonnenstand. Geprüft gegen PROJ (pyproj, EPSG:25833/25832 → 4326).
public enum UTMProjection {
    /// - Parameters:
    ///   - east: Ostwert (m) mit 500 000 m Falschem Rechtswert, ohne Zonenvorsatz (z. B. 389 918)
    ///   - north: Nordwert (m), Nordhalbkugel
    ///   - zone: UTM-Zone (Mittelmeridian 6 · zone − 183°), z. B. 33 → 15° O
    ///   - height: Gebrauchshöhe (DHHN2016, m); die ellipsoidische Höhe ist genähert (Geoid in Deutschland
    ///     ca. 36–50 m über dem Ellipsoid, hier pauschal 40 m)
    public static func wgs84(east: Double, north: Double, zone: Int, height: Double = 0) -> SwissProjection.Geographic {
        let a = 6_378_137.0, f = 1 / 298.257_222_101  // GRS80
        let k0 = 0.9996
        let n = f / (2 - f), n2 = n * n, n3 = n2 * n
        let A = a / (1 + n) * (1 + n2 / 4 + n2 * n2 / 64)
        let beta = [n / 2 - 2 * n2 / 3 + 37 * n3 / 96, n2 / 48 + n3 / 15, 17 * n3 / 480]
        let delta = [2 * n - 2 * n2 / 3 - 2 * n3, 7 * n2 / 3 - 8 * n3 / 5, 56 * n3 / 15]
        let xi = north / (k0 * A)
        let eta = (east - 500_000) / (k0 * A)
        var xi1 = xi, eta1 = eta
        for j in 1...3 {
            let b = beta[j - 1], jj = 2 * Double(j)
            xi1 -= b * sin(jj * xi) * cosh(jj * eta)
            eta1 -= b * cos(jj * xi) * sinh(jj * eta)
        }
        let chi = asin(sin(xi1) / cosh(eta1))
        var phi = chi
        for j in 1...3 { phi += delta[j - 1] * sin(2 * Double(j) * chi) }
        let lambda0 = (6 * Double(zone) - 183) * Double.pi / 180
        let lambda = lambda0 + atan2(sinh(eta1), cos(xi1))
        return SwissProjection.Geographic(latitude: phi * 180 / .pi, longitude: lambda * 180 / .pi,
                                          ellipsoidalHeight: height + 40)
    }
}

/// Projizierte Koordinaten eines Kartenpakets → WGS84, je nach Koordinatensystem (`Course.crs`).
///
/// - `EPSG:2056` (LV95, Standard, wenn `crs` fehlt): `SwissProjection`
/// - `EPSG:25832`, `EPSG:25833` (ETRS89/UTM 32N bzw. 33N): `UTMProjection`
/// - sonst: nil (unbekanntes System, keine Route und kein Ort)
public enum GeoProjection {
    /// UTM-Zone für einen ETRS89/UTM-Code (EPSG:258zz), sonst nil
    public static func utmZone(_ crs: String) -> Int? {
        let code = crs.uppercased().replacingOccurrences(of: "EPSG:", with: "")
        guard code.count == 5, code.hasPrefix("258"), let z = Int(code.suffix(2)), (28...38).contains(z) else {
            return nil
        }
        return z
    }

    public static func isSupported(_ crs: String) -> Bool { crs == "EPSG:2056" || utmZone(crs) != nil }

    public static func wgs84(crs: String, east: Double, north: Double, height: Double = 0) -> SwissProjection.Geographic? {
        if crs == "EPSG:2056" { return SwissProjection.wgs84(east: east, north: north, height: height) }
        if let z = utmZone(crs) { return UTMProjection.wgs84(east: east, north: north, zone: z, height: height) }
        return nil
    }

    /// Ursprung [E0, N0] der Szene im Koordinatensystem der Strecke und dieses System, nil ohne gültigen Bezug
    /// (z. B. Teststrecke). LV95 verlangt Werte im Bereich der Landeskoordinaten (E > 2 000 000, N > 1 000 000),
    /// UTM einen Ostwert zwischen 100 und 900 km.
    public static func reference(of course: Course) -> (crs: String, east: Double, north: Double)? {
        let crs = course.coordinateSystem
        let o = course.projectedOrigin
        guard o.count >= 2, o[0].isFinite, o[1].isFinite else { return nil }
        if crs == "EPSG:2056" {
            guard o[0] > 2_000_000, o[1] > 1_000_000 else { return nil }
            return (crs: crs, east: o[0], north: o[1])
        }
        if utmZone(crs) != nil {
            guard o[0] > 100_000, o[0] < 900_000, o[1] > 0 else { return nil }
            return (crs: crs, east: o[0], north: o[1])
        }
        return nil
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
/// - Szenenkoordinaten → Landeskoordinaten: E = E0 + x, N = N0 − z ([E0, N0] = `course.projectedOrigin`, also
///   `origin` bzw. `origin_lv95`) → WGS84 je nach `course.coordinateSystem` (`GeoProjection`: LV95 oder ETRS89/UTM).
/// - Etwa ein Punkt je `interval` Sekunden; steht das Boot (Pause), nur alle `pauseInterval` Sekunden ein Punkt.
/// - Strecken ohne Ursprung (Teststrecke) bzw. mit unbekanntem `crs` und Trainings ohne Zeitreihe ergeben keine
///   Route (leere Liste).
public enum RoutePoints {
    /// Hat die Strecke einen Bezug zu Landeskoordinaten (LV95 oder ETRS89/UTM)?
    public static func hasGeoreference(_ course: Course) -> Bool {
        GeoProjection.reference(of: course) != nil
    }

    /// Szenenkoordinaten (x = Ost, z = −Nord) der Strecke → WGS84
    public static func geographic(x: Double, z: Double, course: Course) -> SwissProjection.Geographic? {
        guard let ref = GeoProjection.reference(of: course) else { return nil }
        return GeoProjection.wgs84(crs: ref.crs, east: ref.east + x, north: ref.north - z, height: course.lakeLevelM)
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
            guard let p = point(at: pose(d), time: t, distance: d, speed: speed, course: course) else { return [] }
            result.append(p)
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
                              course: Course) -> RoutePoint? {
        guard let ref = GeoProjection.reference(of: course) else { return nil }
        let east = ref.east + p.x, north = ref.north - p.z
        guard let g = GeoProjection.wgs84(crs: ref.crs, east: east, north: north, height: course.lakeLevelM)
        else { return nil }
        // Richtung: Punkt 10 m voraus ebenfalls umrechnen (berücksichtigt die Meridiankonvergenz des Gitters)
        let dx = -sin(p.heading), dz = -cos(p.heading)
        guard let ahead = GeoProjection.wgs84(crs: ref.crs, east: east + 10 * dx, north: north - 10 * dz,
                                              height: course.lakeLevelM) else { return nil }
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
