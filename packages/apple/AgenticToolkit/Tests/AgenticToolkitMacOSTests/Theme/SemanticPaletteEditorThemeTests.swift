import Testing
import AppKit
// The suite names `EditorTheme.Attribute` outright, which the transitive
// import through `AgenticToolkitMacOS` does not bring into scope.
import CodeEditSourceEditor
@testable import AgenticToolkitCore
@testable import AgenticToolkitCoreMacOS
@testable import AgenticToolkitMacOS

/// The source editor is themed by the app's theme, not by a palette of its own.
/// These pin the two halves of that: chrome comes from the semantic roles, and
/// syntax comes from the theme's own ANSI colors, so a theme switch — including
/// to an imported `.itermcolors` scheme — actually repaints the editor.
@MainActor
@Suite("SemanticPalette → EditorTheme")
struct SemanticPaletteEditorThemeTests {

    private func palette(_ theme: ColorTheme) -> SemanticPalette { SemanticPalette(theme: theme) }

    @Test("chrome comes from the semantic roles")
    func chrome() {
        let palette = palette(BuiltInThemes.dracula)
        let editor = palette.editorTheme

        #expect(editor.background == palette.nsColor(.windowBackground))
        #expect(editor.text.color == palette.nsColor(.primaryText))
        #expect(editor.insertionPoint == palette.nsColor(.cursor))
        #expect(editor.selection == palette.nsColor(.selection))
        #expect(editor.lineHighlight == palette.nsColor(.surface))
    }

    @Test("syntax colors come from the theme's own ANSI palette")
    func syntax() throws {
        let theme = BuiltInThemes.dracula
        let editor = palette(theme).editorTheme

        #expect(editor.keywords.color == NSColor(try #require(theme.ansiColor(at: 5))))
        #expect(editor.strings.color == NSColor(try #require(theme.ansiColor(at: 2))))
        #expect(editor.characters.color == editor.strings.color)
        #expect(editor.types.color == NSColor(try #require(theme.ansiColor(at: 6))))
        #expect(editor.numbers.color == NSColor(try #require(theme.ansiColor(at: 9))))
    }

    @Test("keywords are bold and comments italic, so weight survives a theme swap")
    func emphasis() {
        let editor = palette(BuiltInThemes.solarizedLight).editorTheme
        #expect(editor.keywords.bold)
        #expect(editor.comments.italic)
        #expect(editor.text.bold == false)
    }

    @Test("switching themes changes the editor theme")
    func followsTheTheme() {
        #expect(palette(BuiltInThemes.dracula).editorTheme != palette(BuiltInThemes.solarizedLight).editorTheme)
    }

    /// A hand-authored or partially imported scheme need not carry all 16 ANSI
    /// slots. A missing slot must fall back to a semantic role rather than
    /// blanking out a whole syntax class.
    @Test("a theme short of ANSI colors falls back to semantic roles")
    func shortPalette() {
        var theme = BuiltInThemes.dracula
        theme.ansi = []
        let palette = palette(theme)
        let editor = palette.editorTheme

        #expect(editor.keywords.color == palette.nsColor(.accent))
        #expect(editor.strings.color == palette.nsColor(.success))
        #expect(editor.numbers.color == palette.nsColor(.danger))
        #expect(editor.types.color == palette.nsColor(.info))
    }

    // MARK: - Themes that state their syntax colors outright

    /// A theme imported from VS Code says what code looks like (`tokenColors`),
    /// and that beats the ANSI derivation role by role. Every built-in theme
    /// declares none, which is why every assertion above still holds unchanged.
    private func declaring(_ styles: [SyntaxRole: SyntaxStyle]) -> ColorTheme {
        BuiltInThemes.dracula.withSyntaxStyles(styles)
    }

    private func color(_ hex: String) throws -> RGBAColor {
        try #require(RGBAColor(hexString: hex))
    }

