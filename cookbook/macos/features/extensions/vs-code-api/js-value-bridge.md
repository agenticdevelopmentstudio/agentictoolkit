---
id: cb25bd84-9a11-4070-8b3c-f178cff76068
title: JSValueBridge
domain: agentictoolkit://cookbook/macos/features/extensions/vs-code-api/js-value-bridge
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Shared JSValue constructions and Promise-rejection builders every MainThread*
  VSCodeAPI adaptor in the extension host uses instead of its own copy.
platforms:
- swift
- macos
tags:
- extension-host
- vscode-api
- javascriptcore
- bridge
depends-on: []
related:
- agentictoolkit://cookbook/macos/features/extensions/vs-code-api/extension-event
- agentictoolkit://cookbook/macos/features/extensions/vs-code-api/extension-input-box-presenting
- agentictoolkit://cookbook/macos/features/extensions/vs-code-api/extension-status-bar-presenting
- agentictoolkit://cookbook/macos/features/extensions/vs-code-api/ai-plugin-language-model-provider
- agentictoolkit://cookbook/macos/features/extensions/vs-code-api/extension-quick-pick-presenting
- agentictoolkit://cookbook/macos/features/extensions/vs-code-api/extension-tree-data-source
- agentictoolkit://cookbook/macos/features/extensions/vs-code-api/extension-message-presenting
- agentictoolkit://cookbook/macos/features/extensions/vs-code-api/extension-webview-presenting
references:
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/JSValueBridge.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Extensions/JSValueBridgeTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/VSCodeAPI.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadWindow.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadWorkspace.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadDiagnostics.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadLanguageModels.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadWebviews.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadTreeViews.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/project.yml (agentictoolkit)
approved-by: ''
approved-date: ''
---

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

## Appearance

Not applicable — this is a pure-function JSValue construction/reading bridge, not a visual component.

## States

Not applicable — this is a pure-function JSValue construction/reading bridge, not a visual component.

## Accessibility

