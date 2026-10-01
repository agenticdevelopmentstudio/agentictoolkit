---
id: f5432726-5b0f-47c5-b0f6-c0b19a9db5bb
title: VS Code Diagnostics Bridge
domain: agentictoolkit://cookbook/workspace/extensions/vscode-api/languages/main-thread-diagnostics
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: The vscode.languages diagnostics slice — createDiagnosticCollection, getDiagnostics,
  and the debounced onDidChangeDiagnostics event — bridging an in-memory diagnostic
  store to extension code.
platforms:
- swift
- macos
tags:
- extension-host
- vscode-api
- diagnostics
- event-emitter
depends-on:
- agentictoolkit://cookbook/workspace/extensions/vscode-api/languages/diagnostic-types
- agentictoolkit://cookbook/workspace/extensions/host/extension-event
related: []
references:
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadDiagnostics.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Extensions/MainThreadDiagnosticsTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/DiagnosticTypes.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/HostDiagnosticSink.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/ExtensionEvent.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/VSCodeAPI.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadWindow.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Loggable.swift (agentictoolkit)
approved-by: ''
approved-date: ''
---

# VS Code Diagnostics Bridge

## Overview

This component gives extension code the `vscode.languages` diagnostics
slice: `createDiagnosticCollection`, `getDiagnostics`, and the debounced
`onDidChangeDiagnostics` event (`vscode.d.ts`, `:14807`, `:14814`). It is
two cooperating parts. The diagnostic store (holding only plain values —
a URL and a diagnostic value, never a script value) is the storage layer:
it owns collection lifecycle (creating and removing a collection),
per-collection mutation (`set`, `setEntries`, `delete`, `clear`),
per-collection reads (`get`, `has`, `pairs`), and cross-collection reads
(diagnostics for one `Uri`, and all diagnostics). This component is the
extension-facing adaptor built on top of it: it validates and decodes
every argument arriving from extension code, builds the extension-visible
`DiagnosticCollection` object each `createDiagnosticCollection` call
returns, and publishes the shared, debounced `onDidChangeDiagnostics`
emitter. Every mutating operation reports the URLs it touched to an
injected diagnostic sink; the sink, not this adaptor, fires the event —
the host diagnostic sink is the production conformer, and its own
documentation explains why the event's read half (`onDidChangeDiagnostics`,
published here) and write half (reporting changed URLs, called here but
implemented in the sink) sit on opposite sides of that seam. This
component ports upstream VS Code's own diagnostics implementation
closely, including two upstream quirks it keeps rather than "fixes" (the
array-set overload's stable-sort-by-`Uri`-string cleanup asymmetry, and
`clear()`/`dispose()` not firing on an already-empty collection under an
earlier reading — see Design Decisions), and diverges from it in one
place it states plainly: a disposed collection's methods are inert no-ops
rather than throwing, with precedent cited from this codebase's own
status-bar-item handling.

## Behavioral Requirements

- **no-jsvalue-capture-in-store**: the diagnostic store MUST hold only
  plain values (a URL, a diagnostic value) in its stored collection
  state; it MUST NOT store a script value or a script context.
- **no-defaulted-seams**: constructing this component MUST NOT default
  any of the store, sink, or event-emitter arguments; a caller that
  omitted one would silently disconnect that seam while still compiling,
  per the component's own documentation drawing the same comparison to
  the languages bridge's store and vocabulary arguments.
- **collection-name-collision-keeps-name-uniquifies-owner**: creating a
  collection MUST, when the requested name is non-empty and already in
  use, keep the returned name equal to the requested name while
  uniquifying only the internal owner key (e.g. `"eslint0"`), matching
  upstream VS Code, so two `createDiagnosticCollection("eslint")` calls
  both report `.name === "eslint"` yet are distinct collections.
- **collection-name-generated-when-omitted**: creating a collection MUST,
  when the requested name is empty or omitted, generate both the
  internal owner key and the returned name as
  `_generated_diagnostic_collection_name_#<n>`, where `<n>` is the shared
  id counter's current value before incrementing.
- **id-pool-shared-across-branches**: the id counter MUST be a single
  counter shared by both the name-collision case and the generated-name
  case of creating a collection, matching upstream VS Code's single
  counter, rather than one counter per case.
- **remove-collection-returns-affected-uris**: removing a collection MUST
  return every URL the removed collection held (in its stored order) and
  MUST return an empty list for an owner key the store does not contain.
- **single-uri-set-nil-is-removal**: setting diagnostics for a single
  `Uri` MUST treat an absent diagnostics argument as removing that `Uri`
  from the collection, not as storing an empty list, matching upstream
  VS Code.
- **single-uri-set-non-nil-replaces**: setting diagnostics for a single
  `Uri` MUST replace that `Uri`'s entire diagnostics list with the
  supplied list rather than appending to it.
- **single-uri-set-no-op-on-absent-owner**: `set`, `setEntries`, `delete`,
  and `clear` MUST each be a no-op returning an empty list when the owner
  key is not present in the store.
- **array-set-overload-merges-repeated-uris**: applying an entries batch
  MUST merge (append to, not replace) the diagnostics of repeated
  same-`Uri` tuples within one array-taking `set` call, per `vscode.d.ts`'s
  documented "entries are merged" contract, not last-tuple-wins.
- **array-set-overload-sorts-by-uri-string**: applying an entries batch
  MUST stable-sort the input tuples by the `Uri`'s string form (ties
  broken by original index) before processing them, matching upstream
  VS Code's own tuple comparison.
- **array-set-overload-transition-cleanup-asymmetry**: applying an
  entries batch MUST, on transitioning to a new `Uri` in the sorted
  batch, delete the *previous* `Uri` from storage if it ended up empty,
  and MUST NOT perform this cleanup for the final `Uri` of the batch
  (there is no following transition to trigger it) — this asymmetry is
  upstream's own behavior and MUST be preserved, not "fixed."
