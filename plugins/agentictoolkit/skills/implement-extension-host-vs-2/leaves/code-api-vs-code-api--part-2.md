<!-- leaf: implement-extension-host-vs-2/code-api-vs-code-api--part-2 · source: extension-host-vs-code-api-vs-code-api.md -->

# VSCodeAPI — continued (part 2)

**Rules** (cite as `implement-extension-host-vs-2/code-api-vs-code-api--part-2#<slug>`):

- `main-actor-isolation` MUST
- `stateless-enum` MUST
- `member-builds-a-block-closure` MUST
- `member-block-asserts-isolation-internally` MUST
- `member-captures-owner-weakly` MUST
- `member-answers-teardown-response-when-owner-gone` MUST
- `teardown-response-two-cases` MUST
- `torn-down-dispatches-by-response` MUST
- `current-arguments-never-nil` MUST
- `array-length-requires-true-array` MUST
- `array-length-uses-exact-int32-conversion` MUST
- `array-length-bounds-decoding` MUST
- `raise-sets-context-exception` MUST
- `raise-logs-when-error-construction-fails` MUST
- `resolved-promise-nil-becomes-undefined` MUST
- `resolved-promise-passes-non-nil-through` MUST
- `rejected-promise-preserves-extension-supplied-reason` MUST
- `rejected-promise-from-message-builds-a-fresh-error` MUST
- `settled-promise-nil-resolves-undefined` MUST
- `settled-promise-passes-a-thenable-through-unchanged` MUST
- `settled-promise-resolves-a-non-thenable` MUST
- `settled-promise-rejects-on-a-throwing-then-getter` MUST
- `settled-promise-rejects-when-dispatch-is-unavailable` MUST
- `call-outcome-three-cases` MUST
- `call-outcome-and-settlement-are-non-sendable` MUST
- `call-outcome-returned-nil-is-not-void-success` MUST
- `call-refuses-when-trampoline-cannot-be-installed` MUST
- `call-normalizes-nullish-this-arg` MUST
- `call-catches-the-callbacks-own-throw` MUST
- `outcome-refuses-a-malformed-trampoline-record` MUST
- `outcome-requires-error-property-on-failure` MUST
- `can-dispatch-checks-both-helpers-present` MUST
- `can-dispatch-installs-the-trampoline-as-a-side-effect` MUST
- `dispatch-unavailable-message-is-shared-verbatim` MUST
- `observe-rejection-leaves-value-unchanged` MUST
- `observe-rejection-only-attaches-to-a-thenable` MUST
- `observe-rejection-reads-the-rejection-reason-off-the-actual-arguments` MUST
- `settlement-non-thenable-is-fulfilled-with-itself` MUST
- `settlement-resumes-the-continuation-exactly-once` MUST
- `settlement-does-not-time-out` MUST

## Behavioral Requirements

