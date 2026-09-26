---
id: 95e26bae-21cb-4f99-8d28-724beca8ae1d
title: ExtensionTreeDataSource
domain: agentictoolkit://cookbook/macos/features/extensions/vs-code-api/extension-tree-data-source
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'The pull-based seam a contributed tree pane calls into a registered TreeDataProvider:
  async children, activation, title/message/multi-select chrome, and provider-replacement
  handover.'
platforms:
- swift
- macos
tags:
- extension-host
- vscode-api
- tree-view
- protocol
- mainactor
depends-on: []
related:
- agentictoolkit://cookbook/macos/features/extensions/tree/extension-tree-view-controller
references:
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/ExtensionTreeDataSource.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/Tree/ContributedTreeItem.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadTreeViews.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Extensions/MainThreadTreeViewsTests.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

# ExtensionTreeDataSource

## Overview

`ExtensionTreeDataSource` (`packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/ExtensionTreeDataSource.swift`) is a `@MainActor`, class-only (`AnyObject`) protocol: the seam a contributed **tree** pane calls into a registered `TreeDataProvider`. It is documented in its own header as the inverse of every other extension-host seam in that directory — a webview or a status bar item is something the extension *pushes* at the app through a `…Presenting` type the adaptor calls, while a tree is *pulled*: `children(of:)` is asked as rows come into view, asked again whenever the provider says the tree moved, and never asked for a branch the user never opens. The protocol is therefore what the pane calls, and the adaptor that wraps an extension's JavaScript `TreeDataProvider` is the conformer.

`children(of:)` is `async` because upstream's `TreeDataProvider.getChildren` returns `ProviderResult<T[]>` — `T[] | undefined | null | Thenable<...>` (`vscode.d.ts`) — and the thenable case is the common one, since a provider that reads a file or runs a process is usually the reason a tree exists; an `NSOutlineView` cannot wait, so the caller asks, draws what it has, and redraws when the answer lands. One conforming instance is held per registered view id, by the adaptor, for the extension's lifetime; `AnyObject` is required because the caller assigns the three callback properties directly onto the instance it holds, and a value type would take a copy of the thing it was trying to talk to rather than reach the same object the conformer mutates.

Every operation in this protocol traffics in `ContributedTreeItem` (`packages/apple/AgenticToolkit/macOS/Features/Extensions/Tree/ContributedTreeItem.swift`) — a `Sendable`, `Equatable`, `Identifiable` struct reducing a `vscode.TreeItem` to what an `NSOutlineView` row can draw, keyed by `id` (the extension's own element handle, `elementID`, not upstream's optional `TreeItem.id`). `ContributedTreeItem` is a collaborator consulted for grounding but is out of this recipe's scope, as is `MainThreadTreeViews.swift`'s `ExtensionTreeModel`, the one production conformer given among the sources, and `ExtensionTreeViewController` (`agentictoolkit://cookbook/macos/features/extensions/tree/extension-tree-view-controller`), the pane that is this protocol's one given caller.

## Behavioral Requirements

