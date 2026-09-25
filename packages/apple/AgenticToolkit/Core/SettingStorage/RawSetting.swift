import Foundation

/// Reads a setting stored as text — a settings table row, an environment
/// variable — into the value it means, falling back to a default for anything
/// absent or malformed.
///
/// One set of rules, so the same garbage string never reads true in one
/// feature and false in another.
public enum RawSetting {

    /// `1`/`true`/`yes`/`on` are true and `0`/`false`/`no`/`off` false, case-
    /// and whitespace-insensitive. Anything else — absent, empty, garbage — is
    /// `fallback`: a caller whose safe answer is "off" passes `false`.
    public static func bool(_ raw: String?, default fallback: Bool) -> Bool {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on": return true
        case "0", "false", "no", "off": return false
        default: return fallback
        }
    }

    /// The integer `raw` holds, clamped into `range`; `fallback` when it holds
    /// none. A value out of range is clamped rather than refused, so an
    /// over-eager hand edit still means the nearest allowed value.
    public static func int(_ raw: String?, default fallback: Int, range: ClosedRange<Int>) -> Int {
        guard let raw, let value = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return fallback
        }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    /// `raw` trimmed, or `fallback` when that leaves nothing.
    public static func string(_ raw: String?, default fallback: String) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }
}
