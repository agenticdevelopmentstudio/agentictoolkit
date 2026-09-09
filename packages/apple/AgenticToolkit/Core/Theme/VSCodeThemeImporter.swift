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
/// wrong tool for a file you consume a fraction of. It also means `tokenColors`
/// and `semanticTokenColors` cost nothing here — mapping those onto the source
/// editor's syntax attributes is a separate job.
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
    public static func parse(
        _ data: Data,
        label: String,
        uiTheme: String
    ) throws -> ColorTheme {
        guard let root = try jsonObject(from: data) as? [String: Any] else {
            throw VSCodeThemeParseError.notAnObject
        }
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

        return ColorTheme(
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
    }

    /// Parses the VS Code colour-theme file at `url`.
    public static func parse(
        contentsOf url: URL,
        label: String,
        uiTheme: String
    ) throws -> ColorTheme {
        try parse(Data(contentsOf: url), label: label, uiTheme: uiTheme)
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

    // MARK: - JSONC

    /// The encodings a theme file can legally arrive in, in the order they are
    /// tried. UTF-8 is what every real theme uses; the rest are legal JSON and
    /// cost one decode attempt each.
    private static let candidateEncodings: [String.Encoding] = [
        .utf8,
        .utf16,
        .utf16BigEndian,
        .utf16LittleEndian,
        .utf32BigEndian,
        .utf32LittleEndian
    ]

    private static func jsonObject(from data: Data) throws -> Any {
        // VS Code reads theme files as JSONC; `JSONSerialization` does not, and the
        // preprocessor that closes that gap needs *text*. Transcoding is what keeps
        // JSONC support from depending on the file's encoding: handing raw UTF-16/32
        // bytes to `JSONSerialization` parses them, but only if they are strict JSON,
        // so a commented theme would fail purely for not having been saved as UTF-8.
        //
        // First candidate that yields a parseable document wins, rather than first
        // that merely decodes: UTF-16 bytes for ASCII text also decode as UTF-8 (the
        // interleaved NULs are valid UTF-8), and `.utf16` accepts any even-length
        // payload as big-endian, so "decodes" alone would let an earlier candidate
        // swallow a later one's file and turn a good theme into a syntax error.
        for encoding in candidateEncodings {
            guard var text = String(data: data, encoding: encoding) else { continue }
            // A BOM can survive decoding as U+FEFF, and `JSONSerialization` rejects
            // the document over it; VS Code's parser skips it.
            if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
            let stripped = removingTrailingCommas(removingComments(text))
            if let object = try? JSONSerialization.jsonObject(with: Data(stripped.utf8)) {
                return object
            }
        }
        // Nothing decoded into a parseable document. The raw bytes go to
        // `JSONSerialization` so the error describes the caller's actual file rather
        // than one of the transcodings attempted above.
        return try JSONSerialization.jsonObject(with: data)
    }

    /// Removes `//` and `/* … */` comments, leaving anything inside a string
    /// literal alone.
    ///
    /// String-awareness is the whole difficulty: a `$schema` value is an
    /// `https://…` URL, so a scanner that does not track quoting and backslash
    /// escapes truncates the document at the first one and reports a syntax
    /// error pointing nowhere near the problem.
    private static func removingComments(_ text: String) -> String {
        var output = String()
        output.reserveCapacity(text.count)
        var inString = false
        var escaped = false
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]

            if inString {
                output.append(character)
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                index = text.index(after: index)
                continue
            }

            if character == "\"" {
                inString = true
                output.append(character)
                index = text.index(after: index)
                continue
            }

            if character == "/" {
                let next = text.index(after: index)
                if next < text.endIndex, text[next] == "/" {
                    // Stop *at* the newline rather than past it, so the outer
                    // loop still emits it and line numbers survive.
                    index = next
                    while index < text.endIndex, !text[index].isNewline {
                        index = text.index(after: index)
                    }
                    continue
                }
                if next < text.endIndex, text[next] == "*" {
                    index = text.index(after: next)
                    while index < text.endIndex {
                        let closing = text.index(after: index)
                        if text[index] == "*", closing < text.endIndex, text[closing] == "/" {
                            index = text.index(after: closing)
                            break
                        }
                        index = text.index(after: index)
                    }
                    continue
                }
            }

            output.append(character)
            index = text.index(after: index)
        }

        return output
    }

    /// Blanks a comma that has nothing but whitespace between it and its closing
    /// `}` or `]`. Runs *after* comment removal, so `[1, /* stale */]` is caught
    /// too. Overwriting with a space rather than deleting keeps every remaining
    /// offset valid while the scan is still running.
    private static func removingTrailingCommas(_ text: String) -> String {
        var characters = Array(text)
        var inString = false
        var escaped = false
        var pendingComma: Int?

        for offset in characters.indices {
            let character = characters[offset]

            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }

            if character == "\"" {
                inString = true
                pendingComma = nil
            } else if character == "," {
                pendingComma = offset
            } else if character == "}" || character == "]" {
                if let comma = pendingComma { characters[comma] = " " }
                pendingComma = nil
            } else if !character.isWhitespace {
                pendingComma = nil
            }
        }

        return String(characters)
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
