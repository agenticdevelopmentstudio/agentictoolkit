import Foundation

/// The wire instant — `yyyy-MM-dd'T'HH:mm:ss'Z'`, whole seconds, UTC — and the
/// `yyyy-MM-dd` day keys derived from it, written and read without a formatter.
///
/// One owner for a cross-process format: a daemon that compares instants as
/// fixed-width *strings* (sorting, run bounds, interval walks) is only
/// chronological while every writer produces the same width, so every writer
/// goes through here. Parsing tries the fixed-width fast path first — a
/// `DateFormatter` costs tens of microseconds to build and a daemon parsing
/// every activity stamp of a long session spent most of its CPU building them —
/// and falls back to ``TimestampParsing`` for every other shape, so what is
/// accepted is exactly what the shared parser accepts, plus SQLite's
/// millisecond form.
public enum UTCTimestamp {

    // MARK: - Writing

    /// Now, as a wire instant.
    public static func now() -> String {
        string(from: Date())
    }

    /// `date` as a wire instant. Fractions truncate, so an instant never reads
    /// later than it happened.
    public static func string(from date: Date) -> String {
        string(epochSeconds: Int(date.timeIntervalSince1970.rounded(.down)))
    }

    /// Whole epoch seconds as a wire instant.
    public static func string(epochSeconds seconds: Int) -> String {
        let (days, secondOfDay) = floorDivide(seconds, 86_400)
        let (year, month, day) = civil(fromDays: days)
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:%02dZ",
            year, month, day, secondOfDay / 3600, (secondOfDay % 3600) / 60, secondOfDay % 60
        )
    }

    /// The wire instant `days` whole days before `reference` — the lower
    /// bound a "recent" query sends.
    public static func string(daysAgo days: Int, from reference: Date = Date()) -> String {
        string(from: reference.addingTimeInterval(-TimeInterval(days) * 86_400))
    }

    /// The `yyyy-MM-dd` calendar day `date` falls on in `timeZone`.
    public static func day(of date: Date, in timeZone: TimeZone) -> String {
        day(epochSeconds: Int(date.timeIntervalSince1970.rounded(.down)), in: timeZone)
    }

    /// The `yyyy-MM-dd` calendar day whole epoch `seconds` fall on in `timeZone`.
    public static func day(epochSeconds seconds: Int, in timeZone: TimeZone) -> String {
        let instant = Date(timeIntervalSince1970: TimeInterval(seconds))
        let local = seconds + timeZone.secondsFromGMT(for: instant)
        let (year, month, day) = civil(fromDays: floorDivide(local, 86_400).quotient)
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    // MARK: - Reading

    /// Whole seconds since 1970 for any accepted shape, fractions truncated.
    public static func epochSeconds(_ text: String) -> Int? {
        if let fast = fastComponents(text) { return fast.seconds }
        guard let date = TimestampParsing.parse(text) else { return nil }
        return Int(date.timeIntervalSince1970.rounded(.down))
    }

    /// The instant `text` names, fraction included; nil if it doesn't parse.
    public static func date(from text: String) -> Date? {
        if let fast = fastComponents(text) {
            return Date(timeIntervalSince1970: TimeInterval(fast.seconds) + fast.fraction)
        }
        return TimestampParsing.parse(text)
    }

    /// Any accepted shape, rewritten as the wire instant — or nil if it doesn't
    /// parse. The one normalisation that makes stored instants comparable as
    /// strings (`.218Z` sorts before `Z` at the same second).
    public static func canonical(_ text: String) -> String? {
        epochSeconds(text).map { string(epochSeconds: $0) }
    }

    /// Whole seconds from `start` to `end`. Unparseable or backwards pairs are
    /// zero: a negative duration would silently subtract from a total.
    public static func seconds(from start: String, to end: String) -> Int {
        guard let startSeconds = epochSeconds(start), let endSeconds = epochSeconds(end) else { return 0 }
        return max(0, endSeconds - startSeconds)
    }

    /// `text` moved by `delta` whole seconds, as a wire instant; nil if it doesn't parse.
    public static func adding(_ delta: Int, to text: String) -> String? {
        epochSeconds(text).map { string(epochSeconds: $0 + delta) }
    }

    /// Parses the two fixed-width shapes that make up nearly every stored
    /// instant — `2026-09-22T10:00:00[.fff…]Z` and `2026-09-22 10:00:00[.SSS]`
    /// (SQLite's `datetime()`, UTC) — by hand. Anything else (offsets, odd
    /// widths, out-of-range fields) returns nil so the caller falls back to
    /// ``TimestampParsing``.
    public static func epochSeconds(fast text: String) -> Int? {
        fastComponents(text)?.seconds
    }

    private static func fastComponents(_ text: String) -> (seconds: Int, fraction: Double)? {
        let bytes = Array(text.utf8)
        guard bytes.count >= 19 else { return nil }
        func digits(_ start: Int, _ count: Int) -> Int? {
            var value = 0
            for index in start..<(start + count) {
                let byte = bytes[index]
                guard byte >= 48, byte <= 57 else { return nil }
                value = value * 10 + Int(byte - 48)
            }
            return value
        }
        let dash: UInt8 = 45, colon: UInt8 = 58, space: UInt8 = 32, letterT: UInt8 = 84, dot: UInt8 = 46
        guard bytes[4] == dash, bytes[7] == dash, bytes[13] == colon, bytes[16] == colon,
              let year = digits(0, 4), let month = digits(5, 2), let day = digits(8, 2),
              let hour = digits(11, 2), let minute = digits(14, 2), let second = digits(17, 2)
        else { return nil }

        // What may follow the seconds depends on the separator: the ISO form
        // needs `Z` (a fraction of any width first), the SQLite form takes no
        // zone and exactly three fraction digits.
        var tail = bytes[19...]
        switch bytes[10] {
        case letterT:
            guard tail.last == 90 else { return nil } // "Z"
            tail = tail.dropLast()
            if let first = tail.first {
                guard first == dot, tail.count >= 2 else { return nil }
            }
        case space:
            if !tail.isEmpty {
                guard tail.count == 4, tail.first == dot else { return nil }
            }
        default:
            return nil
        }
        var fraction = 0.0
        var scale = 0.1
        for byte in tail.dropFirst() {
            guard byte >= 48, byte <= 57 else { return nil }
            fraction += Double(byte - 48) * scale
            scale /= 10
        }

        guard (1...12).contains(month), day >= 1, day <= daysIn(month: month, year: year),
              hour < 24, minute < 60, second < 60 else { return nil }
        let seconds = days(fromCivil: year, month, day) * 86_400 + hour * 3600 + minute * 60 + second
        return (seconds, fraction)
    }

    // MARK: - Civil calendar

    private static func floorDivide(_ value: Int, _ divisor: Int) -> (quotient: Int, remainder: Int) {
        let quotient = value >= 0 ? value / divisor : -((-value + divisor - 1) / divisor)
        return (quotient, value - quotient * divisor)
    }

    private static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    /// Days since 1970-01-01 for a proleptic Gregorian date (Hinnant's
    /// `days_from_civil`).
    static func days(fromCivil year: Int, _ month: Int, _ day: Int) -> Int {
        let adjustedYear = month <= 2 ? year - 1 : year
        let era = (adjustedYear >= 0 ? adjustedYear : adjustedYear - 399) / 400
        let yearOfEra = adjustedYear - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// The inverse of `days(fromCivil:)` (Hinnant's `civil_from_days`).
    static func civil(fromDays days: Int) -> (year: Int, month: Int, day: Int) {
        let shifted = days + 719_468
        let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
        let dayOfEra = shifted - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthIndex = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthIndex + 2) / 5 + 1
        let month = monthIndex < 10 ? monthIndex + 3 : monthIndex - 9
        return (yearOfEra + era * 400 + (month <= 2 ? 1 : 0), month, day)
    }
}
