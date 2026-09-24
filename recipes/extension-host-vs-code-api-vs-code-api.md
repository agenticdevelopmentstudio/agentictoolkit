---
id: 94dc5dad-be14-4520-8afe-e944e59a0117
title: VSCodeAPI
domain: agentictoolkit://recipes/extension-host-vs-code-api-vs-code-api
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Shared ceremony every vscode.* adaptor uses for installing members, promise
  settlement, calling back into extensions, and stub sub-namespaces.
platforms:
- swift
- macos
tags:
- extension-host
- vscode-api
- javascriptcore
- mainactor
- disposable
- bridge
depends-on: []
related:
- agentictoolkit://recipes/extension-host-vs-code-api-main-thread-commands
- agentictoolkit://recipes/extension-host-vs-code-api-main-thread-diagnostics
- agentictoolkit://recipes/extension-host-vs-code-api-main-thread-language-models
- agentictoolkit://recipes/extension-host-vs-code-api-main-thread-languages
- agentictoolkit://recipes/extension-host-vs-code-api-js-value-bridge
references:
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/VSCodeAPI.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Extensions/VSCodeAPISettlementTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Extensions/VSCodeAPIDisposableTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Extensions/VSCodeAPISubNamespaceTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadCommands.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/project.yml (agentictoolkit)
approved-by: ''
approved-date: ''
---

# VSCodeAPI

## Overview

`VSCodeAPI.swift` (`packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/VSCodeAPI.swift`) is the shared ceremony every `vscode.*` namespace adaptor in the extension host needs, written once. `MainThreadCommands` is the first of five adaptors the type's own doc names — the other four are `workspace`, `window`, `languages`, and `lm` — and each of them installs its members through the same seam, answers a torn-down host the same way, invokes extension callbacks the same way, and settles the same promises. `VSCodeAPI` is a caseless `enum`: it has no stored state, and every operation derives entirely from the arguments it is given and from `JSContext.current()`, which JavaScriptCore fills in for the duration of a block call. The whole type is `@MainActor`-isolated because `JSValue` is not `Sendable`, and JavaScriptCore calls every block this file builds on the thread that made the call — for an `ExtensionHost`, always the main actor.

Three groups of primitives make up the file. The first — `member(_:of:whenTornDown:body:)`, `currentArguments()`, `arrayLength(of:)`, `raise(_:in:)`, and the promise builders (`resolvedPromise`, `rejectedPromise`, `settledPromise`) — are the small pieces an adaptor member reaches for directly. The second — `call(_:thisArg:arguments:)`, `observeRejection(of:in:_:)`, and `settlement(of:in:)`, built over a JavaScript trampoline evaluated once per `JSContext` and cached under `__vscodeAPITrampoline` — let Swift call back into an extension's own callback or thenable without an uncaught extension exception ever reaching the host's own exception handling. The third — `disposable(in:onDispose:)` and `subNamespace(path:members:in:recordMiss:recordProbe:)`, the latter built over a second trampoline cached under `__vscodeSubNamespaceFactory` — give an adaptor a ready-made `Disposable` and a throw-on-unimplemented-member stub namespace without writing its own JavaScript `Proxy`. Three small `@unchecked Sendable` box types (`UncheckedSendableBox`, its `UncheckedJSValueBox` specialization, and `PromiseSettlementBox`) exist only to carry `JSValue`s already confined to one isolation domain across standard-library signatures that require `Sendable` regardless.

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

## Appearance

Not applicable — this is the extension host's shared `vscode.*` member/promise/dispatch ceremony, not a visual component.

## States

Not applicable — this is the extension host's shared `vscode.*` member/promise/dispatch ceremony, not a visual component. `VSCodeAPI` itself holds no state; the lifecycle-shaped behavior that exists (an owner already torn down, a trampoline not yet installed, a settlement not yet resolved) is covered under Behavioral Requirements.

## Accessibility