- **main-actor-isolation**: `ExtensionTreeDataSource` MUST be declared `@MainActor`; every property read/write and every method call on a conforming instance MUST execute on the main actor.
- **class-only-conformance**: A conforming type MUST be a reference type, since `ExtensionTreeDataSource` is declared `AnyObject`; the caller assigns `onDidChangeTreeData`, `onDidChangeChrome`, and `onProviderReplaced` directly onto the instance it holds, which a value-type conformer could not support.
- **children-signature**: `children(of:)` MUST be an `async` function that returns the children of the item named by `parent`, or the roots when `parent` is `nil`, as an array of `ContributedTreeItem`.
- **children-empty-on-failure**: `children(of:)` MUST answer with an empty array for every failure a conforming provider can produce: a provider that threw, a thenable that rejected, a provider that answered a non-array, and a call made against a registration that has since been disposed. A conformer MUST NOT propagate a thrown error to the caller through this method, since it declares no `throws` and the caller has no error-display surface for a tree row.
- **activation-caller-restraint**: `activate(_:)` MUST be invoked by the caller only on an explicit activation gesture (for example a double click, or Return on the selected row) and MUST NOT be invoked on a selection change alone, matching upstream's own firing of `TreeItem.command` on the click that selects rather than on every arrow-key move through the tree.
- **activate-runs-declared-command-only**: `activate(_:)` MUST run the command the given item declared, and MUST have no effect when the item declared none.
- **title-fallback-semantics**: `title` MUST be `nil` while the extension has not renamed the view through the `TreeView` object `createTreeView` returned; a caller MUST treat `nil` as "fall back to the manifest's declared name for this view."
- **message-is-supplementary-banner**: A non-`nil` `message` MUST be presented by the caller as a banner shown above the tree's rows, with the tree still drawn beneath it, and MUST NOT be presented as a replacement for the tree — an extension that keeps a standing message (for example, reporting a partial result count) would otherwise lose its entire tree to a caller that read the message as substituting for it.
- **multi-selection-flag-honored**: `allowsMultipleSelection` MUST be honored by the caller exactly as reported, since it is a value this seam's host is always capable of enforcing and has no business reporting as one it cannot.
- **tree-data-change-argument-semantics**: When invoked, `onDidChangeTreeData` MUST be called with the `id` of the `ContributedTreeItem` whose subtree changed, never with a freshly-built item, and MUST be called with `nil` to mean the whole tree changed; a caller MUST treat an id it has never resolved to a drawn row the same as `nil` — redrawing everything — since it has no other way to locate the corresponding row.
- **chrome-change-separate-from-tree-change**: A change to `title`, `message`, or `allowsMultipleSelection` MUST be signaled only through `onDidChangeChrome`, never through `onDidChangeTreeData`, because reloading the outline's rows for a chrome-only change would collapse every branch the user had opened.
- **provider-replacement-ordering**: When a conforming instance is superseded, `onProviderReplaced` MUST be called on the outgoing instance, with the replacement instance as its argument, before the outgoing instance is invalidated — so that whatever currently owns the outgoing instance's callbacks can hand them to the replacement while both are still live. `MainThreadTreeViews.swift`'s `adopt(_:for:)` (`packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadTreeViews.swift`) confirms this ordering is actually implemented as documented: it calls `replaced.onProviderReplaced?(model)` and only then `replaced.invalidate()`.
- **replacement-instance-arrives-unwired**: The replacement instance handed to `onProviderReplaced` MUST arrive with `onDidChangeTreeData`, `onDidChangeChrome`, and `onProviderReplaced` all unassigned.
- **replacement-callback-rewiring-required**: Whoever receives a data source through `onProviderReplaced` MUST assign that instance's `onDidChangeTreeData`, `onDidChangeChrome`, and `onProviderReplaced` — including reassigning `onProviderReplaced` itself — or a later replacement of that same instance has no path back to the caller.
- **one-instance-per-view-id**: A conforming instance MUST be held for exactly one registered view id, by the adaptor that resolves it to a pane, for the lifetime of the extension that registered it.
- **selection-reporting**: `selectionDidChange(to:)` MUST be called by the caller with the full current selection, as `ContributedTreeItem` values, whenever the row selection the pane displays changes.
- **visibility-reporting**: `visibilityDidChange(to:)` MUST be called by the caller whenever the pane hosting the tree becomes visible or becomes hidden.
- **expand-collapse-reporting**: `didExpand(_:)` and `didCollapse(_:)` MUST each be called by the caller with the corresponding row's `ContributedTreeItem` whenever the user expands or collapses that row.
- **in-flight-request-during-replacement**: The protocol orders only `onProviderReplaced` before the outgoing instance is invalidated; it declares nothing about a `children(of:)` call already in flight against the outgoing instance at that moment. Whether such a call completes, is discarded, or must be re-issued against the replacement is left to the conformer and its `invalidate()` timing; a caller MUST NOT assume any one of those outcomes from the protocol alone.

