---
id: d5812249-f235-43df-9cd7-504220da1a7d
title: Scripting Support
domain: agentictoolkit://cookbook/system/scripting
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Three primitives that add AppleScript execution and Cocoa Scripting command
  support to a macOS app — a script runner that returns a structured result, a
  command base that serializes command handling onto one execution context, and
  a helper that builds a scripting locator for an application-level element.
platforms:
- swift
- macos
tags:
- scripting
- applescript
- cocoa-scripting
depends-on:
- agenticdevelopercookbook://guidelines/implementing/concurrency/concurrency
- agenticdevelopercookbook://principles/fail-fast
related: []
references:
- packages/apple/AgenticToolkit/macOS/Scripting/AppleScriptRunner.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Scripting/MainActorScriptCommand.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/SystemIntegration/ScriptingReExports.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Scripting/AppleScriptRunnerTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Scripting/MainActorScriptCommandTests.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Scripting Support

## Overview

Three small, independent primitives that give an app AppleScript and
scripting-dictionary support without each app-shell reimplementing the same
cross-context bridging boilerplate. A script-running operation compiles and
executes an AppleScript source string and returns a structured result instead
of an unrepresentable failure. A command base is what a scriptable command
handler inherits from so its command-handling override runs on a single,
serialized execution context without each handler re-deriving that bridge by
hand. An element-locator helper builds the scripting locator a scriptable
wrapper returns for an element that hangs directly off the application (a
pane, tab, project window, or terminal session). All three live in one
scripting module and are re-exported through the toolkit's feature layer so
existing call sites keep working. The script-running operation depends only
on the platform's foundational, UI-free layer; the command base and the
element-locator helper additionally depend on the platform's UI framework.

## Behavioral Requirements

- **script-compilation-and-execution**: The script-running operation MUST compile the given AppleScript source string and, when compilation succeeds, MUST execute it.
- **compile-failure-result**: The script-running operation MUST return a compile-failed result when compiling the given source string fails.
- **runtime-failure-result**: The script-running operation MUST return a runtime-failed result carrying a message and a number when execution produces a non-empty error description, with the message taken from that description's error-message entry and the number from its error-number entry.
- **runtime-failure-fallback-values**: The script-running operation MUST substitute the literal string "unknown error" for the message when the error description has no string value for its error-message entry, and MUST substitute `0` for the number when the description has no integer value for its error-number entry.
- **success-result-value**: The script-running operation MUST return a success result carrying the executed script's own textual result value when the error description is empty.
- **success-value-nilable**: Callers MUST treat the textual value a success result carries as possibly absent, since the executed script's own result is not guaranteed to produce a textual value for every script.
- **result-value-equality**: The result type MUST support equality comparison, comparing the success, compile-failed, and runtime-failed cases (and their carried values) by value.
- **runner-caller-thread**: The script-running operation MUST execute synchronously on the thread it is called from and MUST NOT dispatch the compile-or-execute work to any other thread or queue internally.
- **caller-main-thread-marshaling**: Callers SHOULD invoke the script-running operation on the platform's main thread on system versions where the underlying scripting engine requires it, per the documented guidance that the engine requires the main thread on some system versions and that a caller running on a background execution context should marshal to the main thread if needed.
- **command-default-behavior**: The command base's default command-handling behavior, when a subclass does not override it, MUST return an absent value.
- **command-runs-on-serialized-context**: A subclass's command-handling override MUST run on the base's single serialized execution context, since the override point itself is isolated to that context.
- **command-default-implementation-bridges-context**: The command base's default-implementation operation MUST invoke the command-handling override from inside a bridge onto that same serialized execution context.
- **command-result-propagation**: The command base's default-implementation operation MUST return exactly the value produced by that invocation of the command-handling override, with no transformation.
- **command-return-type-freedom**: A subclass's command-handling override MAY return any value assignable to the command base's declared open result type, including an absent value, since the default-implementation operation's own contract returns that same open result type.
- **element-specifier-result**: The element-locator helper MUST return a locator built from the application's own scripting class description as the container class description, the given key, and the result of calling the given unique-id closure, when the application's own class description resolves to a scripting class description.
- **element-specifier-nil-fallback**: The element-locator helper MUST return an absent value when the application's own class description does not resolve to a scripting class description.
- **element-specifier-runs-on-serialized-context**: The element-locator helper MUST perform the application's-class-description read, the unique-id call, and the locator construction from inside a bridge onto the platform's serialized main execution context.
- **element-specifier-no-container-specifier**: The element-locator helper MUST pass an absent container locator, since every element it addresses hangs directly off the application.

