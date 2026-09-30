<!-- leaf: implement-extension-host-vs-2/code-api-vs-code-api--part-3 · source: extension-host-vs-code-api-vs-code-api.md -->

# VSCodeAPI — continued (part 3)

**Rules** (cite as `implement-extension-host-vs-2/code-api-vs-code-api--part-3#<slug>`):

- `settlement-handler-blocks-capture-no-jsvalue` MUST
- `settlement-missing-argument-fulfills-as-undefined` MUST
- `settlement-unavailable-when-context-cannot-mint-undefined` MUST
- `settlement-getter-throw-becomes-rejected` MUST
- `then-function-distinguishes-four-outcomes` MUST
- `helper-source-is-evaluated-at-most-once-per-context` MUST
- `trampoline-object-is-frozen-before-caching` MUST
- `sharedhelper-adopts-whatever-object-it-finds` MUST — sharedHelper(in:) MUST adopt whatever object already exists under __vscodeAPITrampoline rather than verifying its …
- `install-trampoline-is-not-fatal-to-activation` MUST
- `helper-function-rejects-nullish-members` MUST
- `context-name-fallback` MUST
- `disposable-idempotent-by-construction` MUST
- `sub-namespace-factory-evaluated-once-per-context` MUST
- `sub-namespace-unimplemented-member-throws-named-error` MUST
- `sub-namespace-probe-keys-answer-quietly` MUST
- `sub-namespace-is-read-only` MUST
- `sub-namespace-table-has-no-inherited-prototype` MUST
- `sub-namespace-records-misses-only-when-a-recorder-is-supplied` MUST
- `sub-namespace-records-probes-only-from-has-and-descriptor` MUST
- `sub-namespace-swallows-a-throwing-recorder` MUST
- `sub-namespace-returns-nil-when-factory-or-table-unavailable` MUST
- `logger-conformance` MUST
- `unchecked-sendable-box-never-crosses-isolation` MUST
- `unchecked-jsvalue-box-is-a-named-specialization` MUST
- `promise-settlement-box-carries-a-fixed-pair` MUST

