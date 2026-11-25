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

/// Form einer Strecke (Filter in der Streckenauswahl)
public enum CourseShape: String, CaseIterable, Sendable, Identifiable {
    case outAndBack, loop, oneWay
    public var id: String { rawValue }
}

extension Course {
    public var shape: CourseShape {
        if turns > 0 { return .outAndBack }
        return isLoop ? .loop : .oneWay
    }
}

/// Filter der Streckenauswahl: Land (ISO-Code) und Form; nil = alle
public struct CourseFilter: Equatable, Sendable {
    public var countryCode: String?
    public var shape: CourseShape?
    public init(countryCode: String? = nil, shape: CourseShape? = nil) {
        self.countryCode = countryCode
        self.shape = shape
    }
    public var isActive: Bool { countryCode != nil || shape != nil }
    public func matches(_ c: Course) -> Bool {
        (countryCode == nil || c.countryCode == countryCode) && (shape == nil || c.shape == shape)
    }
    public func apply(_ courses: [Course]) -> [Course] { courses.filter(matches) }
}
