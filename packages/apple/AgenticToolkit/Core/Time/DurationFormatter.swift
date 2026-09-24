import Foundation

/// Integer seconds rendered three ways: `hoursMinutes` for reading,
/// `decimalHours` for transcribing into a client's billing tool, and `clock`
/// for a running timer.
///
/// This does not converge the repo's three existing duration formatters — that
/// is separate work. It exists because the billing path must never route a
/// duration through a `Double`.
public enum DurationFormatter {

    /// `"2h 15m"`. Seconds below a minute round down to `"0m"` rather than
    /// implying precision the rounding rules have already discarded.
    public static func hoursMinutes(seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        switch (hours, minutes) {
        case (0, _): return "\(minutes)m"
        case (_, 0): return "\(hours)h"
        default: return "\(hours)h \(minutes)m"
        }
    }

    /// `"2.25"` — the form typed into a client's tool. Half-up at `places`.
    public static func decimalHours(seconds: Int, places: Int = 2) -> String {
        let total = max(0, seconds)
        let clampedPlaces = max(0, places)
        var scale = 1
        for _ in 0..<clampedPlaces { scale *= 10 }
        // (total / 3600) × scale, rounded half-up, entirely in integers.
        let scaled = (total * scale * 2 + 3600) / 7200
        let whole = scaled / scale
        let fraction = scaled % scale
        guard clampedPlaces > 0 else { return "\(whole)" }
        return "\(whole)." + String(format: "%0\(clampedPlaces)d", fraction)
    }

    /// `"2:15:00"` — hours are not zero-padded and are not wrapped at 24.
    public static func clock(seconds: Int) -> String {
        let total = max(0, seconds)
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    /// A typed duration, in seconds, or nil if the text is not one.
    ///
    /// Accepts decimal hours (`"1.5"`, `"0.25"`, `".5"`, `"1,5"`), a clock
    /// (`"1:30"`, minutes always two digits), and units (`"1h 30m"`, `"2h"`,
    /// `"90m"`). Negative numbers and anything else answer nil. Whether a
    /// duration is *allowed* (not zero, not over a day) is the caller's call.
    ///
    /// Integer arithmetic throughout, as everywhere billing touches time: a
    /// fraction of an hour becomes seconds by `(digits × 3600) / 10ⁿ`, rounded
    /// half-up, never through a `Double`.
    public static func seconds(parsing text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return nil }
        if let colon = trimmed.firstIndex(of: ":") {
            let minutesText = trimmed[trimmed.index(after: colon)...]
            guard let hours = digits(trimmed[..<colon]), minutesText.count == 2,
                  let minutes = digits(minutesText), minutes < 60 else { return nil }
            return hours * 3600 + minutes * 60
        }
        if trimmed.contains("h") || trimmed.contains("m") {
            return unitSeconds(trimmed)
        }
        return decimalHourSeconds(trimmed)
    }

    /// Plain ASCII digits, at most six of them. Six keeps every product below
    /// in range and is already more hours than anyone bills.
    private static func digits(_ text: Substring) -> Int? {
        guard !text.isEmpty, text.count <= 6,
              text.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(text)
    }

    /// `"1h 30m"`, `"1h30m"`, `"2h"`, `"90m"`.
    private static func unitSeconds(_ text: String) -> Int? {
        let compact = Substring(text.filter { $0 != " " })
        var hours = 0
        var rest = compact
        if let hourMark = compact.firstIndex(of: "h") {
            guard let value = digits(compact[..<hourMark]) else { return nil }
            hours = value
            rest = compact[compact.index(after: hourMark)...]
        }
        var minutes = 0
        if !rest.isEmpty {
            guard rest.last == "m", let value = digits(rest.dropLast()) else { return nil }
            minutes = value
        }
        return hours * 3600 + minutes * 60
    }

    /// `"1.5"`, `".5"`, `"2"`, `"1,5"`.
    private static func decimalHourSeconds(_ text: String) -> Int? {
        let parts = text.replacingOccurrences(of: ",", with: ".")
            .split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }
        let wholeText = parts[0]
        let fractionText = parts.count == 2 ? parts[1] : Substring("")
        guard !(wholeText.isEmpty && fractionText.isEmpty) else { return nil }
        guard let whole = wholeText.isEmpty ? 0 : digits(wholeText) else { return nil }
        guard !fractionText.isEmpty else { return whole * 3600 }
        guard let fraction = digits(fractionText) else { return nil }
        var scale = 1
        for _ in 0..<fractionText.count { scale *= 10 }
        return whole * 3600 + (fraction * 3600 * 2 + scale) / (2 * scale)
    }
}
