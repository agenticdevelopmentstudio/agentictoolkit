<!-- leaf: implement-foundation/scripting · source: foundation-scripting.md -->

**Rules** (cite as `implement-foundation/scripting#<slug>`):

- `script-compilation-and-execution` MUST
- `compile-failure-result` MUST
- `runtime-failure-result` MUST
- `runtime-failure-fallback-values` MUST
- `success-result-value` MUST
- `success-value-nilable` MUST
- `result-value-equality` MUST
- `result-fixed-case-set` MUST
- `runner-caller-thread` MUST
- `caller-main-thread-marshaling` SHOULD
- `command-default-behavior` MUST
- `command-main-actor-isolation` MUST
- `command-dispatch-via-assume-isolated` MUST
- `command-result-propagation` MUST
- `command-sendable-conformance` MUST
- `command-return-type-freedom` MAY
- `element-specifier-result` MUST
- `element-specifier-nil-fallback` MUST
- `element-specifier-main-actor-work` MUST
- `element-specifier-no-container-specifier` MUST

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `source` | `String` | none (required) | The AppleScript source text `AppleScriptRunner.run(_:)` compiles and executes. |
| `key` | `String` | none (required) | The `application` element key declared in the host app's `.sdef` (e.g. `panes`, `projectTabs`, `projectWindows`, `terminalSessions`), passed to `applicationElementSpecifier(key:uniqueID:)`. |
| `uniqueID` | `@escaping @MainActor () -> String` | none (required) | Closure `applicationElementSpecifier(key:uniqueID:)` calls, on the main actor, to obtain the addressed element's unique id string. |
| `performMain()` override | `@MainActor open func performMain() -> Any?` | returns `nil` | The subclass hook a caller overrides on `MainActorScriptCommand` to implement one scriptable command; the base class's own implementation is the default when unoverridden. |

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

## Platform Notes

- **SwiftUI**: A SwiftUI app still reaches Cocoa Scripting through AppKit, not through any SwiftUI-specific API — `NSApplication`, `NSScriptCommand`, and `NSScriptSuiteRegistry` sit underneath a SwiftUI `App`/`Scene` lifecycle exactly as they do under an `NSApplicationDelegate`-based app. `MainActorScriptCommand` and `applicationElementSpecifier` need no adaptation; the only SwiftUI-specific concern is where the app registers its `.sdef` and constructs its scriptable object graph (typically still in an `NSApplicationDelegateAdaptor`).
- **Compose (Kotlin Desktop/Android)**: there is no OS-level AppleEvent/Cocoa Scripting equivalent on these platforms. A Compose Desktop port has no direct analog to `NSAppleScript`; a Compose Android port has no analog to either piece — Android's nearest comparable surface is an `Intent`-based or `Binder`/AIDL IPC command dispatcher that a port would have to design from scratch, with its own thread-marshaling story (e.g. posting to the main `Looper` via `Handler.post` in place of `MainActor.assumeIsolated`).
- **React/Web**: browsers provide no OS-level scripting/automation bridge comparable to Apple Events. The nearest analogs are a browser extension's `runtime.sendMessage`/native-messaging host, or a page's own `postMessage`-based command dispatcher; either is sandboxed and permissioned very differently from Cocoa Scripting's AppleEvent model, so a web port is a different security surface, not a line-for-line translation.
- **AppKit / UIKit**: this is the source platform. `AppleScriptRunner.swift` (Foundation-only) wraps `NSAppleScript(source:)`/`executeAndReturnError` into the `Result` enum. `MainActorScriptCommand.swift` (AppKit) supplies the `NSScriptCommand` base class and the `applicationElementSpecifier(key:uniqueID:)` helper, both bridging onto the main actor via `MainActor.assumeIsolated` and a private `final class Box: @unchecked Sendable` to satisfy Swift 6 region isolation for the captured `self`/closure/result (see Design Decisions). UIKit has no Cocoa Scripting/AppleEvent equivalent; none of this recipe applies to an iOS target.
- **WinUI 3**: Windows has no AppleScript/Apple Events equivalent, but it has a comparable automation surface: a COM Automation object (a `[ComVisible(true)]` class implementing `IDispatch`, registered so script hosts such as Windows Script Host's VBScript/JScript engines, or PowerShell via `New-Object -ComObject`, can drive it) is the closest analog to Cocoa Scripting's `.sdef`-declared, AppleEvent-dispatched command surface. For an `AppleScriptRunner` analog, `Microsoft.PowerShell.SDK`'s `PowerShell` class can compile and invoke a script string and capture output/errors via `PSDataCollection<PSObject>` and `ErrorRecord`, mirroring `.success`/`.compileFailed`/`.runtimeFailed`. For `MainActorScriptCommand`'s main-actor bridge, a WinUI 3 app's `DispatcherQueue` is the analog to the main actor: a base command class would capture the UI thread's `DispatcherQueue` and call `TryEnqueue` (or an `EnqueueAsync` helper) to marshal `performMain()`'s equivalent onto the UI thread — but `TryEnqueue` enqueues asynchronously by default, so a port preserving `performDefaultImplementation()`'s synchronous return-value contract must block on completion (e.g. via a `TaskCompletionSource`) rather than assume synchronous main-thread execution the way `MainActor.assumeIsolated` does.