Not applicable — this is the extension host's shared `vscode.*` member/promise/dispatch ceremony, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
| --- | --- | --- | --- |
| vscodeapi-001 | member-captures-owner-weakly, member-answers-teardown-response-when-owner-gone, torn-down-dispatches-by-response | a member built via `member(_:of:whenTornDown: .raisedException:body:)` is called after `owner` has been deallocated | the block calls `tornDown(path:response: .raisedException)`, which raises a JavaScript exception; `body` is never invoked — traced to `member(_:of:whenTornDown:body:)` and `tornDown(path:response:)` |
| vscodeapi-002 | array-length-uses-exact-int32-conversion, array-length-bounds-decoding | `arrayLength(of:)` given a real JS array built with `new Array(4294967295)` (its `length` exceeds the `Int32` range) | answers `nil` via the `Int32(exactly:)` guard, never reaching a Swift range built from a wrapped-around count |
| vscodeapi-003 | array-length-bounds-decoding | `arrayLength(of:)` given an array of exactly 100,001 elements | logs an error naming the count and answers `nil`, since the count exceeds `maximumDecodableArrayLength` (100,000) |
| vscodeapi-004 | raise-sets-context-exception | `raise("boom", in: context)` on a healthy context | `context.exception` is set to a JS `Error` whose message is `"boom"`; the function returns `nil` |
| vscodeapi-005 | resolved-promise-nil-becomes-undefined | `resolvedPromise(with: nil, in: context)` | answers a promise already resolved with JS `undefined`, not `null` — an extension's `result === undefined` check passes |
| vscodeapi-006 | rejected-promise-preserves-extension-supplied-reason | `rejectedPromise(reason: customError, in: context)`, where `customError` is an extension-thrown `Error` subclass carrying custom properties | the returned promise rejects with that exact `JSValue` — same subclass, same `stack`, same custom properties, not a paraphrase |
| vscodeapi-007 | settled-promise-resolves-a-non-thenable, settlement-non-thenable-is-fulfilled-with-itself | `settlement(of:in:)` given a plain array `['alpha', 'beta']` as the value | answers `.fulfilled` with a 2-element array, `'alpha'` at index 0 and `'beta'` at index 1 — `VSCodeAPISettlementTests.aPlainArrayIsFulfilledWithThatSameArray` |
| vscodeapi-008 | settlement-resumes-the-continuation-exactly-once | a thenable whose `then` calls `onFulfilled(['first-win'])`, then afterward calls `onRejected(new Error('too-late'))` | `settlement(of:in:)` answers `.fulfilled` with `['first-win']`; the later rejection call is a no-op and does not trap — `VSCodeAPISettlementTests.resolveFollowedByRejectAnswersTheFulfilmentAndDoesNotTrap` |
| vscodeapi-009 | settled-promise-rejects-on-a-throwing-then-getter, settlement-getter-throw-becomes-rejected | a value whose `then` property getter throws `new Error('getter-boom')` | `settlement(of:in:)` answers `.rejected` with message `'getter-boom'`; the exception does not reach the context's exception handler — `VSCodeAPISettlementTests.aThrowingThenGetterRejectsWithoutReachingTheHostsExceptionHandler` |
| vscodeapi-010 | settlement-unavailable-when-context-cannot-mint-undefined, then-function-distinguishes-four-outcomes | `settlement(of:in:)` called in a `JSContext` whose trampoline's `thenOf` helper cannot answer | answers `.unavailable`; the same array in an untouched context still answers `.fulfilled` — `VSCodeAPISettlementTests.aContextWhoseTrampolineCannotAnswerThenOfIsUnavailable` |
| vscodeapi-011 | disposable-idempotent-by-construction | a `Disposable` from `disposable(in:onDispose:)` has its JS `dispose()` called twice | `onDispose` runs exactly once; no exception is raised — `VSCodeAPIDisposableTests.disposingTwiceRunsOnDisposeExactlyOnce` |
| vscodeapi-012 | disposable-idempotent-by-construction | a `Disposable` from `disposable(in:onDispose:)` has its JS `dispose()` called once | `onDispose` runs exactly once — `VSCodeAPIDisposableTests.disposingOnceRunsOnDisposeOnce` |
| vscodeapi-013 | sub-namespace-unimplemented-member-throws-named-error | reading an unimplemented key off a namespace from `subNamespace(path: "vscode.test", members: [:], in: context)` | throws an `Error` named `NotImplementedError` whose `memberPath` names `path` and the key — `VSCodeAPISubNamespaceTests.anUnimplementedMemberThrowsANotImplementedErrorNamingItsPath` |
| vscodeapi-014 | sub-namespace-probe-keys-answer-quietly | reading a `PROBE_KEYS` member (such as `then`) on an otherwise-unimplemented namespace | answers a quiet feature-detection value without throwing — `VSCodeAPISubNamespaceTests.aProbeKeyAnswersQuietlyRatherThanThrowing` |
| vscodeapi-015 | sub-namespace-records-misses-only-when-a-recorder-is-supplied | `subNamespace(..., recordMiss: { path in ... })` with the recorder supplied, then an unimplemented member is read | `recordMiss` is called once with the full member path, in addition to the thrown `NotImplementedError` — `VSCodeAPISubNamespaceTests.aMissIsRecordedWhenARecorderIsSupplied` |
| vscodeapi-016 | sub-namespace-swallows-a-throwing-recorder | `subNamespace(..., recordMiss:)` supplied with a recorder that itself throws, then an unimplemented member is read | the extension still sees the same `NotImplementedError`; the recorder's own throw is discarded — `VSCodeAPISubNamespaceTests.aThrowingRecordMissDoesNotReplaceTheNotImplementedError` |
| vscodeapi-017 | sub-namespace-is-read-only | assigning to, or deleting, a member on a `subNamespace` `Proxy` | throws a `TypeError` naming `path` and the key; the assignment or deletion does not succeed — traced to `subNamespaceFactorySource`'s `set`/`deleteProperty` traps |
| vscodeapi-018 | call-refuses-when-trampoline-cannot-be-installed | `call(function, thisArg: nil, arguments: [])` where `function.context` is `nil` | answers `.unavailable` without invoking `function` — traced to `call(_:thisArg:arguments:)`'s guard clause |
| vscodeapi-019 | outcome-refuses-a-malformed-trampoline-record | `outcome(of:in:)` given a settled value that is not an object (a bare number) | logs an error and answers `.unavailable`, not `.threw` and not `.returned` — traced to `outcome(of:in:)`'s guard clause |

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

