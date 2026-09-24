---
id: d5812249-f235-43df-9cd7-504220da1a7d
title: Foundation Scripting
domain: agentictoolkit://recipes/foundation-scripting
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: AppleScript execution wrapper, a main-actor NSScriptCommand base, and an
  application-element NSScriptObjectSpecifier helper for macOS Cocoa Scripting.
platforms:
- swift
- macos
tags:
- scripting
- applescript
- cocoa-scripting
- main-actor
- appkit
- macos
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

# Foundation Scripting

## Overview

Three small, independent primitives that give a macOS app AppleScript and
Cocoa Scripting support without each app-shell reimplementing the same
Sendable/main-actor bridging boilerplate. `AppleScriptRunner` compiles and
executes an AppleScript source string via `NSAppleScript` and returns a
structured `Result` instead of `nil`. `MainActorScriptCommand` is the base
class `NSScriptCommand` subclasses inherit from so their command handler
runs on the main actor without each one re-deriving the
`MainActor.assumeIsolated` bridge by hand. `applicationElementSpecifier`
builds the `NSScriptObjectSpecifier` a scriptable wrapper returns from
`objectSpecifier` for an element that hangs directly off `application`
(a pane, tab, project window, or terminal session). All three live in the
`AgenticToolkitScripting` module and are re-exported through
`AgenticToolkitMacOS` (`ScriptingReExports.swift`) so existing
`import AgenticToolkitMacOS` call sites keep working. `AppleScriptRunner`
depends only on Foundation; `MainActorScriptCommand` and
`applicationElementSpecifier` additionally depend on AppKit.

## Behavioral Requirements

- **script-compilation-and-execution**: `AppleScriptRunner.run(_:)` MUST compile the given AppleScript source string via `NSAppleScript(source:)` and, when compilation succeeds, MUST execute it via `executeAndReturnError`.
- **compile-failure-result**: `AppleScriptRunner.run(_:)` MUST return `.compileFailed` when `NSAppleScript(source:)` returns `nil` for the given source.
- **runtime-failure-result**: `AppleScriptRunner.run(_:)` MUST return `.runtimeFailed(message:number:)` when `executeAndReturnError` populates a non-nil error dictionary, with `message` taken from that dictionary's `NSAppleScript.errorMessage` entry and `number` from its `NSAppleScript.errorNumber` entry.
- **runtime-failure-fallback-values**: `AppleScriptRunner.run(_:)` MUST substitute the literal string "unknown error" for `message` when the error dictionary has no string value for `NSAppleScript.errorMessage`, and MUST substitute `0` for `number` when the dictionary has no int value for `NSAppleScript.errorNumber`.
- **success-result-value**: `AppleScriptRunner.run(_:)` MUST return `.success(value)`, where `value` is the executed script's result descriptor's `stringValue`, when the error dictionary is nil.
- **success-value-nilable**: Callers MUST treat the `String?` a `.success` case carries as possibly `nil`, since `NSAppleScriptResult.stringValue` is not guaranteed to produce a value for every executed script.
- **result-value-equality**: `AppleScriptRunner.Result` MUST conform to `Equatable`, comparing the `.success`, `.compileFailed`, and `.runtimeFailed` cases (and their associated values) by value.
- **result-fixed-case-set**: `AppleScriptRunner.Result` MUST be declared `@frozen`, fixing its three cases as part of the type's binary-stable public contract.
- **runner-caller-thread**: `AppleScriptRunner.run(_:)` MUST execute synchronously on the thread it is called from and MUST NOT dispatch the compile-or-execute work to any other thread or queue internally.
- **caller-main-thread-marshaling**: Callers SHOULD invoke `AppleScriptRunner.run(_:)` on the main thread on macOS versions where `NSAppleScript` requires it, per the doc comment: "`NSAppleScript` requires the main thread on some macOS versions; callers running on a background queue should marshal to main if needed."
- **command-default-behavior**: `MainActorScriptCommand.performMain()`'s default implementation, when a subclass does not override it, MUST return `nil`.
- **command-main-actor-isolation**: A `MainActorScriptCommand` subclass's `performMain()` override MUST run on the main actor, since `performMain()` is declared `@MainActor`.
- **command-dispatch-via-assume-isolated**: `MainActorScriptCommand.performDefaultImplementation()` MUST invoke `performMain()` from inside a `MainActor.assumeIsolated` closure.
- **command-result-propagation**: `MainActorScriptCommand.performDefaultImplementation()` MUST return exactly the value produced by that invocation of `performMain()`, with no transformation.
- **command-sendable-conformance**: `MainActorScriptCommand` MUST declare itself `@unchecked Sendable`, because its superclass `NSScriptCommand` carries mutable state and is not itself `Sendable`.
- **command-return-type-freedom**: A `MainActorScriptCommand` subclass's `performMain()` override MAY return any value assignable to `Any?`, including `nil`, since `NSScriptCommand.performDefaultImplementation()`'s own contract returns `Any?`.
- **element-specifier-result**: `applicationElementSpecifier(key:uniqueID:)` MUST return an `NSUniqueIDSpecifier` built from `NSApp`'s script class description as the container class description, the given `key`, and the result of calling the given `uniqueID` closure, when `NSApp.classDescription` can be cast to `NSScriptClassDescription`.
- **element-specifier-nil-fallback**: `applicationElementSpecifier(key:uniqueID:)` MUST return `nil` when `NSApp.classDescription` cannot be cast to `NSScriptClassDescription`.
- **element-specifier-main-actor-work**: `applicationElementSpecifier(key:uniqueID:)` MUST perform the `NSApp.classDescription` read, the `uniqueID()` call, and the `NSUniqueIDSpecifier` construction from inside a `MainActor.assumeIsolated` closure.
- **element-specifier-no-container-specifier**: `applicationElementSpecifier(key:uniqueID:)` MUST pass `nil` for `containerSpecifier`, since every element it addresses hangs directly off `application`.

