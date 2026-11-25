import XCTest
@testable import RowCoachKit

final class SwissProjectionTests: XCTestCase {
    /// Bern, alte Sternwarte (Fundamentalpunkt der Landesvermessung): E 2 600 000 / N 1 200 000
    /// ≈ 46.95108° N, 7.43864° E (swisstopo)
    func testBernOldObservatory() {
        let g = SwissProjection.wgs84(east: 2_600_000, north: 1_200_000)
        XCTAssertEqual(g.latitude, 46.95108, accuracy: 1e-5)
        XCTAssertEqual(g.longitude, 7.43864, accuracy: 1e-5)
    }

    /// Referenzwerte aus dem swisstopo-Dienst REFRAME (strenge Transformation LV95 → WGS84, abgefragt 23.11.2026);
    /// die Näherungsformeln sollen auf ca. 1 m genau sein.
    func testReferencePointsWithinOneAndAHalfMetres() {
        let refs: [(e: Double, n: Double, h: Double, lat: Double, lon: Double, hEll: Double)] = [
            (2_700_000, 1_100_000, 500, 46.0441303, 8.7304971, 550.60),  // Zahlenbeispiel der swisstopo-Doku
            (2_683_000, 1_246_000, 406, 47.3596205, 8.5373196, 453.53),  // Zürich, unteres Seebecken
            (2_611_000, 1_267_000, 245, 47.5536255, 7.5847593, 292.91),  // Basel, Rheinknie
            (2_666_000, 1_211_000, 434, 47.0467477, 8.3071801, 482.58),  // Luzern, Seebecken
            (2_706_000, 1_280_000, 400, 47.6620643, 8.8498132, 446.40),  // Stein am Rhein
        ]
        for r in refs {
            let g = SwissProjection.wgs84(east: r.e, north: r.n, height: r.h)
            let d = RoutePoints.groundDistance(lat1: g.latitude, lon1: g.longitude, lat2: r.lat, lon2: r.lon)
            XCTAssertLessThan(d, 1.5, "Lage bei E \(r.e) / N \(r.n): \(d) m daneben")
            XCTAssertEqual(g.ellipsoidalHeight, r.hEll, accuracy: 0.5)
        }
    }

    /// 1 km nach Norden bzw. Osten im Gitter ist auch auf der Kugel ca. 1 km (Massstab der Projektion nahe 1;
    /// die Kugel mit mittlerem Radius weicht ost-west um ca. 3 m je km vom Ellipsoid ab).
    func testScale() {
        let a = SwissProjection.wgs84(east: 2_683_500, north: 1_245_000)
        let b = SwissProjection.wgs84(east: 2_683_500, north: 1_246_000)
        let c = SwissProjection.wgs84(east: 2_684_500, north: 1_245_000)
        XCTAssertEqual(RoutePoints.groundDistance(lat1: a.latitude, lon1: a.longitude, lat2: b.latitude, lon2: b.longitude),
                       1000, accuracy: 5)
        XCTAssertEqual(RoutePoints.groundDistance(lat1: a.latitude, lon1: a.longitude, lat2: c.latitude, lon2: c.longitude),
                       1000, accuracy: 5)
        XCTAssertGreaterThan(b.latitude, a.latitude)
        XCTAssertGreaterThan(c.longitude, a.longitude)
    }
}

final class RoutePointsTests: XCTestCase {
    private let e0 = 2_683_500.0, n0 = 1_245_000.0

    /// Gerade Strecke 1000 m nach Norden, Wende, 1000 m zurück (Rückfahrt 12 m westlich), am Zürichsee verortet
    private func zurichCourse() -> Course {
        var c = Course.straight(id: "test-zh", title: "Test Zürich", oneWay: 1000)
        c.originLV95 = [e0, n0]
        c.lakeLevelM = 405.9
        return c
    }

