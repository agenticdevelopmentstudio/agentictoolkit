---
id: 724f6428-7dc6-4dab-bb25-834edf488f44
title: Error Message
domain: agentictoolkit://cookbook/status/dashboard/logic/err
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Pure operation that renders any thrown value as a display string: an
  error object''s message, otherwise the value''s standard text conversion'
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

The error-message operation is a one-line pure function. Its doc comment states its whole contract: "Render an unknown thrown value as a display string (Error → message, else String)." Some runtimes let a caught value be of an unconstrained type; the operation narrows any such value to a string a caller can show.

Every caller in the package uses it inside error handling to build a user-visible error string, some prefixing situational context such as "Auto-configure failed: ", "Match failed — " or "Ignore failed — ". The operation owns no state, performs no I/O, and has no side effects.

## Behavioral Requirements

- **accepts-any-thrown-value**: the error-message operation MUST accept a thrown value of any type and MUST return a text value; it MUST NOT reject any input by type.
- **error-message-passthrough**: When the thrown value is an error object (including any specialized error subtype), the operation MUST return its message text unchanged.
- **error-name-omitted**: When the thrown value is an error object, the returned string MUST NOT include the error's type name (for example "TypeError: ") or its stack trace; only the message text is returned.
- **non-error-string-conversion**: When the thrown value is not an error object, the operation MUST return the result of the platform's standard text conversion of that value.
- **string-identity**: When the thrown value is a string, the operation MUST return that same string.
- **nullish-conversion**: When the thrown value is one of the two absent-value tokens `null` or `undefined`, the operation MUST return the literal text `"null"` or `"undefined"` respectively, matching which token was thrown.
- **plain-object-conversion**: When the thrown value is a plain object that is not an error object, the operation MUST return that object's own text-conversion result (which is `"[object Object]"` for an object using the platform's default conversion), even if the object carries a `message` field.
- **instanceof-discrimination**: the operation MUST decide between the two branches by a type check on whether the value is an error object, not by checking for the presence of a `message` field; an error value constructed in a different execution context that this check cannot recognize takes the string-conversion branch instead.
- **no-truncation**: the operation MUST NOT trim, truncate, escape or localize the text it returns.
- **purity**: the operation MUST NOT mutate its input, log, throw on its own, or perform any I/O; the only way it can throw is if the standard text conversion of the input itself throws (see Edge Cases).
- **synchronous**: the operation MUST be synchronous and return its result directly; it has no asynchronous path, no cancellation and no timeout.
- **no-prefixing**: the operation MUST NOT add any prefix or context to the returned text; callers compose context such as "Auto-configure failed: " themselves.

## Appearance

Not applicable — this is a pure string-conversion helper, not a visual component.

## States

Not applicable — this is a pure string-conversion helper, not a visual component.

## Accessibility

Not applicable — this is a pure string-conversion helper, not a visual component.

## Conformance Test Vectors

No test file exists for this module in the source; these vectors are derived from the function body and standard text-conversion semantics.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| err-001 | error-message-passthrough | An error object with message `"boom"` | `"boom"` |
| err-002 | error-message-passthrough, error-name-omitted | A specialized error subtype (type name `TypeError`) with message `"bad arg"` | `"bad arg"` (no "TypeError: " prefix) |
| err-003 | error-message-passthrough | An error object with an empty message | `""` (empty string) |
| err-004 | string-identity, non-error-string-conversion | `"network down"` | `"network down"` |
| err-005 | nullish-conversion | `null` | `"null"` |
| err-006 | nullish-conversion | `undefined` | `"undefined"` |
| err-007 | non-error-string-conversion | `42` | `"42"` |
| err-008 | plain-object-conversion, instanceof-discrimination | `{ message: "x" }` | `"[object Object]"` |
| err-009 | non-error-string-conversion | an object whose text conversion returns `"custom"` | `"custom"` |
| err-010 | purity | an error object, called twice | same string both times; the error object's own fields are unchanged |
| err-011 | no-prefixing, no-truncation | An error object with message `"  padded  "` | `"  padded  "` exactly |
| err-012 | accepts-any-thrown-value | The module | exports a single error-message operation |

## Edge Cases

