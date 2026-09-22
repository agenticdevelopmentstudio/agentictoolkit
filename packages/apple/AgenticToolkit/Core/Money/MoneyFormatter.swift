import Foundation

/// Renders integer minor units as currency. The only integer-to-string bridge
/// in the billing path — nothing else may reach for `String(format: "$%.2f", …)`,
/// which would need a `Double` to exist first.
public struct MoneyFormatter: Sendable {

    private let currency: String
    private let locale: Locale

    public init(currency: String = "USD", locale: Locale = .current) {
        self.currency = currency
        self.locale = locale
    }

    public func string(cents: Int) -> String {
        let decimal = Decimal(cents) / Decimal(100)
        return decimal.formatted(.currency(code: currency).locale(locale))
    }

    /// Follows the amount's own currency, not the formatter's default.
    public func string(_ money: Money) -> String {
        MoneyFormatter(currency: money.currency, locale: locale).string(cents: money.cents)
    }

    /// A plain editable amount — `"150"`, `"150.50"` — with no currency symbol
    /// and no grouping. What a text field shows while someone is typing a rate
    /// into it; `string(cents:)` is for display, where the symbol belongs.
    public func editableString(cents: Int) -> String {
        let decimal = Decimal(cents) / Decimal(100)
        return decimal.formatted(
            .number.precision(.fractionLength(2)).grouping(.never).locale(locale))
    }

    /// Reads what someone typed. Accepts a currency symbol, grouping
    /// separators and either decimal separator, because a field that rejects
    /// `"$1,250.00"` pasted from an email is a field people stop using.
    /// Returns nil for anything with no digits at all — a half-typed `"-"` is
    /// not zero, and treating it as zero wipes the rate mid-keystroke.
    public func cents(parsing text: String) -> Int? {
        // `.first`, not `Character(_:)`: that initializer traps on a
        // multi-character string, and nothing guarantees a locale's separator
        // is one grapheme.
        let separator = (locale.decimalSeparator ?? ".").first ?? "."
        var kept = ""
        for character in text where character.isNumber
            || character == separator
            || (character == "-" && kept.isEmpty) {
            kept.append(character == separator ? "." : character)
        }
        guard kept.contains(where: \.isNumber), let value = Decimal(string: kept) else {
            return nil
        }
        // `rounded` before `NSDecimalNumber`: 150.555 is 15056 cents, and the
        // double path would make it 15055 often enough to be a bug report.
        var scaled = value * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }
}
