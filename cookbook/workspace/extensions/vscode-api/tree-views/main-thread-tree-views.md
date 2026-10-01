---
id: 8a2a51ce-eee3-4c8b-b6df-90daa35f7ad0
title: VS Code Tree Views Bridge
domain: agentictoolkit://cookbook/workspace/extensions/vscode-api/tree-views/main-thread-tree-views
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: The extension host's bridge for vscode.window.registerTreeDataProvider
  and createTreeView — pulling rows from an extension's tree data provider, minting
  a per-row handle for each element, and bridging the TreeView object's chrome,
  selection, and lifecycle events back into the extension's JavaScript environment.
platforms:
- swift
- macos
tags:
- extension-host
- vscode-api
- tree-view
- disposable
depends-on: []
related:
- agentictoolkit://cookbook/workspace/extensions/vscode-api/tree-views/extension-tree-data-source
- agentictoolkit://cookbook/workspace/extensions/vscode-api/commands/main-thread-commands
references:
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadTreeViews.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/ExtensionTreeDataSource.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/Tree/ContributedTreeItem.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/Host/NotImplementedLedger.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/VSCodeAPI.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/UI/AppShell/AppCommand.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Extensions/ContributedViews.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Loggable.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Extensions/MainThreadTreeViewsTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/project.yml (agentictoolkit)
approved-by: ''
approved-date: ''
---

# VS Code Tree Views Bridge

## Overview

This is the extension host's bridge for `vscode.window.registerTreeDataProvider` and `vscode.window.createTreeView`, and it builds the `vscode.TreeView` object the second one hands back. It is the one bridge in this area whose seam points the other way from its siblings: a webview provider is called once and never again, while a tree data provider is asked for rows for as long as its pane is open, so this bridge's whole substance is the element bookkeeping a webview bridge has no use for. It owns a registration table, one entry per contributed view id this extension currently provides; each entry is the actual tree data source conformer for that registration and does the element bookkeeping — the one production conformer the type `agentictoolkit://cookbook/workspace/extensions/vscode-api/tree-views/extension-tree-data-source` names out of its own scope.

The element table is the whole of the bookkeeping. `getChildren`/`getTreeItem` are asked about the provider's own model objects, which live only in the extension's JavaScript environment; the pane on the other side of the protocol boundary knows nothing but tree item values keyed by an opaque id. The element table is what lets a later children-request or activation call turn that opaque id back into the element the extension itself understands, and a command table, a parent table, and a child-handle table are the same idea applied to a row's declared command and its position in the tree. Every element reference here belongs to the registration alone — nothing exported back to the extension (the `TreeView` object, its event-subscription blocks) retains one, because holding a live reference to an extension-side value from an object the extension's own runtime holds would create a reference cycle; every block the `TreeView` object exposes holds the registration only weakly instead.

Handles are minted per row and are **positional unless the row declared a `TreeItem.id`**: a declared id becomes `#<escaped-id>` and an undeclared one becomes `<parent-handle>/<index>`. The two handle spaces are kept disjoint by escaping `%` and `/` out of a declared id (never by the `#` prefix, which is not itself sufficient — see Behavioral Requirements), which is what lets a declared handle safely be a string-prefix of a positional one without the two ever colliding. This bridge's own history documents one bug this shape previously produced and fixed: a targeted refresh (`onDidChangeTreeData(element)`) used to drop a whole subtree from the element table before rebuilding it, which left rows the pane had already drawn (and their commands) pointing at nothing; the fix diffs the previous children against the newly reissued ones and only forgets the ones that were not reissued, at any depth.

## Behavioral Requirements

- **main-thread-confinement**: Both the bridge and each registration MUST be confined to a single thread; every stored property and method on either MUST execute on that thread, because the extension's own values are not safe to share across threads and the extension's runtime invokes every block here on the thread that made the call.
- **register-raises-on-torn-down-adaptor**: Registering a tree data provider MUST raise rather than return a disposable once the bridge has been torn down, matching the registration call's own synchronous disposable return shape.
- **create-tree-view-raises-on-torn-down-adaptor**: Creating a tree view MUST raise rather than return a tree view once the bridge has been torn down, matching the creation call's own synchronous return shape.
- **register-requires-string-view-id**: Registering a tree data provider MUST raise "\<path\>'s first argument must be a view id string." and register nothing when the first argument is missing or is not a string.
- **create-tree-view-requires-string-view-id**: Creating a tree view MUST raise "\<path\>'s first argument must be a view id string." and register nothing when the first argument is missing or is not a string.
- **create-tree-view-requires-options-object**: Creating a tree view MUST raise "\<path\>'s second argument must be a TreeViewOptions object." when the second argument is missing or is not an object.
- **provider-requires-getchildren-and-gettreeitem**: Both registering a tree data provider and creating a tree view MUST require the provider argument to be an object whose `getChildren` and `getTreeItem` properties are both functions, and MUST raise "\<path\> requires a TreeDataProvider with getChildren(element) and getTreeItem(element) methods." and register nothing when either check fails.
- **last-registration-wins-and-is-logged**: Adopting a new registration for a view id MUST replace whatever registration currently exists for that view id, and MUST log, at error level, that this extension registered a second provider for that view id and the later one wins, whenever a replacement occurs.
- **provider-replacement-ordering**: Adopting a replacement registration MUST notify the outgoing registration's provider-replaced callback with the new registration, and only after that notification MUST it invalidate the outgoing registration — matching the tree data source's own provider-replacement-ordering requirement.
- **registration-disposable-is-token-guarded**: The disposable returned by registration MUST remove that registration only when it is still the one currently held for that view id, identified by a token minted at registration time; a disposable from a registration that has since been superseded by a later one for the same view id MUST therefore have no effect.
- **subscribe-to-changes-is-optional**: Subscribing to the provider's change notifications MUST do nothing when the provider has no change-notification property, or when that property is not a function, treating a provider with no change event as one that simply never refreshes rather than as an error.
- **can-select-many-is-honored**: Reading the tree view options MUST set the registration's allows-multiple-selection setting to `canSelectMany`'s boolean value whenever that property is present and is a boolean, and MUST leave it at its default (`false`) otherwise.
- **show-collapse-all-is-recorded-not-implemented**: Reading the tree view options MUST record `vscode.TreeViewOptions.showCollapseAll` in the not-implemented ledger when that option is present, is a boolean, and is `true`; a title-bar "collapse all" button is a capability this pane does not draw.
- **drag-and-drop-controller-is-recorded-not-implemented**: Reading the tree view options MUST record `vscode.TreeViewOptions.dragAndDropController` in the not-implemented ledger when that option is present and is an object.
- **manage-checkbox-state-manually-is-recorded-not-implemented**: Reading the tree view options MUST record `vscode.TreeViewOptions.manageCheckboxStateManually` in the not-implemented ledger when that option is present, is a boolean, and is `true`.
- **children-of-nil-requests-roots**: Requesting children MUST call the provider's `getChildren` with no element argument when the parent is the root, and MUST call it with the element the parent handle was minted from otherwise.
- **children-empty-when-parent-element-unknown**: Requesting children MUST return an empty list without calling `getChildren` at all when the parent is non-root and the element table has no entry for it (the registration has forgotten that row, most likely because a refresh replaced its own parent).
- **children-empty-when-getchildren-unusable**: Requesting children MUST log the extension identifier and view id and return an empty list when the provider has no `getChildren` property or that property is not a function.
- **children-empty-on-getchildren-throw-or-rejection**: Requesting children MUST log and return an empty list when calling `getChildren` throws or is unavailable, or when the returned thenable rejects or its settlement is unavailable.
- **children-treats-undefined-null-as-no-children**: Requesting children MUST treat a `getChildren` return value (or its settled thenable value) of `undefined` or `null` as "no children," returning an empty list without logging, per `ProviderResult<T[]>`'s own `T[] | undefined | null | Thenable<...>` shape (`vscode.d.ts`).
- **children-empty-on-non-array-result**: Reading items from an answer MUST log and return an empty list when the settled result's length cannot be determined (the provider answered something that is not an array).
- **children-rechecks-invalidation-after-await**: Requesting children MUST check whether the registration has since been invalidated immediately after the settlement wait returns, and MUST return an empty list rather than reading items when the registration was invalidated while that wait was in flight.
- **tree-item-duck-typed-not-instanceof**: Reading a tree item MUST accept any object `getTreeItem` returns (directly or through a settled thenable) as a `TreeItem`, and MUST NOT require it to be an actual instance of a `TreeItem` class; it MUST log and return nothing only when the value is missing, `undefined`, `null`, not an object, or when `getTreeItem` threw, its promise rejected, or the call was unavailable.
- **declared-id-becomes-the-handle**: Minting a handle for a row MUST return `"#<escaped-id>"` when the `TreeItem`'s `id` property is a non-empty string, and MUST return `"<parent>/<index>"` (the positional handle) otherwise.
- **handle-escaping-keeps-the-two-spaces-disjoint**: Escaping a declared id for use as a handle MUST replace every `%` with `%25` and then every `/` with `%2F` (in that order, so escaping `%` first cannot re-escape the escapes it just produced from `/`), so that no declared handle ever contains a `/` character and a declared handle can never collide with, or be misread as a prefix boundary of, a positional handle built from `<parent>/<index>`.
- **duplicate-declared-id-in-one-answer-keeps-the-first**: When `getChildren` (or the settled array from its thenable) lists two elements that mint the same handle within one answer, reading that answer MUST keep the first one's element and row, MUST log that the later one is dropped, and MUST NOT add a second row for the same handle.
- **targeted-refresh-keeps-unreissued-descendants-alive**: Reading a targeted refresh's items MUST take the parent's previously recorded children out of the child-handle table before rebuilding, but MUST leave every grandchild's own element/command/child-handle entries untouched during the rebuild, so that a child handle reissued during this refresh keeps every row already drawn beneath it live and answerable.
- **targeted-refresh-forgets-only-genuinely-removed-children**: After rebuilding, reading a targeted refresh's items MUST forget only the subset of the previous children that were not reissued in this answer, and MUST NOT forget any handle the answer reissued.
- **forget-drops-a-handle-and-everything-beneath-it**: Forgetting a handle MUST remove it (and, recursively, every handle recorded under it) from the element table, the command table, the parent table, and the child-handle table.
- **file-moves-a-relocated-declared-handle**: Filing a handle under a parent MUST, when that handle was previously filed under a different parent, remove it from that former parent's list before appending it under the new parent, so a declared handle an extension moves between branches is never listed under both at once.
- **label-fallback-chain**: Deriving a row's label MUST use `TreeItem.label` when it is a plain string; otherwise, when `label` is an object with a string `label` property (the structured `TreeItemLabel` form), MUST use that string; otherwise, when `resourceUri` is an object with a non-empty `fsPath` or `path` string, MUST use that path's last path component; otherwise MUST use the element's own string representation; it MUST NOT return an empty string through any of these branches for a value that reached the final fallback.
- **description-true-reads-as-absent**: A row's description MUST be absent both when `TreeItem.description` is absent and when it is the boolean `true`, since deriving a description from `resourceUri` (upstream's meaning of `true`) has no resource model on this host to derive it from; only a `TreeItem.description` that is itself a string MUST be carried through.
- **tooltip-markdown-string-reads-as-plain-text**: Reading a row's tooltip MUST read `TreeItem.tooltip` as a plain string when it is one, and otherwise, when it is an object, MUST read its `value` property as a plain string; a `MarkdownString` tooltip's markup is never rendered, only its `value` text.
- **collapsible-state-clamps-unknown-to-none**: Reading a row's collapsible state MUST map `1` to `.collapsed` and `2` to `.expanded`, and MUST map every other value (including absent and any integer outside `0...2`) to `.none`.
- **icon-path-theme-icon-resolves-via-codicon-symbols**: Resolving a row's icon path MUST resolve a `ThemeIcon`-shaped value (an object with a string `id` and no `fsPath` or `path` string) to that codicon's mapped symbol name, and MUST return that mapping's result unchanged, including nothing for a codicon this host has no mapping for.
- **icon-path-other-cases-record-not-implemented**: Resolving a row's icon path MUST record `vscode.TreeItem.iconPath` in the not-implemented ledger and return nothing for every non-absent icon path value that is not the `ThemeIcon` shape in `icon-path-theme-icon-resolves-via-codicon-symbols` (a string, a `Uri`/`fsPath`-bearing object, or a `{ light, dark }` object).
- **context-value-records-not-implemented-on-any-value**: Reading a row's fields MUST record `vscode.TreeItem.contextValue` in the not-implemented ledger whenever `TreeItem.contextValue` is a non-absent string, since this host contributes no `when`-clause context menus for a tree row to drive.
- **checkbox-state-records-not-implemented-on-any-defined-value**: Reading a row's fields MUST record `vscode.TreeItem.checkboxState` in the not-implemented ledger whenever `TreeItem.checkboxState` is present and is neither `undefined` nor `null`, including the falsy value `0`.
- **command-is-read-and-cleared-on-absence**: Reading a row's declared command MUST store its id and arguments and return the id when `TreeItem.command` is an object with a string `command` property; when it is not (absent, not an object, or missing that property), it MUST clear any previously stored command for that handle and return nothing, so a row whose extension has withdrawn its command cannot go on running the command it declared on a previous refresh under the same handle.
- **command-arguments-are-forwarded-as-jsvalues-unconverted**: Reading a row's declared command MUST read `command.arguments` as a list of the extension's own values, and MUST store each element exactly as given, with no conversion to a host-native representation.
- **activate-runs-through-the-command-registry-directly**: Activating a row MUST dispatch its stored command through the command registry directly (the same registry the commands bridge uses), and MUST NOT go back through the extension-visible command-execution API, because the command may belong to another extension or to the app itself and the registry is where all three meet.
- **activate-is-a-no-op-with-no-stored-command**: Activating a row MUST have no effect, and MUST NOT dispatch anything, when that row's handle has no stored command (including when the registration has been invalidated).
- **activate-catches-and-logs-a-thrown-registry-error**: Activating a row MUST catch any error the command registry throws, MUST log it at error level with the extension identifier and the command id, and MUST NOT propagate it to the caller.
- **change-with-nil-refreshes-the-whole-tree**: Handling the provider's change notification MUST report the whole tree changed when its argument is absent, `undefined`, or `null`.
- **change-with-an-array-fires-once-per-resolved-element**: Handling the provider's change notification MUST, when its argument is an array, report a change once for each element that resolves to exactly one known handle, in the array's own order.
- **change-with-an-unknown-or-ambiguous-element-refreshes-the-whole-tree**: Handling the provider's change notification MUST report the whole tree changed and stop, without processing any further elements in the array, as soon as matching an element to a handle answers "none" or "ambiguous" for any array element or for a single non-array argument.
- **element-match-is-by-javascript-identity-with-ambiguity-detection**: Matching an element to a handle MUST scan every entry in the element table and compare by the extension's own identity equality, MUST answer with exactly one handle when exactly one entry matches, "none" when zero match, and MUST answer "ambiguous" — even though it has already found one match — as soon as a second matching entry is found, since identity equality is value equality for a primitive element and the same primitive can legitimately be filed under two handles.
- **selection-reporting-suppresses-unchanged-selections**: Reporting a selection change MUST compare the new selection's handles against the recorded selection and MUST return without firing the selection-changed event when they are equal.
- **visibility-reporting-suppresses-unchanged-visibility**: Reporting a visibility change MUST compare the new value against the recorded visibility and MUST return without firing the visibility-changed event when they are equal.
- **expand-collapse-always-fire**: Reporting an expansion or a collapse MUST fire the corresponding event for that row's item on every call, with no suppression of a repeated expand or collapse of the same row.
- **checkbox-change-event-is-real-but-never-fired**: The checkbox-change event MUST be a real, subscribable event, and no code path here MUST ever fire it; subscribing to it MUST record `vscode.TreeView.onDidChangeCheckboxState` in the not-implemented ledger.
- **title-message-accessors-forward-to-the-model**: The tree view object's `title` and `message` accessors MUST read and write the registration's own title and message unchanged.
- **description-accessor-records-not-implemented-only-on-write**: The tree view object's `description` accessor's getter MUST return the registration's stored description unchanged; its setter MUST store the written value and MUST record `vscode.TreeView.description` in the not-implemented ledger on every write, whether or not the pane draws a subtitle anywhere.
- **badge-accessor-ignores-reads-and-records-non-nullish-writes**: The tree view object's `badge` accessor's getter MUST always answer `undefined`/`null` regardless of any value ever written; its setter MUST record `vscode.TreeView.badge` in the not-implemented ledger only when the written value is non-absent, not `undefined`, and not `null`.
- **visible-and-selection-are-readonly**: The tree view object MUST expose `visible` and `selection` only as readonly properties, backed by the registration's own visibility and selection state.
- **event-emitters-are-built-lazily-on-first-subscription**: Each of the selection-changed, visibility-changed, expansion, collapse, and checkbox-change events MUST be constructed only on first subscription, so an event this extension never subscribes to is never built.
- **reveal-always-records-not-implemented-and-resolves**: The tree view object's `reveal` member MUST record `vscode.TreeView.reveal` in the not-implemented ledger on every call and MUST resolve with nothing, regardless of the element or options passed to it; it MUST NOT reject and MUST NOT scroll, select, or expand any row.
- **treeview-dispose-forgets-through-the-owning-registration**: The tree view object's `dispose` member MUST forget the registration through the same token guard as `registration-disposable-is-token-guarded`.
- **disposal-invalidates-every-live-model**: Disposing the bridge MUST invalidate every live registration and MUST leave the registration table empty when it returns; it MUST be idempotent, doing nothing on a second call.
- **invalidate-is-idempotent-and-releases-the-change-subscription**: Invalidating a registration MUST do nothing on any call after its first; on its first call it MUST release its change subscription (if present), clear the element, command, parent, child-handle, and selected-handle tables, remove every listener this registration owns from all five events, and clear its change and chrome-change callbacks; it MUST clear its provider-replaced callback only after any pending notification through that callback that this invalidation is part of has already fired, per `provider-replacement-ordering`.
- **hastreedataprovider-and-treedatasource-answer-false-nil-when-disposed**: Checking whether a tree data provider exists MUST answer `false`, and reading the tree data source MUST answer nothing, whenever the bridge has been disposed, regardless of whether the registration table still holds an entry for the given view id.
- **logging-conformance**: Both the bridge and each registration MUST each expose their own separately-scoped logger.

A dedicated "forget descendants" operation exists but is not called anywhere in this component; the targeted-refresh diff (`targeted-refresh-forgets-only-genuinely-removed-children`) is what actually retires a handle's descendants today. This is a fact about the current implementation, not a gap — the underlying forget operation that it is built on is what every live code path calls.

## Appearance

Not applicable — this is the extension host's `vscode.window` tree-view bridge, a logic component with no view of its own; the rows it produces are drawn by whatever tree data source's caller exists outside this component's scope.

## States

Not applicable — this is a logic component, not a visual one. Its lifecycle-shaped behavior (a registration's live-versus-superseded-versus-invalidated status, and the bridge's own disposed status) is captured under Behavioral Requirements (**provider-replacement-ordering**, **registration-disposable-is-token-guarded**, **invalidate-is-idempotent-and-releases-the-change-subscription**, **disposal-invalidates-every-live-model**) rather than as a visual-state table.

## Accessibility

Not applicable — this is a logic component with no UI of its own; accessibility of the rows it produces belongs to the pane that draws the tree items, out of this component's scope.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| main-thread-tree-views-001 | declared-id-becomes-the-handle | Root elements with declared ids `'fruit'` and `'veg'` | Requesting root children answers rows whose ids are exactly `["#fruit", "#veg"]` — `MainThreadTreeViewsTests.aDeclaredTreeItemIDBecomesTheHandle` |
| main-thread-tree-views-002 | declared-id-becomes-the-handle | Two root elements, neither declaring a `TreeItem.id` | Requesting root children answers rows whose ids are exactly `["/0", "/1"]` — `MainThreadTreeViewsTests.anItemWithNoIDGetsAPositionalHandle` |
| main-thread-tree-views-003 | last-registration-wins-and-is-logged | A second `registerTreeDataProvider('acme.tree', ...)` call for a view id an earlier provider from the same extension already owns | The pane's rows now come from the second provider only; the error is logged — `MainThreadTreeViewsTests.aSecondRegistrationForTheSameViewIDTakesOver` |
| main-thread-tree-views-004 | registration-disposable-is-token-guarded | The first registration's `Disposable` is called after a second registration has replaced it for the same view id | Whether a tree data provider is registered remains `true`; the second registration is unaffected — `MainThreadTreeViewsTests.theFirstRegistrationsDisposableCannotRetractTheSecond` |
| main-thread-tree-views-005 | change-with-an-array-fires-once-per-resolved-element | The provider fires `onDidChangeTreeData` with the element already filed under handle `#fruit` | The registration's change callback is called with `handles == ["#fruit"]` — `MainThreadTreeViewsTests.firingTheChangeEventWithAnElementNamesThatElementsHandle` |
| main-thread-tree-views-006 | change-with-nil-refreshes-the-whole-tree | The provider fires `onDidChangeTreeData` with no argument (JavaScript `undefined`) | The registration's change callback is called with `handles == [nil]` — `MainThreadTreeViewsTests.firingTheChangeEventWithNothingNamesTheWholeTree` |
| main-thread-tree-views-007 | show-collapse-all-is-recorded-not-implemented, drag-and-drop-controller-is-recorded-not-implemented, manage-checkbox-state-manually-is-recorded-not-implemented, description-accessor-records-not-implemented-only-on-write, reveal-always-records-not-implemented-and-resolves, context-value-records-not-implemented-on-any-value, checkbox-state-records-not-implemented-on-any-defined-value | `createTreeView` with `showCollapseAll: true`, `manageCheckboxStateManually: true`, and a `dragAndDropController`; the returned `TreeView`'s `description` is set and `reveal(1)` is called; the provider's `getTreeItem` sets `contextValue: 'file'` and `checkboxState: 0` | The ledger for this extension contains rows for `vscode.TreeViewOptions.showCollapseAll`, `.manageCheckboxStateManually`, `.dragAndDropController`, `vscode.TreeView.description`, `vscode.TreeView.reveal`, `vscode.TreeItem.contextValue`, and `vscode.TreeItem.checkboxState` — `MainThreadTreeViewsTests.membersThisHostDoesNotDrawRecordALedgerRow` |
| main-thread-tree-views-008 | icon-path-theme-icon-resolves-via-codicon-symbols, icon-path-other-cases-record-not-implemented | One element's `iconPath` is `new vscode.ThemeIcon('github')` (a codicon this host has no faithful mapping for); another's is `{ fsPath: '/tmp/icon.png' }` | Both rows' resolved symbol is nothing; exactly one ledger row is recorded for `vscode.TreeItem.iconPath`, with `count == 1` — `MainThreadTreeViewsTests.aFileIconPathRecordsARowAndAnUnmappableCodiconDoesNot` |
| main-thread-tree-views-009 | disposal-invalidates-every-live-model | The bridge is disposed while a provider is registered for `'acme.tree'` | Whether a tree data provider is registered for `"acme.tree"` becomes `false`, and reading its tree data source becomes nothing — `MainThreadTreeViewsTests.disposingTheAdaptorRetractsEveryDataSource` |
| main-thread-tree-views-010 | register-raises-on-torn-down-adaptor | Registration is attempted again, from the extension, after the bridge has been disposed | The call raises rather than returning a `Disposable` — `MainThreadTreeViewsTests.registeringAfterTeardownThrows` |
| main-thread-tree-views-011 | targeted-refresh-keeps-unreissued-descendants-alive, forget-drops-a-handle-and-everything-beneath-it | A three-level tree (`branch`/`child`/`grandchild`, all declared ids) is fully expanded, then `branch`'s own subtree is targeted-refreshed (its `getChildren` reissues the same `child`) | `grandchild`'s row is still answerable — requesting its children still resolves, and activating it still runs its own declared command — `MainThreadTreeViewsTests.refreshingABranchKeepsTheRowsBelowItAlive` |
| main-thread-tree-views-012 | targeted-refresh-forgets-only-genuinely-removed-children, command-is-read-and-cleared-on-absence | A root list of two declared-id rows (`a`, `b`) is read, then the provider is made to answer only `a` on the next request for root children | The second root-children request answers only `["#a"]`; activating the row previously known as `b` (kept from the first read) no longer runs any command — `MainThreadTreeViewsTests.refreshingABranchForgetsTheRowsItStoppedNaming` |
| main-thread-tree-views-013 | handle-escaping-keeps-the-two-spaces-disjoint | A root declaring `id: 'src'` (collapsible, one unnamed child) alongside a sibling root declaring `id: 'src/0'` | The sibling's handle (`#src%2F0`) and the unnamed child's positional handle (`#src/0`) are different strings; activating the sibling runs its own command, not the unnamed child's — `MainThreadTreeViewsTests.aDeclaredIDCannotCollideWithAPositionalHandle` |

## Edge Cases

- **Null/empty input**: `registerTreeDataProvider()`/`createTreeView()` called with zero arguments MUST fail the string-view-id guard (the first argument is missing) and raise the same message as a non-string first argument, per **register-requires-string-view-id**/**create-tree-view-requires-string-view-id** (MUST).
- **Null/empty input**: a provider's `getChildren` answering `undefined` or `null` (directly, or as the settled value of a returned thenable) MUST be read as "no children," not as a failure, per **children-treats-undefined-null-as-no-children** (MUST).
- **Boundary values**: a view id equal to the empty string is a valid string and reaches the registration step exactly as any other id would; nothing in this component rejects it, since **register-requires-string-view-id**/**create-tree-view-requires-string-view-id** check only that the value is a string (fact).
- **Boundary values**: a `TreeItem.collapsibleState` outside `0...2` (or absent) is clamped to `.none` rather than rejected, per **collapsible-state-clamps-unknown-to-none** (MUST).
- **Concurrent access**: both the bridge and each registration are confined to a single thread with no additional locking; every stored property is read and mutated only on that thread, so there is no data race to define behavior for at the implementation level (fact).
- **Concurrent access**: NEEDS REVIEW: Not implemented. Behavior undefined. Two children requests issued for the **same** parent before the first one's settlement wait returns MUST NOT be assumed to leave the child-handle/element tables in any particular state relative to each other — each call independently clears the parent's previous-children entry before its own wait, so the second call to reach that point sees an already-emptied entry rather than the first call's in-flight previous-children snapshot.
- **Error states**: a provider's `getChildren` or `getTreeItem` throwing, or its returned thenable rejecting, MUST be logged and MUST answer a children request with an empty list; neither exception nor rejection reason is ever surfaced to the pane, per **children-empty-on-getchildren-throw-or-rejection** and **tree-item-duck-typed-not-instanceof** (MUST).
- **Error states**: activating a row's underlying command-registry dispatch throwing MUST be caught, logged, and swallowed; it MUST NOT propagate to the pane that requested activation, per **activate-catches-and-logs-a-thrown-registry-error** (MUST).
- **Cancellation or timeout**: not applicable to any member here — the settlement wait (out of this component's scope) has no timeout of its own, and this component imposes none; a `getChildren`/`getTreeItem` thenable that never settles leaves the corresponding children request suspended indefinitely (fact, inherited from that settlement mechanism).
- **Missing or unreachable resource**: a children request for a `parent` whose handle this registration has already forgotten (a branch expanded across a refresh that replaced its parent) MUST answer an empty list without calling `getChildren`, per **children-empty-when-parent-element-unknown** (MUST).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `notImplementedLedger` | ledger (shared) | none (required) | Shared record of unimplemented `vscode` members this extension reached for; passed to every registration this bridge creates. |
| `extensionIdentifier` | string | none (required) | The extension this bridge instance belongs to; attributed on every ledger row and every log line. |
| `commands` | registry | none (required) | The registry activation dispatches a row's declared command through. |
| `TreeViewOptions.canSelectMany` | boolean | `false` | Read when creating a tree view; sets the registration's allows-multiple-selection setting. |
| `TreeViewOptions.showCollapseAll` | boolean | `false` | Read when creating a tree view; `true` records a not-implemented ledger row and has no other effect. |
| `TreeViewOptions.dragAndDropController` | object | absent | Read when creating a tree view; presence records a not-implemented ledger row and has no other effect. |
| `TreeViewOptions.manageCheckboxStateManually` | boolean | `false` | Read when creating a tree view; `true` records a not-implemented ledger row and has no other effect. |

## Deep Linking

Not applicable: this bridge defines no URL, route, or navigable destination — it dispatches extension-originated tree-provider registration and row-pulling calls into an in-process registration, with no navigation surface of its own.

## Localization

This bridge raises with hardcoded English string literals; none carries a localization key or a lookup into a string catalog. Every raised message reaches the extension as a thrown error, so an extension author sees the literal English text regardless of locale. The log-only messages (the duplicate-registration warning, the dropped-duplicate-handle warning) reach only the host's own log, never the extension.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal only) | `<path>'s first argument must be a view id string.` | Raised by `registerTreeDataProvider` or `createTreeView` when the first argument is missing or not a string. |
| (none — literal only) | `<path>'s second argument must be a TreeViewOptions object.` | Raised by `createTreeView` when the second argument is missing or not an object. |
| (none — literal only) | `<path> requires a TreeDataProvider with getChildren(element) and getTreeItem(element) methods.` | Raised by either member when the provider argument fails **provider-requires-getchildren-and-gettreeitem**. |
| (none — literal only) | `<path> is unavailable: this extension's host has been torn down.` | Raised by either member when the bridge has been disposed. |

## Accessibility Options

Not applicable: this bridge renders nothing and reads no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color) — it has no UI of its own.

## Feature Flags

Not applicable: the source declares no feature-flag key and contains no conditional feature-gating logic; registration and tree-view creation are always available once this bridge is constructed.

## Analytics

Not applicable: this component contains no analytics or event-emission call of any kind. Recording a not-implemented member is diagnostic bookkeeping for a not-yet-built-features report, not an analytics event, and the selection/visibility/expansion/collapse/checkbox-change events are the extension's own subscribed `vscode` events, not telemetry this host emits about itself.

## Privacy

- **Data collected**: this bridge and its registrations collect no data of their own; the element, command, parent, and child-handle tables hold, for the lifetime of each registration, values and identifiers the extension itself supplied (and, indirectly through them, the extension's own script environment and everything its module graph captured). The not-implemented ledger (out of this component's scope) retains the extension identifier and member path of every not-implemented member reached for.
- **Storage**: this bridge performs no storage of its own; every table here is in-memory only and exists for the registration's lifetime.
- **Transmission**: nothing here leaves the process; every call is an in-process round trip between the host and the extension's own script environment, which the same process owns.
- **Retention**: a registration's own values (elements, the provider, the change subscription) are retained until it is invalidated — via a superseding registration (**provider-replacement-ordering**), an explicit `Disposable` call, the tree view object's `dispose` member, or disposing the whole bridge — per **invalidate-is-idempotent-and-releases-the-change-subscription**.

## Logging

Subsystem: the app's own bundle identifier | Category: the bridge and each registration, separately scoped by type name.

| Event | Level | Message |
|-------|-------|---------|
| A provider for a view id has no `getChildren` function to call | error | `<extensionIdentifier>'s provider for view id <viewID> has no getChildren to call` |
| `getChildren`/`getTreeItem` threw, was unavailable, its result could not be settled, its rejection reason, or it answered something that is not an array/TreeItem | error | `<extensionIdentifier>'s tree data provider for view id <viewID> <what>: <detail>` |
| Two children in one `getChildren` answer minted the same handle | error | `getChildren listed two children under one id; the later one is dropped` (logged by the registration) |
| `activate(_:)`'s dispatched command threw | error | `<extensionIdentifier>'s tree row command <commandID> failed: <error.localizedDescription>` |
| A second `registerTreeDataProvider`/`createTreeView` call replaces an existing provider for the same view id | error | `<extensionIdentifier> registered a second tree data provider for view id <viewID>; the later one wins` |

## Platform Notes

- **SwiftUI**: not applicable to this file — `MainThreadTreeViews.swift` imports only `Foundation`, `JavaScriptCore`, `os`, and `AgenticToolkitCore`, with no SwiftUI dependency; nothing in this component renders a view.
- **AppKit / UIKit**: this is the source. `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadTreeViews.swift` is part of the `AgenticToolkitMacOS` framework target, which `project.yml` declares `platform: macOS` only — no iOS target packages this file. It is `@MainActor`-isolated per both class declarations (`main-thread-confinement`), because `JSValue` is not `Sendable` and JavaScriptCore invokes every block here on the thread that made the call. Every provider-supplied model object is held as a `JSValue` inside the extension's own `JSContext`; `ExtensionTreeModel.elements: [String: JSValue]`, `commandsByHandle`, `parentByHandle`, and `childHandles` are the concrete tables behind the element/command/parent/child-handle bookkeeping described above, and a row's command arguments (`command-arguments-are-forwarded-as-jsvalues-unconverted`) are read via `VSCodeAPI.arrayLength(of:)`/`atIndex(_:)` and stored as the `JSValue`s they already are, with no conversion through `toObject()`. Nothing exported back to JavaScript (the `TreeView` object, its event-subscription blocks) stores a `JSValue` of its own, because a `JSValue` retained by an object JavaScriptCore itself holds is a retain cycle through `JSManagedValue.h`; every block the `TreeView` object exposes (the `title`/`message`/`description`/`badge` accessors, the four `install(event:...)` subscriptions, `onDidChangeCheckboxState`, `reveal`, `dispose`) captures `model`/`treeViews` only as `[weak ...]` and stores no `JSValue` of its own. Both `MainThreadTreeViews` and `ExtensionTreeModel` conform to `Loggable`, each exposing its own `nonisolated static let logger` built with `makeLogger()`; the bundle identifier comes from `Bundle.main.bundleIdentifier` (via `Loggable`'s default, falling back to `"nil"`), and the category is each type's own name. Raise-on-teardown (`register-raises-on-torn-down-adaptor`, `create-tree-view-raises-on-torn-down-adaptor`) is built via `VSCodeAPI.member(..., whenTornDown: .raisedException, ...)`. Its one given caller-side collaborator, `ExtensionTreeViewController` (`agentictoolkit://cookbook/workspace/extensions/vscode-api/tree-views/extension-tree-view`), is an `NSOutlineView`-backed macOS controller.
- **Compose**: model `MainThreadTreeViews` as a Kotlin class holding a `MutableMap<String, ExtensionTreeModel>`, confined to the main dispatcher to mirror `@MainActor`. `ExtensionTreeModel`'s `elements`/`commandsByHandle`/`parentByHandle`/`childHandles` become plain `MutableMap`s guarded by that same confinement (no `Mutex` needed, matching the source's own single-actor argument); the four `ExtensionEventEmitter`s become `SharedFlow`s a `TreeView`-equivalent surface collects from, matching how `agentictoolkit://cookbook/workspace/extensions/vscode-api/tree-views/extension-tree-data-source` already models that boundary.
- **React/Web**: this component's own upstream is VS Code's real `MainThreadTreeViews` (`mainThreadTreeViews.ts`), already TypeScript, so a web port is closer to restoring the original than translating it — a class wrapping the same element-handle bookkeeping, with `registerTreeDataProvider` returning a `Disposable`-shaped object and `createTreeView` returning a plain object exposing native `EventEmitter`s instead of this file's hand-built `ExtensionEventEmitter` bridge.
- **WinUI 3**: model `ExtensionTreeModel`'s element table as a class whose every member runs on a captured `DispatcherQueue` (the `@MainActor` equivalent — WinUI 3 has no compiler-enforced actor isolation, so every entry point MUST assert `DispatcherQueue.HasThreadAccess` or marshal via `DispatcherQueue.TryEnqueue`). The extension-side `JSValue` element becomes whatever the chosen JavaScript engine binding uses (ClearScript's `ScriptObject`, or Jint's `JsValue`), and the handle-minting scheme (`#<escaped-id>` versus `<parent>/<index>`) ports unchanged, since it is pure string manipulation with no platform dependency. Drive a `Microsoft.UI.Xaml.Controls.TreeView` from `children(of:)`-equivalent calls exactly as the companion `ExtensionTreeViewController` recipe's WinUI note describes, and fire `ProviderReplaced`/invalidate in the same order as **provider-replacement-ordering** from whatever registry class plays the role of `MainThreadTreeViews`.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadTreeViews.swift` |

## Design Decisions

**Decision**: a row's handle is positional (`<parent>/<index>`) unless the extension declared a `TreeItem.id`, rather than always positional or always requiring a declared id.
**Rationale**: a positional handle is stable for a tree whose shape does not change between refreshes, which is what makes an expanded branch stay expanded across an ordinary refresh with no extra work from the extension. A tree that *reorders* its rows without declaring ids keeps the expansion on the position rather than the row — the exact astonishment upstream's own documentation warns extension authors about — but that cost falls on an extension that chose not to declare ids, not on one that did.
**Approved**: pending

**Decision**: `%` and `/` are escaped out of a declared id (`escapedForHandle`) rather than relying on the `#` prefix alone to separate the declared-id handle space from the positional one.
**Rationale**: a declared handle is a legal string-prefix of a positional one — a row declaring `id: "src"` gives its first unnamed child the handle `#src/0`, which is exactly what a row declaring `id: "src/0"` would be given without escaping. Escaping `/` (and `%` first, so the escape of `/` cannot itself be re-escaped) makes a declared handle contain no `/` at all, which is what makes the two spaces provably disjoint rather than merely unlikely to collide.
**Approved**: pending

**Decision**: a targeted refresh diffs the previous children against the newly reissued ones and forgets only the difference, rather than dropping the whole previous subtree before rebuilding it.
**Rationale**: this bridge's own history documents this as a fix for a real regression: dropping the whole subtree left every grandchild's row on screen with nothing behind it, because a targeted refresh (`onDidChangeTreeData(element)`) only reloads the one branch named, and the pane never re-asks a branch it has already read. Diffing keeps every row the extension did not stop naming answerable, at the cost of walking the previous-children list once per refresh.
**Approved**: pending

**Decision**: `activate(_:)` dispatches a row's command straight through `CommandRegistry.execute(id:arguments:)` rather than back through `vscode.commands.executeCommand`.
**Rationale**: a tree row routinely runs a command another extension, or the app itself, contributed — not necessarily one this extension registered — and the registry is the one place all three meet. Going back through `vscode.commands.executeCommand` would add a round trip through the extension's own runtime for no benefit, since the arguments are already in the right form, exactly what the commands bridge hands the registry itself.
**Approved**: pending

**Decision** (AppKit/UIKit): every block installed on the JS-visible `TreeView` object captures `model` and `treeViews` only weakly and stores no `JSValue` of its own.
**Rationale**: a `JSValue` retained by an object JavaScriptCore itself holds (the `TreeView` object, exported back into the extension's context) is a retain cycle through `JSManagedValue.h`. The sole strong reference to a live `ExtensionTreeModel` is `MainThreadTreeViews.models`; dropping an entry from that dictionary is what makes every weakly-captured block on that model's `TreeView` object go inert at once, mirroring `MainThreadWebviews`'s identical no-capture contract.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [secure-log-output](agenticdevelopercookbook://compliance/security#secure-log-output) | passed | Security |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |

`separation-of-concerns` passes because the file's only responsibilities are the two `vscode.window` members' own argument validation, the element-handle bookkeeping a tree provider needs that no other adaptor in this directory needs, and the `TreeView` object's chrome; everything else is delegated — actual command storage and dispatch to `CommandRegistry` (`AppCommand.swift`), codicon-to-symbol resolution to `CodiconSymbols` (`ContributedViews.swift`), not-implemented bookkeeping to `NotImplementedLedger`, and JavaScript call/promise/disposable/event ceremony to `VSCodeAPI` and `ExtensionEventEmitter`. `unit-test-coverage` is partial: the given `MainThreadTreeViewsTests.swift` suite thoroughly covers handle minting (declared and positional), last-registration-wins with a stale-disposable no-op, targeted-refresh liveness and forgetting, the declared-versus-positional handle-space disjointness, activation with and without a command, chrome forwarding, selection/visibility/expand/collapse events, provider-replacement ordering, teardown, and post-teardown raising — but no test in the given sources isolates the concurrent-same-parent-`children(of:)` race flagged under Edge Cases, or exercises **command-arguments-are-forwarded-as-jsvalues-unconverted** with an argument that is itself an object rather than a primitive. `explicit-error-handling` passes: every failure path this file can produce (bad arguments, an invalid provider, a torn-down adaptor, a provider that throws or whose thenable rejects, a non-array or non-object answer, a thrown command) is either an explicit raise or a logged-and-continued failure, per the corresponding Behavioral Requirements above — nothing is silently discarded. `secure-log-output` passes because no credential or secret value is ever read or logged by this file; the values logged (extension and view identifiers, handles, command ids, an exception's own `toString()`/`localizedDescription`) are diagnostic identifiers and the extension's own error text, not host secrets. `no-hardcoded-strings` fails because every raised message this file constructs directly (see Localization) is an English literal with no localization mechanism.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/extensions/vscode-api/tree-views/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
