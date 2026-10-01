---
id: 94dc5dad-be14-4520-8afe-e944e59a0117
title: VS Code API Bridge
domain: agentictoolkit://cookbook/workspace/extensions/vscode-api
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
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
- disposable
- bridge
depends-on: []
related:
- agentictoolkit://cookbook/workspace/extensions/vscode-api/commands/main-thread-commands
- agentictoolkit://cookbook/workspace/extensions/vscode-api/languages/main-thread-diagnostics
- agentictoolkit://cookbook/workspace/extensions/vscode-api/language-models/main-thread-language-models
- agentictoolkit://cookbook/workspace/extensions/vscode-api/languages/main-thread-languages
- agentictoolkit://cookbook/workspace/extensions/host/js-value-bridge
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

# VS Code API Bridge

## Overview

The bridge is the shared ceremony every `vscode.*` namespace adaptor in the
extension host needs, written once. The commands adaptor is the first of
five adaptors this concept names — the other four are workspace, window,
languages, and language models — and each of them installs its members
through the same seam, answers a torn-down host the same way, invokes
extension callbacks the same way, and settles the same promises. The bridge
is a stateless collection of operations: it holds no state of its own, and
every operation derives entirely from the arguments it is given and from
whichever script call is currently active. Every operation MUST run
confined to a single, serialized execution context, since the values this
bridge passes between the host and an extension's script are not safe to
share across concurrent contexts, and the script engine always invokes a
callback on the thread that made the call — for this host, always that one
confined context.

Three groups of primitives make up this concept. The first — installing a
member with a teardown response, reading the current call's arguments,
reading an array-like value's length, raising a script exception, and the
promise builders (a resolved promise, a rejected promise, a settled
promise) — are the small pieces an adaptor member reaches for directly. The
second — calling back into an extension's own callback or thenable,
observing a thenable's rejection, and reading a thenable's settlement,
built over a script trampoline evaluated once per script context and
cached under a fixed global name — let this host call back into an
extension's own callback or thenable without an uncaught extension
exception ever reaching the host's own exception handling. The third —
building a ready-made disposable, and building a throw-on-unimplemented-
member stub sub-namespace over a second trampoline cached under its own
fixed global name — give an adaptor both without writing its own proxy
object. Three small concurrency-safety wrapper values exist only to carry
values already confined to one execution context across shared-library
signatures that require concurrency safety regardless.

## Behavioral Requirements

- **thread-confined-access**: The bridge's every operation MUST run
  confined to the same single, serialized execution context the script
  engine uses to invoke the callbacks it builds.
- **stateless-enum**: The bridge MUST be a stateless collection of
  operations with no stored state; every operation MUST derive its answer
  solely from its arguments and from whichever script call is currently
  active.
- **member-builds-a-block-closure**: Installing a member MUST return a
  callback closure usable directly as the implementation of an adaptor's
  member-defining call.
- **member-block-asserts-isolation-internally**: The callback that
  installing a member returns MUST assert, at the start of its body, that
  it is running on the bridge's confined execution context, since the
  callback's own declared type cannot itself carry that confinement, and
  the script engine calls it from whatever thread made the call.
- **member-captures-owner-weakly**: Installing a member MUST capture the
  owning adaptor instance weakly inside the callback, so the callback's
  continued existence in the extension's script does not keep a
  deallocated adaptor instance alive.
- **member-answers-teardown-response-when-owner-gone**: The callback MUST
  answer the configured teardown response instead of invoking its body,
  when the owning adaptor instance has already been deallocated by the
  time the callback runs.
- **teardown-response-two-cases**: The teardown-response value MUST provide
  exactly two cases, "rejected promise" and "raised exception," and MUST be
  safe to share across concurrent contexts.
- **torn-down-dispatches-by-response**: Answering a teardown response MUST
  answer with a rejected promise for the "rejected promise" case, and MUST
  raise a script exception for the "raised exception" case; it MUST answer
  nothing when there is no active script context.
- **current-arguments-never-nil**: Reading the current call's arguments
  MUST answer an empty list, never nothing, when the active call's
  arguments cannot be read as a list of values or when there is no call in
  flight.
- **array-length-requires-true-array**: Reading an array-like value's
  length MUST require the value to be a genuine array before reading its
  length property, so an object literal carrying a numeric length property
  is never treated as a decodable array.