## Deep Linking

Not applicable: `VSCodeAPI.swift` defines no URL, route, or navigable destination — it is in-process JavaScriptCore ceremony only.

## Localization

Every user-facing string this file produces is a hardcoded English literal; there is no localization key or lookup anywhere in `VSCodeAPI.swift`.

| String | Context |
| --- | --- |
| dispatch-unavailable message (`dispatchUnavailableMessage(for:)`) | shown to an extension, via a raised exception or a rejected promise, when the command/promise dispatch trampoline cannot be installed in its context |
| `NotImplementedError` message (`subNamespaceFactorySource`) | thrown to an extension reading an unimplemented `vscode.*` member, naming the member's path |
| read-only assignment/deletion `TypeError` messages (`subNamespaceFactorySource`) | thrown to an extension attempting to assign to or delete a member of a `subNamespace` stub |
| trampoline/factory install-failure log lines (`sharedHelper(in:)`, `subNamespaceFactory(in:)`) | host-only diagnostic text, never seen by the extension itself |
| malformed-record and oversized-array log lines (`outcome(of:in:)`, `arrayLength(of:)`) | host-only diagnostic text, never seen by the extension itself |

## Accessibility Options

Not applicable: `VSCodeAPI.swift` renders nothing and responds to no system accessibility setting (Reduce Motion, larger text, VoiceOver, or otherwise).

## Feature Flags

Not applicable: `VSCodeAPI.swift` contains no feature-flag key or conditional gate; every code path it defines is unconditionally reachable.

## Analytics

Not applicable: `VSCodeAPI.swift` emits no analytics or telemetry event; its only observability channel is the diagnostic logging covered under Logging.

## Privacy

- **Data collected**: none of its own; `VSCodeAPI` holds no stored state and collects nothing about the user. It transiently handles values an extension itself supplies (its callbacks, its thenables, its error objects) for the duration of one call.
- **Storage**: none — `VSCodeAPI` is a stateless enum with no persisted or cached data of its own; the trampoline objects it caches on `globalThis` live only for the lifetime of their `JSContext`.
- **Transmission**: none — everything happens in-process inside JavaScriptCore; nothing here makes a network call or writes to disk.
- **Retention**: an extension-supplied value is retained only as long as the call stack that produced it, or (for `settlement(of:in:)`) until the thenable it is watching settles or its `JSContext` is torn down; `member(_:of:whenTornDown:body:)`'s weak capture of `owner` ensures a torn-down adaptor is not kept alive by a still-reachable JavaScript callback.

## Logging

Subsystem: matches the host's `Loggable`-derived subsystem (via `makeLogger()`) | Category: `VSCodeAPI`

