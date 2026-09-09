import Testing
import Foundation
@testable import AgenticToolkitCore

/// An in-memory `ThemeStorage`. AgenticDeveloperToolkitUITests has a double of
/// its own, but that target is not reachable from here, and the protocol is
/// three `{ get set }` requirements on an `AnyObject` — nothing about
/// exercising the store's wiring needs a disk.
@MainActor
private final class InMemoryThemeStorage: ThemeStorage {
    var customThemes: [ColorTheme] = []
    var activeThemeID: String?
    /// Never invoked here: `onExternalChange` fires for writes that bypass
    /// `ThemeStore`, and these tests make none.
    var onExternalChange: (() -> Void)?
}

@MainActor
@Suite
struct VSCodeThemeImporterTests {

    // MARK: - Fixtures

    /// The sixteen ANSI keys in the slot order the importer must produce.
    /// Restated here rather than read back out of the importer: a test that
    /// asks the table under test what it contains cannot catch it being wrong.
    private static let ansiKeyNames = [
        "terminal.ansiBlack", "terminal.ansiRed", "terminal.ansiGreen",
        "terminal.ansiYellow", "terminal.ansiBlue", "terminal.ansiMagenta",
        "terminal.ansiCyan", "terminal.ansiWhite", "terminal.ansiBrightBlack",
        "terminal.ansiBrightRed", "terminal.ansiBrightGreen", "terminal.ansiBrightYellow",
        "terminal.ansiBrightBlue", "terminal.ansiBrightMagenta", "terminal.ansiBrightCyan",
        "terminal.ansiBrightWhite"
    ]

    /// A full theme document, spelled out. `jsoncJSON` below is this same file
    /// with JSONC syntax added, so the two must parse identically.
    ///
    /// `name` and `type` are present and both disagree with what the caller
    /// passes, which is the point: the manifest wins over the theme file.
    private static let minimalJSON = """
    {
        "name": "The Theme File's Own Name",
        "type": "light",
        "colors": {
            "editor.foreground": "#D8DEE9",
            "editor.background": "#2E3440",
            "editorCursor.foreground": "#FF00FF",
            "editor.selectionBackground": "#4C566A",
            "terminal.ansiBlack": "#000000",
            "terminal.ansiRed": "#010000",
            "terminal.ansiGreen": "#020000",
            "terminal.ansiYellow": "#030000",
            "terminal.ansiBlue": "#040000",
            "terminal.ansiMagenta": "#050000",
            "terminal.ansiCyan": "#060000",
            "terminal.ansiWhite": "#070000",
            "terminal.ansiBrightBlack": "#080000",
            "terminal.ansiBrightRed": "#090000",
            "terminal.ansiBrightGreen": "#0A0000",
            "terminal.ansiBrightYellow": "#0B0000",
            "terminal.ansiBrightBlue": "#0C0000",
            "terminal.ansiBrightMagenta": "#0D0000",
            "terminal.ansiBrightCyan": "#0E0000",
            "terminal.ansiBrightWhite": "#0F0000"
        }
    }
    """

    /// `minimalJSON` as JSONC: line and block comments, trailing commas inside
    /// both the `colors` object and the root, a `$schema` URL whose `//` is not
    /// a comment, and a string value carrying an escaped quote followed by
    /// `/* … */`. A stripper that does not track string state and backslash
    /// escapes mangles this document and fails the test.
    private static let jsoncJSON = """
    {
        // The picker shows the manifest label, never this.
        "$schema": "https://raw.githubusercontent.com/vscode/schemas/color-theme.json",
        "name": "The Theme File's Own Name",
        "author": "Someone \\" who writes /* like this */",
        "type": "light",
        /* The palette follows.
           Two lines of it, even. */
        "colors": {
            "editor.foreground": "#D8DEE9", // default editor text
            "editor.background": "#2E3440",
            "editorCursor.foreground": "#FF00FF",
            "editor.selectionBackground": "#4C566A",
            "terminal.ansiBlack": "#000000",
            "terminal.ansiRed": "#010000",
            "terminal.ansiGreen": "#020000",
            "terminal.ansiYellow": "#030000",
            "terminal.ansiBlue": "#040000",
            "terminal.ansiMagenta": "#050000",
            "terminal.ansiCyan": "#060000",
            "terminal.ansiWhite": "#070000",
            "terminal.ansiBrightBlack": "#080000",
            "terminal.ansiBrightRed": "#090000",
            "terminal.ansiBrightGreen": "#0A0000",
            "terminal.ansiBrightYellow": "#0B0000",
            "terminal.ansiBrightBlue": "#0C0000",
            "terminal.ansiBrightMagenta": "#0D0000",
            "terminal.ansiBrightCyan": "#0E0000",
            "terminal.ansiBrightWhite": "#0F0000",
        },
    }
    """