Not applicable — this is a pure-function JSValue construction/reading bridge, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|--------------|-------|----------|
| js-value-bridge-001 | undefined-value | A live `JSContext`; call `JSValueBridge.undefined(in: context)`. | Returns a non-`nil` `JSValue`; `built.isUndefined == true` and `built.isNull == false` (`JSValueBridgeTests.undefinedIsUndefined`). |
| js-value-bridge-002 | undefined-or-null-value | A live `JSContext`; call `JSValueBridge.undefinedOrNull(in: context)`. | Returns an `Any` castable to `JSValue`; `isUndefined == true` and `isNull == false` (`JSValueBridgeTests.undefinedOrNullIsUndefinedInPractice`). |
| js-value-bridge-003 | array-construction, array-construction-is-fresh, pure-value-construction | `items = [JSValue("a"), JSValue("b")]`; call `JSValueBridge.array(of: items, in: context)` twice, keeping both results. | Both results are real arrays: `Array.isArray` true, `length == 2`, `join('') == "ab"`. `first.push('mutated')` leaves `first.length == 2` but `second.length == 1`; `first === second` is `false` (`JSValueBridgeTests.arrayBridgesToAJavaScriptArray`, `.eachCallBridgesItsOwnArray`). |
| js-value-bridge-004 | empty-array-is-empty-not-missing | `values = []`; call `JSValueBridge.array(of: [], in: context)`. | `Array.isArray` true, `length == 0` — an empty array, not `undefined` (`JSValueBridgeTests.anEmptyArrayIsStillAnArray`). |
| js-value-bridge-005 | array-or-null-construction | `objects = [JSValue("a")]`; call `JSValueBridge.arrayOrNull(of: objects, in: context)`. | Returns an `Any` castable to `JSValue`; `Array.isArray` true, `length == 1`, contents equal `array(of:in:)`'s result for the same input — traced to the shared `JSValue(object:in:) ?? NSNull()` expression at `JSValueBridge.swift` (no dedicated test method exists for this member; see Design Decisions). |
| js-value-bridge-006 | string-or-null-value | `value = ""`; call `JSValueBridge.stringOrNull("", in: context)`. | Returns an `Any` castable to `JSValue`; `isString == true`, `toString() == ""` — the empty string is a value, not an absence (`JSValueBridgeTests.theEmptyStringIsAValue`). |
| js-value-bridge-007 | string-or-null-value | `value = "a'b\"c\\d\u{1F600}"`; call `JSValueBridge.stringOrNull(value, in: context)`. | `toString()` equals the exact input, quotes/backslash/emoji intact (`JSValueBridgeTests.aStringKeepsItsContents`). |
| js-value-bridge-008 | reject-with-error, reject-with-error-has-no-stack | A JS `reject` function that captures its argument as `caught`; call `JSValueBridge.rejectWithError(reject, message: "the host said no")`. | `caught instanceof Error` true; `caught.name == "Error"`; `caught.message == "the host said no"`; `typeof caught.stack == "undefined"` (`JSValueBridgeTests.aRejectionCarriesAnError`, `.aRejectionHasNoStack`). |
| js-value-bridge-009 | reject-with-error-silent-when-context-gone | A `reject` `JSValue` whose `context` has already been released (`reject.context == nil`); call `JSValueBridge.rejectWithError(reject, message: "the host said no")`. | `reject` is never invoked and no crash occurs — traced to the `guard let context = reject.context ... else { return }` in `JSValueBridge.swift` (no dedicated test exists for this branch; the guard is exercised only structurally). |
| js-value-bridge-010 | reject-torn-down-wording | A captured `reject`; call `JSValueBridge.rejectTornDown(reject, path: "vscode.window.showInputBox")`. | `caught.message` contains `"vscode.window.showInputBox"` and contains `"torn down"` (`JSValueBridgeTests.aTornDownRejectionNamesThePath`). |
| js-value-bridge-011 | string-field-read-without-coercion | `value` evaluates to `'hello'`; call `JSValueBridge.stringOptionalField(value)`. | Returns `"hello"` (`JSValueBridgeTests.aStringFieldIsRead`). |
| js-value-bridge-012 | string-field-empty-is-a-value | `value` evaluates to `''`; call `JSValueBridge.stringOptionalField(value)`. | Returns `""`, not `nil` (`JSValueBridgeTests.anEmptyStringFieldIsRead`). |
| js-value-bridge-013 | string-field-read-without-coercion | `value` evaluates in turn to `42`, `true`, `({})`, `[]`, `(function () {})`, `null`, and `undefined`; call `JSValueBridge.stringOptionalField(value)` for each. | Returns `nil` for every one — never a coerced string (`JSValueBridgeTests.nonStringsAreNotCoerced`). |
| js-value-bridge-014 | string-field-read-without-coercion | `options = ({ ignoreFocusOut: true })`; call `JSValueBridge.stringOptionalField(options.objectForKeyedSubscript("placeHolder"))`. | Returns `nil` — a property that was never set reads as no constraint (`JSValueBridgeTests.anAbsentFieldIsNoConstraint`). |
| js-value-bridge-015 | string-field-read-without-coercion | Call `JSValueBridge.stringOptionalField(nil)`. | Returns `nil` (`JSValueBridgeTests.aMissingOperandIsNoConstraint`). |
| js-value-bridge-016 | no-actor-isolation-declared | Any `@MainActor`-isolated call site in this directory (e.g. `MainThreadWindow.swift`'s `showInputBox` handler) calls `JSValueBridge.undefinedOrNull(in:)` synchronously. | Compiles with no actor-isolation diagnostic, because `JSValueBridge` declares no conflicting isolation and its `JSContext`/`JSValue` arguments stay in the caller's own domain (verified by inspection: `JSValueBridge.swift` carries no `@MainActor`/`Sendable`/`actor` annotation; every real call site — `VSCodeAPI`, `MainThreadWindow`, `MainThreadWorkspace`, `MainThreadDiagnostics`, `MainThreadLanguageModels`, `MainThreadWebviews`, `MainThreadTreeViews` — is itself `@MainActor`). |

## Edge Cases

- **Null/empty input**: an empty `values` array to `array(of:in:)`/`arrayOrNull(of:in:)` MUST produce an empty JavaScript array, never `undefined`/`NSNull()` (**empty-array-is-empty-not-missing**). The empty string to `stringOrNull(_:in:)` or `stringOptionalField(_:)` MUST be treated as a real value, not an absence (**string-or-null-value**, **string-field-empty-is-a-value**). A `nil` operand to `stringOptionalField(_:)` (no property at all was passed) MUST return `nil` (**string-field-read-without-coercion**).
- **Boundary values**: not applicable — no function in this file constrains `values`, `message`, or `path` to a minimum or maximum length, count, or numeric range; none is declared in the source.
- **Concurrent access**: not applicable to `JSValueBridge` itself — it holds no stored state and every member is a pure function of its arguments (**pure-value-construction**), so there is nothing for two calls to race over. Its `JSContext`/`JSValue` parameters are non-Sendable classes, so the Swift compiler already confines any one instance of them to whichever isolation domain created it before this bridge is ever called (**no-actor-isolation-declared**); every real call site in this codebase happens to be `@MainActor`.
- **Error states**: when the underlying JavaScriptCore constructor (`JSValue(undefinedIn:)`, `JSValue(object:in:)`, or `JSValue(newErrorFromMessage:in:)`) returns `nil`, each `*OrNull`/`Any`-returning member MUST fall back to `NSNull()` and each `JSValue?`-returning member MUST return `nil` (**undefined-value**, **undefined-or-null-value**, **array-construction**, **array-or-null-construction**, **string-or-null-value**). When `reject.context` is `nil` or `JSValue(newErrorFromMessage:in:)` fails, `rejectWithError(_:message:)` MUST take no action and produce no signal to any caller (**reject-with-error-silent-when-context-gone**) — this is documented in the source's own comment as deliberate, not an oversight.
- **Offline/disconnected state**: not applicable — this file performs no network or file-system I/O; every member only constructs or reads in-memory `JSValue` objects already resident in a `JSContext` the caller supplies.

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

## Deep Linking

Not applicable: `JSValueBridge` has no user-facing navigation surface or URL scheme of its own; every member only builds or reads a `JSValue` already resident in a caller-supplied `JSContext`.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal, not externalized) | `{path} is unavailable: this extension's host has been torn down.` | The `Error.message` `rejectTornDown(_:path:)` builds (via `rejectWithError`), delivered to an extension's `Promise.catch` as `error.message`, with `{path}` substituted verbatim by the caller's `path` argument. |