- **array-length-uses-exact-int32-conversion**: Reading an array-like
  value's length MUST use an exact, bounds-checked conversion of the
  numeric length value, and MUST NOT use a truncating conversion, so a
  length outside the representable range (such as the length of an array
  built with an index count of 4294967295) answers nothing instead of
  wrapping to a small, plausible-looking count.
- **array-length-bounds-decoding**: Reading an array-like value's length
  MUST log an error and answer nothing for any array whose length exceeds
  the maximum decodable array length (100,000).
- **raise-sets-context-exception**: Raising a script exception MUST set
  the active context's exception to a newly built error value and MUST
  always answer nothing.
- **raise-logs-when-error-construction-fails**: Raising a script exception
  MUST log an error when building a fresh error value from the message
  fails, and MUST still leave the call to answer nothing in that case, so
  the caller sees no throw beyond the log line.
- **resolved-promise-nil-becomes-undefined**: Building a resolved promise
  MUST resolve a missing value with the script engine's "undefined," and
  MUST NOT resolve it with "null."
- **resolved-promise-passes-non-nil-through**: Building a resolved promise
  MUST resolve any present value with that value unchanged.
- **rejected-promise-preserves-extension-supplied-reason**: Building a
  rejected promise from a caller-supplied reason MUST build it from the
  given value unchanged, preserving that reason's own error subclass,
  stack, and any custom properties.
- **rejected-promise-from-message-builds-a-fresh-error**: Building a
  rejected promise from a message MUST build a fresh error value from that
  message, delegating to the reason-based builder, and MUST answer nothing
  without producing any promise when that construction fails.
- **settled-promise-nil-resolves-undefined**: Building a settled promise
  MUST resolve with "undefined," via the resolved-promise builder, when the
  input value is missing.
- **settled-promise-passes-a-thenable-through-unchanged**: Building a
  settled promise MUST return the same value unchanged, not a wrapping
  promise, when the input value is a thenable, preserving its identity and
  whatever it later settles with.
- **settled-promise-resolves-a-non-thenable**: Building a settled promise
  MUST resolve with the input value itself, via the resolved-promise
  builder, when the input value is not a thenable.
- **settled-promise-rejects-on-a-throwing-then-getter**: Building a
  settled promise MUST reject with the error a throwing `then` property
  getter raised, rather than resolving with the raw object.
- **settled-promise-rejects-when-dispatch-is-unavailable**: Building a
  settled promise MUST reject with the shared dispatch-unavailable message
  when the context cannot answer whether the input value is thenable,
  rather than guessing "not a thenable" and resolving with the raw object.
- **call-outcome-three-cases**: The call-outcome value MUST provide
  exactly three cases: "returned" (carrying an optional value), "threw"
  (carrying a value), and "unavailable."
- **call-outcome-and-settlement-stay-context-confined**: The call-outcome
  value, the settlement value, and the then-lookup result MUST NOT be
  declared safe to share across concurrent contexts (unlike the
  teardown-response value), since each carries a value confined to the
  bridge's own execution context; every producer and consumer stays
  confined to that same context.
- **call-outcome-returned-nil-is-not-void-success**: A caller MUST treat
  "returned" carrying no value as "no value was read back" — distinct from
  both success and failure — never as "the callback returned nothing,"
  which is "returned" holding a value for "undefined."
- **call-refuses-when-trampoline-cannot-be-installed**: Calling back into
  an extension's callback MUST answer "unavailable," and MUST NOT invoke
  the callback directly, when the callback has no active context or the
  dispatch trampoline's call helper cannot be installed in that context.
- **call-normalizes-nullish-this-arg**: Calling back into an extension's
  callback MUST bind the call's receiver as the script engine's
  "undefined" when the caller passes nothing.
- **call-catches-the-callbacks-own-throw**: Calling back into an
  extension's callback MUST answer "threw" carrying the reason — never let
  the exception reach the host's own exception handling — when a call
  through this bridge's own trampoline reports failure.
- **outcome-refuses-a-malformed-trampoline-record**: Reading a dispatch
  outcome MUST log an error and answer "unavailable" when the settled
  value is not an object, or its success flag is missing or not a boolean.
- **outcome-requires-error-property-on-failure**: Reading a dispatch
  outcome MUST answer "unavailable," not "threw," when the success flag is
  false but the record's error property is absent.
