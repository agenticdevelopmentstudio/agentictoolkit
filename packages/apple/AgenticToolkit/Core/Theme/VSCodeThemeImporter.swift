import Foundation

/// Errors thrown while parsing a VS Code colour-theme JSON file.
public enum VSCodeThemeParseError: Error, Equatable {
    /// The document's root was not a JSON object.
    case notAnObject
    /// The `colors` member was absent, or present but not an object. Every
    /// palette value this importer reads lives inside it, so there is nothing
    /// left to salvage without it.
    case missingColors
    /// A required colour key (`editor.foreground` / `editor.background`) was
    /// absent, or carried a value that is not a parseable hex colour.
    case missingColor(String)
    /// One or more of the sixteen `terminal.ansi*` keys were absent. Every
    /// missing name is carried, because "which ones" is the only actionable
    /// thing to tell whoever has to fix the theme.
    case missingANSIColors([String])
    /// Foreground and background are identical, so the theme renders all text
    /// invisible — the same rejection `ITermColorsParser` and
    /// `ThemeStore.importJSON` perform.
    case foregroundMatchesBackground
    /// An `include` chain went deeper than `maximumIncludeDepth`. Carries the
    /// limit rather than the depth reached: the limit is the fact the author
    /// can act on, and a cycle has no depth to report.
    case includeChainTooDeep(limit: Int)
}

/// Parses VS Code colour-theme JSON files (a `contributes.themes` entry's
/// `path`) into a `ColorTheme`.
///
/// Shaped after `ITermColorsParser`: a caseless namespace, Foundation-only, and
/// dynamic casts over a deserialized document rather than a `Codable` struct.
/// The document is deliberately *read by key* instead of decoded: real themes
/// carry `$schema`, `author`, `maintainers`, `semanticClass`,
/// `semanticHighlighting`, `semanticTokenColors` and outright non-schema
/// objects alongside the six keys that matter here, and a strict decoder is the
/// wrong tool for a file you consume a fraction of. It also means
/// `semanticTokenColors` costs nothing here — the source editor highlights with
/// tree-sitter, which has no semantic-token vocabulary to map onto.
///
/// The theme file's own `name` and `type` keys are ignored. VS Code shows the
/// *manifest* entry's `label` in its picker, and the manifest is the authority
/// on what the user chose to install, so `label` and `uiTheme` are parameters.
public enum VSCodeThemeImporter {

    // MARK: - Public API

    /// Parses VS Code colour-theme JSON into a `ColorTheme`.
    ///
    /// - Parameters:
    ///   - data: Raw theme-file bytes. JSONC (comments, trailing commas) is
    ///     accepted, because VS Code accepts it.
    ///   - label: The manifest entry's `label`, used as the theme's name.
    ///   - uiTheme: The manifest entry's `uiTheme`, which decides appearance.
    /// - Throws: `VSCodeThemeParseError` when the document is malformed or a
    ///   required colour is missing (fail-fast; never repaired).
    ///
    /// An `include` key is *not* resolved here and cannot be: resolving one
    /// needs a directory to resolve it against, and raw bytes have none. Use
    /// `parse(contentsOf:label:uiTheme:containedIn:)` for a theme on disk,
    /// which is every production caller.
    public static func parse(
        _ data: Data,
        label: String,
        uiTheme: String
    ) throws -> ColorTheme {
        try theme(from: try object(from: data), label: label, uiTheme: uiTheme)
    }

    /// Parses the VS Code colour-theme file at `url`, resolving its `include`
    /// chain first.
    ///
    /// - Parameters:
    ///   - url: The theme file.
    ///   - label: The manifest entry's `label`, used as the theme's name.
    ///   - uiTheme: The manifest entry's `uiTheme`, which decides appearance.
    ///   - root: The directory the whole chain must stay inside — the
    ///     extension's own folder for a contributed theme. `nil` narrows it to
    ///     the theme file's own directory, which is the right default for a
    ///     file the user picked themselves.
    public static func parse(
        contentsOf url: URL,
        label: String,
        uiTheme: String,
        containedIn root: URL? = nil
    ) throws -> ColorTheme {
        let root = root ?? url.deletingLastPathComponent()
        let document = try resolvedRoot(at: url, containedIn: root, depth: 0)
        return try theme(from: document, label: label, uiTheme: uiTheme)
    }

    // MARK: - Includes

