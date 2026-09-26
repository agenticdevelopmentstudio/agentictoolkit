---
id: 77fe79f8-7d45-4e51-aee0-d6de78b459e1
title: NSAlertMessagePresenter
domain: agentictoolkit://cookbook/macos/features/extensions/vs-code-api/ns-alert-message-presenter
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'The one given `ExtensionMessagePresenting` conformer: presents a vscode.window.show*Message
  request as an NSAlert sheet, or drops it when no window is available.'
platforms:
- swift
- macos
tags:
- extension-host
- vscode-api
- message-presenting
- mainactor
- sheet
depends-on:
- agentictoolkit://cookbook/macos/features/extensions/vs-code-api/extension-message-presenting
related: []
references:
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/NSAlertMessagePresenter.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/ExtensionMessagePresenting.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Loggable.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Extensions/MainThreadWindowTests.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

# NSAlertMessagePresenter

## Overview

`NSAlertMessagePresenter` (`packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/NSAlertMessagePresenter.swift`) is the one production conformer of [ExtensionMessagePresenting](agentictoolkit://cookbook/macos/features/extensions/vs-code-api/extension-message-presenting) given among the sources: it turns a `vscode.window.show*Message` request into an `NSAlert` sheet. Per the file's own header comment, it was split out of `MainThreadWindow.swift` once that adaptor grew past 2,800 lines. Where the protocol recipe documents the contract every conformer must satisfy, this recipe documents this conformer's own presentation choices: always a sheet, attached to a window read fresh from an injected `() -> NSWindow?` closure rather than guessed at from ambient application state; never an app-modal `runModal()` alert, because this is an `LSUIElement` menu-bar app for which activating unexpectedly would seize the screen from whoever is typing; and, with no window anywhere in the app to attach a sheet to, the message is logged and dropped rather than shown by any means that would seize the screen. The type also derives the AppKit button layout — including which button carries the Escape key equivalent — from `request.itemTitles` and `request.closeAffordanceIndices`, and conforms to `Loggable` to report the one failure mode it can reach on its own: a dropped, never-shown message.

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

## Appearance

Not applicable — this is a message-presentation conformer that hands the request to a system-drawn `NSAlert`, not a custom visual component with appearance of its own to specify.

## States

Not applicable — this is a message-presentation conformer that hands the request to a system-drawn `NSAlert`, not a custom visual component with a visual-state table. The per-call sequencing this type has (build an alert, present it as a sheet or drop it, resolve an index or `nil`) is captured under Behavioral Requirements, not here.

## Accessibility

Not applicable — this is a message-presentation conformer that hands the request to a system-drawn `NSAlert`, not a custom visual component. Whatever accessibility behavior the presented sheet has is `NSAlert`'s own AppKit-level behavior; this file implements no accessibility logic of its own.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| ns-alert-message-presenter-001 | button-plan-skip-flagged, button-plan-cancel-slot | `buttonPlan(for:)` on `itemTitles == ["A", "B", "C"]`, `closeAffordanceIndices == []` | Returns `[0, 1, 2, nil]` — `MainThreadWindowTests.buttonPlanOrdersButtonsAndFillsTheCancelSlotFromTheLastCloseAffordance` |
| ns-alert-message-presenter-002 | button-plan-skip-flagged, button-plan-cancel-slot | Same items, `closeAffordanceIndices == [0]` | Returns `[1, 2, 0]` — same test |
| ns-alert-message-presenter-003 | button-plan-skip-flagged, button-plan-cancel-slot | Same items, `closeAffordanceIndices == [0, 2]` (two items flagged) | Returns `[1, 2]` — the last flagged index, `2`, wins the cancel slot; same test |
| ns-alert-message-presenter-004 | button-plan-skip-flagged, button-plan-cancel-slot | Same items, `closeAffordanceIndices == [0, 1, 2]` (every item flagged) | Returns `[2]` — no ordinary button survives the skip; same test |
| ns-alert-message-presenter-005 | button-plan-skip-flagged, button-plan-cancel-slot | `itemTitles == ["A"]`, `closeAffordanceIndices == []` | Returns `[0, nil]` — same test |
| ns-alert-message-presenter-006 | button-plan-skip-flagged, button-plan-cancel-slot | `itemTitles == ["A"]`, `closeAffordanceIndices == [0]` | Returns `[0]` — same test |
| ns-alert-message-presenter-007 | escape-key-position-rule | `escapeKeyEquivalentPosition(in:)` on `[0, 1, 2, nil]`, `[1, 2, 0]`, and `[1, 2]` | Returns `3`, `2`, and `1` respectively — each plan's own `count - 1` — `MainThreadWindowTests.escapeKeyEquivalentPositionIsTheCancelSlotOnlyWhenThePlanHasMoreThanOneButton` |
| ns-alert-message-presenter-008 | escape-key-position-rule | Same function on `[0]` and `[2]` (one-entry plans) | Returns `nil` for both — same test |
| ns-alert-message-presenter-009 | empty-items-single-ok | `presentMessage(_:)` on a request with `itemTitles == []`, presented by a conformer with a window available | Adds exactly one `OK` button and returns `nil` unconditionally, regardless of that button's response; traced to the source's `guard !request.itemTitles.isEmpty else { ...; return nil }` branch — not exercised by any given test, since every `MainThreadWindowTests` case substitutes a `RecordingMessagePresenter`/`SuspendingMessagePresenter` test double for `NSAlertMessagePresenter` itself |
| ns-alert-message-presenter-010 | severity-style-mapping | `alertStyle(for:)` on `.information`, `.warning`, and `.error` | Returns `.informational`, `.warning`, and `.critical` respectively; traced to the source's `switch` statement — not exercised by any given test |
| ns-alert-message-presenter-011 | drop-when-no-window, dropped-message-logged | `presentMessage(_:)` where the injected `window` closure returns `nil` and no window in `NSApp.windows` satisfies both `isVisible` and `canBecomeMain` | `sheetWindow()` returns `nil`; `presentedResponse(for:)` logs an error-level message and returns `nil` without calling `beginSheetModal(for:completionHandler:)`; `presentMessage(_:)` resolves to `nil`; traced to the source — not exercised by any given test, since running it would put a sheet on screen or require a stubbed `NSApp.windows` the given sources do not provide |
| ns-alert-message-presenter-012 | response-to-item-index, out-of-range-response-resolves-nil | `presentMessage(_:)` on a non-empty-items request where the user's response, once reduced to `buttonIndex`, falls within `buttonItemIndices`'s bounds, versus a (defensive) case where it does not | Returns `buttonItemIndices[buttonIndex]` (an item index, or `nil` for the cancel slot) in the first case, and `nil` in the second without an out-of-bounds trap; traced to the source's two-guard structure — not exercised by any given test |

## Edge Cases

- **Null/empty input**: `request.itemTitles == []` MUST make `presentMessage(_:)` add a single `OK` button and return `nil` unconditionally, per **empty-items-single-ok** (MUST).
- **Null/empty input**: `request.detail == nil` MUST be treated as "assign nothing to `informativeText`," not coerced to an empty string, per **detail-text-conditional** (MUST).
- **Null/empty input**: `request.message == ""` MUST be accepted and assigned to `messageText` unchanged; the code performs no non-empty validation, so a caller MUST NOT assume `message` is non-empty before this presenter is reached (MUST NOT).
- **Boundary values**: `itemTitles` of exactly one entry, unflagged, MUST make `buttonPlan(for:)` return a two-entry plan (`[0, nil]`), and `escapeKeyEquivalentPosition(in:)` MUST then assign Escape to the second (cancel) slot, since `plan.count > 1` (MUST).
- **Boundary values**: `itemTitles` of exactly one entry, flagged `isCloseAffordance`, MUST make `buttonPlan(for:)` return a one-entry plan (`[0]`) holding that item's own index, and `escapeKeyEquivalentPosition(in:)` MUST return `nil` for it, leaving that sole button's default Return key equivalent untouched, per the source's own rationale for why a one-entry plan is the exception (MUST).
- **Boundary values**: every entry in `itemTitles` flagged (two or more items) MUST make `buttonPlan(for:)` return a one-entry plan holding only the *last* flagged index; every other flagged item's button MUST NOT be added (MUST / MUST NOT).
- **Concurrent access**: `@MainActor` isolation serializes the synchronous portion of each `presentMessage(_:)` call on a given instance, but does not by itself serialize the calls across the `await` inside `presentedResponse(for:)` — see **concurrent-presentation-ordering** below.
- **Concurrent access**: because `NSAlertMessagePresenter` declares no `Sendable` conformance, an instance MUST NOT be called from outside its main actor's isolation domain except by `await`ing across that boundary (MUST NOT).
- **Error states**: `sheetWindow()` returning `nil` (no window anywhere in the app) MUST cause the message to be logged at `error` level and MUST resolve `presentMessage(_:)` to `nil` rather than crash, throw, or block the caller, per **drop-when-no-window** and **dropped-message-logged** (MUST).
- **Error states**: a `buttonIndex` computed from the sheet's response that does not index into `buttonItemIndices` MUST resolve to `nil` rather than trap on an out-of-bounds array subscript, per **out-of-range-response-resolves-nil** (MUST).
- **Cancellation and timeouts**: `presentMessage(_:)` defines no timeout of its own and does not observe `Task` cancellation; a caller whose enclosing `Task` is cancelled while awaiting `presentMessage(_:)` MUST NOT assume the sheet is dismissed or the underlying continuation is resumed early, because the source implements no cancellation-handling path for this call (MUST NOT).
- **Offline or disconnected state**: not applicable — the source imports only `AppKit`, `Foundation`, `OSLog`, and `AgenticToolkitCore`, and performs no network access of its own.
- **Missing file or unreachable server**: not applicable — the source opens no file and makes no network or process call of its own.

- **concurrent-presentation-ordering**: `NSAlertMessagePresenter` is `@MainActor`, so each `presentMessage(_:)` call's synchronous portion runs serially, but the actor is reentrant at the `await` inside `presentedResponse(for:)`: a second call MAY reach `beginSheetModal(for:completionHandler:)` before the first sheet is dismissed. The presenter adds no queuing or coalescing of its own; a second sheet on the same window is ordered by AppKit's own sheet queue, and each call's continuation resumes independently with its own sheet's response.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `window` | `() -> NSWindow?` | none (required; `init(window:)` takes no default) | Queried fresh by `sheetWindow()` on every `presentMessage(_:)` call to decide which window a sheet attaches to; a `nil` result falls back to `anyVisibleWindow()` before the message is dropped. |
| `request` | `ExtensionMessageRequest` | none (required, supplied per call to `presentMessage(_:)`) | The per-call payload — `severity`, `message`, `detail`, `isModal`, `itemTitles`, `closeAffordanceIndices`; its own field shapes, defaults, and invariants are documented in [ExtensionMessagePresenting](agentictoolkit://cookbook/macos/features/extensions/vs-code-api/extension-message-presenting) rather than restated here. |

## Deep Linking

Not applicable: `NSAlertMessagePresenter.swift` defines no URL, route, or navigable destination — it presents a modal sheet in place and has no navigation surface of its own.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — hardcoded literal) | `OK` | The single button title added when `request.itemTitles` is empty. |
| (none — hardcoded literal) | `Cancel` | The title given the synthesized cancel-slot button whenever `buttonPlan(for:)`'s cancel entry is `nil`. |

Both are literal English string constants in the source, assigned with no `String(localized:)` call and no String Catalog entry, so the code presents them in English regardless of the user's system locale. `request.message`, `request.detail`, and `request.itemTitles` are passed through verbatim from the caller and are not this file's own strings to localize.

## Accessibility Options

Not applicable: `NSAlertMessagePresenter.swift` reads no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color) of its own; any such behavior in the sheet it presents is `NSAlert`'s own AppKit-level behavior, not logic this file implements.

