---
id: 77fe79f8-7d45-4e51-aee0-d6de78b459e1
title: Alert Message Presenter
domain: agentictoolkit://cookbook/workspace/extensions/vscode-api/window/alert-message-presenter
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'The one given implementation of the message-presenting role: presents
  a vscode.window.show*Message request as a native alert attached to a window,
  or drops it when no window is available.'
platforms:
- swift
- macos
tags:
- extension-host
- vscode-api
- message-presenting
depends-on:
- agentictoolkit://cookbook/workspace/extensions/vscode-api/window/extension-message-presenting
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

# Alert Message Presenter

## Overview

This component is the one production implementation of the message-presenting
role documented in [Extension Message Presenting](agentictoolkit://cookbook/workspace/extensions/vscode-api/window/extension-message-presenting)
given among the sources: it turns a `vscode.window.show*Message` request into
a native alert attached to a window. Where the protocol recipe documents the
contract every implementation must satisfy, this recipe documents this
implementation's own presentation choices: always a window-attached alert,
attached to a window read fresh from an injected window-lookup function
rather than guessed at from ambient application state; never an
application-wide modal alert, because this is a background-only app with no
dock icon, for which activating unexpectedly would seize the screen from
whoever is typing; and, with no window anywhere in the app to attach an
alert to, the message is logged and dropped rather than shown by any means
that would seize the screen. The type also derives the button layout —
including which button carries the Escape key equivalent — from the
request's item titles and close-affordance indices, and reports, through
this project's shared logging convention, the one failure mode it can reach
on its own: a dropped, never-shown message.

## Behavioral Requirements

- **thread-confined-role-conformance**: this component MUST be confined to a
  single execution context, and MUST conform to the message-presenting role.
- **explicit-window-parameter**: constructing this component MUST take a
  window-lookup function with no default value, so a caller MUST make an
  explicit choice about which window (if any) an alert attaches to, rather
  than construction picking one implicitly.
- **injected-window-storage**: the injected window-lookup function MUST be
  stored privately, set once at construction and never reassigned.
- **window-queried-per-presentation**: resolving the presentation window
  MUST call the injected window-lookup function fresh on every invocation
  rather than caching its result at construction, so the answer reflects
  whichever window is frontmost at presentation time.
- **presentation-window-fallback**: resolving the presentation window MUST
  return the injected window-lookup function's value when it is present,
  and otherwise MUST return the value of selecting any visible window.
- **any-visible-window-selection**: selecting any visible window MUST return
  the first window, among those the app currently has, for which both
  visibility and eligibility to become the main window are true, and MUST
  return nothing when no such window exists.
- **window-attached-presentation-only**: presenting a request MUST present
  every request as an alert attached to the resolved presentation window.
- **no-app-activation**: presenting a request MUST NOT call an
  application-wide modal presentation, or any other presentation approach
  that activates the app or makes a window key when the app is not already
  active.
- **drop-when-no-window**: when resolving the presentation window yields no
  window, resolving the response MUST NOT present the alert by any means,
  and MUST resolve to nothing.
- **dropped-message-logged**: whenever resolving the response drops a
  message because no presentation window was found, it MUST log an
  error-level message under this component's own logging identity, and
  MUST NOT log anything when a window is found.
- **message-text-assignment**: presenting a request MUST set the alert's
  message text to the request's message unconditionally, including when
  the request's message is an empty string.
- **detail-text-conditional**: presenting a request MUST set the alert's
  detail text to the request's detail when it is present, and MUST leave
  the detail text at whatever default the native alert itself assigns when
  the request's detail is absent.
- **severity-style-mapping**: mapping a severity to an alert style MUST map
  the request's severity to the platform's alert-style vocabulary as
  information to informational, warning to warning, and error to critical,
  and presenting a request MUST assign that mapped value to the alert's
  style.
- **empty-items-single-ok**: when the request's item titles are empty,
  presenting a request MUST add exactly one button titled `OK`, MUST await
  its presentation, and MUST return nothing regardless of which response
  that presentation produces.
- **button-plan-skip-flagged**: for a non-empty set of item titles, planning
  the button layout MUST include, in item-title order, the index of every
  item whose index is not a member of the request's close-affordance
  indices.
- **button-plan-cancel-slot**: planning the button layout MUST append
  exactly one further entry after that skip pass: the last close-affordance
  index when the close-affordance indices are non-empty, or nothing
  (denoting a synthesized cancel button) when they are empty.
- **button-titles-from-plan**: adding the buttons MUST add exactly one
  button per button-plan entry, in plan order, titled with the
  corresponding item title for an entry naming an item index and titled
  `Cancel` for an entry denoting the synthesized cancel button.
- **escape-key-position-rule**: computing the Escape-key position MUST
  return the plan's last index when the plan has more than one entry, and
  MUST return nothing when the plan has one entry or is empty.
- **escape-key-assignment**: adding the buttons MUST assign the Escape
  character as the keyboard equivalent of the button at the position
  computing the Escape-key position returns, when that position is
  present, and MUST leave every other added button's keyboard equivalent
  at whatever default the native alert itself assigns it.
- **response-to-item-index**: on a non-empty-items alert, presenting a
  request MUST compute a button index by comparing the user's response
  against the platform's first-button response baseline, and MUST return
  the corresponding button-plan entry — itself nothing when that plan entry
  is the synthesized cancel button — as the call's result.
- **out-of-range-response-resolves-absent**: if the computed button index does
  not index into the button-plan entries, presenting a request MUST return
  nothing rather than access the entries out of bounds.
- **no-throwing-path**: presenting a request MUST NOT fail under any input
  or presentation outcome, matching the message-presenting role's
  non-failing requirement.
- **is-modal-not-honored**: presenting a request MUST NOT read or branch on
  the request's modal flag; every request MUST be presented as a
  window-attached alert regardless of that field's value.
- **logger-identity**: this component MUST log under its own name as
  category, with a subsystem derived from the app's own identifier (or a
  fixed fallback literal when unset), matching the shared logging
  convention this project's components use.