    /// Training mit konstant `speed` m/s; optional eine Pause (Distanz steht) ab `pauseAt` für `pauseLength` s
    private func record(course: Course, distance: Double, speed: Double = 4, planId: String? = nil,
                        pauseAt: Double? = nil, pauseLength: Double = 0) -> WorkoutRecord {
        let rowTime = distance / speed
        let total = rowTime + pauseLength
        var samples: [WorkoutSample] = []
        var t = 0.0
        while t <= total + 1e-9 {
            let moving: Double
            if let p = pauseAt, t > p { moving = t < p + pauseLength ? p : t - pauseLength } else { moving = t }
            samples.append(WorkoutSample(time: t, distance: min(moving * speed, distance), pace: 125, strokeRate: 22,
                                         power: 150, heartRate: 140))
            t += 1
        }
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let header = WorkoutHeader(startDate: start, endDate: start.addingTimeInterval(total), courseId: course.id,
                                   courseTitle: course.title, courseLength: course.totalM,
                                   device: WorkoutDevice(source: .pm5), workoutPlanId: planId)
        let summary = WorkoutSummary(distance: distance, activeDuration: rowTime, totalDuration: total,
                                     averagePace: 125, averageSpeed: speed, averageStrokeRate: 22, strokeCount: 100,
                                     averagePower: 150, maxPower: 200, calories: 100, averageHeartRate: 140,
                                     maxHeartRate: 160, heartRateZoneSeconds: nil, completedCourse: true,
                                     pauseCount: pauseAt == nil ? 0 : 1)
        return WorkoutRecord(header: header, summary: summary, samples: samples, splits: [])
    }

    private func lv95(_ east: Double, _ north: Double) -> SwissProjection.Geographic {
        SwissProjection.wgs84(east: east, north: north, height: 405.9)
    }

    private func dist(_ p: RoutePoint, _ g: SwissProjection.Geographic) -> Double {
        RoutePoints.groundDistance(lat1: p.latitude, lon1: p.longitude, lat2: g.latitude, lon2: g.longitude)
    }

    private func point(_ pts: [RoutePoint], atTime t: Double) -> RoutePoint? {
        pts.min { abs($0.time - t) < abs($1.time - t) }
    }

    /// Winkelabstand in Grad (0…180)
    private func angle(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
    }

    func testLengthMatchesRowedDistance() {
        let c = zurichCourse()
        let pts = RoutePoints.make(record: record(course: c, distance: 2000), course: c)
        XCTAssertEqual(pts.count, 501)  // 500 s, 1 Punkt je Sekunde, plus Start
        XCTAssertEqual(RoutePoints.length(pts), 2000, accuracy: 20)
        XCTAssertEqual(pts.last?.distance ?? 0, 2000, accuracy: 0.01)
    }

    func testStartsAtCourseStart() throws {
        let c = zurichCourse()
        let pts = RoutePoints.make(record: record(course: c, distance: 2000), course: c)
        let first = try XCTUnwrap(pts.first)
        XCTAssertEqual(first.time, 0)
        XCTAssertLessThan(dist(first, lv95(e0, n0)), 0.5)
        XCTAssertEqual(first.altitude, 405.9)
    }

    /// Hinfahrt nach Norden; Wende bei ca. 1000 m; Rückfahrt 12 m westlich nach Süden
    func testTurnAtTheRightPlace() throws {
        let c = zurichCourse()
        let pts = RoutePoints.make(record: record(course: c, distance: 2000), course: c)
        let start = lv95(e0, n0)

        // 500 m (t = 125 s): 500 m nördlich des Starts, Richtung Nord, 4 m/s
        let p500 = try XCTUnwrap(point(pts, atTime: 125))
        XCTAssertLessThan(dist(p500, lv95(e0, n0 + 500)), 0.5)
        XCTAssertEqual(dist(p500, start), 500, accuracy: 2)
        XCTAssertLessThan(angle(p500.course, 0), 2)
        XCTAssertEqual(p500.speed, 4, accuracy: 0.01)

        // nördlichster Punkt = Wende: kurz vor dem Wendepunkt bei 1000 m (Kehre ab 960 m, ca. 31 m nach vorn)
        let north = try XCTUnwrap(pts.max { $0.latitude < $1.latitude })
        XCTAssertEqual(north.distance, 1000, accuracy: 20)
        let northOffset = (north.latitude - start.latitude) * 111_200
        XCTAssertGreaterThan(northOffset, 970)
        XCTAssertLessThan(northOffset, 1005)

        // 1500 m (t = 375 s): Rückfahrt, wieder 500 m nördlich, 12 m westlich, Richtung Süd
        let p1500 = try XCTUnwrap(point(pts, atTime: 375))
        XCTAssertLessThan(dist(p1500, lv95(e0 - 12, n0 + 500)), 0.5)
        XCTAssertLessThan(p1500.longitude, p500.longitude)
        XCTAssertLessThan(angle(p1500.course, 180), 2)

        // Ziel: am Start, 12 m westlich
        let last = try XCTUnwrap(pts.last)
        XCTAssertLessThan(dist(last, lv95(e0 - 12, n0)), 0.5)
    }

