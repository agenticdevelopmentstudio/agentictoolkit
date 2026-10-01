---
id: cb25bd84-9a11-4070-8b3c-f178cff76068
title: JavaScript Value Bridge
domain: agentictoolkit://cookbook/workspace/extensions/host/js-value-bridge
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Shared JavaScript value constructions and Promise-rejection builders every
  vscode-namespace adaptor in the extension host uses instead of its own copy.
platforms:
- swift
- macos
tags:
- extension-host
- vscode-api
- bridge
depends-on: []
related:
- agentictoolkit://cookbook/workspace/extensions/host/extension-event
- agentictoolkit://cookbook/workspace/extensions/vscode-api/window/extension-input-box-presenting
- agentictoolkit://cookbook/workspace/extensions/vscode-api/window/extension-status-bar-presenting
- agentictoolkit://cookbook/workspace/extensions/vscode-api/language-models/ai-plugin-language-model-provider
- agentictoolkit://cookbook/workspace/extensions/vscode-api/window/extension-quick-pick-presenting
- agentictoolkit://cookbook/workspace/extensions/vscode-api/tree-views/extension-tree-data-source
- agentictoolkit://cookbook/workspace/extensions/vscode-api/window/extension-message-presenting
- agentictoolkit://cookbook/workspace/extensions/vscode-api/webviews/extension-webview-presenting
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

# JavaScript Value Bridge

## Overview

This bridge is a stateless namespace holding the handful of one-line JavaScript value constructions every vscode-namespace adaptor needs: building a genuine JavaScript `undefined`, an array, or a string to hand back into a JavaScript execution context, and rejecting a `Promise`'s `reject` callback with a real JavaScript `Error`. Each of these constructions used to exist two or three times over, duplicated individually inside several adaptors; this bridge is the one reachable home all of them now call through instead. It also holds one read-side helper: pulling a string out of an optional JavaScript-value property only when that property is genuinely a JavaScript string, never a coercion of one. The bridge declares no state and no confinement of its own — every member is a pure function of its arguments — and it is not an abstract interface, because there is nothing here to substitute.

## Behavioral Requirements

- **pure-value-construction**: The bridge MUST NOT declare or retain any stored state across calls; every member MUST be a pure function of its arguments, since it is declared as a stateless namespace with no stored properties.
- **confinement-left-to-call-site**: The bridge MUST NOT declare any exclusive-execution-context or safe-to-share annotation on itself; each call site remains solely responsible for confining its call to whatever execution context already holds the JavaScript execution context/value arguments it passes in, because those underlying JavaScript-engine and platform types are reference types the compiler already keeps confined to their creating context.
- **undefined-value**: Building an undefined value MUST return a JavaScript value wrapping a genuine JavaScript `undefined`, or an absent result if the underlying construction itself fails, for a synchronous member result where an absent result is itself a legitimate answer.
- **undefined-or-null-value**: Building an undefined-or-null value MUST return the same JavaScript `undefined` value building an undefined value builds, boxed generically, and MUST fall back to a JavaScript `null` value only when the underlying construction itself fails, for a `Promise` settlement, which has no way to accept an absent result.
- **array-construction**: Building an array MUST return a JavaScript array holding exactly the elements of `values` in their given order, or an absent result if the underlying construction fails, for a synchronous member result.
- **array-construction-is-fresh**: Building an array MUST build a new JavaScript array object on every call; mutating the array returned by one call MUST NOT change the array returned by any other call, even when both calls are given the same `values`.
- **array-or-null-construction**: Building an array-or-null value MUST return the same array building an array would build for the same `values` and execution context, boxed generically, and MUST fall back to a JavaScript `null` value only when the underlying construction fails, for a `Promise` settlement.
- **empty-array-is-empty-not-missing**: Building an array and building an array-or-null value MUST return an empty JavaScript array of length `0`, never `undefined` and never an absent result or JavaScript `null`, when `values` is an empty array.
- **string-or-null-value**: Building a string-or-null value MUST return a JavaScript string carrying exactly the characters of `value`, boxed generically, including when `value` is the empty string, and MUST fall back to a JavaScript `null` value only when the underlying construction fails.
- **reject-with-error**: Rejecting with an error MUST call `reject` with a single argument that is a JavaScript `Error` instance built in `reject`'s own execution context, whose `message` property equals `message` and whose `name` property equals `"Error"`.
- **reject-with-error-has-no-stack**: The `Error` that rejecting with an error builds MUST NOT carry a populated `stack` property (JavaScript `typeof error.stack` MUST evaluate to `"undefined"`), because the underlying construction builds the object directly rather than throwing it from JavaScript, leaving no frame to record.
- **reject-with-error-silent-when-context-gone**: Rejecting with an error MUST take no action and MUST NOT call `reject` when `reject`'s own execution context is gone, or when the underlying error construction itself fails; there is nothing left to reject into once `reject`'s context is gone, so this path produces no signal to any caller.
- **reject-torn-down-wording**: Rejecting for a torn-down host MUST reject `reject` (via rejecting with an error) with the message `"<path> is unavailable: this extension's host has been torn down."`, substituting `path` verbatim, so every vscode-namespace adaptor built on this bridge reports teardown with one shared wording.
- **string-field-read-without-coercion**: Reading a string field MUST return `value`'s string contents only when `value` is present and is genuinely a JavaScript string; it MUST return an absent result for an absent operand, and MUST return an absent result — never a coerced string — when `value` holds a JavaScript number, boolean, object, array, function, `null`, or `undefined`.
- **string-field-empty-is-a-value**: Reading a string field MUST return the empty string `""`, not an absent result, when `value` holds a JavaScript string whose contents are empty.

