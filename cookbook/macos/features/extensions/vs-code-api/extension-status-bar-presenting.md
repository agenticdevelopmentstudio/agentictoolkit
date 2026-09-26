---
id: 84292002-9039-4f8b-9bfb-69f9b4832e4f
title: ExtensionStatusBarPresenting
domain: agentictoolkit://cookbook/macos/features/extensions/vs-code-api/extension-status-bar-presenting
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'The @MainActor presenter seam behind vscode.window.createStatusBarItem:
  two synchronous methods to put up or refresh, and to remove, one status bar item.'
platforms:
- swift
- macos
tags:
- extension-host
- vscode-api
- status-bar
- presenter
depends-on: []
related: []
references:
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/ExtensionStatusBarPresenting.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadWindow.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/UI/WindowFooterStatusBarPresenter.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Extensions/MainThreadWindowStatusBarTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/project.yml (agentictoolkit)
approved-by: ''
approved-date: ''
---

# ExtensionStatusBarPresenting

## Overview

`ExtensionStatusBarPresenting` (`packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/ExtensionStatusBarPresenting.swift`) is the presenter seam behind `vscode.window.createStatusBarItem`: the interface `MainThreadWindow` calls into whenever a returned `StatusBarItem` object's `show()`, `hide()`, or `dispose()` method runs, or one of its mutable property setters commits a change. Its own header comment says it was split out of `MainThreadWindow.swift`, which had grown past 2,800 lines, and that the split is a file boundary rather than a tier boundary — `MainThreadWindow` is still its only consumer. The same file also declares the two value types the protocol's two methods pass across that seam: `ExtensionStatusBarAlignment` (VS Code's `StatusBarAlignment` enum, reduced to `left`/`right`) and `ExtensionStatusBarItemRequest` (one `createStatusBarItem()` call's current display state, reduced to what a presenter needs to render it). The type carries no rendering logic, no AppKit import, and no state of its own; the production conformer is `WindowFooterStatusBarPresenter` (`packages/apple/AgenticToolkit/macOS/Features/Extensions/UI/WindowFooterStatusBarPresenter.swift`), which renders every shown item into the trailing slot of each open window's `WindowFooterBar`, and the test suite exercises the contract through a recording double, `RecordingStatusBarPresenter` (`MainThreadWindowStatusBarTests.swift`).

## Behavioral Requirements

