---
id: 0aa82a1f-42ed-4585-9f65-bb20aa110712
title: ExtensionMessagePresenting
domain: agentictoolkit://recipes/extension-host-vs-code-api-extension-message-presenting
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: "The vscode.window.show*Message contract: a severity-tagged, Sendable request value and the @MainActor protocol that presents it and reports back which button, if any, was chosen."
platforms:
  - swift
  - macos
tags:
  - extension-host
  - vscode-api
  - message-presenting
depends-on: []
related: []
references:
  - packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/ExtensionMessagePresenting.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/NSAlertMessagePresenter.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadWindow.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Extensions/MainThreadWindowTests.swift (agentictoolkit)
approved-by: ""
approved-date: ""
---

# ExtensionMessagePresenting

## Overview

`ExtensionMessagePresenting` (`packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/ExtensionMessagePresenting.swift`) is the seam a `vscode.window.show*Message` call is reduced to before anything AppKit-specific gets involved. The file defines three things: `ExtensionMessageSeverity`, an enum for which of the three `show*Message` calls (`showInformationMessage`, `showWarningMessage`, `showErrorMessage`) produced the request; `ExtensionMessageRequest`, a `Sendable` value carrying everything a presenter needs to show something and report back which button — if any — the user chose; and `ExtensionMessagePresenting` itself, a `@MainActor`, class-only protocol with one method, `presentMessage(_:) async -> Int?`. Per the file's own header comment, it was split out of `MainThreadWindow.swift` once that adaptor grew past 2,800 lines — a file boundary, not a tier boundary, since `MainThreadWindow` remains the seam's only consumer of the protocol and its argument-parsing/promise-settlement logic is what the split keeps testable without AppKit. The one production conformer given among the sources, `NSAlertMessagePresenter`, presents a request with `NSAlert` as an app-modal-avoiding sheet; this recipe documents the contract that conformer (and any other) must satisfy, not that conformer's own presentation choices, except where the request struct's own doc comments describe an invariant a conformer is required to honor.

## Behavioral Requirements

- **severity-cases**: `ExtensionMessageSeverity` MUST expose exactly three cases — `information`, `warning`, and `error` — one per `vscode.window.show*Message` call kind.
- **severity-value-semantics**: `ExtensionMessageSeverity` MUST conform to `Sendable` and `Equatable`, and MUST carry no associated value on any case.
- **request-stored-shape**: `ExtensionMessageRequest` MUST carry exactly six immutable stored properties: `severity` (`ExtensionMessageSeverity`), `message` (`String`), `detail` (`String?`), `isModal` (`Bool`), `itemTitles` (`[String]`), and `closeAffordanceIndices` (`[Int]`).
- **request-sendable-only**: `ExtensionMessageRequest` MUST conform to `Sendable`; the source declares no `Equatable` conformance for it, so two request values MUST NOT be compared with a built-in `==` — a caller that needs equality must compare individual fields itself.
- **request-module-private-construction**: because the source declares no explicit `public init` for `ExtensionMessageRequest`, its Swift-synthesized memberwise initializer MUST remain at internal access; a caller outside the compiling module (`AgenticToolkitMacOS`) MUST NOT be able to construct an `ExtensionMessageRequest` value directly.
- **close-affordance-indices-are-a-list**: `closeAffordanceIndices` MUST hold every index into `itemTitles` whose corresponding message item carried a truthy `isCloseAffordance`, in item order, as a list rather than a single optional index, so that more than one flagged item is representable.
- **close-affordance-indices-empty-default**: `closeAffordanceIndices` MUST be empty when no item in `itemTitles` was flagged `isCloseAffordance`.
- **close-affordance-indices-within-item-bounds**: every value in `closeAffordanceIndices` MUST be a valid index into `itemTitles`; `ExtensionMessageRequest` performs no bounds check of its own, so upholding this invariant MUST be the responsibility of whatever constructs the request.
- **presenting-protocol-isolation**: `ExtensionMessagePresenting` MUST be declared `@MainActor`, so a conforming type's stored-property access and the synchronous portion of `presentMessage(_:)` MUST run on the main actor.
- **presenting-protocol-class-only**: `ExtensionMessagePresenting` MUST constrain conformers to `AnyObject`; a value type MUST NOT conform to it.
- **presenting-single-operation**: `ExtensionMessagePresenting` MUST declare exactly one requirement, `presentMessage(_ request: ExtensionMessageRequest) async -> Int?`, and MUST supply no default implementation for it.
- **present-message-return-index**: when the user chooses an item, `presentMessage(_:)` MUST return the index of that item into `request.itemTitles`.
- **present-message-return-nil-on-dismiss**: `presentMessage(_:)` MUST return `nil` when the user dismissed the message without choosing an item.
- **present-message-empty-items-always-nil**: `presentMessage(_:)` MUST return `nil` whenever `request.itemTitles` is empty, regardless of how the message was dismissed, because there is no item to choose.
- **present-message-no-throwing-path**: `presentMessage(_:)` MUST NOT throw; the protocol defines no error case, so a conformer that cannot present the message at all MUST resolve the call the same way as a user dismissal, `nil`, rather than signal the failure by any other means.
- **is-modal-carried-not-enforced**: `isModal` MUST be carried on `ExtensionMessageRequest` exactly as supplied; `ExtensionMessagePresenting` places no requirement on whether, or how, a conformer's presentation honors it.
- **detail-optional-presentation**: a conformer MAY omit presenting `detail` in its own surface when it is `nil`; the protocol imposes no non-nil or minimum-length constraint on either `message` or `detail`.

