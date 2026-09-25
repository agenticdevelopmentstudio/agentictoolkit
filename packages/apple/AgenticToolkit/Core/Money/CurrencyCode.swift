import Foundation

/// The shape rule for an ISO-4217 currency code, in one place so a code one
/// screen refuses is never accepted by another.
public enum CurrencyCode {

    /// `text` as a three-letter code, trimmed and upper-cased, or nil if it
    /// isn't one. `" usd "` is `"USD"`; `"U5D"`, `"US"` and `"EURO"` are nil.
    /// Only the shape is checked — whether the code is in circulation is not.
    public static func normalized(_ text: String) -> String? {
        let code = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count == 3, code.unicodeScalars.allSatisfy({ ("A"..."Z").contains($0) }) else { return nil }
        return code
    }
}
