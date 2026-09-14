import Foundation

/// Optional string fields arrive from forms as `""` and must encode as absent, never as an empty string.
public enum HubText {
    /// The trimmed value, or nil when it is missing or only whitespace.
    public static func nonBlank(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