## Appearance

Not applicable — this is a data-and-protocol contract for the extension host, not a visual component.

## States

Not applicable — this is a data-and-protocol contract for the extension host, not a visual component. The only per-call sequencing this seam has (present, await a choice, resolve an index or nil) is captured under Behavioral Requirements, not as a visual-state table.

## Accessibility

Not applicable — this is a data-and-protocol contract for the extension host, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| extension-message-presenting-001 | present-message-empty-items-always-nil | `ExtensionMessageRequest(severity: .information, message: "m", detail: nil, isModal: true, itemTitles: [], closeAffordanceIndices: [])` presented via a conformer | `presentMessage(_:)` returns `nil`; traced to the source's own doc comment on `presentMessage`, "Always `nil` when `itemTitles` is empty," and to `NSAlertMessagePresenter.presentMessage(_:)`'s `guard !request.itemTitles.isEmpty else { ...; return nil }` branch |
| extension-message-presenting-002 | close-affordance-indices-are-a-list, close-affordance-indices-empty-default | Three `showWarningMessage` calls with, respectively, no item flagged `isCloseAffordance`, only the second item flagged, and the first and third items both flagged | `closeAffordanceIndices` is `[]`, `[1]`, and `[0, 2]` respectively — `MainThreadWindowTests.closeAffordanceIndicesReflectWhichItemsIfAnyAreMarkedCloseAffordance` |
| extension-message-presenting-003 | close-affordance-indices-are-a-list | `closeAffordanceIndices == [0, 2]` on `itemTitles == ["A", "B", "C"]` | A conformer honoring the request's own invariant renders ordinary buttons only for the un-flagged indices (`[1]`, i.e. `"B"`) and puts the *last* flagged index (`2`) in the single cancel/close slot — `NSAlertMessagePresenterTests`-equivalent assertion in `MainThreadWindowTests.buttonPlanOrdersButtonsAndFillsTheCancelSlotFromTheLastCloseAffordance`: `NSAlertMessagePresenter.buttonPlan(for:)` on this request returns `[1, 2]` |
| extension-message-presenting-004 | close-affordance-indices-are-a-list, close-affordance-indices-within-item-bounds | `closeAffordanceIndices == [0, 1, 2]` on `itemTitles == ["A", "B", "C"]` (every item flagged) | The cancel slot alone carries the *last* flagged index (`2`); no ordinary button remains — `MainThreadWindowTests.buttonPlanOrdersButtonsAndFillsTheCancelSlotFromTheLastCloseAffordance`: `buttonPlan(for:)` on this request returns `[2]` |
| extension-message-presenting-005 | present-message-return-index, present-message-return-nil-on-dismiss | A request with `itemTitles == ["A", "B"]` presented by a conformer, once with the user choosing `"B"` and once with the user dismissing | `presentMessage(_:)` returns `1` in the first case and `nil` in the second — traced to the protocol doc comment, "The index into `request.itemTitles` of the button the user chose, or `nil` if they dismissed it," and exercised through `RecordingMessagePresenter`/`SuspendingMessagePresenter` in `MainThreadWindowTests.swift` |
| extension-message-presenting-006 | is-modal-carried-not-enforced | `isModal == false` on an otherwise ordinary request, presented by `NSAlertMessagePresenter` | The value is preserved verbatim on the request (`request.isModal == false` remains true of the value itself), while the conformer still presents the message as a modal sheet regardless — traced to `NSAlertMessagePresenter`'s own doc comment, "`request.isModal == false` is presented modally anyway," which states plainly that the protocol does not dictate this conformer's choice |
| extension-message-presenting-007 | request-module-private-construction | Attempting `ExtensionMessageRequest(severity: .information, message: "m", detail: nil, isModal: true, itemTitles: [], closeAffordanceIndices: [])` from a Swift module other than `AgenticToolkitMacOS`, with no `@testable import` | Fails to compile — no accessible initializer; traced to the absence of an explicit `public init` in the source and to every construction site among the given sources (`MainThreadWindow.swift`, and `MainThreadWindowTests.swift` via `@testable import AgenticToolkitMacOS`) requiring internal-or-better access |

