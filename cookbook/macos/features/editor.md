---
id: 8f3c2a6e-9d41-4b8a-9c2e-7a1d5f6b3e90
title: LanguageServicesEditor
domain: agentictoolkit://cookbook/macos/features/editor
type: ingredient
version: 1.0.2
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Non-UI logic that wires a project's text documents to one or more language servers for completion, hover, jump-to-definition, diagnostics annotation, and semantic-token highlighting, and keeps their caches, marks, and watchers consistent under concurrent edits.
platforms:
  - swift
  - macos
tags:
  - language-server-protocol
  - completion
  - hover
  - jump-to-definition
  - diagnostics
  - semantic-highlighting
  - editor
  - appkit
  - concurrency
depends-on: []
related: []
references:
  - packages/apple/AgenticToolkit/macOS/Features/Editor/LSPCompletionDelegate.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/macOS/Features/Editor/LSPCompletionEntry.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/macOS/Features/Editor/LSPEditorAnnotationCoordinator.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/macOS/Features/Editor/LSPHoverController.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/macOS/Features/Editor/LSPJumpToDefinitionDelegate.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/macOS/Features/Editor/LanguageServerStatusModel.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/macOS/Features/Editor/OpenDocumentReloader.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/macOS/Features/Editor/ProjectLanguageServices.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/macOS/Features/Editor/SemanticTokenCaptureMapping.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/macOS/Features/Editor/SemanticTokenHighlightProvider.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/macOS/Features/Editor/TextDocumentCoordinator.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/macOS/Features/Editor/TextDocumentStorage.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Editor/LSPCompletionDelegateTests.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Editor/LSPCompletionEntryTests.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Editor/LSPCompletionSnippetTests.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Editor/LSPEditorAnnotationTests.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Editor/LSPJumpToDefinitionDelegateTests.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Editor/LanguageServerStatusModelTests.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Editor/OpenDocumentReloaderTests.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Editor/ProjectLanguageServicesTests.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Editor/SemanticTokenCaptureMappingTests.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Editor/SemanticTokenHighlightProviderTests.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Editor/TextDocumentStorageTests.swift (agentictoolkit)
approved-by: ''
approved-date: ''
---

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

