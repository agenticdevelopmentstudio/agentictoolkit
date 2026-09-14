import Foundation

/// Identifier rules shared by every feature that lets the user pick a slug (personas, products, buckets, users).
public enum Slug {
    public static let pattern = "^[a-z0-9]([a-z0-9-]*[a-z0-9])?$"
    public static let patternMessage = "Use lowercase letters, numbers and hyphens."

    public static func make(from text: String) -> String {
        var out = ""
        var pendingHyphen = false
        for scalar in text.lowercased().unicodeScalars {
            let isAllowed = (scalar >= "a" && scalar <= "z") || (scalar >= "0" && scalar <= "9")
            if isAllowed {
                if pendingHyphen, !out.isEmpty { out.append("-") }
                pendingHyphen = false
                out.unicodeScalars.append(scalar)
            } else {
                pendingHyphen = true
            }
        }
        return out
    }

    public static func isValid(_ slug: String) -> Bool {
        slug.range(of: pattern, options: .regularExpression) != nil
    }
}