- **array-set-overload-per-uri-undefined-clears-then-appends**: within
  one entries-batch call, a tuple whose diagnostics value is absent for
  a `Uri` MUST replace that `Uri`'s accumulated diagnostics with an empty
  list at the point it is processed; a later tuple for the same `Uri` in
  the same batch MUST then append to that now-empty list rather than to
  whatever preceded the absent-value tuple.
- **delete-and-clear-are-distinct**: `delete` MUST remove only the named
  `Uri`; `clear` MUST remove every `Uri` the collection holds and reset
  its stored state to empty, returning the previously-affected order.
- **get-returns-nil-for-absent-uri**: `get` MUST return an absent value —
  not an empty list — for a `Uri` the collection does not hold, matching
  `vscode.d.ts`'s declared `readonly Diagnostic[] | undefined`,
  deliberately different from upstream's own internal storage-backed
  accessor, which returns an empty list for the same case; that raw
  accessor is upstream's internal storage layer, not the interface
  contract this store's exposed `get` must match.
- **has-checks-presence-not-emptiness**: `has` MUST return `true` for a
  `Uri` present in the collection (even with an empty diagnostics list)
  and `false` for a `Uri` not present.
- **pairs-order-is-shared-source-of-truth**: reading a collection's pairs
  MUST return `(url, diagnostics)` pairs in the collection's stored
  order, and this MUST be the same order `forEach` and `Symbol.iterator`
  both read from, so the two agree by construction.
- **cross-collection-diagnostics-for-uri-concatenates-in-creation-order**:
  reading diagnostics for one `Uri` MUST concatenate every collection's
  diagnostics for that `Uri` in collection-creation order, matching
  upstream VS Code's equivalent lookup.
- **cross-collection-all-diagnostics-merges-by-first-seen-uri**: reading
  all diagnostics with no argument MUST return every `Uri` across every
  collection in first-seen order, with diagnostics merged across every
  collection holding that `Uri`, matching upstream VS Code's no-argument
  behavior.
- **adaptor-owns-only-its-created-collections**: this component MUST
  track every owner key it created, and disposing it MUST tear down only
  those collections from a possibly-shared store, never another
  adaptor's collections.
- **disposal-flag-is-reference-typed**: each collection's disposed state
  MUST be a shared, reference-typed disposal flag, not a value captured
  independently by each closure, so that both the collection object's own
  extension-visible `dispose` method and the adaptor's own disposal can
  flip the same flag from outside each other.
- **disposed-collection-methods-are-inert-not-throwing**: once a
  collection's disposal flag is set, its `set`, `delete`, `clear`, and
  `forEach` methods MUST return `undefined` and perform no mutation and
  no sink notification; `get` MUST return `undefined`; `has` MUST return
  `false` — none of the seven methods MUST throw, diverging from upstream
  VS Code, which throws on every method call of a disposed collection;
  precedent for quiet inertness over inventing a throw is this codebase's
  own "a disposed item ignores this call" handling for status bar items.
- **disposed-collection-symbol-iterator-yields-empty**: a disposed
  collection's `Symbol.iterator` MUST yield an empty sequence rather than
  causing a downstream failure from iterating an absent value.
- **disposed-collection-name-remains-readable**: the readonly `name`
  reader installed on a `DiagnosticCollection` object MUST continue to
  answer the collection's name — captured once at creation, not
  re-queried from the store — even after the collection's disposal flag
  is set.
- **collection-name-is-not-writable**: the `name` property MUST be
  installed as a read-only accessor with no setter, so an assignment such
  as `collection.name = 'tampered'` from extension code MUST be a silent
  no-op that does not change the value later reads see.
- **disposed-collection-stays-inert-after-name-reuse**: every method on a
  `DiagnosticCollection` object MUST check its disposal flag before its
  captured owner key is used to reach the store again; this ordering MUST
  hold even after a disposed collection's owner key has been reused by a
  later `createDiagnosticCollection` call, so a stale reference held by
  extension code cannot write into the collection now registered under
  that reused key.
- **create-diagnostic-collection-validates-name-argument**:
  `createDiagnosticCollection`'s handler MUST accept a first argument
  that is a string, `undefined`, or `null`; any other type MUST raise the
  exact message `"createDiagnosticCollection requires a string name, or
  no argument."`.
- **get-diagnostics-null-and-undefined-both-mean-no-argument**:
  `getDiagnostics`'s handler MUST treat both a `null` and an `undefined`
  (or omitted) first argument as the no-argument, all-diagnostics branch,
  matching upstream VS Code's own resource-presence dispatch; a present,
  non-`null`, non-`Uri` first argument MUST raise `"getDiagnostics
  requires a Uri, or no argument."`.
- **get-diagnostics-refuses-whole-array-on-undecodable-entry**: both
  branches of `getDiagnostics`'s handler MUST raise (`"Could not decode a
  diagnostic for this Uri."` for the resource branch, `"Could not decode
  a diagnostic entry."` for the no-argument branch) rather than return a
  silently shortened list when any diagnostic or pair fails to decode
  back into a value extension code can read.
- **collection-set-falsy-first-argument-clears**: `set`'s handler MUST,
  when the first argument is falsy under the extension-code truthiness
  rules (including `0`, `""`, `false`, `NaN`, `null`, `undefined`, or an
  omitted argument — but NOT an empty array, which is an object and
  therefore truthy), clear the whole collection, regardless of which
  overload the call otherwise resembles, matching upstream VS Code.
- **collection-set-dispatches-on-isarray**: `set`'s handler MUST dispatch
  to the array-taking overload when the (truthy) first argument is an
  array, and to the single-`Uri` overload otherwise; an argument that is
  truthy, not an array, and not decodable as a `Uri` MUST raise
  `"DiagnosticCollection.set requires a Uri, an entries array, or no
  argument."`.
