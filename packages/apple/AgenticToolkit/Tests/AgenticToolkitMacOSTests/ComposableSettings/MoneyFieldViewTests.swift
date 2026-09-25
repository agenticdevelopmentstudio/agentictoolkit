import AppKit
import Testing
import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// A money row: what text it accepts, what it writes, and what it shows.
@Suite(.serialized)
@MainActor
struct MoneyFieldViewTests {

    private typealias Field = ComposableSettings.MoneyFieldView
    private let usd = MoneyFormatter(currency: "USD", locale: Locale(identifier: "en_US"))

    @Test func parseAcceptsAnAmountInRange() {
        #expect(Field.parse("150", formatter: usd, range: 0...100_000, allowsBlank: false) == .some(15_000))
        #expect(Field.parse(" 1.5 ", formatter: usd, range: 0...100_000, allowsBlank: false) == .some(150))
    }

    @Test func parseRefusesTextThatIsNotAnAmountOrOutOfRange() {
        #expect(Field.parse("abc", formatter: usd, range: 0...100_000, allowsBlank: false) == nil)
        #expect(Field.parse("5000", formatter: usd, range: 0...100_000, allowsBlank: false) == nil)
    }

    @Test func aBlankIsNilOnlyWhenAllowed() {
        #expect(Field.parse("  ", formatter: usd, range: 0...100_000, allowsBlank: true) == .some(nil))
        #expect(Field.parse("", formatter: usd, range: 0...100_000, allowsBlank: false) == nil)
    }

    @Test func showsTheStoredAmountAndItsFallback() {
        var stored: Int? = 12_000
        let usd = self.usd
        let field = Field(title: "Rate", range: 0...100_000, allowsBlank: true,
                          formatter: { usd }, get: { stored }, set: { stored = $0 })
        #expect(field.textField.stringValue == usd.editableString(cents: 12_000))

        field.placeholderCents = 9_000
        #expect(field.textField.placeholderString == usd.editableString(cents: 9_000))

        stored = nil
        field.refresh()
        #expect(field.textField.stringValue == "", "no amount of its own: the fallback shows as the placeholder")
    }
}
