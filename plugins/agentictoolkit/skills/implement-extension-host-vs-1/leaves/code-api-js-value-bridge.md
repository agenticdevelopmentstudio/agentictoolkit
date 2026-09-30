<!-- leaf: implement-extension-host-vs-1/code-api-js-value-bridge · source: extension-host-vs-code-api-js-value-bridge.md -->

**Rules** (cite as `implement-extension-host-vs-1/code-api-js-value-bridge#<slug>`):

- `pure-value-construction` MUST
- `no-actor-isolation-declared` MUST
- `undefined-value` MUST
- `undefined-or-null-value` MUST
- `array-construction` MUST
- `array-construction-is-fresh` MUST
- `array-or-null-construction` MUST
- `empty-array-is-empty-not-missing` MUST
- `string-or-null-value` MUST
- `reject-with-error` MUST
- `reject-with-error-has-no-stack` MUST
- `reject-with-error-silent-when-context-gone` MUST
- `reject-torn-down-wording` MUST
- `string-field-read-without-coercion` MUST
- `string-field-empty-is-a-value` MUST

# JSValueBridge

## Overview

`JSValueBridge` is a caseless `enum` in `JSValueBridge.swift` holding the handful of one-line `JSValue` constructions every `MainThread*` `VSCodeAPI` adaptor needs: building a genuine JavaScript `undefined`, an array, or a string to hand back into a `JSContext`, and rejecting a `Promise`'s `reject` callback with a real JavaScript `Error`. Each of these constructions used to exist two or three times over as a `private static` member of `MainThreadWindow`, `MainThreadWorkspace`, `MainThreadDiagnostics`, and `MainThreadLanguageModels` individually; `JSValueBridge` is the one reachable home all four now call through instead. It also holds `stringOptionalField(_:)`, the one read-side helper: pulling a `String` out of a `JSValue?` property only when that property is genuinely a JavaScript string, never a coercion of one. `JSValueBridge` declares no state and no isolation of its own — every member is a pure function of its arguments — and it is not a protocol, because there is nothing here to substitute.

## Behavioral Requirements

- **pure-value-construction**: `JSValueBridge` MUST NOT declare or retain any stored state across calls; every member MUST be a pure function of its arguments, since the type is declared as a caseless `enum` with no stored properties.
- **no-actor-isolation-declared**: `JSValueBridge` MUST NOT declare `@MainActor`, `actor`, or `Sendable` on itself; each call site remains solely responsible for confining its call to whatever isolation domain already holds the `JSContext`/`JSValue` arguments it passes in, because those JavaScriptCore/Foundation types are non-Sendable classes the Swift compiler already keeps within their creating domain.
- **undefined-value**: `undefined(in:)` MUST return a `JSValue` wrapping a genuine JavaScript `undefined` built via `JSValue(undefinedIn:)`, or `nil` if that constructor itself returns `nil`, for a synchronous member result where `nil` is itself a legitimate answer.
- **undefined-or-null-value**: `undefinedOrNull(in:)` MUST return the same JavaScript `undefined` value `undefined(in:)` builds, boxed as `Any`, and MUST fall back to `NSNull()` (JavaScript `null`) only when `JSValue(undefinedIn:)` itself returns `nil`, for a `Promise` settlement, which has no way to accept `nil`.
- **array-construction**: `array(of:in:)` MUST return a JavaScript array holding exactly the elements of `values` in their given order, built via `JSValue(object:values,in:context)`, or `nil` if that constructor returns `nil`, for a synchronous member result.
- **array-construction-is-fresh**: `array(of:in:)` MUST build a new JavaScript array object on every call; mutating the array returned by one call MUST NOT change the array returned by any other call, even when both calls are given the same `values`.
- **array-or-null-construction**: `arrayOrNull(of:in:)` MUST return the same array `array(of:in:)` would build for the same `values` and `context`, boxed as `Any`, and MUST fall back to `NSNull()` only when the underlying `JSValue(object:in:)` call returns `nil`, for a `Promise` settlement.
- **empty-array-is-empty-not-missing**: `array(of:in:)` and `arrayOrNull(of:in:)` MUST return an empty JavaScript array of length `0`, never `undefined` and never `nil`/`NSNull()`, when `values` is an empty array.
- **string-or-null-value**: `stringOrNull(_:in:)` MUST return a JavaScript string carrying exactly the characters of `value`, boxed as `Any`, built via `JSValue(object:value,in:context)`, including when `value` is the empty string, and MUST fall back to `NSNull()` only when that constructor returns `nil`.
- **reject-with-error**: `rejectWithError(_:message:)` MUST call `reject` with a single argument that is a JavaScript `Error` instance built via `JSValue(newErrorFromMessage:message,in:context)` in `reject`'s own `context`, whose `message` property equals `message` and whose `name` property equals `"Error"`.
- **reject-with-error-has-no-stack**: The `Error` `rejectWithError(_:message:)` builds MUST NOT carry a populated `stack` property (JavaScript `typeof error.stack` MUST evaluate to `"undefined"`), because `JSValue(newErrorFromMessage:in:)` constructs the object directly rather than throwing it from JavaScript, leaving no frame to record.
- **reject-with-error-silent-when-context-gone**: `rejectWithError(_:message:)` MUST take no action and MUST NOT call `reject` when `reject.context` is `nil`, or when `JSValue(newErrorFromMessage:message:in:)` itself returns `nil`; there is nothing left to reject into once `reject`'s context is gone, so this path produces no signal to any caller.
- **reject-torn-down-wording**: `rejectTornDown(_:path:)` MUST reject `reject` (via `rejectWithError`) with the message `"\(path) is unavailable: this extension's host has been torn down."`, substituting `path` verbatim, so every `MainThread*` adaptor built on this bridge reports teardown with one shared wording.
- **string-field-read-without-coercion**: `stringOptionalField(_:)` MUST return `value`'s Swift `String` contents only when `value` is non-`nil` and `value.isString` is `true`; it MUST return `nil` for a `nil` operand, and MUST return `nil` — never a coerced string — when `value` holds a JavaScript number, boolean, object, array, function, `null`, or `undefined`.
- **string-field-empty-is-a-value**: `stringOptionalField(_:)` MUST return the empty string `""`, not `nil`, when `value` holds a JavaScript string whose contents are empty.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `context` | `JSContext` | (required, no default) | The JavaScriptCore context a value is built in, or that a rejection's `Error` is built in via `reject.context`. Every caller supplies its own live extension-host context. |
| `values` | `[JSValue]` | (required, no default) | The ordered `JSValue`s `array(of:in:)`/`arrayOrNull(of:in:)` bridge into a new JavaScript array. |
| `value` (string builder) | `String` | (required, no default) | The Swift string `stringOrNull(_:in:)` bridges into a JavaScript string, including the empty string. |
| `value` (field reader) | `JSValue?` | (required, no default; `nil` is a valid operand) | The property `stringOptionalField(_:)` reads without coercion; `nil` represents "no operand was supplied at all." |
| `reject` | `JSValue` | (required, no default) | The JavaScript `reject` callback of a `Promise` that `rejectWithError(_:message:)`/`rejectTornDown(_:path:)` invokes with a JavaScript `Error`. |
| `message` | `String` | (required, no default) | The literal text `rejectWithError(_:message:)` writes into the built `Error`'s `message` property. |
| `path` | `String` | (required, no default) | The dotted `vscode.*` member path `rejectTornDown(_:path:)` embeds verbatim into its fixed teardown wording. |

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal, not externalized) | `{path} is unavailable: this extension's host has been torn down.` | The `Error.message` `rejectTornDown(_:path:)` builds (via `rejectWithError`), delivered to an extension's `Promise.catch` as `error.message`, with `{path}` substituted verbatim by the caller's `path` argument. |