- **Empty message**: An error object with an empty message MUST yield `""`; the operation does not substitute a fallback, so callers that display it alone show an empty error text.
- **Null and undefined**: A thrown `null` or `undefined` MUST yield "null" or "undefined" as literal text, matching which absent-value token was thrown.
- **Object with a message field**: A non-error object such as a JSON error body `{ message: "..." }` MUST yield "[object Object]"; the `message` field is not read.
- **Value from a different execution context**: An error object constructed in a different execution context that the type check does not recognize as an error MUST take the string branch and yield that context's own default text form for an error, which typically includes the type name, unlike the same-context result.
- **Unconvertible value**: An input whose text conversion itself fails MUST cause the operation to throw that conversion error; the operation does not catch it, so the exception propagates out of the caller's error-handling block.
- **Error subclass overriding message**: An error subclass whose message accessor returns a non-string value MUST have that value returned as-is; the operation does not coerce the message.
- **Concurrent access**: Not applicable — the operation is stateless and pure; concurrent calls cannot interfere with each other.
- **Offline or disconnected state**: Not applicable — the operation performs no network access; it only renders errors that network failures produce elsewhere.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| the thrown value | a value of unconstrained type | none (required) | The thrown value to render. The operation takes no other parameters, environment variables, settings or injected dependencies. |

## Deep Linking

Not applicable: the operation is a string-conversion function with no route, screen or URL.

## Localization

Not applicable: the operation contains no user-facing strings of its own; it returns the thrown value's text verbatim (the caller-side prefixes such as "Auto-configure failed: " are hardcoded English in the calling code, not in this module).

## Accessibility Options

Not applicable: the operation has no visual output and cannot respond to Reduce Motion, Increase Contrast or Differentiate Without Color.

## Feature Flags

Not applicable: the module reads no flag and is always exported unconditionally.

## Analytics

Not applicable: the operation emits no events and calls no analytics API.

## Privacy

Not applicable: the operation collects, stores and transmits nothing; it returns the error text in memory to its caller, and whatever the error message contains is shown unchanged.

## Logging

Not applicable: the operation makes no log call; errors it renders are surfaced by callers through their own state, not through a logger.

## Platform Notes

- **SwiftUI**: Start from a free function `func msg(_ error: any Error) -> String` returning `error.localizedDescription`, or `String(describing:)` for the general case. Swift `catch` always binds an `Error`, so the non-Error branch collapses; decide whether `localizedDescription` (which may be localized and wrapped by Foundation) or `String(describing: error)` best matches "message only".
- **Compose**: A Kotlin top-level function `fun msg(e: Throwable): String = e.message ?: e.toString()`. Kotlin can only throw `Throwable`, and `message` is nullable, so the port needs an explicit null fallback that the source does not have (the source returns `""` for an empty message and never sees a null one).
- **React/Web**: The source platform. `packages/web/packages/status-web/src/lib/err.ts` is the whole implementation. The module exports a single function named `msg`, taking one parameter `e` of type `unknown` and returning `string`; it relies on TypeScript's `useUnknownInCatchVariables` so `catch (e)` is `unknown`, and on `instanceof Error` for narrowing. `null` and `undefined` are two distinct absent-value tokens in JavaScript, which is why the nullish-conversion requirement has two literal outputs; most ports have only one absent-value concept and need only one fallback text. "A different execution context" means another realm (an iframe or a worker): an `Error` constructed there fails the same-realm `instanceof Error` check and takes the string branch, yielding the standard `Error` string form ("Error: boom"). A thrown `Symbol("x")` yields "Symbol(x)", since `String()` converts symbols without throwing — Symbol has no equivalent in the other target languages, so a port has nothing to handle here. An object with no prototype (`Object.create(null)`) or whose `toString` throws causes `msg` to throw that conversion error, uncaught. Because TypeScript's `string` return type is not enforced at runtime, an `Error` subclass whose `message` getter returns a non-string value passes it through unchanged. Callers are `AutoConfigureProvider.tsx`, `ConfigPanel.tsx`, `configure/use-editor-mutations.ts` and `configure/PlatformProjects.tsx`, each feeding the result into React state. The operation is stateless and runs on the single JavaScript thread, so concurrent calls cannot interfere.
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

The helper is pure and framework-free, separated from the components that display its output, so separation-of-concerns passes. Unit-test-coverage fails: the source has test files for most sibling modules but none for this one, so the behavior above is asserted by no test in the source. Explicit-error-handling passes because the operation swallows nothing: it converts the value it is given and lets a failing conversion propagate rather than hiding it.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to status/dashboard/logic/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation from `packages/web/packages/status-web/src/lib/err.ts` |
