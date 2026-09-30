<!-- leaf: implement-language/services-snippets · source: language-services-snippets.md -->

# Language Services Snippets

## Overview

Three files under `packages/apple/AgenticToolkit/Language/Snippets/` implement the `contributes.snippets` contribution point: `ExtensionSnippet.swift` models one snippet an extension contributes and converts it to an LSP `CompletionItem`; `SnippetFile.swift` reads one VS Code `.json`/`.code-snippets` file's bytes into `[ExtensionSnippet]`; `SnippetStore.swift` is the `@MainActor` `ContributionPoint` (agentictoolkit://recipes/extension-host-core-extensions-contribution-point) that reads every snippet file a loaded extension declares, buckets the results by language, and answers `snippets(forLanguage:)` for the editor's completion path. `ExtensionSnippet.body` is deliberately left as raw LSP snippet syntax, per `ExtensionSnippet.swift`'s own doc comment, because a snippet contributed by an extension *is* already an LSP concept — `LanguageServerProtocol`'s `Snippet` parser and `LSPCompletionDelegate` already know how to insert one, so no separate insertion code is written for extension snippets. `SnippetStore` is consumed by `ExtensionsCoordinator` (which constructs it) and by `LSPCompletionDelegate.completionSuggestionsRequested`, which calls `snippets?.snippets(forLanguage: languageId).map { $0.completionItem() }` to fold extension snippets into the same completion list a language server's own snippet completions travel through.

