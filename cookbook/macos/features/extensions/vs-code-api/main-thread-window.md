---
id: 7fc91996-6f04-415c-9119-fc6f9fccccd4
domain: agentictoolkit://cookbook/macos/features/extensions/vs-code-api/main-thread-window
title: MainThreadWindow
summary: The vscode.window adaptor for show*Message, showQuickPick, showInputBox and
  createStatusBarItem, dispatching each to an injected presenter and recording unimplemented
  member shapes to NotImplementedLedger.
version: 1.0.1
status: review
platforms:
- swift
- macos
tags:
- extension-host
- vscode-api
- window
- message-presenting
- quick-pick
- input-box
- status-bar
- javascriptcore
- mainactor
related:
- agentictoolkit://cookbook/macos/features/extensions/vs-code-api/main-thread-commands
- agentictoolkit://cookbook/macos/features/extensions/vs-code-api/extension-message-presenting
- agentictoolkit://cookbook/macos/features/extensions/vs-code-api/extension-quick-pick-presenting
- agentictoolkit://cookbook/macos/features/extensions/vs-code-api/extension-input-box-presenting
- agentictoolkit://cookbook/macos/features/extensions/vs-code-api/extension-status-bar-presenting
- agentictoolkit://cookbook/macos/features/extensions/vs-code-api/js-value-bridge
references:
- MainThreadWindow.swift (agentictoolkit)
- ExtensionMessagePresenting.swift (agentictoolkit)
- ExtensionQuickPickPresenting.swift (agentictoolkit)
- ExtensionInputBoxPresenting.swift (agentictoolkit)
- ExtensionStatusBarPresenting.swift (agentictoolkit)
- NotImplementedLedger.swift (agentictoolkit)
- VSCodeAPI.swift (agentictoolkit)
- JSValueBridge.swift (agentictoolkit)
- Loggable.swift (agentictoolkit)
- MainThreadWindowTests.swift (agentictoolkit)
- MainThreadWindowQuickPickTests.swift (agentictoolkit)
- MainThreadWindowInputBoxTests.swift (agentictoolkit)
- MainThreadWindowStatusBarTests.swift (agentictoolkit)
- project.yml (agentictoolkit)
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
approved-by: ''
approved-date: ''
type: ingredient
language: en
depends-on: []
---

## Overview

`MainThreadWindow` is the `@MainActor`-isolated adaptor that answers everything
an extension reaches for on `vscode.window`'s message, quick-pick, input-box
and status-bar surface: `showInformationMessage`, `showWarningMessage`,
`showErrorMessage`, `showQuickPick`, `showInputBox` and
`createStatusBarItem`. It is not a UI component itself — it holds no view,
draws nothing, and has no appearance. Every call it receives from the
embedded JavaScript engine is parsed, coerced and validated against the
extension's actual arguments, then handed to one of four injected presenter
protocols (`ExtensionMessagePresenting`, `ExtensionQuickPickPresenting`,
`ExtensionInputBoxPresenting`, `ExtensionStatusBarPresenting`) that do the
real presenting; this recipe documents the adaptor's own contract —
argument parsing, coercion, promise settlement, status-bar item bookkeeping
and teardown — not the four presenter protocols' own contracts, which each
already have their own recipe. A fifth collaborator, `NotImplementedLedger`,
receives a record whenever a status-bar item's `tooltip` or `command` is set
to a shape this host does not project (a `MarkdownString`-typed tooltip or a
`Command`-object-typed command).

The type is non-`Sendable` and `@MainActor`-isolated by design: every member
it exposes is called from JavaScriptCore's synchronous bridge, which itself
only ever calls in from the main actor, so there is no cross-actor hop to
document. It conforms to `Loggable` but, as of this source, none of its
members call through the logger — every failure this adaptor detects is
reported to the extension itself, by rejecting or never settling the promise
it returned, not by a log line.

## Behavioral Requirements

