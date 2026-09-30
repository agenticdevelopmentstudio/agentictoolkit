<!-- leaf: implement-extension-host-vs-1/code-api-main-thread-tree-views--part-2 · source: extension-host-vs-code-api-main-thread-tree-views.md -->

# MainThreadTreeViews — continued (part 2)

**Rules** (cite as `implement-extension-host-vs-1/code-api-main-thread-tree-views--part-2#<slug>`):

- `main-actor-isolation` MUST
- `register-raises-on-torn-down-adaptor` MUST
- `create-tree-view-raises-on-torn-down-adaptor` MUST
- `register-requires-string-view-id` MUST
- `create-tree-view-requires-string-view-id` MUST
- `create-tree-view-requires-options-object` MUST
- `provider-requires-getchildren-and-gettreeitem` MUST
- `last-registration-wins-and-is-logged` MUST
- `provider-replacement-ordering` MUST
- `registration-disposable-is-token-guarded` MUST
- `subscribe-to-changes-is-optional` MUST
- `can-select-many-is-honored` MUST
- `show-collapse-all-is-recorded-not-implemented` MUST
- `drag-and-drop-controller-is-recorded-not-implemented` MUST
- `manage-checkbox-state-manually-is-recorded-not-implemented` MUST
- `children-of-nil-requests-roots` MUST
- `children-empty-when-parent-element-unknown` MUST
- `children-empty-when-getchildren-unusable` MUST
- `children-empty-on-getchildren-throw-or-rejection` MUST
- `children-treats-undefined-null-as-no-children` MUST
- `children-empty-on-non-array-result` MUST
- `children-rechecks-invalidation-after-await` MUST
- `tree-item-duck-typed-not-instanceof` MUST
- `declared-id-becomes-the-handle` MUST
- `handle-escaping-keeps-the-two-spaces-disjoint` MUST
- `duplicate-declared-id-in-one-answer-keeps-the-first` MUST
- `targeted-refresh-keeps-unreissued-descendants-alive` MUST
- `targeted-refresh-forgets-only-genuinely-removed-children` MUST
- `forget-drops-a-handle-and-everything-beneath-it` MUST
- `file-moves-a-relocated-declared-handle` MUST
- `label-fallback-chain` MUST

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