## Appearance

Not applicable — this is a scripting-bridge utility, not a visual component.

## States

Not applicable — this is a scripting-bridge utility, not a visual component.

## Accessibility

Not applicable — this is a scripting-bridge utility, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|---------------|-------|----------|
| foundation-scripting-001 | script-compilation-and-execution, success-result-value | `AppleScriptRunner.run("return \"hello\"")` | Returns `.success("hello")` (`AppleScriptRunnerTests.successReturnsString`) |
| foundation-scripting-002 | success-result-value | `AppleScriptRunner.run("return 42")` | Returns `.success("42")` — `NSAppleScript` stringifies the numeric result (`AppleScriptRunnerTests.successReturnsNumericString`) |
| foundation-scripting-003 | success-value-nilable | `AppleScriptRunner.run("")` (empty source) | Compiles and executes; returns `.success(nil)` (`AppleScriptRunnerTests.emptySourceSucceeds`) |
| foundation-scripting-004 | runtime-failure-result | `AppleScriptRunner.run("error \"boom\" number -1728")` | Returns `.runtimeFailed(message:number:)` whose message contains "boom" and whose number equals -1728 (`AppleScriptRunnerTests.runtimeFailed`) |
| foundation-scripting-005 | runtime-failure-fallback-values | An error dictionary from `executeAndReturnError` with no `NSAppleScript.errorMessage`/`errorNumber` entries | `message` equals "unknown error", `number` equals `0` (source: `AppleScriptRunner.swift`'s `?? "unknown error"` / `?? 0`; no dedicated test found) |
| foundation-scripting-006 | compile-failure-result | A source string for which `NSAppleScript(source:)` returns `nil` | Returns `.compileFailed` (source: `AppleScriptRunner.swift`; `AppleScriptRunnerTests`' own comment notes this path is unreachable in practice) |
| foundation-scripting-007 | result-value-equality, result-fixed-case-set | `AppleScriptRunner.Result.success("x") == AppleScriptRunner.Result.success("x")` | `true` (source: `Result: Equatable`, `@frozen`) |
| foundation-scripting-008 | runner-caller-thread | `AppleScriptRunner.run(_:)` called from a background `DispatchQueue` | Executes and returns synchronously on that same background thread, with no internal hop to another queue (source: `AppleScriptRunner.swift` — no `DispatchQueue`/`Task` inside `run(_:)`) |
| foundation-scripting-009 | caller-main-thread-marshaling | A background-queue caller invokes `AppleScriptRunner.run(_:)` without marshaling to the main thread, on a macOS version where `NSAppleScript` requires it | Documented as the caller's own responsibility; `AppleScriptRunner` performs no thread check or automatic marshaling (source: `AppleScriptRunner.swift` doc comment) |
| foundation-scripting-010 | command-default-behavior | `MainActorScriptCommand(commandDescription:).performDefaultImplementation()` with no subclass override | Returns `nil` (`MainActorScriptCommandTests.baseReturnsNil`) |
| foundation-scripting-011 | command-result-propagation, command-return-type-freedom | `ReturningCommand(value: "answer").performDefaultImplementation()` | Returns `"answer"` (`MainActorScriptCommandTests.subclassReturnValue`) |
| foundation-scripting-012 | command-return-type-freedom | `ReturningCommand(value: 42).performDefaultImplementation()` | Returns `42` (`MainActorScriptCommandTests.subclassReturnsInt`) |
| foundation-scripting-013 | command-result-propagation | `ReturningCommand(value: nil).performDefaultImplementation()` | Returns `nil` (`MainActorScriptCommandTests.subclassReturnsNil`) |
| foundation-scripting-014 | command-main-actor-isolation, command-dispatch-via-assume-isolated | `MainActorAssertingCommand().performDefaultImplementation()` invoked from the main thread | `sawMainThread` observed as `true` inside `performMain()` (`MainActorScriptCommandTests.runsOnMainThread`) |
| foundation-scripting-015 | command-sendable-conformance | A `MainActorScriptCommand` subclass instance is created and handed to Cocoa Scripting's arbitrary-thread AppleEvent dispatch, compiled under `SWIFT_STRICT_CONCURRENCY: complete` | Compiles with no Sendable-conformance diagnostic, because `MainActorScriptCommand` declares `@unchecked Sendable` (source: class declaration in `MainActorScriptCommand.swift`) |
| foundation-scripting-016 | element-specifier-result, element-specifier-no-container-specifier, element-specifier-main-actor-work | `applicationElementSpecifier(key: "panes") { "some-uuid" }` called on the main actor while `NSApp.classDescription` is an `NSScriptClassDescription` | Returns a non-nil `NSUniqueIDSpecifier` whose `key` is `"panes"`, whose `uniqueID` is `"some-uuid"`, and whose `containerSpecifier` is `nil` (source: `MainActorScriptCommand.swift`'s `applicationElementSpecifier`; consumed by `ScriptablePane.swift`'s `objectSpecifier`) |
| foundation-scripting-017 | element-specifier-nil-fallback | `applicationElementSpecifier(key:uniqueID:)` called while `NSApp.classDescription` cannot be cast to `NSScriptClassDescription` | Returns `nil` (source: the `guard let appDescription = NSApp.classDescription as? NSScriptClassDescription else { return }` in `MainActorScriptCommand.swift`) |

## Edge Cases

- **Empty AppleScript source** (null/empty input): `AppleScriptRunner.run("")` MUST compile and execute successfully, returning `.success(nil)`, per `AppleScriptRunnerTests.emptySourceSucceeds` — `NSAppleScript` treats empty source as a valid, no-op script rather than a compile failure.
- **Script produces no textual result** (boundary of `success-result-value`): when the executed script's result descriptor's `stringValue` is `nil`, `AppleScriptRunner.run(_:)` MUST still return `.success(nil)` rather than promoting the absence of a value to `.compileFailed` or `.runtimeFailed`.
- **Extreme or unusual error numbers** (boundary values): AppleScript/OSA error numbers span the full `Int` domain, including negative codes (e.g. `-1728`); `AppleScriptRunner.run(_:)` MUST pass `NSAppleScript.errorNumber` through unmodified, with no range validation or clamping.
- **Concurrent calls to `AppleScriptRunner.run(_:)`** (concurrent access): each call constructs and owns its own `NSAppleScript` instance with no state shared inside `AppleScriptRunner` itself, so concurrent calls from independent threads MUST NOT corrupt one another's result; the source's own doc comment notes that `NSAppleScript` may nonetheless require all such calls to land on the main thread on some macOS versions, a requirement `AppleScriptRunner` does not enforce (see `caller-main-thread-marshaling`).
- **Concurrent `performMain()` invocations on one `MainActorScriptCommand` instance** (concurrent access): because `performMain()` is `@MainActor`-isolated and Cocoa Scripting always dispatches command handlers on the main thread, invocations MUST be serialized by the main actor's executor; the component adds no further locking because none is needed.
- **`performDefaultImplementation()` invoked off the main thread** (error state, outside the stated contract): `MainActor.assumeIsolated` MUST trap — a fatal runtime error, not a catchable error or a returned value — because the safety of that call rests on the documented assumption that Cocoa Scripting always invokes command handlers on the main thread when the script suite is registered in the app's `Info.plist`, not on a runtime-checked precondition.
- **`NSApp.classDescription` is not an `NSScriptClassDescription`** (error/unavailable-dependency state): `applicationElementSpecifier(key:uniqueID:)` MUST return `nil` rather than trapping or constructing a malformed specifier.
- **Compile failure path** (error state): `NSAppleScript(source:)` returning `nil` MUST route to `.compileFailed`; `AppleScriptRunnerTests`' own comment documents this path as unreachable in practice, since `NSAppleScript` accepts any string and defers all parse/tokenizer errors to `executeAndReturnError` — the case exists purely as a defensive catch against a documented-nullable initializer, not because any known input currently exercises it.
- **Offline / disconnected state**: Not applicable — none of the three sources perform network I/O. An AppleScript run through `AppleScriptRunner.run(_:)` may itself address another application or a network resource, but any such failure surfaces through that script's own `error`/return value and is reported through the ordinary `.runtimeFailed`/`.success` path, not through a distinct offline case in this component.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `source` | `String` | none (required) | The AppleScript source text `AppleScriptRunner.run(_:)` compiles and executes. |
| `key` | `String` | none (required) | The `application` element key declared in the host app's `.sdef` (e.g. `panes`, `projectTabs`, `projectWindows`, `terminalSessions`), passed to `applicationElementSpecifier(key:uniqueID:)`. |
| `uniqueID` | `@escaping @MainActor () -> String` | none (required) | Closure `applicationElementSpecifier(key:uniqueID:)` calls, on the main actor, to obtain the addressed element's unique id string. |
| `performMain()` override | `@MainActor open func performMain() -> Any?` | returns `nil` | The subclass hook a caller overrides on `MainActorScriptCommand` to implement one scriptable command; the base class's own implementation is the default when unoverridden. |

## Deep Linking

Not applicable: none of the three sources register a URL scheme or route. Cocoa Scripting's AppleEvent-based command dispatch (`NSScriptCommand`, `NSScriptObjectSpecifier`) is a distinct, non-URL addressing mechanism, and it is specified in full above under Behavioral Requirements.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| `appleScriptRunner.unknownError` | unknown error | `AppleScriptRunner.run(_:)`'s fallback substitution for `message` when the error dictionary carries no `NSAppleScript.errorMessage` entry (see `runtime-failure-fallback-values`) |

The key above is synthetic, for this table only: the string is a raw literal
returned directly to callers, not looked up from any string table, resource
bundle, or locale-aware API. This is the only hardcoded, user/caller-visible
string across the three given sources, and it is a plain fact about the
current implementation, not a gap — there is no localization mechanism in
this component at all.

## Accessibility Options

Not applicable: none of the three sources render a visual or interactive surface, so there is no contrast, motion, font-size, or other accessibility-preference surface for this recipe to define.

## Feature Flags

Not applicable: no feature-flag check (e.g. a remote-config lookup or a hand-rolled flag check) appears in any of the three given sources.

## Analytics

Not applicable: none of the three given sources emit an analytics/telemetry event or call an analytics client.

## Privacy

Not applicable: none of the three given sources collect, store, or transmit any data. `AppleScriptRunner.run(_:)` passes a caller-supplied AppleScript source string through to `NSAppleScript` and returns its result or error to the caller without persisting, logging, or transmitting either; `applicationElementSpecifier` passes a caller-supplied `key` and `uniqueID()` value into an `NSUniqueIDSpecifier` with the same no-persistence, no-transmission characteristics.

## Logging

Not applicable: none of the three given sources call a logger, `print`, `os_log`, or any other diagnostic-output API.

## Platform Notes

- **SwiftUI**: A SwiftUI app still reaches Cocoa Scripting through AppKit, not through any SwiftUI-specific API — `NSApplication`, `NSScriptCommand`, and `NSScriptSuiteRegistry` sit underneath a SwiftUI `App`/`Scene` lifecycle exactly as they do under an `NSApplicationDelegate`-based app. `MainActorScriptCommand` and `applicationElementSpecifier` need no adaptation; the only SwiftUI-specific concern is where the app registers its `.sdef` and constructs its scriptable object graph (typically still in an `NSApplicationDelegateAdaptor`).
- **Compose (Kotlin Desktop/Android)**: there is no OS-level AppleEvent/Cocoa Scripting equivalent on these platforms. A Compose Desktop port has no direct analog to `NSAppleScript`; a Compose Android port has no analog to either piece — Android's nearest comparable surface is an `Intent`-based or `Binder`/AIDL IPC command dispatcher that a port would have to design from scratch, with its own thread-marshaling story (e.g. posting to the main `Looper` via `Handler.post` in place of `MainActor.assumeIsolated`).
- **React/Web**: browsers provide no OS-level scripting/automation bridge comparable to Apple Events. The nearest analogs are a browser extension's `runtime.sendMessage`/native-messaging host, or a page's own `postMessage`-based command dispatcher; either is sandboxed and permissioned very differently from Cocoa Scripting's AppleEvent model, so a web port is a different security surface, not a line-for-line translation.
- **AppKit / UIKit**: this is the source platform. `AppleScriptRunner.swift` (Foundation-only) wraps `NSAppleScript(source:)`/`executeAndReturnError` into the `Result` enum. `MainActorScriptCommand.swift` (AppKit) supplies the `NSScriptCommand` base class and the `applicationElementSpecifier(key:uniqueID:)` helper, both bridging onto the main actor via `MainActor.assumeIsolated` and a private `final class Box: @unchecked Sendable` to satisfy Swift 6 region isolation for the captured `self`/closure/result (see Design Decisions). UIKit has no Cocoa Scripting/AppleEvent equivalent; none of this recipe applies to an iOS target.
- **WinUI 3**: Windows has no AppleScript/Apple Events equivalent, but it has a comparable automation surface: a COM Automation object (a `[ComVisible(true)]` class implementing `IDispatch`, registered so script hosts such as Windows Script Host's VBScript/JScript engines, or PowerShell via `New-Object -ComObject`, can drive it) is the closest analog to Cocoa Scripting's `.sdef`-declared, AppleEvent-dispatched command surface. For an `AppleScriptRunner` analog, `Microsoft.PowerShell.SDK`'s `PowerShell` class can compile and invoke a script string and capture output/errors via `PSDataCollection<PSObject>` and `ErrorRecord`, mirroring `.success`/`.compileFailed`/`.runtimeFailed`. For `MainActorScriptCommand`'s main-actor bridge, a WinUI 3 app's `DispatcherQueue` is the analog to the main actor: a base command class would capture the UI thread's `DispatcherQueue` and call `TryEnqueue` (or an `EnqueueAsync` helper) to marshal `performMain()`'s equivalent onto the UI thread — but `TryEnqueue` enqueues asynchronously by default, so a port preserving `performDefaultImplementation()`'s synchronous return-value contract must block on completion (e.g. via a `TaskCompletionSource`) rather than assume synchronous main-thread execution the way `MainActor.assumeIsolated` does.

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