- **completion-trigger-characters-resolved-eagerly**: `resolveTriggerCharacters()` MUST be callable independently of a completion request and MUST cache its answer keyed to the originating session, admitting a write only when its own `triggerReadClock` stamp is at or after `resolvedTriggerReadStamp` (LSPCompletionDelegate.swift).
- **completion-trigger-characters-empty-when-unresolved**: `completionTriggerCharacters()` MUST return the empty set until `resolveTriggerCharacters()` has completed at least once, and MUST return `[]` again once the serving session dies or is replaced by one declaring no `completionProvider` (LSPCompletionDelegate.swift).
- **completion-request-reads-facts-before-suspending**: `completionSuggestionsRequested(textView:cursorPosition:)` MUST read the caret offset, document URI, language id, prefix start, position, and the character immediately before the caret before its first `await`, so one request describes one consistent document version (LSPCompletionDelegate.swift).
- **completion-request-generation-guards-cache**: Every write to the cached entries, cache anchor offset, incomplete-list flag, or cache request offset from `publish(...)` MUST be gated on the request's generation still being current, so a request superseded by a newer one cannot overwrite or clear the cache the newer one owns (LSPCompletionDelegate.swift).
- **completion-snippets-independent-of-server**: Snippet items from the injected `SnippetStore` MUST be included in the completion window even when no session serves the document's language, the session declares no `completionProvider`, or the completion request throws (LSPCompletionDelegate.swift).
- **completion-context-precedence**: `completionContext(characterBeforeCaret:triggerCharacters:)` MUST answer `.triggerForIncompleteCompletions` when a refresh is pending, MUST answer `.triggerCharacter` only when the character immediately before the caret is one the server itself declared as a trigger, and MUST answer `.invoked` otherwise (LSPCompletionDelegate.swift).
- **completion-cursor-move-incomplete-list-reopens**: `completionOnCursorMove(textView:cursorPosition:)` MUST return `nil` and mark a refresh pending, rather than filter locally, when the cached list is `isIncomplete` and the caret has moved past the offset the list was requested at (LSPCompletionDelegate.swift).
- **completion-apply-extends-range-to-live-caret**: `completionWindowApplyCompletion` MUST extend the entry's stored request range forward to the live cursor position before replacing, so text typed while the window stayed open is swallowed rather than duplicated (LSPCompletionDelegate.swift).
- **completion-apply-ignores-foreign-entry-type**: `completionWindowApplyCompletion` MUST return without effect when the applied item is not an `LSPCompletionEntry`, since the completion window is shared with `JumpToDefinitionLink` (LSPCompletionDelegate.swift).
- **completion-additional-edits-bounds-and-conflict-checked**: `applicableAdditionalEdits` MUST discard an `additionalTextEdits` entry whose converted range falls outside the document's bounds, and MUST discard one that conflicts with the primary edit or an already-accepted edit, logging the conflict case via `logger.error` (LSPCompletionDelegate.swift).
- **completion-edits-applied-back-to-front**: Accepted edits MUST be sorted descending by start offset, ties broken by longer range then by original index, and applied in that order, so an edit not yet applied still describes the pre-edit characters it was converted against (LSPCompletionDelegate.swift).
- **completion-multi-edit-single-undo-group**: `completionWindowApplyCompletion` MUST wrap more than one edit in one undo group and MUST NOT open a group for a single edit (LSPCompletionDelegate.swift).
- **completion-snippet-text-strips-placeholders**: `insertionText(for:)` MUST render a `.snippet`-formatted item's text by keeping each placeholder's default text and dropping bare tabstops (LSPCompletionDelegate.swift).
- **completion-entry-carries-request-range**: `LSPCompletionEntry.requestRange` MUST be captured at request time from the server's `textEdit`/`InsertReplaceEdit.replace` range or, absent one, the caller's default range, since the range cannot be recomputed later against a moved live cursor (LSPCompletionEntry.swift).
- **completion-entry-jump-fields-nil**: `LSPCompletionEntry.pathComponents`, `.targetPosition`, and `.sourcePreview` MUST all be `nil`, since a completion entry carries no jump-to-definition target (LSPCompletionEntry.swift).
- **hover-diagnostics-take-precedence**: `present(offset:point:token:)` MUST show an overlapping diagnostic, ranked by severity, before ever asking the server for a hover, and MUST issue no request when one is found (LSPHoverController.swift).
- **hover-generation-guards-late-publish**: Every `pointerMoved(to:)` call MUST advance the generation and cancel the pending task unconditionally, and `present` MUST re-check its own token against the current generation before publishing the diagnostic result, before issuing the request, and again before publishing the server's answer (LSPHoverController.swift).
- **hover-provider-false-means-unsupported**: `declaresHoverProvider(_:)` MUST treat a bare `false` `hoverProvider` capability as unsupported and MUST treat a missing key the same way, distinguishing both from an object value, which it MUST treat as supported (LSPHoverController.swift).
- **hover-contents-markdown-only-when-declared**: `hoverText(from:)` MUST render both `MarkedString` shapes as plain text and MUST treat `MarkupContent` as markdown only when its `kind` is `.markdown` (LSPHoverController.swift).
- **hover-still-inside-range-is-a-no-op**: `pointerMoved(to:)` MUST leave the presented card alone, issuing no dismiss and no new request, while the pointer stays within the presented range (LSPHoverController.swift).
- **hover-invalidate-tears-down-without-crossing-actor**: `invalidate()` MUST advance the generation, cancel the pending task, and dismiss the card synchronously on the main actor (LSPHoverController.swift).
- **jump-nonisolated-witness-assumes-isolation**: `openLink(link:)` MUST be declared `nonisolated` to satisfy `JumpToDefinitionDelegate`'s non-`@MainActor` requirement, and MUST reach `openFile` only through `MainActor.assumeIsolated`, never a `Task` hop (LSPJumpToDefinitionDelegate.swift).
- **jump-definition-provider-false-means-unsupported**: `declaresDefinitionProvider(_:)` MUST follow the same bool-or-object rule as the hover capability check: a bare `false` and a missing key both mean unsupported, an object means supported (LSPJumpToDefinitionDelegate.swift).
- **jump-location-link-uses-selection-range**: For a `DefinitionResponse` carrying `[LocationLink]`, `queryLinks` MUST build each target from `targetSelectionRange`, never `targetRange` (LSPJumpToDefinitionDelegate.swift).
- **jump-same-file-uses-cursor-range-not-line-column**: A same-file target MUST be built from the range-based cursor-position initializer, never the line/column one, because the line/column form leaves the range unset and the same-file caret-move branch would then do nothing (LSPJumpToDefinitionDelegate.swift).
- **jump-same-file-detection-by-resolved-path**: `isSameFile(_:as:)` MUST fall back to comparing two file URIs by their standardized, symlink-resolved paths when a literal string comparison fails, so a server's own percent-encoding or a symlinked path does not turn a same-file jump into a cross-file one (LSPJumpToDefinitionDelegate.swift).
- **jump-cross-file-target-carries-empty-range**: A cross-file `JumpToDefinitionLink` MUST carry a zero-length range at offset zero, since opening a different document does not read a range into that document's own line index (LSPJumpToDefinitionDelegate.swift).
- **annotation-coordinator-witnesses-nonmainactor-protocol**: All `TextViewCoordinator` requirements MUST be declared `nonisolated`, and every one except `destroy()` MUST reach main-actor state only through `MainActor.assumeIsolated`, never a `Task` hop (LSPEditorAnnotationCoordinator.swift).
- **annotation-destroy-checks-thread-before-isolating**: `destroy()`, also reachable from a plain `deinit` under SE-0371, MUST check whether it is already running on the main thread and run `MainActor.assumeIsolated` synchronously when true, and MUST hop via a detached main-actor `Task` rather than trap when false (LSPEditorAnnotationCoordinator.swift).
- **annotation-marks-reanchored-on-edit-notification**: Diagnostic marks MUST be re-anchored from `NSTextStorage.didProcessEditingNotification`, registered to fire synchronously on the posting thread, not from a delegate's did-change-text callback, because only the notification carries the edited range and the length delta (LSPEditorAnnotationCoordinator.swift).
- **annotation-reanchor-drops-marks-inside-edit**: `reanchor(replacedStart:replacedLength:delta:)` MUST shift a mark starting at or after the replaced span by the delta, MUST leave a mark ending at or before the replaced span untouched, and MUST drop, not merely leave stale, a mark the edit lands inside (LSPEditorAnnotationCoordinator.swift).
- **annotation-diagnostic-hover-invalidated-on-republish**: `apply(_:)` MUST invalidate the hover controller when the currently presented content's origin is `.diagnostic`, since a republish means the server's complaint may have changed, and MUST leave a `.server`-origin hover card alone (LSPEditorAnnotationCoordinator.swift).
- **annotation-overlay-installed-as-subview-not-floating**: `install(in:)` MUST add the diagnostic overlay as a subview of the text view itself, not of the scroll view, so overlay rects share the text view's own coordinate space (LSPEditorAnnotationCoordinator.swift).
- **status-row-one-per-session**: `recomputeRows()` MUST emit exactly one status row per project/configuration pair present in that project's session-state snapshot, and MUST NOT synthesize a row for a configuration with no session entry (LanguageServerStatusModel.swift).
- **status-row-failed-carries-reason-and-stderr**: For a `.failed` session state, row construction MUST set the failure reason from the error's localized description and the standard-error text from the failure's captured stream, trimmed of whitespace and newlines; every other state MUST leave both empty (LanguageServerStatusModel.swift).
- **status-recompute-reads-only-delivered-snapshot**: `recomputeRows()` MUST build rows only from the snapshot delivered to its subscription closure, never by reading the registry's published properties directly inside that closure, because a `willSet`-driven publish would otherwise be read before the update it announces (LanguageServerStatusModel.swift).
- **status-rows-sorted-deterministically**: The rebuilt row list MUST be sorted by project name, then configuration name, then configuration id, then project id, so two rows tied on the first three keys still sort deterministically across runs with different dictionary-iteration order (LanguageServerStatusModel.swift).
- **status-rows-published-only-on-change**: `recomputeRows()` MUST compare the freshly built list against the currently published rows and MUST return without publishing when they are equal (LanguageServerStatusModel.swift).
- **status-project-close-drops-subscriptions-and-snapshot**: Closing a project MUST remove its entry from both the per-project registry-observation table and the snapshot table, releasing its registry subscription rather than merely leaving an empty snapshot behind (LanguageServerStatusModel.swift).
- **status-has-open-project-independent-of-services**: The open-project indicator MUST be driven from the count of observed projects, not from whether any project currently has rows, so a project whose language services failed to start is still reflected as open (LanguageServerStatusModel.swift).
- **reload-watches-directories-not-files**: `beginWatching(_:)` MUST watch the resolved parent directory of an open document's URI, refcounted per directory, and MUST create at most one directory watcher per directory regardless of how many open documents share it (OpenDocumentReloader.swift).
- **reload-start-seeds-from-open-documents**: `start()` MUST begin watching every document already present in the document store before subscribing to future open events, so app-startup ordering cannot leave an already-open document unwatched (OpenDocumentReloader.swift).
- **reload-signature-avoids-unnecessary-read**: `reloadIfNeeded(_:)` MUST compare a freshly computed file signature against the last one read for that URI and MUST return without reading the file when they are equal (OpenDocumentReloader.swift).
- **reload-deleted-file-forgets-signature-leaves-buffer**: When the file signature cannot be computed at all (deleted, renamed away, or momentarily absent), `reloadIfNeeded` MUST clear the tracked signature for that URI and MUST leave the buffer untouched (OpenDocumentReloader.swift).
- **reload-save-echo-detected-by-text-compare**: `apply(_:to:uri:readAt:)` MUST detect the reloader's own save echoing back by comparing the read text against the buffer's current text, not by tracking the write itself, and MUST no-op when they already match (OpenDocumentReloader.swift).
- **reload-dirty-buffer-left-alone-and-conflict-logged**: When the buffer is dirty and its text differs from what was read, `apply` MUST leave the buffer's text untouched, MUST log the conflict, and MUST clear the tracked signature so the next dirty-state change can retry the reload once the buffer goes clean (OpenDocumentReloader.swift).
- **reload-clean-behind-replaces-whole-buffer**: When the buffer is clean and its text differs from what was read, `apply` MUST replace the entire buffer with the full text read from disk (OpenDocumentReloader.swift).
- **reload-stale-read-discarded**: `apply` MUST discard a completed read whose signature no longer matches the URI's currently tracked signature, because a later filesystem event has already triggered another read (OpenDocumentReloader.swift).
- **reload-read-hops-off-main-actor**: `reloadIfNeeded` MUST perform the file read off the main actor, at user-initiated quality of service, and MUST re-validate the buffer's continued existence and the signature after control returns (OpenDocumentReloader.swift).
- **reload-case-insensitive-path-matching**: A delivered filesystem-event path MUST be matched against tracked URIs case-insensitively, and every tracked URI resolving to that path MUST be reloaded, not only the first (OpenDocumentReloader.swift).
- **reload-stop-idempotent-start-fresh**: `stop()` MUST clear every watcher and every tracked signature; a subsequent `start()` MUST behave as a fresh start rather than a no-op (OpenDocumentReloader.swift).
- **project-services-not-an-appfeature**: `ProjectLanguageServices` MUST NOT register as a process-lifetime app feature, since its lifetime is scoped to one project window, not the process (ProjectLanguageServices.swift).
- **project-services-start-idempotent-and-terminal-after-shutdown**: `start()` MUST be a no-op both when already started and permanently after `shutdown()` has run (ProjectLanguageServices.swift).
- **project-services-shutdown-order-sync-then-diagnostics-then-registry**: `shutdown()` MUST await the document-sync pipeline's shutdown before calling the diagnostics coordinator's shutdown, and MUST await the registry's shutdown last, so no pipeline queue is drained against servers the registry has already stopped (ProjectLanguageServices.swift).
- **project-services-shutdown-idempotent-but-counted**: `shutdown()` MUST record that it was called every time, including a call blocked by having already shut down, while performing the actual teardown at most once (ProjectLanguageServices.swift).
- **project-services-diagnostics-observe-sessions-and-documents**: `start()` MUST have the diagnostics coordinator observe both the session registry and the document store, so a document opened before its server finishes handshaking still receives diagnostics once the server answers, and a closed document's diagnostics are pruned (ProjectLanguageServices.swift).
- **semantic-provider-registered-at-index-zero**: The provider MUST be registered with the source editor ahead of the tree-sitter highlighter, since the styled-range container prioritizes the lower provider index (SemanticTokenHighlightProvider.swift).
- **semantic-fetch-clock-orders-writes**: A settling fetch MUST be admitted to storage only when its stamp is at or after the currently recorded highlights stamp, and both setup and edit-handling MUST advance the fetch clock and stamp before starting a fresh fetch, so a fetch begun before an edit can never overwrite that edit's invalidation (SemanticTokenHighlightProvider.swift).
- **semantic-nil-vs-empty-distinguishes-unknown-from-settled**: Highlights being unset MUST mean "not known yet," parking a query, and highlights being an empty, settled list MUST mean "known, and empty," answering a query immediately; only a successful store MUST transition from the first state to the second (SemanticTokenHighlightProvider.swift).
- **semantic-ragged-response-abandoned-not-settled**: A `semanticTokens/full` response whose token-data count is not a multiple of five MUST be logged and MUST abandon the fetch without storing an empty result, leaving highlights unset so a future edit or language change can retry (SemanticTokenHighlightProvider.swift).
- **semantic-request-error-settles-not-parked**: A thrown error from the semantic-tokens request MUST settle the fetch by storing an empty highlight list, answering any parked query immediately, rather than abandoning it the way a ragged response does; the catch that does this logs nothing, which the `lsp-request-failure-unsignaled` finding below covers (SemanticTokenHighlightProvider.swift).
- **semantic-query-parks-and-times-out**: A highlight query MUST park when highlights are unset and a fetch is in flight, MUST be answered exactly once, either by that fetch settling or by a fixed timeout elapsing, and MUST be answered immediately when no fetch is in flight at all (SemanticTokenHighlightProvider.swift).
- **semantic-refetch-debounced**: An edit-driven refetch MUST be started after a short fixed delay rather than immediately, so consecutive edits collapse into one request instead of one per keystroke (SemanticTokenHighlightProvider.swift).
- **semantic-apply-edit-completes-without-awaiting-refetch**: The edit-handling entry point MUST call its completion with the full-document invalidation set synchronously, without awaiting the refetch it starts, so a server round trip never sits inside the edit-handling path (SemanticTokenHighlightProvider.swift).
- **semantic-setup-resets-on-language-change**: Setup MUST clear the stored highlights, advance the fetch clock and stamp past every fetch already in flight, and start a fresh fetch, so a second setup call, such as a language change, cannot be answered from the previous language's tokens (SemanticTokenHighlightProvider.swift).
- **semantic-deinit-completes-parked-queries**: Teardown MUST cancel the in-flight fetch task and complete every parked query exactly once rather than leaving any uncalled (SemanticTokenHighlightProvider.swift).
- **semantic-unmapped-and-overlap-narrowings-recorded**: Decoding MUST tally unmapped token types and out-of-range lines and record each as one divergence-ledger entry per fetch, not per token, and MUST both log and record a dropped-overlap entry when a token's range does not start at or after the previous token's end (SemanticTokenHighlightProvider.swift).
- **semantic-decline-lexical-types-tree-sitter-already-handles**: `SemanticTokenCaptureMapping.capture(for:)` MUST map only identifier-role token types to a highlight capture and MUST return `nil` for lexical types such as keyword, string, number, comment, and operator, leaving those to the existing tree-sitter highlighter (SemanticTokenCaptureMapping.swift).
- **semantic-modifiers-discarded-and-recorded-once**: Decoding MUST discard every token's modifier bits from the emitted highlight range and MUST record a single modifiers-ignored ledger entry, with a positive count, when any token in the response carried a non-zero modifier bitmask (SemanticTokenHighlightProvider.swift).
- **semantic-full-capability-requires-explicit-true-or-object**: The full-request legend lookup MUST return `nil` when the client's declared full-request capability is a bare `false` or absent, and MUST return the legend for a bare `true` or an object value (SemanticTokenHighlightProvider.swift).
- **semantic-clip-preserves-end-to-end-layout**: Clipping stored highlight ranges to a queried range MUST intersect each range with the query and MUST drop any resulting empty intersection, because the caller lays the returned ranges end to end (SemanticTokenHighlightProvider.swift).
- **coordinator-terminate-stops-reloader-before-flush**: `terminate()` MUST stop the reloader before awaiting the save scheduler's final flush, so a reload landing between the flush and process exit cannot rewrite a buffer nothing will save again (TextDocumentCoordinator.swift).
- **coordinator-unsaved-documents-logged-only-when-nonempty**: `terminate()` MUST log, naming the count and the joined list of unsaved documents, when the final flush reports a non-empty list, and MUST log nothing when it reports an empty one (TextDocumentCoordinator.swift).
- **coordinator-default-debounce-one-second**: The coordinator's initializer MUST default its save debounce to one second when the caller supplies none (TextDocumentCoordinator.swift).
- **coordinator-reloader-started-at-init**: Initialization MUST start the reloader unconditionally as its last step, registering the document-store observer before any host code can open a document through this coordinator (TextDocumentCoordinator.swift).
- **storage-local-edit-guard-prevents-reentrant-rewrite**: `replaceCharacters(in:with:)` MUST set its local-edit guard only around the call that pushes the change into the `TextDocument`, and the external-change handler MUST return immediately while that guard is set, so pushing a local edit into the document cannot re-enter and corrupt the storage the user is mid-edit in (TextDocumentStorage.swift).
- **storage-document-updated-before-edited-notification**: `replaceCharacters(in:with:)` MUST update the `TextDocument` before calling AppKit's `edited(...)`, so an observer re-entering from inside editing notification processing, such as the annotation coordinator or the highlight provider, converts ranges against a document that already reflects the edit (TextDocumentStorage.swift).
- **storage-range-converted-before-backing-store-mutated**: `replaceCharacters(in:with:)` MUST convert the incoming range against the `TextDocument` before mutating the backing string storage, because the document still describes the pre-edit text at that point and the backing store would not (TextDocumentStorage.swift).
- **storage-external-change-full-rewrite-not-partial-replay**: The external-change handler MUST rewrite the backing string wholesale from the document's current text rather than replaying the incoming change's own range, since by the time it fires the document has already applied every change in that batch (TextDocumentStorage.swift).
- **storage-main-thread-only-primitives-fail-loudly**: The storage's string accessor, attribute accessor, and `replaceCharacters(in:with:)` MUST each assert that they are running on the main queue before touching the backing store (TextDocumentStorage.swift).
- **storage-external-change-application-count-testable**: The external-change application counter MUST increment exactly once per call that actually rewrites the backing store, and MUST NOT increment for a call turned away by the local-edit guard or carrying no change (TextDocumentStorage.swift).
- **lsp-request-failure-unsignaled**: NEEDS REVIEW: Not implemented in source. Every catch around a language-server request in this family discards the thrown error with no logging call at all — `LSPCompletionDelegate.completionSuggestionsRequested`'s completion-request catch, `LSPHoverController.present`'s hover-request catch, `LSPJumpToDefinitionDelegate.queryLinks`'s definition-request catch, and `SemanticTokenHighlightProvider.fetch`'s semantic-tokens-request catch — even though `LSPCompletionDelegate` and `SemanticTokenHighlightProvider` both conform to `Loggable` and log elsewhere, while `LSPHoverController` and `LSPJumpToDefinitionDelegate` conform to `Loggable` nowhere in either file; what is missing is a log call, or a comment stating the silence is intentional because the user-visible fallback (no completions, no hover, no jump target, no highlights) is itself considered sufficient signal, and either would settle it.
- **document-read-failure-unsignaled**: NEEDS REVIEW: Not implemented in source. `OpenDocumentReloader.reloadIfNeeded`'s catch around its injected file reader discards the thrown read error with no logging call, unlike the dirty-conflict path in the very same file, `apply(_:to:uri:readAt:)`, which logs via `Self.logger.notice`; what is missing is a log call on the caught path, or a comment saying why a transient read failure between the stat and the read needs no signal beyond the next event's retry, and either would settle it.

