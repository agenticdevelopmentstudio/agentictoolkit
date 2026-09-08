//
//  SemanticTokenCaptureMappingTests.swift
//  AgenticToolkit
//

import AppKit
import CodeEditSourceEditor
import Foundation
import LanguageServerProtocol
import Testing
@testable import AgenticToolkitMacOS

/// The table that decides what a language server is allowed to repaint.
///
/// Asserted as a table rather than a behaviour because that is what it is: the
/// semantic provider sits *ahead* of tree-sitter, so every row here is a
/// decision to overrule a grammar, and every omission is a decision not to.
/// A row added or removed by accident is invisible in a screenshot and obvious
/// here.
@Suite("Semantic token capture mapping")
struct SemanticTokenCaptureMappingTests {

    @Test(
        "the mapped LSP token types yield their capture",
        arguments: [
            // Everything type-shaped collapses onto `.type`: `CaptureName` has
            // no `class`/`struct`/`enum`/`interface` case and `EditorTheme`
            // has one colour behind all of them.
            ("namespace", CaptureName.type),
            ("type", CaptureName.type),
            ("class", CaptureName.type),
            ("enum", CaptureName.type),
            ("interface", CaptureName.type),
            ("struct", CaptureName.type),
            // Ruling BG. `.typeAlternate` is the theme's `attributes` slot, so
            // it would paint `T` like `@MainActor`; a generic parameter reads
            // as a type, so it is painted as one.
            ("typeParameter", CaptureName.type),
            ("parameter", CaptureName.parameter),
            ("property", CaptureName.property),
            ("enumMember", CaptureName.property),
            ("function", CaptureName.function),
            ("method", CaptureName.method),
            ("macro", CaptureName.function)
        ]
    )
    func mappedTypesYieldTheirCapture(tokenType: String, expected: CaptureName) {
        #expect(SemanticTokenCaptureMapping.captureName(forTokenType: tokenType) == expected)
    }

    @Test(
        "the declined LSP token types are declined",
        arguments: [
            // `event` has no `CaptureName` at all. Seven of the rest are places
            // where tree-sitter is exact and *finer* — a grammar separates
            // `keywordReturn`, `keywordFunction`, `conditional`, `repeat` and
            // `boolean` where LSP has only `keyword` — so taking them over at
            // this priority would make highlighting worse the moment a server
            // appeared.
            //
            // `variable` is the ninth, and it declines for a stronger reason
            // (Ruling AZ): it is the one row that could actively *undo* a
            // grammar. `EditorTheme` paints `.variable` and `.variableBuiltin`
            // in different colours, so a server's `variable` token for `self`
            // would outrank tree-sitter's `.variableBuiltin` and strip the
            // keyword colour `self` has today — while buying nothing, because
            // an ordinary variable already lands on that same `variables`
            // colour through the grammar.
            "variable", "event", "keyword", "modifier", "comment",
            "string", "number", "regexp", "operator"
        ]
    )
    func declinedTypesAreDeclined(tokenType: String) {
        #expect(SemanticTokenCaptureMapping.captureName(forTokenType: tokenType) == nil)
    }

    @Test(
        "a legend string that is not an LSP token type is declined rather than guessed at",
        arguments: [
            // Servers routinely extend the legend. `identifier` is
            // sourcekit-lsp-adjacent; `typeAlias` and `type_alternate` are the
            // near-misses that a `CaptureName.fromString` route would either
            // accept by coincidence of spelling or reject for the wrong reason.
            "identifier", "typeAlias", "type_alternate", "Type", "", "🎨"
        ]
    )
    func unknownLegendStringsAreDeclined(tokenType: String) {
        #expect(SemanticTokenCaptureMapping.captureName(forTokenType: tokenType) == nil)
    }

    @Test(
        "every mapped row resolves to the theme colour the table claims",
        arguments: [
            ("namespace", "types"),
            ("type", "types"),
            ("class", "types"),
            ("enum", "types"),
            ("interface", "types"),
            ("struct", "types"),
            ("typeParameter", "types"),
            ("parameter", "variables"),
            ("property", "variables"),
            ("enumMember", "variables"),
            ("function", "variables"),
            ("method", "variables"),
            ("macro", "variables")
        ]
    )
    @MainActor
    func rowsResolveToTheThemeColourTheTableClaims(tokenType: String, field: String) {
        let theme = makeSixteenDistinctColourTheme()
        let controller = makeEditorTextViewController(text: "", theme: theme)

        guard let capture = SemanticTokenCaptureMapping.captureName(forTokenType: tokenType) else {
            Issue.record("\(tokenType) has left the table; this test lists the table and must be updated with it")
            return
        }

        // Through `attributesFor`, which is the package's own public route from
        // a `CaptureName` to a colour, rather than a reimplementation of
        // `EditorTheme.mapCapture` here — that method is `private`, and a
        // test-local copy of it would agree with itself forever.
        let painted = controller.attributesFor(capture)[.foregroundColor] as? NSColor

        #expect(
            painted == expectedColour(named: field, in: theme),
            """
            \(tokenType) maps to \(capture), which no longer paints the theme's \(field) colour. \
            Either the theme grew a field and this row can now say something finer, or a capture was \
            re-routed underneath us. Update the table's comment as well as this list.
            """
        )
    }
}

// MARK: - The sixteen-colour theme

/// The `EditorTheme` field an expectation names, by name.
///
/// A `switch` rather than a `KeyPath`, because `EditorTheme` holds `NSColor` and
/// is therefore not `Sendable`, which disqualifies a key path from being a test
/// argument.
private func expectedColour(named field: String, in theme: EditorTheme) -> NSColor? {
    switch field {
    case "types": return theme.types.color
    case "variables": return theme.variables.color
    case "keywords": return theme.keywords.color
    case "attributes": return theme.attributes.color
    case "text": return theme.text.color
    default:
        Issue.record("no EditorTheme field named \(field)")
        return nil
    }
}

/// A theme whose sixteen fields are sixteen different colours.
///
/// The shipped palettes reuse colours across fields, so a theme derived from one
/// cannot tell you *which* field a capture landed in — only that it landed
/// somewhere that looks plausible. Sixteen distinct greys make the question
/// answerable.
private func makeSixteenDistinctColourTheme() -> EditorTheme {
    // sRGB, not `calibratedWhite`: the editor converts theme colours to HSB
    // while it builds its views, and that conversion throws on a colour in the
    // calibrated-white space rather than returning a wrong answer.
    var next = 0.0
    func distinct() -> NSColor {
        next += 1
        return NSColor(srgbRed: next / 20.0, green: 1 - next / 20.0, blue: 0.5, alpha: 1)
    }
    func attribute() -> EditorTheme.Attribute {
        EditorTheme.Attribute(color: distinct())
    }

    return EditorTheme(
        text: attribute(),
        insertionPoint: distinct(),
        invisibles: attribute(),
        background: distinct(),
        lineHighlight: distinct(),
        selection: distinct(),
        keywords: attribute(),
        commands: attribute(),
        types: attribute(),
        attributes: attribute(),
        variables: attribute(),
        values: attribute(),
        numbers: attribute(),
        strings: attribute(),
        characters: attribute(),
        comments: attribute()
    )
}
