import Foundation

/// Times of day the way a viewer reads and types them: a 12-hour clock where
/// their locale uses one, a 24-hour clock where it doesn't, the month and day
/// in the locale's own order, and either clock accepted when typed.
///
/// Every formatter is built once per pattern, zone and locale and reused. A
/// table of timestamps renders hundreds of rows per refresh, and a
/// `DateFormatter` costs tens of microseconds to build against well under one
/// to reuse. The cache is lock-guarded, so any thread may format.
///
/// For display and entry only. The wire form every process compares as a
/// string is ``UTCTimestamp``'s, never this one.
public enum LocalTimeText {

    /// A time of day typed without a date.
    public struct Clock: Equatable, Sendable {
        public let hour: Int
        public let minute: Int

        public init(hour: Int, minute: Int) {
            self.hour = hour
            self.minute = minute
        }
    }

    /// `2:05 PM` in a 12-hour locale, `14:05` in a 24-hour one.
    public static func clock(_ date: Date, timeZone: TimeZone, locale: Locale) -> String {
        formatter(clockPattern(locale), timeZone: timeZone, locale: locale).string(from: date)
    }

    /// `Sep 24, 2:05 PM` / `24 Sep, 14:05`: the month and day in the locale's
    /// order, then the clock.
    public static func dayAndClock(_ date: Date, timeZone: TimeZone, locale: Locale) -> String {
        let day = DateFormatter.dateFormat(fromTemplate: "MMMd", options: 0, locale: locale) ?? "MMM d"
        let pattern = "\(day), \(clockPattern(locale))"
        return formatter(pattern, timeZone: timeZone, locale: locale).string(from: date)
    }

    /// Every time of day `text` could mean, or none if it isn't a time.
    ///
    /// The viewer's own clock is tried first, then `14:05`, `2:05 PM`,
    /// `2:05pm`, `2 PM`, `2pm` and a bare `14`, whatever the locale. In a
    /// 12-hour locale a bare `2:05` is either end of the day, so both are
    /// returned and the caller picks the one nearest what the cell showed.
    public static func clocks(parsing text: String, locale: Locale) -> [Clock] {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        let utc = TimeZone(identifier: "UTC") ?? .current
        let posix = Locale(identifier: "en_US_POSIX")
        let marked: [(String, Locale)] = [
            (clockPattern(locale), locale),
            ("h:mm a", posix), ("h:mma", posix), ("h a", posix), ("ha", posix)
        ]
        for (pattern, patternLocale) in marked {
            if let date = formatter(pattern, timeZone: utc, locale: patternLocale).date(from: text) {
                return [clock(of: date, in: utc)]
            }
        }
        for pattern in ["H:mm", "H"] {
            guard let date = formatter(pattern, timeZone: utc, locale: posix).date(from: text) else { continue }
            let typed = clock(of: date, in: utc)
            guard uses12HourClock(locale), (1...12).contains(typed.hour) else { return [typed] }
            let other = Clock(hour: (typed.hour + 12) % 24, minute: typed.minute)
            return [typed, other]
        }
        return []
    }

    /// The instant among `clocks`, on the reference's day or either side of
    /// it in `timeZone`, closest to `reference`. A time typed over a shown
    /// one means the same stretch of time, which is what lets an end past
    /// midnight, or a time recorded in another zone, be edited in place.
    public static func instant(nearest reference: Date, clocks: [Clock], timeZone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var best: (date: Date, distance: Int)?
        for offset in -1...1 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: reference) else { continue }
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            for clock in clocks {
                var wanted = parts
                wanted.hour = clock.hour
                wanted.minute = clock.minute
                wanted.second = 0
                guard let date = calendar.date(from: wanted) else { continue }
                let distance = abs(seconds(from: reference, to: date))
                if best.map({ distance < $0.distance }) ?? true { best = (date, distance) }
            }
        }
        return best?.date
    }

    /// The instant a `yyyy-MM-dd` day starts in `timeZone`, or nil if `day`
    /// is not one.
    public static func startOfDay(_ day: String, timeZone: TimeZone) -> Date? {
        formatter("yyyy-MM-dd", timeZone: timeZone, locale: Locale(identifier: "en_US_POSIX")).date(from: day)
    }

    /// Whole seconds from one instant to another, without a `Double` between
    /// them, for arithmetic that is integer end to end.
    public static func seconds(from start: Date, to end: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar.dateComponents([.second], from: start, to: end).second ?? 0
    }

    /// Whether `locale` shows the time on a 12-hour clock.
    public static func uses12HourClock(_ locale: Locale) -> Bool {
        (DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? "").contains("a")
    }

    // MARK: - Formatters

    private static func clockPattern(_ locale: Locale) -> String {
        uses12HourClock(locale) ? "h:mm a" : "H:mm"
    }

    private static func clock(of date: Date, in zone: TimeZone) -> Clock {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return Clock(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }

    /// `DateFormatter` is thread-safe to use once configured; only the map
    /// needs the lock.
    private final class Cache: @unchecked Sendable {
        let lock = NSLock()
        var formatters: [String: DateFormatter] = [:]
    }

    private static let cache = Cache()

    private static func formatter(_ pattern: String, timeZone: TimeZone, locale: Locale) -> DateFormatter {
        let key = "\(pattern)|\(timeZone.identifier)|\(locale.identifier)"
        cache.lock.lock()
        defer { cache.lock.unlock() }
        if let cached = cache.formatters[key] { return cached }
        let format = DateFormatter()
        format.locale = locale
        format.timeZone = timeZone
        format.dateFormat = pattern
        format.isLenient = false
        cache.formatters[key] = format
        return format
    }
}