## Appearance

Not applicable — this is a non-UI logic component; the completion window, hover card, and diagnostic overlay it drives are owned and drawn by other, presentation-layer types.

## States

Not applicable — this is a non-UI logic component; its internal state (cached completion lists, hover generation, highlight stamps, watch refcounts) is private bookkeeping, not a presented state machine.

## Accessibility

Not applicable — this is a non-UI logic component with no view hierarchy of its own to expose to assistive technology.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|--------------|-------|----------|
| language-services-editor-001 | completion-trigger-characters-resolved-eagerly, completion-trigger-characters-empty-when-unresolved | "the server's trigger characters are resolved without a completion request having been made" / "a server that advertises no completionProvider resolves to no trigger characters" / "a failed session's cached trigger characters are dropped, not merely bypassed once" (LSPCompletionDelegateTests.swift) | Trigger characters resolve independently of a request, are empty when unsupported, and are dropped when the session fails. |
| language-services-editor-002 | completion-trigger-characters-resolved-eagerly | "a superseded trigger resolution cannot overwrite a newer one's answer" / "a trigger resolution suspended across a request that returns early still lands its answer" (LSPCompletionDelegateTests.swift) | Stamp ordering admits the newest resolution only, and a suspended resolution still lands once it completes. |
| language-services-editor-003 | completion-request-reads-facts-before-suspending, completion-context-precedence | "the request's position is the one the document computes for the caret offset" / "a request made after a trigger character says so, and says which character" / "a request made mid-identifier is invoked, with no trigger character" / "a character the server did not declare is not treated as a trigger" (LSPCompletionDelegateTests.swift) | The request context captures caret facts up front and classifies the trigger correctly in each case. |
| language-services-editor-004 | completion-request-generation-guards-cache | "a superseded request cannot wipe the cache a newer one published" / "a superseded request cannot overwrite the cache a newer one published" (LSPCompletionDelegateTests.swift) | A stale request's completion can neither clear nor overwrite a newer request's cache. |
| language-services-editor-005 | completion-snippets-independent-of-server, lsp-request-failure-unsignaled | "snippets appear when no language server serves the document" / "snippets appear when the server declares no completion provider" / "snippets appear when the completion request throws" (LSPCompletionSnippetTests.swift) | Snippets appear in the window in all three no-server-answer cases, and a thrown request answers nil with nothing cached. |
| language-services-editor-006 | completion-cursor-move-incomplete-list-reopens | "an incomplete list is re-requested rather than filtered locally" / "a complete list is filtered locally rather than re-requested" (LSPCompletionDelegateTests.swift) | An incomplete cached list forces a refresh; a complete one is filtered in place. |
| language-services-editor-007 | completion-apply-extends-range-to-live-caret, completion-entry-carries-request-range | "an item with a textEdit replaces exactly the edit's range" / "a completion applied after the user kept typing swallows what was typed" / "the request range is carried on the entry, not recomputed later" (LSPCompletionDelegateTests.swift, LSPCompletionEntryTests.swift) | The stored request range is extended to the live caret before the replacement lands. |
| language-services-editor-008 | completion-additional-edits-bounds-and-conflict-checked, completion-edits-applied-back-to-front | "a completion's additionalTextEdits land in the buffer alongside the insertion" / "additional edits are applied back-to-front so each range still means what the server meant" / "an additional edit overlapping the insertion is dropped rather than doubled" (LSPCompletionDelegateTests.swift) | Additional edits apply back-to-front, and an out-of-bounds or conflicting one is discarded. |
| language-services-editor-009 | completion-multi-edit-single-undo-group | "a completion with additional edits is one undo step, not two" (LSPCompletionDelegateTests.swift) | Multiple edits from one completion undo as a single step. |
| language-services-editor-010 | completion-snippet-text-strips-placeholders | "a snippet item inserts plain text with its placeholder syntax removed" (LSPCompletionDelegateTests.swift) | Snippet placeholder syntax is stripped, keeping each placeholder's default text. |
| language-services-editor-011 | completion-entry-jump-fields-nil | "the three jump-to-definition members of the protocol are nil for a completion" (LSPCompletionEntryTests.swift) | A completion entry reports nil for every jump-to-definition field. |
| language-services-editor-012 | completion-apply-ignores-foreign-entry-type | "an entry of a foreign type is left alone, and does not crash" (LSPCompletionDelegateTests.swift) | Applying a non-completion item through the shared window is a safe no-op. |
| language-services-editor-013 | hover-diagnostics-take-precedence | "a point inside a diagnostic shows the message and asks the server nothing" (LSPEditorAnnotationTests.swift) | A diagnostic under the pointer preempts the hover request entirely. |
| language-services-editor-014 | hover-generation-guards-late-publish | "a hover answer that arrives after the pointer moved on is not shown" / "a hover answer that is still current is shown" (LSPEditorAnnotationTests.swift) | A stale hover answer is dropped; a current one is shown. |
| language-services-editor-015 | hover-provider-false-means-unsupported | "a server advertising hoverProvider: false is never asked" (LSPEditorAnnotationTests.swift) | A server declaring no hover support is never queried. |
| language-services-editor-016 | hover-contents-markdown-only-when-declared | "all three Hover.contents shapes reduce to the expected text" (LSPEditorAnnotationTests.swift) | Each of the three hover-contents shapes renders to the correct plain or markdown text. |
| language-services-editor-017 | hover-invalidate-tears-down-without-crossing-actor | "destroy removes the overlay and takes the card down" / "destroy called off the main thread tears down instead of trapping" (LSPEditorAnnotationTests.swift) | Teardown removes the overlay and dismisses the hover card whether invoked on or off the main thread. |
| language-services-editor-018 | jump-definition-provider-false-means-unsupported | "a server that advertises definitionProvider as a bare false is taken at its word" (LSPJumpToDefinitionDelegateTests.swift) | A bare-false definition capability is honored as unsupported. |
| language-services-editor-019 | jump-location-link-uses-selection-range | "a LocationLink jumps to its targetSelectionRange, not its targetRange" (LSPJumpToDefinitionDelegateTests.swift) | A LocationLink response resolves to its selection range, not its full target range. |
| language-services-editor-020 | jump-same-file-uses-cursor-range-not-line-column, jump-cross-file-target-carries-empty-range | "a target in this document has no url and a real range; one elsewhere has the file's url" (LSPJumpToDefinitionDelegateTests.swift) | A same-file target carries a real range and no url; a cross-file target carries the file's url and an empty range. |
| language-services-editor-021 | jump-nonisolated-witness-assumes-isolation | "opening a cross-file link calls the injected openFile once, with the link's url" / "opening a same-file link does nothing: the package moves the caret itself" (LSPJumpToDefinitionDelegateTests.swift) | Opening a link routes cross-file links to the injected opener and leaves same-file links to the caret-move path. |
| language-services-editor-022 | lsp-request-failure-unsignaled | "a definition request that throws returns nil rather than an empty link list" (LSPJumpToDefinitionDelegateTests.swift) | A thrown definition request answers nil, with nothing logged. |
| language-services-editor-023 | annotation-marks-reanchored-on-edit-notification, annotation-reanchor-drops-marks-inside-edit | "an insertion above a mark moves the mark down by the inserted length" / "a deletion above a mark moves the mark up, and never off the end of the buffer" / "an edit below a mark leaves the mark alone" / "an edit inside a mark drops it rather than underlining the replacement" (LSPEditorAnnotationTests.swift) | Marks shift, hold, or drop correctly depending on where an edit falls relative to them. |
| language-services-editor-024 | annotation-marks-reanchored-on-edit-notification | "the re-anchored marks reach the overlay, not just the coordinator" (LSPEditorAnnotationTests.swift) | Re-anchored marks propagate to the drawn overlay, not only to internal state. |
| language-services-editor-025 | annotation-destroy-checks-thread-before-isolating | "destroy stops the coordinator re-anchoring against further edits" (LSPEditorAnnotationTests.swift) | Torn-down coordinators no longer react to subsequent edit notifications. |
| language-services-editor-026 | annotation-overlay-installed-as-subview-not-floating | "the overlay is transparent to the mouse everywhere inside it" (LSPEditorAnnotationTests.swift) | The overlay never intercepts pointer events meant for the text view beneath it. |
| language-services-editor-027 | status-row-one-per-session | "the status rows are one per project per server the registry has a session for" / "a configuration with no session has no row, and the list has no status to show for it" (LanguageServerStatusModelTests.swift) | Rows exist one-to-one with sessions and never for a session-less configuration. |
| language-services-editor-028 | status-row-failed-carries-reason-and-stderr | "a failed row carries the reason and what the server wrote on its error output" (LanguageServerStatusModelTests.swift) | A failed session's row carries both the failure reason and its captured stderr text. |
| language-services-editor-029 | status-project-close-drops-subscriptions-and-snapshot, status-has-open-project-independent-of-services | "opening a project adds its rows" / "closing a project removes its rows and releases its registry" / "an open project with no language services is still an open project" (LanguageServerStatusModelTests.swift) | Rows appear on open, disappear and release on close, and the open-project count tracks projects, not their row output. |
| language-services-editor-030 | status-rows-sorted-deterministically | "two projects with the same name running the same server hold a stable order" (LanguageServerStatusModelTests.swift) | Rows tied on name and configuration still sort in a stable, deterministic order. |
| language-services-editor-031 | reload-watches-directories-not-files, reload-start-seeds-from-open-documents | "two documents in one directory share a single watcher, released only when both close" / "a document already open when start() runs is watched" (OpenDocumentReloaderTests.swift) | One watcher serves a shared directory, refcounted per document, and startup seeds watches for already-open documents. |
| language-services-editor-032 | reload-signature-avoids-unnecessary-read | "a second event for a file that did not change reads nothing" / "a file that changed since the last read is read again" (OpenDocumentReloaderTests.swift) | An unchanged signature skips the read; a changed one triggers it. |
| language-services-editor-033 | reload-deleted-file-forgets-signature-leaves-buffer | "a deleted file leaves the buffer intact" / "a file that went away is read again when it returns" (OpenDocumentReloaderTests.swift) | A deleted file's buffer is untouched, and its return is detected because the signature was forgotten. |
| language-services-editor-034 | reload-save-echo-detected-by-text-compare, reload-clean-behind-replaces-whole-buffer | "a clean buffer takes on the text that arrived on disk" / "a save echoing back changes nothing" (OpenDocumentReloaderTests.swift) | A clean buffer adopts genuinely different disk text and stays put on its own echoed save. |
| language-services-editor-035 | reload-dirty-buffer-left-alone-and-conflict-logged | "a dirty buffer is left alone" (OpenDocumentReloaderTests.swift) | A dirty buffer's text is untouched when disk content diverges from it. |
| language-services-editor-036 | reload-case-insensitive-path-matching | "an event for a sibling nobody has open is ignored" (OpenDocumentReloaderTests.swift) | An event for an untracked path in a watched directory triggers no reload. |
| language-services-editor-037 | reload-stop-idempotent-start-fresh | "stop() releases every watcher" (OpenDocumentReloaderTests.swift) | Stopping releases every active watcher. |
| language-services-editor-038 | project-services-shutdown-order-sync-then-diagnostics-then-registry | "shutdown drains the document sync before it stops the servers" (ProjectLanguageServicesTests.swift) | The sync pipeline drains before the registry stops its servers. |
| language-services-editor-039 | project-services-start-idempotent-and-terminal-after-shutdown, project-services-shutdown-idempotent-but-counted | "shutdown is idempotent, and start after it does nothing" (ProjectLanguageServicesTests.swift) | Repeated shutdown performs teardown once; start after shutdown is a permanent no-op. |
| language-services-editor-040 | project-services-diagnostics-observe-sessions-and-documents | "closing a document prunes its diagnostics from the project's store" (ProjectLanguageServicesTests.swift) | Closing a document removes its diagnostics from the project's diagnostics store. |
| language-services-editor-041 | semantic-fetch-clock-orders-writes | "a superseded fetch released late does not overwrite newer data" (SemanticTokenHighlightProviderTests.swift) | A late-settling superseded fetch cannot overwrite the highlights a newer fetch already stored. |
| language-services-editor-042 | semantic-nil-vs-empty-distinguishes-unknown-from-settled, semantic-query-parks-and-times-out | "a query issued before the first fetch resolves is answered once, with the fetched data" / "a query whose fetch never answers is still completed exactly once" (SemanticTokenHighlightProviderTests.swift) | A parked query is answered exactly once, whether by the fetch settling or by the timeout. |
| language-services-editor-043 | semantic-ragged-response-abandoned-not-settled | "a token array whose count is not a multiple of five is refused rather than decoded" (SemanticTokenHighlightProviderTests.swift) | A malformed token array is refused, leaving highlights unset rather than settled empty. |
| language-services-editor-044 | semantic-request-error-settles-not-parked | "a query after an unreadable response is answered at once rather than parked for the timeout" (SemanticTokenHighlightProviderTests.swift) | An unreadable response still answers a subsequent query immediately, without a timeout wait. |
| language-services-editor-045 | semantic-refetch-debounced, semantic-apply-edit-completes-without-awaiting-refetch | "two edits in quick succession collapse to one refetch" / "applyEdit answers without waiting for the refetch" (SemanticTokenHighlightProviderTests.swift) | Rapid edits collapse to one debounced refetch, and edit handling itself never waits on that refetch. |
| language-services-editor-046 | semantic-setup-resets-on-language-change | "a second setUp does not answer from the tokens the first one fetched" (SemanticTokenHighlightProviderTests.swift) | A second setup call answers from the new language's tokens, not the previous one's. |
| language-services-editor-047 | semantic-deinit-completes-parked-queries | "a provider released with a query parked completes it rather than dropping it" (SemanticTokenHighlightProviderTests.swift) | A parked query is completed, not silently dropped, when the provider is released. |
| language-services-editor-048 | semantic-unmapped-and-overlap-narrowings-recorded | "tokens of one unmapped type are recorded once with a count, not once each" / "two unmapped types are two rows, each recorded once" (SemanticTokenHighlightProviderTests.swift) | Repeated unmapped-type occurrences collapse to one ledger row per type per fetch. |
| language-services-editor-049 | semantic-modifiers-discarded-and-recorded-once | "a response whose tokens carry no modifier bits opens no row" / "tokens carrying modifier bits are counted in one row for the document" (SemanticTokenHighlightProviderTests.swift) | Modifier bits are tallied into a single per-fetch row only when present, and never emitted on the highlight range itself. |
| language-services-editor-050 | semantic-decline-lexical-types-tree-sitter-already-handles | "a legend index past the end of the legend produces no token and shifts nothing" (SemanticTokenHighlightProviderTests.swift) | An out-of-range legend index yields no highlight and does not desynchronize the ones after it. |
| language-services-editor-051 | semantic-full-capability-requires-explicit-true-or-object | "a server that does not advertise semantic tokens is never asked, and the query answers empty" / "a server that advertises semantic tokens but refuses full requests is never asked" (SemanticTokenHighlightProviderTests.swift) | An undeclared or full-request-refusing server is never queried, and answers resolve empty immediately. |
| language-services-editor-052 | semantic-clip-preserves-end-to-end-layout | "a query is answered clipped to the range it asked about" (SemanticTokenHighlightProviderTests.swift) | A query for a sub-range receives highlights clipped exactly to that range. |
| language-services-editor-053 | storage-local-edit-guard-prevents-reentrant-rewrite | "a local edit through the storage does not re-enter the external-change handler" / "typing still does not re-enter the external-change path" (TextDocumentStorageTests.swift) | A local edit never triggers the external-change handler on itself. |
| language-services-editor-054 | storage-document-updated-before-edited-notification, storage-range-converted-before-backing-store-mutated | "typing through replaceCharacters updates storage and document identically, and bumps version" / "an observer notified during the edit sees the document already updated" (TextDocumentStorageTests.swift) | Storage and document stay identical after a local edit, and an observer notified mid-edit already sees the updated document. |
| language-services-editor-055 | storage-external-change-full-rewrite-not-partial-replay, storage-external-change-application-count-testable | "a document changed from outside via replaceAll updates storage.string" / "an external change after local edits is still observed exactly once" (TextDocumentStorageTests.swift) | An external change rewrites storage wholesale and is observed exactly once. |
| language-services-editor-056 | storage-range-converted-before-backing-store-mutated | "changeInLength is correct for an insert/delete/replace of different length" (TextDocumentStorageTests.swift) | The reported length delta is correct for insertions, deletions, and replacements of differing length. |
| language-services-editor-057 | document-read-failure-unsignaled | See OpenDocumentReloader.swift's `reloadIfNeeded`: the read-error catch has no dedicated test asserting silence, since the gap is the absence of a log call, not a return-value difference; the buffer-left-untouched behavior on read failure is exercised by "a deleted file leaves the buffer intact" (OpenDocumentReloaderTests.swift). | The buffer is untouched on a read failure; no test can observe that the failure is also unlogged. |