- **thread-confined-external-access**: a caller outside this component's own
  confined execution context MUST reach any of its operations only through
  an asynchronous call across that boundary.

## Appearance

Not applicable — this is a message-presentation implementation that hands the request to a system-drawn native alert, not a custom visual component with appearance of its own to specify.

## States

Not applicable — this is a message-presentation implementation that hands the request to a system-drawn native alert, not a custom visual component with a visual-state table. The per-call sequencing this type has (build an alert, present it as a window-attached alert or drop it, resolve an index or nothing) is captured under Behavioral Requirements, not here.

## Accessibility

Not applicable — this is a message-presentation implementation that hands the request to a system-drawn native alert, not a custom visual component. Whatever accessibility behavior the presented alert has is the platform's own native-alert behavior; this component implements no accessibility logic of its own.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| ns-alert-message-presenter-001 | button-plan-skip-flagged, button-plan-cancel-slot | Plan the button layout for item titles `["A", "B", "C"]` with close-affordance indices `[]` | Returns `[0, 1, 2, nothing]` |
| ns-alert-message-presenter-002 | button-plan-skip-flagged, button-plan-cancel-slot | Same items, close-affordance indices `[0]` | Returns `[1, 2, 0]` |
| ns-alert-message-presenter-003 | button-plan-skip-flagged, button-plan-cancel-slot | Same items, close-affordance indices `[0, 2]` (two items flagged) | Returns `[1, 2]` — the last flagged index, `2`, wins the cancel slot |
| ns-alert-message-presenter-004 | button-plan-skip-flagged, button-plan-cancel-slot | Same items, close-affordance indices `[0, 1, 2]` (every item flagged) | Returns `[2]` — no ordinary button survives the skip |
| ns-alert-message-presenter-005 | button-plan-skip-flagged, button-plan-cancel-slot | Item titles `["A"]`, close-affordance indices `[]` | Returns `[0, nothing]` |
| ns-alert-message-presenter-006 | button-plan-skip-flagged, button-plan-cancel-slot | Item titles `["A"]`, close-affordance indices `[0]` | Returns `[0]` |
| ns-alert-message-presenter-007 | escape-key-position-rule | Compute the Escape-key position for the plans `[0, 1, 2, nothing]`, `[1, 2, 0]`, and `[1, 2]` | Returns `3`, `2`, and `1` respectively — each plan's own last index |
| ns-alert-message-presenter-008 | escape-key-position-rule | Same computation on `[0]` and `[2]` (one-entry plans) | Returns nothing for both |
| ns-alert-message-presenter-009 | empty-items-single-ok | Present a request with empty item titles, presented with a window available | Adds exactly one `OK` button and returns nothing unconditionally, regardless of that button's response |
| ns-alert-message-presenter-010 | severity-style-mapping | Map the severities information, warning, and error to an alert style | Returns informational, warning, and critical respectively |
| ns-alert-message-presenter-011 | drop-when-no-window, dropped-message-logged | Present a request where the injected window-lookup function returns nothing and no window the app currently has satisfies both visibility and eligibility to become the main window | Resolving the presentation window returns nothing; resolving the response logs an error-level message and returns nothing without presenting any alert; presenting the request resolves to nothing |
| ns-alert-message-presenter-012 | response-to-item-index, out-of-range-response-resolves-absent | Present a non-empty-items request where the user's response, once reduced to a button index, falls within the button-plan entries' bounds, versus a (defensive) case where it does not | Returns the corresponding button-plan entry (an item index, or nothing for the cancel slot) in the first case, and nothing in the second without an out-of-bounds access |