| Event | Level | Trigger |
| --- | --- | --- |
| oversized-array refusal | error | `arrayLength(of:)` refuses a JS array-like value whose length exceeds `maximumDecodableArrayLength` |
| error-construction failure | error | `raise(_:in:)` finds `JSValue(newErrorFromMessage:in:)` answers `nil` for the message it was given |
| malformed trampoline record | error | `outcome(of:in:)` finds the settled dispatch value is not an object, or its `ok` property is missing or not a boolean |
| trampoline install failure | error | `sharedHelper(in:)` cannot evaluate or cache `helperSource` in a context |
| sub-namespace factory install failure | error | `subNamespaceFactory(in:)` cannot evaluate or cache `subNamespaceFactorySource` in a context |

## Platform Notes

- **SwiftUI**: not applicable — `VSCodeAPI.swift` imports only Foundation, JavaScriptCore, OSLog, and this framework's own `Loggable`; nothing here renders a view or depends on SwiftUI.
- **AppKit / UIKit**: this is the source. `VSCodeAPI.swift` lives in `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/`, part of the macOS-only `AgenticToolkitMacOS` module per `project.yml`; it is `@MainActor` because `JSValue` is not `Sendable` and JavaScriptCore always calls an installed block on the thread that made the call, which for this host is the main actor driven by AppKit's own run loop. No iOS target packages this file today.
- **Compose**: model `VSCodeAPI` as a Kotlin `object` (or a set of top-level functions) confined to the main dispatcher, since there is no per-instance state to gate; `JSValue`/`JSContext` become whatever the chosen embeddable JS engine binding uses, and the evaluate-once-and-cache-under-a-global trampoline pattern ports directly, since it depends only on the engine's own global-object and `Proxy` support, which most JVM-embeddable JS engines provide.
- **React/Web**: this component's own counterpart needs no cross-boundary bridging ceremony at all, since a real VS Code extension already runs as JavaScript inside the same runtime as the host (VS Code's own `vscode.d.ts` and extension host process fill this role); a from-scratch web port only needs the once-only-settlement guard around a native `Promise`'s `resolve`/`reject` and the `Proxy`-based stub namespace, both of which are already plain JavaScript in `helperSource`/`subNamespaceFactorySource` and need no translation.
- **WinUI 3**: model `VSCodeAPI` as a static class confined to a captured `DispatcherQueue` — WinUI 3's nearest equivalent to `@MainActor` — asserting `DispatcherQueue.HasThreadAccess` or marshaling via `TryEnqueue` at every entry point, since nothing catches a wrong-thread call at compile time the way Swift's actor isolation does. `JSContext`/`JSValue` become the chosen embeddable engine's types (ClearScript's `ScriptEngine`/`ScriptObject`, or Jint's `Engine`/`JsValue`); the promise builders and `settlement(of:in:)` become helpers around `TaskCompletionSource<object?>`, guarded by `Interlocked.CompareExchange` in place of the once-only continuation box, since .NET has no first-class `Promise` type and no `CheckedContinuation` leaked-continuation diagnostic to inherit. The frozen-trampoline-object pattern ports if the engine's script realm supports freezing a host-exposed object; the `Proxy`-based `subNamespace` stub has no built-in .NET equivalent and must be hand-rolled over `DynamicObject`/`IDynamicMetaObjectProvider` (ClearScript) or a custom `ObjectInstance` override (Jint) to reproduce the `get`/`has`/`set`/`deleteProperty`/`ownKeys`/`getOwnPropertyDescriptor` trap set this file defines directly in JavaScript.

## Design Decisions

- **Decision**: `call(_:thisArg:arguments:)` never falls back to invoking `function` directly when the trampoline cannot be installed.
  **Rationale**: an uncaught throw from a direct call is exactly what routing every call through the JavaScript trampoline exists to keep out of the host's own exception handling; a direct-call fallback would reopen that path for precisely the contexts where the trampoline is least trustworthy.
  **Approved**: pending

- **Decision**: `sharedHelper(in:)` and `subNamespaceFactory(in:)` adopt whatever object already exists under their cached global name rather than verifying its provenance.
  **Rationale**: a JavaScript object cannot prove its provenance to JavaScript, and freezing the object after installation cannot retroactively make an already-adopted impostor genuine. The blast radius is bounded to the pre-empting extension's own context: `outcome(of:in:)` refuses a malformed *returned* record from any caller, and an impostor that throws instead lands in that same extension's own pending-exception state, never another extension's.
  **Approved**: pending

