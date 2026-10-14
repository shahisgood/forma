import Foundation
@testable import FormaKit

/// A fixed Gregorian calendar so tests do not depend on the machine's locale or time zone.
func makeCalendar(timeZone: String = "Europe/London", firstWeekday: Int = 2) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: timeZone)!
    // Locale first: assigning a locale can reset `firstWeekday`.
    calendar.locale = Locale(identifier: "en_GB")
    calendar.firstWeekday = firstWeekday
    return calendar
}

func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 8, _ min: Int = 0, calendar: Calendar) -> Date {
    var c = DateComponents()
    c.year = y
    c.month = m
    c.day = d
    c.hour = h
    c.minute = min
    return calendar.date(from: c)!
}
