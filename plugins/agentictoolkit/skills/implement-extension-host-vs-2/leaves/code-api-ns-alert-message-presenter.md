<!-- leaf: implement-extension-host-vs-2/code-api-ns-alert-message-presenter · source: extension-host-vs-code-api-ns-alert-message-presenter.md -->

**Rules** (cite as `implement-extension-host-vs-2/code-api-ns-alert-message-presenter#<slug>`):

- `mainactor-conformance` MUST
- `explicit-window-parameter` MUST
- `injected-window-storage` MUST
- `window-queried-per-presentation` MUST
- `sheet-window-fallback` MUST
- `any-visible-window-selection` MUST
- `sheet-only-presentation` MUST
- `no-app-activation` MUST
- `drop-when-no-window` MUST
- `dropped-message-logged` MUST
- `message-text-assignment` MUST
- `detail-text-conditional` MUST
- `severity-style-mapping` MUST
- `empty-items-single-ok` MUST
- `button-plan-skip-flagged` MUST
- `button-plan-cancel-slot` MUST
- `button-plan-internal-access` MUST
- `button-titles-from-plan` MUST
- `escape-key-position-rule` MUST
- `escape-position-internal-access` MUST
- `escape-key-assignment` MUST
- `response-to-item-index` MUST
- `out-of-range-response-resolves-nil` MUST
- `no-throwing-path` MUST
- `continuation-bridging` MUST
- `is-modal-not-honored` MUST
- `logger-identity` MUST
- `non-sendable-isolation` MUST

# NSAlertMessagePresenter

## Overview

`NSAlertMessagePresenter` (`packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/NSAlertMessagePresenter.swift`) is the one production conformer of ExtensionMessagePresenting given among the sources: it turns a `vscode.window.show*Message` request into an `NSAlert` sheet. Per the file's own header comment, it was split out of `MainThreadWindow.swift` once that adaptor grew past 2,800 lines. Where the protocol recipe documents the contract every conformer must satisfy, this recipe documents this conformer's own presentation choices: always a sheet, attached to a window read fresh from an injected `() -> NSWindow?` closure rather than guessed at from ambient application state; never an app-modal `runModal()` alert, because this is an `LSUIElement` menu-bar app for which activating unexpectedly would seize the screen from whoever is typing; and, with no window anywhere in the app to attach a sheet to, the message is logged and dropped rather than shown by any means that would seize the screen. The type also derives the AppKit button layout — including which button carries the Escape key equivalent — from `request.itemTitles` and `request.closeAffordanceIndices`, and conforms to `Loggable` to report the one failure mode it can reach on its own: a dropped, never-shown message.

## Behavioral Requirements

