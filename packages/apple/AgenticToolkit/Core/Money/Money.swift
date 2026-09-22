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

    public static func < (lhs: Money, rhs: Money) -> Bool {
        lhs.cents < rhs.cents
    }

    public static func + (lhs: Money, rhs: Money) -> Money {
        Money(cents: lhs.cents + rhs.cents, currency: lhs.currency)
    }

    /// Sums same-currency amounts. An empty list is zero in `currency` rather
    /// than a nil every call site has to unwrap.
    public static func sum(_ amounts: [Money], currency: String = "USD") -> Money {
        Money(
            cents: amounts.reduce(0) { $0 + $1.cents },
            currency: amounts.first?.currency ?? currency
        )
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