## Edge Cases

- **Null/empty input**: an empty set of item titles MUST make presenting a
  request add a single `OK` button and return nothing unconditionally, per
  **empty-items-single-ok** (MUST).
- **Null/empty input**: an absent detail MUST be treated as "assign nothing
  to the detail text," not coerced to an empty string, per
  **detail-text-conditional** (MUST).
- **Null/empty input**: an empty message string MUST be accepted and
  assigned to the message text unchanged; the code performs no non-empty
  validation, so a caller MUST NOT assume the message is non-empty before
  this presenter is reached (MUST NOT).
- **Boundary values**: item titles of exactly one entry, unflagged, MUST
  make planning the button layout return a two-entry plan (`[0, nothing]`),
  and computing the Escape-key position MUST then assign Escape to the
  second (cancel) slot, since the plan has more than one entry (MUST).
- **Boundary values**: item titles of exactly one entry, flagged as a close
  affordance, MUST make planning the button layout return a one-entry plan
  (`[0]`) holding that item's own index, and computing the Escape-key
  position MUST return nothing for it, leaving that sole button's default
  key equivalent untouched, per the source's own rationale for why a
  one-entry plan is the exception (MUST).
- **Boundary values**: every entry in the item titles flagged (two or more
  items) MUST make planning the button layout return a one-entry plan
  holding only the *last* flagged index; every other flagged item's button
  MUST NOT be added (MUST / MUST NOT).
- **Concurrent access**: this component's confinement to a single execution
  context serializes the synchronous portion of each presentation call on
  a given instance, but does not by itself serialize the calls across the
  asynchronous wait inside resolving the response — see
  **concurrent-presentation-ordering** below.
- **Concurrent access**: an instance MUST NOT be called from outside its
  own confined execution context except by an asynchronous call across
  that boundary (MUST NOT).
- **Error states**: resolving the presentation window returning nothing (no
  window anywhere in the app) MUST cause the message to be logged at error
  level and MUST resolve presenting a request to nothing rather than
  crash, fail, or block the caller, per **drop-when-no-window** and
  **dropped-message-logged** (MUST).
- **Error states**: a button index computed from the alert's response that
  does not index into the button-plan entries MUST resolve to nothing
  rather than trap on an out-of-bounds access, per
  **out-of-range-response-resolves-absent** (MUST).
- **Cancellation and timeouts**: presenting a request defines no timeout of
  its own and does not observe cancellation of its enclosing task; a caller
  whose enclosing task is cancelled while awaiting presentation MUST NOT
  assume the alert is dismissed or the underlying wait is resumed early,
  because the source implements no cancellation-handling path for this call
  (MUST NOT).
- **Offline or disconnected state**: not applicable — the source performs
  no network access of its own.
- **Missing file or unreachable server**: not applicable — the source opens
  no file and makes no network or process call of its own.