- **mainactor-conformance**: `NSAlertMessagePresenter` MUST be declared `final`, `public`, and `@MainActor`, and MUST conform to `ExtensionMessagePresenting`.
- **explicit-window-parameter**: `init(window:)` MUST take a `() -> NSWindow?` closure with no default value, so a caller MUST make an explicit choice about which window (if any) a sheet attaches to, rather than the initializer picking one implicitly.
- **injected-window-storage**: the injected closure MUST be stored as a `private let window: () -> NSWindow?`, set once at initialization and never reassigned.
- **window-queried-per-presentation**: `sheetWindow()` MUST call the injected `window` closure fresh on every invocation rather than caching its result at initialization, so the answer reflects whichever window is frontmost at presentation time.
- **sheet-window-fallback**: `sheetWindow()` MUST return the injected `window()`'s value when it is non-nil, and otherwise MUST return `anyVisibleWindow()`'s value.
- **any-visible-window-selection**: `anyVisibleWindow()` MUST return the first window in `NSApp.windows` for which both `isVisible` and `canBecomeMain` are true, and MUST return `nil` when no such window exists.
- **sheet-only-presentation**: `presentMessage(_:)` MUST present every request by calling `NSAlert.beginSheetModal(for:completionHandler:)` on `sheetWindow()`'s window.
- **no-app-activation**: `presentMessage(_:)` MUST NOT call `NSAlert.runModal()` or any other presentation API that activates the app or makes a window key when the app is not already active.
- **drop-when-no-window**: when `sheetWindow()` returns `nil`, `presentedResponse(for:)` MUST NOT present the alert by any means, and MUST resolve to `nil`.
- **dropped-message-logged**: whenever `presentedResponse(for:)` drops a message because `sheetWindow()` returned `nil`, it MUST log an `error`-level message via `NSAlertMessagePresenter.logger`, and MUST NOT log anything when a window is found.
- **message-text-assignment**: `presentMessage(_:)` MUST set `NSAlert.messageText` to `request.message` unconditionally, including when `request.message` is an empty string.
- **detail-text-conditional**: `presentMessage(_:)` MUST set `NSAlert.informativeText` to `request.detail` when it is non-nil, and MUST leave `informativeText` at whatever default `NSAlert` itself assigns when `request.detail` is `nil`.
- **severity-style-mapping**: `alertStyle(for:)` MUST map `request.severity` to `NSAlert.Style` as `.information` to `.informational`, `.warning` to `.warning`, and `.error` to `.critical`, and `presentMessage(_:)` MUST assign that mapped value to `NSAlert.alertStyle`.
- **empty-items-single-ok**: when `request.itemTitles` is empty, `presentMessage(_:)` MUST add exactly one button titled `OK`, MUST await its presentation, and MUST return `nil` regardless of which response that presentation produces.
- **button-plan-skip-flagged**: for a non-empty `request.itemTitles`, `buttonPlan(for:)` MUST include, in `itemTitles` order, the index of every item whose index is not a member of `request.closeAffordanceIndices`.
- **button-plan-cancel-slot**: `buttonPlan(for:)` MUST append exactly one further entry after that skip pass: `request.closeAffordanceIndices.last` when `closeAffordanceIndices` is non-empty, or `nil` (denoting a synthesized cancel button) when it is empty.
- **button-plan-internal-access**: `buttonPlan(for:)` MUST remain at `internal` access, not `private`, because `MainThreadWindowTests` calls it directly through `@testable import AgenticToolkitMacOS`.
- **button-titles-from-plan**: `addButtons(for:to:)` MUST add exactly one `NSAlert` button per `buttonPlan(for:)` entry, in plan order, titled `request.itemTitles[itemIndex]` for an entry naming an item index and titled `Cancel` for a `nil` entry.
- **escape-key-position-rule**: `escapeKeyEquivalentPosition(in:)` MUST return `plan.count - 1` when `plan.count` is greater than 1, and MUST return `nil` when `plan.count` is 1 or 0.
- **escape-position-internal-access**: `escapeKeyEquivalentPosition(in:)` MUST remain at `internal` access, not `private`, because `MainThreadWindowTests` calls it directly through `@testable import AgenticToolkitMacOS`.
- **escape-key-assignment**: `addButtons(for:to:)` MUST assign the Escape character as the `keyEquivalent` of the button at the position `escapeKeyEquivalentPosition(in:)` returns, when that position is non-nil, and MUST leave every other added button's `keyEquivalent` at whatever default `NSAlert.addButton(withTitle:)` assigns it.
- **response-to-item-index**: on a non-empty-items alert, `presentMessage(_:)` MUST compute `buttonIndex` as the user's `NSApplication.ModalResponse` minus `NSApplication.ModalResponse.alertFirstButtonReturn`, and MUST return `buttonItemIndices[buttonIndex]` — itself `nil` when that plan entry is the synthesized cancel button — as the call's result.
- **out-of-range-response-resolves-nil**: if the computed `buttonIndex` does not index into `buttonItemIndices`, `presentMessage(_:)` MUST return `nil` rather than access the array out of bounds.
- **no-throwing-path**: `presentMessage(_:)` MUST NOT throw under any input or presentation outcome, matching `ExtensionMessagePresenting`'s non-throwing requirement.
- **continuation-bridging**: `presentedResponse(for:)` MUST bridge `NSAlert.beginSheetModal(for:completionHandler:)`'s completion handler into `async` using `withCheckedContinuation`, resuming the continuation with the `NSApplication.ModalResponse` the completion handler is given.
- **is-modal-not-honored**: `presentMessage(_:)` MUST NOT read or branch on `request.isModal`; every request MUST be presented as a modal sheet regardless of that field's value.
- **logger-identity**: `NSAlertMessagePresenter` MUST conform to `Loggable` with `logger = makeLogger()`, giving it an `OSLog` category of `NSAlertMessagePresenter` and a subsystem of `Bundle.main.bundleIdentifier` (or the literal string "nil" when unset), per `Loggable`'s own defaults.
- **non-sendable-isolation**: `NSAlertMessagePresenter` MUST declare no `Sendable` conformance of its own; because it is `@MainActor`-isolated, its stored-property access and the synchronous portion of every method MUST run on the main actor, and a caller MUST reach any of its methods only via `await` from outside that isolation domain.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `window` | `() -> NSWindow?` | none (required; `init(window:)` takes no default) | Queried fresh by `sheetWindow()` on every `presentMessage(_:)` call to decide which window a sheet attaches to; a `nil` result falls back to `anyVisibleWindow()` before the message is dropped. |
| `request` | `ExtensionMessageRequest` | none (required, supplied per call to `presentMessage(_:)`) | The per-call payload — `severity`, `message`, `detail`, `isModal`, `itemTitles`, `closeAffordanceIndices`; its own field shapes, defaults, and invariants are documented in ExtensionMessagePresenting rather than restated here. |

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — hardcoded literal) | `OK` | The single button title added when `request.itemTitles` is empty. |
| (none — hardcoded literal) | `Cancel` | The title given the synthesized cancel-slot button whenever `buttonPlan(for:)`'s cancel entry is `nil`. |

Both are literal English string constants in the source, assigned with no `String(localized:)` call and no String Catalog entry, so the code presents them in English regardless of the user's system locale. `request.message`, `request.detail`, and `request.itemTitles` are passed through verbatim from the caller and are not this file's own strings to localize.

## Privacy

- **Data collected**: `NSAlertMessagePresenter` collects nothing of its own; `request.message`, `request.detail`, and `request.itemTitles` are whatever text the calling extension supplied to a `show*Message` call, held only as fields of the `ExtensionMessageRequest` value for the duration of one `presentMessage(_:)` call.
- **Storage**: the file performs no storage of its own; nothing here persists a request past the call it was built for.
- **Transmission**: the file performs no network transmission; the request is presented in-process, via AppKit, to whatever window `sheetWindow()` resolves.
- **Retention**: the one thing that outlives a single call is the dropped-message log line `presentedResponse(for:)` writes when `sheetWindow()` returns `nil`; that line includes `alert.messageText` (i.e., `request.message`) marked `privacy: .public`, so — unlike a `privacy: .private` value — it is not redacted from the unified log, whatever text the calling extension put in that message; retention of that log entry itself is governed by the OS's unified-logging policy, not by this file.

