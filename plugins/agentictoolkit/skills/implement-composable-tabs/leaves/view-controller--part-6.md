<!-- leaf: implement-composable-tabs/view-controller--part-6 · source: composable-tabs-view-controller.md -->

# ComposableTabsViewController — continued (part 6)

## Design Decisions

- **Decision**: One-shot `hasAppliedPreferredThicknesses` guard, reset
  explicitly by every mutation that changes the arrangement (split, remove,
  rebuild, `applySizes`) rather than on every `layoutChildren` assignment.
  **Rationale**: Per the `viewDidLayout` doc comment, "after the first real
  layout the user owns the dividers, and re-imposing a fraction on every
  layout pass would fight them"; resetting only where the arrangement actually
  changes keeps a plain window resize from re-snapping dividers back to their
  preferred fractions.
  **Approved**: pending
- **Decision**: `captureThicknessFractions()` refuses to run over a zoomed
  tree, and skips a whole split (not just its pinned item) when any item in it
  shows a rail.
  **Rationale**: Per the method's own doc comment, a zoom or a rail is "an
  arrangement of the screen rather than a decision about sizes," and reading
  either back would silently corrupt the persisted layout — a saved layout
  while zoomed would "restore unzoomed and wrong," and a captured rail
  fraction would make a dragged 200pt pane "reopen at its floor" after a
  relaunch.
  **Approved**: pending
- **Decision**: Thickness persistence is debounced 300ms and deduplicated by a
  rounded signature, rather than writing on every `splitViewDidResizeSubviews`.
  **Rationale**: A drag posts a resize notification per mouse event and a
  window resize posts one per frame; per the method's doc comment, writing on
  each "would put the database in the middle of a gesture," and the signature
  check drops writes "that changed nothing" — a resize that ends where it
  began costs no write.
  **Approved**: pending
- **Decision**: `restoreSizing(of:)` clears `maximumThickness` before it
  lowers `minimumThickness`/`holdingPriority`, rather than the reverse order.
  **Rationale**: Per the method's doc comment, raising the minimum first would
  briefly ask AppKit to satisfy a minimum at or above the still-pinned
  maximum — a pair AppKit "cannot satisfy, logs, and recovers from by
  breaking one of them." Lifting the ceiling first keeps every intermediate
  state satisfiable.
  **Approved**: pending
- **Decision**: A non-root split with one remaining child collapses itself out
  of the tree instead of being left in place holding a single child.
  **Rationale**: Per `remove(_:)`'s doc comment, "a non-root split left with
  one child is a degenerate split" that should collapse into its parent; the
  *root* is allowed to hold a single child, because that legitimately
  represents "a tab reduced to one full-size pane."
  **Approved**: pending
- **Decision**: `zoomedLeaf` and `onLastPaneCloseRequest` are stored on the
  root and read through `rootSplit()`, never on an intermediate split.
  **Rationale**: Per their doc comments, a zoom "is a fact about the tab
  rather than about one split," and the last-pane-close override is "the
  right answer for a window's own tree" but has to be installed per tab
  (root) since which container "has somewhere else for the request to go"
  differs by container.
  **Approved**: pending
