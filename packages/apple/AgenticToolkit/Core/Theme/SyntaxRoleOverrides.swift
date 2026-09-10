import Foundation

/// The ten syntax attributes a source editor paints.
///
/// The case names are the names of `EditorTheme`'s ten syntax fields verbatim,
/// which is what lets the macOS bridge read a role out of a dictionary and
/// assign it straight across instead of carrying a translation table that has
/// to be kept in step with two vocabularies.
public enum SyntaxRole: String, CaseIterable, Sendable, Equatable {
    case keywords, commands, types, attributes, variables
    case values, numbers, strings, characters, comments
}

/// How one syntax role is painted: a colour plus the emphasis the theme asked
/// for. Matches `EditorTheme.Attribute`, which has no underline — so nothing
/// upstream of here has a reason to carry one.
public struct SyntaxStyle: Equatable, Sendable {
    public var color: RGBAColor
    public var bold: Bool
    public var italic: Bool

    public init(color: RGBAColor, bold: Bool = false, italic: Bool = false) {
        self.color = color
        self.bold = bold
        self.italic = italic
    }
}

// MARK: - The `roleOverrides` key grammar

/// A `roleOverrides` key of the form `syntax.<role>[.bold][.italic]`, parsed.
///
/// Reading treats the trailing segments as a *set* rather than a sequence, so a
/// hand-edited `syntax.comments.italic.bold` is understood even though
/// `overrideKey` only ever writes bold before italic.
private struct SyntaxOverrideKey {
    let role: SyntaxRole
    let bold: Bool
    let italic: Bool

    /// `nil` for every key that is not a syntax key — a role override, a
    /// misspelling, a flag this grammar has no meaning for, or a flag stated
    /// twice. A theme file is user-editable, so a key nobody can act on is
    /// ignored rather than thrown on: one bad line must not cost the user a
    /// theme the rest of which is fine.
    init?(_ key: String) {
        let segments = key.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2,
              segments[0] == SyntaxRole.keyPrefix,
              let role = SyntaxRole(rawValue: String(segments[1])) else { return nil }

        var bold = false
        var italic = false
        for segment in segments.dropFirst(2) {
            switch segment {
            case "bold":
                guard !bold else { return nil }
                bold = true
            case "italic":
                guard !italic else { return nil }
                italic = true
            default:
                return nil
            }
        }

        self.role = role
        self.bold = bold
        self.italic = italic
    }
}

extension SyntaxRole {
    /// The namespace every syntax key sits under. `ThemeRole` rawValues are
    /// camelCase Swift identifiers and so can never contain a dot, which is
    /// what makes this prefix collision-proof against the role keys sharing
    /// the dictionary.
    fileprivate static let keyPrefix = "syntax"

    /// The `roleOverrides` key carrying this role's colour and emphasis.
    ///
    /// Always emits bold before italic, so `syntax.keywords`,
    /// `syntax.keywords.bold`, `syntax.keywords.italic` and
    /// `syntax.keywords.bold.italic` are the only four shapes this code writes.
    public func overrideKey(bold: Bool = false, italic: Bool = false) -> String {
        var key = "\(Self.keyPrefix).\(rawValue)"
        if bold { key += ".bold" }
        if italic { key += ".italic" }
        return key
    }
}

extension ColorTheme {

    /// The syntax styles this theme states outright. Empty for a theme that
    /// states none — the editor then derives all ten from the ANSI palette.
    ///
    /// They live in `roleOverrides` because `ColorTheme` is the unit that
    /// travels: `ThemeStore.exportJSON(_:)` and `ThemeStore.duplicate(_:)` are
    /// both ordinary things to do with an imported theme, and
    /// `ColorTheme.init(from:)` decodes a fixed key list — so anything stored
    /// beside a `ColorTheme` is silently dropped by both, and duplicating an
    /// imported theme to edit it would repaint the editor the moment it was
    /// made. `SemanticPalette` looks roles up strictly by `ThemeRole.rawValue`,
    /// so the extra keys are invisible to it.
    public var syntaxStyles: [SyntaxRole: SyntaxStyle] {
        var styles: [SyntaxRole: SyntaxStyle] = [:]
        var winning: [SyntaxRole: String] = [:]
        for (key, color) in roleOverrides {
            guard let parsed = SyntaxOverrideKey(key) else { continue }
            // Two keys for one role are only reachable by hand-editing a theme
            // file — this writer never emits more than one. Picking the
            // lexicographically greatest makes the answer total and stable;
            // dictionary iteration order is not, so "last seen wins" would
            // resolve differently between two reads of the same theme.
            if let held = winning[parsed.role], held > key { continue }
            winning[parsed.role] = key
            styles[parsed.role] = SyntaxStyle(color: color, bold: parsed.bold, italic: parsed.italic)
        }
        return styles
    }

    /// A copy carrying exactly `styles`: every key this grammar recognises as a
    /// syntax key is replaced, and every other `roleOverrides` entry is left
    /// alone — including a `syntax.`-prefixed key the grammar rejects, because
    /// this shares its parser with `syntaxStyles` and two functions disagreeing
    /// about what a syntax key *is* would be the real bug, where an inert key
    /// (ignored on read, invisible to `SemanticPalette`) is only clutter that a
    /// later widening of this grammar may yet want to own.
    ///
    /// Replacing rather than merging is the point (`idempotency`): re-importing
    /// a theme, or importing over one that already carried syntax keys, must
    /// not leave behind a key in a shape that is no longer written — a stale
    /// `syntax.keywords.bold` would outrank the fresh `syntax.keywords`.
    public func withSyntaxStyles(_ styles: [SyntaxRole: SyntaxStyle]) -> ColorTheme {
        var copy = self
        copy.roleOverrides = roleOverrides.filter { SyntaxOverrideKey($0.key) == nil }
        for (role, style) in styles {
            copy.roleOverrides[role.overrideKey(bold: style.bold, italic: style.italic)] = style.color
        }
        return copy
    }
}