## Appearance

Not applicable — this is a pure-function JavaScript value construction/reading bridge, not a visual component.

## States

Not applicable — this is a pure-function JavaScript value construction/reading bridge, not a visual component.

## Accessibility

Not applicable — this is a pure-function JavaScript value construction/reading bridge, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|--------------|-------|----------|
| js-value-bridge-001 | undefined-value | A live JavaScript execution context; build an undefined value. | Returns a present JavaScript value; `built.isUndefined == true` and `built.isNull == false` (`JSValueBridgeTests.undefinedIsUndefined`). |
| js-value-bridge-002 | undefined-or-null-value | A live JavaScript execution context; build an undefined-or-null value. | Returns a value castable to a JavaScript value; `isUndefined == true` and `isNull == false` (`JSValueBridgeTests.undefinedOrNullIsUndefinedInPractice`). |
| js-value-bridge-003 | array-construction, array-construction-is-fresh, pure-value-construction | `items = ['a', 'b']` as JavaScript string values; build an array from them twice, keeping both results. | Both results are real arrays: `Array.isArray` true, `length == 2`, `join('') == "ab"`. `first.push('mutated')` leaves `first.length == 2` but `second.length == 1`; `first === second` is `false` (`JSValueBridgeTests.arrayBridgesToAJavaScriptArray`, `.eachCallBridgesItsOwnArray`). |
| js-value-bridge-004 | empty-array-is-empty-not-missing | `values = []`; build an array from the empty list. | `Array.isArray` true, `length == 0` — an empty array, not `undefined` (`JSValueBridgeTests.anEmptyArrayIsStillAnArray`). |
| js-value-bridge-005 | array-or-null-construction | `objects = ['a']` as a JavaScript string value; build an array-or-null value from them. | Returns a value castable to a JavaScript value; `Array.isArray` true, `length == 1`, contents equal building an array's result for the same input — traced to the shared construction expression in the source (no dedicated test method exists for this member; see Design Decisions). |
| js-value-bridge-006 | string-or-null-value | `value = ""`; build a string-or-null value from it. | Returns a value castable to a JavaScript value; `isString == true`, `toString() == ""` — the empty string is a value, not an absence (`JSValueBridgeTests.theEmptyStringIsAValue`). |
| js-value-bridge-007 | string-or-null-value | `value = "a'b\"c\\d😀"`; build a string-or-null value from it. | `toString()` equals the exact input, quotes/backslash/emoji intact (`JSValueBridgeTests.aStringKeepsItsContents`). |
| js-value-bridge-008 | reject-with-error, reject-with-error-has-no-stack | A JS `reject` function that captures its argument as `caught`; reject with an error, passing the message "the host said no". | `caught instanceof Error` true; `caught.name == "Error"`; `caught.message == "the host said no"`; `typeof caught.stack == "undefined"` (`JSValueBridgeTests.aRejectionCarriesAnError`, `.aRejectionHasNoStack`). |
| js-value-bridge-009 | reject-with-error-silent-when-context-gone | A `reject` value whose execution context has already been released; reject with an error, passing the message "the host said no". | `reject` is never invoked and no crash occurs — traced to the context-presence guard in the source (no dedicated test exists for this branch; the guard is exercised only structurally). |
| js-value-bridge-010 | reject-torn-down-wording | A captured `reject`; reject for a torn-down host, passing the path "vscode.window.showInputBox". | `caught.message` contains "vscode.window.showInputBox" and contains "torn down" (`JSValueBridgeTests.aTornDownRejectionNamesThePath`). |
| js-value-bridge-011 | string-field-read-without-coercion | `value` evaluates to `'hello'`; read it as a string field. | Returns `"hello"` (`JSValueBridgeTests.aStringFieldIsRead`). |
| js-value-bridge-012 | string-field-empty-is-a-value | `value` evaluates to `''`; read it as a string field. | Returns `""`, not an absent result (`JSValueBridgeTests.anEmptyStringFieldIsRead`). |
| js-value-bridge-013 | string-field-read-without-coercion | `value` evaluates in turn to `42`, `true`, `({})`, `[]`, `(function () {})`, `null`, and `undefined`; read each as a string field. | Returns an absent result for every one — never a coerced string (`JSValueBridgeTests.nonStringsAreNotCoerced`). |
| js-value-bridge-014 | string-field-read-without-coercion | `options = ({ ignoreFocusOut: true })`; read its (unset) `placeHolder` property as a string field. | Returns an absent result — a property that was never set reads as no constraint (`JSValueBridgeTests.anAbsentFieldIsNoConstraint`). |
| js-value-bridge-015 | string-field-read-without-coercion | Read an absent operand as a string field. | Returns an absent result (`JSValueBridgeTests.aMissingOperandIsNoConstraint`). |
| js-value-bridge-016 | confinement-left-to-call-site | Any call site confined to a single execution context (e.g. the input-box handler in this directory) calls building an undefined-or-null value synchronously. | Compiles and runs with no confinement conflict, because the bridge declares no conflicting confinement and its JavaScript execution context/value arguments stay in the caller's own context (verified by inspection: the bridge declares no exclusive-execution-context or safe-to-share annotation; every real call site is itself confined to a single execution context). |

