//
//  ExtensionSnippet.swift
//  AgenticToolkit
//

import Foundation
import LanguageServerProtocol

/// One snippet contributed by a VS Code extension's `contributes.snippets`
/// file.
///
/// The type is deliberately thin, because a snippet *is* already an LSP
/// concept: `body` is LSP snippet syntax, which `LanguageServerProtocol`'s
/// `Snippet` parses and `LSPCompletionDelegate` already knows how to insert.
/// Everything here beyond `body` is the bookkeeping the file format carries
/// around it.
public struct ExtensionSnippet: Sendable, Equatable {

    /// The snippet file's key for this snippet — VS Code shows it when
    /// `description` is absent.
    public let name: String

    /// What the user types to summon it.
    public let prefix: String

    /// The LSP snippet string. An array `body` is joined with "\n" at parse
    /// time, so this is always one string by the time anyone reads it.
    public let body: String

    public let description: String?

    /// The snippet file's own `scope`, split on commas and trimmed. Empty
    /// means "no further restriction beyond the manifest's `language`".
    public let scopes: [String]

    /// The extension that contributed it, for withdrawal and diagnostics.
    public let extensionIdentifier: String

    public init(
        name: String,
        prefix: String,
        body: String,
        description: String?,
        scopes: [String],
        extensionIdentifier: String
    ) {
        self.name = name
        self.prefix = prefix
        self.body = body
        self.description = description
        self.scopes = scopes
        self.extensionIdentifier = extensionIdentifier
    }

    /// Whether this snippet is offered for `language`.
    ///
    /// The manifest entry's `language` already decided that this snippet's
    /// *file* belongs to a language; a per-snippet `scope` narrows further,
    /// and only narrows — a snippet with no scope is offered wherever its
    /// file is.
    public func applies(to language: String) -> Bool {
        scopes.isEmpty || scopes.contains(language)
    }
}

extension ExtensionSnippet {

    /// This snippet as an LSP completion item. `insertTextFormat` is
    /// `.snippet` because `body` *is* LSP snippet syntax — which is what lets
    /// the existing completion machinery insert it with no new code.
    ///
    /// `textEdit` is left `nil` on purpose. The delegate's fallback chain
    /// ("the `textEdit`'s text, else `insertText`, else the label") is exactly
    /// what this wants, and a `textEdit` would have to name a document range
    /// that a snippet file — which knows nothing about any document — cannot
    /// supply.
    public func completionItem() -> CompletionItem {
        CompletionItem(
            label: prefix,
            kind: .snippet,
            // The name is the fallback because it is what VS Code shows when a
            // snippet declares no description, and an item with no detail at
            // all is a row the user cannot tell from its neighbours.
            detail: description ?? name,
            filterText: prefix,
            insertText: body,
            insertTextFormat: .snippet
        )
    }
}
