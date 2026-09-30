<!-- leaf: implement-extension/tree-view-controller--part-2 · source: extension-tree-view-controller.md -->

# ExtensionTreeViewController — continued (part 2)

**Rules** (cite as `implement-extension/tree-view-controller--part-2#<slug>`):

- `contributed-view-retained` MUST
- `coder-init-unsupported` MUST
- `initial-placeholder-shown` MUST
- `container-background-tracks-theme` MUST
- `resolve-called-in-view-did-load` MUST
- `first-resolve-shows-outline` MUST
- `resolve-after-discard-ignored` MUST
- `duplicate-resolve-ignored` MUST
- `provider-replacement-swaps-source` MUST
- `swap-tears-down-previous-content` MUST
- `swap-pins-new-content-to-edges` MUST
- `swap-notifies-title-change` MUST
- `outer-pane-title-delegates` MUST
- `outer-teardown-marks-discarding` MUST
- `outer-teardown-forwards-to-content` MUST
- `outline-single-column-no-header` MUST
- `outline-row-height` MUST
- `outline-indentation-per-level` MUST
- `outline-inset-style` MUST
- `outline-allows-empty-selection` MUST
- `message-banner-shown-conditionally` MUST
- `message-banner-inset` MUST
- `message-banner-wraps` MUST
- `accessibility-ids-assigned` MUST
- `initial-load-on-view-did-load` MUST
- `callback-ownership-transfers-to-latest-pane` MUST
- `visibility-forwarded-only-by-owner` MUST
- `message-label-wrap-width-tracks-container` MUST
- `multiple-selection-mirrors-source` MUST
- `children-answered-from-cache` MUST
- `uncached-branch-triggers-load-and-empty-answer` MUST
- `load-skipped-while-in-flight` MUST
- `load-marked-stale-when-busy` MUST
- `load-skipped-for-unreachable-handle` MUST
- `disclosure-driven-by-declared-state` MUST
- `load-bounded-by-budget` MUST
- `timeout-logged` MUST
- `timeout-leaves-branch-askable` MUST
- `late-answer-discarded-when-defunct` MUST
- `successful-load-updates-table-and-redraws` MUST
- `duplicate-child-id-deduplicated` MUST
- `moved-row-preserves-identity` MUST
- `orphan-return-by-same-parent-is-new-row` MUST
- `prune-orphans-after-settling` MUST
- `forget-is-cycle-safe` MUST

## Behavioral Requirements

### Construction & the placeholder

- **contributed-view-retained**: The controller MUST retain the `ContributedView` and extension display name given at construction, using them respectively as the placeholder's subject and as `paneTitle`'s fallback until a tree is shown.
- **coder-init-unsupported**: The controller MUST NOT support `NSCoder`-based initialization; invoking `init(coder:)` MUST call `fatalError`.
- **initial-placeholder-shown**: `loadView()` MUST show an `ExtensionViewPlaceholderViewController` for the contributed view before any data source has resolved.
- **container-background-tracks-theme**: The container view's background MUST track the `.surface` semantic theme color.
- **resolve-called-in-view-did-load**: The controller MUST invoke the `resolve` closure from `viewDidLoad()`, not from `loadView()`.

### Swapping to a tree once resolved

- **first-resolve-shows-outline**: The first time `resolve`'s callback delivers a data source, the controller MUST replace the placeholder with an `ExtensionTreeOutlineViewController` bound to that data source.
- **resolve-after-discard-ignored**: A resolve callback delivered after the pane has begun teardown MUST NOT change what is displayed.
- **duplicate-resolve-ignored**: A second invocation of the `resolve` closure's callback, delivered once the outline is already showing, MUST be ignored — regardless of whether it carries the same or a different data source; only `onProviderReplaced` (below) may install a different data source once one is showing.
- **provider-replacement-swaps-source**: When the currently-bound data source's `onProviderReplaced` fires, the controller MUST replace the displayed outline with a new one bound to the replacement data source, and MUST re-hook `onProviderReplaced` on the replacement so a further replacement continues the chain.
- **swap-tears-down-previous-content**: Swapping displayed content MUST call the outgoing child's `PaneContentTeardown.paneContentWillBeDiscarded()` when it implements that protocol, and MUST clear its `onPaneTitleChange`, before removing it from the view hierarchy.
- **swap-pins-new-content-to-edges**: The newly shown child's view MUST be constrained to all four edges of the container.
- **swap-notifies-title-change**: Swapping displayed content MUST invoke the pane's own `onPaneTitleChange` callback once, since `paneTitle` may now answer differently.

### Pane title & teardown (outer controller)

- **outer-pane-title-delegates**: `paneTitle` MUST return the currently-shown child's `paneTitle` when that child implements `PaneTitleProviding`, and MUST return `contributedView.name` otherwise (i.e. while the placeholder is showing).
- **outer-teardown-marks-discarding**: `paneContentWillBeDiscarded()` MUST set an internal flag that suppresses any further reaction to `resolve`.
- **outer-teardown-forwards-to-content**: `paneContentWillBeDiscarded()` MUST forward to the currently-shown child's `PaneContentTeardown.paneContentWillBeDiscarded()` when that child implements it.