    /// How many `include` hops are followed before the chain is refused.
    ///
    /// VS Code allows nesting and real packs use two or three levels, so the
    /// bound is generous rather than tight. It is a bound and not a visited-set
    /// because that is all a cycle needs: `a → b → a` exhausts it and is
    /// refused, and no legitimate theme comes close.
    private static let maximumIncludeDepth = 8

    /// One theme document with its `include` chain merged in.
    ///
    /// Themes routinely ship one shared base file plus small per-variant files
    /// that inherit from it — `{"include": "./base.json", "colors": {…}}`.
    /// Parsing the variant alone sees one overridden colour, throws
    /// `missingColor("editor.foreground")`, and reports a well-formed theme
    /// pack as broken.
    ///
    /// The include path is extension-controlled, so it goes through the same
    /// containment check as the manifest's own `path` — an `include` of
    /// `../../../../.ssh/config` is the identical escape.
    private static func resolvedRoot(
        at url: URL,
        containedIn root: URL,
        depth: Int
    ) throws -> [String: Any] {
        let own = try object(from: Data(contentsOf: url))
        guard let include = own["include"] as? String, !include.isEmpty else { return own }
        guard depth < maximumIncludeDepth else {
            throw VSCodeThemeParseError.includeChainTooDeep(limit: maximumIncludeDepth)
        }
        // Relative to the *including file's* directory, contained in the
        // extension's — which are usually not the same folder, since the
        // including file typically sits in `themes/`.
        let includeURL = try ExtensionResourcePath.resolve(
            include,
            relativeTo: url.deletingLastPathComponent(),
            containedIn: root
        )
        let base = try resolvedRoot(at: includeURL, containedIn: root, depth: depth + 1)
        return merging(own, onto: base)
    }

    /// `overriding` layered onto `base`, by VS Code's own inheritance rules.
    ///
    /// `colors` merges key by key with the including file winning — the whole
    /// point of the pattern is a variant that restates three keys out of
    /// eighty. `tokenColors` concatenates with the base's rules *first*,
    /// because `style(for:in:)` resolves equal-length selectors in document
    /// order and lets the later one win, which is exactly VS Code's tie-break.
    /// Every other key is a plain override.
    private static func merging(
        _ overriding: [String: Any],
        onto base: [String: Any]
    ) -> [String: Any] {
        var result = base
        // `include` is consumed here and must not survive into the merged
        // document, or a re-entrant parse would follow it a second time.
        for (key, value) in overriding where key != "include" {
            result[key] = value
        }

        let baseColors = base["colors"] as? [String: Any]
        let ownColors = overriding["colors"] as? [String: Any]
        if baseColors != nil || ownColors != nil {
            result["colors"] = (baseColors ?? [:]).merging(ownColors ?? [:]) { _, own in own }
        }

        let baseTokens = base["tokenColors"] as? [Any]
        let ownTokens = overriding["tokenColors"] as? [Any]
        if baseTokens != nil || ownTokens != nil {
            result["tokenColors"] = (baseTokens ?? []) + (ownTokens ?? [])
        }
        return result
    }

    // MARK: - The document

    /// The deserialized root object, or `notAnObject`.
    private static func object(from data: Data) throws -> [String: Any] {
        guard let root = try JSONCPreprocessor.jsonObject(from: data) as? [String: Any] else {
            throw VSCodeThemeParseError.notAnObject
        }
        return root
    }

    /// The theme one fully-resolved document describes.
    private static func theme(
        from root: [String: Any],
        label: String,
        uiTheme: String
    ) throws -> ColorTheme {
        guard let colors = root["colors"] as? [String: Any] else {
            throw VSCodeThemeParseError.missingColors
        }

        let foreground = try requiredColor(in: colors, forKey: "editor.foreground")
        let background = try requiredColor(in: colors, forKey: "editor.background")
        guard foreground != background else {
            throw VSCodeThemeParseError.foregroundMatchesBackground
        }

        let ansi = try ansiColors(in: colors)

        // Not universal (18 of 20 surveyed themes set it); the rest expect the
        // caret drawn in the editor's own ink.
        let cursor = color(in: colors, forKey: "editorCursor.foreground") ?? foreground

        let declaredSelection = color(in: colors, forKey: "editor.selectionBackground")
            ?? color(in: colors, forKey: "editor.inactiveSelectionBackground")
        // Selection is stored opaque. `SemanticPalette.derive(.selectionText)`
        // is `theme.selection.bestTextColor()`, so a stored translucent value
        // makes the app measure contrast against a colour that is never
        // painted — it picks black over what actually renders dark.
        let selection = declaredSelection?.composited(over: background)
            ?? background.blended(withFraction: 0.20, of: foreground)

        let theme = ColorTheme(
            name: label,
            appearance: appearance(for: uiTheme, background: background),
            isBuiltIn: false,
            foreground: foreground,
            background: background,
            cursor: cursor,
            selection: selection,
            ansi: ansi,
            roleOverrides: roleOverrides(in: colors)
        )
        // `tokenColors` sits beside `colors` at the root, not inside it.
        return theme.withSyntaxStyles(syntaxStyles(in: root))
    }

