<!-- leaf: implement-extension-host-vs-2/code-api-vs-code-api--edge-cases · source: extension-host-vs-code-api-vs-code-api.md -->

# VSCodeAPI

**Rules** (cite as `implement-extension-host-vs-2/code-api-vs-code-api--edge-cases#<slug>`):

- `null-empty-input` MUST — currentArguments() called with no call in flight (JSContext.currentArguments() answers nil or something that is not …
- `null-empty-input-2` MUST — {length: -1} (an object literal, not a real array) is rejected by arrayLength(of:) before its length is ever read, …
- `boundary-values` MUST — an array reporting exactly 100_000 elements is accepted by arrayLength(of:); 100_001 is refused with a logged error …
- `boundary-values-2` MUST — an array whose length cannot be represented as an Int32 (such as one built with new Array(4294967295)) is refused by …
- `concurrent-access` MUST — a then implementation that calls both onFulfilled and onRejected, or calls one of them twice, has its second and later …
- `error-states` MUST — a context whose dispatch trampoline could not be installed answers .unavailable from call, from canDispatch, and from …
- `error-states-2` MUST — a then getter, or a then call, that throws rejects rather than letting the exception reach the context's …
- `error-states-3` MUST — a malformed trampoline record (missing or non-boolean ok) is treated as .unavailable, never silently coerced into a …

## Edge Cases

- **Null/empty input**: `currentArguments()` called with no call in flight (`JSContext.currentArguments()` answers `nil` or something that is not `[JSValue]`) answers `[]`, never `nil` (MUST, per **current-arguments-never-nil**).
- **Null/empty input**: `{length: -1}` (an object literal, not a real array) is rejected by `arrayLength(of:)` before its `length` is ever read, because it fails `value.isArray` (MUST, per **array-length-requires-true-array**).
- **Boundary values**: an array reporting exactly `100_000` elements is accepted by `arrayLength(of:)`; `100_001` is refused with a logged error (MUST, per **array-length-bounds-decoding**).
- **Boundary values**: an array whose `length` cannot be represented as an `Int32` (such as one built with `new Array(4294967295)`) is refused by the `Int32(exactly:)` guard rather than wrapped to a small, plausible-looking count (MUST, per **array-length-uses-exact-int32-conversion**).
- **Concurrent access**: every member of `VSCodeAPI` is `@MainActor`-isolated with no additional locking; JavaScriptCore calls every block this file builds on the thread that made the call, which for this host is always the main actor, so there is no data race for this recipe to define behavior for (fact).
- **Concurrent access**: a `then` implementation that calls both `onFulfilled` and `onRejected`, or calls one of them twice, has its second and later calls resumed at most once by the once-only guard inside `settlement(of:in:)`; the first settlement by call order wins (MUST, per **settlement-resumes-the-continuation-exactly-once**).
- **Error states**: a context whose dispatch trampoline could not be installed answers `.unavailable` from `call`, from `canDispatch`, and from `settlement`/`thenFunction` — never a fabricated success or fulfillment (MUST, per **call-refuses-when-trampoline-cannot-be-installed**, **settlement-unavailable-when-context-cannot-mint-undefined**).
- **Error states**: a `then` getter, or a `then` call, that throws rejects rather than letting the exception reach the context's `exceptionHandler` and be misattributed to unrelated host activity (MUST, per **settled-promise-rejects-on-a-throwing-then-getter**, **settlement-getter-throw-becomes-rejected**).
- **Error states**: a malformed trampoline record (missing or non-boolean `ok`) is treated as `.unavailable`, never silently coerced into a success or a thrown value (MUST, per **outcome-refuses-a-malformed-trampoline-record**).
- **Error states**: a JS stack already exhausted by extension code throws a `RangeError` while entering `helperSource` or `subNamespaceFactorySource` itself, before either script's own `try` executes; that exception reaches the host's exception handling like any other uncaught extension exception, because a context in that state is already failing the extension's own next frame regardless (fact — `helperSource`/`subNamespaceFactorySource` document this as accepted, not as something this file defends against).
- **Cancellation or timeout**: `settlement(of:in:)` imposes no timeout and offers no cancellation path; a thenable that never settles leaves its continuation, and the two blocks capturing it, permanently pending (fact, per **settlement-does-not-time-out**).
- **Missing or unreachable resource**: a JavaScript object already installed under `__vscodeAPITrampoline` or `__vscodeSubNamespaceFactory` before this file's own install runs is adopted as-is by `sharedHelper(in:)`/`subNamespaceFactory(in:)`; `outcome(of:in:)` and the sub-namespace `Proxy` traps can only refuse a malformed *answer* from such an object, never verify its provenance — an impostor that throws instead of answering lands its exception in the calling extension's own pending-exception state, confusing that one extension's activation report and no other extension's (fact, per **sharedHelper-adopts-whatever-object-it-finds**).
