import XCTest
@testable import AgenticToolkitCore

final class MoneyTotalsTests: XCTestCase {

    func testKeepsEachCurrencyApart() {
        var totals = MoneyTotals()
        XCTAssertTrue(totals.isEmpty)
        totals.add(cents: 25_000, currency: "USD")
        totals.add(cents: 4_000, currency: "EUR")
        totals.add(cents: 500, currency: "USD")

        XCTAssertEqual(totals.cents, ["USD": 25_500, "EUR": 4_000])
        XCTAssertEqual(totals.currencies, ["EUR", "USD"])
    }

    func testAddingAnotherTotalMergesItsBuckets() {
        var first = MoneyTotals()
        first.add(cents: 100, currency: "USD")
        var second = MoneyTotals()
        second.add(cents: 50, currency: "USD")
        second.add(cents: 70, currency: "GBP")
        first.add(second)
        XCTAssertEqual(first.cents, ["USD": 150, "GBP": 70])
    }

    func testTheDescriptionJoinsEachCurrencyInCodeOrder() {
        var totals = MoneyTotals()
        XCTAssertEqual(totals.description, "")
        totals.add(cents: 100, currency: "USD")
        totals.add(cents: 100, currency: "EUR")
        let parts = totals.description.components(separatedBy: " + ")
        XCTAssertEqual(parts.count, 2)
    }
}

final class CurrencyCodeTests: XCTestCase {

    func testNormalizesTheShapeOnly() {
        XCTAssertEqual(CurrencyCode.normalized(" usd "), "USD")
        XCTAssertEqual(CurrencyCode.normalized("EUR"), "EUR")
        XCTAssertNil(CurrencyCode.normalized("U5D"))
        XCTAssertNil(CurrencyCode.normalized("US"))
        XCTAssertNil(CurrencyCode.normalized("EURO"))
        XCTAssertNil(CurrencyCode.normalized(""))
    }
}

final class IncrementRoundingTests: XCTestCase {

    func testUpwardAlwaysTakesTheNextIncrement() {
        XCTAssertEqual(IncrementRounding.upward.round(1, toIncrement: 900), 900)
        XCTAssertEqual(IncrementRounding.upward.round(900, toIncrement: 900), 900)
        XCTAssertEqual(IncrementRounding.upward.round(901, toIncrement: 900), 1_800)
    }

    func testNearestRoundsHalfUp() {
        XCTAssertEqual(IncrementRounding.nearest.round(450, toIncrement: 900), 900)
        XCTAssertEqual(IncrementRounding.nearest.round(449, toIncrement: 900), 0)
    }

    func testNoIncrementMeansNoRoundingAndNothingStaysNothing() {
        XCTAssertEqual(IncrementRounding.upward.round(1_234, toIncrement: 0), 1_234)
        XCTAssertEqual(IncrementRounding.upward.round(0, toIncrement: 900), 0)
        XCTAssertEqual(IncrementRounding.upward.round(-5, toIncrement: 900), 0)
    }

    func testTheStoredSpellingIsStable() {
        XCTAssertEqual(IncrementRounding(rawValue: "up"), .upward)
        XCTAssertEqual(IncrementRounding(rawValue: "nearest"), .nearest)
    }
}
