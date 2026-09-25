import XCTest
@testable import AgenticToolkitCore

final class MoneyTests: XCTestCase {

    func testAmountCentsIsExactForWholeHours() {
        XCTAssertEqual(Money.amountCents(seconds: 3600, rateCents: 12_500), 12_500)
        XCTAssertEqual(Money.amountCents(seconds: 7200, rateCents: 12_500), 25_000)
    }

    /// 15 minutes at $125/hr is exactly $31.25 — no float drift.
    func testAmountCentsForAQuarterHour() {
        XCTAssertEqual(Money.amountCents(seconds: 900, rateCents: 12_500), 3_125)
    }

    /// 1 second at $100/hr is 10000/3600 = 2.777… cents → 3 (half-up).
    func testAmountCentsRoundsHalfUp() {
        XCTAssertEqual(Money.amountCents(seconds: 1, rateCents: 10_000), 3)
        // Exactly .5: 1800s at 1 cent/hr = 0.5 → 1.
        XCTAssertEqual(Money.amountCents(seconds: 1800, rateCents: 1), 1)
        // Just under .5: 1799s at 1 cent/hr = 0.4997 → 0.
        XCTAssertEqual(Money.amountCents(seconds: 1799, rateCents: 1), 0)
    }

    /// A negative rate (e.g. a credit or refund) keeps its sign through the
    /// arithmetic rather than being clamped to zero like negative seconds are.
    func testAmountCentsPreservesNegativeRateSign() {
        XCTAssertEqual(Money.amountCents(seconds: 3600, rateCents: -12_500), -12_500)
        // Half-up boundary on the negative side: 1800s at -1 cent/hr = -0.5 → -1.
        XCTAssertEqual(Money.amountCents(seconds: 1800, rateCents: -1), -1)
    }

    func testAmountCentsIsZeroForAZeroRate() {
        XCTAssertEqual(Money.amountCents(seconds: 86_400, rateCents: 0), 0)
    }

    func testAmountCentsIsZeroForZeroOrNegativeSeconds() {
        XCTAssertEqual(Money.amountCents(seconds: 0, rateCents: 12_500), 0)
        XCTAssertEqual(Money.amountCents(seconds: -60, rateCents: 12_500), 0)
    }

    func testSumAddsSameCurrency() {
        let total = Money.sum([Money(cents: 100), Money(cents: 250), Money(cents: 5)])
        XCTAssertEqual(total, Money(cents: 355))
    }

    /// Summing an empty list is zero in the caller's currency, not a crash.
    func testSumOfNothingIsZero() {
        XCTAssertEqual(Money.sum([], currency: "EUR"), Money(cents: 0, currency: "EUR"))
    }

    func testComparableOrdersByCents() {
        XCTAssertLessThan(Money(cents: 99), Money(cents: 100))
    }

    func testSubtractionKeepsTheCurrency() {
        let difference = Money(cents: 1_000, currency: "EUR") - Money(cents: 250, currency: "EUR")
        XCTAssertEqual(difference, Money(cents: 750, currency: "EUR"))
        XCTAssertEqual(Money(cents: 100) - Money(cents: 300), Money(cents: -200))
    }

    /// `+`, `-`, `<` and `sum` trap on mixed currencies; this is the check
    /// they share, so it is what a test can reach without crashing the run.
    func testMixedCurrenciesAreNotTheSameCurrency() {
        XCTAssertTrue(Money(cents: 1, currency: "USD").isSameCurrency(as: Money(cents: 2, currency: "USD")))
        XCTAssertFalse(Money(cents: 1, currency: "USD").isSameCurrency(as: Money(cents: 1, currency: "EUR")))
    }

    func testSumKeepsTheAmountsCurrency() {
        let total = Money.sum([Money(cents: 100, currency: "GBP"), Money(cents: 5, currency: "GBP")])
        XCTAssertEqual(total, Money(cents: 105, currency: "GBP"))
    }

    func testFormatterRendersIntegerCents() {
        let formatter = MoneyFormatter(currency: "USD", locale: Locale(identifier: "en_US"))
        XCTAssertEqual(formatter.string(cents: 0), "$0.00")
        XCTAssertEqual(formatter.string(cents: 3_125), "$31.25")
        XCTAssertEqual(formatter.string(cents: 123_456_789), "$1,234,567.89")
    }

    func testFormatterFollowsTheMoneysOwnCurrency() {
        let formatter = MoneyFormatter(currency: "USD", locale: Locale(identifier: "en_US"))
        XCTAssertTrue(formatter.string(Money(cents: 500, currency: "EUR")).contains("5.00"))
    }

    func testEditableStringHasNoSymbolAndNoGrouping() {
        let formatter = MoneyFormatter(currency: "USD", locale: Locale(identifier: "en_US"))
        XCTAssertEqual(formatter.editableString(cents: 3_125), "31.25")
        XCTAssertEqual(formatter.editableString(cents: 123_456_789), "1234567.89")
        XCTAssertEqual(formatter.editableString(cents: 0), "0.00")
    }

    func testParsingAcceptsWhatPeopleActuallyType() {
        let formatter = MoneyFormatter(currency: "USD", locale: Locale(identifier: "en_US"))
        XCTAssertEqual(formatter.cents(parsing: "150"), 15_000)
        XCTAssertEqual(formatter.cents(parsing: "150.5"), 15_050)
        XCTAssertEqual(formatter.cents(parsing: "$1,250.00"), 125_000)
        XCTAssertEqual(formatter.cents(parsing: " 31.25 "), 3_125)
    }

