<!-- leaf: implement-extension/tree-view-controller--part-5 · source: extension-tree-view-controller.md -->

# ExtensionTreeViewController — continued (part 5)

## Design Decisions

**Decision**: `resolve` is invoked from `viewDidLoad()` rather than `loadView()`.
**Rationale**: An already-awake extension answers synchronously; swapping displayed content while `view` is still being assigned inside `loadView()` would have the view controller ask for its own view before it exists.
**Approved**: pending

**Decision**: A branch's children are always answered from a cache, never by blocking the outline on the provider, and a `getChildren` ask is bounded by a 30-second wall-clock budget whose expiry leaves the branch unread rather than adopted as empty.
**Rationale**: `TreeDataProvider.getChildren` is documented as commonly asynchronous, and `NSOutlineView`'s data source protocol has no way to await an answer. An unbounded wait would make a provider that never answers leave the branch not just slow but permanently unaskable — the budget stops the wait without recording a wrong (empty) answer in its place.
**Approved**: pending

**Decision**: Installing this pane's callbacks on a data source supersedes whichever pane held them before ("one pane per view id"), and a superseded pane's teardown only clears wiring it can prove it still owns (`callbackOwners`/`callbackToken`).
**Rationale**: A data source has exactly one `onDidChangeTreeData`/`onDidChangeChrome` slot; a second pane for the same contributed view (e.g. a second window) must take live updates over, and the older, now-inert pane's later teardown must not silently disable the newer, visible one. Closures can't be compared for identity, so ownership is tracked explicitly instead.
**Approved**: pending

**Decision**: A row dropped by its parent during a refresh is held as an orphan rather than forgotten immediately, and is only forgotten once every in-flight load for that refresh has settled.
**Rationale**: Refresh answers can arrive in any order; an item that genuinely moved from one open branch to another would otherwise be destroyed by whichever branch's answer happens to drop it first, discarding its whole loaded subtree and collapsing it when the claiming branch's answer arrives moments later. Deferring the forget makes both arrival orders produce the same result.
**Approved**: pending

**Decision**: A row's disclosure triangle is driven solely by the extension's declared `collapsibleState`, never by whether a load has actually found any children.
**Rationale**: This mirrors the source's own upstream contract (`TreeItemCollapsibleState`) rather than inferring expandability from data, which means an item declared `.expanded`/`.collapsed` that turns out to have zero real children still shows a disclosure triangle opening onto an empty list — documented here as a known consequence of following the declared contract, not smoothed into "expandable only when non-empty."
**Approved**: pending

**Decision**: Rows and their background views are drawn through recycled, pooled view instances rather than a fresh view hierarchy per row.
**Rationale**: The source's own comment notes this is what every other outline/table in the framework already does; a tree is the shape where skipping it costs the most, since a branch with a few hundred children previously rebuilt a few hundred view hierarchies on every scroll pass.
**Approved**: pending