### Outline construction & layout

- **outline-single-column-no-header**: The outline MUST be built with exactly one table column and MUST hide its header view.
- **outline-row-height**: The outline's row height MUST be 22pt.
- **outline-indentation-per-level**: The outline's indentation per level MUST be 14pt.
- **outline-inset-style**: The outline MUST use `NSOutlineView.Style.inset`.
- **outline-allows-empty-selection**: The outline MUST allow an empty selection.
- **message-banner-shown-conditionally**: A non-nil `dataSource.message` MUST be shown as a banner above the tree; when `message` is nil, the tree MUST instead be pinned to the container's top edge and the banner MUST be hidden.
- **message-banner-inset**: The message banner MUST be inset 16pt from the container's leading and trailing edges and 8pt from its top edge; the tree MUST sit 8pt below the banner's bottom edge when the banner is shown.
- **message-banner-wraps**: The message banner MUST wrap onto multiple lines with no line-count limit and left alignment.
- **accessibility-ids-assigned**: The outline MUST carry the accessibility identifier `"<accessibilityPrefix>.tree"` and the message label MUST carry `"<accessibilityPrefix>.message"`, where `accessibilityPrefix` is the contributed view's `registryID`.

### Loading lifecycle

- **initial-load-on-view-did-load**: `viewDidLoad()` MUST request the root's children and MUST apply the data source's chrome (`title`/`message`/`allowsMultipleSelection`).
- **callback-ownership-transfers-to-latest-pane**: Installing this pane's callbacks on a data source MUST record this pane as that data source's current callback owner, superseding whichever pane owned them before.
- **visibility-forwarded-only-by-owner**: `viewDidAppear`/`viewDidDisappear` MUST report visibility to the data source only when this pane is still that data source's recorded callback owner; a superseded pane's appearance or disappearance MUST NOT be reported.
- **message-label-wrap-width-tracks-container**: The message label's preferred maximum layout width MUST track the container's width minus 32pt (16pt inset on each side).
- **multiple-selection-mirrors-source**: The outline's `allowsMultipleSelection` MUST mirror `dataSource.allowsMultipleSelection`, re-applied every time chrome is applied.

### Reading children

- **children-answered-from-cache**: A request for an item's children MUST be answered from the cached row table, never by blocking the outline on the data source.
- **uncached-branch-triggers-load-and-empty-answer**: A request for the children of a branch with no cached answer MUST return an empty array immediately and MUST trigger a load of that branch.
- **load-skipped-while-in-flight**: A load already in flight for a handle MUST NOT trigger a second, concurrent ask of the provider for that same handle.
- **load-marked-stale-when-busy**: A load requested for a handle that already has one in flight MUST be remembered and re-issued once the in-flight one completes.
- **load-skipped-for-unreachable-handle**: A load MUST NOT be issued for a non-root handle whose row is not currently reachable in the table (never loaded, orphaned pending settlement, or already forgotten).
- **disclosure-driven-by-declared-state**: Whether a row offers a disclosure triangle MUST be determined solely by `item.collapsibleState.isExpandable`, independent of how many children (if any) a load of that row actually returns.
- **load-bounded-by-budget**: A children load MUST be bounded by `childrenBudget` (default 30 seconds).
- **timeout-logged**: A children load that exceeds `childrenBudget` MUST log an error.
- **timeout-leaves-branch-askable**: A children load that exceeds `childrenBudget` MUST NOT adopt any rows for that branch — the branch stays unread, not recorded as empty — and MUST remain askable by a later expansion, refresh, or the stale re-ask mechanism below.
- **late-answer-discarded-when-defunct**: A children answer that arrives after the pane has begun teardown, or for a non-root handle whose row no longer exists, MUST be discarded without updating the outline.
- **successful-load-updates-table-and-redraws**: A successful children answer MUST replace that branch's rows in the table — reusing the existing row object (and its already-loaded subtree) for every id that was already drawn somewhere, whether under this parent or another — and MUST redraw both that branch and any other branch a moved row was taken from.
- **duplicate-child-id-deduplicated**: When a single children answer contains the same item id more than once, only the first occurrence MUST be kept; the rest MUST be dropped.
- **moved-row-preserves-identity**: When an item dropped by one already-loaded branch is claimed by a different branch before the refresh that dropped it has settled (no loads in flight), the row MUST keep its object identity and its already-loaded subtree, regardless of the order in which the two branches' answers arrive.
- **orphan-return-by-same-parent-is-new-row**: When the same branch that stopped naming an id later names that same id again (in a separate, subsequent refresh), that id MUST be treated as a new row — its previous subtree discarded — rather than as a preserved one.
- **prune-orphans-after-settling**: Once no children loads are in flight, a row dropped during that refresh and never reclaimed by any branch MUST be forgotten, along with everything beneath it; a row still claimed by some branch MUST NOT be forgotten.
- **forget-is-cycle-safe**: Forgetting a handle and its descendants MUST terminate even when the extension's declared ids form a cycle, visiting each handle at most once.

