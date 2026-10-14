import Foundation
import Testing
@testable import FormaKit

@Suite("DayKey")
struct DayKeyTests {
    let cal = makeCalendar()

    @Test func roundTripsThroughString() {
        let key = DayKey(year: 2026, month: 3, day: 7)
        #expect(key.string == "2026-03-07")
        #expect(DayKey(string: "2026-03-07") == key)
        #expect(DayKey(string: "2026-13-01") == nil)
        #expect(DayKey(string: "nonsense") == nil)
    }

    @Test func ordersChronologically() {
        let a = DayKey(year: 2025, month: 12, day: 31)
        let b = DayKey(year: 2026, month: 1, day: 1)
        #expect(a < b)
        #expect([b, a].sorted() == [a, b])
    }

    @Test func addingDaysCrossesMonthAndDST() {
        // UK clocks go forward on 2026-03-29.
        let key = DayKey(year: 2026, month: 3, day: 28)
        #expect(key.adding(days: 1, calendar: cal) == DayKey(year: 2026, month: 3, day: 29))
        #expect(key.adding(days: 2, calendar: cal) == DayKey(year: 2026, month: 3, day: 30))
        #expect(key.adding(days: 4, calendar: cal) == DayKey(year: 2026, month: 4, day: 1))
        #expect(key.days(to: DayKey(year: 2026, month: 4, day: 1), calendar: cal) == 4)
    }

    @Test func lateNightInstantBelongsToLocalDay() {
        // 23:30 in New York is already the next day in UTC.
        let ny = makeCalendar(timeZone: "America/New_York")
        let instant = date(2026, 10, 14, 23, 30, calendar: ny)
        #expect(DayKey(instant, calendar: ny) == DayKey(year: 2026, month: 10, day: 14))
        #expect(DayKey(instant, calendar: makeCalendar(timeZone: "UTC")) == DayKey(year: 2026, month: 10, day: 15))
    }

    @Test func weekStartsOnCalendarFirstWeekday() {
        // 2026-10-14 is a Wednesday.
        let wed = DayKey(year: 2026, month: 10, day: 14)
        #expect(wed.startOfWeek(calendar: makeCalendar(firstWeekday: 2)) == DayKey(year: 2026, month: 10, day: 12))
        #expect(wed.startOfWeek(calendar: makeCalendar(firstWeekday: 1)) == DayKey(year: 2026, month: 10, day: 11))
        let week = WeekInterval(containing: wed, calendar: cal)
        #expect(week.days(calendar: cal).count == 7)
        #expect(week.end == DayKey(year: 2026, month: 10, day: 18))
        #expect(week.previous(calendar: cal).start == DayKey(year: 2026, month: 10, day: 5))
    }
}

@Suite("Units")
struct UnitsTests {
    @Test func convertsBetweenKilogramsAndPounds() {
        #expect(abs(WeightUnit.pounds.fromKilograms(100) - 220.462) < 0.001)
        #expect(abs(WeightUnit.pounds.toKilograms(220.462_262_18) - 100) < 0.000_001)
        #expect(WeightUnit.kilograms.fromKilograms(81.4) == 81.4)
    }

    @Test func repeatedConversionDoesNotDrift() {
        var kg = 80.0
        for _ in 0..<1000 {
            kg = WeightUnit.pounds.toKilograms(WeightUnit.pounds.fromKilograms(kg))
        }
        #expect(abs(kg - 80) < 1e-9)
    }

    @Test func servingUnitsConvertWithinFamily() {
        #expect(abs(ServingUnit.ounce.convert(1, to: .gram)! - 28.3495) < 0.001)
        #expect(ServingUnit.gram.convert(100, to: .milliliter) == nil)
        #expect(ServingUnit.cup.convert(1, to: .milliliter) == 240)
        #expect(ServingUnit.piece.convert(2, to: .piece) == 2)
    }

    @Test func servingMath() {
        // Yogurt: 170 g per serving.
        #expect(ServingMath.servings(amount: 255, unit: .gram, servingSize: 170, servingUnit: .gram) == 1.5)
        #expect(ServingMath.servings(amount: 2, unit: .serving, servingSize: 170, servingUnit: .gram) == 2)
        #expect(ServingMath.servings(amount: 1, unit: .cup, servingSize: 170, servingUnit: .gram) == nil)
        #expect(ServingMath.amount(servings: 1.5, unit: .gram, servingSize: 170, servingUnit: .gram) == 255)
        #expect(ServingMath.loggableUnits(for: .gram) == [.serving, .gram, .ounce])
        #expect(ServingMath.loggableUnits(for: .slice) == [.serving, .slice])
    }

    @Test func roundingToPlates() {
        #expect(Rounding.round(81.3, toNearest: 2.5) == 82.5)
        #expect(Rounding.round(81.2, toNearest: 2.5) == 80)
        #expect(Rounding.round(1.2345, fractionDigits: 2) == 1.23)
    }
}

@Suite("Number parsing")
struct NumberParsingTests {
    let us = Locale(identifier: "en_US")
    let de = Locale(identifier: "de_DE")

    @Test func acceptsEitherDecimalSeparator() {
        #expect(NumberParsing.decimal(from: "81.4", locale: us) == 81.4)
        #expect(NumberParsing.decimal(from: "81,4", locale: us) == 81.4)
        #expect(NumberParsing.decimal(from: "81,4", locale: de) == 81.4)
        #expect(NumberParsing.decimal(from: " 81.4 ", locale: de) == 81.4)
    }

    @Test func understandsGrouping() {
        #expect(NumberParsing.decimal(from: "2,500", locale: us) == 2500)
        #expect(NumberParsing.decimal(from: "1,234.5", locale: us) == 1234.5)
        #expect(NumberParsing.decimal(from: "1.234,5", locale: de) == 1234.5)
        #expect(NumberParsing.decimal(from: "12.000", locale: de) == 12000)
        #expect(NumberParsing.decimal(from: "0,500", locale: us) == 0.5)
    }

    @Test func rejectsGarbage() {
        #expect(NumberParsing.decimal(from: "", locale: us) == nil)
        #expect(NumberParsing.decimal(from: "abc", locale: us) == nil)
        #expect(NumberParsing.decimal(from: "1.2.3", locale: us) == nil)
    }

    @Test func integersRejectFractions() {
        #expect(NumberParsing.integer(from: "8", locale: us) == 8)
        #expect(NumberParsing.integer(from: "10,000", locale: us) == 10000)
        #expect(NumberParsing.integer(from: "7.5", locale: us) == nil)
    }
}