## Appearance

Not applicable — this is the pull-based seam a contributed tree pane calls into a registered `TreeDataProvider`, not a visual component.

## States

Not applicable — this is the pull-based seam a contributed tree pane calls into a registered `TreeDataProvider`, not a visual component. Its one lifecycle-shaped behavior — a conforming instance being superseded via `onProviderReplaced` and then invalidated — is captured under Behavioral Requirements (**provider-replacement-ordering**, **replacement-instance-arrives-unwired**), not as a visual-state table.

## Accessibility

Not applicable — this is the pull-based seam a contributed tree pane calls into a registered `TreeDataProvider`, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| etds-001 | children-signature | A conforming provider whose root list has two items | `children(of: nil)` returns exactly those two items, in the provider's order — traced to `MainThreadTreeViewsTests.childrenAreAskedForWithTheProvidersOwnElement` and `.rootRowsCarryTheLabelDescriptionTooltipStateAndIcon` |
| etds-002 | activate-runs-declared-command-only | A row whose declared `command` is `"acme.open"` with an argument | `activate(row)` runs `"acme.open"` with that argument — traced to `MainThreadTreeViewsTests.activatingARowRunsItsCommandThroughTheRegistryWithItsArguments` |
| etds-003 | activate-runs-declared-command-only | A row that declared no `command` (`item.commandID == nil`) | `activate(row)` has no effect; no command runs — traced to `MainThreadTreeViewsTests.activatingARowWithNoCommandRunsNothing` |
| etds-004 | title-fallback-semantics, message-is-supplementary-banner, multi-selection-flag-honored | `createTreeView` called with `canSelectMany: true`, then `title` and `message` written on the returned `TreeView` object | `source.title`, `source.message`, and `source.allowsMultipleSelection` read back exactly what was written — traced to `MainThreadTreeViewsTests.theTreeViewObjectsTitleMessageAndCanSelectManyReachTheDataSource` |
| etds-005 | chrome-change-separate-from-tree-change | `message` written on an already-created `TreeView` object | `onDidChangeChrome` fires (not `onDidChangeTreeData`) and `source.message` reflects the new value — traced to `MainThreadTreeViewsTests.writingTheMessageLaterTellsThePaneOnceForEachRealChange` |
| etds-006 | selection-reporting | `selectionDidChange(to: [row])` called for a specific drawn row | The extension's `onDidChangeSelection` fires carrying that row's own element, and `TreeView.selection` reflects it — traced to `MainThreadTreeViewsTests.selectingRowsFiresOnDidChangeSelectionWithTheProvidersElements` |
| etds-007 | visibility-reporting | `visibilityDidChange(to: true)` then `visibilityDidChange(to: false)` | The extension's `onDidChangeVisibility` observes `true` then `false`, in that order, and `TreeView.visible` ends `false` — traced to `MainThreadTreeViewsTests.visibilityChangesFireOnceEach` |
| etds-008 | expand-collapse-reporting | `didExpand(branch)` then `didCollapse(branch)` for a drawn branch row | The extension's `onDidExpandElement` then `onDidCollapseElement` each fire once, carrying that branch's own element — traced to `MainThreadTreeViewsTests.expandingAndCollapsingFireTheirEventsWithTheElement` |
| etds-009 | provider-replacement-ordering, replacement-instance-arrives-unwired | A second `TreeDataProvider` is registered for a view id an existing instance already holds live | `onProviderReplaced` fires on the outgoing instance with the new instance, before the outgoing instance is invalidated; the new instance's `onDidChangeTreeData`/`onDidChangeChrome`/`onProviderReplaced` are all `nil` at that point — traced to `MainThreadTreeViews.swift`'s `adopt(_:for:)`, corroborated by `MainThreadTreeViewsTests.aSecondRegistrationForTheSameViewIDTakesOver` |
| etds-010 | children-empty-on-failure | A conforming provider's `getChildren` throws, or its thenable rejects, or it answers a non-array, or the request targets a disposed registration | `children(of:)` resolves to an empty array in every one of the four cases — traced directly to the protocol's own doc comment enumerating them; only the "malformed registration" and "disposed registration" cases are exercised individually among the given tests (`MainThreadTreeViewsTests.registeringSomethingThatIsNotATreeDataProviderThrows`, `.disposingTheRegistrationRetractsTheDataSource`) — no test in the given sources isolates a thrown `getChildren` or a rejected thenable specifically |