    /// Training mit Runden (Programm über 3000 m auf 2 × 1000 m): bei 2500 m wieder auf der Hinfahrt, 500 m nördlich.
    /// Frei gerudert endet die Position dagegen an der Streckenlänge.
    func testLapsForTrainingPlans() throws {
        let c = zurichCourse()
        let withPlan = RoutePoints.make(record: record(course: c, distance: 3000, planId: "plan"), course: c,
                                        planEndDistance: 3000)
        let p2500 = try XCTUnwrap(point(withPlan, atTime: 625))
        XCTAssertEqual(p2500.distance, 2500, accuracy: 0.01)
        XCTAssertLessThan(dist(p2500, lv95(e0, n0 + 500)), 0.5)
        XCTAssertLessThan(angle(p2500.course, 0), 2)
        XCTAssertEqual(RoutePoints.length(withPlan), 3000, accuracy: 30)

        let free = RoutePoints.make(record: record(course: c, distance: 3000), course: c)
        let f2500 = try XCTUnwrap(point(free, atTime: 625))
        XCTAssertLessThan(dist(f2500, lv95(e0 - 12, n0)), 0.5)
    }

    /// Während einer Pause (Boot steht) nur alle 10 s ein Punkt
    func testPausesAreThinned() {
        let c = zurichCourse()
        let rec = record(course: c, distance: 800, pauseAt: 100, pauseLength: 60)
        let pts = RoutePoints.make(record: rec, course: c)
        let inPause = pts.filter { $0.time > 100.5 && $0.time < 159.5 }
        XCTAssertLessThanOrEqual(inPause.count, 6)
        XCTAssertGreaterThanOrEqual(inPause.count, 5)
        XCTAssertEqual(pts.count, 202 + inPause.count)  // 0…100 s und 160…260 s (t = 160 s nach 10 s Stand), dazu die Pausenpunkte
        XCTAssertEqual(RoutePoints.length(pts), 800, accuracy: 8)
        XCTAssertTrue(inPause.allSatisfy { $0.speed == 0 })
        // Zeit läuft immer vorwärts
        XCTAssertTrue(zip(pts, pts.dropFirst()).allSatisfy { $0.time < $1.time })
    }

    func testNoRouteWithoutGeoreference() {
        let test = Course.straight(id: "teststrecke-2x1000", oneWay: 1000)
        XCTAssertFalse(RoutePoints.hasGeoreference(test))
        XCTAssertTrue(RoutePoints.make(record: record(course: test, distance: 2000), course: test).isEmpty)
    }

    func testNoRouteForOtherCourse() {
        let c = zurichCourse()
        var other = c
        other.id = "andere-strecke"
        XCTAssertTrue(RoutePoints.make(record: record(course: c, distance: 2000), course: other).isEmpty)
    }

    func testNoRouteWithoutSamples() {
        let c = zurichCourse()
        var rec = record(course: c, distance: 2000)
        rec.samples = []
        rec.summary.distance = 0
        XCTAssertTrue(RoutePoints.make(record: rec, course: c).isEmpty)
    }
}