## Edge Cases

- **Null/empty input**: An empty completion list, an empty semantic-tokens data array, and an empty additional-edits array are all valid, settled answers, not errors — `SemanticTokenHighlightProvider.store([], stamp:)` and a completion publish with zero entries both resolve normally (SemanticTokenHighlightProvider.swift, LSPCompletionDelegate.swift).
- **Boundary values**: A zero-length diagnostic range still produces a mark at least one character wide so it remains visible on the overlay; a caret at offset zero or at the document's end is a valid completion or hover anchor with no special-cased crash path (LSPEditorAnnotationCoordinator.swift, LSPHoverController.swift).
- **Concurrent access**: `LSPCompletionDelegate` uses a request generation, `LSPHoverController` a pointer-move generation, and `SemanticTokenHighlightProvider` a fetch clock, all for the same reason — an async server answer racing a newer user action must be detectable and discardable rather than silently applied late (LSPCompletionDelegate.swift, LSPHoverController.swift, SemanticTokenHighlightProvider.swift).
- **Reentrancy**: `TextDocumentStorage`'s local-edit guard exists specifically because pushing a local AppKit edit into the `TextDocument` can re-enter the external-change handler on the same call stack; the guard is the only thing standing between a local edit and storage corruption (TextDocumentStorage.swift).
- **Multi-byte text**: Offsets and ranges throughout this family are UTF-16-based `NSRange` values converted through the shared `TextDocument`; a completion or semantic-token position after a multi-byte character (an emoji, a combining character) is converted once, by the document, rather than recomputed ad hoc by any of these twelve types.
- **Untrusted server input**: `LSPCompletionDelegate.applicableAdditionalEdits` silently discards an `additionalTextEdits` entry whose converted range falls outside the document's bounds; this is stated here as a plain fact, unflagged, because it is defensive validation of untrusted server input rather than a swallowed internal error — the correct behavior on invalid input is exactly to discard it (LSPCompletionDelegate.swift).
- **Missing file / unreachable server**: A deleted file leaves its buffer intact and its tracked signature cleared so a later reappearance is detected as a fresh change (OpenDocumentReloader.swift); a server declaring no capability for a given request (completion, hover, definition, semantic tokens) is never asked at all, which this family treats identically to "asked and answered empty."
- **Cancellation / timeouts**: A parked semantic-token query is guaranteed exactly one completion, via either the fetch settling or a fixed timeout, and teardown completes any query still parked rather than leaving its continuation dangling (SemanticTokenHighlightProvider.swift).
- **Foreign or mismatched types**: `LSPCompletionDelegate.completionWindowApplyCompletion` and the diagnostics/hover interaction both check the concrete type or origin of the item they are handed before acting, because the completion window and hover presentation are shared with types (`JumpToDefinitionLink`, diagnostic-origin hover content) this family does not own (LSPCompletionDelegate.swift, LSPEditorAnnotationCoordinator.swift).

