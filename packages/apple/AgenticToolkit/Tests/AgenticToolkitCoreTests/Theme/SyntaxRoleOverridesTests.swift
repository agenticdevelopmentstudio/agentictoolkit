import Testing
import Foundation
@testable import AgenticToolkitCore

/// The `syntax.<role>[.bold][.italic]` key grammar that the VS Code importer
/// writes and the source-editor bridge reads.
///
/// Two things it has to be, and both are pinned here: **total** — every
/// malformed key is ignored rather than thrown on, because a theme file is
/// user-editable — and **invisible to `SemanticPalette`**, which shares the
/// `roleOverrides` dictionary with it.
@Suite
struct SyntaxRoleOverridesTests {

    // MARK: - Fixtures

    /// The smallest theme that carries `overrides`. Every value below is
    /// distinct per key so an assertion can tell which entry it got back.
    private func theme(_ overrides: [String: RGBAColor]) -> ColorTheme {
        ColorTheme(
            name: "Fixture",
            appearance: .dark,
            foreground: RGBAColor(hexString: "D6DEEBFF")!,
            background: RGBAColor(hexString: "011627FF")!,
            cursor: RGBAColor(hexString: "80A4C2FF")!,
            selection: RGBAColor(hexString: "1D3B53FF")!,
            ansi: [],
            roleOverrides: overrides
        )
    }

    /// A colour whose red channel carries `seed`, so a test can name which
    /// colour it expects without spelling six hex digits each time.
    private func color(_ seed: Int) -> RGBAColor {
        RGBAColor(hexString: String(format: "%02X1234FF", seed))!
    }

    // MARK: - Round-tripping (case 1)

    /// All ten roles × all four flag combinations, through the key and back.
    /// The colour is seeded per combination, so a key that resolved to the
    /// wrong role or dropped a flag lands the wrong colour rather than merely
    /// the wrong flag.
    @Test("overrideKey round-trips through syntaxStyles for every role and flag combination")
    func roundTrip() throws {
        let combinations = [(false, false), (true, false), (false, true), (true, true)]
        for (index, role) in SyntaxRole.allCases.enumerated() {
            for (offset, flags) in combinations.enumerated() {
                let style = SyntaxStyle(color: color(index * 4 + offset), bold: flags.0, italic: flags.1)
                let subject = theme([role.overrideKey(bold: flags.0, italic: flags.1): style.color])
                #expect(subject.syntaxStyles == [role: style])
            }
        }
    }

    @Test("the four written key shapes are spelled exactly as documented")
    func keySpelling() {
        #expect(SyntaxRole.keywords.overrideKey() == "syntax.keywords")
        #expect(SyntaxRole.keywords.overrideKey(bold: true) == "syntax.keywords.bold")
        #expect(SyntaxRole.keywords.overrideKey(italic: true) == "syntax.keywords.italic")
        #expect(SyntaxRole.keywords.overrideKey(bold: true, italic: true) == "syntax.keywords.bold.italic")
    }

    // MARK: - Reading (case 2)

    /// Writing is canonical (bold before italic) but reading is not, because a
    /// theme file is hand-editable and the flags are a set, not a sequence.
    @Test("the flags are read in either order")
    func flagsAreASet() {
        let subject = theme(["syntax.comments.italic.bold": color(1)])
        #expect(subject.syntaxStyles == [.comments: SyntaxStyle(color: color(1), bold: true, italic: true)])
    }

    // MARK: - Rejection (case 3)

    /// Each of these is ignored rather than thrown on, and contributes no
    /// style. `syntaxStyles` is a computed property with no `throws`, so the
    /// meaningful assertion is that the bad key produces *nothing* while a good
    /// key in the same theme still produces its style.
    @Test(
        "a key that is not a syntax key is ignored, never thrown on",
        arguments: [
            "syntax.nope",              // second segment is not a role
            "syntax.keywords.underline", // a suffix this grammar has no meaning for
            "syntax.keywords.bold.bold", // the same flag twice
            "syntax",                    // no role segment at all
            "syntax.",                   // an empty role segment
            "keywords",                  // no prefix
            "syntaxkeywords",            // the prefix without its separator
            "prefix.syntax.keywords"     // the prefix, but not at the front
        ]
    )
    func rejectedKeys(_ key: String) {
        #expect(theme([key: color(1)]).syntaxStyles.isEmpty)

        // …and it does not poison a well-formed key sitting beside it.
        let mixed = theme([key: color(1), "syntax.strings": color(2)])
        #expect(mixed.syntaxStyles == [.strings: SyntaxStyle(color: color(2))])
    }

