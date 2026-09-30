<!-- leaf: implement-extension-host-vs-1/code-api-main-thread-diagnostics--part-2 · source: extension-host-vs-code-api-main-thread-diagnostics.md -->

# MainThreadDiagnostics — continued (part 2)

**Rules** (cite as `implement-extension-host-vs-1/code-api-main-thread-diagnostics--part-2#<slug>`):

- `main-actor-isolation` MUST
- `no-jsvalue-capture-in-store` MUST
- `no-defaulted-seams` MUST
- `collection-name-collision-keeps-name-uniquifies-owner` MUST
- `collection-name-generated-when-omitted` MUST
- `id-pool-shared-across-branches` MUST
- `remove-collection-returns-affected-uris` MUST
- `single-uri-set-nil-is-removal` MUST
- `single-uri-set-non-nil-replaces` MUST
- `single-uri-set-no-op-on-absent-owner` MUST
- `array-set-overload-merges-repeated-uris` MUST
- `array-set-overload-sorts-by-uri-string` MUST
- `array-set-overload-transition-cleanup-asymmetry` MUST
- `array-set-overload-per-uri-undefined-clears-then-appends` MUST
- `delete-and-clear-are-distinct` MUST
- `get-returns-nil-for-absent-uri` MUST
- `has-checks-presence-not-emptiness` MUST
- `pairs-order-is-shared-source-of-truth` MUST
- `cross-collection-diagnostics-for-uri-concatenates-in-creation-order` MUST
- `cross-collection-all-diagnostics-merges-by-first-seen-uri` MUST
- `adaptor-owns-only-its-created-collections` MUST
- `disposal-flag-is-reference-typed` MUST
- `disposed-collection-methods-are-inert-not-throwing` MUST
- `disposed-collection-symbol-iterator-yields-empty` MUST
- `disposed-collection-name-remains-readable` MUST
- `collection-name-is-not-writable` MUST
- `disposed-collection-stays-inert-after-name-reuse` MUST
- `create-diagnostic-collection-validates-name-argument` MUST
- `get-diagnostics-null-and-undefined-both-mean-no-argument` MUST
- `get-diagnostics-refuses-whole-array-on-undecodable-entry` MUST
- `collection-set-falsy-first-argument-clears` MUST

## Behavioral Requirements