This is a hardcoded English literal with no localization mechanism (no string catalog, no key lookup) anywhere in `JSValueBridge.swift`; see **reject-torn-down-wording** and the `no-hardcoded-strings` row in Compliance.

## Accessibility Options

Not applicable: `JSValueBridge` renders no UI and has no motion, contrast, or color-differentiation behavior to adapt — it imports only `Foundation` and `JavaScriptCore`.

## Feature Flags

Not applicable: no feature flag or `{{app_prefix}}`-keyed toggle gates any member of this file; every function is unconditionally available for any `JSContext` a caller supplies.

## Analytics

Not applicable: `JSValueBridge.swift` contains no analytics event, telemetry call, or event-name literal of any kind.

## Privacy

Not applicable: `JSValueBridge` stores nothing and transmits nothing off-device — it only constructs or reads in-memory `JSValue` objects for the duration of one call, and holds no credential, token, or persistent state.

## Logging

Not applicable: `JSValueBridge.swift` makes no logging call of its own (no `OSLog`/`Logger` reference anywhere in the file); the one branch that cannot report a failure to any caller (**reject-with-error-silent-when-context-gone**) returns silently rather than logging.

## Platform Notes

- **SwiftUI**: not applicable to this file — `JSValueBridge.swift` imports only `Foundation` and `JavaScriptCore`, with no SwiftUI dependency; it renders nothing and observes no view state.
- **AppKit / UIKit**: this is the source. `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/JSValueBridge.swift` is part of the `AgenticToolkitMacOS` framework target, which `project.yml` declares `platform: macOS` for — no iOS target packages this file. It is a caseless `enum`, not itself `@MainActor`, called from seven `@MainActor` types in the same directory — `VSCodeAPI`, `MainThreadWindow`, `MainThreadWorkspace`, `MainThreadDiagnostics`, `MainThreadLanguageModels`, `MainThreadWebviews`, and `MainThreadTreeViews` — each of which builds or reads `JSValue`s through it rather than repeating its five constructions.
- **Compose**: model each member as a top-level function on a plain Kotlin `object` (mirroring the caseless-enum-as-namespace pattern) over whichever embedded JS engine the Android host uses in place of `JSContext`/`JSValue` (e.g. a `V8Object`/`V8Array` pair). Keep the two-return-shape split: `undefined`/`array` return a nullable wrapper for a synchronous result, while `undefinedOrNull`/`arrayOrNull`/`stringOrNull` return `Any?`/`Object` with a null-object fallback for a coroutine `Deferred`/`Promise`-equivalent settlement, per **undefined-value**/**undefined-or-null-value** and **array-construction**/**array-or-null-construction**. Reproduce **string-field-read-without-coercion** with an explicit type check (`is String`) rather than `toString()`.
- **React/Web**: this is closest to the runtime the bridge is emulating — a real VS Code extension already runs directly against a JavaScript engine, so a React/Web host embedding a similar extension bridge would not need most of these helpers at all (there is no second JS-to-native boundary for `undefined`, arrays, or strings to cross). The part worth keeping is the rejection shape: **reject-with-error**, **reject-with-error-has-no-stack**, and **reject-torn-down-wording**, for whatever transport (e.g. a `MessageChannel` to a worker) replaces this file's `JSContext` boundary — an extension's `catch (e)` still needs a real `Error` with a stable `message`.
- **WinUI 3**: model the five constructions as `static` methods on a `JSValueBridge`-equivalent helper class built on whichever embedded JS engine the Windows host runs extensions in (e.g. ClearScript's `V8ScriptEngine`, using `Undefined.Value`/`ScriptObject`/`string` in place of `JSValue`). Map `undefinedOrNull`/`arrayOrNull`/`stringOrNull`'s `Any`-with-`NSNull()`-fallback shape onto `TaskCompletionSource<object>.SetResult(...)` for the `Task`-based promise settlement in place of a JS `Thenable`, and map `rejectWithError`/`rejectTornDown` onto `TaskCompletionSource<object>.SetException(new ScriptEngineException(message))` (or the engine's native JS-`Error`-carrying exception type), so a `.catch`-equivalent still reads a `message` matching **reject-torn-down-wording** exactly. Map `stringOptionalField`'s "read a string only when it truly is one" rule onto refusing anything but a `ScriptObject`/.NET `string` before reading — never `.ToString()` — exactly as **string-field-read-without-coercion** requires.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/JSValueBridge.swift` |

## Design Decisions

**Decision**: Two return shapes exist for equivalent values — `undefined(in:)`/`array(of:in:)` return `JSValue?`, while `undefinedOrNull(in:)`/`arrayOrNull(of:in:)`/`stringOrNull(_:in:)` return `Any` with an `NSNull()` fallback — rather than collapsing to one signature.
**Rationale**: per the source file's own header, a `Promise` settlement takes `Any` and cannot be handed `nil` (an unsettled promise would leave an extension's `await` hanging on a failure it cannot see), so those builders fall back to `NSNull()`; a synchronous member result is `JSValue?`, where `nil` is itself a legitimate answer. Collapsing the two would force every synchronous call site to widen its result to `Any` and then immediately narrow it back. See **undefined-value**/**undefined-or-null-value** and **array-construction**/**array-or-null-construction**.
**Approved**: pending

**Decision**: `JSValueBridge` declares no actor isolation of its own — no `@MainActor`, no `actor`, no `Sendable` — even though every current call site is `@MainActor`.
**Rationale**: the type is a caseless enum with no stored state, so per **pure-value-construction** and **no-actor-isolation-declared** there is nothing to isolate; its `JSContext`/`JSValue` parameters are non-Sendable classes, so the Swift compiler already confines any given instance of them to whichever isolation domain created it before this bridge is called. Declaring `@MainActor` here would add a redundant constraint that a future call site building its own off-main-actor `JSContext` would then have to work around.
**Approved**: pending

**Decision**: `rejectTornDown(_:path:)`'s exact wording is not the only copy of a teardown rejection in this codebase: `MainThreadLanguageModels.swift` rebuilds the same wording in a private `rejectLanguageModelTornDown` function rather than calling `rejectTornDown`, so it can attach the extra `code` property a language-model rejection carries that this bridge's plain `Error` does not.
**Rationale**: recorded here so a future reader of **reject-torn-down-wording** does not assume every `vscode.lm.*` teardown rejection routes through this file. `MainThreadLanguageModels.swift`'s own comment (near its `rejectLanguageModelTornDown` declaration) explains the divergence is deliberate rather than a missed refactor, and this recipe's contract covers only what `JSValueBridge.swift` itself does.
**Approved**: pending

**Decision**: `arrayOrNull(of:in:)` has no dedicated test method in `JSValueBridgeTests.swift`, unlike every other public member of this file.
**Rationale**: its implementation is `JSValue(object: values, in: context) ?? NSNull()`, the same expression `array(of:in:)` already exercises under **array-construction**/**array-construction-is-fresh**, differing only in the `Any` box and the `NSNull()` fallback **array-or-null-construction** requires. Recorded here as a completeness fact traced to the test file itself, per **js-value-bridge-005**, rather than raised as an open question — the behavior is fully specified by the shared implementation and the sibling test on `array(of:in:)`, even though no test method calls `arrayOrNull` directly.
**Approved**: pending

**Decision**: this recipe is deliberately shorter than sibling `extension-host-vs-code-api-*` recipes for stateful adaptors (`MainThreadWindow`, `MainThreadDiagnostics`, and similar).
**Rationale**: `JSValueBridge` is a genuinely smaller component — eight one-line pure functions and no installed JS classes, no state machine, and no `JSContext` lifecycle of its own — so its behavioral surface (fifteen requirements, zero states) is proportionate to its actual scope rather than under-authored, per the cross-recipe-consistency guideline's "genuinely warranted" allowance.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | passed | Security |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |

`separation-of-concerns` passes because this file's only responsibility is building and reading the handful of `JSValue` shapes every `MainThread*` adaptor needs; it does not install JS classes, decode domain types, or manage a `JSContext`'s lifecycle — those responsibilities stay in `VSCodeAPI.swift`, `DiagnosticTypes.swift`, and the individual `MainThread*` files (see Overview). `unit-test-coverage` is partial: `JSValueBridgeTests.swift` has a dedicated test method for every member except `arrayOrNull(of:in:)` (see **js-value-bridge-005** and the fourth Design Decision) — seven of the file's eight members are directly exercised, including both "undefined is not null" spellings, array freshness, empty-array/empty-string-as-value, the rejection's `Error` shape and missing `stack`, the shared teardown wording, and every `stringOptionalField` coercion refusal. `explicit-error-handling` is partial: the primary path is genuinely explicit — `rejectWithError`/`rejectTornDown` deliver real, typed JavaScript `Error` objects with specific messages (**reject-with-error**, **reject-torn-down-wording**) rather than a bare string or a swallowed exception — but the guard-failure branches in `rejectWithError` (`reject.context == nil`, or `JSValue(newErrorFromMessage:in:)` returning `nil`) produce no signal to any caller or log (**reject-with-error-silent-when-context-gone**). `input-sanitization` passes because `stringOptionalField(_:)` refuses to coerce a non-string JavaScript value before reading it — an extension-authored number, object, array, function, `null`, or `undefined` is read as `nil` rather than trusted as a string (**string-field-read-without-coercion**). `no-hardcoded-strings` fails because the teardown message `rejectTornDown(_:path:)` builds is an English literal with no localization mechanism (see Localization).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