- **main-actor-isolation**: `ExtensionStatusBarPresenting` MUST be declared `@MainActor`, matching every protocol in its directory; a conforming type's implementations of `putOrUpdateStatusBarItem(_:)` and `removeStatusBarItem(internalID:)` MUST execute on the main actor.
- **class-bound-conformance**: `ExtensionStatusBarPresenting` MUST constrain conformers to `AnyObject`; a value type MUST NOT be able to conform to the protocol as declared.
- **two-operation-contract**: A conforming type MUST implement exactly two members, `putOrUpdateStatusBarItem(_:)` and `removeStatusBarItem(internalID:)`; the protocol MUST NOT declare separate members mirroring VS Code's upstream `show()`, `hide()`, a debounced `update()`, and `dispose()`, because `hide()` and `dispose()` resolve to the same removal effect upstream and nothing here replicates `update()`'s debounce.
- **synchronous-no-await**: Both `putOrUpdateStatusBarItem(_:)` and `removeStatusBarItem(internalID:)` MUST be non-`async` functions that return `Void` synchronously; neither MUST suspend to await a result, unlike `ExtensionQuickPickPresenting.presentQuickPick(_:onHighlight:)`, which awaits the user's choice.
- **put-or-refresh-semantics**: `putOrUpdateStatusBarItem(_:)` MUST put `request` up as a new item when `request.internalID` is not currently shown by the conformer, and MUST refresh the already-shown item in place when `request.internalID` is already up; one method MUST serve both the initial "add" and every subsequent "update".
- **caller-commits-once-per-change**: The caller MUST invoke `putOrUpdateStatusBarItem(_:)` exactly once for every committed change to a shown item's state; the caller MUST NOT batch two or more property changes into a single call.
- **no-debounce-assumed**: A conforming presenter MUST NOT assume any minimum interval, coalescing, or debounce between successive `putOrUpdateStatusBarItem(_:)` calls for the same `internalID`; none is performed on its behalf.
- **never-called-for-hidden-or-disposed**: The caller MUST NOT invoke `putOrUpdateStatusBarItem(_:)` for an item that has not yet been shown or that has already been disposed; a conformer MAY assume every call it receives corresponds to a currently visible, non-disposed item.
- **remove-tolerates-unknown-id**: `removeStatusBarItem(internalID:)` MUST be safe to call with an `internalID` the conformer never received via `putOrUpdateStatusBarItem(_:)`; a conformer MUST treat this as a no-op rather than raising an error, trapping, or crashing.
- **remove-key-is-internal-id**: `removeStatusBarItem(internalID:)` MUST take the item down using the same `internalID` value carried on the `ExtensionStatusBarItemRequest.internalID` field previously passed to `putOrUpdateStatusBarItem(_:)`; it MUST NOT use `StatusBarItem.id`, the public, non-unique identifier the extension sees.
- **internal-id-not-exposed**: `ExtensionStatusBarItemRequest.internalID` MUST never be surfaced to the extension; it exists solely as the registry and removal key shared between the caller and the presenter.
- **fixed-identity-fields**: `ExtensionStatusBarItemRequest.internalID`, `.id`, `.alignment`, and `.priority` MUST be treated as fixed for the lifetime of one status bar item; the struct declares each `let`, and the caller's own model rebuilds every request from the same immutable values, so a conformer MUST NOT expect any of the four to differ between two calls sharing one `internalID`.
- **mutable-display-fields**: `ExtensionStatusBarItemRequest.name`, `.text`, `.tooltip`, `.color`, `.backgroundColor`, `.command`, `.accessibilityLabel`, and `.accessibilityRole` MUST be free to differ between successive `putOrUpdateStatusBarItem(_:)` calls that share one `internalID`; the struct declares each `var` for exactly this reason.
- **priority-nil-means-undefined**: `ExtensionStatusBarItemRequest.priority` MUST be `nil` when the extension supplied no priority, and MUST NOT be coerced to `0` or any other sentinel numeric value.
- **alignment-two-cases**: `ExtensionStatusBarAlignment` MUST expose exactly two cases, `left` and `right`, corresponding to `vscode.window.StatusBarAlignment`'s `Left` (`1`) and `Right` (`2`); the raw JavaScript numbers MUST map onto these cases nowhere else in the codebase besides `MainThreadWindow.statusBarAlignmentMembers` and `MainThreadWindow.parseAlignment(_:)`.
- **color-flat-string**: `ExtensionStatusBarItemRequest.color` and `.backgroundColor` MUST each be represented as an optional flat `String` id, never as a value that distinguishes a plain string color from a `ThemeColor` id; a conformer MUST NOT expect any richer shape than a single optional string per field.
- **value-equatable**: `ExtensionStatusBarAlignment` and `ExtensionStatusBarItemRequest` MUST both conform to `Equatable`, so a test double or a conformer's own state MAY be compared to an incoming request by value.
- **sendable-value-types**: `ExtensionStatusBarAlignment` and `ExtensionStatusBarItemRequest` MUST both conform to `Sendable`.
- **cross-actor-before-applying**: A conformer MAY move a received `ExtensionStatusBarItemRequest` off the main actor to prepare a view before returning to the main actor to apply it, relying on the type's `Sendable` conformance to cross that boundary safely.
- **designated-initializer**: `ExtensionStatusBarItemRequest` MUST be constructed via its explicit `public init(internalID:id:alignment:priority:name:text:tooltip:color:backgroundColor:command:accessibilityLabel:accessibilityRole:)`; the type MUST NOT rely on Swift's synthesized memberwise initializer, which is `internal` and unusable from the test module that also constructs this type.
- **void-return-no-failure-channel**: `putOrUpdateStatusBarItem(_:)` and `removeStatusBarItem(internalID:)` MUST both return `Void`; the protocol provides no channel through which a conformer can report a presentation failure back to the caller.
- **serialized-calls**: Because both the caller (`MainThreadWindow`, itself `@MainActor`) and the protocol are confined to the main actor, every call into one conformer instance MUST be strictly serialized in the order the caller's method calls and property writes occur; no two calls into the same conformer instance can overlap.

## Appearance

Not applicable — this is a presenter protocol and its two associated value types, not a visual component.

