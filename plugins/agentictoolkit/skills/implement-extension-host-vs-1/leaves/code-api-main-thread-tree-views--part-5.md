<!-- leaf: implement-extension-host-vs-1/code-api-main-thread-tree-views--part-5 · source: extension-host-vs-code-api-main-thread-tree-views.md -->

# MainThreadTreeViews — continued (part 5)

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
