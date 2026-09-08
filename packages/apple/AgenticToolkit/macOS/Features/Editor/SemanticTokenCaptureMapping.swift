//
//  SemanticTokenCaptureMapping.swift
//  AgenticToolkit
//

import CodeEditSourceEditor
import Foundation
import LanguageServerProtocol

/// Which LSP semantic token types are worth colouring, and as what.
///
/// A free-standing table rather than a method on the provider, so that it is
/// testable without a text view and so that the *table* is what a reviewer
/// reads.
///
/// **Why this lives in `AgenticToolkitMacOS` rather than in the Language
/// target:** `CaptureName` is declared in `CodeEditSourceEditor`, which is
/// linked only into this framework. That is a dependency fact, not a
/// preference — the Language target cannot name the type this returns.
enum SemanticTokenCaptureMapping {

    /// The `CaptureName` an LSP token type should paint with, or `nil` for a
    /// token this editor has nothing to say about.
    ///
    /// A legend string that is not an LSP-standard token type at all — servers
    /// routinely add their own — declines here, at the `init(rawValue:)`. There
    /// is no honest guess to make about a name we have never seen, and a wrong
    /// guess at this priority repaints code the grammar already had right.
    ///
    /// Matched against `SemanticTokenTypes` rather than routed through
    /// `CaptureName.fromString(_:)`: that function is a closed switch over
    /// tree-sitter's own spellings and recognises none of LSP's distinctive
    /// ones — `namespace`, `class`, `enum`, `interface`, `struct`,
    /// `typeParameter`, `enumMember`, `event`, `macro`, `modifier`, `regexp`
    /// and `operator` all return `nil` from it, and it spells the alternate
    /// `"type_alternate"`. Routing through it would map exactly the wrong
    /// subset, by coincidence of spelling, and look deliberate.
    static func captureName(forTokenType tokenType: String) -> CaptureName? {
        guard let type = SemanticTokenTypes(rawValue: tokenType) else { return nil }
        return capture(for: type)
    }

    /// The table itself.
    ///
    /// **It is deliberately partial, and that is the feature.** The semantic
    /// provider sits *ahead* of tree-sitter in the highlight-provider array, so
    /// whatever it names wins the overlap outright. Semantic tokens earn that
    /// only where a lexer is blind — whether an identifier is a type, a
    /// property, a parameter or a local. Where tree-sitter is already exact
    /// they are strictly *coarser*: a grammar separates `keywordReturn`,
    /// `keywordFunction`, `conditional`, `repeat` and `boolean`, and LSP
    /// flattens all five to `keyword`. Mapping `keyword` here would make
    /// highlighting worse the moment a language server appeared, which is the
    /// opposite of the feature.
    ///
    /// So the lexical types decline. They are spelled out in the last case
    /// rather than left to a `default:`, both because there is no coarse bucket
    /// to fall back to honestly and because an exhaustive switch is what makes
    /// the compiler tell us when `SemanticTokenTypes` grows a case nobody has
    /// ruled on.
    ///
    /// Adding a row later is a one-line change that breaks no test.
    private static func capture(for type: SemanticTokenTypes) -> CaptureName? {
        switch type {
        // Type-ish. All six collapse onto `.type` because `CaptureName` has no
        // `class`/`struct`/`enum`/`interface` case and `EditorTheme` has a
        // single `types` colour behind all of them.
        case .namespace, .type, .class, .enum, .interface, .struct:
            return .type

        // The one judgment call. A generic parameter *is* a type, but painting
        // it the same colour as the concrete types around it loses what makes
        // it interesting; `.typeAlternate` is the theme's `attributes` slot,
        // the only other type-adjacent colour there is.
        case .typeParameter:
            return .typeAlternate

        // Identifier roles — the whole reason to ask a server at all. These are
        // the distinctions a lexer cannot make, and the ones a grammar gets
        // wrong or leaves as a bare `variable`.
        case .parameter:
            return .parameter
        case .variable:
            return .variable
        case .property, .enumMember:
            return .property
        case .method:
            return .method

        // A macro reads as a call at its use site, which is what `.function`
        // paints; there is no `macro` capture to be more precise with.
        case .function, .macro:
            return .function

        // Declined. `event` has no `CaptureName` at all. The other seven are
        // places tree-sitter is exact and finer, so taking them over at this
        // priority would be a downgrade.
        case .event, .keyword, .modifier, .comment, .string, .number, .regexp, .operator:
            return nil
        }
    }
}