## Edge Cases

- **Null/empty input**: `itemTitles == []` MUST make `presentMessage(_:)` return `nil` unconditionally, per **present-message-empty-items-always-nil** (MUST).
- **Null/empty input**: `detail == nil` MUST be treated as "no additional detail supplied"; the type does not coerce it to an empty string or otherwise distinguish "no detail" from "empty detail," because `detail` is typed as an optional rather than defaulted (MUST).
- **Null/empty input**: `message == ""` (an empty string) MUST be accepted unchanged; `ExtensionMessageRequest` performs no non-empty validation on `message`, so a conformer MUST NOT assume it is non-empty (MUST NOT).
- **Boundary values**: an `itemTitles` array of exactly one entry, with that entry's index present in `closeAffordanceIndices`, is the minimal all-flagged case; **close-affordance-indices-within-item-bounds** MUST still hold for it (MUST).
- **Boundary values**: `closeAffordanceIndices` MAY name every index in `itemTitles` (every item flagged); the struct places no upper limit on how many indices may be flagged, and **close-affordance-indices-within-item-bounds** MUST hold regardless of count (MUST).
- **Concurrent access**: `ExtensionMessagePresenting` is `@MainActor`-isolated, so two `presentMessage(_:)` calls on the same conforming instance MUST be serialized by the main actor; the protocol requires no additional queuing or coalescing beyond what actor isolation already provides (MUST).
- **Concurrent access**: because `ExtensionMessageRequest` and `ExtensionMessageSeverity` are `Sendable`, a request value MUST be safely passable across actor and task boundaries before it reaches `presentMessage(_:)`, even though the call itself always resumes on the main actor (MUST).
- **Error states**: `presentMessage(_:)` has no thrown-error path; per **present-message-no-throwing-path**, any inability to present the message MUST resolve as `nil`, indistinguishable to the caller from a user dismissal (MUST).
- **Cancellation and timeouts**: `ExtensionMessagePresenting` defines no cancellation support and no timeout of its own; the protocol has no mechanism for a caller to signal that its enclosing `Task` was cancelled while `presentMessage(_:)` was still awaiting a user response, and a conformer MUST NOT be assumed to observe or honor `Task` cancellation absent its own separate implementation of that (MUST NOT).
- **Offline or disconnected state**: not applicable — `ExtensionMessagePresenting.swift` imports only `Foundation`, performs no network access, and has no concept of connectivity.
- **Missing file or unreachable server**: not applicable — the file opens no file and makes no network or process call of its own.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `severity` | `ExtensionMessageSeverity` | none (required) | Which `show*Message` call produced this request. |
| `message` | `String` | none (required) | The primary text to present; no length or emptiness constraint. |
| `detail` | `String?` | none (required argument; `nil` denotes "no detail") | Optional secondary text. |
| `isModal` | `Bool` | none (required) | The caller's stated modality preference; carried but not enforced, per **is-modal-carried-not-enforced**. |
| `itemTitles` | `[String]` | none (required; empty array denotes no buttons) | Button titles in display order; also the domain `presentMessage(_:)`'s returned index is drawn from. |
| `closeAffordanceIndices` | `[Int]` | none (required; empty array denotes no flagged items) | Indices into `itemTitles` whose item the extension flagged `isCloseAffordance`. |

## Deep Linking

Not applicable: `ExtensionMessagePresenting.swift` defines no URL, route, or navigable destination — it is a presentation seam with no navigation surface of its own.

## Localization

