import Foundation

/// Turns raw tracked seconds into billed seconds.
///
/// Applied **once**, at entry level. Rounding each segment and summing would
/// bill five five-minute bursts as 75 minutes instead of 30 — see
/// `testRoundingOncePerEntryNotPerSegment`. The arithmetic is
/// ``IncrementRounding``'s; this only maps billing's stored knobs onto it.
public enum BillingRounding {

    /// `rawSeconds` rounded to a whole number of `roundingMinutes` increments.
    ///
    /// - `roundingMinutes <= 0` means *no rounding* — the raw seconds pass
    ///   through. It does not mean "round to zero".
    /// - `mode` is `"up"` (always to the next increment) or `"nearest"`
    ///   (half-up). Anything else behaves as `"up"`, the default, rather than
    ///   billing nothing.
    /// - Zero or negative raw seconds bill zero: a session with no time should
    ///   not acquire a minimum increment out of nowhere.
    public static func billedSeconds(rawSeconds: Int, roundingMinutes: Int, mode: String) -> Int {
        let rule = IncrementRounding(rawValue: mode) ?? .upward
        return rule.round(rawSeconds, toIncrement: roundingMinutes > 0 ? roundingMinutes * 60 : 0)
    }
}
