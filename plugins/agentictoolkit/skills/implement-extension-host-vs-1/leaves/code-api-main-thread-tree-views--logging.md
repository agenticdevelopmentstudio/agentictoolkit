<!-- leaf: implement-extension-host-vs-1/code-api-main-thread-tree-views--logging · source: extension-host-vs-code-api-main-thread-tree-views.md -->

# MainThreadTreeViews

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (via `Loggable`'s default, falling back to `"nil"`) | Category: `MainThreadTreeViews` and `ExtensionTreeModel` (via `Loggable`'s default, derived from each type's own name).

| Event | Level | Message |
|-------|-------|---------|
| A provider for a view id has no `getChildren` function to call | error | `<extensionIdentifier>'s provider for view id <viewID> has no getChildren to call` |
| `getChildren`/`getTreeItem` threw, was unavailable, its result could not be settled, its rejection reason, or it answered something that is not an array/TreeItem | error | `<extensionIdentifier>'s tree data provider for view id <viewID> <what>: <detail>` (via `ExtensionTreeModel.log`) |
| Two children in one `getChildren` answer minted the same handle | error | `getChildren listed two children under one id; the later one is dropped` (via `ExtensionTreeModel.log`) |
| `activate(_:)`'s dispatched command threw | error | `<extensionIdentifier>'s tree row command <commandID> failed: <error.localizedDescription>` |
| A second `registerTreeDataProvider`/`createTreeView` call replaces an existing provider for the same view id | error | `<extensionIdentifier> registered a second tree data provider for view id <viewID>; the later one wins` |
