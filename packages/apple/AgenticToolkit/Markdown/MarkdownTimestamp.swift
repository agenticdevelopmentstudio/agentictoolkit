import Foundation

/// The one place a date becomes a column value and back.
///
/// adh stores `timestamptz` and serialises ISO-8601 UTC; SQLite has no date
/// type, so a mirrored row is text. Two formatters that disagree by a `Z` or a
/// fractional second produce rows that sort wrongly against each other, and the
/// bug shows up as a document list in the wrong order rather than as an error —
/// so there is exactly one formatter and everything goes through it.
public enum MarkdownTimestamp {

    /// Writes with milliseconds, so two edits inside the same second still
    /// order. `withInternetDateTime` supplies the explicit `Z`.
    ///
    /// `ISO8601DateFormatter` isn't `Sendable`, but a formatter that is
    /// configured once at init and only ever read from (`string(from:)`,
    /// `date(from:)`) afterward has no mutable state a concurrent caller can
    /// race on.
    nonisolated(unsafe) private static let writer: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    /// A server row may or may not carry fractional seconds, so reading tries
    /// both. Writing never has that ambiguity.
    nonisolated(unsafe) private static let readerWithoutFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    public static func string(_ date: Date) -> String {
        writer.string(from: date)
    }

    public static func date(_ text: String) -> Date? {
        writer.date(from: text) ?? readerWithoutFraction.date(from: text)
    }
}