- **collection-set-raises-on-invalid-entries-array**: an array first
  argument containing a tuple whose `Uri` slot or diagnostics slot fails
  to decode MUST raise `"Invalid entries passed to DiagnosticCollection.set."`,
  refusing the whole call rather than applying the entries that did
  decode.
- **collection-set-raises-on-invalid-diagnostics-array**: the
  single-`Uri` overload's second argument, when present and not
  decodable as `Diagnostic[] | undefined`, MUST raise `"Invalid
  diagnostics array passed to DiagnosticCollection.set."`.
- **collection-delete-requires-uri**: `delete`'s handler MUST raise
  `"DiagnosticCollection.delete requires a Uri."` when its first argument
  is missing or not decodable as a `Uri`.
- **collection-get-requires-uri-and-raises-on-decode-failure**: `get`'s
  handler MUST raise `"DiagnosticCollection.get requires a Uri."` for a
  missing/undecodable `Uri` argument, and MUST raise `"Could not decode a
  diagnostic for this Uri."` — not return `undefined` — when the stored
  diagnostics for an otherwise-valid `Uri` fail to re-encode.
- **collection-has-requires-uri**: `has`'s handler MUST raise
  `"DiagnosticCollection.has requires a Uri."` when its first argument is
  missing or not decodable as a `Uri`.
- **collection-foreach-requires-callable-callback**: `forEach`'s handler
  MUST validate its first argument with a callable check, MUST NOT accept
  a non-callable object such as `{}`, and MUST raise
  `"DiagnosticCollection.forEach requires a callback function."` on
  failure.
- **collection-foreach-third-argument-is-the-live-receiver-not-a-capture**:
  the collection object passed as the callback's third argument MUST be
  read from the live call-site receiver at call time, and MUST NOT be
  captured ahead of time when the method is installed, because a value
  captured at that point can be released before it is next needed,
  silently making every later `forEach` call iterate nothing.
- **collection-foreach-propagates-thrown-callback-exception**: a callback
  invocation that throws MUST cause `forEach`'s handler to propagate that
  exception and stop iteration immediately, mirroring upstream VS Code's
  plain loop that lets a thrown exception propagate rather than being
  swallowed or logged.
- **collection-foreach-decode-failure-raises-never-skips**: an entry that
  fails to decode during `forEach` MUST raise one of
  `"DiagnosticCollection.forEach could not decode the Uri of an entry."`,
  `"DiagnosticCollection.forEach could not decode a diagnostic for this
  Uri."`, or `"DiagnosticCollection.forEach could not invoke its
  callback."`, and MUST NOT skip past it, because `get`, `forEach`, and
  `Symbol.iterator` all read the same stored pair order and must fail
  consistently at the same entry rather than silently disagree on entry
  counts.
- **symbol-iterator-delegates-to-a-real-array**: `Symbol.iterator` MUST
  be installed so that it delegates to a genuine array's own iteration
  protocol built from the collection's stored pairs, rather than
  hand-writing a generator protocol.
- **symbol-iterator-agrees-with-foreach-order**: the pairs
  `Symbol.iterator` yields MUST be built from the same stored pair order
  `forEach` reads, and MUST raise `"Could not decode a diagnostic
  entry."` rather than silently shortening the sequence when an entry
  fails to decode.
- **sink-notified-on-every-mutation-with-affected-uris**: every mutating
  operation on a `DiagnosticCollection` — both `set` overloads, `delete`,
  `clear`, and the collection's own `dispose()` — MUST report to the
  diagnostic sink exactly the URLs that operation affected, whenever that
  set is non-empty.
- **sink-not-notified-on-reads**: `get`, `has`, `forEach`, and
  `Symbol.iterator` MUST NOT report to the diagnostic sink under any
  circumstance; only mutations notify.
- **sink-not-notified-on-empty-affected-set**: an empty `clear()` or an
  empty collection-level `dispose()` (no `Uri`s were actually removed)
  MUST NOT report to the diagnostic sink, diverging from upstream VS
  Code, which fires unconditionally; kept because the shared emitter is
  keyed by `Uri`, so an empty affected set contributes nothing to it
  either way.
- **ondidchangediagnostics-emitter-is-shared-and-not-defaulted**:
  building the shared `onDidChangeDiagnostics` emitter MUST take its
  window-scheduling dependency with no default, and the resulting emitter
  MUST be handed to every instance of this component and to the host
  diagnostic sink as the same shared object, matching upstream's one
  shared emitter per extension host rather than one per extension.
- **ondidchangediagnostics-delay-is-fifty-milliseconds**: the debounce
  delay MUST equal fifty milliseconds, matching upstream VS Code's own
  delay.
- **ondidchangediagnostics-merge-flattens-only**: the emitter's merge
  step MUST flatten the queued batches of URL lists into one URL list and
  MUST NOT deduplicate — deduplication is a separate, later step's
  responsibility, applied after flattening.
- **ondidchangediagnostics-dedups-by-uri-identity-not-object-identity**:
  the later deduplication step MUST deduplicate the flattened URLs by
  their string form, so two distinct `Uri` objects for the same path
  collapse to one entry in the delivered `uris` array.
- **ondidchangediagnostics-preserves-first-insertion-order**: the later
  deduplication step MUST preserve the first-insertion order of distinct
  URLs across the merged window, never re-sorting.
- **ondidchangediagnostics-uris-array-is-frozen**: the `uris` array on
  the delivered `{ uris }` event object MUST be frozen, so extension code
  cannot mutate it in a way that is visible to another listener or to the
  next window.
- **ondidchangediagnostics-refuses-whole-event-on-bad-uri**: building the
  delivered event MUST fail for the entire event — not a `uris` array
  silently missing one entry — if any URL fails to convert into a value
  extension code can read.