    func testParsingRoundsHalfUpRatherThanTruncating() {
        let formatter = MoneyFormatter(currency: "USD", locale: Locale(identifier: "en_US"))
        XCTAssertEqual(formatter.cents(parsing: "150.555"), 15_056)
        XCTAssertEqual(formatter.cents(parsing: "150.554"), 15_055)
    }

    func testParsingRejectsTextWithNoDigits() {
        let formatter = MoneyFormatter(currency: "USD", locale: Locale(identifier: "en_US"))
        XCTAssertNil(formatter.cents(parsing: ""))
        XCTAssertNil(formatter.cents(parsing: "-"))
        XCTAssertNil(formatter.cents(parsing: "$"))
    }

    func testParsingFollowsTheLocalesDecimalSeparator() {
        let formatter = MoneyFormatter(currency: "EUR", locale: Locale(identifier: "de_DE"))
        XCTAssertEqual(formatter.cents(parsing: "150,50"), 15_050)
    }

    // MARK: - Review V9-a / V9-b / V9-c

    private let enUS = MoneyFormatter(currency: "USD", locale: Locale(identifier: "en_US"))
    private let deDE = MoneyFormatter(currency: "EUR", locale: Locale(identifier: "de_DE"))

    /// V9-a: a European-typed rate in an en_US field is 150.50, not 15050.00.
    func testACommaDecimalIsHonouredInAnEnglishLocale() {
        XCTAssertEqual(enUS.cents(parsing: "150,50"), 15_050)
        XCTAssertEqual(enUS.cents(parsing: "1,250"), 125_000,
                       "three digits after the locale's grouping separator group")
        XCTAssertEqual(enUS.cents(parsing: "1,250.00"), 125_000)
    }

    /// V9-a: a US-typed amount in a de_DE field is not scaled by 100 or 1/1000.
    func testADotDecimalIsHonouredInAGermanLocale() {
        XCTAssertEqual(deDE.cents(parsing: "$1,250.00"), 125_000)
        XCTAssertEqual(deDE.cents(parsing: "150.50"), 15_050)
        XCTAssertEqual(deDE.cents(parsing: "1.250,00"), 125_000)
        XCTAssertEqual(deDE.cents(parsing: "1.250"), 125_000)
    }

    /// V9-a: a separator the locale uses for neither job, once, followed by
    /// three digits, could be either — refuse rather than guess.
    func testAnAmbiguousSeparatorIsRefused() {
        let frFR = MoneyFormatter(currency: "EUR", locale: Locale(identifier: "fr_FR"))
        XCTAssertNil(frFR.cents(parsing: "1.250"))
        XCTAssertEqual(frFR.cents(parsing: "1.25"), 125)
    }

    /// V9-b: malformed text is nil, never a prefix of it.
    func testMalformedAmountsAreRefused() {
        XCTAssertNil(enUS.cents(parsing: "1.2.5"))
        XCTAssertNil(enUS.cents(parsing: "15..50"))
        XCTAssertNil(enUS.cents(parsing: "12,34,567"))
        XCTAssertNil(enUS.cents(parsing: "1,250.00.5"))
        XCTAssertNil(enUS.cents(parsing: "1.250,00.5"))
        XCTAssertNil(enUS.cents(parsing: "15-0"))
        XCTAssertNil(enUS.cents(parsing: "15/0"))
    }

    /// V9-b: the typographic minus is a minus, not dropped.
    func testUnicodeMinusIsNegative() {
        XCTAssertEqual(enUS.cents(parsing: "\u{2212}5"), -500)
        XCTAssertEqual(enUS.cents(parsing: "-5"), -500)
    }

    /// V9-b: past Int's range is nil, not a wrapped number.
    func testAnOverflowingAmountIsRefused() {
        XCTAssertNil(enUS.cents(parsing: "99999999999999999999"))
        XCTAssertNil(enUS.cents(parsing: "-99999999999999999999"))
    }

    /// V9-c: displayed rows add up to the displayed total in a currency with
    /// no minor unit — 1050 + 500 hundredths of a yen is ¥15.50, and each row
    /// shows its own two decimals rather than rounding to whole yen.
    func testYenRowsShowTheSameScaleAsTheirTotal() {
        let jpy = MoneyFormatter(currency: "JPY", locale: Locale(identifier: "en_US"))
        XCTAssertTrue(jpy.string(cents: 1_050).contains("10.50"), jpy.string(cents: 1_050))
        XCTAssertTrue(jpy.string(cents: 500).contains("5.00"), jpy.string(cents: 500))
        XCTAssertTrue(jpy.string(cents: 1_550).contains("15.50"), jpy.string(cents: 1_550))
    }

    /// V9-c: KWD has a three-digit minor unit; the stored hundredths never had
    /// a third digit, so display does not invent one.
    func testDinarShowsTwoDecimals() {
        let kwd = MoneyFormatter(currency: "KWD", locale: Locale(identifier: "en_US"))
        let text = kwd.string(cents: 3_125)
        XCTAssertTrue(text.contains("31.25"), text)
        XCTAssertFalse(text.contains("31.250"), text)
    }
}
