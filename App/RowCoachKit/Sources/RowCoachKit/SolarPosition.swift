import Foundation

/// Sonnenstand aus Zeitpunkt und Ort nach dem NOAA-Verfahren (Solar Calculator der NOAA, nach J. Meeus,
/// „Astronomical Algorithms“). Genauigkeit für 1800–2100 etwa 0,01–0,05°, geprüft gegen den SPA-Algorithmus
/// des NREL (pvlib). Dieselben Formeln stehen in `tools/coursebuilder/sun.py` (Vorschauen); ändert sich eine
/// Fassung, die andere nachziehen.
public struct SolarPosition: Equatable, Sendable {
    /// Kompassrichtung in Grad ab Nord im Uhrzeigersinn (0 = Nord, 90 = Ost, 180 = Süd, 270 = West)
    public var azimuthDegrees: Double
    /// Höhe über dem Horizont in Grad (mit Refraktion, sofern berechnet)
    public var elevationDegrees: Double

    public init(azimuthDegrees: Double, elevationDegrees: Double) {
        self.azimuthDegrees = azimuthDegrees
        self.elevationDegrees = elevationDegrees
    }

    /// Kleinste Sonnenhöhe, die die Szene zeigt: darunter (Nacht, Dämmerung) wird auf die Abenddämmerung geklemmt.
    public static let minimumSceneElevation = 2.0

    // MARK: - Berechnung

    /// - Parameters:
    ///   - date: Zeitpunkt (absolut, Zeitzone spielt keine Rolle)
    ///   - latitude: Breite in Grad (Nord positiv)
    ///   - longitude: Länge in Grad (Ost positiv)
    ///   - refraction: Refraktion der Atmosphäre einrechnen (scheinbare Höhe, NOAA-Näherung)
    public static func compute(date: Date, latitude: Double, longitude: Double,
                               refraction: Bool = true) -> SolarPosition {
        let (decl, eot) = declinationAndEquationOfTime(date)
        let secondsOfDay = date.timeIntervalSince1970.truncatingRemainder(dividingBy: 86_400)
        let minutes = (secondsOfDay < 0 ? secondsOfDay + 86_400 : secondsOfDay) / 60
        let trueSolarTime = minutes + eot + 4 * longitude
        let ha = radians(trueSolarTime / 4 - 180)
        let lat = radians(latitude)
        let cosZenith = sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(ha)
        let zenith = acos(min(1, max(-1, cosZenith)))
        var elevation = 90 - degrees(zenith)
        var azimuth = degrees(atan2(sin(ha), cos(ha) * sin(lat) - tan(decl) * cos(lat))) + 180
        azimuth = azimuth.truncatingRemainder(dividingBy: 360)
        if azimuth < 0 { azimuth += 360 }
        if refraction { elevation += refractionDegrees(elevation) }
        return SolarPosition(azimuthDegrees: azimuth, elevationDegrees: elevation)
    }

    /// Wahrer Mittag (Sonne im Süden bzw. Norden) des wahren Sonnentags am Ort, der `date` enthält.
    public static func solarNoon(containing date: Date, longitude: Double) -> Date {
        let shift = longitude * 240   // Sekunden: 4 min je Grad
        let solar = date.timeIntervalSince1970 + shift
        let dayStart = (solar / 86_400).rounded(.down) * 86_400 - shift
        var noon = dayStart + 43_200
        for _ in 0..<2 {
            let (_, eot) = declinationAndEquationOfTime(Date(timeIntervalSince1970: noon))
            noon = dayStart + (720 - eot) * 60
        }
        return Date(timeIntervalSince1970: noon)
    }