Not applicable: the file declares no user-facing string literal of its own. `message`, `detail`, and `itemTitles` are caller-supplied data passed straight through, not strings authored in this file, and the file contains no `String(localized:)` call, no String Catalog entry, and no hardcoded literal a user would see.

## Accessibility Options

Not applicable: `ExtensionMessagePresenting.swift` renders nothing and reads no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color) — it has no UI of its own.

## Feature Flags

Not applicable: the source declares no feature-flag key and contains no conditional feature-gating logic.

## Analytics

Not applicable: the source contains no analytics or event-emission call of any kind.

## Privacy

- **Data collected**: `ExtensionMessagePresenting.swift` collects nothing on its own; `message`, `detail`, and `itemTitles` are whatever text the calling extension supplied to a `vscode.window.show*Message` call, held only as the fields of one `ExtensionMessageRequest` value for the lifetime of a single `presentMessage(_:)` call.
- **Storage**: the file performs no storage of its own; nothing here persists a request beyond the call it was built for.
- **Transmission**: the file performs no network transmission; the request value is passed in-process, from whatever constructs it to whichever conformer presents it.
- **Retention**: no value defined here outlives the `presentMessage(_:)` call it was constructed for; the type keeps no cache, log, or history of past requests.

## Logging

Not applicable: `ExtensionMessagePresenting.swift` contains no logging call and no `Loggable` conformance. The one related log line in this seam — reporting a dropped, never-shown message — belongs to `NSAlertMessagePresenter.presentedResponse(for:)`, an actual conformer, not to this file's own types.

## Platform Notes

- **SwiftUI**: SwiftUI has no single API that both renders a button and marks it "the cancel one" the way `NSAlert.addButton(withTitle:)` plus a manually-assigned key equivalent does, so a SwiftUI port of a conformer would need its own `buttonPlan`-equivalent function (mirroring `NSAlertMessagePresenter.buttonPlan(for:)`) feeding a `ForEach` over `.alert(_:isPresented:actions:)` actions, deciding per action whether it gets the `.cancel` role or an ordinary button role.
- **Compose**: model `ExtensionMessagePresenting` as a Kotlin `interface ExtensionMessagePresenting { suspend fun presentMessage(request: ExtensionMessageRequest): Int? }` confined to the main dispatcher — the `@MainActor` equivalent — and `ExtensionMessageRequest`/`ExtensionMessageSeverity` as a Kotlin `data class`/`enum class`; a `data class` gives structural `equals`/`hashCode` for free, unlike the Swift struct, which a port should decide whether to suppress to match **request-sendable-only**. A Compose conformer would use `AlertDialog`'s `confirmButton`/`dismissButton` slots for up to two buttons and a manually built list for anything beyond that, since `AlertDialog` has no built-in N-button layout.
- **React/Web**: model the protocol as an async function `presentMessage(request: ExtensionMessageRequest): Promise<number | null>`, and the data shapes as a TypeScript `type`/`interface`; TypeScript has no compiler-enforced actor isolation, so **presenting-protocol-isolation** becomes a convention — call and resolve on the same JS execution context that owns the UI — rather than something the compiler checks. A browser conformer builds its own modal (a native `dialog` element or a design-system modal) rendering one button per `buttonPlan`-equivalent entry, since neither `window.confirm` nor `window.alert` supports more than a fixed OK/Cancel pair.
- **AppKit / UIKit**: this is the source. `ExtensionMessagePresenting.swift` and its one given conformer, `NSAlertMessagePresenter.swift` (both in `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/`), belong to the `AgenticToolkitMacOS` framework target; the conformer uses `NSAlert` and `beginSheetModal(for:completionHandler:)` bridged into `async` with `withCheckedContinuation`. A UIKit iOS port would use `UIAlertController` with an array of `UIAlertAction`s and `present(_:animated:completion:)`; because an iOS app is always foreground, the "no window anywhere, drop the message" fallback `NSAlertMessagePresenter.presentedResponse(for:)` implements has a much narrower analogue there — a root view controller that has not yet attached.
- **WinUI 3**: model `ExtensionMessagePresenting` as `public interface IExtensionMessagePresenting { Task<int?> PresentMessageAsync(ExtensionMessageRequest request); }`, called only on the `DispatcherQueue` a `@MainActor` maps to (marshalling any off-thread call through `DispatcherQueue.TryEnqueue`). `ExtensionMessageRequest` becomes a `public sealed record ExtensionMessageRequest(ExtensionMessageSeverity Severity, string Message, string? Detail, bool IsModal, IReadOnlyList<string> ItemTitles, IReadOnlyList<int> CloseAffordanceIndices)`, and `ExtensionMessageSeverity` a plain `enum`. A WinUI 3 conformer presents with `ContentDialog`, whose `PrimaryButtonText`/`SecondaryButtonText`/`CloseButtonText` give exactly three button slots — fewer than `NSAlert`'s unbounded button list — so a request needing more than three effective buttons (after the same last-wins cancel-slot collapse **close-affordance-indices-are-a-list** requires) needs either a custom `ContentDialog` body with its own `StackPanel` of `Button`s wired to close the dialog with a result, or `Windows.UI.Popups.MessageDialog` with its own capped `UICommand` list; either way the port must reimplement `buttonPlan(for:)`'s skip-and-collapse logic itself. `Task`/`async`/`await` plays the role of Swift's `async`; `CancellationToken` has no counterpart to wire up here, per the Edge Cases entry on cancellation.