- **can-dispatch-checks-both-helpers-present**: Checking whether dispatch
  is possible MUST answer true only when both the call helper and the
  then-lookup helper are present and neither "undefined" nor "null" on the
  trampoline; it MUST NOT invoke either to verify callability.
- **can-dispatch-installs-the-trampoline-as-a-side-effect**: Checking
  whether dispatch is possible MUST evaluate and cache the trampoline in
  the active context if it has not already been installed, so a later
  dispatch in the same context finds it cached.
- **dispatch-unavailable-message-is-shared-verbatim**: The
  dispatch-unavailable message MUST produce the identical message text
  used by every refusal on the dispatch-unavailable path, naming the
  context by its resolved name.
- **observe-rejection-leaves-value-unchanged**: Observing a thenable's
  rejection MUST attach the handler to a promise derived from the value's
  `then` member, and MUST leave the input value itself as what the caller
  keeps and hands back to the extension; the derived promise MUST be
  discarded.
- **observe-rejection-only-attaches-to-a-thenable**: Observing a thenable's
  rejection MUST answer false, and attach nothing, when the input value is
  not a thenable, when reading its `then` member throws, or when calling
  `then` throws.
- **observe-rejection-reads-the-rejection-reason-off-the-actual-arguments**:
  The rejection handler observing a thenable's rejection builds MUST read
  its argument from the current call's arguments, not from a declared
  formal parameter.
- **settlement-non-thenable-is-fulfilled-with-itself**: Reading a value's
  settlement MUST answer "fulfilled" with that value immediately when the
  value is not a thenable.
- **settlement-resumes-the-continuation-exactly-once**: Reading a value's
  settlement MUST resume its underlying suspended call at most once even
  when the extension's own `then` implementation calls both handlers,
  calls one handler more than once, or throws after a handler already
  fired; the first settlement by call order MUST win.
- **settlement-does-not-time-out**: Reading a value's settlement MUST
  impose no timeout on a thenable that never settles, matching upstream VS
  Code's own behavior for a promise given to an API such as
  `showQuickPick` that never resolves.
- **settlement-handlers-capture-no-live-value**: Neither the fulfillment
  nor the rejection handler passed to the extension's `then` MUST capture
  a script value directly; each MUST read its argument from the current
  call's arguments or mint a fresh "undefined" from the active context at
  call time.
- **settlement-missing-argument-fulfills-as-undefined**: A handler invoked
  with no argument MUST settle the read as a value holding "undefined,"
  not as "unavailable" and not as an absent result.
- **settlement-unavailable-when-context-cannot-mint-undefined**: Reading a
  value's settlement MUST answer "unavailable" before attaching any
  handler, when the context can no longer produce a value for "undefined."
- **settlement-getter-throw-becomes-rejected**: Reading a value's
  settlement MUST answer "rejected" with the thrown value, and MUST NOT
  let the exception reach the context's own exception handling, when
  reading the value's `then` member throws.
- **then-function-distinguishes-four-outcomes**: Looking up a value's
  `then` function MUST distinguish "not thenable" (no callable `then`),
  "thenable" (carrying a value), "threw" (carrying a value, when reading
  `then` raised), and "unavailable" (the lookup itself could not be
  performed); callers MUST NOT conflate "unavailable" with "not thenable."
- **helper-source-is-evaluated-at-most-once-per-context**: Installing the
  shared trampoline helper MUST evaluate its source at most once per
  context, caching the result under a non-enumerable, non-writable,
  non-configurable global name, and reading the cached value back on
  every later call.
- **trampoline-object-is-frozen-before-caching**: The trampoline object
  MUST be frozen before it is cached, so a member-level reassignment is
  refused in addition to a whole-binding reassignment.
- **sharedHelper-adopts-whatever-object-it-finds**: Installing the shared
  trampoline helper MUST adopt whatever object already exists under its
  cached global name rather than verifying its provenance, for a context
  reached before anything has called the trampoline installer.
- **install-trampoline-is-not-fatal-to-activation**: Installing the
  trampoline MUST answer nothing, through the shared-helper installer's own
  logging, rather than failing the caller, when the eager install fails,
  leaving the lazy path through the call and dispatch-check operations as
  the fallback.
- **helper-function-rejects-nullish-members**: Reading a named helper
  function from the trampoline MUST answer nothing when the named member
  on the trampoline is "undefined" or "null," in addition to when the
  trampoline itself could not be installed.
