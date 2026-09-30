<!-- leaf: implement-extension/tree-view-controller--test-vectors-part-2 · source: extension-tree-view-controller.md -->

# ExtensionTreeViewController — Conformance Test Vectors (part 2)

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| etvc-001 | contributed-view-retained | Construct the pane with a `ContributedView` named "Files" and display name "Acme" | The placeholder shows "Files"/"Acme"; `paneTitle` before any resolve is "Files" |
| etvc-002 | coder-init-unsupported | Call `init(coder:)` | Calls `fatalError` (process traps rather than returning) |
| etvc-003 | initial-placeholder-shown | Load the pane's view before `resolve`'s callback has fired | Displayed content is `ExtensionViewPlaceholderViewController` |
| etvc-004 | container-background-tracks-theme | Switch the active theme after the pane loads | The container's layer background color updates to the new theme's `.surface` color |
| etvc-005 | resolve-called-in-view-did-load | Instrument `loadView()` and `viewDidLoad()` | `resolve` is invoked only after `loadView()` has returned |
| etvc-006 | first-resolve-shows-outline | Call `resolve`'s `didResolve` with a data source | Displayed content becomes an `ExtensionTreeOutlineViewController` bound to that data source |
| etvc-007 | resolve-after-discard-ignored, outer-teardown-marks-discarding | Call `paneContentWillBeDiscarded()`, then invoke `didResolve` | Displayed content is unchanged; no outline is created — the discard flag `paneContentWillBeDiscarded()` sets is what suppresses it |
| etvc-008 | duplicate-resolve-ignored | Invoke `didResolve` twice with two different data sources, back to back | Only the first data source's outline is shown; the second call has no effect |
| etvc-009 | provider-replacement-swaps-source | With an outline shown for source A, fire `A.onProviderReplaced(B)` | Displayed content becomes a new outline bound to `B`; `B.onProviderReplaced` is non-nil afterward |
| etvc-010 | swap-tears-down-previous-content | Swap from a placeholder implementing `PaneContentTeardown` to an outline | `paneContentWillBeDiscarded()` is called on the placeholder before it is removed from the view hierarchy |
| etvc-011 | swap-pins-new-content-to-edges | Swap in a new child | The child's view has four active constraints pinning it to the container's leading/trailing/top/bottom |
| etvc-012 | swap-notifies-title-change | Swap in a new child while `onPaneTitleChange` is set | The callback fires exactly once as part of the swap |
| etvc-013 | outer-pane-title-delegates | Read `paneTitle` while the placeholder is shown, then again once the outline (title "Explorer") is shown | First read is `contributedView.name`; second read is "Explorer" |
| etvc-015 | outer-teardown-forwards-to-content | Content is an outline implementing `PaneContentTeardown`; call `paneContentWillBeDiscarded()` on the outer controller | The outline's own `paneContentWillBeDiscarded()` runs |
| etvc-016 | outline-single-column-no-header | Load the outline's view | `outline.tableColumns.count == 1`; `outline.headerView` is nil |
| etvc-017 | outline-row-height | Read `outline.rowHeight` | Equals 22 |
| etvc-018 | outline-indentation-per-level | Read `outline.indentationPerLevel` | Equals 14 |
| etvc-019 | outline-inset-style | Read `outline.style` | Equals `.inset` |
| etvc-020 | outline-allows-empty-selection | Read `outline.allowsEmptySelection` | `true` |
| etvc-021 | message-banner-shown-conditionally | Set `dataSource.message` to "No results", then to `nil` | Banner visible and tree offset below it in the first case; banner hidden and tree flush to the top in the second |
| etvc-022 | message-banner-inset | Banner shown | Its leading/trailing constraints use a 16pt constant; its top constraint uses 8pt; the tree's top constraint (`treeBelowMessage`) uses 8pt from the banner's bottom |
| etvc-023 | message-banner-wraps | Set `dataSource.message` to a string longer than the pane's width | The label renders on multiple lines rather than truncating to one |
| etvc-024 | accessibility-ids-assigned | `contributedView.registryID == "acme.files"` | `outline.accessibilityIdentifier() == "acme.files.tree"`; `messageLabel.accessibilityIdentifier() == "acme.files.message"` |
| etvc-025 | initial-load-on-view-did-load | Load the outline's view with a data source whose `message` is "Loading…" | A root children ask is issued; the banner shows "Loading…" immediately |
| etvc-026 | callback-ownership-transfers-to-latest-pane | Build a second outline for the same data source | The data source's `onDidChangeTreeData`/`onDidChangeChrome` now point at the second outline's handlers |
| etvc-027 | visibility-forwarded-only-by-owner | Pane B has superseded pane A per etvc-026; call `viewDidAppear()` on pane A | `dataSource.visibilityDidChange` is NOT called by pane A |
| etvc-028 | message-label-wrap-width-tracks-container | Resize the container to 250pt wide | `messageLabel.preferredMaxLayoutWidth == 218` (250 − 32) |
| etvc-029 | multiple-selection-mirrors-source | `dataSource.allowsMultipleSelection == true`; call `applyChrome()` | `outline.allowsMultipleSelection == true` |
| etvc-030 | children-answered-from-cache | Ask for the children of an item whose branch is already cached | Returns the cached rows synchronously; no new ask is issued |
| etvc-031 | uncached-branch-triggers-load-and-empty-answer | Ask for the children of a branch never asked before | Returns `[]` immediately; a load for that handle begins |
| etvc-032 | load-skipped-while-in-flight | Ask for the same branch's children twice before the first ask's provider call returns | Exactly one call reaches `dataSource.children(of:)` |
| etvc-033 | load-marked-stale-when-busy | While a load for handle H is in flight, trigger a tree-data change for H | Once the in-flight load completes and adopts, a second load for H is issued automatically |
| etvc-034 | load-skipped-for-unreachable-handle | Request a load for a handle whose row was already forgotten | No call reaches `dataSource.children(of:)` |
| etvc-035 | disclosure-driven-by-declared-state | Item has `collapsibleState == .collapsed` and its load answers zero children | `isItemExpandable` still reports `true` for that row |
| etvc-036 | load-bounded-by-budget | Set `childrenBudget` to a short, injected value; provider never answers | No rows are adopted for that branch (see etvc-038's later, successful ask); the ask does not wait indefinitely |
| etvc-037 | timeout-logged | Trigger a timeout as in etvc-036 | An error is logged: "A tree provider did not answer getChildren in time; the branch stays unread" |
| etvc-038 | timeout-leaves-branch-askable | After a timeout on handle H, request H's children again | A fresh load for H is issued and can succeed |
| etvc-039 | late-answer-discarded-when-defunct | Call `paneContentWillBeDiscarded()` while a load is in flight, then let the provider answer | The answer is not adopted; the outline is not reloaded |
| etvc-040 | successful-load-updates-table-and-redraws | Handle H moves from parent P1 (already drawn) to parent P2 in a refresh | Both P1 and P2's branches redraw; H's row object is the same instance as before |
| etvc-041 | duplicate-child-id-deduplicated | A `getChildren` answer for parent P lists id "x" twice | P's children contain exactly one row for "x" |
| etvc-042 | moved-row-preserves-identity | P2's answer (claiming H) arrives before P1's answer (which no longer lists H), within the same settling refresh | H keeps the same row object and its loaded subtree under P2 |
| etvc-043 | orphan-return-by-same-parent-is-new-row | Parent P drops id "x" in refresh 1, then names "x" again in a later, separate refresh 2 | "x" is a new row in refresh 2; any subtree it had before refresh 1 is gone, and its default expansion (if `.expanded`) is re-applied |
| etvc-044 | prune-orphans-after-settling | Parent P drops id "x" and nothing claims it; wait for all in-flight loads to finish | Row "x" and its descendants are forgotten from the table |
| etvc-045 | forget-is-cycle-safe | An extension declares item "a" as its own descendant (a cycle) and it is later forgotten | Forgetting completes without hanging or crashing |
| etvc-046 | redraw-preserves-selection | Row H is selected; a redraw of H's parent branch runs and H is still present afterward | H remains selected after the redraw |
| etvc-047 | redraw-narrowing-selection-notifies-source | Rows H1 and H2 are selected; a redraw drops H2 | `dataSource.selectionDidChange` is called with only H1's item |
| etvc-048 | redraw-suppresses-source-notifications | Trigger `reloadItem`/`reloadData` as part of a redraw | `dataSource.selectionDidChange`/`didExpand`/`didCollapse` are not called for the notifications the reload itself generates |
| etvc-049 | default-expansion-applied-once | Row H has `collapsibleState == .expanded`; it is drawn, the user collapses it, then a refresh redraws it again | H auto-expands the first time only; it stays collapsed after the user's action and the later refresh |
| etvc-050 | expansion-request-triggers-load | User expands a row whose children were never loaded | A load for that row's handle begins |
| etvc-051 | expand-collapse-reported-to-source | User expands a row (not via auto-expand or redraw sync) | `dataSource.didExpand(_:)` is called with that row's item |