This is a hardcoded English literal with no localization mechanism (no string catalog, no key lookup) anywhere in `JSValueBridge.swift`; see **reject-torn-down-wording** and the `no-hardcoded-strings` row in Compliance.

## Platform Notes

- **SwiftUI**: not applicable to this file — `JSValueBridge.swift` imports only `Foundation` and `JavaScriptCore`, with no SwiftUI dependency; it renders nothing and observes no view state.
- **AppKit / UIKit**: this is the source. `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/JSValueBridge.swift` is part of the `AgenticToolkitMacOS` framework target, which `project.yml` declares `platform: macOS` for — no iOS target packages this file. It is a caseless `enum`, not itself `@MainActor`, called from seven `@MainActor` types in the same directory — `VSCodeAPI`, `MainThreadWindow`, `MainThreadWorkspace`, `MainThreadDiagnostics`, `MainThreadLanguageModels`, `MainThreadWebviews`, and `MainThreadTreeViews` — each of which builds or reads `JSValue`s through it rather than repeating its five constructions.
- **Compose**: model each member as a top-level function on a plain Kotlin `object` (mirroring the caseless-enum-as-namespace pattern) over whichever embedded JS engine the Android host uses in place of `JSContext`/`JSValue` (e.g. a `V8Object`/`V8Array` pair). Keep the two-return-shape split: `undefined`/`array` return a nullable wrapper for a synchronous result, while `undefinedOrNull`/`arrayOrNull`/`stringOrNull` return `Any?`/`Object` with a null-object fallback for a coroutine `Deferred`/`Promise`-equivalent settlement, per **undefined-value**/**undefined-or-null-value** and **array-construction**/**array-or-null-construction**. Reproduce **string-field-read-without-coercion** with an explicit type check (`is String`) rather than `toString()`.
- **React/Web**: this is closest to the runtime the bridge is emulating — a real VS Code extension already runs directly against a JavaScript engine, so a React/Web host embedding a similar extension bridge would not need most of these helpers at all (there is no second JS-to-native boundary for `undefined`, arrays, or strings to cross). The part worth keeping is the rejection shape: **reject-with-error**, **reject-with-error-has-no-stack**, and **reject-torn-down-wording**, for whatever transport (e.g. a `MessageChannel` to a worker) replaces this file's `JSContext` boundary — an extension's `catch (e)` still needs a real `Error` with a stable `message`.
- **WinUI 3**: model the five constructions as `static` methods on a `JSValueBridge`-equivalent helper class built on whichever embedded JS engine the Windows host runs extensions in (e.g. ClearScript's `V8ScriptEngine`, using `Undefined.Value`/`ScriptObject`/`string` in place of `JSValue`). Map `undefinedOrNull`/`arrayOrNull`/`stringOrNull`'s `Any`-with-`NSNull()`-fallback shape onto `TaskCompletionSource<object>.SetResult(...)` for the `Task`-based promise settlement in place of a JS `Thenable`, and map `rejectWithError`/`rejectTornDown` onto `TaskCompletionSource<object>.SetException(new ScriptEngineException(message))` (or the engine's native JS-`Error`-carrying exception type), so a `.catch`-equivalent still reads a `message` matching **reject-torn-down-wording** exactly. Map `stringOptionalField`'s "read a string only when it truly is one" rule onto refusing anything but a `ScriptObject`/.NET `string` before reading — never `.ToString()` — exactly as **string-field-read-without-coercion** requires.

