<!-- leaf: implement-language/services-editor · source: language-services-editor.md -->

## Overview

`LanguageServicesEditor` is the aggregate of twelve non-UI types under
`Features/Editor` that connect an open project's text documents to whatever
language servers its `LanguageServerRegistry` has started, and that keep an
AppKit `NSTextStorage` and a domain `TextDocument` in lockstep as both local
edits and server answers arrive out of order. `LSPCompletionDelegate` and
`LSPCompletionEntry` drive the completion window, merging server items with
locally injected snippets. `LSPHoverController` shows hover cards, preferring
an overlapping diagnostic over a server request. `LSPJumpToDefinitionDelegate`
resolves `textDocument/definition` into same-file caret moves or cross-file
opens. `LSPEditorAnnotationCoordinator` witnesses `TextViewCoordinator` to
keep diagnostic marks anchored across edits and to install the squiggle
overlay. `LanguageServerStatusModel` republishes the registry's per-project
session state as a flat, sorted row list for a status UI to render.
`OpenDocumentReloader` watches the filesystem under open documents and
reloads them when the disk changes out from under a clean buffer.
`ProjectLanguageServices` is the per-project composition root that starts and
shuts down a project's registry, diagnostics, and document-sync pipeline in a
fixed order. `SemanticTokenCaptureMapping` and `SemanticTokenHighlightProvider`
turn `textDocument/semanticTokens/full` responses into `HighlightProviding`
ranges, narrowing what a server declares against what this component can
represent and recording every narrowing. `TextDocumentCoordinator` owns a
project's `TextDocument` set, its save scheduler, and its reloader across
open/close/terminate. `TextDocumentStorage` is the `NSTextStorage` subclass
that bridges AppKit's text system to a `TextDocument`, guarding against
reentrant rewrites when either side edits the other.

Every entry point that touches AppKit state is `@MainActor`; several conform
to protocols (`TextViewCoordinator`, `JumpToDefinitionDelegate`) that are not
themselves `@MainActor`-isolated, so their witnesses are declared `nonisolated`
and reach main-actor state through `MainActor.assumeIsolated`. Every
LSP-derived value is guarded by a monotonic stamp, clock, or generation
counter so that a request or fetch superseded by a newer one cannot overwrite
what the newer one already published.

## Behavioral Requirements
