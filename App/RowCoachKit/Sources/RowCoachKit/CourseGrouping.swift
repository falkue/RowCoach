import Foundation

/// Strecken für die Auswahl nach Land und Stadt gruppiert: Länder und Städte alphabetisch nach ihrem angezeigten
/// Namen, Strecken je Stadt nach Titel. Strecken ohne Land (Teststrecke) kommen in eine Gruppe ohne Code ans Ende.
public struct CourseCountryGroup: Equatable, Sendable, Identifiable {
    public var countryCode: String?
    public var countryName: String
    public var cities: [CourseCityGroup]
    public var id: String { countryCode ?? "-" }
    public var flag: String { countryCode.map(Course.flag) ?? "" }
    public var courseCount: Int { cities.reduce(0) { $0 + $1.courses.count } }
}

public struct CourseCityGroup: Equatable, Sendable, Identifiable {
    public var city: String
    public var courses: [Course]
    public var id: String { city }
}

public enum CourseGrouping {
    /// - Parameters:
    ///   - countryName: angezeigter Name eines Ländercodes (z. B. über `Locale.localizedString(forRegionCode:)`)
    ///   - cityName: angezeigter Name einer Stadt (Übersetzung), Standard unverändert
    ///   - otherName: Name der Gruppe ohne Land bzw. ohne Stadt
    public static func byCountryAndCity(_ courses: [Course], countryName: (String) -> String,
                                        cityName: (String) -> String = { $0 }, otherName: String) -> [CourseCountryGroup] {
        let byCountry = Dictionary(grouping: courses) { $0.countryCode }
        var groups: [CourseCountryGroup] = byCountry.map { code, list in
            let byCity = Dictionary(grouping: list) { c -> String in
                guard let city = c.city, !city.isEmpty else { return otherName }
                return cityName(city)
            }
            let cities = byCity.map { city, items in
                CourseCityGroup(city: city, courses: items.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending })
            }
            .sorted { $0.city.localizedStandardCompare($1.city) == .orderedAscending }
            return CourseCountryGroup(countryCode: code, countryName: code.map(countryName) ?? otherName, cities: cities)
        }
        groups.sort { a, b in
            if (a.countryCode == nil) != (b.countryCode == nil) { return a.countryCode != nil }
            return a.countryName.localizedStandardCompare(b.countryName) == .orderedAscending
        }
        return groups
    }
}