- **concurrent-presentation-ordering**: this component is confined to a
  single execution context, so each presentation call's synchronous
  portion runs serially, but that confinement is reentrant at the
  asynchronous wait inside resolving the response: a second call MAY reach
  the underlying presentation call before the first alert is dismissed. The
  presenter adds no queuing or coalescing of its own; a second alert on the
  same window is ordered by the platform's own alert queue, and each call's
  wait resumes independently with its own alert's response.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `window` | window-lookup function | none (required; construction takes no default) | Queried fresh on every presentation call to decide which window an alert attaches to; an absent result falls back to selecting any visible window before the message is dropped. |
| `request` | message request | none (required, supplied per presentation call) | The per-call payload — severity, message, detail, modal flag, item titles, close-affordance indices; its own field shapes, defaults, and invariants are documented in [Extension Message Presenting](agentictoolkit://cookbook/workspace/extensions/vscode-api/window/extension-message-presenting) rather than restated here. |

## Deep Linking

Not applicable: this component defines no URL, route, or navigable destination — it presents a window-attached alert in place and has no navigation surface of its own.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — hardcoded literal) | `OK` | The single button title added when the request's item titles are empty. |
| (none — hardcoded literal) | `Cancel` | The title given the synthesized cancel-slot button whenever the button plan's cancel entry is absent. |

Both are literal English string constants, assigned with no localization lookup and no string-table entry, so the code presents them in English regardless of the user's system locale. The request's message, detail, and item titles are passed through verbatim from the caller and are not this component's own strings to localize.

## Accessibility Options

Not applicable: this component reads no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color) of its own; any such behavior in the alert it presents is the platform's own native-alert behavior, not logic this component implements.

## Feature Flags

Not applicable: this component declares no feature-flag key and contains no conditional feature-gating logic.

## Analytics

Not applicable: this component contains no analytics or event-emission call of any kind.

## Privacy

- **Data collected**: this component collects nothing of its own; the
  request's message, detail, and item titles are whatever text the calling
  extension supplied to a `show*Message` call, held only as fields of the
  request value for the duration of one presentation call.
- **Storage**: this component performs no storage of its own; nothing here
  persists a request past the call it was built for.
- **Transmission**: this component performs no network transmission; the
  request is presented in-process to whatever window resolving the
  presentation window resolves.