- **Decision**: `settlement(of:in:)` imposes no timeout on an unsettled thenable.
  **Rationale**: upstream VS Code does not settle either, and answering after some fixed delay would invent user-visible-wrong behavior (an extension told a picker was dismissed that the user never saw). The cost — one leaked continuation and two capturing blocks per un-settling thenable — is confined to the extension whose own thenable never resolves.
  **Approved**: pending

- **Decision**: the `onFulfilled`/`onRejected` blocks in `settlement(of:in:)`, and `observeRejection`'s `onRejected`, capture no `JSValue`, reading their argument from `currentArguments()` or minting a fresh `undefined` from `JSContext.current()` at call time instead.
  **Rationale**: a `JSValue` retains its `JSContext`, so a block capturing one and exported to JavaScript creates a retain cycle between the block and the context; the leak would then be the whole context rather than one continuation.
  **Approved**: pending

- **Decision**: `CallOutcome.returned(nil)` is a distinct, narrow case rather than being folded into "the callback returned `undefined`".
  **Rationale**: a callback that genuinely returns nothing answers a `JSValue` holding `undefined`, not a Swift `nil`; `nil` here means the bridge itself declined to answer. Conflating the two would let a caller resolve an extension's promise with `undefined` — the same answer a successful `void` command produces — when the true situation was a dispatch failure.
  **Approved**: pending

- **Decision**: `UncheckedSendableBox` is one generic type rather than several private, purpose-built box structs.
  **Rationale**: several unrelated standard-library signatures independently require `Sendable` for values (`JSValue`s and closures over them) this module cannot conform, because `JSValue` is a JavaScriptCore class it does not own. One declaration replaces what would otherwise be several private structs under different names, each a copy of another.
  **Approved**: pending

- **Decision**: `VSCodeAPI`, `CallOutcome`, `Settlement`, and `ThenLookup` carry no `Sendable` conformance beyond `TeardownResponse`'s explicit one.
  **Rationale**: every value in play (`JSValue`, `JSContext`) is non-`Sendable` by nature, and every producer and consumer is already confined to `VSCodeAPI`'s own `@MainActor` isolation; adding a conformance would either be a false promise or require boxing types that have no reason to leave the actor.
  **Approved**: pending

## Compliance

| Check | Status | Category |
| --- | --- | --- |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [secure-log-output](agenticdevelopercookbook://compliance/security#secure-log-output) | passed | Security |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | passed | Security |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |

`VSCodeAPI` is exactly the ceremony every `vscode.*` adaptor needs and nothing an adaptor's own domain logic — command lookup, diagnostic storage, tree data — should be doing itself, so separation-of-concerns passes. `VSCodeAPISettlementTests.swift`, `VSCodeAPIDisposableTests.swift`, and `VSCodeAPISubNamespaceTests.swift` cover `settlement(of:in:)`, `disposable(in:onDispose:)`, and `subNamespace(path:members:in:recordMiss:recordProbe:)` in real depth, but `arrayLength(of:)`, `raise(_:in:)`, the promise builders, `call(_:thisArg:arguments:)`, `canDispatch(in:)`, `observeRejection(of:in:_:)`, and `member(_:of:whenTornDown:body:)` have no dedicated test in those suites — they are exercised only indirectly through adaptors such as `MainThreadCommands` — so unit-test-coverage is partial. Every failure path answers an explicit `.unavailable`/`.threw`/`.rejected` case, a raised exception, or a logged error rather than silently swallowing anything, so explicit-error-handling passes. Nothing this file logs is a secret, token, or credential — only member paths, counts, and diagnostic error text — so secure-log-output passes. `arrayLength(of:)`'s hard ceiling on decodable array length, and its refusal to trust `toInt32()`'s wraparound-prone conversion, are exactly the kind of untrusted-input bound input-sanitization asks for, so it passes. Every user-facing string this file produces — the dispatch-unavailable message, the `NotImplementedError` message, and the read-only `TypeError` messages — is a hardcoded English literal with no localization key, so no-hardcoded-strings fails.

## Change History

| Version | Date | Author | Changes |
| --- | --- | --- | --- |
| 1.0.0 | | | Initial creation |