- **context-name-fallback**: Resolving a context's name MUST answer
  `"<unnamed>"` when the context has no name of its own.
- **disposable-idempotent-by-construction**: Building a disposable MUST
  return an object whose dispose operation calls the supplied cleanup
  action on its first invocation and MUST do nothing on every later
  invocation, tracked by a disposed flag captured in the returned
  callback's own closure.
- **sub-namespace-factory-evaluated-once-per-context**: Installing the
  sub-namespace factory MUST evaluate its source at most once per context,
  matching the shared trampoline helper's caching pattern under its own
  fixed global name.
- **sub-namespace-unimplemented-member-throws-named-error**: A stub built
  by the sub-namespace builder MUST throw a not-implemented error — an
  error named "NotImplementedError" with a member-path property equal to
  the sub-namespace's path joined with the key — from its property-read
  trap, for any key that is neither an implemented member nor one of the
  shim's probe keys.
- **sub-namespace-probe-keys-answer-quietly**: The property-read trap MUST
  answer a quiet feature-detection value, never throw, for every key in
  the probe-key list (the standard object-prototype own names plus `then`,
  `toJSON`, `__esModule`, `default`, `inspect`, `prototype`, `nodeType`,
  and `$$typeof`), even when that key is not implemented.
- **sub-namespace-is-read-only**: The property-write and property-delete
  traps MUST both throw a type error naming the sub-namespace's path and
  the key, and MUST NOT allow any assignment or deletion to succeed
  silently.
- **sub-namespace-table-has-no-inherited-prototype**: The object holding
  the sub-namespace's implemented members MUST be built with no inherited
  prototype, so standard object-prototype member names are never already
  present in it before any real member is added.
- **sub-namespace-records-misses-only-when-a-recorder-is-supplied**: The
  property-read trap's throwing branch MUST call the miss recorder with
  the full member path when a miss recorder is supplied, and MUST NOT call
  it — while still throwing the same not-implemented error — when none is
  supplied.
- **sub-namespace-records-probes-only-from-has-and-descriptor**: The probe
  recorder MUST be invoked only from the property-existence and
  descriptor-lookup traps' negative branches, and MUST NOT be invoked from
  a property read of a probe-key name or from a symbol key.
- **sub-namespace-swallows-a-throwing-recorder**: A throw from the miss
  recorder or the probe recorder itself MUST be caught and discarded, and
  MUST NOT replace the not-implemented error the extension is entitled to
  see, or turn a boolean-returning trap into an uncaught throw.
- **sub-namespace-returns-nil-when-factory-or-table-unavailable**:
  Building a sub-namespace MUST answer nothing when the factory could not
  be installed in the active context, or when the context cannot produce
  an object with no inherited prototype to hold the sub-namespace's
  members.
- **logger-conformance**: The bridge MUST participate in the host's
  logging convention, exposing a logger as the destination for every
  failure that has no extension-facing channel.
- **confined-value-box-never-crosses-isolation**: The confined-value box
  MUST only ever carry a value already confined to one execution context
  across a signature that requires concurrency safety, never to move a
  value between execution contexts.
- **bridge-value-box-is-a-named-specialization**: The bridge-value box
  MUST be a named specialization of the confined-value box, not a second,
  independent box declaration.
- **promise-settlement-box-carries-a-fixed-pair**: The promise-settlement
  box MUST hold exactly one promise's resolve and reject values, read back
  only by name, and MUST NOT double as a general-purpose value box.

## Appearance

Not applicable — this is the extension host's shared `vscode.*` member/promise/dispatch ceremony, not a visual component.

## States

Not applicable — this is the extension host's shared `vscode.*` member/promise/dispatch ceremony, not a visual component. The bridge itself holds no state; the lifecycle-shaped behavior that exists (an owner already torn down, a trampoline not yet installed, a settlement not yet resolved) is covered under Behavioral Requirements.

## Accessibility