## States

Not applicable — this is a presenter protocol and its two associated value types, not a visual component. The per-item lifecycle a conformer must honor (never shown, shown, hidden, disposed) is captured under Behavioral Requirements as call-ordering rules rather than as a visual-state table, because the state itself — `isVisible`/`isDisposed` — is tracked by the caller's own model, not by this file.

## Accessibility

Not applicable — this is a presenter protocol and its two associated value types, not a visual component. `ExtensionStatusBarItemRequest.accessibilityLabel` and `.accessibilityRole` carry extension-supplied accessibility data through to whatever conformer renders it; see **mutable-display-fields**.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-bar-presenting-001 | never-called-for-hidden-or-disposed | An item is created and its `text`/`name` are written, but `show()` is never called | `putOrUpdateStatusBarItem` is invoked zero times — `MainThreadWindowStatusBarTests.neverShownItemReachesThePresenterZeroTimesEvenAfterWrites` |
| status-bar-presenting-002 | put-or-refresh-semantics, caller-commits-once-per-change | `show()` called once after `text = 'hello'` | `putOrUpdateStatusBarItem` is invoked exactly once, and its request's `text == "hello"` — `MainThreadWindowStatusBarTests.showReachesThePresenterOnceWithCurrentText` |
| status-bar-presenting-003 | caller-commits-once-per-change, no-debounce-assumed | `show()`, then `text = 'a'`, then `text = 'b'` | `putOrUpdateStatusBarItem` is invoked three times total — once per commit, with no coalescing — and the last call's request has `text == "b"` — `MainThreadWindowStatusBarTests.aWriteAfterShowReachesThePresenterAgainWithNoCoalescing` |
| status-bar-presenting-004 | remove-key-is-internal-id | `createStatusBarItem('my.id')`, `show()`, then `hide()` | `removeStatusBarItem` is called with the item's `internalID`, which is not equal to the public `id` string `"my.id"`, and equals the `internalID` carried on the earlier `putOrUpdateStatusBarItem` call's request — `MainThreadWindowStatusBarTests.hideRemovesByInternalID` |
| status-bar-presenting-005 | put-or-refresh-semantics | `show()`, `hide()`, `show()` again | `putOrUpdateStatusBarItem` is invoked twice total and `removeStatusBarItem` is invoked once total | `MainThreadWindowStatusBarTests.showAfterHidePutsTheItemBackUp` |
| status-bar-presenting-006 | never-called-for-hidden-or-disposed, remove-tolerates-unknown-id | `show()`, `dispose()`, then `text = 'after-dispose'` | `putOrUpdateStatusBarItem` is invoked exactly once (the `show()`), `removeStatusBarItem` is invoked exactly once (`dispose()`'s implicit hide), and the post-dispose text write reaches the presenter zero further times — `MainThreadWindowStatusBarTests.disposeRemovesTheItemAndFurtherWritesReachThePresenterZeroTimes` |
| status-bar-presenting-007 | never-called-for-hidden-or-disposed | `dispose()` called, then `show()` called on the same item | `putOrUpdateStatusBarItem` is invoked zero times — `MainThreadWindowStatusBarTests.showAfterDisposeReachesThePresenterZeroTimes` |
| status-bar-presenting-008 | remove-tolerates-unknown-id | `show()`, `dispose()`, `dispose()` again | `removeStatusBarItem` is invoked exactly once total; the second `dispose()` is a no-op at the caller's own idempotence guard and never reaches the presenter a second time — `MainThreadWindowStatusBarTests.disposeTwiceIsNotAnErrorAndRemovesOnce` |
| status-bar-presenting-009 | fixed-identity-fields, priority-nil-means-undefined | `createStatusBarItem('x', 2, 7)`, then `show()` | Every `putOrUpdateStatusBarItem` request for that item carries `id == "x"`, `alignment == .right`, and `priority == 7`, unchanged across calls — `MainThreadWindowStatusBarTests.idFormOverloadRoutesAllThreeArgumentsToTheirProperties` combined with the caller's `ExtensionStatusBarItem.request` computed property |
| status-bar-presenting-010 | color-flat-string | `color` set to a `ThemeColor`-shaped object `{ id: 'myTheme.color' }`, then `show()` | The `putOrUpdateStatusBarItem` request's `color == "myTheme.color"` — the flat id string, never the original object shape — `MainThreadWindowStatusBarTests.colorAsAThemeColorShapedObjectRoundTripsAsAFreshObjectWithMatchingID` |

## Edge Cases

- **Null/empty input**: `ExtensionStatusBarItemRequest.text == ""` MUST be accepted and passed to `putOrUpdateStatusBarItem(_:)` unchanged; the type enforces no minimum length (MUST).
- **Null/empty input**: `name`, `tooltip`, `color`, `backgroundColor`, `command`, `accessibilityLabel`, and `accessibilityRole` MAY all be `nil` simultaneously on one request; a conformer MUST accept that combination rather than requiring any of them (MUST).
- **Boundary values**: `priority` MAY carry `Double.infinity` or `-Double.infinity` unchanged — the caller performs no infinity clamping across this seam, because `MainThreadWindow` and its presenter share one process and one actor with no JSON boundary between them (MUST).
- **Boundary values**: `priority == nil` (undefined) and `priority == 0` (an explicit zero the extension supplied) MUST remain distinguishable on every request; the type never collapses the two (MUST).
- **Concurrent access**: because both `MainThreadWindow` and `ExtensionStatusBarPresenting` are `@MainActor`, calls into one conformer instance MUST be strictly serialized in the order the caller's own method calls and property writes occur; no two calls into the same instance can race (MUST). See **serialized-calls**.
- **Concurrent access**: `internalID` uniqueness is guaranteed by the caller alone — `MainThreadWindow.statusBarItemCounter`, a `static` ordinal incremented only under `@MainActor` — and this protocol's contract does not itself check or enforce that uniqueness; a conformer MUST trust the `internalID` it is given (MUST).
- **Error states**: not applicable — the protocol declares no `throws` and no `Result`/optional failure return on either method; see **void-return-no-failure-channel**.
- **Offline or disconnected state**: not applicable — this seam has no network dependency; every call is a same-process, same-actor method call between `MainThreadWindow` and its presenter.
- **Cancellation and timeouts**: not applicable — both methods are synchronous with no `async` gap, so there is nothing for a caller to cancel or time out; see **synchronous-no-await**.
- **Repeated removal**: `removeStatusBarItem(internalID:)` MUST remain safe if it is ever called more than once for the same `internalID`, or for an `internalID` already removed, on the same terms as **remove-tolerates-unknown-id** — an already-removed id and a never-shown id are the same case from the conformer's point of view (MUST).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `request` (parameter of `putOrUpdateStatusBarItem`) | `ExtensionStatusBarItemRequest` | none (required) | The full display state of one status bar item to put up or refresh. |
| `internalID` (parameter of `removeStatusBarItem`) | `String` | none (required) | The registry key of the item to take down; safe to pass an id the conformer never received. |
| `ExtensionStatusBarItemRequest.internalID` | `String` | none (required) | Set once by the caller at construction — the extension's supplied id folded with a per-process ordinal, or a bare ordinal when the extension gave none; never shown to the extension. |
| `ExtensionStatusBarItemRequest.id` | `String` | none (required) | The public `StatusBarItem.id` the extension sees; not guaranteed unique across items. |
| `ExtensionStatusBarItemRequest.alignment` | `ExtensionStatusBarAlignment` | none (required) | `.left` or `.right`; fixed for the item's lifetime. |
| `ExtensionStatusBarItemRequest.priority` | `Double?` | `nil` | `nil` means "the extension supplied no priority"; never coerced to `0`. |
| `ExtensionStatusBarItemRequest.name` | `String?` | `nil` | Extension-supplied display name. |
| `ExtensionStatusBarItemRequest.text` | `String` | none (required, caller initializes to `""`) | The item's rendered text; the one field every request always carries a concrete value for. |
| `ExtensionStatusBarItemRequest.tooltip` | `String?` | `nil` | The string form of `StatusBarItem.tooltip`; a `MarkdownString` write is recorded elsewhere as not implemented rather than reaching this field. |
| `ExtensionStatusBarItemRequest.color` / `.backgroundColor` | `String?` | `nil` | The flat id string for either a plain color string or a `ThemeColor`'s `id`; see **color-flat-string**. |
| `ExtensionStatusBarItemRequest.command` | `String?` | `nil` | The string form of `StatusBarItem.command`; a `Command`-object write is likewise recorded elsewhere as not implemented. |
| `ExtensionStatusBarItemRequest.accessibilityLabel` / `.accessibilityRole` | `String?` | `nil` | Extension-supplied `accessibilityInformation` fields, carried through unchanged. |

## Deep Linking

Not applicable: `ExtensionStatusBarPresenting.swift` defines no URL, route, or navigable destination — it is a presenter interface and two value types with no navigation surface.

## Localization

Not applicable: `ExtensionStatusBarPresenting.swift` declares no string literal, no error type, and no `CustomStringConvertible` conformance of its own — every string field on `ExtensionStatusBarItemRequest` is extension-supplied data passed through unchanged, not text this file authors.

## Accessibility Options

Not applicable: `ExtensionStatusBarPresenting.swift` renders nothing and reads no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color) itself — it is a data-carrying interface, not a view.