- **Retention**: the one thing that outlives a single call is the
  dropped-message log line resolving the response writes when resolving
  the presentation window returns nothing; that line includes the alert's
  message text (i.e., the request's message), logged so that it is not
  redacted from the log, whatever text the calling extension put in that
  message; retention of that log entry itself is governed by the
  platform's own logging policy, not by this component.

## Logging

Subsystem: the app's own identifier (or a fixed fallback literal when unset) | Category: this component's own name

| Event | Level | Message |
|-------|-------|---------|
| Resolving the presentation window returns nothing while presenting a message | error | `Dropped a show*Message; no window for its sheet: ` followed by the alert's message text, logged without redaction |

## Platform Notes

- **SwiftUI**: reproduce `buttonPlan(for:)` as a plain Swift function and feed its entries into `.alert(_:isPresented:actions:)` (or `.confirmationDialog` for a longer button list, since SwiftUI's alert API is best suited to a small, fixed count), giving the cancel-slot entry's `Button` a `role: .cancel` so SwiftUI supplies its own default/Escape handling rather than a manually assigned key equivalent the way `addButtons(for:to:)` does.
- **Compose**: `AlertDialog`'s `confirmButton`/`dismissButton` slots cover at most two buttons; for the general case, matching this presenter's unbounded `itemTitles` list, render a `Column` of `TextButton`s inside `AlertDialog`'s `text` slot, driven by the same `buttonPlan`-equivalent skip-and-collapse function. Compose has no sheet-versus-application-modal distinction to preserve, so the source's "never activate the app" constraint has no direct analogue to violate.
- **React/Web**: build a modal (a native `dialog` element, or a design-system modal) rather than `window.confirm`/`window.alert`, since neither supports more than one fixed OK/Cancel pair; reproduce `buttonPlan(for:)` as a pure function over `itemTitles`/`closeAffordanceIndices` driving the rendered button list, and model the "nothing to attach to" fallback as resolving the returned `Promise` with `null`, logged rather than thrown, when no container element is mounted.
- **AppKit / UIKit**: this is the source. `NSAlertMessagePresenter.swift` (`packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/`) belongs to the `AgenticToolkitMacOS` framework target and uses `NSAlert`, `NSAlert.Style`, `NSApplication.ModalResponse`, and `beginSheetModal(for:completionHandler:)` bridged into `async` with `withCheckedContinuation`. Concretely: the type is declared `final`, `public`, and `@MainActor`, and conforms to `ExtensionMessagePresenting`; the injected window-lookup function is stored as `private let window: () -> NSWindow?`; `sheetWindow()` returns `window()`'s value when non-nil, else `anyVisibleWindow()`'s value, which itself scans `NSApp.windows` for the first entry with both `isVisible` and `canBecomeMain` true; `presentMessage(_:)` calls `NSAlert.beginSheetModal(for:completionHandler:)` on that window and never `NSAlert.runModal()`; it sets `NSAlert.messageText`/`informativeText`, maps severity to `NSAlert.Style` (`.information`→`.informational`, `.warning`→`.warning`, `.error`→`.critical`) and assigns `NSAlert.alertStyle`; it computes `buttonIndex` from the user's `NSApplication.ModalResponse` minus `NSApplication.ModalResponse.alertFirstButtonReturn`; `presentedResponse(for:)` bridges `beginSheetModal(for:completionHandler:)`'s completion handler into `async` using `withCheckedContinuation`, resuming with the `NSApplication.ModalResponse` the handler is given; `buttonPlan(for:)` and `escapeKeyEquivalentPosition(in:)` are kept at `internal` access rather than `private` specifically because `MainThreadWindowTests` calls each directly through `@testable import AgenticToolkitMacOS`; the type declares no `Sendable` conformance of its own, and because it is `@MainActor`-isolated, its stored-property access and the synchronous portion of every method run on the main actor; it conforms to `Loggable` with `logger = makeLogger()`, giving it an `OSLog` category of `NSAlertMessagePresenter` and a subsystem of `Bundle.main.bundleIdentifier` (or the literal string `"nil"` when unset), per `Loggable`'s own defaults, and its dropped-message log line marks `alert.messageText` with `privacy: .public` rather than `.private` so it is not redacted from the unified log. The app itself is an `LSUIElement` menu-bar app, which is why an app-modal alert is avoided. Per the file's own header comment, this type was split out of `MainThreadWindow.swift` once that adaptor grew past 2,800 lines. A UIKit iOS port would use `UIAlertController` with `UIAlertAction`s and `present(_:animated:completion:)`; because an iOS app is always in the foreground, the "no window anywhere, drop the message" fallback this file implements has a much narrower analogue there — a root view controller that has not yet attached to a window.
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
**Rationale**: the rule itself — the *last* flagged item's index wins the single cancel slot — is documented in full, with its upstream justification, in [ExtensionMessagePresenting](agentictoolkit://cookbook/workspace/extensions/vscode-api/window/extension-message-presenting)'s Design Decisions; **button-plan-cancel-slot** in this recipe applies that same rule to this conformer's concrete AppKit button layout rather than restating the rationale.
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

`separation-of-concerns` passes because the file's own header comment states it was split out of `MainThreadWindow.swift` specifically to keep the adaptor's argument parsing and promise settlement testable without AppKit, and the file itself confines its own responsibility to turning one `ExtensionMessageRequest` into `NSAlert` calls and back into an index. `unit-test-coverage` is partial: `MainThreadWindowTests` directly pins `buttonPlan(for:)` and `escapeKeyEquivalentPosition(in:)`, but every test exercising message *presentation* substitutes a `RecordingMessagePresenter`/`SuspendingMessagePresenter` double for `NSAlertMessagePresenter` itself, so `presentMessage(_:)`, `sheetWindow()`, `presentedResponse(for:)`, `alertStyle(for:)`, and `anyVisibleWindow()` have no given test of their own. `fault-tolerance` passes: the no-window case (**drop-when-no-window**) and an out-of-range button response (**out-of-range-response-resolves-absent**) both resolve to `nil` rather than crash, block, or throw, and neither depends on an external service being reachable. `secure-log-output` fails: `presentedResponse(for:)`'s dropped-message log interpolates `alert.messageText` — i.e., `request.message`, arbitrary caller-supplied text with no length or content constraint — with `privacy: .public`, so any sensitive content an extension happened to put in that message is not redacted from the unified log, contrary to the guideline's requirement that log output not carry PII.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/extensions/vscode-api/window/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
