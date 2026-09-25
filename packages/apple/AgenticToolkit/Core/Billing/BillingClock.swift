import Foundation

/// Local-day bucketing for billing.
///
/// Billing's day boundary is *not* UTC: an entry belongs to the local day in
/// the zone the work happened in, which is stored per segment. Every other
/// instant operation — parsing, formatting, canonicalising, arithmetic — is
/// ``UTCTimestamp``'s; this holds only the one rule that is billing's own.
public enum BillingClock {

    // swiftlint:disable identifier_name
    /// The calendar day `utc` falls on *in `tz`*. An empty or unrecognised zone
    /// falls back to UTC — deliberately not the host's current zone, which would
    /// make the same row bucket differently depending on where it is read.
    public static func localDay(utc: String, tz: String) -> String {
        guard let date = UTCTimestamp.date(from: utc) else { return "" }
        let zone = TimeZone(identifier: tz) ?? TimeZone(identifier: "UTC") ?? .current
        return UTCTimestamp.day(of: date, in: zone)
    }
    // swiftlint:enable identifier_name
}