## Edge Cases

- **Null/empty input**: an empty `values` array to building an array/building an array-or-null value MUST produce an empty JavaScript array, never `undefined`/JavaScript `null` (**empty-array-is-empty-not-missing**). The empty string to building a string-or-null value or reading a string field MUST be treated as a real value, not an absence (**string-or-null-value**, **string-field-empty-is-a-value**). An absent operand to reading a string field (no property at all was passed) MUST return an absent result (**string-field-read-without-coercion**).
- **Boundary values**: not applicable — no member in this component constrains `values`, `message`, or `path` to a minimum or maximum length, count, or numeric range; none is declared in the source.
- **Concurrent access**: not applicable to the bridge itself — it holds no stored state and every member is a pure function of its arguments (**pure-value-construction**), so there is nothing for two calls to race over. Its JavaScript execution context/value parameters are reference types, so the underlying platform already confines any one instance of them to whichever execution context created it before this bridge is ever called (**confinement-left-to-call-site**); every real call site in this codebase happens to be confined to a single execution context.
- **Error states**: when the underlying JavaScript-engine construction fails, each generically-boxed member MUST fall back to a JavaScript `null` value and each optional-result member MUST return an absent result (**undefined-value**, **undefined-or-null-value**, **array-construction**, **array-or-null-construction**, **string-or-null-value**). When `reject`'s own execution context is gone or the underlying error construction fails, rejecting with an error MUST take no action and produce no signal to any caller (**reject-with-error-silent-when-context-gone**) — this is documented in the source's own comment as deliberate, not an oversight.
- **Offline/disconnected state**: not applicable — this component performs no network or file-system I/O; every member only constructs or reads in-memory JavaScript values already resident in an execution context the caller supplies.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| execution context | JavaScript execution context | (required, no default) | The JavaScript execution context a value is built in, or that a rejection's `Error` is built in via `reject`'s own context. Every caller supplies its own live extension-host context. |
| values | ordered list of JavaScript values | (required, no default) | The ordered JavaScript values that building an array/building an array-or-null value bridge into a new JavaScript array. |
| value (string builder) | string | (required, no default) | The string that building a string-or-null value bridges into a JavaScript string, including the empty string. |
| value (field reader) | optional JavaScript value | (required, no default; an absent operand is valid) | The property reading a string field reads without coercion; an absent operand represents "no operand was supplied at all." |
| reject | JavaScript value | (required, no default) | The JavaScript `reject` callback of a `Promise` that rejecting with an error/rejecting for a torn-down host invokes with a JavaScript `Error`. |
| message | string | (required, no default) | The literal text rejecting with an error writes into the built `Error`'s `message` property. |
| path | string | (required, no default) | The dotted `vscode.*` member path rejecting for a torn-down host embeds verbatim into its fixed teardown wording. |