## Edge Cases

- **Null/empty input**: `parent == nil` on `children(of:)` MUST be read as "give me the roots," not as an error or an empty request (MUST, per **children-signature**).
- **Null/empty input**: `title == nil` and `message == nil` are both meaningful, non-error values — `nil` title means "use the manifest name" and `nil` message means "show no banner" — neither MUST be treated as an unset/error state by the caller (MUST, per **title-fallback-semantics**, **message-is-supplementary-banner**).
- **Boundary values**: `children(of:)` answering an empty array for a genuinely childless branch is indistinguishable, at this protocol's boundary, from every failure case in **children-empty-on-failure** — the source documents this as deliberate (see Design Decisions), not a boundary the caller can resolve by inspecting the answer alone.
- **Concurrent access**: `@MainActor` isolation serializes entry into every property access and method call on a conforming instance, but does not serialize the `async` work inside `children(of:)` itself — two concurrent `children(of:)` calls for different parents against the same instance MAY have their underlying provider work interleave, and the protocol declares no de-duplication for two concurrent calls against the *same* parent (a caller that wants that guarantee, as `ExtensionTreeViewController` does, MUST implement it itself; see `agentictoolkit://cookbook/macos/features/extensions/tree/extension-tree-view-controller`).
- **Concurrent access**: a `children(of:)` call already awaiting an answer from the outgoing instance when `onProviderReplaced` fires has no protocol-level ordering; its outcome is the conformer's, per `in-flight-request-during-replacement`.
- **Error states**: no method in this protocol is declared `throws`; `children(of:)`'s only channel for any failure is the empty-array answer in **children-empty-on-failure**, and none of `activate(_:)`, `selectionDidChange(to:)`, `visibilityDidChange(to:)`, `didExpand(_:)`, or `didCollapse(_:)` has any failure channel at all — each is a plain, non-throwing notification (MUST, as declared).
- **Offline or disconnected state**: not applicable to this file directly. `children(of:)` is `async` specifically because a provider commonly performs I/O (reading a file, running a process) to answer it, but that I/O happens on the far side of this seam, inside the extension's own `TreeDataProvider` implementation — this protocol declares no network call, no timeout, and no retry of its own; any bound on how long a caller waits is imposed by the caller (`ExtensionTreeViewController`'s 30-second `childrenBudget`, out of this recipe's scope).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `parent` | `ContributedTreeItem?` | `nil` (roots) | Supplied by the caller to `children(of:)`; names the item whose children are requested, or asks for the roots when `nil`. |
| `item` | `ContributedTreeItem` | required | Supplied by the caller to `activate(_:)`, `didExpand(_:)`, and `didCollapse(_:)`; names the row the caller is reporting on. |
| `items` | `[ContributedTreeItem]` | required | Supplied by the caller to `selectionDidChange(to:)`; the full current selection. |
| `isVisible` | `Bool` | required | Supplied by the caller to `visibilityDidChange(to:)`; whether the pane hosting the tree is currently on screen. |
| `onDidChangeTreeData` | `((String?) -> Void)?` | `nil` | Assigned by whoever currently owns the instance's callbacks; invoked by the conformer with a changed element's `id`, or `nil` for the whole tree. |
| `onDidChangeChrome` | `(() -> Void)?` | `nil` | Assigned by whoever currently owns the instance's callbacks; invoked by the conformer when `title`, `message`, or `allowsMultipleSelection` changes. |
| `onProviderReplaced` | `((any ExtensionTreeDataSource) -> Void)?` | `nil` | Assigned by whoever currently owns the instance's callbacks; invoked once, with the replacement instance, before this instance is invalidated. |

## Deep Linking

Not applicable: `ExtensionTreeDataSource.swift` declares only method and property signatures — no URL scheme, route, or navigable destination of any kind appears anywhere in the file.

## Localization

Not applicable: `ExtensionTreeDataSource.swift` contains no string literal outside its doc comments — `title` and `message` are typed as caller-supplied `String?` values sourced from whatever the extension wrote, and the protocol itself neither produces nor owns any user-facing text of its own.

## Accessibility Options

Not applicable: `ExtensionTreeDataSource.swift` is a set of signatures with no executable body and renders nothing, so it consults none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: the file declares no feature-flag key and contains no conditional gating logic — it has no executable statements to gate.

## Analytics

Not applicable: the file emits no analytics or telemetry event of any kind — it has no executable statements to emit one from.

## Privacy

Not applicable: `ExtensionTreeDataSource.swift` declares no storage, transmission, or collection of any kind — it is a set of method and property signatures. Whatever data flows through them (row labels, titles, messages, the user's selection) is held and moved by the conformer and the caller on either side of the seam, neither of which is this file.

## Logging

Not applicable: `ExtensionTreeDataSource.swift` contains no log call — it has no executable body to log from. Its one given conformer's own logging (`MainThreadTreeViews.swift`) belongs to that conformer's own recipe, out of this recipe's scope.

## Platform Notes

- **SwiftUI**: not applicable to this file — `ExtensionTreeDataSource.swift` imports only `Foundation`, with no SwiftUI dependency. A SwiftUI port of this seam would replace the two settable closures `onDidChangeTreeData`/`onDidChangeChrome` with `@Observable`/`@Published` state (or an `AsyncStream<String?>`) a `List`/`OutlineGroup` view model subscribes to, keep `children(of:)` as an `async` method called from a `Task` per expanded node, and represent `onProviderReplaced` as a one-shot `AsyncStream<any TreeDataSource>` the holder awaits once to rebind — the same "assign once per instance" discipline this protocol requires, expressed idiomatically.
- **Compose**: model as a Kotlin `interface TreeDataSource` with `suspend fun children(of: Item?): List<Item>` and `fun activate(item: Item)`, confined to the main dispatcher to mirror `@MainActor`; replace `title`/`message`/`allowsMultipleSelection` with `StateFlow`s the caller collects instead of settable closures, and replace `onDidChangeTreeData`/`onDidChangeChrome` with `SharedFlow<String?>`/`SharedFlow<Unit>` the caller collects — Compose's idiomatic substitute for an assignable callback slot — while `onProviderReplaced` becomes a `SharedFlow<TreeDataSource>` collected exactly once per instance, preserving **replacement-callback-rewiring-required**.
- **React/Web**: model as an interface exposing `children(parent: Item | null): Promise<Item[]>` and `activate(item: Item): void`, plus an `EventTarget`-style pair of callback props (or a small pub/sub object) standing in for `onDidChangeTreeData`/`onDidChangeChrome`, and a `replace` callback prop standing in for `onProviderReplaced`; a component holding the source subscribes in a `useEffect` whose cleanup un-subscribes, and re-subscribes to the replacement inside the `replace` callback, matching **replacement-callback-rewiring-required**.
- **AppKit / UIKit**: this recipe's own platform. `ExtensionTreeDataSource.swift` is part of the `AgenticToolkitMacOS` framework target (macOS only; no iOS target packages this file). Its one given caller among the sources is `ExtensionTreeViewController.swift` (`NSOutlineView`-backed, `agentictoolkit://cookbook/macos/features/extensions/tree/extension-tree-view-controller`), and its one given conformer is `ExtensionTreeModel` in `MainThreadTreeViews.swift`; both are `@MainActor`-isolated, matching **main-actor-isolation**.
- **WinUI 3**: model this seam as a C# interface `IExtensionTreeDataSource` — `Task<IReadOnlyList<ContributedTreeItem>> GetChildrenAsync(ContributedTreeItem? parent)`, `void Activate(ContributedTreeItem item)`, `string? Title { get; }`, `string? Message { get; }`, `bool AllowsMultipleSelection { get; }` — with the three settable closures replaced by C# events: `event Action<string?>? TreeDataChanged`, `event Action? ChromeChanged`, `event Action<IExtensionTreeDataSource>? ProviderReplaced`. Events support `+=`/`-=` naturally, but **replacement-callback-rewiring-required** still applies: whoever takes over a replacement instance must subscribe its own handlers to that instance's events, including `ProviderReplaced` again, or a further replacement has nowhere to go. Drive a `Microsoft.UI.Xaml.Controls.TreeView` from `GetChildrenAsync` exactly as the companion `ExtensionTreeViewController` recipe's WinUI note describes (populate `TreeViewNode.Children` lazily inside `TreeView.Expanding`). Fire `ProviderReplaced` from whatever registry class plays the role of `MainThreadTreeViews`, immediately before that registry drops its own reference to the retiring instance, mirroring `adopt(_:for:)`'s "fire, then invalidate" order from **provider-replacement-ordering**.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/ExtensionTreeDataSource.swift` |

## Design Decisions

**Decision**: `children(of:)` answers an empty array for every failure a provider can produce — a thrown error, a rejected thenable, a non-array answer, and a call against a disposed registration — rather than distinguishing any of them to the caller.
**Rationale**: the caller draws an empty branch either way and has no display surface for the difference; the source's own doc comment states that surfacing a thrown error as a row "would put an extension's stack trace in a user's sidebar." The distinction is recorded by whichever conformer's own logging captures it (out of this recipe's scope), not by this protocol.
**Approved**: pending

**Decision**: `onDidChangeTreeData`'s argument is the changed element's `id` — a handle — rather than a freshly rebuilt `ContributedTreeItem`, and an id the caller has never resolved to a drawn row is treated the same as `nil`.
**Rationale**: the id is all a caller needs to locate the corresponding row and ask for its children again; building an item here would force a round trip for a row the caller may have already scrolled away from. Over-refreshing on an unresolvable id costs one extra `children(of:)` call; under-refreshing would leave a tree that silently stops matching the extension's own state.
**Approved**: pending

**Decision**: `onProviderReplaced` travels forward, from the outgoing instance to the caller, rather than through either of the two existing outward callbacks.
**Rationale**: a caller resolves its data source exactly once, when its view loads, and nothing ever re-offers one; an extension re-registering a provider for a view id it already owns is ordinary (every deactivate/activate cycle does it, and reloading the host does it for every view at once). Without a forward-traveling event, an already-open caller would go on holding an instance that, once invalidated, answers no children by design, forever.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |

`separation-of-concerns` passes because this file is a bare protocol: it declares the tree seam's shape and carries zero rendering, storage, or transport logic of its own — every side effect happens on the conformer's side (`MainThreadTreeViews.swift`) or the caller's side (`ExtensionTreeViewController.swift`), both out of this recipe's scope. `unit-test-coverage` is partial: a bare protocol has no body to unit-test directly, so its contract is exercised only indirectly, through `MainThreadTreeViewsTests.swift`'s tests of the one given conformer; those cover activation, chrome, selection, visibility, expand/collapse, and change-event semantics, but no test in the given sources isolates each of `children(of:)`'s four documented failure causes individually (see etds-010). `explicit-error-handling` is partial: no method here is declared `throws`, and `children(of:)`'s empty-array answer for every failure is a deliberate, documented choice rather than a silent swallow (see Design Decisions) — but it leaves conformers with no typed error channel, and the open question on **in-flight-request-during-replacement** is exactly the kind of ordering gap that absence leaves unresolved.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation from ExtensionTreeDataSource.swift; documented `in-flight-request-during-replacement` |
