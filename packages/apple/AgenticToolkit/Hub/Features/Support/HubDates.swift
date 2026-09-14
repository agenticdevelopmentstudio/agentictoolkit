import AgenticToolkitHTDV
import Foundation

/// The backend sends ISO-8601 strings (usually with milliseconds). Models keep them as strings; these
/// helpers convert at the edges: forms (`value`), labels (`display`) and request bodies (`iso`).
public enum HubDates {
    // All four formatters are built once and never mutated after construction; building one per call is
    // expensive enough to show up when a rail formats a few hundred rows. `Date.ISO8601FormatStyle` is a
    // `Sendable` value type, so `fractional`/`whole` need no isolation opt-out; `DateFormatter` is also
    // `Sendable`, so `output`/`humane` need none either.
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let whole = Date.ISO8601FormatStyle(includingFractionalSeconds: false)
    private static let output: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return formatter
    }()
    private static let humane: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    public static func parse(_ iso: String?) -> Date? {
        guard let iso, !iso.isEmpty else { return nil }
        return (try? fractional.parse(iso)) ?? (try? whole.parse(iso))
    }

    public static func iso(_ date: Date) -> String {
        output.string(from: date)
    }

    public static func display(_ iso: String?, fallback: String = "—") -> String {
        guard let date = parse(iso) else { return fallback }
        return humane.string(from: date)
    }

    public static func value(_ iso: String?) -> FormValue {
        guard let date = parse(iso) else { return .null }
        return .date(date)
    }
}