    // MARK: - Appearance

    /// `uiTheme` is VS Code's own four-value vocabulary, and it is what the
    /// extension author declared, so it wins over anything measurable. The
    /// luminance fallback is only reachable via a manifest naming a `uiTheme`
    /// VS Code does not define, and matches `ITermColorsParser`'s inference.
    private static func appearance(for uiTheme: String, background: RGBAColor) -> ThemeAppearance {
        switch uiTheme {
        case "vs-dark", "hc-black":
            return .dark
        case "vs", "hc-light":
            return .light
        default:
            return background.isDark ? .dark : .light
        }
    }

    // MARK: - Palette

    /// The sixteen `terminal.ansi*` keys in `ColorTheme.ansi` slot order.
    private static let ansiKeys = [
        "terminal.ansiBlack", "terminal.ansiRed", "terminal.ansiGreen",
        "terminal.ansiYellow", "terminal.ansiBlue", "terminal.ansiMagenta",
        "terminal.ansiCyan", "terminal.ansiWhite", "terminal.ansiBrightBlack",
        "terminal.ansiBrightRed", "terminal.ansiBrightGreen", "terminal.ansiBrightYellow",
        "terminal.ansiBrightBlue", "terminal.ansiBrightMagenta", "terminal.ansiBrightCyan",
        "terminal.ansiBrightWhite"
    ]

    /// All sixteen or nothing. Synthesising a missing slot would go wrong in
    /// several places at once: `ColorTheme.hasValidPalette` is `ansi.count == 16`
    /// and gates the store's import path, the terminal profile editor indexes
    /// every slot, and `SemanticPalette` derives the accent, status and syntax
    /// colours from specific slots — so an invented `ansi[5]` silently repaints
    /// the editor. Rejecting is the honest answer.
    private static func ansiColors(in colors: [String: Any]) throws -> [RGBAColor] {
        var resolved: [RGBAColor] = []
        resolved.reserveCapacity(ColorTheme.ansiColorCount)
        var missing: [String] = []
        for key in ansiKeys {
            if let value = color(in: colors, forKey: key) {
                resolved.append(value)
            } else {
                missing.append(key)
            }
        }
        guard missing.isEmpty else {
            throw VSCodeThemeParseError.missingANSIColors(missing)
        }
        return resolved
    }

    // MARK: - Semantic roles

    /// The VS Code keys general enough to stand in for a `ThemeRole`.
    ///
    /// A key earns a place here only when it is a *general* token for that
    /// meaning rather than one surface's token, and when authors use it that
    /// way consistently. Everything else derives, deliberately — writing a
    /// redundant override would make `SemanticPalette.declares(_:)`, which the
    /// UI branches on, report "the author chose this" about a value nobody
    /// chose. So `windowBackground`, `primaryText` and `selection` are absent
    /// (derivation already produces exactly the obvious key's value), and so
    /// are the tempting near-misses: `textLink.foreground` is white in one
    /// popular theme and would paint every accent surface white,
    /// `errorForeground` is body-text grey in others, `contrastBorder` is
    /// missing from genuine high-contrast themes, and `editorWarning.foreground`
    /// means "squiggle", not "warning status" — VS Code has no general warning
    /// token at all.
    private static let roleKeys: [(role: ThemeRole, key: String)] = [
        (.surface, "sideBar.background"),
        (.elevatedSurface, "editorWidget.background"),
        (.controlBackground, "input.background"),
        (.secondaryText, "descriptionForeground"),
        (.placeholderText, "input.placeholderForeground"),
        (.outline, "focusBorder")
    ]

