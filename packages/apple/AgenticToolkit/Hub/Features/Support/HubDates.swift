import AgenticToolkitHTDV
import Foundation

/// The backend sends ISO-8601 strings (usually with milliseconds). Models keep them as strings; these
/// helpers convert at the edges: forms (`value`), labels (`display`) and request bodies (`iso`).
public enum HubDates {
    // All four formatters are built once and never mutated after construction; building one per call is
    // expensive enough to show up when a rail formats a few hundred rows. `DateFormatter` is `Sendable`;
    // `ISO8601DateFormatter` is not, but it is documented as safe to *use* concurrently once configured,
    // which is all these two do.
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    nonisolated(unsafe) private static let whole: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
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
        return fractional.date(from: iso) ?? whole.date(from: iso)
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
