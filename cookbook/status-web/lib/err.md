---
id: 724f6428-7dc6-4dab-bb25-834edf488f44
title: Error Message
domain: agentictoolkit://cookbook/status-web/lib/err
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Pure helper that renders any thrown value as a display string: an Error''s
  message, otherwise the value''s String conversion'
platforms:
- typescript
- web
tags: []
depends-on: []
related: []
references: []
approved-by: ''
approved-date: ''
---

# Error Message

## Overview

`msg` is a one-line pure function in the status-web package (`packages/web/packages/status-web/src/lib/err.ts`). Its doc comment states its whole contract: "Render an unknown thrown value as a display string (Error → message, else String)." JavaScript lets any value be thrown, so a `catch` clause receives `unknown`; `msg` narrows that value to a string a caller can show.

Every caller in the package uses it inside a `catch` block to build a user-visible error string: `AutoConfigureProvider.tsx` (prefixing "Auto-configure failed: "), `ConfigPanel.tsx` (the refresh error), `configure/use-editor-mutations.ts` (the editor error), and `configure/PlatformProjects.tsx` (prefixing "Match failed — ", "Ignore failed — " and similar). The function owns no state, performs no I/O, and has no side effects.

## Behavioral Requirements

- **export-name**: The module MUST export a single function named `msg` taking one parameter `e` of type `unknown` and returning `string`.
- **error-message-passthrough**: When `e` is an instance of `Error` (including any subclass such as `TypeError`), `msg` MUST return `e.message` unchanged.
- **error-name-omitted**: When `e` is an `Error`, the returned string MUST NOT include the error's `name` (for example "TypeError: ") or its stack; only `message` is returned.
- **non-error-string-conversion**: When `e` is not an instance of `Error`, `msg` MUST return the result of the language's standard string conversion of `e` (`String(e)`).
- **string-identity**: When `e` is a string, `msg` MUST return that same string.
- **nullish-conversion**: When `e` is `null` or `undefined`, `msg` MUST return the literal text "null" or "undefined" respectively.
- **plain-object-conversion**: When `e` is a plain object that is not an `Error`, `msg` MUST return the object's string conversion (for an object with the default `toString`, "[object Object]"), even if the object carries a `message` property.
- **instanceof-discrimination**: `msg` MUST decide between the two branches by an `instanceof Error` check, not by duck-typing on a `message` property; an `Error` created in another realm (iframe, worker) fails that check and takes the string-conversion branch.
- **no-truncation**: `msg` MUST NOT trim, truncate, escape or localize the text it returns.
- **purity**: `msg` MUST NOT mutate `e`, log, throw on its own, or perform any I/O; the only way it can throw is if the standard string conversion of `e` throws (see Edge Cases).
- **synchronous**: `msg` MUST be synchronous and return its result directly; it has no asynchronous path, no cancellation and no timeout.
- **no-prefixing**: `msg` MUST NOT add any prefix or context to the returned text; callers compose context such as "Auto-configure failed: " themselves.

## Appearance

Not applicable — this is a pure string-conversion helper, not a visual component.

## States

Not applicable — this is a pure string-conversion helper, not a visual component.

## Accessibility

Not applicable — this is a pure string-conversion helper, not a visual component.

## Conformance Test Vectors

No test file exists for `err.ts` in the source (`src/lib` has no `err.test.ts`); these vectors are derived from the function body and standard `String` conversion semantics.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| err-001 | error-message-passthrough | `new Error("boom")` | `"boom"` |
| err-002 | error-message-passthrough, error-name-omitted | `new TypeError("bad arg")` | `"bad arg"` (no "TypeError: " prefix) |
| err-003 | error-message-passthrough | `new Error("")` | `""` (empty string) |
| err-004 | string-identity, non-error-string-conversion | `"network down"` | `"network down"` |
| err-005 | nullish-conversion | `null` | `"null"` |
| err-006 | nullish-conversion | `undefined` | `"undefined"` |
| err-007 | non-error-string-conversion | `42` | `"42"` |
| err-008 | plain-object-conversion, instanceof-discrimination | `{ message: "x" }` | `"[object Object]"` |
| err-009 | non-error-string-conversion | an object whose `toString` returns `"custom"` | `"custom"` |
| err-010 | purity | an `Error` instance, called twice | same string both times; the error object's own properties are unchanged |
| err-011 | no-prefixing, no-truncation | `new Error("  padded  ")` | `"  padded  "` exactly |
| err-012 | export-name | import from `lib/err` | a function named `msg` is exported |

## Edge Cases