## Feature Flags

Not applicable: the source declares no feature-flag key and contains no conditional feature-gating logic; both protocol members are always available to any conformer.

## Analytics

Not applicable: the source contains no analytics or event-emission call of any kind.

## Privacy

Not applicable: `ExtensionStatusBarPresenting.swift` collects, stores, and transmits nothing itself — `ExtensionStatusBarItemRequest`'s fields are data the caller (`MainThreadWindow`) already holds in its own `ExtensionStatusBarItem` model and forwards unchanged; this file defines no persistence, no network call, and no credential or token field.

## Logging

Not applicable: the source contains no `import OSLog` and no logging call of any kind.

## Platform Notes

- **SwiftUI**: not applicable to this file as the source of truth — it imports only `Foundation` — but a SwiftUI-based status bar host would still conform a reference type (a class, or an `@Observable`/`ObservableObject` store) to this same protocol; `putOrUpdateStatusBarItem(_:)` would mutate that store's published state, and SwiftUI's diffing would apply the resulting view update, replacing `WindowFooterStatusBarPresenter`'s manual AppKit view management with declarative state.
- **Compose**: model `ExtensionStatusBarPresenting` as a Kotlin `interface` confined to the main dispatcher (calls made only from a `@MainThread`-annotated context, since Kotlin coroutines have no direct equivalent of Swift's `@MainActor` type-level enforcement). `ExtensionStatusBarItemRequest` becomes an immutable Kotlin `data class` with `val` properties for the identity fields and ordinary `val` properties reassigned via `copy()` for what were `var` fields on the Swift side, since a `data class` instance is itself immutable; `data class` already supplies the structural equality `Equatable` gives on the Swift side. Android has no OS-level status bar surface analogous to VS Code's; a port would render into an in-app footer/status strip composable instead.
- **React/Web**: model as a plain TypeScript interface — `interface ExtensionStatusBarPresenting { putOrUpdateStatusBarItem(request: ExtensionStatusBarItemRequest): void; removeStatusBarItem(internalId: string): void; }` — with `ExtensionStatusBarItemRequest` as a `readonly`-field object type; TypeScript's structural typing replaces `Sendable`, and value comparison must be written explicitly (a shallow field compare, or a library's `deepEqual`) since the language has no built-in `Equatable`. There is no browser-level main-thread actor to declare; the equivalent discipline is calling both methods only from the same task/microtask the DOM updates run on. The web has no OS status bar either; a port renders into a footer or toolbar DOM element.
- **AppKit / UIKit**: this is the source. `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/ExtensionStatusBarPresenting.swift` declares the protocol and its two value types; `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadWindow.swift` is its sole caller, and `packages/apple/AgenticToolkit/macOS/Features/Extensions/UI/WindowFooterStatusBarPresenter.swift` is the shipping AppKit conformer, rendering every shown item into the trailing slot of each open window's `WindowFooterBar`. `project.yml` declares the owning `AgenticToolkitMacOS` framework target `platform: macOS` only — no iOS target packages this file.
- **WinUI 3**: model `ExtensionStatusBarPresenting` as a C# interface, `IExtensionStatusBarPresenting`, with `void PutOrUpdateStatusBarItem(ExtensionStatusBarItemRequest request)` and `void RemoveStatusBarItem(string internalId)`, both documented as callable only while `DispatcherQueue.HasThreadAccess` is `true` on the UI thread — WinUI 3 has no type-level actor enforcement to mirror `@MainActor`, so this is a calling-convention contract rather than a compiler-checked one. `ExtensionStatusBarItemRequest` becomes a C# `record` (or `readonly record struct`): its identity fields (`InternalId`, `Id`, `Alignment`, `Priority`) as ordinary `init`-only properties and its display fields (`Text`, `Tooltip`, `Color`, `BackgroundColor`, `Command`, `AccessibilityLabel`, `AccessibilityRole`) as ordinary mutable properties on a fresh record built per commit — `record`'s built-in value equality supplies what `Equatable` gives on the Swift side. `ExtensionStatusBarAlignment` becomes a C# `enum { Left, Right }`. Because WinUI 3 ships no OS-level status bar surface the way `NSStatusBar` does, a host composes its own status strip — typically a `Grid` or `StackPanel` inside the app's custom title/footer bar holding a `TextBlock` for `Text` plus a `FontIcon`/`Image` for a leading glyph, aligned to the `Grid`'s leading or trailing column per `Alignment` — with a `VisualStateManager` state group (`Shown`/`Hidden`) standing in for the caller-tracked `isVisible` flag that gates whether `PutOrUpdateStatusBarItem`/`RemoveStatusBarItem` is ever called for a given item.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/ExtensionStatusBarPresenting.swift` |

