<!-- leaf: implement-extension-host-vs-2/code-api-text-geometry--edge-cases · source: extension-host-vs-code-api-text-geometry.md -->

# TextGeometry

**Rules** (cite as `implement-extension-host-vs-2/code-api-text-geometry--edge-cases#<slug>`):

- `null-empty-input` MUST — Location constructed with its second argument omitted MUST leave range entirely unset rather than assigning undefined, …
- `null-empty-input-2` MUST — Range's constructor called with arguments matching neither the four-number nor the two-position form MUST throw …
- `boundary-values` MUST — line/character of exactly 0 is the minimum valid value and MUST NOT throw; Position's constructor only rejects strictly …
- `boundary-values-2` MUST — two positions that are equal-but-distinct objects MUST still take Range's swap branch (start.isBefore(end) is strict), …
- `boundary-values-3` MUST — two ranges that touch at exactly one point MUST intersect to an empty Range, not undefined — the boundary between …
- `concurrent-access` MUST — not applicable in the sense of requiring synchronization — every function this file adds runs on the main actor (per …
- `error-states` MUST — installTextGeometryClasses(in:) failing for any of its three logged reasons (evaluate failure, an installedError …
- `error-states-2` MUST — positionValue(for:in:), rangeValue(for:in:), and locationValue(for:in:) each swallow a construction-time throw by …

## Edge Cases

- **Null/empty input**: `Location` constructed with its second argument omitted MUST leave `range` entirely unset rather than assigning `undefined`, per **location-constructor-falsy-range-leaves-unset** (MUST).
- **Null/empty input**: `Range`'s constructor called with arguments matching neither the four-number nor the two-position form MUST throw `Error('Invalid arguments')` rather than construct a partial or default range, per **range-constructor-invalid-arguments-throws** (MUST).
- **Boundary values**: `line`/`character` of exactly `0` is the minimum valid value and MUST NOT throw; `Position`'s constructor only rejects strictly negative values, per **position-constructor-validates-line**/**position-constructor-validates-character** (MUST).
- **Boundary values**: two positions that are equal-but-distinct objects MUST still take `Range`'s swap branch (`start.isBefore(end)` is strict), not the "already ordered" branch, per **range-constructor-swaps-strictly-ordered** (MUST) — unobservable by value, so no test in `TextGeometryTests.swift` pins object identity for this case.
- **Boundary values**: two ranges that touch at exactly one point MUST intersect to an empty `Range`, not `undefined` — the boundary between **range-intersection-empty-not-undefined-when-touching** and **range-intersection-undefined-when-disjoint** (MUST).
- **Concurrent access**: not applicable in the sense of requiring synchronization — every function this file adds runs on the main actor (per **main-actor-isolation**), and `JSContext`/`JSValue` are not `Sendable`, so no two calls into this file's functions can execute concurrently against the same context; the compiler enforces this via `VSCodeAPI`'s own `@MainActor` declaration (MUST).
- **Concurrent access / cache identity**: if some other code has already defined an object under the global name `__vscodeTextGeometryClasses` on a context before `installTextGeometryClasses(in:)` first runs on it, this function adopts that pre-existing object as the cached container with no way to verify it is the genuine geometry classes this file built — the same residual behavior `Uri.swift`'s `installUriClass(in:)` documents for its own global, generalized here to a three-member container (per this file's own header comment; not independently re-verified against `Uri.swift`'s text in this recipe).
- **Error states**: `installTextGeometryClasses(in:)` failing for any of its three logged reasons (evaluate failure, an `installedError` result, or a missing member) MUST leave every `vscode.Position`/`Range`/`Location` global as the shim's not-implemented stub for that context rather than raise a Swift error, per **install-failure-is-non-fatal** (MUST). Unlike `LanguageModelMessageVocabulary.swift`'s installer, this file's outer catch DOES capture and return the underlying JavaScript error's own message via `installedError`, so a caller can distinguish a construction-time failure from a plain non-object result — but `TextGeometryTests.swift` exercises neither failure path directly, unlike some sibling installers' own test suites.
- **Error states**: `positionValue(for:in:)`, `rangeValue(for:in:)`, and `locationValue(for:in:)` each swallow a construction-time throw by clearing `context.exception` and returning `nil`, with nothing logged to say which field or class failed, per **position-value-clears-exception-on-throw**/**range-value-clears-exception-on-throw**/**location-value-clears-exception-on-throw** (MUST).
- **Offline or disconnected state**: not applicable — this file makes no network call and opens no file; every input it processes (a line/character number, a `Position`/`Range`/`Location` instance, a `Uri`) arrives already resident in the `JSContext` or as a Swift value.
- **Cancellation and timeouts**: not applicable — every function this file adds is synchronous; there is no long-running operation to cancel or time out.
- **Missing file or unreachable server**: not applicable — this file has no filesystem or network dependency of its own; `Location`'s `uri` field is an opaque `URL` value read via `Uri.swift`'s own `url(from:in:)`, never dereferenced or resolved here.