## Feature Flags

Not applicable: the source declares no feature-flag key and contains no conditional feature-gating logic.

## Analytics

Not applicable: the source contains no analytics or event-emission call of any kind.

## Privacy

- **Data collected**: `NSAlertMessagePresenter` collects nothing of its own; `request.message`, `request.detail`, and `request.itemTitles` are whatever text the calling extension supplied to a `show*Message` call, held only as fields of the `ExtensionMessageRequest` value for the duration of one `presentMessage(_:)` call.
- **Storage**: the file performs no storage of its own; nothing here persists a request past the call it was built for.
- **Transmission**: the file performs no network transmission; the request is presented in-process, via AppKit, to whatever window `sheetWindow()` resolves.
- **Retention**: the one thing that outlives a single call is the dropped-message log line `presentedResponse(for:)` writes when `sheetWindow()` returns `nil`; that line includes `alert.messageText` (i.e., `request.message`) marked `privacy: .public`, so — unlike a `privacy: .private` value — it is not redacted from the unified log, whatever text the calling extension put in that message; retention of that log entry itself is governed by the OS's unified-logging policy, not by this file.

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (falls back to `"nil"` if unset, via the shared `Loggable` protocol) | Category: `NSAlertMessagePresenter`

| Event | Level | Message |
|-------|-------|---------|
| `sheetWindow()` returns `nil` while presenting a message | error | `Dropped a show*Message; no window for its sheet: ` followed by `alert.messageText`, logged with `privacy: .public` |