final class UTMProjectionTests: XCTestCase {
    /// Referenzwerte aus PROJ (pyproj 3, EPSG:25833 bzw. 25832 → EPSG:4326, abgefragt 23.11.2026)
    func testReferencePointsZone33And32() {
        let refs: [(crs: String, e: Double, n: Double, lat: Double, lon: Double)] = [
            ("EPSG:25833", 389_918.0, 5_819_699.1, 52.5162747, 13.3777034),  // Brandenburger Tor
            ("EPSG:25833", 403_916.0, 5_807_969.2, 52.4134997, 13.5873004),  // Regattastrecke Grünau, Ziel
            ("EPSG:25833", 370_122.4, 5_808_745.8, 52.4134996, 13.0904005),  // Glienicker Brücke
            ("EPSG:25833", 317_027.8, 5_690_878.4, 51.3397003, 12.3730002),  // Leipzig (2,6° vom Mittelmeridian)
            ("EPSG:25833", 499_090.8, 5_666_783.8, 51.1525003, 14.9870002),  // Görlitz (fast auf dem Mittelmeridian)
            ("EPSG:25832", 356_558.9, 5_645_279.7, 50.9412778, 6.9582816),   // Kölner Dom
        ]
        for r in refs {
            guard let g = GeoProjection.wgs84(crs: r.crs, east: r.e, north: r.n) else {
                return XCTFail("\(r.crs) nicht unterstützt")
            }
            let d = RoutePoints.groundDistance(lat1: g.latitude, lon1: g.longitude, lat2: r.lat, lon2: r.lon)
            XCTAssertLessThan(d, 0.05, "\(r.crs) E \(r.e) / N \(r.n): \(d) m daneben")
        }
    }

    /// Weltweite UTM-Systeme (Regel docs/WELTWEIT.md), Referenzwerte aus PROJ (pyproj 3.7, EPSG:xxxx → EPSG:4326,
    /// abgefragt 25.11.2026); Südhalbkugel mit 10 000 000 m Falschem Hochwert, WGS84- und GRS80-Ellipsoid
    func testReferencePointsWorldwide() {
        let refs: [(crs: String, e: Double, n: Double, lat: Double, lon: Double)] = [
            ("EPSG:25830", 620_392.0, 5_734_216.1, 51.7459, -1.2561),     // Oxford, Folly Bridge (westlich Greenwich)
            ("EPSG:32630", 621_783.5, 5_732_658.3, 51.7316, -1.2365),     // Oxford, Iffley Lock
            ("EPSG:25831", 452_482.5, 5_411_717.2, 48.8566, 2.3522),      // Paris
            ("EPSG:25832", 596_757.3, 6_642_373.8, 59.9075, 10.7300),     // Oslo
            ("EPSG:6691", 391_449.7, 3_952_447.5, 35.7100, 139.8000),     // Tokio, Sumida (JGD2011 Zone 54)
            ("EPSG:6690", 582_614.1, 3_870_090.2, 34.9700, 135.9050),     // Ōtsu, Seta (JGD2011 Zone 53)
            ("EPSG:31983", 683_450.6, 7_458_561.2, -22.9711, -43.2105),   // Rio, Lagoa (SIRGAS 2000 Zone 23 S)
            ("EPSG:32723", 683_450.6, 7_458_561.2, -22.9711, -43.2105),   // dasselbe in WGS84/UTM 23 S
            ("EPSG:32721", 354_805.8, 6_190_141.9, -34.4200, -58.5800),   // Tigre
            ("EPSG:32756", 333_471.8, 6_253_018.2, -33.8500, 151.2000),   // Sydney
            ("EPSG:32719", 344_846.7, 6_297_700.2, -33.4489, -70.6693),   // Santiago de Chile
            ("EPSG:26918", 583_959.4, 4_507_351.0, 40.7128, -74.0060),    // New York (NAD83 Zone 18)
        ]
        for r in refs {
            guard let g = GeoProjection.wgs84(crs: r.crs, east: r.e, north: r.n) else {
                return XCTFail("\(r.crs) nicht unterstützt")
            }
            let d = RoutePoints.groundDistance(lat1: g.latitude, lon1: g.longitude, lat2: r.lat, lon2: r.lon)
            XCTAssertLessThan(d, 0.1, "\(r.crs) E \(r.e) / N \(r.n): \(d) m daneben")
        }
    }