- **Empty message**: An `Error` with an empty `message` MUST yield `""`; `msg` does not substitute a fallback, so callers that display it alone (for example `ConfigPanel.tsx` setting the refresh error to `msg(e)`) show an empty error text.
- **Null and undefined**: A thrown `null` or `undefined` MUST yield "null" or "undefined" as literal text.
- **Object with a message field**: A non-`Error` object such as a JSON error body `{ message: "..." }` MUST yield "[object Object]"; the `message` field is not read.
- **Cross-realm Error**: An `Error` constructed in another realm MUST take the string branch and yield the standard `Error` string form ("Error: boom"), which includes the name, unlike the same-realm result.
- **Symbol**: A thrown `Symbol("x")` MUST yield "Symbol(x)", since `String` converts symbols without throwing.
- **Unconvertible value**: An object with no prototype (`Object.create(null)`) or whose `toString` throws MUST cause `msg` to throw the conversion error; `msg` does not catch it, so the exception propagates out of the caller's `catch` block.
- **Error subclass overriding message**: An `Error` subclass whose `message` getter returns a non-string MUST have that value returned as-is; `msg` does not coerce `message`, and the `string` return type is not enforced at runtime.
- **Concurrent access**: Not applicable — `msg` is a stateless pure function in single-threaded JavaScript; concurrent calls cannot interfere.
- **Offline or disconnected state**: Not applicable — `msg` performs no network access; it only renders errors that network failures produce elsewhere.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `e` | `unknown` | none (required) | The thrown value to render. `msg` takes no other parameters, environment variables, settings or injected dependencies. |

## Deep Linking

Not applicable: `msg` is a string-conversion function with no route, screen or URL.

## Localization

Not applicable: `msg` contains no user-facing strings of its own; it returns the thrown value's text verbatim (the caller-side prefixes such as "Auto-configure failed: " are hardcoded English in the calling components, not in this module).

## Accessibility Options

Not applicable: `msg` has no visual output and cannot respond to Reduce Motion, Increase Contrast or Differentiate Without Color.

## Feature Flags

Not applicable: `err.ts` reads no flag and is always exported unconditionally.

## Analytics

Not applicable: `msg` emits no events and calls no analytics API.

## Privacy

Not applicable: `msg` collects, stores and transmits nothing; it returns the error text in memory to its caller, and whatever the error message contains is shown unchanged.

## Logging

Not applicable: `msg` makes no log call; errors it renders are surfaced by callers through component state (for example `setError`, `setMessage`), not through a logger.

## Platform Notes

- **SwiftUI**: Start from a free function `func msg(_ error: any Error) -> String` returning `error.localizedDescription`, or `String(describing:)` for the general case. Swift `catch` always binds an `Error`, so the non-Error branch collapses; decide whether `localizedDescription` (which may be localized and wrapped by Foundation) or `String(describing: error)` best matches "message only".
- **Compose**: A Kotlin top-level function `fun msg(e: Throwable): String = e.message ?: e.toString()`. Kotlin can only throw `Throwable`, and `message` is nullable, so the port needs an explicit null fallback that the source does not have (the source returns `""` for an empty message and never sees a null one).
- **React/Web**: The source platform. `packages/web/packages/status-web/src/lib/err.ts` is the whole implementation; it relies on TypeScript's `useUnknownInCatchVariables` so `catch (e)` is `unknown`, and on `instanceof Error` for narrowing. Callers are `AutoConfigureProvider.tsx`, `ConfigPanel.tsx`, `configure/use-editor-mutations.ts` and `configure/PlatformProjects.tsx`, each feeding the result into React state.
- **AppKit / UIKit**: Same as SwiftUI; for `NSError` values, `localizedDescription` is the conventional display text, and bridged Objective-C exceptions (`NSException`) are not catchable as Swift errors, so they fall outside the port.
- **WinUI 3**: A C# static method `public static string Msg(object? e) => e is Exception ex ? ex.Message : e?.ToString() ?? "null";` in a shared utility class. C# `catch` only yields `System.Exception`, so in practice callers pass `ex` and read `ex.Message`; the `object` overload exists only to match the source's two branches. Note that `Exception.Message` for many framework exceptions is localized by the OS culture, unlike the source; set the result on a view-model property that implements `INotifyPropertyChanged` for binding to an `InfoBar.Message` or `TextBlock.Text`, which is how the source's callers route it into React state.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/lib/err.ts` |

## Design Decisions

**Decision**: Return only `Error.message`, not `name` or `stack`.
**Rationale**: The doc comment says "Error → message"; callers already supply context ("Match failed — "), so the error class name would be noise in a display string.
**Approved**: pending

**Decision**: Use `String(e)` for every non-Error value instead of inspecting objects for a `message` field.
**Rationale**: The doc comment specifies "else String"; this keeps the function total and trivially predictable, at the cost of rendering error-shaped plain objects as "[object Object]" (see plain-object-conversion).
**Approved**: pending

**Decision**: Keep the helper in `src/lib` as a shared module rather than inlining the expression in each component.
**Rationale**: Four components need the same narrowing of `unknown` catch values; one shared function keeps the rendering rule identical across them.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | failed | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | best-practices |

The helper is pure and framework-free, separated from the React components that display its output, so separation-of-concerns passes. Unit-test-coverage fails: `src/lib` has test files for most sibling modules but none for `err.ts`, so the behavior above is asserted by no test in the source. Explicit-error-handling passes because `msg` swallows nothing: it converts the value it is given and lets a failing string conversion propagate rather than hiding it.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation from `packages/web/packages/status-web/src/lib/err.ts` |
