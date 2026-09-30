<!-- leaf: implement-extension-host-vs-1/code-api-main-thread-diagnostics--part-3 · source: extension-host-vs-code-api-main-thread-diagnostics.md -->

# MainThreadDiagnostics — continued (part 3)

**Rules** (cite as `implement-extension-host-vs-1/code-api-main-thread-diagnostics--part-3#<slug>`):

- `collection-set-dispatches-on-isarray` MUST
- `collection-set-raises-on-invalid-entries-array` MUST
- `collection-set-raises-on-invalid-diagnostics-array` MUST
- `collection-delete-requires-uri` MUST
- `collection-get-requires-uri-and-raises-on-decode-failure` MUST
- `collection-has-requires-uri` MUST
- `collection-foreach-requires-callable-callback` MUST
- `collection-foreach-third-argument-is-the-live-receiver-not-a-capture` MUST
- `collection-foreach-propagates-thrown-callback-exception` MUST
- `collection-foreach-decode-failure-raises-never-skips` MUST
- `symbol-iterator-delegates-to-a-real-array` MUST
- `symbol-iterator-agrees-with-foreach-order` MUST
- `sink-notified-on-every-mutation-with-affected-uris` MUST
- `sink-not-notified-on-reads` MUST
- `sink-not-notified-on-empty-affected-set` MUST
- `ondidchangediagnostics-emitter-is-shared-and-not-defaulted` MUST
- `ondidchangediagnostics-delay-is-fifty-milliseconds` MUST
- `ondidchangediagnostics-merge-flattens-only` MUST
- `ondidchangediagnostics-dedups-by-uri-identity-not-object-identity` MUST
- `ondidchangediagnostics-preserves-first-insertion-order` MUST
- `ondidchangediagnostics-uris-array-is-frozen` MUST
- `ondidchangediagnostics-refuses-whole-event-on-bad-uri` MUST
- `ondidchangediagnostics-is-a-call-signature-member-that-raises-on-teardown` MUST
- `dispose-marks-disposal-flags-before-removing-from-store` MUST
- `dispose-notifies-sink-per-nonempty-removed-collection` MUST
- `dispose-removes-only-this-adaptors-own-event-listeners` MUST
- `weak-capture-of-adaptor-strong-capture-of-disposal-flag` MUST
- `loggable-conformance` MUST