## Design Decisions

**Decision**: `ExtensionStatusBarPresenting` declares exactly two members, `putOrUpdateStatusBarItem(_:)` and `removeStatusBarItem(internalID:)`, rather than one member per upstream verb (`show`, `hide`, `update`, `dispose`).
**Rationale**: the source's own doc comment states that only two of upstream's four verbs are distinct *observable effects on a presenter* — putting an item up or refreshing it, and taking one down — because `hide()` and `dispose()` both resolve to the same removal upstream ("there is no `$hideEntry`"), and task 5.5c's Ruling 7 forbids replicating `update()`'s private debounce.
**Approved**: pending

**Decision**: `ExtensionStatusBarItemRequest.color` and `.backgroundColor` are always a flat `String?` id, never a value that preserves whether the extension wrote a plain string or a `ThemeColor` object.
**Rationale**: per the struct's own doc comment, a `ThemeColor`'s `id` *is* its whole value, so nothing is lost by not keeping the original `JSValue`; remembering which shape was written is the caller's own model's job (`MainThreadWindow`'s `ExtensionStatusBarColorValue`), needed only so its getter can answer the same shape back, which this presenter-facing type has no reason to do.
**Approved**: pending

**Decision**: `putOrUpdateStatusBarItem(_:)` is called once per committed change with no debounce, in contrast to VS Code's own upstream implementation, which defers every update through `setTimeout(..., 0)`.
**Rationale**: upstream's own stated reason for deferring is to avoid a redraw per setter call across a cross-process JSON-RPC boundary; `MainThreadWindow` and its presenter share one process and one actor and call each other directly, so that reason does not transfer. A presenter that would prefer a coalesced batch may still coalesce on its own side of the seam, at whatever cost that turns out to have — a cost this file does not measure or claim is free.
**Approved**: pending

**Decision**: `removeStatusBarItem(internalID:)` must tolerate being called for an `internalID` it never received.
**Rationale**: the caller's `hide()` removes unconditionally regardless of whether the item was ever previously visible, mirroring upstream's own `hide()`, which always calls its removal RPC regardless of prior visibility. Calling `hide()` on an item that was never shown is therefore not a no-op on the presenter side from the caller's point of view, and the protocol's own doc comment states this plainly as the reason a conformer must tolerate it.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |

`separation-of-concerns` passes because the file declares only an interface and two plain value types — no AppKit import, no rendering code, no persistence, and no networking of any kind (see Overview and the Behavioral Requirements' repeated "MUST NOT" bounds on what this type carries). `unit-test-coverage` passes because, while a protocol has no test target of its own to instantiate directly, its full observable contract — put-or-refresh semantics, no-coalescing commits, never-called-for-hidden-or-disposed, remove-tolerates-unknown-id, fixed-identity-fields, and color-flat-string — is exercised end to end through `MainThreadWindowStatusBarTests.swift`'s `RecordingStatusBarPresenter` double, cited directly in Conformance Test Vectors 001–010.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