    // MARK: - Coexistence with ThemeRole (cases 4 and 5)

    @Test("a plain role override is untouched by syntaxStyles and survives withSyntaxStyles")
    func roleOverridesAreUntouched() {
        let subject = theme([ThemeRole.accent.rawValue: color(9)])
        #expect(subject.syntaxStyles.isEmpty)

        let restyled = subject.withSyntaxStyles([.keywords: SyntaxStyle(color: color(1), bold: true)])
        #expect(restyled.roleOverrides[ThemeRole.accent.rawValue] == color(9))
        #expect(SemanticPalette(theme: restyled).declares(.accent))
        #expect(SemanticPalette(theme: restyled).color(.accent) == color(9))
    }

    /// The no-collision pin. `ThemeRole` rawValues are camelCase identifiers
    /// and can never contain a dot, and `SemanticPalette` looks roles up
    /// strictly by rawValue — so a theme made entirely of syntax keys must
    /// declare no role at all. If this ever fails, syntax keys have started
    /// repainting the app chrome.
    @Test("a theme of nothing but syntax keys declares no ThemeRole")
    func syntaxKeysDeclareNoRole() {
        let styles = SyntaxRole.allCases.enumerated().reduce(into: [SyntaxRole: SyntaxStyle]()) { styles, entry in
            styles[entry.element] = SyntaxStyle(color: color(entry.offset), bold: true, italic: true)
        }
        let subject = theme([:]).withSyntaxStyles(styles)
        #expect(subject.roleOverrides.count == SyntaxRole.allCases.count)

        let palette = SemanticPalette(theme: subject)
        for role in ThemeRole.allCases {
            #expect(palette.declares(role) == false, "syntax keys leaked into ThemeRole.\(role.rawValue)")
            #expect(palette.color(role) == palette.derived(role))
        }
    }

    // MARK: - Replacement (case 6)

    /// `withSyntaxStyles` replaces rather than merges, so re-importing cannot
    /// leave a key in a shape that is no longer written — a stale
    /// `syntax.keywords.bold` would outrank the fresh `syntax.keywords` under
    /// the greatest-key rule and the editor would still paint bold.
    @Test("withSyntaxStyles replaces every existing syntax key for the role")
    func replacesRatherThanMerges() {
        let subject = theme(["syntax.keywords.bold": color(1), ThemeRole.accent.rawValue: color(9)])
        let restyled = subject.withSyntaxStyles([.keywords: SyntaxStyle(color: color(2))])

        #expect(restyled.roleOverrides.keys.filter { $0.hasPrefix("syntax.") } == ["syntax.keywords"])
        #expect(restyled.syntaxStyles == [.keywords: SyntaxStyle(color: color(2))])
        #expect(restyled.roleOverrides[ThemeRole.accent.rawValue] == color(9))
    }

    @Test("withSyntaxStyles with no styles clears every syntax key and nothing else")
    func replacesWithNothing() {
        let subject = theme(["syntax.keywords.bold": color(1), ThemeRole.accent.rawValue: color(9)])
        let cleared = subject.withSyntaxStyles([:])

        #expect(cleared.syntaxStyles.isEmpty)
        #expect(cleared.roleOverrides == [ThemeRole.accent.rawValue: color(9)])
    }

    // MARK: - Determinism (case 7)

    /// Only reachable by hand-editing a theme file — the importer writes one
    /// key per role. The rule exists so that resolution is total *and* stable:
    /// dictionary iteration order is not, so "last seen wins" would answer
    /// differently between two reads of the same theme.
    @Test("two keys for one role resolve to the lexicographically greatest, stably")
    func greatestKeyWins() {
        // "syntax.keywords.italic" > "syntax.keywords.bold" > "syntax.keywords".
        let subject = theme([
            "syntax.keywords": color(1),
            "syntax.keywords.bold": color(2),
            "syntax.keywords.italic": color(3)
        ])
        let expected = SyntaxStyle(color: color(3), italic: true)
        #expect(subject.syntaxStyles == [.keywords: expected])

        // Repeated reads of the same theme agree, whatever order the dictionary
        // hands its keys over in.
        for _ in 0..<20 {
            #expect(subject.syntaxStyles == [.keywords: expected])
        }
    }
}
