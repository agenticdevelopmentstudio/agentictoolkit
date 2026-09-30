<!-- leaf: implement-composable-tabs/view-controller--edge-cases · source: composable-tabs-view-controller.md -->

# ComposableTabsViewController

**Rules** (cite as `implement-composable-tabs/view-controller--edge-cases#<slug>`):

- `null-empty-input-layoutchildren-legitimately-empty-degenerate` MUST — Null/empty input (MUST): layoutChildren MAY legitimately be empty (a degenerate node mid-teardown); snapshotNode() then …
- `boundary-values-array-taking-initializer-asserts` MUST — Boundary values (MUST): The array-taking initializer asserts a hard upper bound of 2 children …
- `minimize-mutually-exclusive-panedidrequestzoom-restores-minimized-pane` MUST — Zoom and minimize are mutually exclusive (MUST): paneDidRequestZoom(_:) restores a minimized pane before zooming it, …
- `pane-nowhere-send-spec-vetoes-removing-tab` MUST — Refusing the tab's last pane with nowhere to send it (MUST): if the spec vetoes removing a tab's only pane and no …
- `idempotent-persistence-persistthicknessesifchanged-compares-rounded-thickness` MUST — Idempotent persistence (MUST): persistThicknessesIfChanged() compares a rounded thickness signature against the last …
- `leaves-tree-untouched-move-computes-candidate-tree` MUST — A move the spec disallows leaves the tree untouched (MUST): move(_:_:) computes the candidate tree before deciding, and …
- `than-were-live-previously-live-leaf-whose` MUST — Rebuilding onto a shape with fewer leaves than were live (MUST): every previously-live leaf whose id does not survive …

## Edge Cases

- Null/empty input (MUST): `layoutChildren` MAY legitimately be empty (a
  degenerate node mid-teardown); `snapshotNode()` then returns a placeholder
  leaf rather than trapping (see `snapshot-empty-tree-is-placeholder`). Every
  child's `thicknessFraction` is `Optional<CGFloat>`, and `nil` (never sized)
  is handled throughout by falling back to the descriptor's
  `preferredThicknessFraction` or to an even split.
- Boundary values (MUST): The array-taking initializer asserts a hard upper
  bound of 2 children (`binary-or-solo-children`); the preferred-thickness
  loop over dividers (`0..<max(splitViewItems.count - 1, 0)`) degenerates to
  zero iterations for 0 or 1 children, so a solo-child split never attempts to
  place a divider that does not exist.
- Concurrent access: Not applicable — the type is declared `@MainActor`, and
  every mutating operation (`split`, `remove`, `rebuild`, `move`,
  `captureThicknessFractions`, the persistence debounce) reads and writes
  `layoutChildren` and its own stored properties only on the main actor;
  source provides no path for two threads to mutate one instance
  simultaneously.
- Error states: see the named requirements **split-no-ops-without-project**
  (`project` is a `weak var`, and a deallocated project makes
  `split(_:adding:direction:)` return immediately with no mutation) and
  **move-permitted-without-spec** (a resolved project with no layout spec
  configured permits a move rather than refusing it). `layoutParent` is
  `weak`; `rootSplit()`'s upward walk simply stops if that chain is broken,
  rather than throwing.
- Offline/disconnected: Not applicable — this component performs no
  networking; persistence is delegated entirely to the `onLayoutDidChange`
  callback the host installs, and durability of whatever that callback does
  with the snapshot is outside this file's source.
- Zoom and minimize are mutually exclusive (MUST): `paneDidRequestZoom(_:)`
  restores a minimized pane before zooming it, and `paneDidRequestMinimize(_:to:)`
  clears an existing zoom before pinning — a pane can be in at most one of the
  two states at a time.
- Refusing the tab's last pane with nowhere to send it (MUST): if the spec
  vetoes removing a tab's only pane and no `onLastPaneCloseRequest` handler is
  installed, `paneDidRequestClose(_:)` announces a refusal and leaves the pane
  in place; the pane simply cannot be closed through this path.
- Idempotent persistence (MUST): `persistThicknessesIfChanged()` compares a
  rounded thickness signature against the last one written and skips the
  `onLayoutDidChange` call entirely when nothing actually moved — a window
  resize that ends where it began, or a tab switch that re-triggers a layout
  pass, costs no write.
- A move the spec disallows leaves the tree untouched (MUST): `move(_:_:)`
  computes the candidate tree before deciding, and returns `false` with zero
  mutation when the spec refuses it — there is no partial move to roll back.
- Rebuilding onto a shape with fewer leaves than were live (MUST): every
  previously-live leaf whose id does not survive into the new shape has
  `paneWillBeRemoved()` called on it before the new tree is constructed (see
  **rebuild-tears-down-dropped-panes**), so its process/watcher resources are
  released rather than merely dereferenced.