- **settlement-handler-blocks-capture-no-jsvalue**: neither the `onFulfilled` nor `onRejected` block `settlement(of:in:)` passes to the extension's `then` MUST capture a `JSValue` directly; each MUST read its argument from `currentArguments()` or mint a fresh `undefined` from `JSContext.current()` at call time.
- **settlement-missing-argument-fulfills-as-undefined**: a handler invoked with no argument MUST settle `settlement(of:in:)` as a `JSValue` holding `undefined`, not as `.unavailable` and not as a Swift `nil`.
- **settlement-unavailable-when-context-cannot-mint-undefined**: `settlement(of:in:)` MUST answer `.unavailable` before attaching any handler, when `context` can no longer produce a `JSValue` for `undefined`.
- **settlement-getter-throw-becomes-rejected**: `settlement(of:in:)` MUST answer `.rejected(reason)` with the thrown value, and MUST NOT let the exception reach the context's `exceptionHandler`, when reading `value.then` throws.
- **then-function-distinguishes-four-outcomes**: `thenFunction(of:in:)` MUST distinguish `.notThenable` (no callable `then`), `.thenable(JSValue)`, `.threw(JSValue)` (reading `.then` raised), and `.unavailable` (the lookup itself could not be performed); callers MUST NOT conflate `.unavailable` with `.notThenable`.
- **helper-source-is-evaluated-at-most-once-per-context**: `sharedHelper(in:)` MUST evaluate `helperSource` at most once per `JSContext`, caching the result under the non-enumerable, non-writable, non-configurable global `__vscodeAPITrampoline`, and reading the cached value back on every later call.
- **trampoline-object-is-frozen-before-caching**: the JavaScript trampoline object MUST be frozen with `Object.freeze` before it is cached, so a member-level reassignment is refused in addition to a whole-binding reassignment.
- **sharedHelper-adopts-whatever-object-it-finds**: `sharedHelper(in:)` MUST adopt whatever object already exists under `__vscodeAPITrampoline` rather than verifying its provenance, for a context reached before anything has called `installTrampoline(in:)`.
- **install-trampoline-is-not-fatal-to-activation**: `installTrampoline(in:)` MUST answer `nil`, through `sharedHelper(in:)`'s own logging, rather than throwing or trapping, when the eager install fails, leaving the lazy path through `call`/`canDispatch` as the fallback.
- **helper-function-rejects-nullish-members**: `helperFunction(_:in:)` MUST answer `nil` when the named member on the trampoline is `undefined` or `null`, in addition to when the trampoline itself could not be installed.
- **context-name-fallback**: `name(of:)` MUST answer `"<unnamed>"` when `context.name` is `nil`.
- **disposable-idempotent-by-construction**: `disposable(in:onDispose:)` MUST return a JS object whose `dispose()` calls `onDispose` on its first invocation and MUST do nothing on every later invocation, tracked by a `disposed` flag captured in the returned block's closure.
- **sub-namespace-factory-evaluated-once-per-context**: `subNamespaceFactory(in:)` MUST evaluate `subNamespaceFactorySource` at most once per `JSContext`, matching `sharedHelper(in:)`'s caching pattern under its own global name `__vscodeSubNamespaceFactory`.
- **sub-namespace-unimplemented-member-throws-named-error**: a `Proxy` built by `subNamespace(path:members:in:recordMiss:recordProbe:)` MUST throw a `NotImplementedError` — an `Error` named `NotImplementedError` with a `memberPath` property equal to `path` joined with the key — from its `get` trap, for any key that is neither in `members` nor one of the shim's `PROBE_KEYS`.
- **sub-namespace-probe-keys-answer-quietly**: the `get` trap MUST answer a quiet feature-detection value, never throw, for every key in `PROBE_KEYS` (the `Object.prototype` own names plus `then`, `toJSON`, `__esModule`, `default`, `inspect`, `prototype`, `nodeType`, and `$$typeof`), even when that key is not implemented.
- **sub-namespace-is-read-only**: the `set` and `deleteProperty` traps MUST both throw a `TypeError` naming `path` and the key, and MUST NOT allow any assignment or deletion to succeed silently.
- **sub-namespace-table-has-no-inherited-prototype**: the object holding `members` MUST be built with `Object.create(null)`, so `Object.prototype` member names are never already present in it before any real member is added.
- **sub-namespace-records-misses-only-when-a-recorder-is-supplied**: the `get` trap's throwing branch MUST call `recordMiss` with the full member path when a `recordMiss` block is supplied, and MUST NOT call it — while still throwing the same `NotImplementedError` — when none is supplied.
- **sub-namespace-records-probes-only-from-has-and-descriptor**: `recordProbe` MUST be invoked only from the `has` and `getOwnPropertyDescriptor` traps' negative branches, and MUST NOT be invoked from a `get` of a `PROBE_KEYS` name or from a symbol key.
- **sub-namespace-swallows-a-throwing-recorder**: a throw from `recordMiss` or `recordProbe` itself MUST be caught and discarded, and MUST NOT replace the `NotImplementedError` the extension is entitled to see, or turn a boolean-returning trap into an uncaught throw.
- **sub-namespace-returns-nil-when-factory-or-table-unavailable**: `subNamespace(path:members:in:recordMiss:recordProbe:)` MUST answer `nil` when the factory could not be installed in `context`, or when `context` cannot produce a prototype-less object to hold `members`.
- **logger-conformance**: `VSCodeAPI` MUST conform to `Loggable`, exposing a `nonisolated static let logger` built via `makeLogger()`, as the destination for every failure that has no JavaScript-facing channel.
- **unchecked-sendable-box-never-crosses-isolation**: `UncheckedSendableBox` MUST only ever carry a value already confined to one isolation domain across a Swift signature that requires `Sendable`, never to move a value between isolation domains.
- **unchecked-jsvalue-box-is-a-named-specialization**: `UncheckedJSValueBox` MUST be the type alias `UncheckedSendableBox<JSValue?>`, not a second, independent box declaration.
- **promise-settlement-box-carries-a-fixed-pair**: `PromiseSettlementBox` MUST hold exactly one promise's `resolve` and `reject` `JSValue`s, read back only by name, and MUST NOT double as a general-purpose value box.
## Configuration

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `path` | `String` | none (required) | The namespace member's dotted path; used only in log lines, dispatch-unavailable/teardown messages, and `NotImplementedError.memberPath` — never read back to decide behavior. |
| `owner` | generic `Owner: AnyObject` | none (required) | The adaptor instance a member's `body` runs against; captured weakly by `member(_:of:whenTornDown:body:)`. |
| `whenTornDown` | `TeardownResponse` | none (required) | Chooses whether a call after `owner`'s deallocation raises an exception or rejects a promise. |
| `members` | `[String: Any]` | empty | The implemented members of a `subNamespace`; every other key throws `NotImplementedError`. |
| `recordMiss` | `(@convention(block) (String) -> Void)?` | `nil` | Optional hook invoked with an unimplemented member's path, in addition to the thrown error. |
| `recordProbe` | `(@convention(block) (String) -> Void)?` | `nil` | Optional hook invoked with a quietly-missed member's path from the `has`/`getOwnPropertyDescriptor` traps. |
| `maximumDecodableArrayLength` | `Int` (public static constant) | `100_000` | The hard ceiling `arrayLength(of:)` enforces on any JS array-like value's decoded length; not overridable per call. |

## Localization

Every user-facing string this file produces is a hardcoded English literal; there is no localization key or lookup anywhere in `VSCodeAPI.swift`.

| String | Context |
| --- | --- |
| dispatch-unavailable message (`dispatchUnavailableMessage(for:)`) | shown to an extension, via a raised exception or a rejected promise, when the command/promise dispatch trampoline cannot be installed in its context |
| `NotImplementedError` message (`subNamespaceFactorySource`) | thrown to an extension reading an unimplemented `vscode.*` member, naming the member's path |
| read-only assignment/deletion `TypeError` messages (`subNamespaceFactorySource`) | thrown to an extension attempting to assign to or delete a member of a `subNamespace` stub |
| trampoline/factory install-failure log lines (`sharedHelper(in:)`, `subNamespaceFactory(in:)`) | host-only diagnostic text, never seen by the extension itself |
| malformed-record and oversized-array log lines (`outcome(of:in:)`, `arrayLength(of:)`) | host-only diagnostic text, never seen by the extension itself |