    /// Only keys that are present *and* parse become overrides — no defaults,
    /// no synthesis. Assigning `nil` to a dictionary subscript inserts nothing,
    /// which is exactly the rule.
    private static func roleOverrides(in colors: [String: Any]) -> [String: RGBAColor] {
        roleKeys.reduce(into: [String: RGBAColor]()) { overrides, entry in
            overrides[entry.role.rawValue] = color(in: colors, forKey: entry.key)
        }
    }

    // MARK: - Syntax styles

    /// One usable `tokenColors` entry, flattened to a single scope selector.
    /// An entry naming five scopes becomes five rules, because after this point
    /// nothing cares which entry a selector arrived in — only where it sits in
    /// document order, which is preserved by construction.
    private struct SyntaxRule {
        let selector: String
        let style: SyntaxStyle
    }

    /// The TextMate scope to ask for each syntax role, in the order to try.
    ///
    /// Not guesses: measured against 20 published Open VSX themes (the Dracula,
    /// GitHub, Material and Night Owl families). Nine of the ten resolve in
    /// **20/20** themes on the single scope named here. `types` resolves in
    /// 16/20 on `entity.name.type`, and in the remaining four — the Night Owl
    /// family — only on `support.type`, which is why it alone carries a second
    /// step and why the chain is ordered rather than a set. This is the reason
    /// these particular scopes are here and not the dozen plausible
    /// alternatives (`keyword`, `entity.name`, `string`, `comment`), each of
    /// which either matched fewer themes or matched an ancestor so general that
    /// a longer rule elsewhere in the file usually won instead.
    private static let syntaxScopeChains: [(role: SyntaxRole, scopes: [String])] = [
        (.keywords, ["keyword.control"]),
        (.commands, ["entity.name.function"]),
        (.types, ["entity.name.type", "support.type"]),
        (.attributes, ["entity.other.attribute-name"]),
        (.variables, ["variable.other"]),
        (.values, ["constant.language"]),
        (.numbers, ["constant.numeric"]),
        (.strings, ["string.quoted.double"]),
        (.characters, ["constant.character"]),
        (.comments, ["comment.line"])
    ]

    /// Nothing in this section throws. A theme with no `tokenColors`, an
    /// unusable entry, or a role nothing matches simply yields no style for
    /// that role, and the editor falls back to its ANSI derivation — a missing
    /// syntax colour is not a broken theme, and `VSCodeThemeParseError` is
    /// reserved for documents that cannot produce a palette at all.
    private static func syntaxStyles(in root: [String: Any]) -> [SyntaxRole: SyntaxStyle] {
        let rules = syntaxRules(in: root)
        guard !rules.isEmpty else { return [:] }
        return syntaxScopeChains.reduce(into: [SyntaxRole: SyntaxStyle]()) { styles, chain in
            styles[chain.role] = chain.scopes.lazy.compactMap { style(for: $0, in: rules) }.first
        }
    }

    /// The rule painting scope `query`, by VS Code's own resolution order.
    ///
    /// A rule applies when its selector *is* the query or is an ancestor of it,
    /// and the most specific — longest — applicable selector wins. Rules arrive
    /// in document order and a held selector only wins if it is *strictly*
    /// longer, so an equal-length later rule replaces it — VS Code's tie-break:
    /// a later `tokenColors` entry overrides an earlier one naming the same
    /// scope.
    private static func style(for query: String, in rules: [SyntaxRule]) -> SyntaxStyle? {
        var best: SyntaxRule?
        for rule in rules where query == rule.selector || query.hasPrefix(rule.selector + ".") {
            if let held = best, held.selector.count > rule.selector.count { continue }
            best = rule
        }
        return best?.style
    }

    private static func syntaxRules(in root: [String: Any]) -> [SyntaxRule] {
        guard let entries = root["tokenColors"] as? [Any] else { return [] }
        return entries.reduce(into: [SyntaxRule]()) { rules, entry in
            guard let entry = entry as? [String: Any],
                  let settings = entry["settings"] as? [String: Any],
                  // An entry carrying only a `fontStyle` has no colour to
                  // store, and emphasis without a colour is not something this
                  // grammar can express — so it is not a rule at all.
                  let raw = settings["foreground"] as? String,
                  let color = color(fromHex: raw) else { return }
            let emphasis = emphasis(in: settings)
            let style = SyntaxStyle(color: color, bold: emphasis.bold, italic: emphasis.italic)
            rules.append(contentsOf: selectors(in: entry["scope"]).map {
                SyntaxRule(selector: $0, style: style)
            })
        }
    }