## Platform Notes

- **SwiftUI**: reproduce `buttonPlan(for:)` as a plain Swift function and feed its entries into `.alert(_:isPresented:actions:)` (or `.confirmationDialog` for a longer button list, since SwiftUI's alert API is best suited to a small, fixed count), giving the cancel-slot entry's `Button` a `role: .cancel` so SwiftUI supplies its own default/Escape handling rather than a manually assigned key equivalent the way `addButtons(for:to:)` does.
- **Compose**: `AlertDialog`'s `confirmButton`/`dismissButton` slots cover at most two buttons; for the general case, matching this presenter's unbounded `itemTitles` list, render a `Column` of `TextButton`s inside `AlertDialog`'s `text` slot, driven by the same `buttonPlan`-equivalent skip-and-collapse function. Compose has no sheet-versus-application-modal distinction to preserve, so the source's "never activate the app" constraint has no direct analogue to violate.
- **React/Web**: build a modal (a native `dialog` element, or a design-system modal) rather than `window.confirm`/`window.alert`, since neither supports more than one fixed OK/Cancel pair; reproduce `buttonPlan(for:)` as a pure function over `itemTitles`/`closeAffordanceIndices` driving the rendered button list, and model the "nothing to attach to" fallback as resolving the returned `Promise` with `null`, logged rather than thrown, when no container element is mounted.
- **AppKit / UIKit**: this is the source. `NSAlertMessagePresenter.swift` (`packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/`) belongs to the `AgenticToolkitMacOS` framework target and uses `NSAlert`, `NSAlert.Style`, `NSApplication.ModalResponse`, and `beginSheetModal(for:completionHandler:)` bridged into `async` with `withCheckedContinuation`. A UIKit iOS port would use `UIAlertController` with `UIAlertAction`s and `present(_:animated:completion:)`; because an iOS app is always in the foreground, the "no window anywhere, drop the message" fallback this file implements has a much narrower analogue there — a root view controller that has not yet attached to a window.
- **WinUI 3**: present with `ContentDialog`, whose `PrimaryButtonText`/`SecondaryButtonText`/`CloseButtonText` give exactly three button slots — fewer than `NSAlert`'s unbounded button list — so a request needing more than three effective buttons, after the same last-wins cancel-slot collapse **button-plan-cancel-slot** requires, needs either a custom `ContentDialog` body with its own `StackPanel` of `Button` controls wired to close the dialog with a result, or `Windows.UI.Popups.MessageDialog` with its own capped `UICommand` list — either way the port must reimplement `buttonPlan(for:)`'s skip-and-collapse logic itself. Call `ContentDialog.ShowAsync`, which is already the WinUI analogue of a sheet attached to the current window rather than an application-modal call that activates a different one, and marshal onto the `DispatcherQueue` a `@MainActor` maps to via `DispatcherQueue.TryEnqueue` when invoked off that queue. Model "no window to attach to" as "no `XamlRoot` is available," logged and resolved as `ContentDialogResult.None` rather than shown, mirroring this file's own drop-and-log fallback; `Task`/`async`/`await` plays the role of Swift's `async`, and there is no `CancellationToken` wired up here, matching the Edge Cases entry on cancellation.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/NSAlertMessagePresenter.swift` |

## Design Decisions

**Decision**: presentation is always a sheet, never an application-modal alert.
**Rationale**: stated in the type's own doc comment — this is an `LSUIElement` menu-bar app for which `NSAlert.runModal()` would activate the app and make its window key, seizing the screen from whoever is typing, and would additionally block the main thread until dismissed, risking a UI wedge if no window happens to be available.
**Approved**: pending

**Decision**: with no window anywhere in the app, the message is dropped (logged, resolved `nil`) rather than shown by any other means.
**Rationale**: stated in the type's own doc comment — there is no surface a sheet can attach to that does not seize the screen, so the message is logged and resolved the same as a user dismissal, a state `vscode.d.ts` already requires every caller to handle; losing one extension's message is judged the smaller harm.
**Approved**: pending

**Decision**: `window` is an injected closure with no default value.
**Rationale**: stated in `init(window:)`'s own doc comment — the no-window fallback must be an explicit choice a caller made, not an incidental default the initializer picked, and not guessed at from `NSApplication.shared` or another ambient source.
**Approved**: pending

**Decision**: `buttonPlan(for:)` and `escapeKeyEquivalentPosition(in:)` are `internal`, not `private`.
**Rationale**: stated in both functions' own doc comments — `MainThreadWindowTests` calls each directly through `@testable import AgenticToolkitMacOS`, and tightening either to `private` compiles here but breaks that suite.
**Approved**: pending

**Decision**: Escape is assigned to the cancel-slot button only when the plan has more than one entry.
**Rationale**: stated in `escapeKeyEquivalentPosition(in:)`'s own doc comment — on a one-entry plan, the cancel slot is also the sole button, which `NSAlert` already gives Return by default; assigning Escape there would replace Return (and its default-button status) for no behavioral gain, since a one-entry plan only arises when every item was flagged and the sole button already is the close affordance.
**Approved**: pending

**Decision**: `closeAffordanceIndices`'s last-wins tie-break in the cancel slot is applied here, not re-derived here.
**Rationale**: the rule itself — the *last* flagged item's index wins the single cancel slot — is documented in full, with its upstream justification, in [ExtensionMessagePresenting](agentictoolkit://cookbook/macos/features/extensions/vs-code-api/extension-message-presenting)'s Design Decisions; **button-plan-cancel-slot** in this recipe applies that same rule to this conformer's concrete AppKit button layout rather than restating the rationale.
**Approved**: pending

**Decision**: `presentedResponse(for:)` bridges `beginSheetModal(for:completionHandler:)` into `async` with `withCheckedContinuation`, unlike every other `beginSheetModal` site in this tier.
**Rationale**: stated in the source's own doc comment as a claim measured against the rest of the `macOS/` tier — every other `beginSheetModal` site (`ComposableTabsPaneViewController`, `AISettingsViewPanelController`, `ExtensionsSettingsPanelViewController`, `NotesFolderListViewController`, `NotesSplitViewController`) drives its completion handler directly, while this presenter must be `async` to satisfy `ExtensionMessagePresenting`; `withCheckedContinuation` itself is not unprecedented in the tier (`ExtensionHost.swift` uses one for a JS activation callback), only its pairing with `NSAlert`/`beginSheetModal` is.
**Approved**: pending

**Decision**: this recipe traces `presentMessage(_:)`, `sheetWindow()`, `presentedResponse(for:)`, `alertStyle(for:)`, and `anyVisibleWindow()` to the source only, with no given test exercising any of them directly.
**Rationale**: every case in `MainThreadWindowTests.swift` that exercises message presentation substitutes a `RecordingMessagePresenter` or `SuspendingMessagePresenter` test double for `NSAlertMessagePresenter` precisely to avoid putting a real sheet on screen during a test run; `buttonPlan(for:)` and `escapeKeyEquivalentPosition(in:)` were split out as `internal`, side-effect-free functions specifically so something about the button layout could still be pinned without running `beginSheetModal(for:completionHandler:)`.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | passed | Reliability |
| [secure-log-output](agenticdevelopercookbook://compliance/security#secure-log-output) | failed | Security |

`separation-of-concerns` passes because the file's own header comment states it was split out of `MainThreadWindow.swift` specifically to keep the adaptor's argument parsing and promise settlement testable without AppKit, and the file itself confines its own responsibility to turning one `ExtensionMessageRequest` into `NSAlert` calls and back into an index. `unit-test-coverage` is partial: `MainThreadWindowTests` directly pins `buttonPlan(for:)` and `escapeKeyEquivalentPosition(in:)`, but every test exercising message *presentation* substitutes a `RecordingMessagePresenter`/`SuspendingMessagePresenter` double for `NSAlertMessagePresenter` itself, so `presentMessage(_:)`, `sheetWindow()`, `presentedResponse(for:)`, `alertStyle(for:)`, and `anyVisibleWindow()` have no given test of their own. `fault-tolerance` passes: the no-window case (**drop-when-no-window**) and an out-of-range button response (**out-of-range-response-resolves-nil**) both resolve to `nil` rather than crash, block, or throw, and neither depends on an external service being reachable. `secure-log-output` fails: `presentedResponse(for:)`'s dropped-message log interpolates `alert.messageText` — i.e., `request.message`, arbitrary caller-supplied text with no length or content constraint — with `privacy: .public`, so any sensitive content an extension happened to put in that message is not redacted from the unified log, contrary to the guideline's requirement that log output not carry PII.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
