import Foundation

/// An amount of money as integer minor units. There is no `Double` anywhere in
/// this type: a rate of $0.10/hr applied to 3 minutes is exactly 0.5 cents, and
/// a binary float cannot hold the tenths it takes to get there. Every total the
/// billing feature shows is a sum of these.
public struct Money: Codable, Sendable, Equatable, Comparable {

    /// Minor units — cents for USD, whatever the currency's minor unit is
    /// otherwise. Never a fraction.
    public let cents: Int

    /// ISO-4217 code. Carried so a total can refuse to mix currencies; no
    /// conversion is performed anywhere.
    public let currency: String

    public init(cents: Int, currency: String = "USD") {
        self.cents = cents
        self.currency = currency
    }

    /// Whether two amounts can be added, subtracted or compared. There is no
    /// conversion anywhere, so the answer is only ever "same currency".
    public func isSameCurrency(as other: Money) -> Bool {
        currency == other.currency
    }

    /// Ordering across currencies is meaningless — €100 is not "less than"
    /// $101 — so mixing them is a programmer error, not a false.
    public static func < (lhs: Money, rhs: Money) -> Bool {
        precondition(lhs.isSameCurrency(as: rhs), "Money: comparing \(lhs.currency) with \(rhs.currency)")
        return lhs.cents < rhs.cents
    }

    /// Adding across currencies would silently relabel one amount as the
    /// other's currency; it traps instead.
    public static func + (lhs: Money, rhs: Money) -> Money {
        precondition(lhs.isSameCurrency(as: rhs), "Money: adding \(rhs.currency) to \(lhs.currency)")
        return Money(cents: lhs.cents + rhs.cents, currency: lhs.currency)
    }

    public static func - (lhs: Money, rhs: Money) -> Money {
        precondition(lhs.isSameCurrency(as: rhs), "Money: subtracting \(rhs.currency) from \(lhs.currency)")
        return Money(cents: lhs.cents - rhs.cents, currency: lhs.currency)
    }

    /// Sums same-currency amounts through `+`, so a mixed list traps rather
    /// than adding euros to dollars. An empty list is zero in `currency`
    /// rather than a nil every call site has to unwrap.
    public static func sum(_ amounts: [Money], currency: String = "USD") -> Money {
        guard let first = amounts.first else { return Money(cents: 0, currency: currency) }
        return amounts.dropFirst().reduce(first, +)
    }

    /// `seconds × rateCents / 3600`, rounded half-up, in integers throughout.
    ///
    /// Half-up rather than banker's rounding because that is what a person
    /// checking the arithmetic by hand expects, and these amounts are not
    /// numerous enough for the statistical bias banker's rounding exists to
    /// remove to arise.
    public static func amountCents(seconds: Int, rateCents: Int) -> Int {
        guard seconds > 0, rateCents != 0 else { return 0 }
        let numerator = seconds * rateCents
        let sign = numerator < 0 ? -1 : 1
        let magnitude = abs(numerator)
        return sign * ((magnitude * 2 + 3600) / 7200)
    }
}