    /// `"terminal.ansiX": "#NN0000"` for every slot, the red channel carrying
    /// the slot index — so an assertion on `ansi[5]` pins slot *order*, not
    /// merely slot count.
    private static func ansiEntries(excluding excluded: Set<String> = []) -> String {
        ansiKeyNames.enumerated()
            .filter { !excluded.contains($0.element) }
            .map { "\"\($0.element)\": \"#0\(String($0.offset, radix: 16, uppercase: true))0000\"" }
            .joined(separator: ",\n")
    }

    /// Wraps colour entries in the smallest valid theme document. The two
    /// literals above spell a whole file out; every other fixture composes,
    /// because sixteen repeated ANSI lines would bury the one line that differs.
    /// Each `extras` element is a complete `"key": value` root member.
    private static func themeJSON(
        _ colorEntries: String,
        excludingANSI excluded: Set<String> = [],
        extras: [String] = []
    ) -> String {
        let head = extras.map { $0 + ",\n" }.joined()
        let body = colorEntries.isEmpty ? "" : colorEntries + ",\n"
        return """
        {
        \(head)"colors": {
        \(body)\(ansiEntries(excluding: excluded))
        }
        }
        """
    }

    private static let standardPalette = """
        "editor.foreground": "#D6DEEB",
        "editor.background": "#011627"
    """

    private func parse(
        _ json: String,
        label: String = "Acme Dark",
        uiTheme: String = "vs-dark"
    ) throws -> ColorTheme {
        try VSCodeThemeImporter.parse(Data(json.utf8), label: label, uiTheme: uiTheme)
    }

    /// Every colour a `ColorTheme` carries, as hex, so two parses can be
    /// compared without their (deliberately random) ids getting in the way.
    private func palette(_ theme: ColorTheme) -> [String] {
        ([theme.foreground, theme.background, theme.cursor, theme.selection] + theme.ansi)
            .map(\.hexString)
    }

    // MARK: - The happy path

    @Test("a minimal theme lands its five palette fields, and the manifest decides name and appearance")
    func minimalTheme() throws {
        let theme = try parse(Self.minimalJSON, label: "Acme Dark", uiTheme: "vs-dark")

        #expect(theme.name == "Acme Dark")
        #expect(theme.appearance == .dark)
        #expect(theme.isBuiltIn == false)
        #expect(theme.isImported == false)

        #expect(theme.foreground.hexString == "#D8DEE9FF")
        #expect(theme.background.hexString == "#2E3440FF")
        #expect(theme.cursor.hexString == "#FF00FFFF")
        #expect(theme.selection.hexString == "#4C566AFF")

        #expect(theme.ansi.count == ColorTheme.ansiColorCount)
        #expect(theme.hasValidPalette)
        #expect(theme.ansi[0].hexString == "#000000FF")
        #expect(theme.ansi[5].hexString == "#050000FF")
        #expect(theme.ansi[15].hexString == "#0F0000FF")
    }

    @Test("JSONC comments and trailing commas parse to exactly the strict-JSON result")
    func jsoncMatchesStrictJSON() throws {
        let strict = try parse(Self.minimalJSON)
        let jsonc = try parse(Self.jsoncJSON)

        #expect(palette(jsonc) == palette(strict))
        #expect(jsonc.name == strict.name)
        #expect(jsonc.appearance == strict.appearance)
        #expect(jsonc.roleOverrides == strict.roleOverrides)
    }

    @Test("#RRGGBBAA, #RRGGBB, #RGB and #RGBA all parse, with or without the leading hash")
    func colourForms() throws {
        let theme = try parse(Self.themeJSON("""
            "editor.foreground": "#ABCDEF12",
            "editor.background": "#123456",
            "editorCursor.foreground": "#F0A",
            "focusBorder": "#1234",
            "input.background": "abcdef"
        """))

        #expect(theme.foreground.hexString == "#ABCDEF12")
        #expect(theme.background.hexString == "#123456FF")
        #expect(theme.cursor.hexString == "#FF00AAFF")
        #expect(theme.roleOverrides[ThemeRole.outline.rawValue]?.hexString == "#11223344")
        #expect(theme.roleOverrides[ThemeRole.controlBackground.rawValue]?.hexString == "#ABCDEFFF")
    }

    // MARK: - Semantic roles

    /// The six keys, plus every near-miss the importer deliberately refuses.
    private static let allRoleKeys = """
        "editor.foreground": "#FFFFFF",
        "editor.background": "#101010",
        "sideBar.background": "#111111",
        "editorWidget.background": "#222222",
        "input.background": "#333333",
        "descriptionForeground": "#444444",
        "input.placeholderForeground": "#555555",
        "focusBorder": "#666666",
        "textLink.foreground": "#777777",
        "errorForeground": "#888888",
        "contrastBorder": "#999999",
        "editorWarning.foreground": "#AAAAAA",
        "selection.background": "#BBBBBB"
    """

