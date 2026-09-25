import Foundation

/// Rounds a whole quantity to a whole number of increments — billed seconds to
/// fifteen-minute blocks, say — in integers throughout.
///
/// The other half of the arithmetic `Money.amountCents(seconds:rateCents:)`
/// does: that turns seconds into money, this decides which seconds count.
public enum IncrementRounding: String, Sendable, CaseIterable {
    /// Always to the next increment: 1 second of a 15-minute block bills 15.
    case upward = "up"
    /// To the closest increment, half-up: 7m30s of 15 bills 15, 7m29s bills 0.
    case nearest

    /// `value` rounded to a whole number of `increment`s.
    ///
    /// - An `increment` of zero or less means *no rounding*: `value` passes
    ///   through. It never means "round to zero".
    /// - A `value` of zero or less rounds to zero, so nothing never acquires a
    ///   minimum increment out of nowhere.
    public func round(_ value: Int, toIncrement increment: Int) -> Int {
        guard value > 0 else { return 0 }
        guard increment > 0 else { return value }
        switch self {
        case .upward: return ((value + increment - 1) / increment) * increment
        case .nearest: return ((value * 2 + increment) / (increment * 2)) * increment
        }
    }
}
