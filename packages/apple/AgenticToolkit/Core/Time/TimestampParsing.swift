import Foundation

/// The one timestamp parser for the whole system. Timestamps arrive in
/// three shapes across a daemon, its app and its CLI, and every subsystem needs to accept
/// all of them:
///
/// - ISO8601 with fractional seconds — `2026-04-14T10:00:00.123Z` (some Claude
///   versions' hook/JSONL output),
/// - plain ISO8601 — `2026-04-14T10:00:00Z` (other versions),
/// - SQLite `datetime()` output — `2026-04-14 10:00:00` (UTC, space-separated): what
///   the DB stores (`last_activity_at`, event timestamps normalized through
///   `datetime()`), and the shape `ISO8601DateFormatter` silently *cannot* parse.
///
/// Before this existed, ~6 sites hand-rolled a "try fractional, fall back to plain"
/// parser; most omitted the SQLite shape, so they silently failed on stored DB
/// timestamps (the bug behind a monitor's idle minutes always reading 0). Parsing
/// through here fixes that class of bug in one place.
public enum TimestampParsing {

    /// Parse a timestamp in any of the three supported shapes; `nil` if none match
    /// (including empty input).
    public static func parse(_ text: String) -> Date? {
        guard !text.isEmpty else { return nil }
        if let date = isoFractional.date(from: text) { return date }
        if let date = isoPlain.date(from: text) { return date }
        return sqliteDateTime.date(from: text)
    }

    // ISO8601DateFormatter is thread-safe for parsing once `formatOptions` are set, but
    // Foundation doesn't mark it Sendable; `nonisolated(unsafe)` opts these shared,
    // never-mutated instances out of Swift 6's concurrency checks.
    nonisolated(unsafe) private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let isoPlain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// SQLite `datetime()` output: UTC, space-separated, no zone marker.
    /// (`DateFormatter` is `Sendable`, unlike `ISO8601DateFormatter` above.)
    private static let sqliteDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}