## Appearance

Not applicable — this is a scripting-bridge utility, not a visual component.

## States

Not applicable — this is a scripting-bridge utility, not a visual component.

## Accessibility

Not applicable — this is a scripting-bridge utility, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|---------------|-------|----------|
| scripting-001 | script-compilation-and-execution, success-result-value | A source string that returns the text "hello" | A success result carrying "hello" |
| scripting-002 | success-result-value | A source string that returns the number 42 | A success result carrying "42" — the scripting engine stringifies the numeric result |
| scripting-003 | success-value-nilable | An empty source string | Compiles and executes; returns a success result carrying an absent value |
| scripting-004 | runtime-failure-result | A source string that raises an error with message "boom" and number -1728 | A runtime-failed result whose message contains "boom" and whose number equals -1728 |
| scripting-005 | runtime-failure-fallback-values | An error description with no message or number entries | message equals "unknown error", number equals `0` |
| scripting-006 | compile-failure-result | A source string for which compilation itself fails | A compile-failed result (this path is documented as unreachable in practice by the reference test suite's own comment; the case exists purely as a defensive catch — see Design Decisions) |
| scripting-007 | result-value-equality | Two success results, each carrying the same textual value | They compare equal |
| scripting-008 | runner-caller-thread | The script-running operation invoked from a background execution context | Executes and returns synchronously on that same background context, with no internal hop to another thread or queue |
| scripting-009 | caller-main-thread-marshaling | A background-context caller invokes the script-running operation without marshaling to the main thread, on a system version where the engine requires it | Documented as the caller's own responsibility; the operation performs no thread check or automatic marshaling |
| scripting-010 | command-default-behavior | A command base instance with no subclass override, asked to perform its default implementation | Returns an absent value |
| scripting-011 | command-result-propagation, command-return-type-freedom | A subclass override that returns the text "answer" | The default-implementation operation returns "answer" |
| scripting-012 | command-return-type-freedom | A subclass override that returns the number 42 | The default-implementation operation returns 42 |
| scripting-013 | command-result-propagation | A subclass override that returns an absent value | The default-implementation operation returns an absent value |
| scripting-014 | command-runs-on-serialized-context, command-default-implementation-bridges-context | A subclass override that records whether it observed the main thread, invoked through the default-implementation operation from the main thread | The override observes the main thread as true |
| scripting-016 | element-specifier-result, element-specifier-no-container-specifier, element-specifier-runs-on-serialized-context | The element-locator helper called with key "panes" and a unique-id closure returning "some-uuid", while the application's own class description resolves to a scripting class description | Returns a locator whose key is "panes", whose unique id is "some-uuid", and whose container locator is absent |
| scripting-017 | element-specifier-nil-fallback | The element-locator helper called while the application's own class description does not resolve to a scripting class description | Returns an absent value |

A prior vector verified that a command-base instance handed to the scripting
bridge's arbitrary-thread event dispatch compiles with no concurrency-safety
diagnostic under strict concurrency checking. That guarantee is a compile-time
property of the command base's declared concurrency escape hatch (see Platform Notes and Design Decisions), not an independently
observable input/output behavior, so it is not restated as a numbered vector
here.

## Edge Cases

- **Empty AppleScript source** (null/empty input): the script-running operation MUST compile and execute an empty source string successfully, returning a success result carrying an absent value — the underlying scripting engine treats empty source as a valid, no-op script rather than a compile failure.
- **Script produces no textual result** (boundary of success-result-value): when the executed script's own result value is absent, the script-running operation MUST still return a success result carrying an absent value rather than promoting the absence of a value to a compile-failed or runtime-failed result.
- **Extreme or unusual error numbers** (boundary values): AppleScript/OSA error numbers span the full range of a signed integer, including negative codes (e.g. -1728); the script-running operation MUST pass the error description's number through unmodified, with no range validation or clamping.
- **Concurrent calls to the script-running operation** (concurrent access): each call constructs and owns its own scripting-engine instance with no state shared internally, so concurrent calls from independent threads MUST NOT corrupt one another's result; the operation's own documented guidance nonetheless notes that the underlying scripting engine may require all such calls to land on the main thread on some system versions, a requirement the operation does not enforce (see caller-main-thread-marshaling).
- **Concurrent command-handling invocations on one command-base instance** (concurrent access): because the command-handling override is isolated to a single serialized execution context and the scripting bridge always dispatches command handlers on the main thread, invocations MUST be serialized by that context's own executor; the component adds no further locking because none is needed.
- **Default-implementation operation invoked off the main thread** (error state, outside the stated contract): the bridge onto the serialized execution context MUST trap — a fatal runtime error, not a catchable error or a returned value — because the safety of that call rests on the documented assumption that the scripting bridge always invokes command handlers on the main thread when the script suite is registered with the host application, not on a runtime-checked precondition.
- **The application's own class description is not a scripting class description** (error/unavailable-dependency state): the element-locator helper MUST return an absent value rather than trapping or constructing a malformed locator.
- **Compile failure path** (error state): a source string for which compilation itself fails MUST route to a compile-failed result; the reference test suite's own comment documents this path as unreachable in practice, since the underlying scripting engine accepts any string and defers all parse/tokenizer errors to execution — the case exists purely as a defensive catch against a documented-nullable construction step, not because any known input currently exercises it.
- **Offline / disconnected state**: Not applicable — none of the three primitives perform network I/O. An AppleScript run through the script-running operation may itself address another application or a network resource, but any such failure surfaces through that script's own error/return value and is reported through the ordinary runtime-failed/success path, not through a distinct offline case in this component.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `source` | text | none (required) | The AppleScript source text the script-running operation compiles and executes. |
| `key` | text | none (required) | The application element key declared in the host app's scripting definition (e.g. `panes`, `projectTabs`, `projectWindows`, `terminalSessions`), passed to the element-locator helper. |
| `uniqueID` | a closure returning text, called on the serialized main execution context | none (required) | Closure the element-locator helper calls, on that context, to obtain the addressed element's unique id string. |
| command-handler override | a subclass override returning an open result value, isolated to the serialized main execution context | returns an absent value | The subclass hook a caller overrides on the command base to implement one scriptable command; the base class's own implementation is the default when unoverridden. |

## Deep Linking

Not applicable: none of the three primitives register a URL scheme or route. The scripting bridge's own event-based command dispatch is a distinct, non-URL addressing mechanism, and it is specified in full above under Behavioral Requirements.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| `scripting.unknownError` | unknown error | The script-running operation's fallback substitution for the message when the error description carries no error-message entry (see runtime-failure-fallback-values) |

The key above is synthetic, for this table only: the string is a raw literal
returned directly to callers, not looked up from any string table, resource
bundle, or locale-aware API. This is the only hardcoded, user/caller-visible
string across the three given primitives, and it is a plain fact about the
current implementation, not a gap — there is no localization mechanism in
this component at all.

## Accessibility Options

Not applicable: none of the three primitives render a visual or interactive surface, so there is no contrast, motion, font-size, or other accessibility-preference surface for this recipe to define.

## Feature Flags

Not applicable: no feature-flag check (e.g. a remote-config lookup or a hand-rolled flag check) appears in any of the three given primitives.

## Analytics

Not applicable: none of the three given primitives emit an analytics/telemetry event or call an analytics client.

## Privacy

Not applicable: none of the three given primitives collect, store, or transmit any data. The script-running operation passes a caller-supplied AppleScript source string through to the underlying scripting engine and returns its result or error to the caller without persisting, logging, or transmitting either; the element-locator helper passes a caller-supplied key and unique-id value into the locator it constructs, with the same no-persistence, no-transmission characteristics.

## Logging

Not applicable: none of the three given primitives call a logger or any other diagnostic-output API.

## Platform Notes

- **SwiftUI**: A SwiftUI app still reaches Cocoa Scripting through AppKit, not through any SwiftUI-specific API — `NSApplication`, `NSScriptCommand`, and `NSScriptSuiteRegistry` sit underneath a SwiftUI `App`/`Scene` lifecycle exactly as they do under an `NSApplicationDelegate`-based app. `MainActorScriptCommand` and `applicationElementSpecifier` need no adaptation; the only SwiftUI-specific concern is where the app registers its `.sdef` and constructs its scriptable object graph (typically still in an `NSApplicationDelegateAdaptor`).
- **Compose (Kotlin Desktop/Android)**: there is no OS-level AppleEvent/Cocoa Scripting equivalent on these platforms. A Compose Desktop port has no direct analog to `NSAppleScript`; a Compose Android port has no analog to either piece — Android's nearest comparable surface is an `Intent`-based or `Binder`/AIDL IPC command dispatcher that a port would have to design from scratch, with its own thread-marshaling story (e.g. posting to the main `Looper` via `Handler.post` in place of `MainActor.assumeIsolated`).
- **React/Web**: browsers provide no OS-level scripting/automation bridge comparable to Apple Events. The nearest analogs are a browser extension's `runtime.sendMessage`/native-messaging host, or a page's own `postMessage`-based command dispatcher; either is sandboxed and permissioned very differently from Cocoa Scripting's AppleEvent model, so a web port is a different security surface, not a line-for-line translation.
- **AppKit / UIKit**: this is the source platform. `AppleScriptRunner.swift` (Foundation-only) wraps `NSAppleScript(source:)`/`executeAndReturnError` into the `Result` enum. `MainActorScriptCommand.swift` (AppKit) supplies the `NSScriptCommand` base class and the `applicationElementSpecifier(key:uniqueID:)` helper, both bridging onto the main actor via `MainActor.assumeIsolated` and a private `final class Box: @unchecked Sendable` to satisfy Swift 6 region isolation for the captured `self`/closure/result (see Design Decisions). UIKit has no Cocoa Scripting/AppleEvent equivalent; none of this recipe applies to an iOS target. `AppleScriptRunner.Result` is declared `@frozen`, fixing its three cases as part of the type's binary-stable public contract (**result-value-equality**). `MainActorScriptCommand` declares itself `@unchecked Sendable`, because its superclass `NSScriptCommand` carries mutable state and is not itself `Sendable` (**command-runs-on-serialized-context**, **command-default-implementation-bridges-context**); a `MainActorScriptCommand` subclass instance handed to Cocoa Scripting's arbitrary-thread AppleEvent dispatch and compiled under `SWIFT_STRICT_CONCURRENCY: complete` produces no Sendable-conformance diagnostic as a result.
- **WinUI 3**: Windows has no AppleScript/Apple Events equivalent, but it has a comparable automation surface: a COM Automation object (a `[ComVisible(true)]` class implementing `IDispatch`, registered so script hosts such as Windows Script Host's VBScript/JScript engines, or PowerShell via `New-Object -ComObject`, can drive it) is the closest analog to Cocoa Scripting's `.sdef`-declared, AppleEvent-dispatched command surface. For an `AppleScriptRunner` analog, `Microsoft.PowerShell.SDK`'s `PowerShell` class can compile and invoke a script string and capture output/errors via `PSDataCollection<PSObject>` and `ErrorRecord`, mirroring `.success`/`.compileFailed`/`.runtimeFailed`. For `MainActorScriptCommand`'s main-actor bridge, a WinUI 3 app's `DispatcherQueue` is the analog to the main actor: a base command class would capture the UI thread's `DispatcherQueue` and call `TryEnqueue` (or an `EnqueueAsync` helper) to marshal `performMain()`'s equivalent onto the UI thread — but `TryEnqueue` enqueues asynchronously by default, so a port preserving `performDefaultImplementation()`'s synchronous return-value contract must block on completion (e.g. via a `TaskCompletionSource`) rather than assume synchronous main-thread execution the way `MainActor.assumeIsolated` does.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Scripting/` |

## Design Decisions

### Advisory main-thread requirement is not enforced

**Decision**: `AppleScriptRunner.run(_:)` performs no thread check, assertion, or automatic dispatch to the main thread before calling `NSAppleScript(source:).executeAndReturnError`; the main-thread requirement is stated only in a doc comment as guidance to the caller.

**Rationale**: the doc comment itself states the requirement varies by macOS version, so a hard-coded thread assertion here would fail closed on versions where the restriction does not apply, and forcing an internal dispatch to main would turn every call into an implicitly asynchronous operation, breaking the synchronous, directly-returned `Result` contract every existing caller relies on.

**Approved**: pending

### `.compileFailed` is kept as a defensive case despite being unreachable today

**Decision**: `AppleScriptRunner.Result` keeps a `.compileFailed` case even though `AppleScriptRunnerTests`' own comment states `NSAppleScript(source:)` never returns `nil` in practice — parse/tokenizer errors surface later, through `.runtimeFailed`.

**Rationale**: `NSAppleScript(source:)` is declared as a failable initializer (`NSAppleScript?`), so the type system requires a `nil` case regardless of today's observed behavior; naming that case explicitly is cheaper and clearer than force-unwrapping and asserting an invariant that a future Foundation change could silently invalidate.

**Approved**: pending

### Fail-fast main-actor trapping instead of a runtime-checked precondition

**Decision**: both `MainActorScriptCommand.performDefaultImplementation()` and `applicationElementSpecifier(key:uniqueID:)` bridge onto the main actor with `MainActor.assumeIsolated`, which traps if invoked off the main thread, rather than a runtime check that returns an error or `nil`.

**Rationale**: Cocoa Scripting's own contract guarantees `performDefaultImplementation()` is always invoked on the main thread when the script suite is registered in the app's `Info.plist`; trapping converts a violation of that guarantee into an immediate, loud failure at the call site instead of letting undefined AppKit/main-actor state propagate silently, consistent with agenticdevelopercookbook://principles/fail-fast.

**Approved**: pending

### Box-based Sendable bridging instead of an `@unchecked Sendable` closure

**Decision**: both main-actor bridging call sites wrap their captured state and result in a private, file-local `final class Box: @unchecked Sendable` rather than marking the capturing closure itself `@unchecked Sendable`.

**Rationale**: per `MainActorScriptCommand.swift`'s own comment, `assumeIsolated`'s `sending` closure parameter rejects captures of a non-final `@unchecked Sendable` `self` under Swift 6 region analysis, but a `final class @unchecked Sendable` Box holding `self` (and, for `applicationElementSpecifier`, the `key`, `uniqueID`, and result) satisfies the region checker; this is the codebase's one standing pattern for this bridge, applied twice, rather than two independent workarounds.

**Approved**: pending

### Hardcoded, never-localized "unknown error" fallback

**Decision**: `AppleScriptRunner.run(_:)` substitutes the literal English string "unknown error" for a missing `NSAppleScript.errorMessage` value rather than a localized string, a nil message, or a different fallback.

**Rationale**: `runtimeFailed(message:number:)`'s `message` is typed as a non-optional `String`, so some literal value is required when the dictionary entry is absent; no localization layer exists anywhere in this component's three files for this or any other string (see Localization), so the fallback is plain, hardcoded English by default rather than by a deliberate localization decision.

**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [main-thread-freedom](agenticdevelopercookbook://compliance/performance#main-thread-freedom) | partial | Performance |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | partial | Reliability |

`separation-of-concerns` **passed**: each of the three pieces has exactly one
job — `AppleScriptRunner` only compiles/executes AppleScript source and
structures the outcome, `MainActorScriptCommand` only bridges Cocoa
Scripting's dispatch onto the main actor, and `applicationElementSpecifier`
only builds one kind of `NSScriptObjectSpecifier` — with no UI, persistence,
or networking code mixed into any of them. `unit-test-coverage` is
**partial**: `AppleScriptRunner` and `MainActorScriptCommand` each have a
dedicated `Tests/.../Scripting/*Tests.swift` suite with meaningful
assertions (see Conformance Test Vectors), but `applicationElementSpecifier`
has no test file among the given sources or found elsewhere in the
repository. `explicit-error-handling` **passed**: `AppleScriptRunner.run(_:)`
never drops a compile or runtime failure — every failure path returns a
distinct, inspectable `Result` case; nothing is caught and discarded.
`main-thread-freedom` is **partial**: `AppleScriptRunner.run(_:)` executes
synchronously and can block whichever thread calls it for the duration of
the AppleScript's execution, with no timeout and no async variant; the
component leaves avoiding a main-thread block entirely to the caller (see
`caller-main-thread-marshaling`). `fault-tolerance` is **partial**:
`applicationElementSpecifier` degrades safely to `nil` when its AppKit
dependency is in an unexpected state, but it and
`MainActorScriptCommand.performDefaultImplementation()` both trap via
`MainActor.assumeIsolated` if ever invoked off the main thread — a
deliberate fail-fast choice (see Design Decisions) that satisfies
agenticdevelopercookbook://principles/fail-fast but not this check's literal
"without crashing" bar.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to system/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
