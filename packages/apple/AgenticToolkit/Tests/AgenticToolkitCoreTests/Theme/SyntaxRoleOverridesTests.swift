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
    /// The fixture also carries a `syntax.`-prefixed key the grammar *rejects*.
    /// It survives, deliberately: replacement is defined by the same parser
    /// `syntaxStyles` reads with, so the two can never disagree about what a
    /// syntax key is. The key is inert — no style, no `ThemeRole` — and a later
    /// widening of this grammar (an `underline` flag, say) may want to own it,
    /// which deleting it here would have made impossible.
    @Test("withSyntaxStyles replaces every existing syntax key for the role")
    func replacesRatherThanMerges() {
        let subject = theme([
            "syntax.keywords.bold": color(1),
            "syntax.keywords.underline": color(8),
            ThemeRole.accent.rawValue: color(9)
        ])
        let restyled = subject.withSyntaxStyles([.keywords: SyntaxStyle(color: color(2))])

        #expect(restyled.roleOverrides.keys.filter { $0.hasPrefix("syntax.") }.sorted()
            == ["syntax.keywords", "syntax.keywords.underline"])
        #expect(restyled.roleOverrides["syntax.keywords.underline"] == color(8))
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

    // MARK: - Serialization

    /// The narrow unit under the claim the whole storage decision rests on:
    /// syntax colours were put *inside* `ColorTheme` because `ColorTheme` is
    /// what travels. `roleOverrides` is decoded wholesale, so all four written
    /// shapes must come back byte-for-byte — compared as a whole dictionary,
    /// which is what catches a shape being dropped or normalised rather than
    /// merely mis-flagged. The `ThemeStore` export/import/duplicate path over
    /// the same claim is pinned in `VSCodeThemeImporterTests`.
    @Test("every syntax key shape survives a bare ColorTheme JSON round-trip")
    func syntaxKeysSurviveCodable() throws {
        var subject = theme([:]).withSyntaxStyles([
            .keywords: SyntaxStyle(color: color(1)),
            .commands: SyntaxStyle(color: color(2), bold: true),
            .strings: SyntaxStyle(color: color(3), italic: true),
            .comments: SyntaxStyle(color: color(4), bold: true, italic: true)
        ])
        // A plain role override rides along, so this also fails if the round
        // trip ever filtered `roleOverrides` down to one kind of key or the other.
        subject.roleOverrides[ThemeRole.accent.rawValue] = color(9)

        let encoded = try JSONEncoder().encode(subject)
        let decoded = try JSONDecoder().decode(ColorTheme.self, from: encoded)

        #expect(decoded.syntaxStyles == subject.syntaxStyles)
        #expect(decoded.roleOverrides == subject.roleOverrides)

        // `syntaxKeysDeclareNoRole` pins the invisibility before serialization;
        // this pins it after, so a decoder that someday coerced keys is caught.
        let palette = SemanticPalette(theme: decoded)
        for role in ThemeRole.allCases {
            #expect(palette.declares(role) == (role == .accent), "ThemeRole.\(role.rawValue)")
        }
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

        // Re-reading that same dictionary cannot answer differently — an
        // instance's iteration order is fixed for its lifetime — so the storage
        // is what has to vary: every insertion order of the three keys, each
        // over four dictionaries grown to a different capacity first, since
        // capacity is what actually decides which bucket a key lands in and so
        // the order `syntaxStyles` meets the keys in. The expected colour is
        // keyed off the insertion seed, so the assertion names *which* key won:
        // a "last seen wins" implementation lands a different colour, not
        // merely a different flag.
        let orders = [
            ["syntax.keywords", "syntax.keywords.bold", "syntax.keywords.italic"],
            ["syntax.keywords", "syntax.keywords.italic", "syntax.keywords.bold"],
            ["syntax.keywords.bold", "syntax.keywords", "syntax.keywords.italic"],
            ["syntax.keywords.bold", "syntax.keywords.italic", "syntax.keywords"],
            ["syntax.keywords.italic", "syntax.keywords", "syntax.keywords.bold"],
            ["syntax.keywords.italic", "syntax.keywords.bold", "syntax.keywords"]
        ]
        for order in orders {
            for fillers in [0, 8, 32, 128] {
                var overrides: [String: RGBAColor] = [:]
                // Grown then emptied: `Dictionary` never shrinks, so what is
                // left is three keys in a table four sizes apart.
                for filler in 0..<fillers { overrides["filler.\(filler)"] = color(filler % 100) }
                for filler in 0..<fillers { overrides.removeValue(forKey: "filler.\(filler)") }
                for (index, key) in order.enumerated() { overrides[key] = color(index + 1) }

                let seed = (order.firstIndex(of: "syntax.keywords.italic") ?? 0) + 1
                #expect(
                    theme(overrides).syntaxStyles == [.keywords: SyntaxStyle(color: color(seed), italic: true)],
                    "insertion order \(order), fillers: \(fillers)"
                )
            }
        }
    }
}
