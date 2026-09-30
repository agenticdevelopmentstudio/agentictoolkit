<!-- leaf: implement-composable-tabs/view-controller--part-4 · source: composable-tabs-view-controller.md -->

# ComposableTabsViewController — continued (part 4)

**Rules** (cite as `implement-composable-tabs/view-controller--part-4#<slug>`):

- `reapply-drops-stale-zoom` MUST
- `reapply-reresolves-minimize-edge` MUST
- `refresh-pane-controls-notifies-every-leaf` MUST
- `custom-arranger` MAY

- **reapply-drops-stale-zoom**: `reapplyPaneState()` MUST clear the root's
  `zoomedLeaf` and un-collapse the tree when the zoomed leaf is no longer
  present among the tab's leaves.
- **reapply-reresolves-minimize-edge**: `reapplyPaneState()` MUST re-resolve
  each minimized leaf's edge against the current tree rather than trust the
  edge it was last minimized to, and MUST restore the pane instead when no
  edge remains valid.
- **refresh-pane-controls-notifies-every-leaf**: `refreshPaneControls()` MUST
  re-ask every leaf in the tab to refresh its own control availability.
- **custom-arranger**: Component MAY be configured with a custom
  `PaneArranger` (for example `ProportionalArranger`) in place of the default
  `InheritedSlotArranger`, to redistribute thickness fractions along the
  arrangement axis differently than "leave what a split/remove already
  assigned."
## Appearance

- **Corner radius**: Not applicable — the split view and its items draw no
  custom layer or corner radius anywhere in source.
- **Padding**: Not set by this type directly. `PaneSpacing.contentInsets`
  (four independently configurable edge settings, each `0` by default) is the
  app-wide inset applied around the pane area by the window/container that
  hosts a root `ComposableTabsViewController`; this file itself sets no
  content insets on its own view.
- **Font**: Not applicable — this component draws no text of its own; any
  text belongs to the panes it hosts.
- **Background**: `PaneSplitView.drawDivider(in:)` fills a divider wider than
  1pt with `currentPalette.projectPaneBackdrop`, so a wide gutter reads as the
  same backdrop plane the frame spacing shows, not a colored bar; a divider at
  or under 1pt falls back to `ThemedSplitView`'s own (unspecified in this
  source) default drawing.
- **Foreground/Text**: Not applicable — no text is drawn by this type.
- **Border**: Not applicable — no border is configured on the split view or
  its items anywhere in source.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere in
  source.