## Configuration

| Setting | Default | Effect |
|---|---|---|
| Hover request debounce | injected per `LSPHoverController` instance | Delays issuing a hover request after pointer movement to avoid a request per pixel of movement. |
| Semantic-token refetch debounce | 300 ms (`SemanticTokenHighlightProvider`) | Collapses consecutive edits into one `semanticTokens/full` request. |
| Semantic-token query timeout | 5 seconds (`SemanticTokenHighlightProvider`) | Bounds how long a parked highlight query waits for an in-flight fetch before answering empty. |
| Save debounce | 1 second, overridable at `init` (`TextDocumentCoordinator`) | Bounds how long a dirty document's write is delayed before it is flushed to disk. |
| Directory watcher factory | injected `DirectoryWatching`-conforming type (`OpenDocumentReloader`) | Substitutable for tests; production uses an FSEvents-backed implementation. |
| File reader | injected closure (`OpenDocumentReloader`) | Substitutable for tests; production reads the file at the given URL. |

## Deep Linking

Not applicable — none of these twelve types is reachable by URL or handles incoming deep links; `LSPJumpToDefinitionDelegate`'s cross-file "open" is an in-process document open through an injected opener, not a URL scheme handler.

## Localization

All server-authored text (hover contents, completion labels and detail, diagnostic messages) is displayed as the server sent it and is not translated by this family. The one locally authored string surface is `TextDocumentCoordinator.terminate()`'s unsaved-documents log message, which is a developer-facing log line, not user-facing UI text, and is therefore not localized.