- **ondidchangediagnostics-is-a-call-signature-member-that-raises-on-teardown**:
  `onDidChangeDiagnostics` MUST be published as a call-signature member
  that raises — rather than resolving a promise — when the owning adaptor
  has been deallocated, matching `vscode.d.ts`'s `Event<T>` call-signature
  declaration, because the member answers a `Disposable` synchronously
  rather than a `Thenable`.
- **dispose-marks-disposal-flags-before-removing-from-store**: disposing
  this component MUST set every owned collection's disposal flag as part
  of the same step that removes it from the store, and this ordering MUST
  be treated as load-bearing — omitting it would leave a
  `DiagnosticCollection` object already handed to still-live extension
  code reading itself as not disposed forever, letting a stale reference
  write diagnostics into whatever collection a later
  `createDiagnosticCollection` call reused that owner key for.
- **dispose-notifies-sink-per-nonempty-removed-collection**: disposing
  this component MUST report to the diagnostic sink once per owned
  collection whose removal affected a non-empty set of URLs, and MUST NOT
  report for a collection that had none.
- **dispose-removes-only-this-adaptors-own-event-listeners**: disposing
  this component MUST remove only this adaptor's own
  `onDidChangeDiagnostics` listener registrations from the (possibly
  shared) emitter, never another adaptor's.
- **weak-capture-of-adaptor-strong-capture-of-disposal-flag**: every
  method installed on a `DiagnosticCollection` object MUST hold this
  component only weakly and MUST hold its disposal flag strongly; none of
  the installed methods MUST hold the extension-visible collection object
  itself, not even weakly.
- **loggable-conformance**: this component MUST publish log messages
  through the same shared logging seam every other extension-bridge
  component uses.

## Appearance

Not applicable — this is a script-engine bridge and in-memory store, not a visual component.

## States

Not applicable — this is a script-engine bridge and in-memory store, not a visual component. Its only lifecycle-shaped behavior is per-collection disposal (inert-but-not-thrown once its disposal flag is set) and adaptor-level disposal, both captured under Behavioral Requirements rather than as a visual-state table.

## Accessibility