    @Test("all six mapped keys become role overrides the palette reports as declared")
    func roleOverridesAreDeclared() throws {
        let theme = try parse(Self.themeJSON(Self.allRoleKeys))
        let semantic = SemanticPalette(theme: theme)

        let expected: [ThemeRole: String] = [
            .surface: "#111111FF",
            .elevatedSurface: "#222222FF",
            .controlBackground: "#333333FF",
            .secondaryText: "#444444FF",
            .placeholderText: "#555555FF",
            .outline: "#666666FF"
        ]
        #expect(theme.roleOverrides.count == expected.count)
        for (role, hex) in expected {
            #expect(theme.roleOverrides[role.rawValue]?.hexString == hex)
            #expect(semantic.declares(role))
        }
    }

    @Test("the roles that derive stay underived, even when their tempting key is present")
    func derivedRolesAreNeverDeclared() throws {
        let mapped: [ThemeRole] = [
            .surface, .elevatedSurface, .controlBackground, .secondaryText, .placeholderText, .outline
        ]

        let unmapped = try parse(Self.themeJSON(Self.standardPalette))
        let bare = SemanticPalette(theme: unmapped)
        #expect(unmapped.roleOverrides.isEmpty)
        for role in mapped {
            #expect(bare.declares(role) == false)
        }

        // The assertion that pins the mapping: even the fully populated theme,
        // which carries textLink/errorForeground/contrastBorder/selection keys,
        // must leave these four to derivation.
        let populated = SemanticPalette(theme: try parse(Self.themeJSON(Self.allRoleKeys)))
        #expect(populated.declares(.windowBackground) == false)
        #expect(populated.declares(.primaryText) == false)
        #expect(populated.declares(.selection) == false)
        #expect(populated.declares(.accent) == false)
        #expect(populated.declares(.danger) == false)
        #expect(populated.declares(.border) == false)
        #expect(populated.declares(.warning) == false)
    }

    // MARK: - Tolerated oddities

    @Test("a colour value that is null, an array or a number counts as absent, not as a failure")
    func nonStringColourValues() throws {
        let theme = try parse(Self.themeJSON("""
            "editor.foreground": "#FFFFFF",
            "editor.background": "#000000",
            "editorCursor.foreground": null,
            "sideBar.background": ["#123456"],
            "input.background": 42,
            "descriptionForeground": "rebeccapurple"
        """))

        #expect(theme.cursor == theme.foreground)
        #expect(theme.roleOverrides.isEmpty)
    }

    @Test("tokenColors and semanticTokenColors are carried past without touching the result")
    func syntaxKeysAreIgnored() throws {
        let extras = [
            """
            "tokenColors": [
                { "scope": "comment", "settings": { "foreground": "#5C6370", "fontStyle": "italic" } }
            ]
            """,
            "\"semanticTokenColors\": { \"variable.readonly\": \"#E5C07B\" }"
        ]
        let withSyntax = try parse(Self.themeJSON(Self.standardPalette, extras: extras))
        let without = try parse(Self.themeJSON(Self.standardPalette))

        #expect(palette(withSyntax) == palette(without))
        #expect(withSyntax.roleOverrides == without.roleOverrides)
    }

    @Test("an include key is ignored rather than resolved or rejected")
    func includeIsIgnored() throws {
        let withInclude = try parse(
            Self.themeJSON(Self.standardPalette, extras: ["\"include\": \"./dark-base.json\""])
        )
        let without = try parse(Self.themeJSON(Self.standardPalette))
        #expect(palette(withInclude) == palette(without))
    }

    // MARK: - Selection and cursor

    @Test("a translucent selection is composited over the background and stored opaque")
    func translucentSelectionIsComposited() throws {
        let theme = try parse(Self.themeJSON("""
            "editor.foreground": "#D6DEEB",
            "editor.background": "#011627",
            "editor.selectionBackground": "#3392FF44"
        """))

        let expected = RGBAColor(hexString: "#3392FF44")!
            .composited(over: RGBAColor(hexString: "#011627FF")!)
        #expect(theme.selection == expected)
        #expect(theme.selection.hexString.hasSuffix("FF"))
    }

    @Test("selection falls back to the inactive key, then to a blend of background toward foreground")
    func selectionFallbackChain() throws {
        let inactive = try parse(Self.themeJSON("""
            "editor.foreground": "#D6DEEB",
            "editor.background": "#011627",
            "editor.inactiveSelectionBackground": "#1D3B53"
        """))
        #expect(inactive.selection.hexString == "#1D3B53FF")

        let neither = try parse(Self.themeJSON(Self.standardPalette))
        let blended = neither.background.blended(withFraction: 0.20, of: neither.foreground)
        #expect(neither.selection == blended)
    }

