//
//  SemanticTokenCaptureMappingTests.swift
//  AgenticToolkit
//

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
            ("typeParameter", CaptureName.typeAlternate),
            ("parameter", CaptureName.parameter),
            ("variable", CaptureName.variable),
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
        "the lexical LSP token types are declined",
        arguments: [
            // `event` has no `CaptureName` at all. The other seven are places
            // where tree-sitter is exact and *finer* — a grammar separates
            // `keywordReturn`, `keywordFunction`, `conditional`, `repeat` and
            // `boolean` where LSP has only `keyword` — so taking them over at
            // this priority would make highlighting worse the moment a server
            // appeared.
            "event", "keyword", "modifier", "comment",
            "string", "number", "regexp", "operator"
        ]
    )
    func lexicalTypesAreDeclined(tokenType: String) {
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
}