Not applicable — this is a script-engine bridge and in-memory store, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| main-thread-diagnostics-001 | collection-name-collision-keeps-name-uniquifies-owner | Two `vscode.languages.createDiagnosticCollection("eslint")` calls | Both report `.name === "eslint"`; the two returned objects are distinct collections whose diagnostics do not merge — source: `MainThreadDiagnosticsTests.collidingNameKeepsNameAndMakesADistinctCollection` |
| main-thread-diagnostics-002 | collection-name-generated-when-omitted | Two `vscode.languages.createDiagnosticCollection()` calls with no name | Both `.name`s are distinct `_generated_diagnostic_collection_name_#<n>` values — `MainThreadDiagnosticsTests.omittedNameGeneratesADistinctNamePerCall` |
| main-thread-diagnostics-003 | single-uri-set-nil-is-removal, get-returns-nil-for-absent-uri | `collection.set(uri, [d])` then `collection.set(uri, undefined)`, then `collection.get(uri)` | `get(uri)` is `undefined`, not `[]` — distinct from ever storing an empty array — `MainThreadDiagnosticsTests.setUndefinedRemovesDistinctFromStoringEmptyArray` |
| main-thread-diagnostics-004 | get-returns-nil-for-absent-uri | `collection.get(neverSetUri)` on a fresh collection | Returns `undefined` — `MainThreadDiagnosticsTests.getOnAbsentUriIsUndefinedNotEmptyArray` |
| main-thread-diagnostics-005 | array-set-overload-merges-repeated-uris, array-set-overload-sorts-by-uri-string | `collection.set([[uriA, [d1]], [uriB, [d2]], [uriA, [d3]]])` | `get(uriA)` returns `[d1, d3]` (merged, not last-wins); order matches `vscode.d.ts` — `MainThreadDiagnosticsTests.arraySetOverloadMergesRepeatedUrisPerVscodeDts7189to7198` |
| main-thread-diagnostics-006 | delete-and-clear-are-distinct | `collection.set(uriA, [d1]); collection.set(uriB, [d2]); collection.delete(uriA); collection.clear()` | After `delete(uriA)`, `uriB` remains; after `clear()`, both are gone — `MainThreadDiagnosticsTests.deleteAndClearAreDistinctMutations` |
| main-thread-diagnostics-007 | collection-foreach-requires-callable-callback, collection-foreach-third-argument-is-the-live-receiver-not-a-capture | `collection.forEach(function (uri, diags, coll) { ... }, thisArg)` over a collection with several entries | Callback invoked once per `Uri` with `this === thisArg` and `coll === collection`, visiting each Uri exactly once — `MainThreadDiagnosticsTests.forEachVisitsEveryUriOnceWithCollectionAndHonoursThisArg` |
| main-thread-diagnostics-008 | symbol-iterator-delegates-to-a-real-array, symbol-iterator-agrees-with-foreach-order | `[...collection]` compared against pairs collected via `collection.forEach(...)` on the same collection | Both produce the identical sequence of `[uri, diagnostics]` pairs in the same order — `MainThreadDiagnosticsTests.symbolIteratorYieldsSamePairsAsForEachInTheSameOrder` |
| main-thread-diagnostics-009 | remove-collection-returns-affected-uris | `collection.dispose()` then a fresh `vscode.languages.createDiagnosticCollection(sameName)` | The name is free for reuse; a new distinct collection is created under it — `MainThreadDiagnosticsTests.disposeFreesTheNameForReuse` |
| main-thread-diagnostics-010 | disposed-collection-stays-inert-after-name-reuse, disposed-collection-methods-are-inert-not-throwing | `collectionA.dispose(); const collectionB = createDiagnosticCollection(sameName); collectionA.set(uri, [d])` | `collectionA.set` is a silent no-op; `collectionB`'s diagnostics for `uri` are unaffected — `MainThreadDiagnosticsTests.disposedCollectionStaysInertAfterItsNameIsReused` |
| main-thread-diagnostics-011 | adaptor-owns-only-its-created-collections, cross-collection-diagnostics-for-uri-concatenates-in-creation-order | `collectionA.set(uri, [d1]); collectionB.set(uri, [d2]); collectionA.dispose(); vscode.languages.getDiagnostics(uri)` | Returns only `[d2]` — `collectionA`'s contribution is gone, `collectionB`'s remains — `MainThreadDiagnosticsTests.disposeRemovesOnlyThisCollectionsDiagnosticsFromGetDiagnostics` |
| main-thread-diagnostics-012 | cross-collection-diagnostics-for-uri-concatenates-in-creation-order | Two collections both set diagnostics on the same `uri`; `vscode.languages.getDiagnostics(uri)` | Returns both collections' diagnostics concatenated in collection-creation order — `MainThreadDiagnosticsTests.getDiagnosticsForResourceMergesAcrossCollections` |
| main-thread-diagnostics-013 | cross-collection-all-diagnostics-merges-by-first-seen-uri | Multiple collections across multiple `Uri`s; `vscode.languages.getDiagnostics()` with no argument | Returns every `Uri` in first-seen order, diagnostics merged across every collection holding it — `MainThreadDiagnosticsTests.getDiagnosticsWithNoArgumentReturnsEveryUriMergedAcrossCollections` |
| main-thread-diagnostics-014 | get-diagnostics-null-and-undefined-both-mean-no-argument | `vscode.languages.getDiagnostics(null)` compared to `vscode.languages.getDiagnostics()` | Both calls return the identical result — `MainThreadDiagnosticsTests.getDiagnosticsWithExplicitNullMatchesTheNoArgumentResult` |
| main-thread-diagnostics-015 | sink-notified-on-every-mutation-with-affected-uris | A mock diagnostic sink; perform `set`, `setEntries`, `delete`, `clear`, and `dispose()` in turn | Sink receives exactly the affected `URL`s for each of the five calls — `MainThreadDiagnosticsTests.sinkIsNotifiedOnEveryMutatingCallWithTheRightUris` |
| main-thread-diagnostics-016 | sink-not-notified-on-reads | Same mock sink; perform `get`, `has`, `forEach`, and `[...collection]` | Sink receives zero calls across all four read operations — `MainThreadDiagnosticsTests.sinkIsNotNotifiedOnAnyReadOperation` |
| main-thread-diagnostics-017 | collection-name-is-not-writable | `collection.name = 'tampered'` then read `collection.name` | Read still returns the original name; the assignment was a silent no-op — `MainThreadDiagnosticsTests.collectionNameIsNotWritable` |
| main-thread-diagnostics-018 | adaptor-owns-only-its-created-collections, dispose-removes-only-this-adaptors-own-event-listeners | Two instances of this component sharing one store; dispose only the first | Only the first adaptor's collections are removed; the second adaptor's collections and diagnostics are untouched — `MainThreadDiagnosticsTests.adaptorDisposeTearsDownOnlyItsOwnCollections` |
| main-thread-diagnostics-019 | ondidchangediagnostics-emitter-is-shared-and-not-defaulted | Subscribe to `onDidChangeDiagnostics`; perform each of `set`, `setEntries`, `delete`, `clear`, `dispose()` in separate windows | Each of the five mutating operations produces its own delivered event — `MainThreadDiagnosticsTests.eachOfTheFiveMutatingOperationsProducesAnEvent` |
| main-thread-diagnostics-020 | ondidchangediagnostics-merge-flattens-only, ondidchangediagnostics-preserves-first-insertion-order | Two mutations for different `Uri`s within one 50ms debounce window | One delivered event whose `uris` array carries both `Uri`s — `MainThreadDiagnosticsTests.twoMutationsInOneWindowArriveAsOneEventCarryingBothUris` |
| main-thread-diagnostics-021 | ondidchangediagnostics-dedups-by-uri-identity-not-object-identity | Two distinct `Uri` objects built from the same path, each touched within one window | Delivered `uris` array contains exactly one entry for that path — `MainThreadDiagnosticsTests.twoDistinctUriObjectsForOnePathArriveAsOneEntry` |
| main-thread-diagnostics-022 | ondidchangediagnostics-preserves-first-insertion-order | Mutations touching `uriB` then `uriA` then `uriB` again within one window | Delivered `uris` array is `[uriB, uriA]` — first-insertion order, not sorted or last-touched order — `MainThreadDiagnosticsTests.firstInsertionOrderIsPreservedAcrossTheMergedWindow` |
| main-thread-diagnostics-023 | ondidchangediagnostics-uris-array-is-frozen | Receive one delivered event, attempt `event.uris.push(extraUri)` or `event.uris[0] = other`, then trigger a second event | The mutation attempt has no effect; the next delivered event's `uris` array is unaffected by the tampering attempt — `MainThreadDiagnosticsTests.theDeliveredUrisArrayIsFrozenAndTamperingDoesNotAffectTheNextEvent` |

## Edge Cases