Not applicable — this is the extension host's shared `vscode.*` member/promise/dispatch ceremony, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
| --- | --- | --- | --- |
| vscodeapi-001 | member-captures-owner-weakly, member-answers-teardown-response-when-owner-gone, torn-down-dispatches-by-response | A member built with a "raised exception" teardown response is called after its owning adaptor instance has been deallocated | The callback answers the teardown response by raising a script exception; the body is never invoked |
| vscodeapi-002 | array-length-uses-exact-int32-conversion, array-length-bounds-decoding | Reading the length of a real array whose index count is 4294967295 (exceeding the representable range) | Answers nothing via the exact-conversion guard, never reaching a count built from a wrapped-around value |
| vscodeapi-003 | array-length-bounds-decoding | Reading the length of an array of exactly 100,001 elements | Logs an error naming the count and answers nothing, since the count exceeds the maximum decodable array length (100,000) |
| vscodeapi-004 | raise-sets-context-exception | Raising the exception `"boom"` on a healthy context | The context's exception is set to an error value whose message is `"boom"`; the operation answers nothing |
| vscodeapi-005 | resolved-promise-nil-becomes-undefined | Building a resolved promise with no value | Answers a promise already resolved with "undefined," not "null" — an extension's `result === undefined` check passes |
| vscodeapi-006 | rejected-promise-preserves-extension-supplied-reason | Building a rejected promise from an extension-thrown error subclass carrying custom properties | The returned promise rejects with that exact value — same subclass, same stack, same custom properties, not a paraphrase |
| vscodeapi-007 | settled-promise-resolves-a-non-thenable, settlement-non-thenable-is-fulfilled-with-itself | Reading the settlement of a plain array `['alpha', 'beta']` | Answers "fulfilled" with a 2-element array, `'alpha'` at index 0 and `'beta'` at index 1 |
| vscodeapi-008 | settlement-resumes-the-continuation-exactly-once | A thenable whose `then` calls its fulfillment handler with `['first-win']`, then afterward calls its rejection handler with an error | Reading the settlement answers "fulfilled" with `['first-win']`; the later rejection call is a no-op and does not fail the call |
| vscodeapi-009 | settled-promise-rejects-on-a-throwing-then-getter, settlement-getter-throw-becomes-rejected | A value whose `then` property getter throws an error with message `'getter-boom'` | Reading the settlement answers "rejected" with message `'getter-boom'`; the exception does not reach the context's own exception handling |
| vscodeapi-010 | settlement-unavailable-when-context-cannot-mint-undefined, then-function-distinguishes-four-outcomes | Reading the settlement in a context whose trampoline's then-lookup helper cannot answer | Answers "unavailable"; the same array read in an untouched context still answers "fulfilled" |
| vscodeapi-011 | disposable-idempotent-by-construction | A disposable's dispose operation is called twice | The cleanup action runs exactly once; no exception is raised |
| vscodeapi-012 | disposable-idempotent-by-construction | A disposable's dispose operation is called once | The cleanup action runs exactly once |
| vscodeapi-013 | sub-namespace-unimplemented-member-throws-named-error | Reading an unimplemented key off a sub-namespace built with an empty member table | Throws an error named "NotImplementedError" whose member-path names the sub-namespace's path and the key |
| vscodeapi-014 | sub-namespace-probe-keys-answer-quietly | Reading a probe-key member (such as `then`) on an otherwise-unimplemented namespace | Answers a quiet feature-detection value without throwing |
| vscodeapi-015 | sub-namespace-records-misses-only-when-a-recorder-is-supplied | A sub-namespace built with a miss recorder supplied, then an unimplemented member is read | The miss recorder is called once with the full member path, in addition to the thrown not-implemented error |
| vscodeapi-016 | sub-namespace-swallows-a-throwing-recorder | A sub-namespace built with a miss recorder that itself throws, then an unimplemented member is read | The extension still sees the same not-implemented error; the recorder's own throw is discarded |
| vscodeapi-017 | sub-namespace-is-read-only | Assigning to, or deleting, a member on a sub-namespace stub | Throws a type error naming the sub-namespace's path and the key; the assignment or deletion does not succeed |
| vscodeapi-018 | call-refuses-when-trampoline-cannot-be-installed | Calling back into a callback that has no active context, with no receiver and no arguments | Answers "unavailable" without invoking the callback |
| vscodeapi-019 | outcome-refuses-a-malformed-trampoline-record | Reading a dispatch outcome given a settled value that is not an object (a bare number) | Logs an error and answers "unavailable," not "threw" and not "returned" |

## Edge Cases