    /// `underline`, `strikethrough` and anything unrecognised are dropped:
    /// `EditorTheme.Attribute` is colour + bold + italic, with nowhere to put
    /// them. `normal` and `regular` are dropped too — they mean the *absence*
    /// of emphasis, which is already what `false, false` says.
    private static func emphasis(in settings: [String: Any]) -> (bold: Bool, italic: Bool) {
        guard let raw = settings["fontStyle"] as? String else { return (false, false) }
        let styles = raw.split(whereSeparator: \.isWhitespace)
        return (styles.contains("bold"), styles.contains("italic"))
    }

    /// The scope selectors an entry names, in document order.
    ///
    /// `scope` comes in two forms and both occur in the wild: an array of
    /// strings, and a single string holding several comma-separated selectors
    /// (1681 such entries across the 20-theme corpus). An *absent* scope means
    /// "applies to everything" in VS Code; here it can only produce a false
    /// match against whichever role's scope is asked for first, so it is
    /// dropped.
    private static func selectors(in scope: Any?) -> [String] {
        let declared: [String]
        switch scope {
        // Element-wise rather than `as? [String]`, so one stray `null` in an
        // otherwise good array costs that element and not the whole entry.
        case let list as [Any]:
            declared = list.compactMap { $0 as? String }
        case let single as String:
            declared = single.split(separator: ",").map(String.init)
        default:
            return []
        }
        return declared
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            // A selector containing a space is a descendant selector
            // (`meta.tag entity.name`): it applies only inside an ancestor
            // context this code has no way to know it is in. Matching on its
            // last component would paint the wrong tokens, so it is skipped
            // outright — better an undeclared role, which derives, than a
            // confidently wrong colour.
            .filter { !$0.isEmpty && !$0.contains(where: \.isWhitespace) }
    }

    // MARK: - Colour decoding

    private static func requiredColor(in colors: [String: Any], forKey key: String) throws -> RGBAColor {
        guard let value = color(in: colors, forKey: key) else {
            throw VSCodeThemeParseError.missingColor(key)
        }
        return value
    }

    /// `RGBAColor(hexString:)` is `guard hex.count == 8`, and VS Code themes are
    /// overwhelmingly `#RRGGBB`, so shorthands are expanded and a missing alpha
    /// is filled in as opaque before handing the string over.
    ///
    /// A value that is not a string, or that is a string in no recognised form
    /// (a named colour, an odd digit count), counts as *absent* rather than as
    /// an error: one unreadable optional key should never cost the user a theme
    /// VS Code itself renders. The two keys that genuinely cannot be missing
    /// are enforced by `requiredColor`.
    private static func color(in colors: [String: Any], forKey key: String) -> RGBAColor? {
        guard let raw = colors[key] as? String else { return nil }
        return color(fromHex: raw)
    }

    /// The normalizer itself, split out from the keyed lookup above because
    /// `tokenColors` states its colours inline rather than under a key. One
    /// spelling of "what counts as a colour in a VS Code theme" (`dry`).
    private static func color(fromHex raw: String) -> RGBAColor? {
        var hex = raw.hasPrefix("#") ? String(raw.dropFirst()) : raw
        switch hex.count {
        case 3, 4:
            hex = hex.map { "\($0)\($0)" }.joined()
        case 6, 8:
            break
        default:
            return nil
        }
        if hex.count == 6 { hex += "FF" }
        return RGBAColor(hexString: hex)
    }
}

extension ThemeStore {

    /// Parses a VS Code colour theme and stores it as a new **locked** imported
    /// theme (duplicate to edit).
    ///
    /// An extension rather than a method on `ThemeStore` itself because the
    /// store ships from AgenticDeveloperToolkit, which knows nothing about VS
    /// Code. `add(_:)` is `public`, so this wires up from outside the module.
    @discardableResult
    public func importVSCodeTheme(
        contentsOf url: URL,
        label: String,
        uiTheme: String
    ) throws -> ColorTheme {
        var theme = try VSCodeThemeImporter.parse(contentsOf: url, label: label, uiTheme: uiTheme)
        theme.isImported = true
        return add(theme)
    }
}