- **Null/empty input**: an empty-string name to `createDiagnosticCollection("")` MUST be treated the same as an omitted name — a generated `_generated_diagnostic_collection_name_#<n>` — per **collection-name-generated-when-omitted** (MUST).
- **Null/empty input**: the array-taking `set` overload's entries MAY carry a tuple whose diagnostics slot is absent — this is the documented removal shape, not an error, per **array-set-overload-per-uri-undefined-clears-then-appends** (MUST).
- **Null/empty input**: `getDiagnostics(null)` MUST be treated identically to `getDiagnostics()` (no argument), per **get-diagnostics-null-and-undefined-both-mean-no-argument** (MUST) — see main-thread-diagnostics-014.
- **Boundary values**: an array-taking `set` call or a diagnostics-array decode longer than this host's maximum decodable array length (100,000 elements) MUST be refused, causing the whole `set`/array-decode call to fail rather than truncate to the first 100,000 elements (MUST).
- **Boundary values**: a falsy first argument to `set` — `0`, `""`, `false`, `NaN`, `null`, or `undefined` — clears the whole collection under **collection-set-falsy-first-argument-clears** (MUST); an *empty array* `[]`, despite being an "empty" value in the everyday sense, is an object and therefore truthy under extension-code rules, so it dispatches to the array-taking overload (applying zero entries — a no-op) rather than clearing.
- **Concurrent access**: this component is confined to a single serialized execution domain, so every call into either the diagnostic store or this component executes serialized against the same context; concurrent calls from other isolation domains MUST NOT compile without a hop, rather than a lock or queue in the source; see Platform Notes for how the confinement is enforced (MUST).
- **Error states**: a `createDiagnosticCollection`, `getDiagnostics`, or any `DiagnosticCollection` method call whose argument fails validation MUST raise a real exception with the exact message documented under Behavioral Requirements, rather than returning `undefined`/`null` silently or throwing a generic error (MUST).
- **Error states**: a disposed collection's methods MUST fail silently-inert (see **disposed-collection-methods-are-inert-not-throwing**), which is the one place this component deliberately does NOT raise on a condition that would otherwise be an error — a documented, stated divergence from upstream, not an oversight.
- **Offline or disconnected state**: not applicable — this component makes no network call and opens no file; every input it processes arrives already in memory as a value extension code supplied, and every output is delivered synchronously or via the in-process event emitter.
- **Cancellation and timeouts**: not applicable to the collection/store operations, which are all synchronous. `onDidChangeDiagnostics`'s 50ms debounce window (**ondidchangediagnostics-delay-is-fifty-milliseconds**) is a coalescing delay, not a cancellable operation; the shared window-scheduling seam deliberately offers no cancel (see the `extension-host-vs-code-api-extension-event` recipe).
- **Missing file or unreachable server**: not applicable — this component has no filesystem or network dependency of its own; every `Uri`-decoding call site here decodes/encodes a value already resident in or destined for extension code, never resolving anything against a filesystem or server.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| Store (constructor argument) | diagnostic store | none (required) | This component's storage seam; MAY be shared across multiple adaptors, each tracking only its own created collections. |
| Sink (constructor argument) | diagnostic sink | none (required) | Notified of every mutation's affected URLs; production passes the host diagnostic sink. |
| Events (constructor argument) | shared event emitter | none (required) | The shared emitter behind `onDidChangeDiagnostics`; built from a window-scheduling dependency and handed to every adaptor and to the sink alike. |
| Window (to the emitter builder) | window-scheduling seam | none (required) | The debounce window scheduler; production passes a timer-backed implementation. |
| `name` (to `createDiagnosticCollection`) | string, `undefined`, or `null` | generated `_generated_diagnostic_collection_name_#<n>` when omitted | The collection's requested name; MAY collide with an existing one (see **collection-name-collision-keeps-name-uniquifies-owner**). |
| Maximum decodable array length | integer | `100,000` | The ceiling this host enforces for any decoded diagnostics array. Not settable per call. |
| `onDidChangeDiagnostics` delay | time interval | `0.050` seconds | The debounce window width; fixed, not configurable per instance. |

## Deep Linking

Not applicable: this component defines no URL, route, or navigable destination — it installs `vscode.languages` members and bridges values, with no navigation surface of its own.

## Localization

- **hardcoded-error-messages**: every error message this component raises — `"createDiagnosticCollection requires a string name, or no argument."`, `"getDiagnostics requires a Uri, or no argument."`, `"Could not decode a diagnostic for this Uri."`, `"Could not decode a diagnostic entry."`, `"Invalid entries passed to DiagnosticCollection.set."`, `"DiagnosticCollection.set requires a Uri, an entries array, or no argument."`, `"Invalid diagnostics array passed to DiagnosticCollection.set."`, `"DiagnosticCollection.delete requires a Uri."`, `"DiagnosticCollection.get requires a Uri."`, `"DiagnosticCollection.has requires a Uri."`, `"DiagnosticCollection.forEach requires a callback function."`, `"DiagnosticCollection.forEach could not decode the Uri of an entry."`, `"DiagnosticCollection.forEach could not decode a diagnostic for this Uri."`, and `"DiagnosticCollection.forEach could not invoke its callback."` — are hardcoded English string literals with no localization key or mechanism. They are visible to the extension author that made the mistake, not to the app's own end-user UI.
- **hardcoded-log-strings**: this component logs nothing directly at these call sites; the one logging event a call into this component's decode paths can trigger — a message noting an array longer than the maximum this host decodes — is a hardcoded, unlocalized message declared in the shared decoding helper every extension-bridge component uses, including this one.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal only) | `createDiagnosticCollection requires a string name, or no argument.` | Raised when the first argument is present, not a string, and not `undefined`/`null`. |
| (none — literal only) | `getDiagnostics requires a Uri, or no argument.` | Raised when a present, non-`null` first argument does not decode as a `Uri`. |
| (none — literal only) | `Could not decode a diagnostic for this Uri.` | Raised by the resource branch of `getDiagnostics` and by `get`, when a stored diagnostic fails to re-encode. |
| (none — literal only) | `Could not decode a diagnostic entry.` | Raised by the no-argument branch of `getDiagnostics` and by the pairs-encoding step, when a stored pair fails to re-encode. |
| (none — literal only) | `Invalid entries passed to DiagnosticCollection.set.` | Raised when the array-taking overload's argument contains an undecodable tuple. |
| (none — literal only) | `DiagnosticCollection.set requires a Uri, an entries array, or no argument.` | Raised when the first argument is truthy, not an array, and not a `Uri`. |
| (none — literal only) | `Invalid diagnostics array passed to DiagnosticCollection.set.` | Raised when the single-`Uri` overload's second argument is present but not decodable. |
| (none — literal only) | `DiagnosticCollection.delete requires a Uri.` | Raised on a missing/undecodable first argument to `delete`. |
| (none — literal only) | `DiagnosticCollection.get requires a Uri.` | Raised on a missing/undecodable first argument to `get`. |
| (none — literal only) | `DiagnosticCollection.has requires a Uri.` | Raised on a missing/undecodable first argument to `has`. |
| (none — literal only) | `DiagnosticCollection.forEach requires a callback function.` | Raised when the first argument to `forEach` is not callable. |
| (none — literal only) | `DiagnosticCollection.forEach could not decode the Uri of an entry.` | Raised when an entry's stored `Uri` fails to re-encode during `forEach`. |
| (none — literal only) | `DiagnosticCollection.forEach could not decode a diagnostic for this Uri.` | Raised when an entry's diagnostics fail to re-encode during `forEach`. |
| (none — literal only) | `DiagnosticCollection.forEach could not invoke its callback.` | Raised when the callback cannot be invoked. |
| (none — literal only) | `refusing an array of <count> elements: longer than the 100000 this host decodes` | Logged inside the shared array-length helper every extension-bridge component uses, not inside this component; reached whenever this component decodes a diagnostics array. |