- **Null/empty input**: Reading the current call's arguments with no call in flight (the active arguments answer nothing, or something that is not a list of values) answers an empty list, never nothing (MUST, per **current-arguments-never-nil**).
- **Null/empty input**: `{length: -1}` (an object literal, not a real array) is rejected before its length is ever read, because it fails the genuine-array check (MUST, per **array-length-requires-true-array**).
- **Boundary values**: an array reporting exactly 100,000 elements is accepted; 100,001 is refused with a logged error (MUST, per **array-length-bounds-decoding**).
- **Boundary values**: an array whose length cannot be represented in the exact-conversion range (such as one built with an index count of 4294967295) is refused by that guard rather than wrapped to a small, plausible-looking count (MUST, per **array-length-uses-exact-int32-conversion**).
- **Concurrent access**: every operation of the bridge is confined to its execution context with no additional locking; the script engine calls every callback this concept builds on the thread that made the call, which for this host is always that same confined context, so there is no data race for this recipe to define behavior for (fact).
- **Concurrent access**: a `then` implementation that calls both its fulfillment and rejection handlers, or calls one of them twice, has its second and later calls resumed at most once by the once-only guard inside settlement reading; the first settlement by call order wins (MUST, per **settlement-resumes-the-continuation-exactly-once**).
- **Error states**: a context whose dispatch trampoline could not be installed answers "unavailable" from the call, dispatch-check, and settlement/then-lookup operations — never a fabricated success or fulfillment (MUST, per **call-refuses-when-trampoline-cannot-be-installed**, **settlement-unavailable-when-context-cannot-mint-undefined**).
- **Error states**: a `then` getter, or a `then` call, that throws rejects rather than letting the exception reach the context's own exception handling and be misattributed to unrelated host activity (MUST, per **settled-promise-rejects-on-a-throwing-then-getter**, **settlement-getter-throw-becomes-rejected**).
- **Error states**: a malformed trampoline record (missing or non-boolean success flag) is treated as "unavailable," never silently coerced into a success or a thrown value (MUST, per **outcome-refuses-a-malformed-trampoline-record**).
- **Error states**: a script call stack already exhausted by extension code raises a stack-overflow error while entering either trampoline's source itself, before either script's own error handling executes; that exception reaches the host's exception handling like any other uncaught extension exception, because a context in that state is already failing the extension's own next frame regardless (fact — the trampoline sources document this as accepted, not as something this concept defends against).
- **Cancellation or timeout**: reading a value's settlement imposes no timeout and offers no cancellation path; a thenable that never settles leaves its suspended call, and the two handlers capturing it, permanently pending (fact, per **settlement-does-not-time-out**).
- **Missing or unreachable resource**: a script object already installed under either trampoline's cached global name before this concept's own install runs is adopted as-is; reading a dispatch outcome and the sub-namespace stub's traps can only refuse a malformed *answer* from such an object, never verify its provenance — an impostor that throws instead of answering lands its exception in the calling extension's own pending-exception state, confusing that one extension's activation report and no other extension's (fact, per **sharedHelper-adopts-whatever-object-it-finds**).

## Configuration

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `path` | a string | none (required) | The namespace member's dotted path; used only in log lines, dispatch-unavailable/teardown messages, and the not-implemented error's member-path — never read back to decide behavior. |
| `owner` | any owning adaptor instance | none (required) | The adaptor instance a member's body runs against; captured weakly when the member is installed. |
| `whenTornDown` | a teardown-response value | none (required) | Chooses whether a call after the owner's deallocation raises an exception or rejects a promise. |
| `members` | a name-to-value mapping | empty | The implemented members of a sub-namespace; every other key throws a not-implemented error. |
| `recordMiss` | an optional callback taking a string | none | Optional hook invoked with an unimplemented member's path, in addition to the thrown error. |
| `recordProbe` | an optional callback taking a string | none | Optional hook invoked with a quietly-missed member's path from the existence/descriptor traps. |
| `maximumDecodableArrayLength` | an integer constant | 100,000 | The hard ceiling the array-length reader enforces on any array-like value's decoded length; not overridable per call. |

## Deep Linking

Not applicable: this concept defines no URL, route, or navigable destination — it is in-process script-bridging ceremony only.

## Localization

Every user-facing string this concept produces is a hardcoded English literal; there is no localization key or lookup anywhere in it.

| String | Context |
| --- | --- |
| dispatch-unavailable message | shown to an extension, via a raised exception or a rejected promise, when the command/promise dispatch trampoline cannot be installed in its context |
| not-implemented error message | thrown to an extension reading an unimplemented `vscode.*` member, naming the member's path |
| read-only assignment/deletion type-error messages | thrown to an extension attempting to assign to or delete a member of a sub-namespace stub |
| trampoline/factory install-failure log lines | host-only diagnostic text, never seen by the extension itself |
| malformed-record and oversized-array log lines | host-only diagnostic text, never seen by the extension itself |