    /// **A declared style is authoritative, including its absences.** The
    /// derived `keywords` is hardcoded bold, which is the right default for a
    /// terminal-derived scheme — it has no opinion about weight. A theme that
    /// declares `keywords` as italic and nothing else has said "italic, not
    /// bold", and the hardcoded default must not add the bold back.
    @Test("a declared style beats the hardcoded emphasis, absences included")
    func declaredStyleBeatsHardcodedBold() throws {
        let declared = try color("C792EAFF")
        let editor = palette(declaring([.keywords: SyntaxStyle(color: declared, italic: true)])).editorTheme

        #expect(editor.keywords.color == NSColor(declared))
        #expect(editor.keywords.italic)
        #expect(editor.keywords.bold == false)
    }

    /// The "No Italics" case, and the reason emphasis is carried at all:
    /// "Night Owl" and "Night Owl (No Italics)" differ in exactly one thing —
    /// `comments` is italic in one and unstyled in the other, every colour in
    /// both being identical. Drop the emphasis and the two shipped themes
    /// import to the same bytes.
    @Test("a declared style with no flags is not italic, even for comments")
    func declaredCommentsAreNotItalicByDefault() throws {
        let declared = try color("637777FF")
        let italics = declaring([.comments: SyntaxStyle(color: declared, italic: true)])
        let noItalics = declaring([.comments: SyntaxStyle(color: declared)])

        #expect(palette(noItalics).editorTheme.comments.color == NSColor(declared))
        #expect(palette(noItalics).editorTheme.comments.italic == false)
        #expect(palette(italics).editorTheme.comments.italic)
        #expect(palette(italics).editorTheme != palette(noItalics).editorTheme)
    }

    /// A theme need not declare all ten. A role it leaves out derives exactly
    /// as it did before any of this existed, hardcoded emphasis intact — a
    /// partial `tokenColors` must not blank out the rest of the editor.
    @Test("undeclared roles still come from the ANSI derivation, emphasis intact")
    func undeclaredRolesStillDerive() throws {
        let declared = try color("ADDB67FF")
        let theme = declaring([.strings: SyntaxStyle(color: declared, bold: true)])
        let editor = palette(theme).editorTheme
        let derived = palette(BuiltInThemes.dracula).editorTheme

        #expect(editor.strings.color == NSColor(declared))
        #expect(editor.strings.bold)

        // `characters` shares `strings`' ANSI slot but was not declared, so it
        // keeps the derived colour rather than following its neighbour.
        #expect(editor.characters == derived.characters)
        #expect(editor.keywords == derived.keywords)
        #expect(editor.keywords.bold)
        #expect(editor.comments == derived.comments)
        #expect(editor.comments.italic)

        // Chrome is untouched: `tokenColors` has nothing to say about it.
        #expect(editor.background == derived.background)
        #expect(editor.text == derived.text)
        #expect(editor.selection == derived.selection)
        #expect(editor.insertionPoint == derived.insertionPoint)
        #expect(editor.lineHighlight == derived.lineHighlight)
        #expect(editor.invisibles == derived.invisibles)
    }

    /// The ten roles are the ten `EditorTheme` syntax fields, so a theme that
    /// declares every one of them leaves nothing deriving.
    @Test("a theme declaring all ten roles replaces every syntax field")
    func allTenRolesAreReachable() throws {
        var styles: [SyntaxRole: SyntaxStyle] = [:]
        for (index, role) in SyntaxRole.allCases.enumerated() {
            styles[role] = SyntaxStyle(color: try color(String(format: "%02X00FFFF", index)))
        }
        let editor = palette(declaring(styles)).editorTheme

        let painted: [SyntaxRole: EditorTheme.Attribute] = [
            .keywords: editor.keywords, .commands: editor.commands, .types: editor.types,
            .attributes: editor.attributes, .variables: editor.variables, .values: editor.values,
            .numbers: editor.numbers, .strings: editor.strings, .characters: editor.characters,
            .comments: editor.comments
        ]
        for (role, style) in styles {
            #expect(painted[role]?.color == NSColor(style.color), "\(role.rawValue) did not take its declared colour")
            #expect(painted[role]?.bold == false)
            #expect(painted[role]?.italic == false)
        }
    }
}