    /// Sonnenstand für die Szene: wie `compute`, aber nie unter `minimumElevation`. Liegt die Sonne tiefer
    /// (Nacht, späte Dämmerung, früher Morgen), gilt der Stand der Abenddämmerung desselben wahren Sonnentags:
    /// der Zeitpunkt nach dem Mittag, an dem die Sonne auf `minimumElevation` sinkt. Keine Nachtszene.
    public static func scene(date: Date, latitude: Double, longitude: Double,
                             minimumElevation: Double = minimumSceneElevation) -> SolarPosition {
        let p = compute(date: date, latitude: latitude, longitude: longitude)
        if p.elevationDegrees >= minimumElevation { return p }
        let noon = solarNoon(containing: date, longitude: longitude)
        let atNoon = compute(date: noon, latitude: latitude, longitude: longitude)
        guard atNoon.elevationDegrees > minimumElevation else {
            // Polarnacht: Sonne steigt nie so hoch; Richtung des Mittags, Höhe geklemmt
            return SolarPosition(azimuthDegrees: atNoon.azimuthDegrees, elevationDegrees: minimumElevation)
        }
        // Höhe fällt zwischen Mittag und Mitternacht monoton: Halbierungsverfahren
        var lo = noon.timeIntervalSince1970, hi = lo + 43_200
        let atMidnight = compute(date: Date(timeIntervalSince1970: hi), latitude: latitude, longitude: longitude)
        if atMidnight.elevationDegrees >= minimumElevation {
            // Mitternachtssonne: kommt hier nicht vor (date läge sonst darüber); sicherheitshalber klemmen
            return SolarPosition(azimuthDegrees: p.azimuthDegrees, elevationDegrees: minimumElevation)
        }
        for _ in 0..<40 {
            let mid = (lo + hi) / 2
            let e = compute(date: Date(timeIntervalSince1970: mid), latitude: latitude, longitude: longitude)
            if e.elevationDegrees > minimumElevation { lo = mid } else { hi = mid }
        }
        let dusk = compute(date: Date(timeIntervalSince1970: (lo + hi) / 2), latitude: latitude, longitude: longitude)
        return SolarPosition(azimuthDegrees: dusk.azimuthDegrees, elevationDegrees: minimumElevation)
    }

    /// Ort einer Strecke (Ursprung `projectedOrigin` im Koordinatensystem `coordinateSystem`, über
    /// `GeoProjection`: LV95 oder ETRS89/UTM); nil ohne Koordinaten oder bei unbekanntem System.
    public static func location(of course: Course) -> (latitude: Double, longitude: Double)? {
        let o = course.projectedOrigin
        guard o.count >= 2,
              let g = GeoProjection.wgs84(crs: course.coordinateSystem, east: o[0], north: o[1],
                                          height: course.lakeLevelM) else { return nil }
        return (g.latitude, g.longitude)
    }

    // MARK: - NOAA-Formeln

    /// (Deklination in rad, Zeitgleichung in Minuten)
    static func declinationAndEquationOfTime(_ date: Date) -> (Double, Double) {
        let jd = date.timeIntervalSince1970 / 86_400 + 2_440_587.5
        let t = (jd - 2_451_545) / 36_525
        var l0 = (280.46646 + t * (36_000.76983 + t * 0.0003032)).truncatingRemainder(dividingBy: 360)
        if l0 < 0 { l0 += 360 }
        let m = 357.52911 + t * (35_999.05029 - 0.0001537 * t)
        let e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let mr = radians(m)
        let c = sin(mr) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(2 * mr) * (0.019993 - 0.000101 * t)
            + sin(3 * mr) * 0.000289
        let omega = radians(125.04 - 1934.136 * t)
        let lambda = radians(l0 + c - 0.00569 - 0.00478 * sin(omega))
        let eps0 = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
        let eps = radians(eps0 + 0.00256 * cos(omega))
        let decl = asin(sin(eps) * sin(lambda))
        let y = pow(tan(eps / 2), 2)
        let l0r = radians(l0)
        let eot = 4 * degrees(y * sin(2 * l0r) - 2 * e * sin(mr) + 4 * e * y * sin(mr) * cos(2 * l0r)
                              - 0.5 * y * y * sin(4 * l0r) - 1.25 * e * e * sin(2 * mr))
        return (decl, eot)
    }