## Accessibility Options

Not applicable: this concept renders nothing and responds to no system accessibility setting (Reduce Motion, larger text, VoiceOver, or otherwise).

## Feature Flags

Not applicable: this concept contains no feature-flag key or conditional gate; every code path it defines is unconditionally reachable.

## Analytics

Not applicable: this concept emits no analytics or telemetry event; its only observability channel is the diagnostic logging covered under Logging.

## Privacy

- **Data collected**: none of its own; the bridge holds no stored state and collects nothing about the user. It transiently handles values an extension itself supplies (its callbacks, its thenables, its error objects) for the duration of one call.
- **Storage**: none — the bridge is a stateless collection of operations with no persisted or cached data of its own; the trampoline objects it caches on the global scope live only for the lifetime of their script context.
- **Transmission**: none — everything happens in-process inside the script engine; nothing here makes a network call or writes to disk.
- **Retention**: an extension-supplied value is retained only as long as the call stack that produced it, or (for reading a settlement) until the thenable it is watching settles or its script context is torn down; installing a member's weak capture of its owner ensures a torn-down adaptor is not kept alive by a still-reachable script callback.

## Logging

Subsystem: matches the host's logging subsystem | Category: the bridge's own category

| Event | Level | Trigger |
| --- | --- | --- |
| oversized-array refusal | error | reading an array-like value's length refuses one whose length exceeds the maximum decodable array length |
| error-construction failure | error | raising an exception finds that building a fresh error value for the given message failed |
| malformed trampoline record | error | reading a dispatch outcome finds the settled dispatch value is not an object, or its success flag is missing or not a boolean |
| trampoline install failure | error | installing the shared trampoline helper cannot evaluate or cache its source in a context |
| sub-namespace factory install failure | error | installing the sub-namespace factory cannot evaluate or cache its source in a context |

## Platform Notes

