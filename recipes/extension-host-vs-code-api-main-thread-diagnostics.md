---
id: f5432726-5b0f-47c5-b0f6-c0b19a9db5bb
title: MainThreadDiagnostics
domain: agentictoolkit://recipes/extension-host-vs-code-api-main-thread-diagnostics
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: The vscode.languages diagnostics slice — createDiagnosticCollection, getDiagnostics,
  and the debounced onDidChangeDiagnostics event — bridging an in-memory diagnostic
  store to JavaScriptCore.
platforms:
- swift
- macos
tags:
- extension-host
- vscode-api
- diagnostics
- event-emitter
- mainactor
depends-on:
- agentictoolkit://recipes/extension-host-vs-code-api-diagnostic-types
- agentictoolkit://recipes/extension-host-vs-code-api-extension-event
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

# MainThreadDiagnostics

## Overview

`MainThreadDiagnostics.swift` gives the extension host's embedded `JSContext` the `vscode.languages` diagnostics slice: `createDiagnosticCollection`, `getDiagnostics`, and the debounced `onDidChangeDiagnostics` event (`vscode.d.ts:14799`, `:14807`, `:14814`). The file is two cooperating types. `ExtensionDiagnosticStore` (`@MainActor`, holding only plain Swift values — `URL` and `VSCodeAPI.ExtensionDiagnostic`, never a `JSValue`) is the storage layer: it owns collection lifecycle (`createCollection`/`removeCollection`), per-collection mutation (`set`, `setEntries`, `delete`, `clear`), per-collection reads (`get`, `has`, `pairs`), and cross-collection reads (`diagnostics(for:)`, `allDiagnostics()`). `MainThreadDiagnostics` (`@MainActor`) is the JS-facing adaptor built on top of it: it validates and decodes every JavaScriptCore argument, builds the JS-visible `DiagnosticCollection` object each `createDiagnosticCollection` call returns, and publishes the shared, debounced `onDidChangeDiagnostics` emitter. Every mutating operation reports the `URL`s it touched to an injected `ExtensionDiagnosticSink` (`diagnosticsChanged(for:)`); the sink, not this adaptor, fires the event — `HostDiagnosticSink` is the production conformer, and its own doc explains why the event's read half (`onDidChangeDiagnostics`, published here) and write half (`diagnosticsChanged(for:)`, called here but implemented in the sink) sit on opposite sides of that seam. The file ports `extHostDiagnostics.ts` closely, including two upstream quirks it keeps rather than "fixes" (the array-set overload's stable-sort-by-`uri.toString()` cleanup asymmetry, and `clear()`/`dispose()` not firing on an already-empty collection under an earlier reading — see Design Decisions), and diverges from it in one place it states plainly: a disposed collection's methods are inert no-ops rather than throwing, with precedent cited from `MainThreadWindow.showStatusBarItem`.

## Behavioral Requirements

- **main-actor-isolation**: `ExtensionDiagnosticStore` and `MainThreadDiagnostics` MUST both be declared `@MainActor`; every call into either type happens on the thread that made the extension's call, because `JSContext`/`JSValue` are not `Sendable`.
- **no-jsvalue-capture-in-store**: `ExtensionDiagnosticStore` MUST hold only plain Swift values (`URL`, `VSCodeAPI.ExtensionDiagnostic`) in its `collections`/`ownerOrder` state; it MUST NOT store a `JSValue` or `JSContext`.
- **no-defaulted-seams**: `MainThreadDiagnostics.init(store:sink:events:)` MUST NOT default any of `store`, `sink`, or `events`; a caller that omitted one would silently disconnect that seam while still compiling, per the type's own doc comparing this to `MainThreadLanguages`'s `store`/`vocabulary` parameters.
- **collection-name-collision-keeps-name-uniquifies-owner**: `ExtensionDiagnosticStore.createCollection(name:)` MUST, when `name` is non-empty and already in use, keep the returned `name` equal to the requested `name` while uniquifying only the internal `owner` key (e.g. `"eslint0"`), per `extHostDiagnostics.ts:280-291`, so two `createDiagnosticCollection("eslint")` calls both report `.name === "eslint"` yet are distinct collections.
- **collection-name-generated-when-omitted**: `createCollection(name:)` MUST, when `name` is `nil` or empty, generate both `owner` and `name` as `_generated_diagnostic_collection_name_#<n>`, where `<n>` is the shared `idPool` counter's current value before incrementing.
- **id-pool-shared-across-branches**: `idPool` MUST be a single counter shared by both the name-collision branch and the generated-name branch of `createCollection(name:)`, matching `extHostDiagnostics.ts`'s single `_idPool`, rather than one counter per branch.
- **remove-collection-returns-affected-uris**: `removeCollection(owner:)` MUST return every `URL` the removed collection held (its `order` array) and MUST return an empty array for an `owner` the store does not contain.
- **single-uri-set-nil-is-removal**: `set(owner:uri:diagnostics:)` MUST treat a `nil` `diagnostics` argument as removing that `Uri` from the collection, not as storing an empty array, per `extHostDiagnostics.ts:77-81`.
- **single-uri-set-non-nil-replaces**: `set(owner:uri:diagnostics:)` MUST replace the `Uri`'s entire diagnostics array with the supplied non-`nil` array rather than appending to it.
- **single-uri-set-no-op-on-absent-owner**: `set`, `setEntries`, `delete`, and `clear` MUST each be a no-op returning an empty array when `owner` is not present in `collections`.
- **array-set-overload-merges-repeated-uris**: `CollectionState.applyEntries(_:)` MUST merge (append to, not replace) the diagnostics of repeated same-`Uri` tuples within one array-taking `set` call, per `vscode.d.ts:7189-7198`'s documented "entries are merged" contract, not last-tuple-wins.
- **array-set-overload-sorts-by-uri-string**: `applyEntries(_:)` MUST stable-sort the input tuples by `uri.absoluteString` (ties broken by original index) before processing them, porting `extHostDiagnostics.ts`'s `_compareIndexedTuplesByUri`.
- **array-set-overload-transition-cleanup-asymmetry**: `applyEntries(_:)` MUST, on transitioning to a new `Uri` in the sorted batch, delete the *previous* `Uri` from storage if it ended up empty, and MUST NOT perform this cleanup for the final `Uri` of the batch (there is no following transition to trigger it) — this asymmetry is upstream's own behavior and MUST be preserved, not "fixed."
- **array-set-overload-per-uri-undefined-clears-then-appends**: within one `applyEntries(_:)` call, a tuple whose `diagnostics` is `nil` for a `Uri` MUST replace that `Uri`'s accumulated diagnostics with an empty array at the point it is processed; a later tuple for the same `Uri` in the same batch MUST then append to that now-empty array rather than to whatever preceded the `nil` tuple.
- **delete-and-clear-are-distinct**: `delete(owner:uri:)` MUST remove only the named `Uri`; `clear(owner:)` MUST remove every `Uri` the collection holds and reset both `order` and `diagnostics` to empty, returning the previously-affected order.
- **get-returns-nil-for-absent-uri**: `get(owner:uri:)` MUST return `nil` — not an empty array — for a `Uri` the collection does not hold, matching `vscode.d.ts:7230`'s declared `readonly Diagnostic[] | undefined`, deliberately different from `extHostDiagnostics.ts`'s own internal `#data`-backed accessor, which returns `[]` for the same case; that raw accessor is upstream's internal storage layer, not the interface contract this store's exposed `get` must match.
- **has-checks-presence-not-emptiness**: `has(owner:uri:)` MUST return `true` for a `Uri` present in the collection (even with an empty diagnostics array) and `false` for a `Uri` not present.
- **pairs-order-is-shared-source-of-truth**: `pairs(owner:)` MUST return `(url, diagnostics)` pairs in `order`'s stored sequence, and this MUST be the same order `forEach` and `Symbol.iterator` both read from, so the two agree by construction.
- **cross-collection-diagnostics-for-uri-concatenates-in-creation-order**: `diagnostics(for uri:)` MUST concatenate every collection's diagnostics for `uri` in collection-creation order (`ownerOrder`), per `extHostDiagnostics.ts:337-344`'s `_getDiagnostics`.
- **cross-collection-all-diagnostics-merges-by-first-seen-uri**: `allDiagnostics()` MUST return every `Uri` across every collection in first-seen order, with diagnostics merged across every collection holding that `Uri`, per `extHostDiagnostics.ts:320-333`'s no-argument branch.
- **adaptor-owns-only-its-created-collections**: `MainThreadDiagnostics` MUST track every `owner` it created in `ownedOwners`, and its `dispose()` MUST tear down only those collections from a possibly-shared `store`, never another adaptor's collections.
- **disposal-flag-is-reference-typed**: each collection's disposed state MUST be a `DisposalFlag` reference type (a boxed `Bool`), not a value captured by a closure, so that both the collection object's own JS-visible `dispose` method and the adaptor's own `dispose()` can flip the same bit from outside each other.
- **disposed-collection-methods-are-inert-not-throwing**: once a collection's `disposalFlag.isDisposed` is `true`, its `set`, `delete`, `clear`, and `forEach` methods MUST return `undefined` and perform no mutation and no sink notification; `get` MUST return `undefined`; `has` MUST return `false` — none of the seven methods MUST throw, diverging from `extHostDiagnostics.ts`'s `_checkDisposed()`, which throws on every method call of a disposed collection; precedent for quiet inertness over inventing a throw is `MainThreadWindow.showStatusBarItem`'s own "a disposed item ignores this call."
- **disposed-collection-symbol-iterator-yields-empty**: a disposed collection's `Symbol.iterator` MUST yield an empty sequence (`getPairs()` answers `nil`, and the installed iterator falls back to `[]`) rather than `undefined`'s methods being called (which would throw `TypeError: pairs is not iterable` if the fallback were absent).
- **disposed-collection-name-remains-readable**: the readonly `name` getter installed on a `DiagnosticCollection` object MUST continue to answer the collection's `capturedName` — captured once at creation, not re-queried from the store — even after `disposalFlag.isDisposed` becomes `true`.
- **collection-name-is-not-writable**: the `name` property MUST be installed via `MainThreadWindow.installReadonlyGetter` (a `get`-only `defineProperty`, no `set`), so an assignment such as `collection.name = 'tampered'` from extension code MUST be a silent no-op that does not change the value later reads see.
- **disposed-collection-stays-inert-after-name-reuse**: every method block on a `DiagnosticCollection` object MUST check `disposalFlag.isDisposed` before its captured `owner` string is used to reach `store` again; this ordering MUST hold even after a disposed collection's `owner` name has been reused by a later `createDiagnosticCollection` call, so a stale reference held by extension code cannot write into the collection now registered under that reused name.
- **create-diagnostic-collection-validates-name-argument**: `createDiagnosticCollection`'s handler MUST accept a first argument that is a JS string, `undefined`, or `null`; any other type MUST raise the exact message `"createDiagnosticCollection requires a string name, or no argument."`.
- **get-diagnostics-null-and-undefined-both-mean-no-argument**: `getDiagnostics`'s handler MUST treat both a `null` and an `undefined` (or omitted) first argument as the no-argument, `allDiagnostics()`-backed branch, matching `extHostDiagnostics.ts:317`'s `if (resource)` dispatch; a present, non-`null`, non-`Uri` first argument MUST raise `"getDiagnostics requires a Uri, or no argument."`.
- **get-diagnostics-refuses-whole-array-on-undecodable-entry**: both branches of `getDiagnostics`'s handler MUST raise (`"Could not decode a diagnostic for this Uri."` for the resource branch, `"Could not decode a diagnostic entry."` for the no-argument branch) rather than return a silently shortened array when any diagnostic or pair fails to decode back into a `JSValue`.
- **collection-set-falsy-first-argument-clears**: `handleCollectionSet(owner:)` MUST, when the first argument is JS-falsy under `isFalsy(_:)` (including `0`, `""`, `false`, `NaN`, `null`, `undefined`, or an omitted argument — but NOT an empty array, which is an object and therefore truthy), clear the whole collection via `store.clear(owner:)`, regardless of which overload the call otherwise resembles, per `extHostDiagnostics.ts:64-68`.
- **collection-set-dispatches-on-isarray**: `handleCollectionSet(owner:)` MUST dispatch to the array-taking overload (`setEntriesArray`/`store.setEntries`) when the (truthy) first argument's `isArray` is `true`, and to the single-`Uri` overload otherwise; an argument that is truthy, not an array, and not decodable as a `Uri` MUST raise `"DiagnosticCollection.set requires a Uri, an entries array, or no argument."`.
- **collection-set-raises-on-invalid-entries-array**: an array first argument containing a tuple whose `Uri` slot or diagnostics slot fails to decode MUST raise `"Invalid entries passed to DiagnosticCollection.set."`, refusing the whole call rather than applying the entries that did decode.
- **collection-set-raises-on-invalid-diagnostics-array**: the single-`Uri` overload's second argument, when present and not decodable as `Diagnostic[] | undefined`, MUST raise `"Invalid diagnostics array passed to DiagnosticCollection.set."`.
- **collection-delete-requires-uri**: `handleCollectionDelete(owner:)` MUST raise `"DiagnosticCollection.delete requires a Uri."` when its first argument is missing or not decodable as a `Uri`.
- **collection-get-requires-uri-and-raises-on-decode-failure**: `handleCollectionGet(owner:)` MUST raise `"DiagnosticCollection.get requires a Uri."` for a missing/undecodable `Uri` argument, and MUST raise `"Could not decode a diagnostic for this Uri."` — not return `undefined` — when the stored diagnostics for an otherwise-valid `Uri` fail to re-encode.
- **collection-has-requires-uri**: `handleCollectionHas(owner:)` MUST raise `"DiagnosticCollection.has requires a Uri."` when its first argument is missing or not decodable as a `Uri`.
- **collection-foreach-requires-callable-callback**: `handleCollectionForEach(owner:)` MUST validate its first argument via `isInstance(of: Function)` (a callable check), MUST NOT accept a non-callable object such as `{}`, and MUST raise `"DiagnosticCollection.forEach requires a callback function."` on failure.
- **collection-foreach-third-argument-is-the-live-receiver-not-a-capture**: the collection object passed as the callback's third argument MUST be read from `JSContext.currentThis()` at call time, and MUST NOT be captured by the method block at creation time, because a captured `JSValue(newObjectIn:)` result is autoreleased and its Swift wrapper can die before the next drain, silently making every later `forEach` call iterate nothing.
- **collection-foreach-propagates-thrown-callback-exception**: a callback invocation that throws MUST cause `handleCollectionForEach` to set `context.exception` to that exception and return `nil` immediately, stopping iteration, mirroring `extHostDiagnostics.ts:187-190`'s plain loop that lets a thrown exception propagate rather than being swallowed or logged.
- **collection-foreach-decode-failure-raises-never-skips**: an entry that fails to decode during `forEach` MUST raise one of `"DiagnosticCollection.forEach could not decode the Uri of an entry."`, `"DiagnosticCollection.forEach could not decode a diagnostic for this Uri."`, or `"DiagnosticCollection.forEach could not invoke its callback."`, and MUST NOT `continue` past it, because `get`, `forEach`, and `Symbol.iterator` all read the same `store.pairs(owner:)` order and must fail consistently at the same entry rather than silently disagree on entry counts.
- **symbol-iterator-delegates-to-a-real-array**: `Symbol.iterator` MUST be installed via the evaluated `symbolIteratorInstallerSource` snippet, which delegates to a genuine JS array's own `[Symbol.iterator]()` built from `getPairs()`, rather than hand-writing a generator's `next()` protocol.
- **symbol-iterator-agrees-with-foreach-order**: the pairs `Symbol.iterator` yields MUST be built from the same `store.pairs(owner:)` order `forEach` reads, and MUST raise `"Could not decode a diagnostic entry."` (via `pairsArrayValue`) rather than silently shortening the sequence when an entry fails to decode.
- **sink-notified-on-every-mutation-with-affected-uris**: every mutating operation on a `DiagnosticCollection` — both `set` overloads, `delete`, `clear`, and the collection's own `dispose()` — MUST call `sink.diagnosticsChanged(for:)` with exactly the `URL`s that operation affected, whenever that set is non-empty.
- **sink-not-notified-on-reads**: `get`, `has`, `forEach`, and `Symbol.iterator` MUST NOT call `sink.diagnosticsChanged(for:)` under any circumstance; only mutations notify.
- **sink-not-notified-on-empty-affected-set**: an empty `clear()` or an empty collection-level `dispose()` (no `Uri`s were actually removed) MUST NOT call `sink.diagnosticsChanged(for:)`, diverging from `extHostDiagnostics.ts:182`/`:48`, which fire unconditionally; kept because the shared emitter is keyed by `Uri`, so an empty affected set contributes nothing to it either way.
- **ondidchangediagnostics-emitter-is-shared-and-not-defaulted**: `MainThreadDiagnostics.makeOnDidChangeDiagnosticsEmitter(window:)` MUST take `window` with no default, and the resulting `ExtensionEventEmitter<[URL]>` MUST be handed to every `MainThreadDiagnostics` instance and to `HostDiagnosticSink` as the same shared object, matching upstream's one `_onDidChangeDiagnostics` per extension host (`extHostDiagnostics.ts:240`) rather than one per extension.
- **ondidchangediagnostics-delay-is-fifty-milliseconds**: `onDidChangeDiagnosticsDelay` MUST equal `0.050` seconds, porting `extHostDiagnostics.ts:240`'s `delay: 50`.
- **ondidchangediagnostics-merge-flattens-only**: the emitter's `merge` function MUST flatten the queued `[[URL]]` batches into one `[URL]` (`$0.flatMap { $0 }`) and MUST NOT deduplicate — deduplication is `diagnosticChangeEventValue(for:in:)`'s responsibility, applied after flattening.
- **ondidchangediagnostics-dedups-by-uri-identity-not-object-identity**: `diagnosticChangeEventValue(for:in:)` MUST deduplicate the flattened `URL`s by `absoluteString` (this host's `toString()` analogue), so two distinct `Uri` objects for the same path collapse to one entry in the delivered `uris` array.
- **ondidchangediagnostics-preserves-first-insertion-order**: `diagnosticChangeEventValue(for:in:)` MUST preserve the first-insertion order of distinct `URL`s across the merged window (`Set.insert(...).inserted` guards a stable append, never a re-sort).
- **ondidchangediagnostics-uris-array-is-frozen**: the `uris` array on the delivered `{ uris }` event object MUST be produced through `Object.freeze`, so extension code cannot mutate it in a way that is visible to another listener or to the next window.
- **ondidchangediagnostics-refuses-whole-event-on-bad-uri**: `diagnosticChangeEventValue(for:in:)` MUST return `nil` for the entire event — not a `uris` array silently missing one entry — if any `URL` fails to build into a `JSValue`.
- **ondidchangediagnostics-is-a-call-signature-member-that-raises-on-teardown**: `onDidChangeDiagnostics` MUST be published via `VSCodeAPI.member(..., whenTornDown: .raisedException)`, matching `vscode.d.ts:1766`'s `Event<T>` call-signature declaration, and MUST raise (not reject a promise) when the owning adaptor has been deallocated, because the member answers a `Disposable` synchronously rather than a `Thenable`.
- **dispose-marks-disposal-flags-before-removing-from-store**: `MainThreadDiagnostics.dispose()` MUST set every owned collection's `disposalFlag.isDisposed = true` as part of the same loop that removes it from `store`, and this ordering MUST be treated as load-bearing — omitting it would leave a `DiagnosticCollection` object already handed to still-live JavaScript reading `disposed == false` forever, letting a stale reference write diagnostics into whatever collection a later `createDiagnosticCollection` call reused that owner name for.
- **dispose-notifies-sink-per-nonempty-removed-collection**: `dispose()` MUST call `sink.diagnosticsChanged(for:)` once per owned collection whose removal affected a non-empty set of `URL`s, and MUST NOT call it for a collection that had none.
- **dispose-removes-only-this-adaptors-own-event-listeners**: `dispose()` MUST call `events.removeListeners(ownedBy: self)`, removing only this adaptor's own `onDidChangeDiagnostics` listener registrations from the (possibly shared) emitter, never another adaptor's.
- **weak-capture-of-adaptor-strong-capture-of-disposal-flag**: every method block `makeDiagnosticCollectionObject` installs MUST capture `MainThreadDiagnostics` weakly (`[weak diagnostics]`) and MUST capture its `DisposalFlag` strongly; none of the blocks MUST capture the JS-visible collection `object` itself, not even weakly.
- **loggable-conformance**: `MainThreadDiagnostics` MUST conform to `Loggable` with a `nonisolated static let logger = makeLogger()`, matching every other `VSCodeAPI` extension file's logging seam.

## Appearance

Not applicable — this is a `JSContext` bridge and in-memory store, not a visual component.

## States

Not applicable — this is a `JSContext` bridge and in-memory store, not a visual component. Its only lifecycle-shaped behavior is per-collection disposal (inert-but-not-thrown once `disposalFlag.isDisposed`) and adaptor-level `dispose()`, both captured under Behavioral Requirements rather than as a visual-state table.

## Accessibility

Not applicable — this is a `JSContext` bridge and in-memory store, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| main-thread-diagnostics-001 | collection-name-collision-keeps-name-uniquifies-owner | Two `vscode.languages.createDiagnosticCollection("eslint")` calls | Both report `.name === "eslint"`; the two returned objects are distinct collections whose diagnostics do not merge — `MainThreadDiagnosticsTests.collidingNameKeepsNameAndMakesADistinctCollection` |
| main-thread-diagnostics-002 | collection-name-generated-when-omitted | Two `vscode.languages.createDiagnosticCollection()` calls with no name | Both `.name`s are distinct `_generated_diagnostic_collection_name_#<n>` values — `MainThreadDiagnosticsTests.omittedNameGeneratesADistinctNamePerCall` |
| main-thread-diagnostics-003 | single-uri-set-nil-is-removal, get-returns-nil-for-absent-uri | `collection.set(uri, [d])` then `collection.set(uri, undefined)`, then `collection.get(uri)` | `get(uri)` is `undefined`, not `[]` — distinct from ever storing an empty array — `MainThreadDiagnosticsTests.setUndefinedRemovesDistinctFromStoringEmptyArray` |
| main-thread-diagnostics-004 | get-returns-nil-for-absent-uri | `collection.get(neverSetUri)` on a fresh collection | Returns `undefined` — `MainThreadDiagnosticsTests.getOnAbsentUriIsUndefinedNotEmptyArray` |
| main-thread-diagnostics-005 | array-set-overload-merges-repeated-uris, array-set-overload-sorts-by-uri-string | `collection.set([[uriA, [d1]], [uriB, [d2]], [uriA, [d3]]])` | `get(uriA)` returns `[d1, d3]` (merged, not last-wins); order matches `vscode.d.ts:7189-7198` — `MainThreadDiagnosticsTests.arraySetOverloadMergesRepeatedUrisPerVscodeDts7189to7198` |
| main-thread-diagnostics-006 | delete-and-clear-are-distinct | `collection.set(uriA, [d1]); collection.set(uriB, [d2]); collection.delete(uriA); collection.clear()` | After `delete(uriA)`, `uriB` remains; after `clear()`, both are gone — `MainThreadDiagnosticsTests.deleteAndClearAreDistinctMutations` |
| main-thread-diagnostics-007 | collection-foreach-requires-callable-callback, collection-foreach-third-argument-is-the-live-receiver-not-a-capture | `collection.forEach(function (uri, diags, coll) { ... }, thisArg)` over a collection with several entries | Callback invoked once per `Uri` with `this === thisArg` and `coll === collection`, visiting each Uri exactly once — `MainThreadDiagnosticsTests.forEachVisitsEveryUriOnceWithCollectionAndHonoursThisArg` |
| main-thread-diagnostics-008 | symbol-iterator-delegates-to-a-real-array, symbol-iterator-agrees-with-foreach-order | `[...collection]` compared against pairs collected via `collection.forEach(...)` on the same collection | Both produce the identical sequence of `[uri, diagnostics]` pairs in the same order — `MainThreadDiagnosticsTests.symbolIteratorYieldsSamePairsAsForEachInTheSameOrder` |
| main-thread-diagnostics-009 | remove-collection-returns-affected-uris | `collection.dispose()` then a fresh `vscode.languages.createDiagnosticCollection(sameName)` | The name is free for reuse; a new distinct collection is created under it — `MainThreadDiagnosticsTests.disposeFreesTheNameForReuse` |
| main-thread-diagnostics-010 | disposed-collection-stays-inert-after-name-reuse, disposed-collection-methods-are-inert-not-throwing | `collectionA.dispose(); const collectionB = createDiagnosticCollection(sameName); collectionA.set(uri, [d])` | `collectionA.set` is a silent no-op; `collectionB`'s diagnostics for `uri` are unaffected — `MainThreadDiagnosticsTests.disposedCollectionStaysInertAfterItsNameIsReused` |
| main-thread-diagnostics-011 | adaptor-owns-only-its-created-collections, cross-collection-diagnostics-for-uri-concatenates-in-creation-order | `collectionA.set(uri, [d1]); collectionB.set(uri, [d2]); collectionA.dispose(); vscode.languages.getDiagnostics(uri)` | Returns only `[d2]` — `collectionA`'s contribution is gone, `collectionB`'s remains — `MainThreadDiagnosticsTests.disposeRemovesOnlyThisCollectionsDiagnosticsFromGetDiagnostics` |
| main-thread-diagnostics-012 | cross-collection-diagnostics-for-uri-concatenates-in-creation-order | Two collections both set diagnostics on the same `uri`; `vscode.languages.getDiagnostics(uri)` | Returns both collections' diagnostics concatenated in collection-creation order — `MainThreadDiagnosticsTests.getDiagnosticsForResourceMergesAcrossCollections` |
| main-thread-diagnostics-013 | cross-collection-all-diagnostics-merges-by-first-seen-uri | Multiple collections across multiple `Uri`s; `vscode.languages.getDiagnostics()` with no argument | Returns every `Uri` in first-seen order, diagnostics merged across every collection holding it — `MainThreadDiagnosticsTests.getDiagnosticsWithNoArgumentReturnsEveryUriMergedAcrossCollections` |
| main-thread-diagnostics-014 | get-diagnostics-null-and-undefined-both-mean-no-argument | `vscode.languages.getDiagnostics(null)` compared to `vscode.languages.getDiagnostics()` | Both calls return the identical result — `MainThreadDiagnosticsTests.getDiagnosticsWithExplicitNullMatchesTheNoArgumentResult` |
| main-thread-diagnostics-015 | sink-notified-on-every-mutation-with-affected-uris | A mock `ExtensionDiagnosticSink`; perform `set`, `setEntries`, `delete`, `clear`, and `dispose()` in turn | Sink receives exactly the affected `URL`s for each of the five calls — `MainThreadDiagnosticsTests.sinkIsNotifiedOnEveryMutatingCallWithTheRightUris` |
| main-thread-diagnostics-016 | sink-not-notified-on-reads | Same mock sink; perform `get`, `has`, `forEach`, and `[...collection]` | Sink receives zero calls across all four read operations — `MainThreadDiagnosticsTests.sinkIsNotNotifiedOnAnyReadOperation` |
| main-thread-diagnostics-017 | collection-name-is-not-writable | `collection.name = 'tampered'` then read `collection.name` | Read still returns the original name; the assignment was a silent no-op — `MainThreadDiagnosticsTests.collectionNameIsNotWritable` |
| main-thread-diagnostics-018 | adaptor-owns-only-its-created-collections, dispose-removes-only-this-adaptors-own-event-listeners | Two `MainThreadDiagnostics` adaptors sharing one `store`; dispose only the first | Only the first adaptor's collections are removed; the second adaptor's collections and diagnostics are untouched — `MainThreadDiagnosticsTests.adaptorDisposeTearsDownOnlyItsOwnCollections` |
| main-thread-diagnostics-019 | ondidchangediagnostics-emitter-is-shared-and-not-defaulted | Subscribe to `onDidChangeDiagnostics`; perform each of `set`, `setEntries`, `delete`, `clear`, `dispose()` in separate windows | Each of the five mutating operations produces its own delivered event — `MainThreadDiagnosticsTests.eachOfTheFiveMutatingOperationsProducesAnEvent` |
| main-thread-diagnostics-020 | ondidchangediagnostics-merge-flattens-only, ondidchangediagnostics-preserves-first-insertion-order | Two mutations for different `Uri`s within one 50ms debounce window | One delivered event whose `uris` array carries both `Uri`s — `MainThreadDiagnosticsTests.twoMutationsInOneWindowArriveAsOneEventCarryingBothUris` |
| main-thread-diagnostics-021 | ondidchangediagnostics-dedups-by-uri-identity-not-object-identity | Two distinct `Uri` objects built from the same path, each touched within one window | Delivered `uris` array contains exactly one entry for that path — `MainThreadDiagnosticsTests.twoDistinctUriObjectsForOnePathArriveAsOneEntry` |
| main-thread-diagnostics-022 | ondidchangediagnostics-preserves-first-insertion-order | Mutations touching `uriB` then `uriA` then `uriB` again within one window | Delivered `uris` array is `[uriB, uriA]` — first-insertion order, not sorted or last-touched order — `MainThreadDiagnosticsTests.firstInsertionOrderIsPreservedAcrossTheMergedWindow` |
| main-thread-diagnostics-023 | ondidchangediagnostics-uris-array-is-frozen | Receive one delivered event, attempt `event.uris.push(extraUri)` or `event.uris[0] = other`, then trigger a second event | The mutation attempt has no effect; the next delivered event's `uris` array is unaffected by the tampering attempt — `MainThreadDiagnosticsTests.theDeliveredUrisArrayIsFrozenAndTamperingDoesNotAffectTheNextEvent` |

## Edge Cases

- **Null/empty input**: an empty-string name to `createDiagnosticCollection("")` MUST be treated the same as an omitted name — a generated `_generated_diagnostic_collection_name_#<n>` — per **collection-name-generated-when-omitted** (MUST), traced to `createCollection(name:)`'s `if let name, !name.isEmpty` check.
- **Null/empty input**: the array-taking `set` overload's `entries` MAY carry a tuple whose diagnostics slot is `undefined` — this is the documented removal shape (`.removal`), not an error, per **array-set-overload-per-uri-undefined-clears-then-appends** (MUST).
- **Null/empty input**: `getDiagnostics(null)` MUST be treated identically to `getDiagnostics()` (no argument), per **get-diagnostics-null-and-undefined-both-mean-no-argument** (MUST) — see main-thread-diagnostics-014.
- **Boundary values**: an array-taking `set` call or a `diagnosticArray` decode longer than `VSCodeAPI.maximumDecodableArrayLength` (100,000 elements) MUST be refused by `VSCodeAPI.arrayLength(of:)`, which returns `nil` and logs an error, causing `diagnosticArray`/`setEntriesArray` — and therefore the whole `set`/array-decode call — to fail rather than truncate to the first 100,000 elements (MUST).
- **Boundary values**: a JS-falsy first argument to `set` — `0`, `""`, `false`, `NaN`, `null`, or `undefined` — clears the whole collection under **collection-set-falsy-first-argument-clears** (MUST); an *empty array* `[]`, despite being an "empty" value in the everyday sense, is an object and therefore JS-truthy, so it dispatches to the array-taking overload (applying zero entries — a no-op) rather than clearing.
- **Concurrent access**: not applicable in the sense of requiring synchronization — every function in both `ExtensionDiagnosticStore` and `MainThreadDiagnostics` runs on the main actor (**main-actor-isolation**), and `JSContext`/`JSValue` are not `Sendable`, so the compiler rules out two calls into this file's functions executing concurrently against the same context, rather than a lock or queue in the source (MUST).
- **Error states**: a `createDiagnosticCollection`, `getDiagnostics`, or any `DiagnosticCollection` method call whose argument fails validation MUST raise a real JS exception with the exact message documented under Behavioral Requirements, rather than returning `undefined`/`null` silently or throwing a generic error (MUST).
- **Error states**: a disposed collection's methods MUST fail silently-inert (see **disposed-collection-methods-are-inert-not-throwing**), which is the one place this file deliberately does NOT raise on a condition that would otherwise be an error — a documented, stated divergence from upstream, not an oversight.
- **Offline or disconnected state**: not applicable — this file makes no network call and opens no file; every input it processes arrives already in memory as a `JSValue`, and every output is delivered synchronously or via the in-process `events` emitter.
- **Cancellation and timeouts**: not applicable to the collection/store operations, which are all synchronous. `onDidChangeDiagnostics`'s 50ms debounce window (**ondidchangediagnostics-delay-is-fifty-milliseconds**) is a coalescing delay, not a cancellable operation; `ExtensionEventWindowScheduling` deliberately offers no cancel (see the `extension-host-vs-code-api-extension-event` recipe).
- **Missing file or unreachable server**: not applicable — this file has no filesystem or network dependency of its own; `VSCodeAPI.url(from:in:)`/`VSCodeAPI.uriValue(for:in:)`, which every `Uri`-decoding call site here uses, decode/encode a value already resident in or destined for the `JSContext`, never resolving anything against a filesystem or server.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `store` | `ExtensionDiagnosticStore` | none (required) | `MainThreadDiagnostics.init`'s storage seam; MAY be shared across multiple adaptors, each tracking only its own `ownedOwners`. |
| `sink` | `ExtensionDiagnosticSink` | none (required) | Notified of every mutation's affected `URL`s; production passes `HostDiagnosticSink`. |
| `events` | `ExtensionEventEmitter<[URL]>` | none (required) | The shared emitter behind `onDidChangeDiagnostics`; built via `makeOnDidChangeDiagnosticsEmitter(window:)` and handed to every adaptor and to the sink alike. |
| `window` (to `makeOnDidChangeDiagnosticsEmitter`) | `ExtensionEventWindowScheduling` | none (required) | The debounce window scheduler; production passes `ExtensionEventTimerWindow()`. |
| `name` (to `createDiagnosticCollection`) | JS string, `undefined`, or `null` | generated `_generated_diagnostic_collection_name_#<n>` when omitted | The collection's requested name; MAY collide with an existing one (see **collection-name-collision-keeps-name-uniquifies-owner**). |
| `VSCodeAPI.maximumDecodableArrayLength` | `Int` | `100_000` | Declared in `VSCodeAPI.swift`; the ceiling `VSCodeAPI.arrayLength(of:)` enforces for `diagnosticArray`/`setEntriesArray`. Not settable per call. |
| `onDidChangeDiagnosticsDelay` | `TimeInterval` | `0.050` | The debounce window width; a `static let`, not configurable per instance. |

## Deep Linking

Not applicable: `MainThreadDiagnostics.swift` defines no URL, route, or navigable destination — it installs `vscode.languages` members and bridges values, with no navigation surface of its own.

## Localization

- **hardcoded-error-messages**: every `TypeError`/`Error` message this file raises — `"createDiagnosticCollection requires a string name, or no argument."`, `"getDiagnostics requires a Uri, or no argument."`, `"Could not decode a diagnostic for this Uri."`, `"Could not decode a diagnostic entry."`, `"Invalid entries passed to DiagnosticCollection.set."`, `"DiagnosticCollection.set requires a Uri, an entries array, or no argument."`, `"Invalid diagnostics array passed to DiagnosticCollection.set."`, `"DiagnosticCollection.delete requires a Uri."`, `"DiagnosticCollection.get requires a Uri."`, `"DiagnosticCollection.has requires a Uri."`, `"DiagnosticCollection.forEach requires a callback function."`, `"DiagnosticCollection.forEach could not decode the Uri of an entry."`, `"DiagnosticCollection.forEach could not decode a diagnostic for this Uri."`, and `"DiagnosticCollection.forEach could not invoke its callback."` — are hardcoded English string literals with no localization key or `String(localized:)` call. They are visible to the extension author that made the mistake, not to the app's own end-user UI.
- **hardcoded-log-strings**: this file itself calls `logger` nowhere directly (it declares `Loggable` conformance only); the one logging event a call into this file's decode paths can trigger — `VSCodeAPI.arrayLength(of:)`'s `"refusing an array of <count> elements: longer than the 100000 this host decodes"` — is a hardcoded, unlocalized `Logger` interpolated string declared in `VSCodeAPI.swift`, shared by every `VSCodeAPI` extension file including this one.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal only) | `createDiagnosticCollection requires a string name, or no argument.` | `handleCreateDiagnosticCollection`, thrown when the first argument is present, not a string, and not `undefined`/`null`. |
| (none — literal only) | `getDiagnostics requires a Uri, or no argument.` | `handleGetDiagnostics`, thrown when a present, non-`null` first argument does not decode as a `Uri`. |
| (none — literal only) | `Could not decode a diagnostic for this Uri.` | `handleGetDiagnostics`'s resource branch and `handleCollectionGet`, thrown when a stored diagnostic fails to re-encode. |
| (none — literal only) | `Could not decode a diagnostic entry.` | `handleGetDiagnostics`'s no-argument branch and `pairsArrayValue`, thrown when a stored pair fails to re-encode. |
| (none — literal only) | `Invalid entries passed to DiagnosticCollection.set.` | `handleCollectionSet`, thrown when the array-taking overload's argument contains an undecodable tuple. |
| (none — literal only) | `DiagnosticCollection.set requires a Uri, an entries array, or no argument.` | `handleCollectionSet`, thrown when the first argument is truthy, not an array, and not a `Uri`. |
| (none — literal only) | `Invalid diagnostics array passed to DiagnosticCollection.set.` | `handleCollectionSet`, thrown when the single-`Uri` overload's second argument is present but not decodable. |
| (none — literal only) | `DiagnosticCollection.delete requires a Uri.` | `handleCollectionDelete`, thrown on a missing/undecodable first argument. |
| (none — literal only) | `DiagnosticCollection.get requires a Uri.` | `handleCollectionGet`, thrown on a missing/undecodable first argument. |
| (none — literal only) | `DiagnosticCollection.has requires a Uri.` | `handleCollectionHas`, thrown on a missing/undecodable first argument. |
| (none — literal only) | `DiagnosticCollection.forEach requires a callback function.` | `handleCollectionForEach`, thrown when the first argument is not `instanceof Function`. |
| (none — literal only) | `DiagnosticCollection.forEach could not decode the Uri of an entry.` | `handleCollectionForEach`, thrown when an entry's stored `Uri` fails to re-encode. |
| (none — literal only) | `DiagnosticCollection.forEach could not decode a diagnostic for this Uri.` | `handleCollectionForEach`, thrown when an entry's diagnostics fail to re-encode. |
| (none — literal only) | `DiagnosticCollection.forEach could not invoke its callback.` | `handleCollectionForEach`, thrown when `VSCodeAPI.call` reports `.unavailable`. |
| (none — literal only) | `refusing an array of <count> elements: longer than the 100000 this host decodes` | Logged inside `VSCodeAPI.swift`'s shared `arrayLength(of:)`, not inside this file; reached via `diagnosticArray`/`setEntriesArray`. |

## Accessibility Options

Not applicable: `MainThreadDiagnostics.swift` renders nothing and reads no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color) — it has no UI of its own.

