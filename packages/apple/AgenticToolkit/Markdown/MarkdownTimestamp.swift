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

    /// Both formatters, then one repair pass.
    ///
    /// adh's columns are Postgres `timestamp` and its OpenAPI declares them as
    /// bare strings with no format, so a pulled row can legitimately arrive as
    /// `2026-04-13 16:18:07.798+00` — a space where ISO-8601 wants `T`, a
    /// two-digit offset where it wants four, and a fraction of any length.
    /// `ISO8601DateFormatter` rejects all three. Reading such a value as `nil`
    /// is what put an unparseable stamp on disk in the first place
    /// (`MarkdownProjection.normalizedTimestamp` stores verbatim what it cannot
    /// parse), and a stamp with `' '` at index 10 sorts before every normalised
    /// one under `ORDER BY updated_at` — the exact inversion normalisation
    /// exists to prevent.
    public static func date(_ text: String) -> Date? {
        if let date = parse(text) { return date }
        guard let repaired = isoForm(of: text) else { return nil }
        return parse(repaired)
    }

    private static func parse(_ text: String) -> Date? {
        writer.date(from: text) ?? readerWithoutFraction.date(from: text)
    }

    /// `^(date)[ T](time)(.fraction)?(zone)?$`, with the zone in any of the
    /// spellings Postgres emits.
    private static let postgresForm: NSRegularExpression = {
        // The pattern is a literal, so a throw here is a programmer error.
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: "^(\\d{4}-\\d{2}-\\d{2})[ T](\\d{2}:\\d{2}:\\d{2})"
                + "(?:\\.(\\d{1,9}))?(?:[Zz]|([+-]\\d{2}):?(\\d{2})?)?$",
            options: [])
    }()

    /// The same instant rewritten the way `writer` spells it, or `nil` when the
    /// text is not a timestamp at all.
    ///
    /// A missing offset is read as UTC rather than local time: every other
    /// value in these columns is UTC, and guessing the reader's zone would make
    /// the same row parse to a different instant on two machines.
    private static func isoForm(of text: String) -> String? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = postgresForm.firstMatch(in: text, options: [], range: range) else {
            return nil
        }
        func group(_ index: Int) -> String? {
            guard let captured = Range(match.range(at: index), in: text) else { return nil }
            return String(text[captured])
        }
        guard let day = group(1), let time = group(2) else { return nil }
        // Milliseconds, padded or truncated: `withFractionalSeconds` reads
        // exactly three digits, and anything finer than a millisecond is below
        // what `string(_:)` can write back anyway.
        let fraction = group(3).map { "." + $0.padding(toLength: 3, withPad: "0", startingAt: 0) } ?? ""
        let zone = group(4).map { hours in hours + ":" + (group(5) ?? "00") } ?? "Z"
        return day + "T" + time + fraction + zone
    }
}
