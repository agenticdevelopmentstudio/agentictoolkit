<!-- leaf: implement-extension-host-vs-1/code-api-extension-tree-data-source · source: extension-host-vs-code-api-extension-tree-data-source.md -->

**Rules** (cite as `implement-extension-host-vs-1/code-api-extension-tree-data-source#<slug>`):

- `main-actor-isolation` MUST
- `class-only-conformance` MUST
- `children-signature` MUST
- `children-empty-on-failure` MUST
- `activation-caller-restraint` MUST
- `activate-runs-declared-command-only` MUST
- `title-fallback-semantics` MUST
- `message-is-supplementary-banner` MUST
- `multi-selection-flag-honored` MUST
- `tree-data-change-argument-semantics` MUST
- `chrome-change-separate-from-tree-change` MUST
- `provider-replacement-ordering` MUST
- `replacement-instance-arrives-unwired` MUST
- `replacement-callback-rewiring-required` MUST
- `one-instance-per-view-id` MUST
- `selection-reporting` MUST
- `visibility-reporting` MUST
- `expand-collapse-reporting` MUST
- `in-flight-request-during-replacement` MUST

# ExtensionTreeDataSource

## Overview

`ExtensionTreeDataSource` (`packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/ExtensionTreeDataSource.swift`) is a `@MainActor`, class-only (`AnyObject`) protocol: the seam a contributed **tree** pane calls into a registered `TreeDataProvider`. It is documented in its own header as the inverse of every other extension-host seam in that directory — a webview or a status bar item is something the extension *pushes* at the app through a `…Presenting` type the adaptor calls, while a tree is *pulled*: `children(of:)` is asked as rows come into view, asked again whenever the provider says the tree moved, and never asked for a branch the user never opens. The protocol is therefore what the pane calls, and the adaptor that wraps an extension's JavaScript `TreeDataProvider` is the conformer.

`children(of:)` is `async` because upstream's `TreeDataProvider.getChildren` returns `ProviderResult<T[]>` — `T[] | undefined | null | Thenable<...>` (`vscode.d.ts`) — and the thenable case is the common one, since a provider that reads a file or runs a process is usually the reason a tree exists; an `NSOutlineView` cannot wait, so the caller asks, draws what it has, and redraws when the answer lands. One conforming instance is held per registered view id, by the adaptor, for the extension's lifetime; `AnyObject` is required because the caller assigns the three callback properties directly onto the instance it holds, and a value type would take a copy of the thing it was trying to talk to rather than reach the same object the conformer mutates.

Every operation in this protocol traffics in `ContributedTreeItem` (`packages/apple/AgenticToolkit/macOS/Features/Extensions/Tree/ContributedTreeItem.swift`) — a `Sendable`, `Equatable`, `Identifiable` struct reducing a `vscode.TreeItem` to what an `NSOutlineView` row can draw, keyed by `id` (the extension's own element handle, `elementID`, not upstream's optional `TreeItem.id`). `ContributedTreeItem` is a collaborator consulted for grounding but is out of this recipe's scope, as is `MainThreadTreeViews.swift`'s `ExtensionTreeModel`, the one production conformer given among the sources, and `ExtensionTreeViewController` (`agentictoolkit://recipes/extension-tree-view-controller`), the pane that is this protocol's one given caller.

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

