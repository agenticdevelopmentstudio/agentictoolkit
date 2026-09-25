import Foundation

/// Names that read apart from every name already taken.
///
/// One rule for every "New Project", "New Client" and provider configuration:
/// two records with one name read alike in every list, and a chooser that fills
/// by title drops one of them.
public enum UniqueName {

    /// `base`, or if it is taken, `base 2`, `base 3`… — the first that isn't.
    public static func next(base: String, taken: some Sequence<String>) -> String {
        let taken = Set(taken)
        guard taken.contains(base) else { return base }
        var suffix = 2
        while taken.contains("\(base) \(suffix)") { suffix += 1 }
        return "\(base) \(suffix)"
    }

    /// Whether `name` is already one of `taken`, compared the way a person
    /// reading a list would: surrounding whitespace ignored, case-insensitive.
    /// For refusing a rename onto another record's name.
    public static func collides(_ name: String, with taken: some Sequence<String>) -> Bool {
        let wanted = normalized(name)
        return taken.contains { normalized($0) == wanted }
    }

    private static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive], locale: nil)
    }
}
