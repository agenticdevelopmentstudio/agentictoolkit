<!-- leaf: implement-status-web-src-lib-1/err · source: status-web-src-lib-err.md -->

**Rules** (cite as `implement-status-web-src-lib-1/err#<slug>`):

- `export-name` MUST
- `error-message-passthrough` MUST
- `error-name-omitted` MUST
- `non-error-string-conversion` MUST
- `string-identity` MUST
- `nullish-conversion` MUST
- `plain-object-conversion` MUST
- `instanceof-discrimination` MUST
- `no-truncation` MUST
- `purity` MUST
- `synchronous` MUST
- `no-prefixing` MUST

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `e` | `unknown` | none (required) | The thrown value to render. `msg` takes no other parameters, environment variables, settings or injected dependencies. |

## Platform Notes

- **SwiftUI**: Start from a free function `func msg(_ error: any Error) -> String` returning `error.localizedDescription`, or `String(describing:)` for the general case. Swift `catch` always binds an `Error`, so the non-Error branch collapses; decide whether `localizedDescription` (which may be localized and wrapped by Foundation) or `String(describing: error)` best matches "message only".
- **Compose**: A Kotlin top-level function `fun msg(e: Throwable): String = e.message ?: e.toString()`. Kotlin can only throw `Throwable`, and `message` is nullable, so the port needs an explicit null fallback that the source does not have (the source returns `""` for an empty message and never sees a null one).
- **React/Web**: The source platform. `packages/web/packages/status-web/src/lib/err.ts` is the whole implementation; it relies on TypeScript's `useUnknownInCatchVariables` so `catch (e)` is `unknown`, and on `instanceof Error` for narrowing. Callers are `AutoConfigureProvider.tsx`, `ConfigPanel.tsx`, `configure/use-editor-mutations.ts` and `configure/PlatformProjects.tsx`, each feeding the result into React state.
- **AppKit / UIKit**: Same as SwiftUI; for `NSError` values, `localizedDescription` is the conventional display text, and bridged Objective-C exceptions (`NSException`) are not catchable as Swift errors, so they fall outside the port.
- **WinUI 3**: A C# static method `public static string Msg(object? e) => e is Exception ex ? ex.Message : e?.ToString() ?? "null";` in a shared utility class. C# `catch` only yields `System.Exception`, so in practice callers pass `ex` and read `ex.Message`; the `object` overload exists only to match the source's two branches. Note that `Exception.Message` for many framework exceptions is localized by the OS culture, unlike the source; set the result on a view-model property that implements `INotifyPropertyChanged` for binding to an `InfoBar.Message` or `TextBlock.Text`, which is how the source's callers route it into React state.

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