## Accessibility Options

Not applicable — this is a non-UI logic component; any accessibility affordances belong to the presentation-layer views these types drive (the completion window, hover card, and diagnostic overlay), not to this family itself.

## Feature Flags

None of these twelve types is gated behind a feature flag; each capability (completion, hover, jump-to-definition, semantic highlighting) is instead gated per-document by the connected server's own declared capabilities, checked at the point of use (`declaresHoverProvider`, `declaresDefinitionProvider`, `fullRequestLegend`).

## Analytics

None of these twelve types emits analytics events. `LanguageServerStatusModel`'s published rows exist for a status UI to render, not for telemetry, and are not otherwise recorded.

## Privacy

Document text, completion prefixes, and hover/diagnostic content pass through this family only in memory, addressed to the language server already configured for that document's project; none of these twelve types persists, logs, or forwards document content to any destination other than that server. `TextDocumentCoordinator`'s unsaved-documents log message names document identifiers, not their content.

## Logging

Four of the twelve types conform to `Loggable`, each using the shared pattern of a `static nonisolated let logger` whose subsystem is the host app's bundle identifier and whose category is the conforming type's own name:

- `LSPCompletionDelegate` logs, via `logger.error`, a discarded `additionalTextEdits` conflict.
- `SemanticTokenHighlightProvider` logs, via `Self.logger.error`, a ragged (non-multiple-of-five) token response and a dropped-overlap token.
- `OpenDocumentReloader` logs, via `Self.logger.notice`, a dirty-buffer conflict between a local edit and a disk change.
- `TextDocumentCoordinator` logs, via `Self.logger.error`, the count and identifiers of documents `terminate()` could not flush.

