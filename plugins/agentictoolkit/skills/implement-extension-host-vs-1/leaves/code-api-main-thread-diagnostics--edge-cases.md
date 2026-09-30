<!-- leaf: implement-extension-host-vs-1/code-api-main-thread-diagnostics--edge-cases · source: extension-host-vs-code-api-main-thread-diagnostics.md -->

# MainThreadDiagnostics

**Rules** (cite as `implement-extension-host-vs-1/code-api-main-thread-diagnostics--edge-cases#<slug>`):

- `null-empty-input` MUST — an empty-string name to createDiagnosticCollection("") MUST be treated the same as an omitted name — a generated …
- `null-empty-input-2` MUST — the array-taking set overload's entries MAY carry a tuple whose diagnostics slot is undefined — this is the documented …
- `null-empty-input-3` MUST — getDiagnostics(null) MUST be treated identically to getDiagnostics() (no argument), per …
- `boundary-values` MUST — an array-taking set call or a diagnosticArray decode longer than VSCodeAPI.maximumDecodableArrayLength (100,000 …
- `boundary-values-2` MUST — a JS-falsy first argument to set — 0, "", false, NaN, null, or undefined — clears the whole collection under …
- `concurrent-access` MUST — not applicable in the sense of requiring synchronization — every function in both ExtensionDiagnosticStore and …
- `error-states` MUST — a createDiagnosticCollection, getDiagnostics, or any DiagnosticCollection method call whose argument fails validation …
- `error-states-2` MUST — a disposed collection's methods MUST fail silently-inert (see disposed-collection-methods-are-inert-not-throwing), …

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