    func testWorldwideZoneParsing() {
        XCTAssertEqual(GeoProjection.utm("EPSG:25830"), .init(zone: 30, southern: false, ellipsoid: .grs80))
        XCTAssertEqual(GeoProjection.utm("EPSG:32630"), .init(zone: 30, southern: false, ellipsoid: .wgs84))
        XCTAssertEqual(GeoProjection.utm("EPSG:32723"), .init(zone: 23, southern: true, ellipsoid: .wgs84))
        XCTAssertEqual(GeoProjection.utm("EPSG:6688"), .init(zone: 51, southern: false, ellipsoid: .grs80))
        XCTAssertEqual(GeoProjection.utm("EPSG:6692"), .init(zone: 55, southern: false, ellipsoid: .grs80))
        XCTAssertEqual(GeoProjection.utm("EPSG:31965"), .init(zone: 11, southern: false, ellipsoid: .grs80))
        XCTAssertEqual(GeoProjection.utm("EPSG:31976"), .init(zone: 22, southern: false, ellipsoid: .grs80))
        XCTAssertEqual(GeoProjection.utm("EPSG:31977"), .init(zone: 17, southern: true, ellipsoid: .grs80))
        XCTAssertEqual(GeoProjection.utm("EPSG:31985"), .init(zone: 25, southern: true, ellipsoid: .grs80))
        XCTAssertEqual(GeoProjection.utm("epsg:32601")?.zone, 1)
        XCTAssertEqual(GeoProjection.utm("EPSG:32760")?.zone, 60)
        XCTAssertNil(GeoProjection.utm("EPSG:32661"))   // UPS Nord, keine UTM-Zone
        XCTAssertNil(GeoProjection.utm("EPSG:2154"))    // Lambert-93: beim Holen nach UTM umrechnen
        XCTAssertNil(GeoProjection.utm("EPSG:27700"))   // British National Grid: ebenso
        XCTAssertNil(GeoProjection.utm("EPSG:6697"))    // JGD2011 geographisch (PLATEAU)
        XCTAssertNil(GeoProjection.utm("EPSG:025833"))
        XCTAssertTrue(GeoProjection.isSupported("EPSG:32723"))
        XCTAssertFalse(GeoProjection.isSupported("EPSG:3857"))
    }

    /// Strecke auf der Südhalbkugel (Rio, SIRGAS 2000/UTM 23 S): Ort, Route und Richtung; Gitter-Nord zeigt östlich
    /// des Mittelmeridians (45° W) auf der Südhalbkugel leicht nach Westen (Meridiankonvergenz ≈ −0,7°)
    func testSouthernHemisphereCourse() throws {
        let json = #"{"id":"rio-test","title":"T","region":"","scene":"","qualities":["standard"],"one_way_m":1000,"total_m":2000,"turns":1,"crs":"EPSG:31983","origin":[683450.6,7458561.2],"lake_level_m":1.0,"path_xz":[[0,0],[0,-500],[0,-1000]],"attribution":"","country":"BR"}"#
        let c = try Course.decode(Data(json.utf8))
        XCTAssertTrue(RoutePoints.hasGeoreference(c))
        let loc = try XCTUnwrap(SolarPosition.location(of: c))
        XCTAssertEqual(loc.latitude, -22.9711, accuracy: 1e-5)
        XCTAssertEqual(loc.longitude, -43.2105, accuracy: 1e-5)
        let a = try XCTUnwrap(RoutePoints.geographic(x: 0, z: 0, course: c))
        let b = try XCTUnwrap(RoutePoints.geographic(x: 0, z: -1000, course: c))
        XCTAssertGreaterThan(b.latitude, a.latitude)  // −z = Norden, auch südlich des Äquators
        XCTAssertEqual(RoutePoints.groundDistance(lat1: a.latitude, lon1: a.longitude, lat2: b.latitude,
                                                  lon2: b.longitude), 1000, accuracy: 5)
        let dLon = (b.longitude - a.longitude) * cos(a.latitude * .pi / 180)
        let bearing = atan2(dLon, b.latitude - a.latitude) * 180 / .pi
        XCTAssertEqual(bearing, -0.7, accuracy: 0.2)
    }