## Design Decisions

**Decision**: `closeAffordanceIndices` is a list of indices rather than a single optional index.
**Rationale**: stated in the source's own doc comment — upstream (`extHostMessageService.ts`) keeps the `isCloseAffordance` flag on every item that set it, logging only a warning for the second and later ones, and `mainThreadMessageService.ts` routes every flagged command's index through `cancelButton = button` in turn, so the last one wins the cancel slot. A model carrying only the first flagged index cannot represent a second one, and would render it as an ordinary button — a divergence from upstream this design avoids.
**Approved**: pending

**Decision**: `ExtensionMessageRequest` declares no explicit `public init`, leaving its memberwise initializer at internal access.
**Rationale**: not stated in the source; this follows from Swift's own rule that a struct's synthesized memberwise initializer is `internal` unless an explicit `public` one is written, regardless of the struct's own access level. Flagged here so a port does not assume "module-private construction" was a deliberate design choice recorded anywhere in this file — it is a byproduct of what the file omits, worth a conscious choice on any platform being ported to.
**Approved**: pending

**Decision**: `presentMessage(_:)` never throws; an unpresentable message resolves the same as a user dismissal.
**Rationale**: per `NSAlertMessagePresenter`'s own doc comment, an extension calling `show*Message` must already handle "the user dismissed without choosing an item" (`vscode.d.ts`'s own contract), so folding "could not be presented at all" into that same outcome needs no new error type or case, at the cost of losing the distinction on the extension side.
**Approved**: pending

**Decision**: `isModal` is carried on the request but the protocol does not require a conformer to honor it.
**Rationale**: per `NSAlertMessagePresenter`'s own doc comment, this repo "has no toast primitive today, and inventing one is outside this task," so its one conformer presents every request modally regardless of `isModal`; the field is preserved on the request specifically so a later, non-modal presenter can read and honor it without a source change to `ExtensionMessageRequest` itself.
**Approved**: pending

**Decision**: this recipe's Behavioral Requirements section is shorter than its sibling `extension-host-vs-code-api-ai-plugin-language-model-provider`.
**Rationale**: `ExtensionMessagePresenting.swift` is a pure data-and-protocol seam with no executable logic of its own — no persistence, no network access, no request-building — while that sibling documents a full production conformer with resolution, streaming, and error-mapping logic. The depth difference tracks a genuine difference in the two files' complexity, not an authoring gap.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |

`separation-of-concerns` passes because the file's own header comment states it was split out of `MainThreadWindow.swift` specifically to keep the adaptor's argument parsing and promise settlement testable without AppKit; the file itself imports only `Foundation`, contains no argument parsing and no promise-settlement logic, and defines only the data shapes and protocol that both the adaptor and its AppKit-dependent conformer (`NSAlertMessagePresenter`) depend on. `unit-test-coverage` is partial: no test file among the given sources targets `ExtensionMessagePresenting.swift`'s own types by name — `closeAffordanceIndices`'s derivation is exercised indirectly through `MainThreadWindowTests.closeAffordanceIndicesReflectWhichItemsIfAnyAreMarkedCloseAffordance`, and the contract's downstream implications (`buttonPlan(for:)` ordering, `escapeKeyEquivalentPosition(in:)`) are exercised only through its one conformer's own tests in that same file; none of the given tests attempts (or needs to, since it would fail to compile) constructing an `ExtensionMessageRequest` from outside the `AgenticToolkitMacOS` module to verify **request-module-private-construction** as its own assertion.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