- **Min/Max size**: A pane's `minimumThickness` comes from its registered
  `ComposableTabsViewDescriptor.minimumThickness` (`120pt` by default per
  `ComposableTabsViewDescriptor.init`); a nested split's minimum is the sum of
  its children's minimums along the split's own axis, or the max of them
  across it. A divider's thickness is `PaneSpacing.current.betweenColumns`
  (vertical split) or `.betweenRows` (horizontal split) — both `1pt` by
  default — and its draggable hit area is widened to at least
  `PaneSpacing.minimumDividerGrab` (`6pt`) without changing the drawn gutter
  width. A minimized pane is pinned to a fixed thickness (its
  `minimumThickness == maximumThickness`) computed by the pane itself
  (`minimizedThickness(for:)`, outside this file's source).

## Accessibility

- **Role/trait**: Not explicitly set in source. `NSSplitViewController` and
  its `NSSplitView` expose AppKit's own default split-view accessibility role
  and divider semantics; this file overrides no accessibility API.
- **Label requirements**: Not applicable at this level — no accessibility
  label or identifier is assigned to the split view, a divider, or an item in
  this source; a pane's own accessible content is that pane's own concern
  (each pane is a separately hosted child view controller with its own view).
- **Announce state changes**: Not implemented in source. A zoom, a
  minimize/restore, a split, a remove, or a move all change which panes are
  visible and how much space each has, but nothing in this source posts an
  `NSAccessibility.post(element:notification:)` call (or any other
  accessibility notification) when any of these happen; the refusal path even
  for a genuinely-blocked action is a plain audible beep
  (`RefusalFeedback.announce()`), not a VoiceOver-readable message. A
  VoiceOver user is not told a pane appeared, disappeared, or changed size,
  and hears nothing until navigating back into the split.
- **non-pointer-resize**: NEEDS REVIEW: Not implemented in source. A divider's thickness changes only via a mouse drag (`NSSplitView`'s own dragging plus the widened hit-test rect from `widen-divider-grab-area`); no method here lets a keyboard-only or switch-control user change a `thicknessFraction` without a pointer, and whether AppKit's default `NSSplitView` keyboard-accessibility behavior (if any) is sufficient, or a keyboard resize command should be added, needs a keyboard-only/VoiceOver pass over a live project window to settle. The 44×44pt (iOS) / 48×48dp (Android) touch tap-target minimum does not apply to this AppKit, pointer-driven desktop control.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `nodeID` | `UUID` | — (required) | Identity of this node in the persisted `LayoutNode` tree; immutable after init. |
| `axis` | `ComposableTabsAxis` | — (required) | `.horizontal` or `.vertical`; may change via `rebuild(from:)` when the persisted shape re-lays the root along the other axis. |
| `workingDirectory` | `URL` | — (required) | The directory every pane in this split, and every split nested inside it, works in; set once at init. |
| `isRoot` | `Bool` | — (required) | Whether this instance is the tab's own root; gates persistence, `viewDidAppear` restore, and `reassignPaneIdentifiers` on load. |
| `thicknessFraction` | `CGFloat?` | `nil` | This node's share (`0...1`) of the split it sits in; `nil` means "never sized." |
| `arranger` | `PaneArranger` | `InheritedSlotArranger()` | Governs how thickness fractions are redistributed when panes come and go; `ProportionalArranger` is the built-in alternative. |
| `layoutOverride` | `ComposableTabsLayout?` | `nil` | A layout this subtree uses instead of the project's own, stamped down the whole subtree. |
| `stateOwnerNodeID` | `UUID?` | `nil` | The layout node every pane in this subtree should remember its per-pane state against, for panes that are not layout nodes themselves. |
| `clampsToContainer` | `Bool` | `false` | Whether this tree's width is the enclosing container's to decide rather than its own; stamped down the whole subtree. |
| `onLayoutDidChange` | `((LayoutNode) -> Void)?` | `nil` | Root-only callback fired with a fresh snapshot whenever a persistable layout change occurs. |
| `onLastPaneCloseRequest` | `((ComposableTabsPaneViewController) -> Void)?` | `nil` | Root-only callback that, when set, lets the tab's one required pane be emptied instead of refusing its close button. |
| `zoomedLeaf` | `ComposableTabsPaneViewController?` | `nil` | Root-only: the pane currently taking over the whole tab, if any. |

## Accessibility Options

- **Reduce Motion**: Not applicable — source defines no animation,
  transition, or `NSAnimationContext`/`animator()` call; every arrangement
  change (`applyPreferredThicknessesIfNeeded`, zoom's `isCollapsed` flags,
  minimize's pinning) is set directly and takes effect immediately, per the
  `zoom-collapses-off-path-items` comment's own note that `isCollapsed` is
  "set directly rather than through `animator()`."
- **Increase Contrast**: Not applicable — the only custom color usage in this
  source is `PaneSplitView.drawDivider(in:)` filling with
  `currentPalette.projectPaneBackdrop`, a theme-driven color with no
  independent Increase Contrast handling in this file; that concern belongs
  to the palette/theme system, not to this component.
- **Differentiate Without Color**: Not applicable — this component conveys no
  state (zoomed, minimized, collapsed) through color at all; those states are
  conveyed by which panes are visible and how much space each occupies, which
  is unaffected by this accessibility setting.

## Privacy

- **Data collected**: None by this component itself. It manages an in-memory
  tree of node ids, view identifiers, and sizing fractions describing *how*
  panes are arranged — never the content displayed inside a pane.
- **Storage**: In-memory only, for the life of the tree (`layoutChildren`,
  `thicknessFraction`, `zoomedLeaf`, and related properties). Whether and how
  a snapshot handed to `onLayoutDidChange` is written to disk is entirely the
  host's responsibility and outside this file's source.
- **Transmission**: Not applicable — no networking call appears anywhere in
  source.
- **Retention**: None beyond the controller's own lifetime; state is
  discarded when the tab/tree is torn down (`tearDownPanes()`,
  `detachSubtree()`).