    func testZoneParsing() {
        XCTAssertEqual(GeoProjection.utmZone("EPSG:25833"), 33)
        XCTAssertEqual(GeoProjection.utmZone("EPSG:25832"), 32)
        XCTAssertNil(GeoProjection.utmZone("EPSG:2056"))
        XCTAssertNil(GeoProjection.utmZone("EPSG:4326"))
        XCTAssertTrue(GeoProjection.isSupported("EPSG:2056"))
        XCTAssertFalse(GeoProjection.isSupported("EPSG:3857"))
        XCTAssertNil(GeoProjection.wgs84(crs: "EPSG:3857", east: 0, north: 0))
    }

    /// LV95 bleibt unverändert die Wahl ohne `crs`
    func testSwissIsDefault() {
        let g = GeoProjection.wgs84(crs: "EPSG:2056", east: 2_600_000, north: 1_200_000)
        XCTAssertEqual(g?.latitude ?? 0, 46.95108, accuracy: 1e-5)
        XCTAssertEqual(g?.longitude ?? 0, 7.43864, accuracy: 1e-5)
    }

    /// Strecke in Berlin (course.json mit "crs" und "origin", ohne "origin_lv95"): Ort, Route und Richtung
    func testBerlinCourseRouteAndLocation() throws {
        let json = #"{"id":"berlin-test","title":"T","region":"","scene":"","qualities":["standard"],"one_way_m":1000,"total_m":2000,"turns":1,"crs":"EPSG:25833","origin":[389918.0,5819699.1],"lake_level_m":30.5,"path_xz":[[0,0],[0,-500],[0,-1000]],"attribution":""}"#
        let c = try Course.decode(Data(json.utf8))
        XCTAssertEqual(c.originLV95, [])
        XCTAssertEqual(c.coordinateSystem, "EPSG:25833")
        XCTAssertTrue(RoutePoints.hasGeoreference(c))
        let loc = try XCTUnwrap(SolarPosition.location(of: c))
        XCTAssertEqual(loc.latitude, 52.5162747, accuracy: 1e-6)
        XCTAssertEqual(loc.longitude, 13.3777034, accuracy: 1e-6)
        // 1000 m nach Norden im Gitter ≈ 1000 m auf der Kugel (Massstab 0,9996 + Lage in der Zone)
        let a = try XCTUnwrap(RoutePoints.geographic(x: 0, z: 0, course: c))
        let b = try XCTUnwrap(RoutePoints.geographic(x: 0, z: -1000, course: c))
        XCTAssertEqual(RoutePoints.groundDistance(lat1: a.latitude, lon1: a.longitude, lat2: b.latitude,
                                                  lon2: b.longitude), 1000, accuracy: 5)
        // Gitter-Nord zeigt westlich des Mittelmeridians (15° O) leicht nach Westen: Meridiankonvergenz ≈ −1,3°
        let dLon = (b.longitude - a.longitude) * cos(a.latitude * .pi / 180)
        let bearing = atan2(dLon, b.latitude - a.latitude) * 180 / .pi
        XCTAssertEqual(bearing, -1.3, accuracy: 0.2)
    }

    /// Unbekanntes Koordinatensystem oder UTM ohne sinnvollen Ursprung: kein Bezug
    func testNoGeoreferenceForUnknownCrs() {
        var c = Course.straight(oneWay: 1000)
        c.crs = "EPSG:3857"
        c.origin = [1_000_000, 6_000_000]
        XCTAssertFalse(RoutePoints.hasGeoreference(c))
        XCTAssertNil(SolarPosition.location(of: c))
        c.crs = "EPSG:25833"
        c.origin = [0, 0]
        XCTAssertFalse(RoutePoints.hasGeoreference(c))
    }
}
