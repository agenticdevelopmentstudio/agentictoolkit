<!-- leaf: implement-general-controller/tab-pane-view-controller--edge-cases · source: tab-pane-view-controller.md -->

# TabPaneViewController

**Rules** (cite as `implement-general-controller/tab-pane-view-controller--edge-cases#<slug>`):

- `null-empty-input-model-absent` MUST — tabPaneModelName returns nil → the agent label MUST show the agent name alone, with no separator (per …
- `null-empty-input-branch-summary-absent` MUST — tabPaneBranch/tabPaneSummary return nil → the corresponding label MUST be hidden rather than shown empty.
- `null-empty-input-data-source-absent` MUST — dataSource is nil when reload() is called → the component MUST take no action beyond loadViewIfNeeded(), leaving …
- `boundary-values-depth-at-the-recession-ceiling` MUST — stackDepth at 3 (maxStackDepth) or any larger value MUST recede the card by the same amount as depth 3 - recession does …
- `boundary-values-content-far-below-above-the-card-s-natural-size` MUST — Content shorter than minWidth/minHeight MUST still measure at the floor; content wider than maxWidth MUST clamp at the …
- `redundant-state-change` MUST — Setting stackDepth to its own current value MUST be a no-op - no animation starts and applyDepth is not re-run (guard …
- `repeated-reload-with-changing-values` MUST — Calling reload() twice with a data source that has changed its answers between calls MUST update every label, the …
- `view-never-attached-to-a-window` MUST — A depth change on a pane whose view has never been added to a window's view hierarchy MUST apply immediately with no …

## Edge Cases

- **Null/empty input - model absent**: `tabPaneModelName` returns `nil` → the agent label MUST show the agent name alone, with no separator (per `testAModelOfNilShowsOnlyTheAgent`).
- **Null/empty input - branch/summary absent**: `tabPaneBranch`/`tabPaneSummary` return `nil` → the corresponding label MUST be hidden rather than shown empty.
- **Null/empty input - data source absent**: `dataSource` is `nil` when `reload()` is called → the component MUST take no action beyond `loadViewIfNeeded()`, leaving whatever was last displayed unchanged (`guard let dataSource else { return }`). This is the source's only handling of a missing dependency; no error, placeholder, or logged diagnostic is produced.
- **Boundary values - depth at the recession ceiling**: `stackDepth` at `3` (`maxStackDepth`) or any larger value MUST recede the card by the same amount as depth `3` - recession does not keep growing past that ceiling (`recession(atDepth:)` clamps with `min(depth, maxStackDepth)`).
- **Boundary values - content far below/above the card's natural size**: Content shorter than `minWidth`/`minHeight` MUST still measure at the floor; content wider than `maxWidth` MUST clamp at the cap rather than overflow (`testShortContentStillMeasuresTheMinimumWidth`, `testPaneWidthIsCappedAtMaxWidth`).
- **Redundant state change**: Setting `stackDepth` to its own current value MUST be a no-op - no animation starts and `applyDepth` is not re-run (`guard stackDepth != oldValue else { return }`).
- **Concurrent access**: Not applicable in the general sense - every property and method that touches display state is `@MainActor`-isolated, so the AppKit main-thread queue serializes all access; there is no multi-threaded mutation path to defend against.
- **Error states - dependency unavailable**: The only external dependency is `dataSource`; its absence is handled as described above (no-op), not as a surfaced error. There is no network, database, or file-system dependency in this file to fail.
- **Offline/disconnected state**: Not applicable - the component performs no networking of its own; all content arrives synchronously from `dataSource` calls.
- **Repeated `reload()` with changing values**: Calling `reload()` twice with a data source that has changed its answers between calls MUST update every label, the title, and `preferredContentSize` to the new values on the second call, including newly appearing/disappearing branch or summary text (`testReloadTwiceFollowsChangedDataSourceValues`).
- **View never attached to a window**: A depth change on a pane whose view has never been added to a window's view hierarchy MUST apply immediately with no animation, since there is nothing on screen to animate and an animated constraint would read a stale value if measured right after (`animatesDepthChanges`, `testACardOffScreenTakesItsNewDepthImmediately`).
- **Edge-dependent measurement slack (documented quirk, not a guaranteed invariant)**: `contentSize`'s slack term (`2 × deepestRecession`) is edge-dependent - `24` pt on a vertical edge (`3` steps × `4` pt × `2`) versus `8` pt on a horizontal edge (`1` step × `4` pt × `2`) - so, in principle, the same content could measure a different `preferredContentSize` depending solely on which edge hosts the pane. `deepestRecession` reuses `recession(atDepth: maxStackDepth)`, whose body answers a different question for a vertical edge (how far the deepest of several stacked cards recedes) than for a horizontal edge (a constant single-step recession) - the two questions happen to share one implementation. Every existing call site and test happens to mask this: short content is floored to `minWidth`/`minHeight` and long content is capped at `maxWidth`, regardless of which slack value applied (see tab-pane-010), so the difference has never been observed to change a real layout, but the formula itself is not edge-independent when content sits strictly between the floor and the cap.