## Feature Flags

Not applicable: the source declares no feature-flag key and contains no conditional feature-gating logic; `createDiagnosticCollection`, `getDiagnostics`, and `onDidChangeDiagnostics` are always available once a `MainThreadDiagnostics` instance is constructed and installed.

## Analytics

Not applicable: the source contains no analytics or event-emission call of any kind beyond the `ExtensionDiagnosticSink`/`onDidChangeDiagnostics` mechanism, which is functional extension-facing event delivery, not telemetry.

## Privacy

- **Data collected**: `MainThreadDiagnostics.swift` collects no data of its own; it stores and re-encodes whatever `Uri`, `Diagnostic` (range, message, severity, source, code, relatedInformation, tags), and collection-name values an extension supplies through `vscode.languages` calls, without retaining a copy beyond `ExtensionDiagnosticStore`'s own in-memory state for the lifetime of the collections that hold them.
- **Storage**: all state lives in `ExtensionDiagnosticStore`'s in-memory `collections`/`ownerOrder`; nothing in this file persists to disk, `UserDefaults`, or any other durable store.
- **Transmission**: this file makes no network call; it neither sends nor receives anything over a network.
- **Retention**: a collection's diagnostics are retained only until that collection's own `dispose()` or the owning adaptor's `dispose()` removes it from `store`; nothing here retains data beyond that lifetime, and a torn-down adaptor's collections are actively removed rather than merely dereferenced.

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (via `Loggable`'s default, falling back to `"nil"`) | Category: `VSCodeAPI` (the shared logger declared once in `VSCodeAPI.swift` and reused by every `VSCodeAPI` extension file, including this one)

| Event | Level | Message |
|-------|-------|---------|
| An array passed to `VSCodeAPI.arrayLength(of:)` (via `diagnosticArray`/`setEntriesArray`) reports a length over 100,000 | error | (logged inside `VSCodeAPI.swift`'s shared `arrayLength(of:)`, not inside this file): `refusing an array of <count> elements: longer than the 100000 this host decodes` |

No other event in this file is logged: this file itself contains no direct `logger.debug`/`logger.error` call. `VSCodeAPI.raise(_:in:)` — which every raised message above goes through — logs only in the extremely rare case that `JSValue(newErrorFromMessage:in:)` itself returns `nil`, not on the ordinary path of raising a message; every other decode failure surfaces to the caller as a thrown JS error or a `nil`/`undefined` return rather than a log line. `HostDiagnosticSink.diagnosticsChanged(for:)` (not part of this file's given source) logs its own `"diagnostics changed for <count> uri(s)"` debug line on every mutation this file reports to it; that log site belongs to the sink, not to this file.

## Platform Notes

- **SwiftUI**: not applicable to this file — `MainThreadDiagnostics.swift` imports only `Foundation`, `JavaScriptCore`, `OSLog`, and `AgenticToolkitCore`, with no SwiftUI dependency; nothing here renders or observes view state.
- **AppKit / UIKit**: this is the source. `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadDiagnostics.swift` is part of the `AgenticToolkitMacOS` framework target, which `project.yml` declares `platform: macOS` only — no iOS target packages this file. It is consumed by the JS-side `vscode.languages` diagnostics machinery, and it itself consumes `DiagnosticTypes.swift`'s `VSCodeAPI.diagnostic(from:in:)`/`diagnosticValue(for:in:)` and `ExtensionEvent.swift`'s `ExtensionEventEmitter`.
- **Compose**: model `ExtensionDiagnosticStore` as a plain Kotlin class with a `MutableMap<String, CollectionState>` and `MutableList<String>` for `ownerOrder`, guarded by the same single-writer-thread discipline `@MainActor` gives here (a Kotlin coroutine confined to a single dispatcher, or `synchronized`, since Kotlin has no compiler-enforced actor isolation). Model the "refuse the whole array/event on one bad element" contract (**get-diagnostics-refuses-whole-array-on-undecodable-entry**, **collection-foreach-decode-failure-raises-never-skips**, **ondidchangediagnostics-refuses-whole-event-on-bad-uri**) as a decode function returning `Result<T>`/nullable rather than a partial `List`, mirroring this file's own `nil`-refuses-whole-value discipline throughout.
- **React/Web**: this is closest to the actual runtime shape — extension code in the real VS Code product already runs against the genuine `vscode.d.ts` `languages.createDiagnosticCollection`/`getDiagnostics`/`onDidChangeDiagnostics` declarations this file mirrors. A React/Web host embedding a similar extension bridge would decode/encode the same `Diagnostic`/`Uri` shapes across whatever serialization boundary (e.g. `postMessage` to a worker) replaces this file's `JSContext` boundary, and would need the same debounced, deduplicated, order-preserving, frozen-array event contract (**ondidchangediagnostics-*** requirements) for its own `onDidChangeDiagnostics` equivalent.
- **WinUI 3**: model `ExtensionDiagnosticStore` as a plain C# class with a `Dictionary<string, CollectionState>` and a `List<string>` for owner order, confined to the UI thread the way `@MainActor` confines this file (a `DispatcherQueue` check, or simply never crossing threads). Model the debounced `onDidChangeDiagnostics` emitter with a `System.Threading.Timer`-backed coalescing queue analogous to `ExtensionEventEmitter`, deduplicating by `Uri.AbsoluteUri` (the .NET analogue of `absoluteString`) and exposing the delivered collection as a `ReadOnlyCollection<Uri>` in place of `Object.freeze`. The "disposed collection is inert, not throwing" contract (**disposed-collection-methods-are-inert-not-throwing**) maps to a `DiagnosticCollection` whose methods check an `IsDisposed` boolean field first and return default values (`null`, `false`) rather than throwing `ObjectDisposedException`, a deliberate divergence from the .NET idiom that should be called out in the WinUI port's own docs the same way this file calls it out against upstream VS Code.
- **Not implemented / not applicable**: not applicable.

## Design Decisions

**Decision**: a disposed `DiagnosticCollection`'s methods (`set`/`delete`/`clear`/`get`/`has`/`forEach`) are inert no-ops (`get`/`forEach` answer `undefined`, `has` answers `false`, `set`/`delete`/`clear` mutate nothing and notify no one), rather than throwing the way `extHostDiagnostics.ts`'s `_checkDisposed()` makes every method of a disposed collection throw.
**Rationale**: the task's own prose-only behaviors to port were the undefined-removal semantics, the array-overload merge semantics, and `get`'s absent-is-`undefined` contract; a disposed-collection throw was not among them. `MainThreadWindow.showStatusBarItem`'s own precedent — "a disposed item ignores this call" — is cited directly in the source as the reason to choose quiet inertness over inventing a new throw this task was not asked for.
**Approved**: pending

**Decision**: an empty `clear()` and an empty `dispose()` (no `Uri`s actually affected) do not notify the sink, where upstream (`extHostDiagnostics.ts:182`, `:48`) fires unconditionally.
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
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