`LSPHoverController` and `LSPJumpToDefinitionDelegate` conform to `Loggable` nowhere in either file; see the `lsp-request-failure-unsignaled` requirement for what this leaves unsignaled.

## Platform Notes

- **AppKit**: `TextDocumentStorage` subclasses `NSTextStorage` directly and is the only type in this family that touches AppKit's text-storage machinery; every other type reaches AppKit only through the `TextViewCoordinator`/`JumpToDefinitionDelegate` protocol boundary, keeping the LSP logic itself AppKit-agnostic apart from those two witness surfaces.
- **Swift concurrency**: `TextViewCoordinator` and `JumpToDefinitionDelegate` are not `@MainActor`-isolated protocols, so their witnesses in `LSPEditorAnnotationCoordinator` and `LSPJumpToDefinitionDelegate` are declared `nonisolated` and reach main-actor state through `MainActor.assumeIsolated`, never a `Task` hop, except for `destroy()`, which is also reachable from a plain, and therefore `nonisolated`, `deinit` under SE-0371 and must branch on which thread it is already running on.
- **FSEvents**: `OpenDocumentReloader` depends on an injectable `DirectoryWatching` protocol rather than calling FSEvents APIs directly, and matches paths case-insensitively to match APFS's default case-insensitive, case-preserving behavior.
- **WinUI 3**: Port the twelve types to a .NET (C#) Windows App SDK library, keeping every behavior, stamp, clock, and generation rule identical. `TextDocumentStorage` (the `NSTextStorage` subclass) becomes an adapter over the host editor control's buffer — a `RichEditBox`/`ITextDocument` (`Microsoft.UI.Text`) or a third-party code editor control — keeping the local-edit guard, updating the domain `TextDocument` before raising the edited notification, converting ranges against the document before mutating the backing store, and rewriting wholesale on external change; ranges stay UTF-16 offsets, which match .NET `string` indexing directly. `NSTextStorage.didProcessEditingNotification` becomes the control's synchronous text-changed event carrying the edited range and length delta, so `reanchor(replacedStart:replacedLength:delta:)` keeps the same shift/keep/drop rule; the `DiagnosticOverlayView` subview becomes a `Canvas` or Win2D `CanvasControl` layered inside the editor's own element so rects share its coordinate space. `@MainActor` maps to the UI thread's `DispatcherQueue`: `MainActor.assumeIsolated` becomes a `DispatcherQueue.HasThreadAccess` check (assert, then run inline), and the `destroy()` branch becomes run-inline-when-`HasThreadAccess`-else-`DispatcherQueue.TryEnqueue`; `Task` plus `Task.sleep` for the hover delay, the semantic-token debounce, and the parked-query timeout become `async`/`await` with `Task.Delay(delay, CancellationToken)` and a `CancellationTokenSource` per pending request, cancelled where the source cancels its `Task`. Combine `ObservableObject`/`AnyCancellable` in `LanguageServerStatusModel` becomes `INotifyPropertyChanged` (CommunityToolkit.Mvvm `ObservableObject`) plus `IDisposable` subscriptions, still rebuilding rows only from the delivered snapshot and raising only on change, sorted with the same four-key `OrderBy`/`ThenBy` chain; `LanguageServerStatusRow` becomes a `record` with value equality. `OpenDocumentReloader`'s injectable `DirectoryWatching` is backed by `FileSystemWatcher` (one per directory, refcounted), the off-main read becomes `await Task.Run(() => File.ReadAllTextAsync(...))` followed by a hop back via the `DispatcherQueue` and re-validation of the `FileSignature`, and path matching stays `StringComparer.OrdinalIgnoreCase` because NTFS is also case-insensitive by default. The LSP transport (`LanguageServerRegistry`, `CompletionItem`, `HoverResponse`, `DefinitionResponse`, semantic tokens) maps to an LSP client library such as `OmniSharp.Extensions.LanguageClient` or `StreamJsonRpc` over the server process's stdio via `System.Diagnostics.Process`; `SnippetStore`, `CodeSuggestionDelegate`, `HighlightProviding`, and `TextViewCoordinator` stay as C# interfaces with the same members, `Loggable`/`os` logging becomes `Microsoft.Extensions.Logging.ILogger`, undo grouping uses the control's `BeginUndoGroup`/`EndUndoGroup`, and SF Symbols in `LSPCompletionEntry` become Segoe Fluent Icons glyphs.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/Editor/` |

## Design Decisions

- Watching directories rather than individual files (`OpenDocumentReloader`) lets one FSEvents stream serve every open document in that directory and survives file replacement (a common editor and version-control save pattern), which a per-file watch on some platforms would not.
- Distinguishing "not yet known" from "known and empty" for semantic-token highlights, rather than defaulting to empty, lets a query correctly park and wait for the first fetch instead of momentarily painting a document as having no semantic highlights at all.
- Declining to map lexical token types (keyword, string, number, comment, operator) in `SemanticTokenCaptureMapping` keeps the existing tree-sitter highlighter as the source of truth for those, avoiding two highlighters disagreeing about the same span.
- Applying completion's additional edits back-to-front, by descending start offset, avoids the alternative of recomputing every subsequent edit's range after each application, which would require the same information the server's own offsets already encode.
- Routing every LSP capability check (`hoverProvider`, `definitionProvider`, the semantic-tokens full-request option) through the same bare-false-or-absent-means-unsupported rule keeps that judgment call in one place conceptually, even though each type implements its own copy, rather than risking the three checks drifting apart.

## Compliance

| Category | Check | Status |
|---|---|---|
| Best Practices | [Separation of Concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | Passed |
| Best Practices | [Unit Test Coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | Partial |
| Best Practices | [Explicit Error Handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | Partial |
| Reliability | [Graceful Degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | Passed |
| Reliability | [State Recovery](agenticdevelopercookbook://compliance/reliability#state-recovery) | Passed |
| Reliability | [Data Integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | Passed |
| Reliability | [Health Observability](agenticdevelopercookbook://compliance/reliability#health-observability) | Partial |
| Reliability | [Idempotent Operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | Passed |
| Performance | [Main Thread Freedom](agenticdevelopercookbook://compliance/performance#main-thread-freedom) | Passed |
| Performance | [Resource Efficiency](agenticdevelopercookbook://compliance/performance#resource-efficiency) | Passed |

Notes: Separation of concerns holds across all twelve types — each owns exactly one LSP capability, filesystem concern, or AppKit bridge, and none reaches into another's private state. Unit test coverage is partial because `TextDocumentCoordinator.swift` has no corresponding test file anywhere in the repository, while the other eleven types each have real, cited coverage. Explicit error handling and health observability are both partial for the same underlying reason: the two open findings noted beside the Behavioral Requirements above, where a caught error is discarded with no logging call. Graceful degradation, state recovery, data integrity, and idempotent operations are all passed on direct evidence — every async write is generation- or stamp-guarded, every lifecycle method (`start`, `shutdown`, `stop`) is idempotent, and every unsupported server capability degrades to a documented, tested fallback rather than a crash. Main thread freedom is passed because every AppKit-touching entry point asserts its thread, and every blocking file read is explicitly hopped off the main actor. Resource efficiency is passed on the refcounted directory watchers, the signature-based skip-the-read check, and the per-fetch (not per-token) divergence-ledger batching.

## Change History

| Version | Date | Author | Summary |
|---|---|---|---|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation, covering `LSPCompletionDelegate`, `LSPCompletionEntry`, `LSPEditorAnnotationCoordinator`, `LSPHoverController`, `LSPJumpToDefinitionDelegate`, `LanguageServerStatusModel`, `OpenDocumentReloader`, `ProjectLanguageServices`, `SemanticTokenCaptureMapping`, `SemanticTokenHighlightProvider`, `TextDocumentCoordinator`, and `TextDocumentStorage`. |
| 1.0.1 | 2026-09-24 | Claude | Add WinUI 3 translation guidance. |
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