- `init(messagePresenter:quickPickPresenter:inputBoxPresenter:statusBarPresenter:notImplementedLedger:extensionIdentifier:)` MUST require all four presenters and the ledger with no default value; a caller that has no real presenter for one of the four surfaces MUST supply one of its own (e.g. a no-op or recording stub), since `MainThreadWindow` has no fallback behavior for a missing presenter.
- `init` MUST retain the `extensionIdentifier` string and MUST use it, unmodified, as the `extensionIdentifier` argument on every `NotImplementedLedger.record(memberPath:extensionIdentifier:)` call the instance makes.
- `installMembers(on:extensionIdentifier:)` (or the equivalent installation entry point) MUST install `showInformationMessage`, `showWarningMessage` and `showErrorMessage` as three independent closures bound to the same coercion and dispatch logic, differing only in which `ExtensionMessagePresenting` method (`presentInformation`, `presentWarning`, `presentError`) each ultimately calls.
- Each `show*Message` member MUST require at least one argument; a call with zero arguments MUST reject the returned promise with a message of the form `"<memberPath> requires a message argument."`, where `memberPath` is the JS-visible name (`vscode.window.showInformationMessage`, `vscode.window.showWarningMessage` or `vscode.window.showErrorMessage`).
- Each `show*Message` member's first argument MUST be coerced to a string using the extension's own `toString`/`valueOf` machinery; if coercion fails or throws, the member MUST reject the promise with a message of the form `"<memberPath>'s argument 0 could not be converted to a string."` rather than let the coercion's exception propagate uncaught.
- Each `show*Message` member MUST treat every argument after the message as one item, where an item is either a JS string (interpreted as a plain button title) or an object with a string `title` property; any other element (a number, `undefined`, `null`, an array, an object with no string `title`) MUST reject the promise with a message of the form `"<memberPath>'s argument <index> is neither a string nor an object with a string 'title'."`, where `<index>` is the 1-based position of that argument.
- Each `show*Message` member's item objects MUST support an `isCloseAffordance` boolean property; when more than one item in the same call sets `isCloseAffordance: true`, the last one in argument order MUST be the one the resulting button plan treats as the close/cancel slot (last-wins, not first-wins, and not an error).
- Each `show*Message` member MUST forward the parsed message and item list to the corresponding `ExtensionMessagePresenting` method and MUST settle the returned promise with whatever value or `nil` that presenter call resolves to, without transforming it further.
- `showQuickPick` MUST require an items argument; a call with zero arguments MUST reject with `"vscode.window.showQuickPick requires an items argument."`.
- `showQuickPick`'s items argument MUST accept either a JS array or a JS promise (thenable) that itself resolves to an array; MUST reject with `"vscode.window.showQuickPick's argument 0 is neither an array nor a promise of one."` for any other shape, including a rejected promise, which MUST propagate as a rejection of the returned promise using the extension's own rejection reason.
- `showQuickPick`'s items array MUST NOT exceed `VSCodeAPI.maximumDecodableArrayLength` elements, and MUST have a `length` this host can read as a number; either violation MUST reject with `"vscode.window.showQuickPick's argument 0 is an array of more than <max> items, or reports a length this host cannot read."`.
- Each element of `showQuickPick`'s items array MUST be either a JS string (a bare label) or an object with a string `label` property; any other element MUST reject with `"vscode.window.showQuickPick's items[<index>] is neither a string nor an object with a string 'label'."`.
- `showQuickPick`'s optional second argument MUST be either an options object or `undefined`; any other type (a string, number, array, `null`) MUST reject with `"vscode.window.showQuickPick's argument 1 is neither an options object nor undefined."`.
- `showQuickPick`'s options, when present, MUST support `canPickMany`, `placeHolder`, `matchOnDescription`, `matchOnDetail` and `ignoreFocusOut`, each read and forwarded to the presenter using the same optional-field coercion `JSValueBridge` uses elsewhere in this file, and each MUST default to its documented VS Code default (`canPickMany: false`, `matchOnDescription: false`, `matchOnDetail: false`, `ignoreFocusOut: false`, `placeHolder: nil`) when absent.
- `showQuickPick`'s third argument, when present, MUST be accepted as a cancellation token and MUST be ignored; this adaptor MUST NOT wire the token to cancel the presenter call or reject the promise early, and MUST leave the promise's settlement entirely to the presenter's own resolution.
- `showQuickPick` MUST install two enum-like objects on the `vscode` namespace — `QuickPickItemKind` (at minimum `Separator`) and `QuickInputButtons` (at minimum `Back`) — so that extensions referencing those members do not fall through to the not-implemented path merely for referencing a well-known constant.
- `showQuickPick` MUST settle its returned promise using a `PromiseSettlementBox` whose `isDisposed` flag is checked immediately before dispatching to the presenter and again immediately after the presenter's `await` returns; if either check finds the box disposed, the member MUST leave the promise unsettled rather than resolve or reject it.
- `showQuickPick` MUST resolve the promise with the presenter's chosen item(s) exactly as the presenter returns them (single item, or an array when `canPickMany` is true), and MUST resolve with `undefined` when the presenter reports dismissal, without distinguishing a user-cancel from any other dismissal reason.
- `showInputBox`'s optional argument MUST be either an options object or `undefined`; any other type MUST reject with `"vscode.window.showInputBox's argument 0 is neither an options object nor undefined."`.
- `showInputBox`'s options, when present, MUST support `value`, `prompt`, `placeHolder`, `password` and `ignoreFocusOut`, each coerced with the same optional-field rules as `showQuickPick`'s options, defaulting to VS Code's own defaults (`value: ""`, `password: false`, `ignoreFocusOut: false`, `prompt: nil`, `placeHolder: nil`) when absent or when coercion of a present-but-wrong-typed field fails.
- `showInputBox`'s `valueSelection` option, when present, MUST be either `undefined`/`null` or a two-element array of numbers; any other shape MUST reject with `"vscode.window.showInputBox's options.valueSelection is neither a two-element array nor undefined/null."`, and an array of any length other than two MUST reject with `"...must have exactly two elements, not <length>."`.
- `showInputBox`'s `valueSelection`, when a two-element array, MUST have both elements be numbers (rejecting with `"...must both be numbers."` otherwise), MUST have a non-negative start (rejecting with `"...start (<start>) must not be negative."` otherwise), MUST have an end that is not before the start (rejecting with `"...end (<end>) must not be before its start (<start>)."` otherwise), MUST have an end that does not exceed the UTF-16 length of `value` (rejecting with `"...end (<end>) is past the end of value, which is <length> long."` otherwise), and MUST NOT fall inside a single `Character`'s UTF-16 encoding for either offset (rejecting with `"...offsets (<start>, <end>) must not fall inside a character of value."` otherwise). Every one of these five checks MUST reject the promise rather than silently clamp or forward a malformed selection.
- `showInputBox`'s `validateInput` option, when present, MUST be invoked with the current value on each edit the presenter reports, and its return value — a string, a validation-result object, `undefined`/`null`, or a thenable resolving to any of those — MUST be normalized so that `undefined`, `null`, and an empty string all mean "valid" and anything else means "invalid with this message and severity," defaulting severity to `Error` when the closure returns a bare string or an object that omits severity.
- `showInputBox`'s `validateInput` closure, when it is a genuine JS function value, MUST be invoked bound to the same `this` the presenter's `onDidSelectItem`/change callback convention uses elsewhere in this file, matching this component's own callback-binding choice rather than upstream VS Code's.
- `createStatusBarItem` MUST accept either zero arguments, a single `id` string argument, an `(alignment, priority)` pair, or an `(id, alignment, priority)` triple, and MUST discriminate which overload was called by inspecting the runtime type of each argument position rather than by argument count alone, since a JS caller may omit trailing arguments.
- `createStatusBarItem` MUST synthesize an internal identifier for every item that combines the caller-supplied `id` (or a generated one, when omitted) with a strictly-increasing ordinal drawn from a counter shared across every call on this instance, so that two items created with the same explicit `id` in the same session never collide internally even though VS Code itself allows a caller to reuse `id` values.
- `createStatusBarItem`'s `alignment` argument MUST accept `StatusBarAlignment.Left` or `StatusBarAlignment.Right` (as the numeric enum values VS Code defines) and MUST default to `Left` when omitted or unrecognized.
- `createStatusBarItem`'s `priority` argument MUST accept any JS number, including `Infinity` and `-Infinity`, and MUST forward it to the presenter unclamped and unrounded beyond ordinary `Double` representation; this adaptor MUST NOT reject, clamp, or coerce an infinite or out-of-range priority to a finite default.
- The status bar item object `createStatusBarItem` returns to the extension MUST expose `text`, `tooltip`, `command`, `color`, `backgroundColor`, `alignment`, `priority`, `accessibilityInformation`, `show()`, `hide()` and `dispose()` as live JS accessors/methods, each of which MUST take effect through the `ExtensionStatusBarPresenting` presenter rather than being cached inertly on the JS object.
- Setting the returned item's `tooltip` to a plain string or to `undefined`/`null` MUST forward that value to the presenter as-is; setting it to a `MarkdownString`-shaped object MUST record one access to `"vscode.StatusBarItem.tooltip: MarkdownString"` on the `NotImplementedLedger` and MUST NOT forward a markdown rendering to the presenter; any other shape (a number, an array, an unrecognized object) MUST be treated the same as the unsupported-shape branch — recorded to the ledger and not forwarded — rather than silently dropped without a ledger entry.
- Setting the returned item's `command` to a string command identifier or to `undefined`/`null` MUST forward that value to the presenter as-is; setting it to a `Command`-object-shaped value (an object with a string `command` property) MUST record one access to `"vscode.StatusBarItem.command: Command"` on the ledger and MUST NOT forward the object to the presenter; any other shape MUST follow the same recorded-and-not-forwarded rule as `tooltip`.
- Setting the returned item's `color` or `backgroundColor` MUST accept a string (a named/hex color) or a `ThemeColor`-shaped object and MUST forward whichever was set to the presenter without filtering one against a fixed allow-list of accepted theme color IDs; this adaptor MUST NOT cross-check `color` against `backgroundColor` or reject a combination upstream VS Code itself would reject.
- Calling the returned item's `show()` MUST forward to the presenter's show call for that item's internal identifier; calling `hide()` MUST forward to the presenter's hide call for that identifier unconditionally, even when the item was never shown, rather than checking a local shown/hidden flag first.
- Calling the returned item's `dispose()` MUST forward to the presenter's dispose call for that identifier and MUST remove any bookkeeping this adaptor keeps for that identifier (so a later mutation of a disposed item's properties does not resurrect it in the presenter), and MUST perform the presenter-facing dispose call before discarding this adaptor's own bookkeeping for that identifier, not after.
- Every property mutation on a returned status bar item MUST be applied to the presenter immediately, synchronously, on the calling `@MainActor` context, with no debouncing or coalescing of rapid repeated writes (e.g. setting `text` many times in a tight loop) into a single presenter call.
- `MainThreadWindow`'s own `dispose()` (or equivalent teardown entry point) MUST mark every `PromiseSettlementBox` this instance still holds as disposed, so that any `show*Message`, `showQuickPick` or `showInputBox` promise still pending at teardown is left permanently unsettled rather than rejected or resolved after disposal.
- Every promise-returning member MUST run on the `@MainActor` and MUST NOT suspend across an actor boundary other than the single `await` of the corresponding presenter call.

## Appearance

Not applicable — this is the `vscode.window` extension-host adaptor, not a visual component; it holds no view and draws nothing.

## States

Not applicable — this is not a visual component with a rendered state machine. Runtime states this adaptor does track (a status bar item's shown/hidden state, a pending promise's settled/unsettled/disposed state, the internal-identifier registry's live/removed state) are documented as requirements above, not as a visual state table.

## Accessibility

Not applicable — this is not a visual component. The one accessibility-shaped property it carries, a status bar item's `accessibilityInformation`, is a caller-supplied value this adaptor passes through to the presenter unmodified; that pass-through is documented under Behavioral Requirements, not here.

## Conformance Test Vectors

| Input / Call | Expected Output / Effect | Source |
|---|---|---|
| `showInformationMessage()` with no arguments | Promise rejects with `"vscode.window.showInformationMessage requires a message argument."` | `MainThreadWindowTests.swift` |
| `showWarningMessage("text", 42)` | Promise rejects citing argument 1 is neither a string nor an object with a string `title` | `MainThreadWindowTests.swift` |
| `showErrorMessage("text", { title: "Retry" }, { title: "Cancel", isCloseAffordance: true })` | Presenter receives two items; the `Cancel` item is the close affordance | `MainThreadWindowTests.swift` |
| `showQuickPick()` with no arguments | Promise rejects with `"vscode.window.showQuickPick requires an items argument."` | `MainThreadWindowQuickPickTests.swift` |
| `showQuickPick(42)` | Promise rejects with `"...argument 0 is neither an array nor a promise of one."` | `MainThreadWindowQuickPickTests.swift` |
| `showQuickPick(["a", "b"], { canPickMany: true })` and the presenter resolves both | Promise resolves to an array containing both chosen items | `MainThreadWindowQuickPickTests.swift` |
| `showQuickPick` items array longer than `VSCodeAPI.maximumDecodableArrayLength` | Promise rejects citing the array-length limit | `MainThreadWindowQuickPickTests.swift` |
| `showQuickPick(Promise.reject(new Error("boom")))` | Returned promise rejects with the extension's own rejection reason | `MainThreadWindowQuickPickTests.swift` |
| `showInputBox({ valueSelection: [3] })` | Promise rejects with `"...must have exactly two elements, not 1."` | `MainThreadWindowInputBoxTests.swift` |
| `showInputBox({ value: "hi", valueSelection: [1, 5] })` where `value` is length 2 | Promise rejects citing the end offset past the end of `value` | `MainThreadWindowInputBoxTests.swift` |
| `showInputBox({ validateInput: () => "bad" })` on an edit | Presenter reports the input invalid with message `"bad"` and severity `Error` | `MainThreadWindowInputBoxTests.swift` |
| `showInputBox({ validateInput: () => undefined })` on an edit | Presenter reports the input valid | `MainThreadWindowInputBoxTests.swift` |
| `createStatusBarItem("my.id", StatusBarAlignment.Right, 5)` | Presenter creates an item aligned right at priority 5, keyed by an internal identifier derived from `"my.id"` | `MainThreadWindowStatusBarTests.swift` |
| `createStatusBarItem()` twice with the same explicit `id` | Two distinct internal identifiers are created; no collision | `MainThreadWindowStatusBarTests.swift` |
| Setting `.tooltip` to a `MarkdownString`-shaped object | `NotImplementedLedger.record` is called with `memberPath: "vscode.StatusBarItem.tooltip: MarkdownString"`; presenter's tooltip is not updated | `MainThreadWindowStatusBarTests.swift` |
| Setting `.command` to `{ command: "my.cmd", title: "Run" }` | `NotImplementedLedger.record` is called with `memberPath: "vscode.StatusBarItem.command: Command"`; presenter's command is not updated | `MainThreadWindowStatusBarTests.swift` |
| Setting `.command` to the string `"my.cmd"` | Presenter's command is updated to `"my.cmd"`; no ledger record | `MainThreadWindowStatusBarTests.swift` |
| Calling `.hide()` on an item never shown | Presenter's hide call is made unconditionally; no error | `MainThreadWindowStatusBarTests.swift` |
| Calling `.dispose()` then mutating `.text` on the same item | Presenter's dispose call preceded the mutation attempt; the mutation is not forwarded to the presenter for that identifier | `MainThreadWindowStatusBarTests.swift` |
| `createStatusBarItem(undefined, undefined, Infinity)` | Priority forwarded to the presenter as `Infinity`, unclamped | `MainThreadWindowStatusBarTests.swift` (source-documented; not exercised by a dedicated `Infinity` test — see Compliance) |
| `dispose()` on `MainThreadWindow` itself while a `showQuickPick` promise is pending | The pending promise's `PromiseSettlementBox` is marked disposed; the promise never settles | `MainThreadWindowQuickPickTests.swift` |

## Edge Cases

- A `show*Message` argument that is an object with a `title` property whose value is not itself a string (e.g. a number) MUST be treated as failing the "object with a string `title`" test and MUST reject the promise, not coerce the number to a string.
- Two items in the same `show*Message` call that each set `isCloseAffordance: true` MUST resolve to the last one in argument order winning the close-affordance slot, not an error and not the first.
- `showQuickPick`'s items promise resolving to a value that is not itself an array (e.g. a plain object or `undefined`) MUST be treated as a decode failure and MUST reject with the same "neither an array nor a promise of one" message used for a non-array, non-promise first argument.
- `showQuickPick`'s cancellation-token argument, when actually invoked by the extension to signal cancellation, MUST have no observable effect on this adaptor; an extension expecting the picker to close early on token cancellation will not see that happen, because the token is accepted and ignored.
- `showInputBox`'s `valueSelection` offsets that are equal to each other (an empty selection) MUST be accepted as long as both individual checks (non-negative, not past the end, not inside a character) pass; an empty selection is not itself an error.
- `showInputBox`'s `validateInput` rejecting (throwing, or returning a rejected thenable) MUST be treated as the input being reported invalid using the extension's own rejection reason as the message, not as an adaptor-level failure that rejects the whole `showInputBox` promise.
- `createStatusBarItem`'s first argument being a number rather than a string or an alignment enum value MUST be interpreted as the two-argument `(alignment, priority)` overload with `id` omitted, not rejected as a type error.
- Two concurrent `createStatusBarItem` calls on the same instance MUST never receive the same internal identifier, because the ordinal counter is drawn synchronously on the `@MainActor` inside the same call that reads it; there is no window in which two calls can observe the same ordinal.
- A `showQuickPick` or `showInputBox` promise still pending when `MainThreadWindow.dispose()` runs MUST NOT be rejected with a "disposed" error; it is left permanently unsettled, which is a deliberate divergence from a pattern that would reject outstanding work on teardown — an extension awaiting that promise will simply never resume.
- This adaptor makes no network calls and holds no connection to lose; an "offline" or "disconnected" edge case does not apply to any member here — every failure path is a local argument-shape rejection, a presenter-reported invalidity, or a permanently unsettled promise, never a connectivity error.

## Configuration

| Parameter | Type | Required | Description |
|---|---|---|---|
| `messagePresenter` | `ExtensionMessagePresenting` | Yes, no default | Presents `showInformationMessage`/`showWarningMessage`/`showErrorMessage` calls. |
| `quickPickPresenter` | `ExtensionQuickPickPresenting` | Yes, no default | Presents `showQuickPick` calls. |
| `inputBoxPresenter` | `ExtensionInputBoxPresenting` | Yes, no default | Presents `showInputBox` calls. |
| `statusBarPresenter` | `ExtensionStatusBarPresenting` | Yes, no default | Presents `createStatusBarItem` items and their live mutations. |
| `notImplementedLedger` | `NotImplementedLedger` | Yes, no default | Receives one record per unsupported `tooltip`/`command` shape set on a status bar item. |
| `extensionIdentifier` | `String` | Yes, no default | Attributed on every ledger record this instance makes. |

## Deep Linking

Not applicable — this adaptor exposes no URL scheme, route or deep-link target; it only answers in-process JavaScript calls from an already-running extension.

## Localization

This adaptor is not itself a rendered surface, but every rejection and validation message it produces is a hardcoded English literal handed to the extension (and, in several presenter-facing test assertions, to a person debugging the extension), so it is a genuine localization surface, not one this recipe can mark "Not applicable." None of these strings route through any localization mechanism (no `String(localized:)`, no string catalog entry); they are `String(format:)`/interpolation-built English sentences. Representative examples, each traced to source:

| String (representative) | Where |
|---|---|
| `"<memberPath> requires a message argument."` | `show*Message` zero-argument rejection |
| `"<memberPath>'s argument 0 could not be converted to a string."` | `show*Message` message-coercion failure |
| `"<memberPath>'s argument <index> is neither a string nor an object with a string 'title'."` | `show*Message` item-shape rejection |
| `"vscode.window.showQuickPick requires an items argument."` | `showQuickPick` zero-argument rejection |
| `"vscode.window.showQuickPick's argument 0 is neither an array nor a promise of one."` | `showQuickPick` items-shape rejection |
| `"vscode.window.showQuickPick's argument 0 is an array of more than <max> items, or reports a length this host cannot read."` | `showQuickPick` array-length rejection |
| `"vscode.window.showQuickPick's items[<index>] is neither a string nor an object with a string 'label'."` | `showQuickPick` per-item rejection |
| `"vscode.window.showQuickPick's argument 1 is neither an options object nor undefined."` | `showQuickPick` options-shape rejection |
| `"vscode.window.showInputBox's argument 0 is neither an options object nor undefined."` | `showInputBox` options-shape rejection |
| `"...options.valueSelection is neither a two-element array nor undefined/null."` and its four sibling `valueSelection` messages (element count, element types, negative start, end-before-start, end-past-value-length, offset-inside-character) | `showInputBox` `valueSelection` validation |
| `"vscode.window.createStatusBarItem is unavailable: this extension's host has been torn down."` | `createStatusBarItem` raised after teardown |

Any UI surface presenting one of these strings to an end user, rather than to the extension that triggered them, would need its own localization pass; this adaptor itself has none.

## Accessibility Options

Not applicable — this adaptor has no rendered surface, so it reads no Reduce Motion, Increase Contrast or Differentiate Without Color signal.

## Feature Flags

Not applicable — every member this adaptor installs is unconditionally available once the instance is constructed with its four presenters; no member is gated behind a flag, an entitlement, or a build configuration in this source.

## Analytics

Not applicable — this source contains no analytics or telemetry call; every outcome (success, rejection, ledger record) is reported to the extension itself or to `NotImplementedLedger`, never to an event-collection system.

## Privacy

This adaptor does not persist or transmit anything itself, but it is a conduit for user- and extension-authored content: message text and button titles (`show*Message`), quick-pick item labels/descriptions/details (`showQuickPick`), typed input values including a `password: true` field's contents (`showInputBox`), and status bar item text/tooltip/color values all pass through this instance's memory for the duration of a single call or for the lifetime of a live status bar item object, then are discarded when the promise settles or the item is disposed. None of it is written to disk, logged, or sent anywhere by this adaptor; `NotImplementedLedger`'s records carry only a member-path string and the caller's `extensionIdentifier`, never the message, item, or input content itself. A `password: true` input box's typed value is held in process memory identically to a non-password value — this adaptor applies no additional in-memory protection for it, and masking that value on screen is the presenter's responsibility, not this adaptor's.

## Logging

`MainThreadWindow` conforms to `Loggable`, giving it a logger, but as of this source no member on this type calls through it. Every failure this adaptor detects reports itself to the extension directly, by rejecting or never settling the promise it returned, and nothing here yet fails in a way only a log line could report. The conformance is kept for the same reason `NotImplementedLedger` is injected rather than constructed locally: a future member that can fail in a way invisible to the extension (for example, a presenter throwing where none of the current contracts allow it) has a logger ready without another migration.

## Platform Notes

- **SwiftUI**: Not applicable — this is app/extension-host plumbing with no view; a SwiftUI host would call the same presenter protocols this adaptor calls, not reimplement this type.
- **AppKit/UIKit**: This is the source; the surrounding app is macOS-only (see `project.yml`'s `AgenticToolkitMacOS` target), and there is no iOS/UIKit build of this file today.
- **Compose (Android/Kotlin)**: A Kotlin port would model this as a class implementing the JS-engine bridge callbacks (e.g. via a J2V8/QuickJS binding) that dispatches to Kotlin interfaces mirroring the four presenter protocols, with the same argument-shape validation performed before any dispatch, and the same permanently-unsettled-on-dispose behavior for a `Deferred`/`CompletableDeferred` standing in for the pending promise.
- **React/Web**: A web-hosted equivalent would run the extension in a Web Worker or sandboxed iframe and marshal these same calls over `postMessage`, replacing the synchronous JavaScriptCore bridge with an asynchronous message protocol; the argument-shape validation, the last-wins close-affordance rule, and the unclamped-`Infinity`-priority behavior would all need to be reproduced explicitly, since none of them fall out of `postMessage`'s own semantics.
- **WinUI 3**: A .NET port would implement this as a class exposing the same members to a `ClearScript` or `Jint` JavaScript engine instance, using `TaskCompletionSource<object>` in place of `PromiseSettlementBox` (with `TrySetResult`/`TrySetCanceled` guarded the same way `isDisposed` is checked here, since `TaskCompletionSource` has no built-in "leave pending forever" state — a disposed instance would need to hold the `TaskCompletionSource` without ever completing it), `ObservableCollection<T>`/`INotifyPropertyChanged` for a status bar item's live-mutable properties surfaced back to the engine, `DispatcherQueue.TryEnqueue` to guarantee the same single-thread affinity `@MainActor` guarantees here, and a `System.Text.Json`-based decoder for the same options-object shape checks (`valueSelection`, `canPickMany`, etc.) this file performs by hand against `JSValue`.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadWindow.swift` |

## Design Decisions

- **Decision**: `showQuickPick`'s and `showInputBox`'s cancellation-token arguments are accepted and then ignored; nothing in this adaptor wires them to cancel the presenter call or reject the promise.
  **Rationale**: The presenter protocols themselves define no cancellation entry point today, so honoring the token would require a second, currently-nonexistent contract on all four presenters; accepting-and-ignoring keeps extensions that pass a token from crashing on an unrecognized argument while being honest that cancellation has no effect yet.
  **Approved**: pending

- **Decision**: `createStatusBarItem`'s `priority` is forwarded to the presenter unclamped, including `Infinity` and `-Infinity`.
  **Rationale**: VS Code's own priority is an arbitrary-precedence sort key with no documented bound; clamping it here would silently change ordering behavior an extension may depend on, and the presenter — not this adaptor — is the layer responsible for however it chooses to sort or bound priorities for display.
  **Approved**: pending

- **Decision**: Setting `tooltip` to a `MarkdownString`-shaped object or `command` to a `Command`-object-shaped value records one `NotImplementedLedger` access and drops the value rather than raising or rejecting.
  **Rationale**: Both properties are plain (non-promise-returning) setters in the VS Code API, so there is no promise available to reject and no synchronous exception path an extension would expect from a property assignment; recording the access lets the eventual not-implemented report surface the gap to whoever debugs the extension without breaking a setter extensions expect to always succeed.
  **Approved**: pending

- **Decision**: Every status bar item property mutation is applied to the presenter synchronously and immediately, with no debouncing or coalescing of rapid repeated writes.
  **Rationale**: Coalescing would require buffering state this adaptor does not otherwise keep and would change the presenter's view of intermediate states an extension's own logic might depend on (e.g. a progress indicator that sets `text` many times in a loop); the source explicitly notes it has not measured the cost of this choice and does not claim it is free, but treats correctness of intermediate state as the higher priority absent a measured problem.
  **Approved**: pending

- **Decision**: `createStatusBarItem` mints its own internal identifier from the caller's `id` plus a strictly-increasing ordinal, rather than using the caller's `id` directly as the presenter-facing key.
  **Rationale**: VS Code allows an extension to construct multiple status bar items that share the same `id`; using `id` directly as the presenter key would make the second item silently alias or overwrite the first inside this adaptor's own bookkeeping, which upstream VS Code does not do.
  **Approved**: pending

- **Decision**: A `show*Message`, `showQuickPick` or `showInputBox` promise still pending when `MainThreadWindow.dispose()` runs is left permanently unsettled rather than rejected with a teardown error.
  **Rationale**: Rejecting on teardown would require every extension awaiting one of these promises to install a catch handler solely to survive host disposal, which upstream VS Code's own analogous shutdown path does not require; leaving the promise pending matches the observable behavior of the host process disappearing without ever answering, which is what disposal actually represents.
  **Approved**: pending

- **Decision**: `showInputBox`'s and `showQuickPick`'s callback-style options (`validateInput`, and the presenter's own selection-changed callback) are invoked bound to the same `this` convention as each other, rather than each independently choosing a binding the way upstream VS Code's separate extension-host modules do.
  **Rationale**: Keeping one binding convention across both members means an extension author who learns how `this` behaves in one callback does not have to relearn it for the other; upstream VS Code's own two implementations happened to diverge here for historical reasons this adaptor does not need to preserve.
  **Approved**: pending

## Compliance

| Check | Status | Rationale |
|---|---|---|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | Pass | Argument parsing/coercion/validation lives entirely in this adaptor; presenting (rendering a message, a picker, an input box, a status bar item) is fully delegated to four separate injected protocols, and unsupported-shape bookkeeping is delegated to `NotImplementedLedger` rather than folded into this type. |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | Partial | The four message/quick-pick/input-box/status-bar test files exercise argument-shape rejection, coercion, ledger recording, and teardown extensively, but the documented `Infinity`/`-Infinity` priority pass-through has no dedicated test in `MainThreadWindowStatusBarTests.swift` (confirmed by search — no test references `Infinity`), so that specific divergence is source-documented but not test-verified. |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | Pass | Every argument-shape and coercion failure produces a specific, informative rejection message naming the member and the offending argument; no failure path silently swallows an error or falls through to a default without signaling the extension. |
| [secure-log-output](agenticdevelopercookbook://compliance/security#secure-log-output) | Pass | This type performs no logging at all (see Logging above), so no user- or extension-authored content — including a password-flagged input box value — can reach a log line through this adaptor. |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | Fail | Every rejection message is a hardcoded English literal built by string interpolation, with no localization mechanism; see Localization above for the representative set. |

## Change History

| Version | Date | Author | Summary |
|---|---|---|---|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
