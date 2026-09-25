import Foundation

/// Renders integer hundredths as currency, and reads typed amounts back. The
/// only integer-to-string bridge for money — nothing else may reach for
/// `String(format: "$%.2f", …)`, which would need a `Double` to exist first.
///
/// The integer is always **hundredths of the currency's major unit** (see
/// `Money.cents`), whatever that currency's own minor unit is. Parsing
/// multiplies by 100 and display divides by 100 for every currency, so the two
/// agree for JPY (no minor unit) and KWD (three) as well as for USD.
public struct MoneyFormatter: Sendable {

    private let currency: String
    private let locale: Locale

    /// - Parameters:
    ///   - currency: ISO-4217 code used for the symbol.
    ///   - locale: decides symbol placement, grouping and the decimal separator.
    public init(currency: String = "USD", locale: Locale = .current) {
        self.currency = currency
        self.locale = locale
    }

    /// The amount with its currency symbol and grouping — for display.
    ///
    /// Always exactly two fraction digits. Letting the currency choose would
    /// round JPY to whole yen row by row while a total is formatted from the
    /// exact sum, so the rows would not add up to the total; and it would give
    /// KWD a third digit the stored value never had.
    public func string(cents: Int) -> String {
        let decimal = Decimal(cents) / Decimal(100)
        return decimal.formatted(
            .currency(code: currency).precision(.fractionLength(2)).locale(locale))
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

    /// Reads what someone typed. Accepts a currency symbol or code, grouping
    /// separators and either decimal separator, because a field that rejects
    /// `"$1,250.00"` pasted from an email is a field people stop using.
    ///
    /// Which of `.` and `,` is the decimal point is decided by the text, not
    /// assumed from the locale:
    /// - both present: the last one is the decimal point, the other groups;
    /// - one of them, more than once: it groups;
    /// - one of them, once: the locale's decimal separator is a decimal point;
    ///   the locale's grouping separator groups only when exactly three digits
    ///   follow it and a non-zero integer part precedes it (`"1,250"`), and is
    ///   otherwise a decimal point (`"150,50"` in en_US);
    /// - a separator the locale uses for neither, once, with exactly three
    ///   digits after it (`"1.250"` in fr_FR) could be either, and is refused.
    ///
    /// Returns nil — never a plausible-looking wrong number — for anything else:
    /// no digits at all (a half-typed `"-"` is not zero, and treating it as
    /// zero wipes the rate mid-keystroke), groups that are not three digits
    /// (`"1.2.5"`), a decimal point before a grouping separator, a sign after
    /// the digits, stray punctuation, or an amount too large for an `Int`.
    /// A leading `-` or `−` (U+2212) makes the amount negative.
    public func cents(parsing text: String) -> Int? {
        guard let parsed = Self.scan(text) else { return nil }
        guard let decimalIndex = decimalSeparatorIndex(in: parsed.separators, digits: parsed.digits) else {
            return nil
        }

        // Every separator other than the decimal point groups, and grouping is
        // only valid in threes, all before the decimal point.
        var integerDigits = ""
        var fractionDigits = ""
        let groupBoundaries = parsed.separators.enumerated().filter { $0.offset != decimalIndex }
        if let decimalIndex, groupBoundaries.contains(where: { $0.offset > decimalIndex }) {
            return nil
        }
        let decimalPosition = decimalIndex.map { parsed.separators[$0].position }
        let groupPositions = groupBoundaries.map(\.element.position)
        if !groupPositions.isEmpty {
            let integerEnd = decimalPosition ?? parsed.digits.count
            let cuts = groupPositions + [integerEnd]
            // The leading group holds one to three digits, like the rest.
            guard let first = cuts.first, (1...3).contains(first) else { return nil }
            for (start, end) in zip(cuts, cuts.dropFirst()) where end - start != 3 {
                return nil
            }
        }
        let digits = Array(parsed.digits)
        if let decimalPosition {
            integerDigits = String(digits[..<decimalPosition])
            fractionDigits = String(digits[decimalPosition...])
        } else {
            integerDigits = String(digits)
        }

        let normalized = (parsed.isNegative ? "-" : "")
            + (integerDigits.isEmpty ? "0" : integerDigits)
            + (fractionDigits.isEmpty ? "" : "." + fractionDigits)
        guard let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        // `rounded` before `NSDecimalNumber`: 150.555 is 15056 cents, and the
        // double path would make it 15055 often enough to be a bug report.
        var scaled = value * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        // `intValue` wraps silently past `Int`'s range; refuse instead.
        guard rounded >= Decimal(Int.min), rounded <= Decimal(Int.max) else { return nil }
        return NSDecimalNumber(decimal: rounded).intValue
    }

    // MARK: - Parsing internals

    private struct Separator {
        let character: Character
        /// How many digits precede it.
        let position: Int
    }

    private struct Scanned {
        var digits = ""
        var separators: [Separator] = []
        var isNegative = false
    }

    /// Splits text into its digits, the `.`/`,` separators between them, and
    /// a sign. Currency symbols, letters (a currency code) and spaces are
    /// ignored; any other character makes the text unreadable.
    private static func scan(_ text: String) -> Scanned? {
        var result = Scanned()
        for character in text {
            if character.isASCII, character.isNumber {
                result.digits.append(character)
            } else if character == "." || character == "," {
                result.separators.append(Separator(character: character, position: result.digits.count))
            } else if character == "-" || character == "\u{2212}" {
                // A sign belongs before the number, once.
                guard result.digits.isEmpty, result.separators.isEmpty, !result.isNegative else { return nil }
                result.isNegative = true
            } else if character == "+" {
                guard result.digits.isEmpty, result.separators.isEmpty else { return nil }
            } else if character.isWhitespace || character.isLetter || character.isCurrencySymbol
                        || character == "'" || character == "\u{2019}" {
                continue
            } else {
                return nil
            }
        }
        guard !result.digits.isEmpty else { return nil }
        // A separator with no digit after it ("150.") is a half-typed decimal;
        // one with no digit before it (".5") is a leading decimal point. Both
        // are fine; a separator at either end of a run of separators is not.
        for (lhs, rhs) in zip(result.separators, result.separators.dropFirst()) where lhs.position == rhs.position {
            return nil
        }
        return result
    }

    /// The index in `separators` of the decimal point: `.some(nil)` when there
    /// is none, `nil` when the text is ambiguous or malformed.
    private func decimalSeparatorIndex(in separators: [Separator], digits: String) -> Int?? {
        guard let last = separators.last else { return .some(nil) }
        let kinds = Set(separators.map(\.character))
        if kinds.count > 1 {
            // Both kinds: the last separator is the decimal point, and it must
            // be the only one of its kind.
            let decimalCount = separators.filter { $0.character == last.character }.count
            return decimalCount == 1 ? .some(separators.count - 1) : nil
        }
        if separators.count > 1 {
            // One kind, repeated: grouping only.
            return .some(nil)
        }
        let localeDecimal = locale.decimalSeparator?.first
        let localeGrouping = locale.groupingSeparator?.first
        let digitsAfter = digits.count - last.position
        let integerPart = digits.prefix(last.position)
        let couldGroup = digitsAfter == 3 && !integerPart.isEmpty && integerPart.contains { $0 != "0" }
        if last.character == localeDecimal { return .some(0) }
        if last.character == localeGrouping { return couldGroup ? .some(nil) : .some(0) }
        // Neither of the locale's separators: a decimal point unless it could
        // just as well be grouping, in which case guessing is how a rate ends
        // up a thousand times too large.
        return couldGroup ? nil : .some(0)
    }
}

private extension Character {
    /// Unicode general category Sc: $, €, £, ¥, ₹ and the rest.
    var isCurrencySymbol: Bool {
        unicodeScalars.allSatisfy { $0.properties.generalCategory == .currencySymbol }
    }
}
