import AppKit
import CodeEditSourceEditor

import AgenticToolkitCore
import AgenticToolkitCoreMacOS

/// The source editor's face of the app theme.
///
/// `CodeEditSourceEditor` asks for an `EditorTheme` — a fixed set of syntax
/// attributes — while the rest of the app reads a `SemanticPalette`. Deriving
/// one from the other is what keeps the file viewer inside the theme system
/// rather than carrying a second, hardcoded palette beside it (`dry`): pick a
/// theme and the editor follows it, imported `.itermcolors` schemes included.
///
/// Chrome comes from the semantic roles (`primaryText`, `cursor`, `selection`,
/// `surface`), because those *are* the app-wide meanings. Syntax colors come
/// from the ANSI 16 instead: "keyword" and "string" are not UI roles, and the
/// 16-slot palette is the vocabulary terminal-derived schemes — Solarized,
/// Dracula, Nord, Gruvbox — are actually authored in, so a scheme's own idea of
/// "green" is what strings end up painted with.
///
/// A theme that states its syntax colors outright (see `ColorTheme.syntaxStyles`
/// — a VS Code import, whose `tokenColors` say what *code* looks like) overrides
/// that derivation role by role. Deriving from ANSI is the fallback for schemes
/// that have no such opinion, not the preferred answer for ones that do.
///
/// The bridge lives in `AgenticToolkitMacOS` rather than next to
/// `SemanticPalette+NSColor` in `AgenticToolkitCoreMacOS`, because that is the
/// only target that links `CodeEditSourceEditor`.
extension SemanticPalette {

    /// This palette expressed as a source-editor theme.
    public var editorTheme: EditorTheme {
        // A theme imported from VS Code states its syntax colours outright
        // (`tokenColors`); a terminal-derived one states none and every role
        // below falls through to the ANSI derivation.
        let syntax = theme.syntaxStyles
        return EditorTheme(
            // Chrome is untouched by a declared syntax style: `tokenColors` has
            // nothing to say about editor chrome, which comes from the semantic
            // roles the palette half of the import already filled.
            text: .init(color: nsColor(.primaryText)),
            insertionPoint: nsColor(.cursor),
            invisibles: .init(color: nsColor(.placeholderText)),
            background: nsColor(.windowBackground),
            // The caret line sits one elevation above the backdrop, the same
            // relationship a panel has to the window.
            lineHighlight: nsColor(.surface),
            selection: nsColor(.selection),
            keywords: syntax.attribute(.keywords, or: .init(color: ansiColor(5, or: .accent), bold: true)),
            commands: syntax.attribute(.commands, or: .init(color: ansiColor(4, or: .accent))),
            types: syntax.attribute(.types, or: .init(color: ansiColor(6, or: .info))),
            attributes: syntax.attribute(.attributes, or: .init(color: ansiColor(3, or: .warning))),
            // `variables` also carries functions, methods and parameters — see
            // `EditorTheme.mapCapture` — so it takes a bright slot that reads
            // clearly at the density those appear in.
            variables: syntax.attribute(.variables, or: .init(color: ansiColor(12, or: .primaryText))),
            values: syntax.attribute(.values, or: .init(color: ansiColor(11, or: .warning))),
            numbers: syntax.attribute(.numbers, or: .init(color: ansiColor(9, or: .danger))),
            strings: syntax.attribute(.strings, or: .init(color: ansiColor(2, or: .success))),
            characters: syntax.attribute(.characters, or: .init(color: ansiColor(2, or: .success))),
            comments: syntax.attribute(.comments, or: .init(color: nsColor(.tertiaryText), italic: true))
        )
    }

    /// ANSI slot `index`, falling back to a semantic role when the theme is
    /// short of colors. A hand-authored or partially imported scheme is not
    /// guaranteed to carry all 16, and a missing slot must not blank out a
    /// whole syntax class.
    private func ansiColor(_ index: Int, or fallback: ThemeRole) -> NSColor {
        theme.ansiColor(at: index).map(NSColor.init) ?? nsColor(fallback)
    }
}

extension [SyntaxRole: SyntaxStyle] {

    /// The declared style for `role` if the theme states one, otherwise
    /// `derived`.
    ///
    /// **A declared style is authoritative, including its absences.** The
    /// derived attributes hardcode `keywords` bold and `comments` italic, which
    /// is the right default for a terminal-derived scheme — one has no opinion
    /// about weight. A VS Code theme does have an opinion, and a role it
    /// declares without a `fontStyle` means "no emphasis", so a declared
    /// `keywords` is not bold unless the theme said `bold`.
    ///
    /// That is the whole reason emphasis is carried at all, and it is
    /// measurable: "Night Owl" and "Night Owl (No Italics)" differ in exactly
    /// one thing — `comments` is `italic` in one and unstyled in the other,
    /// while every colour in both is identical. Drop the emphasis and the two
    /// shipped themes import to the same bytes.
    ///
    /// `derived` is evaluated eagerly at the call site; every one of them is a
    /// dictionary or array lookup, not work.
    fileprivate func attribute(_ role: SyntaxRole, or derived: EditorTheme.Attribute) -> EditorTheme.Attribute {
        guard let style = self[role] else { return derived }
        return .init(color: NSColor(style.color), bold: style.bold, italic: style.italic)
    }
}
