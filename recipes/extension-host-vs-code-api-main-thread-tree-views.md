---
id: 8a2a51ce-eee3-4c8b-b6df-90daa35f7ad0
title: MainThreadTreeViews
domain: agentictoolkit://recipes/extension-host-vs-code-api-main-thread-tree-views
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: The extension host's adaptor for vscode.window.registerTreeDataProvider
  and createTreeView — pulling rows from an extension's TreeDataProvider, minting
  a per-row handle for each element, and bridging the TreeView object's chrome,
  selection, and lifecycle events back into JavaScript.
platforms:
- swift
- macos
tags:
- extension-host
- vscode-api
- tree-view
- disposable
- javascriptcore
- mainactor
depends-on: []
related:
- agentictoolkit://recipes/extension-host-vs-code-api-extension-tree-data-source
- agentictoolkit://recipes/extension-host-vs-code-api-main-thread-commands
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

# MainThreadTreeViews

## Overview

`MainThreadTreeViews.swift` (`packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadTreeViews.swift`) installs `vscode.window.registerTreeDataProvider` and `vscode.window.createTreeView`, and builds the `vscode.TreeView` object the second one hands back. It is the one adaptor in this directory whose seam points the other way from its siblings: a webview provider is called once and never again, while a `TreeDataProvider` is asked for rows for as long as its pane is open, so the file's whole substance is the element bookkeeping a webview adaptor has no use for. The public class, `MainThreadTreeViews`, owns the registration table (`models: [String: ExtensionTreeModel]`, one entry per contributed view id this extension currently provides); the private nested class, `ExtensionTreeModel`, is the actual `ExtensionTreeDataSource` conformer per registration and does the element bookkeeping, and is the type `agentictoolkit://recipes/extension-host-vs-code-api-extension-tree-data-source` names as the one production conformer out of its own scope.

The element table is the whole of the bookkeeping. `TreeDataProvider.getChildren`/`getTreeItem` are asked about the provider's own model objects, which live only as `JSValue`s in the extension's `JSContext`; the pane on the other side of the protocol boundary knows nothing but `ContributedTreeItem` values keyed by an opaque `id`. `ExtensionTreeModel.elements: [String: JSValue]` is what lets a later `children(of:)`/`activate(_:)` call turn that opaque id back into the element the extension itself understands, and `commandsByHandle`, `parentByHandle`, and `childHandles` are the same idea applied to a row's declared command and its position in the tree. Every `JSValue` here belongs to `ExtensionTreeModel` alone — nothing exported back to JavaScript (the `TreeView` object, its event-subscription blocks) stores one, because a `JSValue` retained by an object JavaScriptCore itself holds is a retain cycle through `JSManagedValue.h`; every block the `TreeView` object exposes captures `model`/`treeViews` **weakly** instead.

Handles are minted per row and are **positional unless the row declared a `TreeItem.id`**: a declared id becomes `#<escaped-id>` and an undeclared one becomes `<parent-handle>/<index>`. The two handle spaces are kept disjoint by escaping `%` and `/` out of a declared id (never by the `#` prefix, which is not itself sufficient — see Behavioral Requirements), which is what lets a declared handle safely be a string-prefix of a positional one without the two ever colliding. The file's own comments document one bug this shape previously produced and fixed: a targeted refresh (`onDidChangeTreeData(element)`) used to drop a whole subtree from `elements` before rebuilding it, which left rows the pane had already drawn (and their commands) pointing at nothing; the fix diffs the previous children against the newly reissued ones and only forgets the ones that were not reissued, at any depth.

## Behavioral Requirements

- **main-actor-isolation**: both `MainThreadTreeViews` and `ExtensionTreeModel` MUST be declared `@MainActor`; every stored property and method on either MUST execute on the main actor, because `JSValue` is not `Sendable` and JavaScriptCore invokes every block here on the thread that made the call.
- **register-raises-on-torn-down-adaptor**: `registerTreeDataProvider` MUST be built with `VSCodeAPI.member(..., whenTornDown: .raisedException, ...)`, matching `registerTreeDataProvider`'s own synchronous `Disposable` return shape.
- **create-tree-view-raises-on-torn-down-adaptor**: `createTreeView` MUST be built with `VSCodeAPI.member(..., whenTornDown: .raisedException, ...)`, matching `createTreeView`'s own synchronous `TreeView` return shape.
- **register-requires-string-view-id**: `handleRegisterTreeDataProvider` MUST call `VSCodeAPI.raise("\(path)'s first argument must be a view id string.", in: context)` and return `nil` without registering anything when `arguments.first` is missing or is not a JavaScript string.
- **create-tree-view-requires-string-view-id**: `handleCreateTreeView` MUST call `VSCodeAPI.raise("\(path)'s first argument must be a view id string.", in: context)` and return `nil` without registering anything when `arguments.first` is missing or is not a JavaScript string.
- **create-tree-view-requires-options-object**: `handleCreateTreeView` MUST call `VSCodeAPI.raise("\(path)'s second argument must be a TreeViewOptions object.", in: context)` and return `nil` when `arguments.count` is `1` or fewer, or when `arguments[1]` is not a JavaScript object.
- **provider-requires-getchildren-and-gettreeitem**: `validProvider` MUST require the provider argument to be a JavaScript object whose `getChildren` and `getTreeItem` properties both pass `MainThreadTreeViews.isFunction(_:in:)`, and MUST call `VSCodeAPI.raise("\(path) requires a TreeDataProvider with getChildren(element) and getTreeItem(element) methods.", in: context)` and return `nil` when either check fails, for both `registerTreeDataProvider` and `createTreeView`.
- **last-registration-wins-and-is-logged**: `adopt(_:for:)` MUST replace whatever `ExtensionTreeModel` is currently registered for a view id with the new one, and MUST log, at `error` level, that this extension registered a second provider for that view id and the later one wins, whenever a replacement occurs.
- **provider-replacement-ordering**: `adopt(_:for:)` MUST call `replaced.onProviderReplaced?(model)` with the new model, and only after that call MUST call `replaced.invalidate()` on the outgoing model — matching `ExtensionTreeDataSource`'s own **provider-replacement-ordering** requirement.
- **registration-disposable-is-token-guarded**: the `Disposable` `handleRegisterTreeDataProvider` returns MUST call `forget(viewID, token: model.token)`, and `forget(_:token:)` MUST remove the registration from `models` only when `models[viewID]` still exists and its `token` equals the `token` argument; a `Disposable` from a registration that has since been superseded by a later one for the same view id MUST therefore have no effect.
- **subscribe-to-changes-is-optional**: `subscribeToChanges()` MUST do nothing when the provider has no `onDidChangeTreeData` property, or when that property is not a function, treating a provider with no change event as one that simply never refreshes rather than as an error.
- **can-select-many-is-honored**: `readOptions` MUST set `model.allowsMultipleSelection` to `options.canSelectMany`'s boolean value whenever that property is present and is a JavaScript boolean, and MUST leave `allowsMultipleSelection` at its default (`false`) otherwise.
- **show-collapse-all-is-recorded-not-implemented**: `readOptions` MUST call `model.recordNotImplemented("vscode.TreeViewOptions.showCollapseAll")` when `options.showCollapseAll` is present, is a JavaScript boolean, and is `true`; a title-bar "collapse all" button is a capability this pane does not draw.
- **drag-and-drop-controller-is-recorded-not-implemented**: `readOptions` MUST call `model.recordNotImplemented("vscode.TreeViewOptions.dragAndDropController")` when `options.dragAndDropController` is present and is a JavaScript object.
- **manage-checkbox-state-manually-is-recorded-not-implemented**: `readOptions` MUST call `model.recordNotImplemented("vscode.TreeViewOptions.manageCheckboxStateManually")` when `options.manageCheckboxStateManually` is present, is a JavaScript boolean, and is `true`.
- **children-of-nil-requests-roots**: `children(of:)` MUST call the provider's `getChildren` with a JavaScript `undefined` argument when `parent` is `nil`, and MUST call it with the `JSValue` element `parent.id` was minted from when `parent` is non-`nil`.
- **children-empty-when-parent-element-unknown**: `children(of:)` MUST return `[]` without calling `getChildren` at all when `parent` is non-`nil` and `elements[parent.id]` has no entry (the model has forgotten that row, most likely because a refresh replaced its own parent).
- **children-empty-when-getchildren-unusable**: `children(of:)` MUST log the extension identifier and view id and return `[]` when the provider has no `getChildren` property or that property is not a function.
- **children-empty-on-getchildren-throw-or-rejection**: `children(of:)` MUST log and return `[]` when `VSCodeAPI.call(getChildren, ...)` answers `.threw`, `.unavailable`, or when `VSCodeAPI.settlement(of:in:)` on the returned value answers `.rejected` or `.unavailable`.
- **children-treats-undefined-null-as-no-children**: `children(of:)` MUST treat a `getChildren` return value (or its settled thenable value) of JavaScript `undefined` or `null` as "no children," returning `[]` without logging, per `ProviderResult<T[]>`'s own `T[] | undefined | null | Thenable<...>` shape (`vscode.d.ts`).
- **children-empty-on-non-array-result**: `items(from:parentHandle:in:)` MUST log and return `[]` when `VSCodeAPI.arrayLength(of:)` cannot determine a length for the settled result (the provider answered something that is not an array).
- **children-rechecks-invalidation-after-await**: `children(of:)` MUST check `isInvalidated` again immediately after `await VSCodeAPI.settlement(of:in:)` returns, and MUST return `[]` rather than calling `items(from:parentHandle:in:)` when the model was invalidated while that await was in flight.
- **tree-item-duck-typed-not-instanceof**: `treeItem(for:in:)` MUST accept any JavaScript object `getTreeItem` returns (directly or through a settled thenable) as a `TreeItem`, and MUST NOT test it with `instanceof vscode.TreeItem`; it MUST log and return `nil` only when the value is missing, `undefined`, `null`, not an object, or when `getTreeItem` threw, its promise rejected, or the call was unavailable.
- **declared-id-becomes-the-handle**: `handle(forDeclaredID:parent:index:)` MUST return `"#\(escapedForHandle(declaredID))"` when the `TreeItem`'s `id` property is a non-empty JavaScript string, and MUST return `"\(parent)/\(index)"` (the positional handle) otherwise.
- **handle-escaping-keeps-the-two-spaces-disjoint**: `escapedForHandle(_:)` MUST replace every `%` in a declared id with `%25` and then every `/` with `%2F` (in that order, so escaping `%` first cannot re-escape the escapes it just produced from `/`), so that no declared handle ever contains a `/` character and a declared handle can never collide with, or be misread as a prefix boundary of, a positional handle built from `<parent>/<index>`.
- **duplicate-declared-id-in-one-answer-keeps-the-first**: when `getChildren` (or the settled array from its thenable) lists two elements that mint the same handle within one `items(from:parentHandle:in:)` call, that call MUST keep the first one's element and row, MUST log that the later one is dropped, and MUST NOT add a second row for the same handle.
- **targeted-refresh-keeps-unreissued-descendants-alive**: `items(from:parentHandle:in:)` MUST take `parentHandle`'s previously recorded children out of `childHandles` before rebuilding, but MUST leave every grandchild's own `elements`/`commandsByHandle`/`childHandles` entries untouched during the rebuild, so that a child handle reissued during this refresh keeps every row already drawn beneath it live and answerable.
- **targeted-refresh-forgets-only-genuinely-removed-children**: after rebuilding, `items(from:parentHandle:in:)` MUST call `forget(_:)` only on the subset of the previous children that were not reissued in this answer, and MUST NOT forget any handle the answer reissued.
- **forget-drops-a-handle-and-everything-beneath-it**: `forget(_:)` MUST remove each given handle (and, recursively, every handle recorded under it in `childHandles`, at any depth) from `elements`, `commandsByHandle`, `parentByHandle`, and `childHandles`.
- **file-moves-a-relocated-declared-handle**: `file(_:under:)` MUST, when `handle` was previously filed under a different parent, remove it from that former parent's list in `childHandles` before appending it under the new `parent`, so a declared handle an extension moves between branches is never listed under both at once.
- **label-fallback-chain**: `label(of:element:)` MUST use `TreeItem.label` when it is a plain string; otherwise, when `label` is an object with a string `label` property (the structured `TreeItemLabel` form), MUST use that string; otherwise, when `resourceUri` is an object with a non-empty `fsPath` or `path` string, MUST use that path's last path component; otherwise MUST use `element.toString()`; it MUST NOT return an empty string through any of these branches for a value that reached the final fallback.
- **description-true-reads-as-absent**: `ContributedTreeItem.description` MUST be `nil` both when `TreeItem.description` is absent and when it is the JavaScript boolean `true`, since deriving a description from `resourceUri` (upstream's meaning of `true`) has no resource model on this host to derive it from; only a `TreeItem.description` that is itself a string MUST be carried through.
- **tooltip-markdown-string-reads-as-plain-text**: `read(_:element:handle:in:)` MUST read `TreeItem.tooltip` as a plain string when it is one, and otherwise, when it is an object, MUST read its `value` property as a plain string; a `MarkdownString` tooltip's markup is never rendered, only its `value` text.
- **collapsible-state-clamps-unknown-to-none**: `ContributedTreeItem.CollapsibleState.read(_:)` MUST map `1` to `.collapsed` and `2` to `.expanded`, and MUST map every other value (including `nil` and any integer outside `0...2`) to `.none`.
- **icon-path-theme-icon-resolves-via-codicon-symbols**: `symbolName(fromIconPath:)` MUST resolve a `ThemeIcon`-shaped value (an object with a string `id` and no `fsPath` or `path` string) to `CodiconSymbols.symbolName(forCodicon: id)`, and MUST return that call's result unchanged, including `nil` for a codicon `CodiconSymbols` has no SF Symbol for.
- **icon-path-other-cases-record-not-implemented**: `symbolName(fromIconPath:)` MUST call `notImplementedLedger.record(memberPath: "vscode.TreeItem.iconPath", extensionIdentifier:)` and return `nil` for every non-`nil`, non-`undefined` `iconPath` value that is not the `ThemeIcon` shape in **icon-path-theme-icon-resolves-via-codicon-symbols** (a string, a `Uri`/`fsPath`-bearing object, or a `{ light, dark }` object).
- **context-value-records-not-implemented-on-any-value**: `read(_:element:handle:in:)` MUST call `notImplementedLedger.record(memberPath: "vscode.TreeItem.contextValue", extensionIdentifier:)` whenever `TreeItem.contextValue` is a non-`nil` string, since this host contributes no `when`-clause context menus for a tree row to drive.
- **checkbox-state-records-not-implemented-on-any-defined-value**: `read(_:element:handle:in:)` MUST call `notImplementedLedger.record(memberPath: "vscode.TreeItem.checkboxState", extensionIdentifier:)` whenever `TreeItem.checkboxState` is present and is neither `undefined` nor `null`, including the falsy value `0`.
- **command-is-read-and-cleared-on-absence**: `readCommand(_:handle:in:)` MUST store `(id, arguments)` in `commandsByHandle[handle]` and return `id` when `TreeItem.command` is an object with a string `command` property; when it is not (absent, not an object, or missing that property), it MUST call `commandsByHandle.removeValue(forKey: handle)` and return `nil`, so a row whose extension has withdrawn its command cannot go on running the command it declared on a previous refresh under the same handle.
- **command-arguments-are-forwarded-as-jsvalues-unconverted**: `readCommand(_:handle:in:)` MUST read `command.arguments` as a `JSValue` array via `VSCodeAPI.arrayLength(of:)` and `atIndex(_:)`, and MUST store each element as the `JSValue` it already is, with no conversion through `toObject()` or any other bridging.
- **activate-runs-through-the-command-registry-directly**: `activate(_:)` MUST dispatch a row's stored command through `commands.execute(id:arguments:)` (the same `CommandRegistry` `MainThreadCommands.handleExecuteCommand` uses), and MUST NOT go back through `vscode.commands.executeCommand`, because the command may belong to another extension or to the app itself and the registry is where all three meet.
- **activate-is-a-no-op-with-no-stored-command**: `activate(_:)` MUST have no effect, and MUST NOT call `commands.execute`, when `commandsByHandle[item.id]` has no entry (including when the model `isInvalidated`).
- **activate-catches-and-logs-a-thrown-registry-error**: `activate(_:)` MUST catch any error `commands.execute(id:arguments:)` throws, MUST log it at `error` level with the extension identifier and the command id, and MUST NOT propagate it to the caller.
- **change-with-nil-refreshes-the-whole-tree**: `providerDidChangeTreeData(_:)` MUST call `onDidChangeTreeData?(nil)` when its argument is `nil`, JavaScript `undefined`, or JavaScript `null`.
- **change-with-an-array-fires-once-per-resolved-element**: `providerDidChangeTreeData(_:)` MUST, when its argument is a JavaScript array, call `onDidChangeTreeData?(handle)` once for each element that resolves to exactly one known handle via `match(_:)`, in the array's own order.
- **change-with-an-unknown-or-ambiguous-element-refreshes-the-whole-tree**: `providerDidChangeTreeData(_:)` MUST call `onDidChangeTreeData?(nil)` and return, without processing any further elements in the array, as soon as `match(_:)` answers `.none` or `.ambiguous` for any array element or for a single non-array argument.
- **element-match-is-by-javascript-identity-with-ambiguity-detection**: `match(_:)` MUST scan every entry in `elements` and compare with `isEqual(to:)` (JavaScript `===`), MUST answer `.one(handle)` when exactly one entry matches, `.none` when zero match, and MUST answer `.ambiguous` — even though it has already found one match — as soon as a second matching entry is found, since `===` is value equality for a primitive element and the same primitive can legitimately be filed under two handles.
- **selection-reporting-suppresses-unchanged-selections**: `selectionDidChange(to:)` MUST compare the new selection's handles against `selectedHandles` and MUST return without firing `selectionChanges` when they are equal.
- **visibility-reporting-suppresses-unchanged-visibility**: `visibilityDidChange(to:)` MUST compare the new value against `isVisible` and MUST return without firing `visibilityChanges` when they are equal.
- **expand-collapse-always-fire**: `didExpand(_:)` and `didCollapse(_:)` MUST call `expansions.fire(item.id)` and `collapses.fire(item.id)` respectively on every call, with no suppression of a repeated expand or collapse of the same row.
- **checkbox-change-event-is-real-but-never-fired**: `checkboxChanges` MUST be a subscribable `ExtensionEventEmitter<Void>`, and no code path in this file MUST ever call `checkboxChanges.fire`; subscribing to it MUST call `model.recordNotImplemented("vscode.TreeView.onDidChangeCheckboxState")`.
- **title-message-accessors-forward-to-the-model**: the `TreeView` object's `title` and `message` accessors MUST read and write `model.title` and `model.message` unchanged, through weak references to `model`.
- **description-accessor-records-not-implemented-only-on-write**: the `TreeView` object's `description` accessor's getter MUST return `model.viewDescription` unchanged; its setter MUST store the written value into `model.viewDescription` and MUST call `model.recordNotImplemented("vscode.TreeView.description")` on every write, whether or not the pane draws a subtitle anywhere.
- **badge-accessor-ignores-reads-and-records-non-nullish-writes**: the `TreeView` object's `badge` accessor's getter MUST always answer `undefined`/`null` (via `JSValueBridge.undefinedOrNull(in:)`) regardless of any value ever written; its setter MUST call `model.recordNotImplemented("vscode.TreeView.badge")` only when the written value is non-`nil`, not `undefined`, and not `null`.
- **visible-and-selection-are-readonly**: the `TreeView` object MUST expose `visible` and `selection` only as readonly getters (`MainThreadWindow.installReadonlyGetter`), backed by `model.isVisible` and `model.elementArray(for: model.selection, in:)` respectively.
- **event-emitters-are-built-lazily-on-first-subscription**: `selectionChanges`, `visibilityChanges`, `expansions`, `collapses`, and `checkboxChanges` MUST each be a `lazy var`, so an `ExtensionEventEmitter` for an event this extension never subscribes to is never constructed.
- **reveal-always-records-not-implemented-and-resolves**: the `TreeView` object's `reveal` member MUST call `model.recordNotImplemented("vscode.TreeView.reveal")` on every call and MUST return `VSCodeAPI.resolvedPromise(with: nil, in: context)`, regardless of the element or options passed to it; it MUST NOT reject and MUST NOT scroll, select, or expand any row.
- **treeview-object-blocks-capture-model-and-treeviews-weakly**: every block installed on the `TreeView` object (`title`/`message`/`description`/`badge` accessors, the four `install(event:...)` subscriptions, `onDidChangeCheckboxState`, `reveal`, `dispose`) MUST capture `model` and, where applicable, `treeViews`, only as `[weak ...]`, and MUST NOT retain a `JSValue` of its own.
- **treeview-dispose-forgets-through-the-owning-registration**: the `TreeView` object's `dispose` member MUST call `treeViews?.forget(model.viewID, token: model.token)`, subject to the same token guard as **registration-disposable-is-token-guarded**.
- **disposal-invalidates-every-live-model**: `MainThreadTreeViews.dispose()` MUST call `invalidate()` on every model in `models` and MUST leave `models` empty when it returns; it MUST be idempotent, doing nothing on a second call.
- **invalidate-is-idempotent-and-releases-the-change-subscription**: `ExtensionTreeModel.invalidate()` MUST do nothing on any call after its first; on its first call it MUST dispose `changeSubscription` (if present, via its own `dispose` member), set it to `nil`, clear `elements`, `commandsByHandle`, `parentByHandle`, `childHandles`, and `selectedHandles`, remove every listener this model owns from all five event emitters, and set `onDidChangeTreeData` and `onDidChangeChrome` to `nil`; it MUST set `onProviderReplaced` to `nil` only after any pending `onProviderReplaced?(model)` call this invalidation is part of has already fired, per **provider-replacement-ordering**.
- **hastreedataprovider-and-treedatasource-answer-false-nil-when-disposed**: `hasTreeDataProvider(for:)` MUST return `false` and `treeDataSource(for:)` MUST return `nil` whenever `MainThreadTreeViews.isDisposed` is `true`, regardless of whether `models` still holds an entry for the given view id.
- **logging-conformance**: both `MainThreadTreeViews` and `ExtensionTreeModel` MUST conform to `Loggable`, each exposing its own `nonisolated static let logger` built with `makeLogger()`.

`forgetDescendants(of:)` is declared on `ExtensionTreeModel` but is not called anywhere in this file; the targeted-refresh diff in `items(from:parentHandle:in:)` (**targeted-refresh-forgets-only-genuinely-removed-children**) is what actually retires a handle's descendants today. This is a fact about the current source, not a gap — `forget(_:)` (which `forgetDescendants` itself is built on) is what every live code path calls.

## Appearance

Not applicable — this is the extension host's `vscode.window` tree-view adaptor, a logic component with no view of its own; the rows it produces are drawn by whatever `ExtensionTreeDataSource` conformer's caller exists outside this file's scope.

## States

Not applicable — this is a logic component, not a visual one. Its lifecycle-shaped behavior (a registration's live-versus-superseded-versus-invalidated status, and the adaptor's own disposed status) is captured under Behavioral Requirements (**provider-replacement-ordering**, **registration-disposable-is-token-guarded**, **invalidate-is-idempotent-and-releases-the-change-subscription**, **disposal-invalidates-every-live-model**) rather than as a visual-state table.

## Accessibility

Not applicable — this is a logic component with no UI of its own; accessibility of the rows it produces belongs to the pane that draws `ContributedTreeItem` values, out of this file's scope.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| main-thread-tree-views-001 | declared-id-becomes-the-handle | Root elements with declared ids `'fruit'` and `'veg'` | `children(of: nil)` answers rows whose `id`s are exactly `["#fruit", "#veg"]` — `MainThreadTreeViewsTests.aDeclaredTreeItemIDBecomesTheHandle` |
| main-thread-tree-views-002 | declared-id-becomes-the-handle | Two root elements, neither declaring a `TreeItem.id` | `children(of: nil)` answers rows whose `id`s are exactly `["/0", "/1"]` — `MainThreadTreeViewsTests.anItemWithNoIDGetsAPositionalHandle` |
| main-thread-tree-views-003 | last-registration-wins-and-is-logged | A second `registerTreeDataProvider('acme.tree', ...)` call for a view id an earlier provider from the same extension already owns | The pane's rows now come from the second provider only; the error is logged — `MainThreadTreeViewsTests.aSecondRegistrationForTheSameViewIDTakesOver` |
| main-thread-tree-views-004 | registration-disposable-is-token-guarded | The first registration's `Disposable` is called after a second registration has replaced it for the same view id | `hasTreeDataProvider(for:)` remains `true`; the second registration is unaffected — `MainThreadTreeViewsTests.theFirstRegistrationsDisposableCannotRetractTheSecond` |
| main-thread-tree-views-005 | change-with-an-array-fires-once-per-resolved-element | The provider fires `onDidChangeTreeData` with the element already filed under handle `#fruit` | `ExtensionTreeModel.onDidChangeTreeData` is called with `handles == ["#fruit"]` — `MainThreadTreeViewsTests.firingTheChangeEventWithAnElementNamesThatElementsHandle` |
| main-thread-tree-views-006 | change-with-nil-refreshes-the-whole-tree | The provider fires `onDidChangeTreeData` with no argument (JavaScript `undefined`) | `ExtensionTreeModel.onDidChangeTreeData` is called with `handles == [nil]` — `MainThreadTreeViewsTests.firingTheChangeEventWithNothingNamesTheWholeTree` |
| main-thread-tree-views-007 | show-collapse-all-is-recorded-not-implemented, drag-and-drop-controller-is-recorded-not-implemented, manage-checkbox-state-manually-is-recorded-not-implemented, description-accessor-records-not-implemented-only-on-write, reveal-always-records-not-implemented-and-resolves, context-value-records-not-implemented-on-any-value, checkbox-state-records-not-implemented-on-any-defined-value | `createTreeView` with `showCollapseAll: true`, `manageCheckboxStateManually: true`, and a `dragAndDropController`; the returned `TreeView`'s `description` is set and `reveal(1)` is called; the provider's `getTreeItem` sets `contextValue: 'file'` and `checkboxState: 0` | The ledger for this extension contains rows for `vscode.TreeViewOptions.showCollapseAll`, `.manageCheckboxStateManually`, `.dragAndDropController`, `vscode.TreeView.description`, `vscode.TreeView.reveal`, `vscode.TreeItem.contextValue`, and `vscode.TreeItem.checkboxState` — `MainThreadTreeViewsTests.membersThisHostDoesNotDrawRecordALedgerRow` |
| main-thread-tree-views-008 | icon-path-theme-icon-resolves-via-codicon-symbols, icon-path-other-cases-record-not-implemented | One element's `iconPath` is `new vscode.ThemeIcon('github')` (a codicon `CodiconSymbols` has no faithful mapping for); another's is `{ fsPath: '/tmp/icon.png' }` | Both rows' `symbolName` is `nil`; exactly one ledger row is recorded for `vscode.TreeItem.iconPath`, with `count == 1` — `MainThreadTreeViewsTests.aFileIconPathRecordsARowAndAnUnmappableCodiconDoesNot` |
| main-thread-tree-views-009 | disposal-invalidates-every-live-model | `MainThreadTreeViews.dispose()` is called while a provider is registered for `'acme.tree'` | `hasTreeDataProvider(for: "acme.tree")` becomes `false` and `treeDataSource(for: "acme.tree")` becomes `nil` — `MainThreadTreeViewsTests.disposingTheAdaptorRetractsEveryDataSource` |
| main-thread-tree-views-010 | register-raises-on-torn-down-adaptor | `registerTreeDataProvider` is called again, from JavaScript, after `MainThreadTreeViews.dispose()` | The call raises rather than returning a `Disposable` — `MainThreadTreeViewsTests.registeringAfterTeardownThrows` |
| main-thread-tree-views-011 | targeted-refresh-keeps-unreissued-descendants-alive, forget-drops-a-handle-and-everything-beneath-it | A three-level tree (`branch`/`child`/`grandchild`, all declared ids) is fully expanded, then `branch`'s own subtree is targeted-refreshed (its `getChildren` reissues the same `child`) | `grandchild`'s row is still answerable — `children(of: grandchild)` still resolves, and activating `grandchild` still runs its own declared command — `MainThreadTreeViewsTests.refreshingABranchKeepsTheRowsBelowItAlive` |
| main-thread-tree-views-012 | targeted-refresh-forgets-only-genuinely-removed-children, command-is-read-and-cleared-on-absence | A root list of two declared-id rows (`a`, `b`) is read, then the provider is made to answer only `a` on the next `children(of: nil)` | The second `children(of: nil)` answers only `["#a"]`; activating the row previously known as `b` (kept from the first read) no longer runs any command — `MainThreadTreeViewsTests.refreshingABranchForgetsTheRowsItStoppedNaming` |
| main-thread-tree-views-013 | handle-escaping-keeps-the-two-spaces-disjoint | A root declaring `id: 'src'` (collapsible, one unnamed child) alongside a sibling root declaring `id: 'src/0'` | The sibling's handle (`#src%2F0`) and the unnamed child's positional handle (`#src/0`) are different strings; activating the sibling runs its own command, not the unnamed child's — `MainThreadTreeViewsTests.aDeclaredIDCannotCollideWithAPositionalHandle` |

## Edge Cases

- **Null/empty input**: `registerTreeDataProvider()`/`createTreeView()` called with zero arguments MUST fail the string-view-id guard (`arguments.first` is `nil`) and raise the same message as a non-string first argument, per **register-requires-string-view-id**/**create-tree-view-requires-string-view-id** (MUST).
- **Null/empty input**: a provider's `getChildren` answering `undefined` or `null` (directly, or as the settled value of a returned thenable) MUST be read as "no children," not as a failure, per **children-treats-undefined-null-as-no-children** (MUST).
- **Boundary values**: a view id equal to the empty string is a valid `String` and reaches `adopt(_:for:)` exactly as any other id would; nothing in this file rejects it, since **register-requires-string-view-id**/**create-tree-view-requires-string-view-id** check only that the value is a string (fact).
- **Boundary values**: a `TreeItem.collapsibleState` outside `0...2` (or absent) is clamped to `.none` rather than rejected, per **collapsible-state-clamps-unknown-to-none** (MUST).
- **Concurrent access**: both classes are `@MainActor`-isolated with no additional locking; every stored property on `MainThreadTreeViews` and `ExtensionTreeModel` is read and mutated only on the main actor, so there is no data race to define behavior for at the Swift level (fact).
- **Concurrent access**: NEEDS REVIEW: Not implemented in source. Behavior undefined. Two `children(of:)` calls issued for the **same** `parent` before the first one's `await` on `VSCodeAPI.settlement(of:in:)` returns MUST NOT be assumed to leave `childHandles`/`elements` in any particular state relative to each other — each call independently removes `childHandles[parentHandle]` before its own `await`, so the second call to reach that line sees an already-emptied entry rather than the first call's in-flight previous-children snapshot.
- **Error states**: a provider's `getChildren` or `getTreeItem` throwing, or its returned thenable rejecting, MUST be logged and MUST answer `children(of:)` with `[]`; neither exception nor rejection reason is ever surfaced to the pane, per **children-empty-on-getchildren-throw-or-rejection** and **tree-item-duck-typed-not-instanceof** (MUST).
- **Error states**: `activate(_:)`'s underlying `commands.execute(id:arguments:)` throwing MUST be caught, logged, and swallowed; it MUST NOT propagate to the pane that called `activate(_:)`, per **activate-catches-and-logs-a-thrown-registry-error** (MUST).
- **Cancellation or timeout**: not applicable to any member here — `VSCodeAPI.settlement(of:in:)` (out of this file's scope) has no timeout of its own, and this file imposes none; a `getChildren`/`getTreeItem` thenable that never settles leaves the corresponding `children(of:)` call suspended indefinitely (fact, inherited from `VSCodeAPI.settlement`).
- **Missing or unreachable resource**: a `children(of:)` call for a `parent` whose handle this model has already forgotten (a branch expanded across a refresh that replaced its parent) MUST answer `[]` without calling `getChildren`, per **children-empty-when-parent-element-unknown** (MUST).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `notImplementedLedger` | `NotImplementedLedger` | none (required) | Shared record of unimplemented `vscode` members this extension reached for; passed to every `ExtensionTreeModel` this adaptor creates. |
| `extensionIdentifier` | `String` | none (required) | The extension this adaptor instance belongs to; attributed on every ledger row and every log line. |
| `commands` | `CommandRegistry` | none (required) | The registry `activate(_:)` dispatches a row's declared command through. |
| `TreeViewOptions.canSelectMany` | `Bool` | `false` | Read by `readOptions`; sets `ExtensionTreeModel.allowsMultipleSelection`. |
| `TreeViewOptions.showCollapseAll` | `Bool` | `false` | Read by `readOptions`; `true` records a not-implemented ledger row and has no other effect. |
| `TreeViewOptions.dragAndDropController` | object | absent | Read by `readOptions`; presence records a not-implemented ledger row and has no other effect. |
| `TreeViewOptions.manageCheckboxStateManually` | `Bool` | `false` | Read by `readOptions`; `true` records a not-implemented ledger row and has no other effect. |

## Deep Linking

Not applicable: `MainThreadTreeViews.swift` defines no URL, route, or navigable destination — it dispatches JavaScript-originated tree-provider registration and row-pulling calls into an in-process model, with no navigation surface of its own.

## Localization

`MainThreadTreeViews` raises with hardcoded English string literals; none carries a localization key, `String(localized:)` call, or String Catalog entry. Every raised message reaches the extension as a thrown JavaScript error, so an extension author sees the literal English text regardless of locale. The log-only messages (`ExtensionTreeModel.log`, the duplicate-registration warning, the dropped-duplicate-handle warning) reach only the host's own log, never the extension.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal only) | `<path>'s first argument must be a view id string.` | Raised by `registerTreeDataProvider` or `createTreeView` when the first argument is missing or not a string. |
| (none — literal only) | `<path>'s second argument must be a TreeViewOptions object.` | Raised by `createTreeView` when the second argument is missing or not an object. |
| (none — literal only) | `<path> requires a TreeDataProvider with getChildren(element) and getTreeItem(element) methods.` | Raised by either member when the provider argument fails **provider-requires-getchildren-and-gettreeitem**. |
| (none — literal only) | `<path> is unavailable: this extension's host has been torn down.` | Raised by either member when `isDisposed` is `true`. |

## Accessibility Options

Not applicable: `MainThreadTreeViews.swift` renders nothing and reads no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color) — it has no UI of its own.

## Feature Flags

Not applicable: the source declares no feature-flag key and contains no conditional feature-gating logic; `registerTreeDataProvider` and `createTreeView` are always available once a `MainThreadTreeViews` is constructed.

## Analytics

Not applicable: the source contains no analytics or event-emission call of any kind. `NotImplementedLedger.record` is diagnostic bookkeeping for a not-yet-built-features report, not an analytics event, and `selectionChanges`/`visibilityChanges`/`expansions`/`collapses`/`checkboxChanges` are the extension's own subscribed `vscode` events, not telemetry this host emits about itself.

## Privacy

- **Data collected**: `MainThreadTreeViews`/`ExtensionTreeModel` collect no data of their own; `elements`, `commandsByHandle`, `parentByHandle`, and `childHandles` hold, for the lifetime of each registration, `JSValue`s and identifiers the extension itself supplied (and, indirectly through them, the `JSContext` and everything the extension's module graph captured). `NotImplementedLedger` (out of this file's scope) retains the extension identifier and member path of every not-implemented member reached for.
- **Storage**: `MainThreadTreeViews`/`ExtensionTreeModel` perform no storage of their own; every table here is in-memory only and exists for the registration's lifetime.
- **Transmission**: nothing here leaves the process; every call is an in-process JavaScriptCore round trip between the host and a `JSContext` the same process owns.
- **Retention**: a registration's `JSValue`s (elements, the provider, the change subscription) are retained until `invalidate()` runs — via a superseding registration (**provider-replacement-ordering**), an explicit `Disposable` call, the `TreeView` object's `dispose` member, or `MainThreadTreeViews.dispose()` — per **invalidate-is-idempotent-and-releases-the-change-subscription**.

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (via `Loggable`'s default, falling back to `"nil"`) | Category: `MainThreadTreeViews` and `ExtensionTreeModel` (via `Loggable`'s default, derived from each type's own name).

| Event | Level | Message |
|-------|-------|---------|
| A provider for a view id has no `getChildren` function to call | error | `<extensionIdentifier>'s provider for view id <viewID> has no getChildren to call` |
| `getChildren`/`getTreeItem` threw, was unavailable, its result could not be settled, its rejection reason, or it answered something that is not an array/TreeItem | error | `<extensionIdentifier>'s tree data provider for view id <viewID> <what>: <detail>` (via `ExtensionTreeModel.log`) |
| Two children in one `getChildren` answer minted the same handle | error | `getChildren listed two children under one id; the later one is dropped` (via `ExtensionTreeModel.log`) |
| `activate(_:)`'s dispatched command threw | error | `<extensionIdentifier>'s tree row command <commandID> failed: <error.localizedDescription>` |
| A second `registerTreeDataProvider`/`createTreeView` call replaces an existing provider for the same view id | error | `<extensionIdentifier> registered a second tree data provider for view id <viewID>; the later one wins` |

## Platform Notes

- **SwiftUI**: not applicable to this file — `MainThreadTreeViews.swift` imports only `Foundation`, `JavaScriptCore`, `os`, and `AgenticToolkitCore`, with no SwiftUI dependency; nothing in this component renders a view.
- **AppKit / UIKit**: this is the source. `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadTreeViews.swift` is part of the `AgenticToolkitMacOS` framework target, which `project.yml` declares `platform: macOS` only — no iOS target packages this file. It is `@MainActor`-isolated per both class declarations, and its one given caller-side collaborator, `ExtensionTreeViewController` (`agentictoolkit://recipes/extension-tree-view-controller`), is an `NSOutlineView`-backed macOS controller.
- **Compose**: model `MainThreadTreeViews` as a Kotlin class holding a `MutableMap<String, ExtensionTreeModel>`, confined to the main dispatcher to mirror `@MainActor`. `ExtensionTreeModel`'s `elements`/`commandsByHandle`/`parentByHandle`/`childHandles` become plain `MutableMap`s guarded by that same confinement (no `Mutex` needed, matching the source's own single-actor argument); the four `ExtensionEventEmitter`s become `SharedFlow`s a `TreeView`-equivalent surface collects from, matching how `agentictoolkit://recipes/extension-host-vs-code-api-extension-tree-data-source` already models that boundary.
- **React/Web**: this component's own upstream is VS Code's real `MainThreadTreeViews` (`mainThreadTreeViews.ts`), already TypeScript, so a web port is closer to restoring the original than translating it — a class wrapping the same element-handle bookkeeping, with `registerTreeDataProvider` returning a `Disposable`-shaped object and `createTreeView` returning a plain object exposing native `EventEmitter`s instead of this file's hand-built `ExtensionEventEmitter` bridge.
- **WinUI 3**: model `ExtensionTreeModel`'s element table as a class whose every member runs on a captured `DispatcherQueue` (the `@MainActor` equivalent — WinUI 3 has no compiler-enforced actor isolation, so every entry point MUST assert `DispatcherQueue.HasThreadAccess` or marshal via `DispatcherQueue.TryEnqueue`). The extension-side `JSValue` element becomes whatever the chosen JavaScript engine binding uses (ClearScript's `ScriptObject`, or Jint's `JsValue`), and the handle-minting scheme (`#<escaped-id>` versus `<parent>/<index>`) ports unchanged, since it is pure string manipulation with no platform dependency. Drive a `Microsoft.UI.Xaml.Controls.TreeView` from `children(of:)`-equivalent calls exactly as the companion `ExtensionTreeViewController` recipe's WinUI note describes, and fire `ProviderReplaced`/invalidate in the same order as **provider-replacement-ordering** from whatever registry class plays the role of `MainThreadTreeViews`.

## Design Decisions

**Decision**: a row's handle is positional (`<parent>/<index>`) unless the extension declared a `TreeItem.id`, rather than always positional or always requiring a declared id.
**Rationale**: a positional handle is stable for a tree whose shape does not change between refreshes, which is what makes an expanded branch stay expanded across an ordinary refresh with no extra work from the extension. A tree that *reorders* its rows without declaring ids keeps the expansion on the position rather than the row — the exact astonishment upstream's own documentation warns extension authors about — but that cost falls on an extension that chose not to declare ids, not on one that did.
**Approved**: pending

**Decision**: `%` and `/` are escaped out of a declared id (`escapedForHandle`) rather than relying on the `#` prefix alone to separate the declared-id handle space from the positional one.
**Rationale**: a declared handle is a legal string-prefix of a positional one — a row declaring `id: "src"` gives its first unnamed child the handle `#src/0`, which is exactly what a row declaring `id: "src/0"` would be given without escaping. Escaping `/` (and `%` first, so the escape of `/` cannot itself be re-escaped) makes a declared handle contain no `/` at all, which is what makes the two spaces provably disjoint rather than merely unlikely to collide.
**Approved**: pending

**Decision**: a targeted refresh diffs the previous children against the newly reissued ones and forgets only the difference, rather than dropping the whole previous subtree before rebuilding it.
**Rationale**: the file's own comments document this as a fix for a real regression: dropping the whole subtree left every grandchild's row on screen with nothing behind it, because a targeted refresh (`onDidChangeTreeData(element)`) only reloads the one branch named, and the pane never re-asks a branch it has already read. Diffing keeps every row the extension did not stop naming answerable, at the cost of walking the previous-children list once per refresh.
**Approved**: pending

**Decision**: `activate(_:)` dispatches a row's command straight through `CommandRegistry.execute(id:arguments:)` rather than back through `vscode.commands.executeCommand`.
**Rationale**: a tree row routinely runs a command another extension, or the app itself, contributed — not necessarily one this extension registered — and the registry is the one place all three meet. Going back through `vscode.commands.executeCommand` would add a JavaScript round trip for no benefit, since the arguments are already `JSValue`s in the right context, exactly what `MainThreadCommands.handleExecuteCommand` hands the registry itself.
**Approved**: pending

**Decision**: every block installed on the JS-visible `TreeView` object captures `model` and `treeViews` only weakly and stores no `JSValue` of its own.
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
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