- **collection-set-dispatches-on-isarray**: `handleCollectionSet(owner:)` MUST dispatch to the array-taking overload (`setEntriesArray`/`store.setEntries`) when the (truthy) first argument's `isArray` is `true`, and to the single-`Uri` overload otherwise; an argument that is truthy, not an array, and not decodable as a `Uri` MUST raise `"DiagnosticCollection.set requires a Uri, an entries array, or no argument."`.
- **collection-set-raises-on-invalid-entries-array**: an array first argument containing a tuple whose `Uri` slot or diagnostics slot fails to decode MUST raise `"Invalid entries passed to DiagnosticCollection.set."`, refusing the whole call rather than applying the entries that did decode.
- **collection-set-raises-on-invalid-diagnostics-array**: the single-`Uri` overload's second argument, when present and not decodable as `Diagnostic[] | undefined`, MUST raise `"Invalid diagnostics array passed to DiagnosticCollection.set."`.
- **collection-delete-requires-uri**: `handleCollectionDelete(owner:)` MUST raise `"DiagnosticCollection.delete requires a Uri."` when its first argument is missing or not decodable as a `Uri`.
- **collection-get-requires-uri-and-raises-on-decode-failure**: `handleCollectionGet(owner:)` MUST raise `"DiagnosticCollection.get requires a Uri."` for a missing/undecodable `Uri` argument, and MUST raise `"Could not decode a diagnostic for this Uri."` — not return `undefined` — when the stored diagnostics for an otherwise-valid `Uri` fail to re-encode.
- **collection-has-requires-uri**: `handleCollectionHas(owner:)` MUST raise `"DiagnosticCollection.has requires a Uri."` when its first argument is missing or not decodable as a `Uri`.
- **collection-foreach-requires-callable-callback**: `handleCollectionForEach(owner:)` MUST validate its first argument via `isInstance(of: Function)` (a callable check), MUST NOT accept a non-callable object such as `{}`, and MUST raise `"DiagnosticCollection.forEach requires a callback function."` on failure.
- **collection-foreach-third-argument-is-the-live-receiver-not-a-capture**: the collection object passed as the callback's third argument MUST be read from `JSContext.currentThis()` at call time, and MUST NOT be captured by the method block at creation time, because a captured `JSValue(newObjectIn:)` result is autoreleased and its Swift wrapper can die before the next drain, silently making every later `forEach` call iterate nothing.
- **collection-foreach-propagates-thrown-callback-exception**: a callback invocation that throws MUST cause `handleCollectionForEach` to set `context.exception` to that exception and return `nil` immediately, stopping iteration, mirroring `extHostDiagnostics.ts`'s plain loop that lets a thrown exception propagate rather than being swallowed or logged.
- **collection-foreach-decode-failure-raises-never-skips**: an entry that fails to decode during `forEach` MUST raise one of `"DiagnosticCollection.forEach could not decode the Uri of an entry."`, `"DiagnosticCollection.forEach could not decode a diagnostic for this Uri."`, or `"DiagnosticCollection.forEach could not invoke its callback."`, and MUST NOT `continue` past it, because `get`, `forEach`, and `Symbol.iterator` all read the same `store.pairs(owner:)` order and must fail consistently at the same entry rather than silently disagree on entry counts.
- **symbol-iterator-delegates-to-a-real-array**: `Symbol.iterator` MUST be installed via the evaluated `symbolIteratorInstallerSource` snippet, which delegates to a genuine JS array's own `[Symbol.iterator]()` built from `getPairs()`, rather than hand-writing a generator's `next()` protocol.
- **symbol-iterator-agrees-with-foreach-order**: the pairs `Symbol.iterator` yields MUST be built from the same `store.pairs(owner:)` order `forEach` reads, and MUST raise `"Could not decode a diagnostic entry."` (via `pairsArrayValue`) rather than silently shortening the sequence when an entry fails to decode.
- **sink-notified-on-every-mutation-with-affected-uris**: every mutating operation on a `DiagnosticCollection` — both `set` overloads, `delete`, `clear`, and the collection's own `dispose()` — MUST call `sink.diagnosticsChanged(for:)` with exactly the `URL`s that operation affected, whenever that set is non-empty.
- **sink-not-notified-on-reads**: `get`, `has`, `forEach`, and `Symbol.iterator` MUST NOT call `sink.diagnosticsChanged(for:)` under any circumstance; only mutations notify.
- **sink-not-notified-on-empty-affected-set**: an empty `clear()` or an empty collection-level `dispose()` (no `Uri`s were actually removed) MUST NOT call `sink.diagnosticsChanged(for:)`, diverging from `extHostDiagnostics.ts`/`:48`, which fire unconditionally; kept because the shared emitter is keyed by `Uri`, so an empty affected set contributes nothing to it either way.
- **ondidchangediagnostics-emitter-is-shared-and-not-defaulted**: `MainThreadDiagnostics.makeOnDidChangeDiagnosticsEmitter(window:)` MUST take `window` with no default, and the resulting `ExtensionEventEmitter<[URL]>` MUST be handed to every `MainThreadDiagnostics` instance and to `HostDiagnosticSink` as the same shared object, matching upstream's one `_onDidChangeDiagnostics` per extension host (`extHostDiagnostics.ts`) rather than one per extension.
- **ondidchangediagnostics-delay-is-fifty-milliseconds**: `onDidChangeDiagnosticsDelay` MUST equal `0.050` seconds, porting `extHostDiagnostics.ts`'s `delay: 50`.
- **ondidchangediagnostics-merge-flattens-only**: the emitter's `merge` function MUST flatten the queued `[[URL]]` batches into one `[URL]` (`$0.flatMap { $0 }`) and MUST NOT deduplicate — deduplication is `diagnosticChangeEventValue(for:in:)`'s responsibility, applied after flattening.
- **ondidchangediagnostics-dedups-by-uri-identity-not-object-identity**: `diagnosticChangeEventValue(for:in:)` MUST deduplicate the flattened `URL`s by `absoluteString` (this host's `toString()` analogue), so two distinct `Uri` objects for the same path collapse to one entry in the delivered `uris` array.
- **ondidchangediagnostics-preserves-first-insertion-order**: `diagnosticChangeEventValue(for:in:)` MUST preserve the first-insertion order of distinct `URL`s across the merged window (`Set.insert(...).inserted` guards a stable append, never a re-sort).
- **ondidchangediagnostics-uris-array-is-frozen**: the `uris` array on the delivered `{ uris }` event object MUST be produced through `Object.freeze`, so extension code cannot mutate it in a way that is visible to another listener or to the next window.
- **ondidchangediagnostics-refuses-whole-event-on-bad-uri**: `diagnosticChangeEventValue(for:in:)` MUST return `nil` for the entire event — not a `uris` array silently missing one entry — if any `URL` fails to build into a `JSValue`.
- **ondidchangediagnostics-is-a-call-signature-member-that-raises-on-teardown**: `onDidChangeDiagnostics` MUST be published via `VSCodeAPI.member(..., whenTornDown: .raisedException)`, matching `vscode.d.ts`'s `Event<T>` call-signature declaration, and MUST raise (not reject a promise) when the owning adaptor has been deallocated, because the member answers a `Disposable` synchronously rather than a `Thenable`.
- **dispose-marks-disposal-flags-before-removing-from-store**: `MainThreadDiagnostics.dispose()` MUST set every owned collection's `disposalFlag.isDisposed = true` as part of the same loop that removes it from `store`, and this ordering MUST be treated as load-bearing — omitting it would leave a `DiagnosticCollection` object already handed to still-live JavaScript reading `disposed == false` forever, letting a stale reference write diagnostics into whatever collection a later `createDiagnosticCollection` call reused that owner name for.
- **dispose-notifies-sink-per-nonempty-removed-collection**: `dispose()` MUST call `sink.diagnosticsChanged(for:)` once per owned collection whose removal affected a non-empty set of `URL`s, and MUST NOT call it for a collection that had none.
- **dispose-removes-only-this-adaptors-own-event-listeners**: `dispose()` MUST call `events.removeListeners(ownedBy: self)`, removing only this adaptor's own `onDidChangeDiagnostics` listener registrations from the (possibly shared) emitter, never another adaptor's.
- **weak-capture-of-adaptor-strong-capture-of-disposal-flag**: every method block `makeDiagnosticCollectionObject` installs MUST capture `MainThreadDiagnostics` weakly (`[weak diagnostics]`) and MUST capture its `DisposalFlag` strongly; none of the blocks MUST capture the JS-visible collection `object` itself, not even weakly.
- **loggable-conformance**: `MainThreadDiagnostics` MUST conform to `Loggable` with a `nonisolated static let logger = makeLogger()`, matching every other `VSCodeAPI` extension file's logging seam.