## Deep Linking

Not applicable: this bridge has no user-facing navigation surface or URL scheme of its own; every member only builds or reads a JavaScript value already resident in a caller-supplied execution context.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal, not externalized) | `{path} is unavailable: this extension's host has been torn down.` | The `Error.message` rejecting for a torn-down host builds (via rejecting with an error), delivered to an extension's `Promise.catch` as `error.message`, with `{path}` substituted verbatim by the caller's `path` argument. |

This is a hardcoded English literal with no localization mechanism (no string catalog, no key lookup) anywhere in the source; see **reject-torn-down-wording** and the `no-hardcoded-strings` row in Compliance.

## Accessibility Options

Not applicable: this bridge renders no UI and has no motion, contrast, or color-differentiation behavior to adapt — it depends only on foundational platform types and the JavaScript engine binding.

## Feature Flags

Not applicable: no feature flag or `{{app_prefix}}`-keyed toggle gates any member of this component; every function is unconditionally available for any execution context a caller supplies.

## Analytics

Not applicable: this component contains no analytics event, telemetry call, or event-name literal of any kind.

## Privacy

Not applicable: this bridge stores nothing and transmits nothing off-device — it only constructs or reads in-memory JavaScript values for the duration of one call, and holds no credential, token, or persistent state.

## Logging

Not applicable: this component makes no logging call of its own; the one branch that cannot report a failure to any caller (**reject-with-error-silent-when-context-gone**) returns silently rather than logging.

## Platform Notes

- **SwiftUI**: not applicable to this file — depends only on foundational platform types and the JavaScript engine binding, with no SwiftUI dependency; it renders nothing and observes no view state.
- **AppKit / UIKit**: this is the source. `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/JSValueBridge.swift` is part of the `AgenticToolkitMacOS` framework target, which `project.yml` declares `platform: macOS` for — no iOS target packages this file. `JSValueBridge` is the type this bridge is named for in source: a caseless `enum`, not itself `@MainActor`, called from seven `@MainActor` types in the same directory — `VSCodeAPI`, `MainThreadWindow`, `MainThreadWorkspace`, `MainThreadDiagnostics`, `MainThreadLanguageModels`, `MainThreadWebviews`, and `MainThreadTreeViews` — each of which builds or reads `JSValue`s through it rather than repeating its five constructions. "JavaScript execution context" and "JavaScript value" are `JavaScriptCore.JSContext` and `JavaScriptCore.JSValue`; "exclusive-execution-context or safe-to-share annotation" refers to Swift's `@MainActor`/`actor`/`Sendable` markers, none of which this type declares. Building an undefined value is `undefined(in:)`, built via `JSValue(undefinedIn:)`; building an array is `array(of:in:)`, built via `JSValue(object:values,in:context)`; building a string-or-null value is `stringOrNull(_:in:)`, built via `JSValue(object:value,in:context)`; rejecting with an error is `rejectWithError(_:message:)`, building the `Error` via `JSValue(newErrorFromMessage:message,in:context)`; the *-or-null members (`undefinedOrNull(in:)`, `arrayOrNull(of:in:)`) box their result as `Any` with an `NSNull()` fallback; rejecting for a torn-down host is `rejectTornDown(_:path:)`. Reading a string field is `stringOptionalField(_:)`, reading a `JSValue?`'s `.isString`/Swift `String` contents without coercion.
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
**Rationale**: the type is a caseless enum with no stored state, so per **pure-value-construction** and **confinement-left-to-call-site** there is nothing to isolate; its `JSContext`/`JSValue` parameters are non-Sendable classes, so the Swift compiler already confines any given instance of them to whichever isolation domain created it before this bridge is called. Declaring `@MainActor` here would add a redundant constraint that a future call site building its own off-main-actor `JSContext` would then have to work around.
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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/extensions/host/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
