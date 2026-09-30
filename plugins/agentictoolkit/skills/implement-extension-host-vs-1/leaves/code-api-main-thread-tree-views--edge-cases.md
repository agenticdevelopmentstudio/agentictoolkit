<!-- leaf: implement-extension-host-vs-1/code-api-main-thread-tree-views--edge-cases · source: extension-host-vs-code-api-main-thread-tree-views.md -->

# MainThreadTreeViews

**Rules** (cite as `implement-extension-host-vs-1/code-api-main-thread-tree-views--edge-cases#<slug>`):

- `null-empty-input` MUST — registerTreeDataProvider()/createTreeView() called with zero arguments MUST fail the string-view-id guard …
- `null-empty-input-2` MUST — a provider's getChildren answering undefined or null (directly, or as the settled value of a returned thenable) MUST be …
- `boundary-values` MUST — a TreeItem.collapsibleState outside 0...2 (or absent) is clamped to .none rather than rejected, per …
- `concurrent-access` MUST — NEEDS REVIEW: Not implemented in source. Behavior undefined. Two children(of:) calls issued for the same parent before …
- `error-states` MUST — a provider's getChildren or getTreeItem throwing, or its returned thenable rejecting, MUST be logged and MUST answer …
- `error-states-2` MUST — activate(_:)'s underlying commands.execute(id:arguments:) throwing MUST be caught, logged, and swallowed; it MUST NOT …
- `missing-or-unreachable-resource` MUST — a children(of:) call for a parent whose handle this model has already forgotten (a branch expanded across a refresh …

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