- **main-actor-isolation**: `VSCodeAPI` MUST be declared `@MainActor`, so every static member runs on the same actor JavaScriptCore uses to invoke the blocks it builds.
- **stateless-enum**: `VSCodeAPI` MUST be a caseless `enum` with no stored state; every operation MUST derive its answer solely from its arguments and from `JSContext.current()`.
- **member-builds-a-block-closure**: `member(_:of:whenTornDown:body:)` MUST return a `@convention(block) () -> JSValue?` closure boxed as `Any`, suitable for the `implementation` parameter of an adaptor's member-defining call.
- **member-block-asserts-isolation-internally**: the block `member(_:of:whenTornDown:body:)` returns MUST wrap its body in `MainActor.assumeIsolated { ... }`, since a `@convention(block)` closure cannot itself carry `@MainActor` in its type, and JavaScriptCore calls it from whatever thread made the call.
- **member-captures-owner-weakly**: `member(_:of:whenTornDown:body:)` MUST capture `owner` weakly inside the block, so the callback's continued existence in JavaScript does not keep a deallocated adaptor instance alive.
- **member-answers-teardown-response-when-owner-gone**: the block MUST call `tornDown(path:response:)` instead of invoking `body`, when `owner` has already been deallocated by the time the block runs.
- **teardown-response-two-cases**: `TeardownResponse` MUST provide exactly two cases, `rejectedPromise` and `raisedException`, and MUST be `Sendable`.
- **torn-down-dispatches-by-response**: `tornDown(path:response:)` MUST answer a rejected promise, via `rejectedPromise(message:in:)`, for `.rejectedPromise`, and MUST raise a JavaScript exception, via `raise(_:in:)`, for `.raisedException`; it MUST answer `nil` when `JSContext.current()` is `nil`.
- **current-arguments-never-nil**: `currentArguments()` MUST answer an empty array, never `nil`, when `JSContext.currentArguments()` cannot be read as `[JSValue]` or when there is no call in flight.
- **array-length-requires-true-array**: `arrayLength(of:)` MUST require `value.isArray` before reading the `length` property, so an object literal carrying a numeric `length` is never treated as a decodable array.
- **array-length-uses-exact-int32-conversion**: `arrayLength(of:)` MUST read the array's length using `Int32(exactly:)` on the numeric `length` value, and MUST NOT use `toInt32()`, so a length outside the `Int32` range (such as the `length` of an array built with `new Array(4294967295)`) answers `nil` instead of wrapping to a small, plausible-looking count.
- **array-length-bounds-decoding**: `arrayLength(of:)` MUST log an error and answer `nil` for any array whose length exceeds `maximumDecodableArrayLength` (100,000).
- **raise-sets-context-exception**: `raise(_:in:)` MUST set `context.exception` to a newly built `Error` and MUST always return `nil`.
- **raise-logs-when-error-construction-fails**: `raise(_:in:)` MUST log an error when `JSValue(newErrorFromMessage:in:)` answers `nil`, and MUST still leave the call to return `nil` in that case, so the caller sees no throw beyond the log line.
- **resolved-promise-nil-becomes-undefined**: `resolvedPromise(with:in:)` MUST resolve a `nil` value with JavaScript `undefined`, and MUST NOT resolve it with `null`.
- **resolved-promise-passes-non-nil-through**: `resolvedPromise(with:in:)` MUST resolve any non-`nil` value with that value unchanged, via `JSValue(newPromiseResolvedWithResult:in:)`.
- **rejected-promise-preserves-extension-supplied-reason**: `rejectedPromise(reason:in:)` MUST build its rejected promise from the given `JSValue` unchanged, preserving that reason's own `Error` subclass, `stack`, and any custom properties.
- **rejected-promise-from-message-builds-a-fresh-error**: `rejectedPromise(message:in:)` MUST build a fresh `Error` from `message` via `JSValue(newErrorFromMessage:in:)`, delegating to `rejectedPromise(reason:in:)`, and MUST answer `nil` without producing any promise when that construction fails.
- **settled-promise-nil-resolves-undefined**: `settledPromise(for:in:)` MUST resolve with `undefined`, via `resolvedPromise(with: nil, in:)`, when `value` is `nil`.
- **settled-promise-passes-a-thenable-through-unchanged**: `settledPromise(for:in:)` MUST return the same `JSValue` unchanged, not a wrapping promise, when `value` is a thenable, preserving its identity and whatever it later settles with.
- **settled-promise-resolves-a-non-thenable**: `settledPromise(for:in:)` MUST resolve with `value` itself, via `resolvedPromise(with:in:)`, when `value` is not a thenable.
- **settled-promise-rejects-on-a-throwing-then-getter**: `settledPromise(for:in:)` MUST reject with the `Error` a throwing `.then` property getter raised, rather than resolving with the raw object.
- **settled-promise-rejects-when-dispatch-is-unavailable**: `settledPromise(for:in:)` MUST reject with `dispatchUnavailableMessage(for:)` when the context cannot answer whether `value` is thenable, rather than guessing "not a thenable" and resolving with the raw object.
- **call-outcome-three-cases**: `CallOutcome` MUST provide exactly three cases: `.returned(JSValue?)`, `.threw(JSValue)`, and `.unavailable`.
- **call-outcome-and-settlement-are-non-sendable**: `CallOutcome`, `Settlement`, and `ThenLookup` MUST NOT be declared `Sendable` (unlike `TeardownResponse`), since each carries a `JSValue`; every producer and consumer stays confined to `VSCodeAPI`'s own `@MainActor` isolation.
- **call-outcome-returned-nil-is-not-void-success**: a caller MUST treat `.returned(nil)` as "no value was read back" — distinct from both success and failure — never as "the callback returned nothing", which is `.returned` holding a `JSValue` for `undefined`.
- **call-refuses-when-trampoline-cannot-be-installed**: `call(_:thisArg:arguments:)` MUST answer `.unavailable`, and MUST NOT invoke `function` directly, when `function.context` is `nil` or the dispatch trampoline's `call` helper cannot be installed in that context.
- **call-normalizes-nullish-this-arg**: `call(_:thisArg:arguments:)` MUST bind `thisArg` as JavaScript `undefined` when the caller passes `nil`.
- **call-catches-the-callbacks-own-throw**: `call(_:thisArg:arguments:)` MUST answer `.threw(reason)` — never let the exception reach the host's own exception handling — when a call through this file's own trampoline reports failure.
- **outcome-refuses-a-malformed-trampoline-record**: `outcome(of:in:)` MUST log an error and answer `.unavailable` when the settled value is not an object, or its `ok` property is missing or not a boolean.
- **outcome-requires-error-property-on-failure**: `outcome(of:in:)` MUST answer `.unavailable`, not `.threw`, when `ok` is `false` but the record's `error` property is absent.
- **can-dispatch-checks-both-helpers-present**: `canDispatch(in:)` MUST answer `true` only when both the `call` and `thenOf` trampoline members are present and neither `undefined` nor `null`; it MUST NOT invoke either to verify callability.
- **can-dispatch-installs-the-trampoline-as-a-side-effect**: calling `canDispatch(in:)` MUST evaluate and cache the trampoline in `context` if it has not already been installed, so a later dispatch in the same context finds it cached.
- **dispatch-unavailable-message-is-shared-verbatim**: `dispatchUnavailableMessage(for:)` MUST produce the identical message text used by every refusal on the dispatch-unavailable path, naming the context via `name(of:)`.
- **observe-rejection-leaves-value-unchanged**: `observeRejection(of:in:_:)` MUST attach `handler` to a promise derived from `value.then`, and MUST leave `value` itself as what the caller keeps and hands back to the extension; the derived promise MUST be discarded.
- **observe-rejection-only-attaches-to-a-thenable**: `observeRejection(of:in:_:)` MUST answer `false`, and attach nothing, when `value` is not a thenable, when reading `.then` throws, or when calling `.then` throws.
- **observe-rejection-reads-the-rejection-reason-off-the-actual-arguments**: the `onRejected` block `observeRejection(of:in:_:)` builds MUST read its argument via `currentArguments().first`, not via a declared formal parameter.
- **settlement-non-thenable-is-fulfilled-with-itself**: `settlement(of:in:)` MUST answer `.fulfilled(value)` immediately when `value` is not a thenable.
- **settlement-resumes-the-continuation-exactly-once**: `settlement(of:in:)` MUST resume its underlying `CheckedContinuation` at most once even when the extension's own `then` implementation calls both handlers, calls one handler more than once, or throws after a handler already fired; the first settlement by call order MUST win.
- **settlement-does-not-time-out**: `settlement(of:in:)` MUST impose no timeout on a thenable that never settles, matching upstream VS Code's own behavior for a promise given to an API such as `showQuickPick` that never resolves.