- **SwiftUI**: not applicable — `VSCodeAPI.swift` imports only Foundation, JavaScriptCore, OSLog, and this framework's own `Loggable`; nothing here renders a view or depends on SwiftUI.
- **AppKit / UIKit**: this is the source. `VSCodeAPI.swift` lives in `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/`, part of the macOS-only `AgenticToolkitMacOS` module per `project.yml`; it is `@MainActor` because `JSValue` is not `Sendable` and JavaScriptCore always calls an installed block on the thread that made the call, which for this host is the main actor driven by AppKit's own run loop. `VSCodeAPI` is a caseless `enum` (no stored state), and every "confined execution context" reference above is JavaScriptCore's guarantee that a `@convention(block) () -> JSValue?` closure it invokes runs on the same thread as `JSContext.current()`; the "assert confinement" requirement is implemented with `MainActor.assumeIsolated { ... }` inside that block, since the block's own declared type cannot itself carry `@MainActor`. `JSValue`/`JSContext` are the "script value"/"active context" of the normative text throughout. The three concurrency-safety wrapper types are `UncheckedSendableBox` (the confined-value box; an `@unchecked Sendable` generic wrapper), `UncheckedJSValueBox` (the bridge-value box; the type alias `UncheckedSendableBox<JSValue?>`), and `PromiseSettlementBox` (the promise-settlement box, holding a promise's `resolve`/`reject` `JSValue`s by name). `CallOutcome`, `Settlement`, and `ThenLookup` are plain (non-`Sendable`) Swift enums; only `TeardownResponse` is `Sendable`. No iOS target packages this file today.
- **Compose**: model the bridge as a Kotlin `object` (or a set of top-level functions) confined to the main dispatcher, since there is no per-instance state to gate; the script-value/script-context types become whatever the chosen embeddable JS engine binding uses, and the evaluate-once-and-cache-under-a-global trampoline pattern ports directly, since it depends only on the engine's own global-object and `Proxy` support, which most JVM-embeddable JS engines provide.
- **React/Web**: this component's own counterpart needs no cross-boundary bridging ceremony at all, since a real VS Code extension already runs as JavaScript inside the same runtime as the host (VS Code's own `vscode.d.ts` and extension host process fill this role); a from-scratch web port only needs the once-only-settlement guard around a native `Promise`'s `resolve`/`reject` and the `Proxy`-based stub namespace, both of which are already plain JavaScript in the two trampoline sources and need no translation.
- **WinUI 3**: model the bridge as a static class confined to a captured `DispatcherQueue` — WinUI 3's nearest equivalent to the main-actor confinement above — asserting `DispatcherQueue.HasThreadAccess` or marshaling via `TryEnqueue` at every entry point, since nothing catches a wrong-thread call at compile time the way Swift's actor isolation does. The script-context/script-value types become the chosen embeddable engine's types (ClearScript's `ScriptEngine`/`ScriptObject`, or Jint's `Engine`/`JsValue`); the promise builders and settlement reader become helpers around `TaskCompletionSource<object?>`, guarded by `Interlocked.CompareExchange` in place of the once-only continuation box, since .NET has no first-class `Promise` type and no leaked-continuation diagnostic to inherit. The frozen-trampoline-object pattern ports if the engine's script realm supports freezing a host-exposed object; the proxy-based sub-namespace stub has no built-in .NET equivalent and must be hand-rolled over `DynamicObject`/`IDynamicMetaObjectProvider` (ClearScript) or a custom `ObjectInstance` override (Jint) to reproduce the get/has/set/deleteProperty/ownKeys/getOwnPropertyDescriptor trap set this concept defines directly in JavaScript.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/VSCodeAPI.swift` |

## Design Decisions

- **Decision**: Calling back into an extension's callback never falls back to invoking it directly when the trampoline cannot be installed.
  **Rationale**: an uncaught throw from a direct call is exactly what routing every call through the script trampoline exists to keep out of the host's own exception handling; a direct-call fallback would reopen that path for precisely the contexts where the trampoline is least trustworthy.
  **Approved**: pending

- **Decision**: Installing either trampoline helper adopts whatever object already exists under its cached global name rather than verifying its provenance.
  **Rationale**: a script object cannot prove its provenance to the script engine, and freezing the object after installation cannot retroactively make an already-adopted impostor genuine. The blast radius is bounded to the pre-empting extension's own context: reading a dispatch outcome refuses a malformed *returned* record from any caller, and an impostor that throws instead lands in that same extension's own pending-exception state, never another extension's.
  **Approved**: pending

- **Decision**: Reading a value's settlement imposes no timeout on an unsettled thenable.
  **Rationale**: upstream VS Code does not settle either, and answering after some fixed delay would invent user-visible-wrong behavior (an extension told a picker was dismissed that the user never saw). The cost — one leaked continuation and two capturing handlers per un-settling thenable — is confined to the extension whose own thenable never resolves.
  **Approved**: pending

- **Decision** (Swift/AppKit implementation): The fulfillment/rejection handlers in settlement reading, and the rejection handler in rejection observation, capture no script value, reading their argument from the current call's arguments or minting a fresh "undefined" from the active context at call time instead.
  **Rationale**: a `JSValue` retains its `JSContext`, so a block capturing one and exported to JavaScript creates a retain cycle between the block and the context; the leak would then be the whole context rather than one continuation.
  **Approved**: pending

- **Decision**: "Returned" carrying no value is a distinct, narrow case rather than being folded into "the callback returned undefined."
  **Rationale**: a callback that genuinely returns nothing answers a value holding "undefined," not an absent result; an absent result here means the bridge itself declined to answer. Conflating the two would let a caller resolve an extension's promise with "undefined" — the same answer a successful void command produces — when the true situation was a dispatch failure.
  **Approved**: pending

- **Decision** (Swift implementation): The confined-value box is one generic type rather than several private, purpose-built box structs.
  **Rationale**: several unrelated shared-library signatures independently require concurrency safety for values (script values and closures over them) this module cannot conform, because the script-value type is owned by the script engine, not by this module. One declaration replaces what would otherwise be several private structs under different names, each a copy of another.
  **Approved**: pending

- **Decision** (Swift implementation): The bridge, the call-outcome value, the settlement value, and the then-lookup result carry no concurrency-safety declaration beyond the teardown-response value's explicit one.
  **Rationale**: every value in play (the script value, the script context) is inherently confined to one execution context by nature, and every producer and consumer is already confined to the bridge's own execution context; adding a declaration would either be a false promise or require boxing types that have no reason to leave that context.
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

| Version | Date | Author | Summary |
|---|---|---|---|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/extensions/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation |
