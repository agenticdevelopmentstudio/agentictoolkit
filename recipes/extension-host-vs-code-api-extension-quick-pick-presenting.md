---
id: 720cc52e-9567-4643-9639-014403ef0ea7
title: ExtensionQuickPickPresenting
domain: agentictoolkit://recipes/extension-host-vs-code-api-extension-quick-pick-presenting
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: "Contract for vscode.window.showQuickPick: the item and request data types, and the presenting protocol a picker conformer implements."
platforms:
  - swift
  - macos
tags:
  - extension-host
  - vscode-api
  - quick-pick
  - presenting
  - mainactor
depends-on: []
related:
  - agentictoolkit://recipes/extension-quick-pick-view-controller
  - agentictoolkit://recipes/extension-input-box-view-controller
references:
  - packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/ExtensionQuickPickPresenting.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadWindow.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/ExtensionMessagePresenting.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/ExtensionInputBoxPresenting.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/macOS/Features/Extensions/UI/ExtensionPickerPresenter.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/macOS/Features/Extensions/UI/ExtensionQuickPickModel.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Extensions/MainThreadWindowQuickPickTests.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Extensions/ExtensionPickerPresenterTests.swift (agentictoolkit)
  - packages/apple/AgenticToolkit/project.yml (agentictoolkit)
approved-by: ""
approved-date: ""
---

# ExtensionQuickPickPresenting

## Overview

`ExtensionQuickPickPresenting.swift` (`packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/ExtensionQuickPickPresenting.swift`) declares the extension-host's contract for one `vscode.window.showQuickPick` call: two `Sendable, Equatable` data types, `ExtensionQuickPickItem` and `ExtensionQuickPickRequest`, that reduce a `QuickPickItem`/`QuickPickOptions` call to what a presenter needs, and the `@MainActor` protocol `ExtensionQuickPickPresenting` that a presenter conforms to in order to actually put a picker on screen (or, in a test, record what it was asked to show). Per the file's own header comment, it was split out of `MainThreadWindow.swift` once that file grew past 2,800 lines — a file-boundary split, not a tier split, and `MainThreadWindow` remains this contract's only caller among the given sources. `ExtensionPickerPresenter` (`packages/apple/AgenticToolkit/macOS/Features/Extensions/UI/ExtensionPickerPresenter.swift`) is the production conformer; it also conforms to the sibling `ExtensionInputBoxPresenting` protocol, one AppKit panel serving both seams. The protocol is declared separately from `ExtensionMessagePresenting`, deliberately, on an interface-segregation rationale documented directly in the source (see Design Decisions).

## Behavioral Requirements

- **item-sendable-equatable**: `ExtensionQuickPickItem` MUST conform to `Sendable` and `Equatable`.
- **item-label-required**: `ExtensionQuickPickItem.label` MUST be a non-optional `String`; it is the only property that applies to a row for which `isSeparator` is `true`.
- **item-description-optional**: `ExtensionQuickPickItem.description` MUST be `nil` when the item carried no description, or carried one that was not a string; when non-`nil` it is rendered less prominently on the same line as `label`.
- **item-detail-optional**: `ExtensionQuickPickItem.detail` MUST be `nil` on the same terms as `description`; when non-`nil` it is rendered less prominently on a separate line.
- **item-separator-flag**: `ExtensionQuickPickItem.isSeparator` MUST be `true` only for a row whose upstream `kind` was `QuickPickItemKind.Separator` (the number `-1`); every other row MUST report `false`.
- **item-separator-fields-defaulted**: When `isSeparator` is `true`, `description`, `detail`, `isPicked`, and `alwaysShow` MUST each be constructed at their default (`nil`, `nil`, `false`, `false`) regardless of what values the extension supplied for them, because only `label` applies to a separator row.
- **item-picked-flag**: `ExtensionQuickPickItem.isPicked` MUST report the item's truthy `picked` value exactly as supplied, independent of the owning request's `canPickMany` value; applying `picked`'s "only honored when the picker allows multiple selections" rule is the presenting conformer's responsibility, not this type's.
- **item-always-show-flag**: `ExtensionQuickPickItem.alwaysShow` MUST report the item's truthy `alwaysShow` value exactly as supplied; keeping the row visible despite an active filter is the presenting conformer's or model's responsibility, not this type's.
- **item-explicit-initializer**: `ExtensionQuickPickItem` MUST declare an explicit `public init(label:description:detail:isSeparator:isPicked:alwaysShow:)` rather than relying on the compiler-synthesized memberwise initializer, so a test in another module can construct one.
- **request-sendable-equatable**: `ExtensionQuickPickRequest` MUST conform to `Sendable` and `Equatable`.
- **request-optional-text-fields**: `ExtensionQuickPickRequest.title`, `.placeHolder`, and `.prompt` MUST each be `nil` when the extension supplied none for the corresponding `QuickPickOptions` field.
- **request-items-order-preserved**: `ExtensionQuickPickRequest.items` MUST preserve the extension-supplied order, separators included at their original positions; the indices a conforming presenter answers are positions into this exact array.
- **request-can-pick-many-flag**: `ExtensionQuickPickRequest.canPickMany` MUST report whether the user may accept more than one row.
- **request-match-flags**: `ExtensionQuickPickRequest.matchOnDescription` and `.matchOnDetail` MUST each report the caller-supplied filtering flag for that field, independent of one another.
- **request-ignore-focus-out-flag**: `ExtensionQuickPickRequest.ignoreFocusOut` MUST report whether the picker should stay open when focus moves elsewhere.
- **request-explicit-initializer**: `ExtensionQuickPickRequest` MUST declare an explicit `public init(title:placeHolder:prompt:items:canPickMany:matchOnDescription:matchOnDetail:ignoreFocusOut:)`, for the same cross-module-testability reason as `ExtensionQuickPickItem`.
- **presenting-main-actor-isolation**: `ExtensionQuickPickPresenting` MUST be declared `@MainActor`; every conformer's `presentQuickPick` call MUST execute on the main actor.
- **presenting-class-only**: `ExtensionQuickPickPresenting` MUST constrain conformers to `AnyObject`; a value type MUST NOT be able to conform.
- **presenting-single-requirement**: `ExtensionQuickPickPresenting` MUST declare exactly one requirement, `presentQuickPick(_:onHighlight:)`.
- **presenting-index-based-answer**: A conformer's non-dismissed answer MUST be indices into the `request.items` array it was given, never labels or copies of the items; two items sharing a `label` MUST remain distinguishable by position alone.
- **presenting-dismissal-is-nil**: A conformer MUST answer `nil` when, and only when, the user dismissed the picker without accepting a selection.
- **presenting-empty-selection-is-not-dismissal**: When `request.canPickMany` is `true` and the user explicitly accepts a selection of zero rows, a conformer MUST answer `[]`; `nil` and `[]` MUST NOT be conflated.
- **presenting-single-select-array-shape**: A conformer's non-dismissed answer MUST be typed `[Int]?` regardless of `request.canPickMany`; when `request.canPickMany` is `false`, a non-dismissed answer MUST contain exactly one element.
- **presenting-answer-order-preserved**: The order of indices in a conformer's non-dismissed answer MUST be the order the selection is to be reported to the extension; it MUST NOT be reordered (for example, sorted) downstream.
- **presenting-highlight-index**: Each `onHighlight` invocation MUST pass an index into `request.items` corresponding to the row newly highlighted.
- **presenting-highlight-frequency**: `onHighlight` MAY be invoked any number of times, including zero, over the lifetime of one `presentQuickPick` call.
- **presenting-highlight-after-return-prohibited**: A conformer MUST NOT invoke `onHighlight` after its `presentQuickPick` call has returned.
- **presenting-async-return**: `presentQuickPick` MUST be an `async` function that suspends until the picker session concludes — accepted or dismissed — before returning.

## Appearance

Not applicable — this is the extension-host contract (two data types and a presenting protocol) for `vscode.window.showQuickPick`, not a visual component.

## States

Not applicable — this is the extension-host contract (two data types and a presenting protocol) for `vscode.window.showQuickPick`, not a visual component. The only lifecycle-shaped behavior — a `presentQuickPick` call outstanding until it resolves accepted or dismissed — is captured under Behavioral Requirements rather than as a visual-state table.

## Accessibility

Not applicable — this is the extension-host contract (two data types and a presenting protocol) for `vscode.window.showQuickPick`, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| quick-pick-presenting-001 | item-label-required, item-description-optional, item-detail-optional, item-picked-flag, item-always-show-flag | Two extension-supplied items — `{label:'one', description:'desc-1', detail:'det-1', picked:true, alwaysShow:true}` and `{label:'two', description:7}` — parsed into `ExtensionQuickPickItem` values | First item: `label == "one"`, `description == "desc-1"`, `detail == "det-1"`, `isPicked == true`, `alwaysShow == true`. Second item: `label == "two"`, `description == nil` (the non-string `7` is omitted, not coerced), `isPicked == false`, `alwaysShow == false` — `MainThreadWindowQuickPickTests.itemFieldsAreCarriedAndANonStringDescriptionIsOmittedRatherThanCoerced` |
| quick-pick-presenting-002 | item-separator-flag, item-separator-fields-defaulted | A separator item `{label:'Group', kind: Separator, description:'ignored', detail:'ignored too', picked:true, alwaysShow:true}` followed by a normal row `{label:'row', kind: Default, description:'kept'}` | Separator: `isSeparator == true`, `label == "Group"`, `description == nil`, `detail == nil`, `isPicked == false`, `alwaysShow == false` (all four defaulted despite being supplied). Following row: `isSeparator == false`, `description == "kept"` — `MainThreadWindowQuickPickTests.anItemWhoseKindIsSeparatorIsMarkedAsOneAndDropsItsOtherFields` |
| quick-pick-presenting-003 | item-explicit-initializer, request-explicit-initializer | `MainThreadWindowQuickPickTests.swift` and `ExtensionPickerPresenterTests.swift`, both in module `AgenticToolkitMacOSTests`, construct `ExtensionQuickPickRequest`/`ExtensionQuickPickItem` values directly and read fields off values they did not construct themselves | Compiles and runs from a module distinct from the declaring `AgenticToolkitMacOS`, because both initializers are declared `public` explicitly; a compiler-synthesized memberwise initializer on a `public` type is `internal` and unreachable from that test module |
| quick-pick-presenting-004 | request-optional-text-fields, request-can-pick-many-flag, request-match-flags, request-ignore-focus-out-flag | `vscode.window.showQuickPick(['a'], { title: 'the-title', placeHolder: 'the-place', prompt: 'the-prompt', canPickMany: false, matchOnDescription: true, matchOnDetail: false, ignoreFocusOut: true })` | The built `ExtensionQuickPickRequest` has `title == "the-title"`, `placeHolder == "the-place"`, `prompt == "the-prompt"`, `canPickMany == false`, `matchOnDescription == true`, `matchOnDetail == false`, `ignoreFocusOut == true` — `MainThreadWindowQuickPickTests.titlePlaceHolderPromptAndTheFourBooleansAllReachTheRequest` |
| quick-pick-presenting-005 | request-items-order-preserved, presenting-index-based-answer | Items `[{label:'dup'},{label:'dup'}]` (identical labels); the presenting double answers indices `[1]` | The extension's promise resolves the object identical to `items[1]`, not `items[0]` — selection is by position within the preserved `items` order, never by label — `MainThreadWindowQuickPickTests.aChosenItemResolvesAsTheExtensionsOwnObjectEvenWhenTwoItemsShareALabel` |
| quick-pick-presenting-006 | presenting-dismissal-is-nil | The presenting double answers `nil` for one single-select call and one `canPickMany: true` call | Both extension-visible promises resolve `undefined`, never `null` and never an empty array — `MainThreadWindowQuickPickTests.aDismissedPickerResolvesUndefinedInBothCanPickManyModes` |
| quick-pick-presenting-007 | presenting-empty-selection-is-not-dismissal | `canPickMany: true`; the presenting double answers `[]` | The promise resolves an array of length 0 (`Array.isArray == true`), not `undefined` — `MainThreadWindowQuickPickTests.anEmptySelectionWithCanPickManyResolvesAnEmptyArrayNotUndefined` |
| quick-pick-presenting-008 | presenting-single-select-array-shape, presenting-answer-order-preserved | `canPickMany: true` over three items; the presenting double answers `[2, 0]` (out of ascending order) | The resolved array is `[items[2], items[0]]`, in that exact order — not sorted, not deduplicated, not reduced to one element — `MainThreadWindowQuickPickTests.canPickManyResolvesAnArrayOfTheOriginalValuesInThePresentersOrder` |
| quick-pick-presenting-009 | presenting-highlight-index, presenting-highlight-frequency | The presenting double's `highlightIndices == [1, 0]`, invoked before it answers `[0]`; `options.onDidSelectItem` records each call | `onDidSelectItem` is invoked exactly twice, first with `items[1]` then with `items[0]`, in that order — `MainThreadWindowQuickPickTests.onDidSelectItemReceivesTheOriginalItemValueWithTheOptionsObjectAsThis` |
| quick-pick-presenting-010 | presenting-highlight-after-return-prohibited | Manual inspection of every conformer among the given sources — `RecordingQuickPickPresenter`, `SuspendingQuickPickPresenter`, and `ExtensionPickerPresenter` | PASS if every `onHighlight` call in a conformer's `presentQuickPick` body occurs strictly before that call's `return` or continuation-resume statement; no automated test in the given sources exercises the prohibited call-after-return case directly, so this vector is a code-inspection check rather than a runtime assertion |
| quick-pick-presenting-011 | presenting-async-return | `SuspendingQuickPickPresenter.presentQuickPick` suspends on `withCheckedContinuation` until the test calls `release(at:with:)` | The caller (`MainThreadWindow`'s `presentQuickPickPromise`) observes no result until `release` runs, confirming `presentQuickPick` is `async` and genuinely suspends rather than polling — `MainThreadWindowQuickPickTests.disposeWhileThePickerIsGenuinelySuspendedRejectsRatherThanDeliveringAResult` |
| quick-pick-presenting-012 | presenting-main-actor-isolation, presenting-class-only, presenting-single-requirement | Attempt to declare a `struct` conforming to `ExtensionQuickPickPresenting`, or call `presentQuickPick` from a non-main-actor context without crossing an actor boundary | Both fail to compile — the `AnyObject` constraint rejects a struct conformer, and the `@MainActor` isolation requires every call to cross an actor boundary — traced to the `@MainActor public protocol ExtensionQuickPickPresenting: AnyObject` declaration; every given conformer (`ExtensionPickerPresenter`, `RecordingQuickPickPresenter`, `SuspendingQuickPickPresenter`) is a `final class` |
| quick-pick-presenting-013 | item-sendable-equatable, request-sendable-equatable | `SuspendingQuickPickPresenter.presentQuickPick` receives an `ExtensionQuickPickRequest` inside a `@MainActor`-isolated `async` method and appends it to `private(set) var requests: [ExtensionQuickPickRequest]` across the `await withCheckedContinuation` suspension point | Compiles and runs with no Sendable diagnostic, because both `ExtensionQuickPickItem` and `ExtensionQuickPickRequest` are declared `Sendable`; a non-Sendable struct captured this way across an actor-isolated suspension point does not compile under the project's `SWIFT_STRICT_CONCURRENCY: complete` setting |

## Edge Cases

- **Null/empty input**: `ExtensionQuickPickRequest.items == []` is not forbidden by this contract; a conformer presents an empty list, and `canPickMany`'s semantics are unaffected by the count (MUST — the protocol places no minimum-count constraint).
- **Null/empty input**: `title`, `placeHolder`, and `prompt` MAY independently be `nil`; nothing in the contract requires any of the three to be present (MAY).
- **Boundary values**: a request with exactly one item is the minimum non-empty case; `presenting-single-select-array-shape` and `presenting-index-based-answer` apply identically to it (MUST).
- **Boundary values**: an `onHighlight` index outside `0..<request.items.count` is not addressed by this protocol — it MAY occur (the type signature is a plain `(Int) -> Void`, with no bounds check declared here); the given sources' one consumer, `MainThreadWindow`, chooses to discard such a call rather than forward it to the extension, but that guard belongs to the consumer, not to this contract (MAY).
- **Concurrent access**: `@MainActor` isolation serializes each conformer's synchronous code, but this protocol places no constraint on whether a second `presentQuickPick` call MAY be issued to the same conformer instance before a prior call on that instance has returned; the production conformer `ExtensionPickerPresenter` resolves that overlap by dismissing the prior session (answering it `nil`) before presenting the new one, but that policy is the conformer's own decision, not part of this protocol's contract (MAY).
- **Error states**: not applicable — this file performs no I/O of its own (no network, database, or file-system access); every value it carries is data already supplied by the extension or a caller, and its one operation either returns a result or suspends, never throws.
- **Offline or disconnected state**: not applicable — `ExtensionQuickPickPresenting.swift` makes no network call and depends on no connectivity; a picker is presented entirely in-process.
- **Cancellation and timeouts**: `presentQuickPick` declares no timeout parameter and no `Task` cancellation handling of its own; a caller wanting a deadline or a cancellation path must implement it independently of this contract (MUST NOT be assumed present — it is an absent feature, not an unspecified one).
- **Malformed input**: not applicable to this file directly — turning a malformed extension-supplied item (a non-string `label`, a non-array `items` argument) into an error or a default is `MainThreadWindow.parseQuickPickItems(from:)`'s job, one layer up; this contract's types only ever hold values that have already passed that validation.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `request` | `ExtensionQuickPickRequest` | none (required) | The whole call's input to `presentQuickPick`; a conformer reads it to build what it shows. |
| `onHighlight` | `@escaping (Int) -> Void` | none (required) | Invoked by the conformer with an index into `request.items` each time the highlighted row changes. |
| `request.title` | `String?` | `nil` | `QuickPickOptions.title`. |
| `request.placeHolder` | `String?` | `nil` | `QuickPickOptions.placeHolder`; filter-field placeholder text. |
| `request.prompt` | `String?` | `nil` | `QuickPickOptions.prompt`; carried but read by nothing this file's own consumer builds. |
| `request.items` | `[ExtensionQuickPickItem]` | none (required) | The rows to present, in extension-supplied order, separators included. |
| `request.canPickMany` | `Bool` | none (required) | `QuickPickOptions.canPickMany`; whether more than one row may be accepted. |
| `request.matchOnDescription` | `Bool` | none (required) | `QuickPickOptions.matchOnDescription`; whether `description` participates in filtering (documented upstream default `false`). |
| `request.matchOnDetail` | `Bool` | none (required) | `QuickPickOptions.matchOnDetail`; whether `detail` participates in filtering (documented upstream default `false`). |
| `request.ignoreFocusOut` | `Bool` | none (required) | `QuickPickOptions.ignoreFocusOut`; whether the picker stays open when focus moves elsewhere. |

## Deep Linking

Not applicable: `ExtensionQuickPickPresenting.swift` defines no URL, route, or navigable destination — it is a data-and-protocol contract with no navigation surface of its own.

## Localization

Not applicable: the file defines no string literal of its own. Every string a user sees through this contract — `label`, `description`, `detail`, `title`, `placeHolder`, `prompt`, and every item's text — originates from the calling extension, not from `ExtensionQuickPickPresenting.swift`.

## Accessibility Options

Not applicable: `ExtensionQuickPickPresenting.swift` renders nothing and reads no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color) — it has no UI of its own.

## Feature Flags

Not applicable: the source declares no feature-flag key and contains no conditional feature-gating logic; every member is always available once a conformer exists.

## Analytics

Not applicable: the source contains no analytics or event-emission call of any kind.

## Privacy

- **Data collected**: `ExtensionQuickPickPresenting.swift` collects no data of its own; `ExtensionQuickPickItem` and `ExtensionQuickPickRequest` hold only values the calling extension already supplied for that one presentation.
- **Storage**: not applicable — this file performs no storage; a value exists only for the duration of one `presentQuickPick` call.
- **Transmission**: not applicable — this file transmits nothing itself; it is presented on-device by whatever conformer is in use.
- **Retention**: this file retains nothing beyond the lifetime of one `presentQuickPick` call's local state.

## Logging

Not applicable: the source contains no logging call of any kind — it imports only `Foundation`, with no `OSLog` or `Loggable` usage.

## Platform Notes

- **SwiftUI**: not this file's own dependency — `ExtensionQuickPickPresenting.swift` imports only `Foundation`, with no SwiftUI reference. A SwiftUI-hosted picker would need its own concrete conformer (the role `ExtensionPickerPresenter` plays for AppKit), but the protocol and its two data types are UI-framework agnostic and would not change.
- **AppKit / UIKit**: this is the source. `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/ExtensionQuickPickPresenting.swift` is part of the `AgenticToolkitMacOS` framework target, which `project.yml` declares `platform: macOS` only — no iOS target packages this file. It is `@MainActor`-isolated per its own declaration, and its production conformer among the given sources, `ExtensionPickerPresenter` (`macOS/Features/Extensions/UI/ExtensionPickerPresenter.swift`), is an AppKit window/view-controller-backed panel that also conforms to `ExtensionInputBoxPresenting`.
- **Compose**: model this as a Kotlin `interface ExtensionQuickPickPresenting` with `suspend fun presentQuickPick(request: ExtensionQuickPickRequest, onHighlight: (Int) -> Unit): List<Int>?`, confined to the main dispatcher (`Dispatchers.Main.immediate`) in place of `@MainActor`; `ExtensionQuickPickItem`/`ExtensionQuickPickRequest` become Kotlin `data class`es, whose structural equality already gives `Equatable` and whose immutability already gives `Sendable`'s guarantee across coroutine dispatch. `List<Int>?`'s `null` vs `emptyList()` distinction maps the `nil`-vs-`[]` contract directly.
- **React/Web**: model as a TypeScript `interface ExtensionQuickPickPresenting { presentQuickPick(request: ExtensionQuickPickRequest, onHighlight: (index: number) => void): Promise<number[] | undefined> }`; `undefined` vs `[]` is the same distinction JavaScript's own `showQuickPick` promise already makes (`extHostQuickOpen.ts`'s `handle.map(...)` resolving `[]` rather than `undefined`), so no adapter is needed for that part of the contract. `ExtensionQuickPickItem`/`ExtensionQuickPickRequest` become plain `interface`s (or `readonly` object types) rather than classes, since there is no initializer-visibility concern to solve on this platform.
- **WinUI 3**: model `ExtensionQuickPickPresenting` as `public interface IExtensionQuickPickPresenting { Task<IReadOnlyList<int>?> PresentQuickPickAsync(ExtensionQuickPickRequest request, Action<int> onHighlight, CancellationToken cancellationToken = default); }`, called only from the UI thread (the `DispatcherQueue` a WinUI 3 window owns, in place of `@MainActor`); a nullable `IReadOnlyList<int>?` gives the same `null`-vs-empty-collection distinction as `[Int]?` without a wrapper type. `ExtensionQuickPickItem` and `ExtensionQuickPickRequest` become `sealed record`s (`record ExtensionQuickPickItem(string Label, string? Description, string? Detail, bool IsSeparator, bool IsPicked, bool AlwaysShow)`), whose generated value-based `Equals`/`GetHashCode` gives `Equatable`'s guarantee, and whose immutability gives the same cross-thread-handoff safety `Sendable` states explicitly on the Swift side. `System.Text.Json` has no role here since nothing in this file serializes; it is Windows App SDK's own extension-host bridge (analogous to `MainThreadWindow`) that would decode the incoming request before constructing these types.

## Design Decisions

**Decision**: `ExtensionQuickPickPresenting` is a separate protocol from `ExtensionMessagePresenting`, rather than one protocol carrying both members.
**Rationale**: per the source's own doc comment, `NSAlertMessagePresenter` is the right conformer for a message and the wrong one for a picker; a single combined protocol would force a message-only conformer to implement a presentation it has no business showing — interface segregation, at the declared cost that `MainThreadWindow.init` takes two presenters rather than one.
**Approved**: pending

**Decision**: `nil` means the picker was dismissed; `[]` (only reachable when `canPickMany` is `true`) means the user explicitly accepted a selection of nothing. The two MUST NOT be conflated.
**Rationale**: upstream's `handle.map(...)` of an empty handle array resolves `[]` rather than `undefined` (`extHostQuickOpen.ts`); a conformer that answered `[]` for a dismissal would tell the extension the user accepted an empty selection, a different, observable answer to code doing `if (result === undefined)`.
**Approved**: pending

**Decision**: single-select and multi-select both answer through the same `[Int]?` return type — a one-element array for single-select — rather than two overloads (a bare `Int?` for single-select, `[Int]?` for multi-select).
**Rationale**: `canPickMany` is a field of the request every conformer already reads; two overloads would make each conformer spell the dismissal rule (`nil` vs `[]`) twice instead of once, per the source's own doc comment.
**Approved**: pending

**Decision**: `ExtensionQuickPickItem` carries no `iconPath`, `resourceUri`, or `buttons` field, even though `QuickPickItem` declares all three.
**Rationale**: per the struct's own doc comment, `buttons` is dropped because the VS Code declaration states buttons are "not rendered when using the `showQuickPick` API" at all; `iconPath` and `resourceUri` are dropped because nothing in this repo resolves an extension-supplied icon path to an image, and a field that is always dropped reads to the next person as a capability that exists when it does not — worse than the field's absence.
**Approved**: pending

**Decision**: constructing an `ExtensionQuickPickItem` for a separator row (`isSeparator == true`) MUST set `description`, `detail`, `isPicked`, and `alwaysShow` to their defaults regardless of what the extension supplied for them.
**Rationale**: quoting the source's own doc comment on `isSeparator`, "The only property that applies is `QuickPickItem.label`. All other properties on `QuickPickItem` will be ignored and have no effect," per `vscode.d.ts`.
**Approved**: pending

**Decision**: `isPicked` and `alwaysShow` are carried truthfully regardless of `canPickMany` or the current filter text; applying VS Code's own conditions for honoring them ("only honored when the picker allows multiple selections" for `picked`; keeping a row visible despite the filter for `alwaysShow`) is deferred to the presenting conformer or, for `alwaysShow`, to `ExtensionQuickPickModel.matches(_:filter:)`.
**Rationale**: per the source's own doc comment, a type that zeroed `isPicked` out itself would leave the presenter unable to tell "the extension did not ask for this row" from "the extension asked and something upstream discarded it"; the rule for when a flag is *honored* is a presentation concern, not a parsing concern.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |

`separation-of-concerns` passes because this file's only responsibility is declaring the contract — two plain data types and a single-method protocol — with no presentation logic, no AppKit dependency, and no networking or persistence of its own; it was split out of `MainThreadWindow.swift` specifically to keep that file from growing further, and is declared apart from `ExtensionMessagePresenting` on an explicit interface-segregation rationale (see Overview and Design Decisions). `unit-test-coverage` is partial: every runtime-observable behavior in this contract — the `nil`-vs-`[]` distinction, index-based (not label-based) selection, answer-order preservation, separator field defaulting, and highlight forwarding — has a direct test among the given sources (see Conformance Test Vectors 001–009, 011), but the two purely structural requirements about calling discipline and actor/type constraints (**presenting-highlight-after-return-prohibited**, **presenting-main-actor-isolation**, **presenting-class-only**, **presenting-single-requirement**, the `Sendable`/`Equatable` conformances) are verified by code inspection or by the compiler rather than by a dedicated runtime assertion in the given test files.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
