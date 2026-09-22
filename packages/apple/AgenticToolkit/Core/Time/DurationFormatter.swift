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
}