## Accessibility Options

Not applicable: this component renders nothing and reads no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color) — it has no UI of its own.

## Feature Flags

Not applicable: this component declares no feature-flag key and contains no conditional feature-gating logic; `createDiagnosticCollection`, `getDiagnostics`, and `onDidChangeDiagnostics` are always available once an instance of this component is constructed and installed.

## Analytics

Not applicable: this component contains no analytics or event-emission call of any kind beyond the diagnostic-sink/`onDidChangeDiagnostics` mechanism, which is functional extension-facing event delivery, not telemetry.

## Privacy

- **Data collected**: this component collects no data of its own; it stores and re-encodes whatever `Uri`, `Diagnostic` (range, message, severity, source, code, relatedInformation, tags), and collection-name values an extension supplies through `vscode.languages` calls, without retaining a copy beyond the diagnostic store's own in-memory state for the lifetime of the collections that hold them.
- **Storage**: all state lives in the diagnostic store's in-memory state; nothing in this component persists to disk or any other durable store.
- **Transmission**: this component makes no network call; it neither sends nor receives anything over a network.
- **Retention**: a collection's diagnostics are retained only until that collection's own `dispose()` or the owning adaptor's disposal removes it from the store; nothing here retains data beyond that lifetime, and a torn-down adaptor's collections are actively removed rather than merely dereferenced.

## Logging

Subsystem: this host's bundle identifier, falling back to `"nil"` | Category: the shared category declared once for every extension-bridge component, including this one

| Event | Level | Message |
|-------|-------|---------|
| An array passed for decoding reports a length over 100,000 | error | (logged inside the shared array-length helper, not inside this component): `refusing an array of <count> elements: longer than the 100000 this host decodes` |

No other event in this component is logged: this component itself contains no direct debug/error log call. The shared raise-an-exception helper — which every raised message above goes through — logs only in the extremely rare case that building the exception value itself fails, not on the ordinary path of raising a message; every other decode failure surfaces to the caller as a thrown exception or an absent return rather than a log line. The host diagnostic sink's own report-a-change step (not part of this component's given source) logs its own "diagnostics changed for <count> uri(s)" debug line on every mutation this component reports to it; that log site belongs to the sink, not to this component.

## Platform Notes