- **main-actor-isolation**: `ExtensionDiagnosticStore` and `MainThreadDiagnostics` MUST both be declared `@MainActor`; every call into either type happens on the thread that made the extension's call, because `JSContext`/`JSValue` are not `Sendable`.
- **no-jsvalue-capture-in-store**: `ExtensionDiagnosticStore` MUST hold only plain Swift values (`URL`, `VSCodeAPI.ExtensionDiagnostic`) in its `collections`/`ownerOrder` state; it MUST NOT store a `JSValue` or `JSContext`.
- **no-defaulted-seams**: `MainThreadDiagnostics.init(store:sink:events:)` MUST NOT default any of `store`, `sink`, or `events`; a caller that omitted one would silently disconnect that seam while still compiling, per the type's own doc comparing this to `MainThreadLanguages`'s `store`/`vocabulary` parameters.
- **collection-name-collision-keeps-name-uniquifies-owner**: `ExtensionDiagnosticStore.createCollection(name:)` MUST, when `name` is non-empty and already in use, keep the returned `name` equal to the requested `name` while uniquifying only the internal `owner` key (e.g. `"eslint0"`), per `extHostDiagnostics.ts`, so two `createDiagnosticCollection("eslint")` calls both report `.name === "eslint"` yet are distinct collections.
- **collection-name-generated-when-omitted**: `createCollection(name:)` MUST, when `name` is `nil` or empty, generate both `owner` and `name` as `_generated_diagnostic_collection_name_#<n>`, where `<n>` is the shared `idPool` counter's current value before incrementing.
- **id-pool-shared-across-branches**: `idPool` MUST be a single counter shared by both the name-collision branch and the generated-name branch of `createCollection(name:)`, matching `extHostDiagnostics.ts`'s single `_idPool`, rather than one counter per branch.
- **remove-collection-returns-affected-uris**: `removeCollection(owner:)` MUST return every `URL` the removed collection held (its `order` array) and MUST return an empty array for an `owner` the store does not contain.
- **single-uri-set-nil-is-removal**: `set(owner:uri:diagnostics:)` MUST treat a `nil` `diagnostics` argument as removing that `Uri` from the collection, not as storing an empty array, per `extHostDiagnostics.ts`.
- **single-uri-set-non-nil-replaces**: `set(owner:uri:diagnostics:)` MUST replace the `Uri`'s entire diagnostics array with the supplied non-`nil` array rather than appending to it.
- **single-uri-set-no-op-on-absent-owner**: `set`, `setEntries`, `delete`, and `clear` MUST each be a no-op returning an empty array when `owner` is not present in `collections`.
- **array-set-overload-merges-repeated-uris**: `CollectionState.applyEntries(_:)` MUST merge (append to, not replace) the diagnostics of repeated same-`Uri` tuples within one array-taking `set` call, per `vscode.d.ts`'s documented "entries are merged" contract, not last-tuple-wins.
- **array-set-overload-sorts-by-uri-string**: `applyEntries(_:)` MUST stable-sort the input tuples by `uri.absoluteString` (ties broken by original index) before processing them, porting `extHostDiagnostics.ts`'s `_compareIndexedTuplesByUri`.
- **array-set-overload-transition-cleanup-asymmetry**: `applyEntries(_:)` MUST, on transitioning to a new `Uri` in the sorted batch, delete the *previous* `Uri` from storage if it ended up empty, and MUST NOT perform this cleanup for the final `Uri` of the batch (there is no following transition to trigger it) — this asymmetry is upstream's own behavior and MUST be preserved, not "fixed."
- **array-set-overload-per-uri-undefined-clears-then-appends**: within one `applyEntries(_:)` call, a tuple whose `diagnostics` is `nil` for a `Uri` MUST replace that `Uri`'s accumulated diagnostics with an empty array at the point it is processed; a later tuple for the same `Uri` in the same batch MUST then append to that now-empty array rather than to whatever preceded the `nil` tuple.
- **delete-and-clear-are-distinct**: `delete(owner:uri:)` MUST remove only the named `Uri`; `clear(owner:)` MUST remove every `Uri` the collection holds and reset both `order` and `diagnostics` to empty, returning the previously-affected order.
- **get-returns-nil-for-absent-uri**: `get(owner:uri:)` MUST return `nil` — not an empty array — for a `Uri` the collection does not hold, matching `vscode.d.ts`'s declared `readonly Diagnostic[] | undefined`, deliberately different from `extHostDiagnostics.ts`'s own internal `#data`-backed accessor, which returns `[]` for the same case; that raw accessor is upstream's internal storage layer, not the interface contract this store's exposed `get` must match.
- **has-checks-presence-not-emptiness**: `has(owner:uri:)` MUST return `true` for a `Uri` present in the collection (even with an empty diagnostics array) and `false` for a `Uri` not present.
- **pairs-order-is-shared-source-of-truth**: `pairs(owner:)` MUST return `(url, diagnostics)` pairs in `order`'s stored sequence, and this MUST be the same order `forEach` and `Symbol.iterator` both read from, so the two agree by construction.
- **cross-collection-diagnostics-for-uri-concatenates-in-creation-order**: `diagnostics(for uri:)` MUST concatenate every collection's diagnostics for `uri` in collection-creation order (`ownerOrder`), per `extHostDiagnostics.ts`'s `_getDiagnostics`.
- **cross-collection-all-diagnostics-merges-by-first-seen-uri**: `allDiagnostics()` MUST return every `Uri` across every collection in first-seen order, with diagnostics merged across every collection holding that `Uri`, per `extHostDiagnostics.ts`'s no-argument branch.
- **adaptor-owns-only-its-created-collections**: `MainThreadDiagnostics` MUST track every `owner` it created in `ownedOwners`, and its `dispose()` MUST tear down only those collections from a possibly-shared `store`, never another adaptor's collections.
- **disposal-flag-is-reference-typed**: each collection's disposed state MUST be a `DisposalFlag` reference type (a boxed `Bool`), not a value captured by a closure, so that both the collection object's own JS-visible `dispose` method and the adaptor's own `dispose()` can flip the same bit from outside each other.
- **disposed-collection-methods-are-inert-not-throwing**: once a collection's `disposalFlag.isDisposed` is `true`, its `set`, `delete`, `clear`, and `forEach` methods MUST return `undefined` and perform no mutation and no sink notification; `get` MUST return `undefined`; `has` MUST return `false` — none of the seven methods MUST throw, diverging from `extHostDiagnostics.ts`'s `_checkDisposed()`, which throws on every method call of a disposed collection; precedent for quiet inertness over inventing a throw is `MainThreadWindow.showStatusBarItem`'s own "a disposed item ignores this call."
- **disposed-collection-symbol-iterator-yields-empty**: a disposed collection's `Symbol.iterator` MUST yield an empty sequence (`getPairs()` answers `nil`, and the installed iterator falls back to `[]`) rather than `undefined`'s methods being called (which would throw `TypeError: pairs is not iterable` if the fallback were absent).
- **disposed-collection-name-remains-readable**: the readonly `name` getter installed on a `DiagnosticCollection` object MUST continue to answer the collection's `capturedName` — captured once at creation, not re-queried from the store — even after `disposalFlag.isDisposed` becomes `true`.
- **collection-name-is-not-writable**: the `name` property MUST be installed via `MainThreadWindow.installReadonlyGetter` (a `get`-only `defineProperty`, no `set`), so an assignment such as `collection.name = 'tampered'` from extension code MUST be a silent no-op that does not change the value later reads see.
- **disposed-collection-stays-inert-after-name-reuse**: every method block on a `DiagnosticCollection` object MUST check `disposalFlag.isDisposed` before its captured `owner` string is used to reach `store` again; this ordering MUST hold even after a disposed collection's `owner` name has been reused by a later `createDiagnosticCollection` call, so a stale reference held by extension code cannot write into the collection now registered under that reused name.
- **create-diagnostic-collection-validates-name-argument**: `createDiagnosticCollection`'s handler MUST accept a first argument that is a JS string, `undefined`, or `null`; any other type MUST raise the exact message `"createDiagnosticCollection requires a string name, or no argument."`.
- **get-diagnostics-null-and-undefined-both-mean-no-argument**: `getDiagnostics`'s handler MUST treat both a `null` and an `undefined` (or omitted) first argument as the no-argument, `allDiagnostics()`-backed branch, matching `extHostDiagnostics.ts`'s `if (resource)` dispatch; a present, non-`null`, non-`Uri` first argument MUST raise `"getDiagnostics requires a Uri, or no argument."`.
- **get-diagnostics-refuses-whole-array-on-undecodable-entry**: both branches of `getDiagnostics`'s handler MUST raise (`"Could not decode a diagnostic for this Uri."` for the resource branch, `"Could not decode a diagnostic entry."` for the no-argument branch) rather than return a silently shortened array when any diagnostic or pair fails to decode back into a `JSValue`.
- **collection-set-falsy-first-argument-clears**: `handleCollectionSet(owner:)` MUST, when the first argument is JS-falsy under `isFalsy(_:)` (including `0`, `""`, `false`, `NaN`, `null`, `undefined`, or an omitted argument — but NOT an empty array, which is an object and therefore truthy), clear the whole collection via `store.clear(owner:)`, regardless of which overload the call otherwise resembles, per `extHostDiagnostics.ts`.