    /// Refraktion in Grad (NOAA-Näherung) für die geometrische Höhe `elevation` in Grad.
    static func refractionDegrees(_ elevation: Double) -> Double {
        if elevation > 85 { return 0 }
        let t = tan(radians(elevation))
        let arcsec: Double
        if elevation > 5 {
            arcsec = 58.1 / t - 0.07 / pow(t, 3) + 0.000086 / pow(t, 5)
        } else if elevation > -0.575 {
            let h = elevation
            arcsec = 1735 + h * (-518.2 + h * (103.4 + h * (-12.79 + h * 0.711)))
        } else {
            arcsec = -20.772 / t
        }
        return arcsec / 3600
    }

    private static func radians(_ d: Double) -> Double { d * .pi / 180 }
    private static func degrees(_ r: Double) -> Double { r * 180 / .pi }
}

/// Wahl des Sonnenstands in der App (Einstellung „Sonnenstand“, Startargument `-demoSun`).
///
/// - `summerAfternoon`: fest 235°/48° – genau die Sonne, die tools/coursebuilder/bake.py in die Gebäude rechnet
///   (Standard, passt zu den vorgerechneten Schatten).
/// - `now`: Datum und Uhrzeit des Geräts am Ort der Strecke.
/// - `morning`, `noon`, `evening`: Sommersonnenwende (21. Juni) des laufenden Jahres am Ort der Strecke,
///   relativ zum wahren Mittag: Morgen −5,5 h (Zürich ca. 79°/22°), Mittag (Süd, ca. 66°), Abend +7,25 h
///   (ca. 299°/5,5°, Abendrot).
public enum SunPreset: String, CaseIterable, Codable, Sendable, Identifiable {
    case summerAfternoon
    case now
    case morning
    case noon
    case evening

    public var id: String { rawValue }

    /// Feste Bake-Sonne (tools/coursebuilder/bake.py SUN_AZ, SUN_EL)
    public static let bakedSun = SolarPosition(azimuthDegrees: 235, elevationDegrees: 48)

    /// Abstand zum wahren Mittag in Stunden (nur Morgen, Mittag, Abend)
    public var hoursFromSolarNoon: Double? {
        switch self {
        case .morning: return -5.5
        case .noon: return 0
        case .evening: return 7.25
        case .summerAfternoon, .now: return nil
        }
    }

    /// Passt der Stand zum vorgerechneten Sonnenschatten der Szene? Nur dann bleibt die Standardszene;
    /// sonst lädt die App die Licht-Variante ohne Sonnenschatten ("ambient"), falls vorhanden.
    public var matchesBakedSun: Bool { self == .summerAfternoon }

    /// Startargument bzw. Kurzname: "morning", "noon", "evening", "now", "afternoon"
    public init?(argument: String) {
        switch argument.lowercased() {
        case "morning", "morgen": self = .morning
        case "noon", "mittag": self = .noon
        case "evening", "abend": self = .evening
        case "now", "jetzt": self = .now
        case "afternoon", "nachmittag", "summerafternoon": self = .summerAfternoon
        default: return nil
        }
    }

    /// Sonnenstand am Ort. `now` ist der aktuelle Zeitpunkt (für Tests einstellbar).
    /// Ergebnis nie unter `SolarPosition.minimumSceneElevation` (Abenddämmerung statt Nacht).
    public func position(latitude: Double, longitude: Double, now: Date = Date()) -> SolarPosition {
        switch self {
        case .summerAfternoon:
            return Self.bakedSun
        case .now:
            return SolarPosition.scene(date: now, latitude: latitude, longitude: longitude)
        case .morning, .noon, .evening:
            return SolarPosition.scene(date: date(longitude: longitude, now: now),
                                       latitude: latitude, longitude: longitude)
        }
    }

    /// Zeitpunkt für Morgen, Mittag, Abend (21. Juni des Jahres von `now`, UTC-Kalender); sonst `now`.
    public func date(longitude: Double, now: Date = Date()) -> Date {
        guard let h = hoursFromSolarNoon else { return now }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? cal.timeZone
        let year = cal.component(.year, from: now)
        let midsummer = cal.date(from: DateComponents(year: year, month: 6, day: 21, hour: 12)) ?? now
        return SolarPosition.solarNoon(containing: midsummer, longitude: longitude).addingTimeInterval(h * 3600)
    }
}