- **SwiftUI**: not applicable to this file — `MainThreadDiagnostics.swift` imports only `Foundation`, `JavaScriptCore`, `OSLog`, and `AgenticToolkitCore`, with no SwiftUI dependency; nothing here renders or observes view state.
- **AppKit / UIKit**: this is the source. `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadDiagnostics.swift` is part of the `AgenticToolkitMacOS` framework target, which `project.yml` declares `platform: macOS` only — no iOS target packages this file. It is consumed by the JS-side `vscode.languages` diagnostics machinery, and it itself consumes `DiagnosticTypes.swift`'s `VSCodeAPI.diagnostic(from:in:)`/`diagnosticValue(for:in:)` and `ExtensionEvent.swift`'s `ExtensionEventEmitter`. `ExtensionDiagnosticStore` and `MainThreadDiagnostics` MUST both be declared `@MainActor`; every call into either type happens on the thread that made the extension's call, because `JSContext`/`JSValue` are not `Sendable`.
- **Compose**: model `ExtensionDiagnosticStore` as a plain Kotlin class with a `MutableMap<String, CollectionState>` and `MutableList<String>` for `ownerOrder`, guarded by the same single-writer-thread discipline `@MainActor` gives here (a Kotlin coroutine confined to a single dispatcher, or `synchronized`, since Kotlin has no compiler-enforced actor isolation). Model the "refuse the whole array/event on one bad element" contract (**get-diagnostics-refuses-whole-array-on-undecodable-entry**, **collection-foreach-decode-failure-raises-never-skips**, **ondidchangediagnostics-refuses-whole-event-on-bad-uri**) as a decode function returning `Result<T>`/nullable rather than a partial `List`, mirroring this file's own `nil`-refuses-whole-value discipline throughout.
- **React/Web**: this is closest to the actual runtime shape — extension code in the real VS Code product already runs against the genuine `vscode.d.ts` `languages.createDiagnosticCollection`/`getDiagnostics`/`onDidChangeDiagnostics` declarations this file mirrors. A React/Web host embedding a similar extension bridge would decode/encode the same `Diagnostic`/`Uri` shapes across whatever serialization boundary (e.g. `postMessage` to a worker) replaces this file's `JSContext` boundary, and would need the same debounced, deduplicated, order-preserving, frozen-array event contract (**ondidchangediagnostics-*** requirements) for its own `onDidChangeDiagnostics` equivalent.
- **WinUI 3**: model `ExtensionDiagnosticStore` as a plain C# class with a `Dictionary<string, CollectionState>` and a `List<string>` for owner order, confined to the UI thread the way `@MainActor` confines this file (a `DispatcherQueue` check, or simply never crossing threads). Model the debounced `onDidChangeDiagnostics` emitter with a `System.Threading.Timer`-backed coalescing queue analogous to `ExtensionEventEmitter`, deduplicating by `Uri.AbsoluteUri` (the .NET analogue of `absoluteString`) and exposing the delivered collection as a `ReadOnlyCollection<Uri>` in place of `Object.freeze`. The "disposed collection is inert, not throwing" contract (**disposed-collection-methods-are-inert-not-throwing**) maps to a `DiagnosticCollection` whose methods check an `IsDisposed` boolean field first and return default values (`null`, `false`) rather than throwing `ObjectDisposedException`, a deliberate divergence from the .NET idiom that should be called out in the WinUI port's own docs the same way this file calls it out against upstream VS Code.
- **Not implemented / not applicable**: not applicable.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadDiagnostics.swift` |

## Design Decisions

**Decision**: a disposed `DiagnosticCollection`'s methods (`set`/`delete`/`clear`/`get`/`has`/`forEach`) are inert no-ops (`get`/`forEach` answer `undefined`, `has` answers `false`, `set`/`delete`/`clear` mutate nothing and notify no one), rather than throwing the way `extHostDiagnostics.ts`'s `_checkDisposed()` makes every method of a disposed collection throw.
**Rationale**: the task's own prose-only behaviors to port were the undefined-removal semantics, the array-overload merge semantics, and `get`'s absent-is-`undefined` contract; a disposed-collection throw was not among them. `MainThreadWindow.showStatusBarItem`'s own precedent — "a disposed item ignores this call" — is cited directly in the source as the reason to choose quiet inertness over inventing a new throw this task was not asked for.
**Approved**: pending

**Decision**: an empty `clear()` and an empty `dispose()` (no `Uri`s actually affected) do not notify the sink, where upstream (`extHostDiagnostics.ts`, `:48`) fires unconditionally.
**Rationale**: the shared `onDidChangeDiagnostics` emitter is keyed by `Uri`; an empty affected set contributes nothing to it whether or not the sink is called. The source's own doc names the cost if this reasoning is ever wrong — a hypothetical consumer that counts `clear()`/`dispose()` *calls* rather than changed `Uri`s would under-count — and states plainly that nothing in the current host does that.
**Approved**: pending

**Decision**: the array-taking `set` overload's cleanup of an emptied *previous* `Uri` never runs for the final `Uri` in a sorted batch (there is no following transition to trigger it), and this asymmetry is kept rather than "fixed" to run unconditionally after the loop.
**Rationale**: this is upstream's own behavior (`extHostDiagnostics.ts`'s `applyEntries`/`_compareIndexedTuplesByUri` predecessor), not a bug introduced in this port; matching upstream's edge-case behavior exactly, asymmetry included, is the stated goal of the port rather than an independent judgment about what the "correct" cleanup rule should be.
**Approved**: pending

**Decision**: `forEach`'s callback receives the collection itself (its third argument) by reading `JSContext.currentThis()` at call time rather than by capturing the `JSValue` the collection object was built as.
**Rationale**: `JSValue(newObjectIn:)` returns an autoreleased wrapper; the strong references keeping the JavaScript object alive (the context, and the JS-side variable holding it) hold nothing in Swift, so a captured reference — even a weak one — can die before the next autorelease-pool drain while the JS object lives on, making every later `forEach` call on that same collection silently iterate nothing. Reading the live receiver at call time has no such window.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | passed | Security |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |

`separation-of-concerns` passes because the file cleanly splits storage (`ExtensionDiagnosticStore`, holding only plain Swift values with no JavaScriptCore dependency) from the JS-facing adaptor (`MainThreadDiagnostics`, which validates/decodes arguments and builds JS objects), and delegates all `Diagnostic`/`Uri` decoding to `DiagnosticTypes.swift`/`Uri.swift` rather than duplicating that logic (see Overview). `unit-test-coverage` passes: `MainThreadDiagnosticsTests.swift`'s twenty-three test methods exercise name collision and generation, both `set` overloads' semantics, delete/clear distinctness, `forEach`/`Symbol.iterator` agreement, disposal freeing and inertness (including post-reuse inertness), cross-collection reads, sink notification on every mutation and on no read, name immutability, adaptor-scoped disposal, and all five documented `onDidChangeDiagnostics` behaviors (per-mutation events, window coalescing, Uri-identity dedup, insertion-order preservation, and frozen-array tamper-resistance). `explicit-error-handling` passes: every validation failure raises a specific, purpose-written JS exception message naming exactly which argument or entry failed, rather than a generic error or a swallowed `nil`; the sole deliberate exception is disposed-collection inertness, which the source documents as an intentional inert-not-thrown divergence rather than an omission. `input-sanitization` passes because every argument-decoding path (`VSCodeAPI.url(from:in:)`, `diagnosticArray`, `setEntriesArray`, the `Function` `instanceof` check) refuses a value that does not genuinely decode before acting on it, and every array walk is bounded by `VSCodeAPI.arrayLength(of:)`'s 100,000-element ceiling rather than trusting an untrusted extension's reported `length`. `no-hardcoded-strings` fails because all fourteen raised exception messages are English literals with no localization mechanism (see Localization).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/extensions/vscode-api/languages/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
