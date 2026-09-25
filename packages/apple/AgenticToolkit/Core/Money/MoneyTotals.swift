import Foundation

/// A running total kept per currency: cents in each ISO-4217 code, never
/// converted, never mixed.
///
/// `Money.sum` traps on mixed currencies and `MoneyFormatter` formats one
/// currency, so anything that totals amounts across clients billed in
/// different currencies needs this bucket. The wording of the result is
/// ``description``: each currency formatted on its own, in code order, joined
/// with `" + "`.
public struct MoneyTotals: Equatable, Sendable {

    /// Cents by ISO-4217 code. Only codes that were added appear.
    public private(set) var cents: [String: Int] = [:]

    public init() {}

    /// Totals of `amounts`, bucketed by their own currencies.
    public init(_ amounts: some Sequence<Money>) {
        for amount in amounts { add(amount) }
    }

    /// Adds `cents` hundredths in `currency`.
    public mutating func add(cents: Int, currency: String) {
        self.cents[currency, default: 0] += cents
    }

    public mutating func add(_ amount: Money) {
        add(cents: amount.cents, currency: amount.currency)
    }

    /// Every other total's buckets added to this one's.
    public mutating func add(_ other: MoneyTotals) {
        for (currency, amount) in other.cents { add(cents: amount, currency: currency) }
    }

    /// Whether nothing has been added.
    public var isEmpty: Bool { cents.isEmpty }

    /// The currencies held, in code order.
    public var currencies: [String] { cents.keys.sorted() }

    /// Each currency's total as a `Money`, in code order.
    public var amounts: [Money] {
        currencies.map { Money(cents: cents[$0] ?? 0, currency: $0) }
    }

    /// `"$250.00 + €40.00"`: each currency formatted by `MoneyFormatter`, in
    /// code order, joined with `" + "`. Empty when nothing was added.
    public var description: String {
        currencies
            .map { MoneyFormatter(currency: $0).string(cents: cents[$0] ?? 0) }
            .joined(separator: " + ")
    }
}