    @Test("an absent editorCursor.foreground leaves the caret in the editor's own ink")
    func cursorFallsBackToForeground() throws {
        let theme = try parse(Self.themeJSON(Self.standardPalette))
        #expect(theme.cursor == theme.foreground)
    }

    // MARK: - Appearance

    @Test("uiTheme decides appearance, and an unknown one falls back to background luminance")
    func appearanceFromUITheme() throws {
        // #2E3440 is dark, so the luminance fallback — reachable only via a
        // uiTheme VS Code does not define — must say so for "aurora".
        let onDark = try ["vs", "hc-light", "vs-dark", "hc-black", "aurora"]
            .map { try parse(Self.minimalJSON, uiTheme: $0).appearance }
        #expect(onDark == [.light, .light, .dark, .dark, .dark])

        let lightJSON = Self.themeJSON("""
            "editor.foreground": "#24292E",
            "editor.background": "#FFFFFF"
        """)
        let onLight = try parse(lightJSON, uiTheme: "aurora")
        #expect(onLight.appearance == .light)
    }

    // MARK: - Rejections

    @Test("a document that is not a JSON object is rejected")
    func rootMustBeAnObject() {
        #expect(throws: VSCodeThemeParseError.notAnObject) {
            _ = try VSCodeThemeImporter.parse(Data("[1, 2]".utf8), label: "x", uiTheme: "vs-dark")
        }
    }

    @Test("a colors member that is missing, null or not an object is rejected")
    func colorsMustBeAnObject() {
        for json in ["{ \"name\": \"x\" }", "{ \"colors\": null }", "{ \"colors\": [] }"] {
            #expect(throws: VSCodeThemeParseError.missingColors) {
                _ = try VSCodeThemeImporter.parse(Data(json.utf8), label: "x", uiTheme: "vs-dark")
            }
        }
    }

    @Test("a missing editor.foreground or editor.background is rejected by name")
    func requiredColoursAreNamed() {
        #expect(throws: VSCodeThemeParseError.missingColor("editor.foreground")) {
            _ = try VSCodeThemeImporter.parse(
                Data(Self.themeJSON("\"editor.background\": \"#011627\"").utf8),
                label: "x", uiTheme: "vs-dark"
            )
        }
        #expect(throws: VSCodeThemeParseError.missingColor("editor.background")) {
            _ = try VSCodeThemeImporter.parse(
                Data(Self.themeJSON("\"editor.foreground\": \"#D6DEEB\"").utf8),
                label: "x", uiTheme: "vs-dark"
            )
        }
    }

    @Test("a missing ANSI key is rejected, and the error carries every missing name")
    func missingANSIKeysAreAllNamed() {
        let one = Self.themeJSON(Self.standardPalette, excludingANSI: ["terminal.ansiGreen"])
        #expect(throws: VSCodeThemeParseError.missingANSIColors(["terminal.ansiGreen"])) {
            _ = try VSCodeThemeImporter.parse(Data(one.utf8), label: "x", uiTheme: "vs-dark")
        }

        let several = Self.themeJSON(
            Self.standardPalette,
            excludingANSI: ["terminal.ansiBlack", "terminal.ansiCyan", "terminal.ansiBrightWhite"]
        )
        let expected = VSCodeThemeParseError.missingANSIColors([
            "terminal.ansiBlack", "terminal.ansiCyan", "terminal.ansiBrightWhite"
        ])
        #expect(throws: expected) {
            _ = try VSCodeThemeImporter.parse(Data(several.utf8), label: "x", uiTheme: "vs-dark")
        }
    }

    @Test("a theme whose foreground equals its background is rejected as unreadable")
    func foregroundMatchingBackgroundIsRejected() {
        let json = Self.themeJSON("""
            "editor.foreground": "#101010",
            "editor.background": "#101010FF"
        """)
        #expect(throws: VSCodeThemeParseError.foregroundMatchesBackground) {
            _ = try VSCodeThemeImporter.parse(Data(json.utf8), label: "x", uiTheme: "vs-dark")
        }
    }

    // MARK: - ThemeStore wiring

    @Test("importVSCodeTheme stores a locked imported theme that shows up in the catalog")
    func storeImportLocksTheTheme() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vscode-theme-\(UUID().uuidString).json")
        try Data(Self.minimalJSON.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let store = ThemeStore(storage: InMemoryThemeStorage())
        let imported = try store.importVSCodeTheme(contentsOf: url, label: "Acme Dark", uiTheme: "vs-dark")

        #expect(imported.name == "Acme Dark")
        #expect(imported.isImported)
        #expect(imported.isLocked)
        #expect(imported.isEditable == false)
        #expect(store.customThemes.map(\.id) == [imported.id])
        #expect(store.allThemes.contains(where: { $0.id == imported.id }))
    }
}
