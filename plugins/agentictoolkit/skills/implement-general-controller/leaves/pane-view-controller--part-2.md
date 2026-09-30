<!-- leaf: implement-general-controller/pane-view-controller--part-2 · source: pane-view-controller.md -->

# PaneViewController — continued (part 2)

**Rules** (cite as `implement-general-controller/pane-view-controller--part-2#<slug>`):

- `state-store-injection` MUST
- `coder-init-unsupported` MUST
- `host-weak-reference` MUST
- `close-is-a-request` MUST
- `zoom-is-a-request` MUST
- `minimize-picker-uses-host-edges` MUST
- `minimize-pick-is-a-request` MUST
- `restore-is-a-request` MUST
- `host-change-refreshes-controls` MUST
- `close-availability-defaults-true` MUST
- `minimize-availability-empty-without-host` MUST
- `title-bar-above-content` MUST
- `content-child-hierarchy` MUST
- `no-content-is-supported` MUST
- `accessibility-id-on-container` MUST
- `clamped-pane-yields-width` MUST
- `clamp-covers-later-installed-chrome` MUST
- `clamp-is-one-way` MUST
- `title-follows-content` MUST
- `title-change-callback-installed` MUST
- `title-refresh-updates-three-readers` MUST
- `fallback-title-default` MUST
- `accessories-from-content` MUST
- `gear-installed-trailing` MUST
- `gear-menu-order` MUST
- `bare-pane-menu-is-settings-only` MUST
- `menu-items-self-validate` MUST
- `settings-opens-options-dialog` MUST
- `options-rows-order` MUST
- `options-dialog-close-flushes-spacing` MUST
- `spacing-defaults-to-inherited` MUST
- `spacing-consumer-applies-its-own-gap` MUST
- `spacing-non-consumer-gets-pane-applied-gap` MUST
- `spacing-control-range` MUST
- `spacing-clamped-on-read` MUST
- `spacing-decode-failure-is-absent` MUST
- `spacing-reset-restores-inheritance` MUST
- `spacing-reset-enabled-only-when-overridden` MUST
- `apply-resolved-spacing-is-idempotent` MUST
- `minimize-vertical-hides-content-only` MUST
- `minimize-horizontal-replaces-with-rail` MUST
- `rail-glyph-from-content` MUST
- `rail-rebuilt-on-edge-change` MUST
- `restore-clears-minimized-chrome` MUST
- `minimized-content-pins-deactivated` MUST
- `minimize-before-load-is-lossless` MUST
- `appearance-methods-noop-before-load` MUST
- `title-bar-trailing-active-except-rail` MUST

## Behavioral Requirements

### Identity & construction

- **state-store-injection**: The pane MUST accept a `PaneStateStore` at construction and MUST default to `EphemeralPaneStateStore` when none is supplied.
- **coder-init-unsupported**: The pane MUST NOT support `NSCoder`-based initialization; invoking `init(coder:)` MUST call `fatalError`.

### Host relationship (requests, not actions)

- **host-weak-reference**: The pane MUST hold its `host` reference weakly.
- **close-is-a-request**: Clicking the close control MUST call `host.paneDidRequestClose(_:)` and MUST NOT remove the pane or change any pane state itself.
- **zoom-is-a-request**: Clicking the zoom control MUST call `host.paneDidRequestZoom(_:)` and MUST NOT change `isZoomed` itself.
- **minimize-picker-uses-host-edges**: Clicking the minimize control MUST present a picker offering exactly the edges `host.availableMinimizeEdges(for:)` returns, with every other edge disabled.
- **minimize-pick-is-a-request**: Choosing an edge from the picker MUST call `host.paneDidRequestMinimize(_:to:)` with the chosen edge and MUST NOT change `minimizedEdge` itself.
- **restore-is-a-request**: Clicking restore, from the title bar or from the minimized rail, MUST call `host.paneDidRequestRestore(_:)` and MUST NOT change `minimizedEdge` itself.
- **host-change-refreshes-controls**: Setting `host` to a new value MUST immediately re-derive whether the minimize and close controls are available from the new host, without waiting for another trigger.
- **close-availability-defaults-true**: `canClose` MUST be treated as `true` when there is no host, or when the host does not override `PaneHost.canClose(_:)`.
- **minimize-availability-empty-without-host**: The minimize control MUST be disabled when there is no host.

### Loading and layout

- **title-bar-above-content**: The pane's view MUST place `titleBar` above `contentContainer`, both inset from the container by `contentInset` (default `0`) on every side.
- **content-child-hierarchy**: When `makeContentViewController()` returns non-nil, that view controller MUST be added as a child and its view MUST be pinned to the four edges of `contentContainer`.
- **no-content-is-supported**: When `makeContentViewController()` returns `nil`, the pane MUST load a working, empty pane rather than failing.
- **accessibility-id-on-container**: The pane's container view MUST carry the accessibility identifier returned by `paneAccessibilityIdentifier` (default `"pane"`).
- **clamped-pane-yields-width**: Setting `clampsToContainer` to `true` MUST call `titleBar.yieldWidthToContainer()` exactly once, and setting it to `false` MUST have no effect.
- **clamp-covers-later-installed-chrome**: Chrome installed into the title bar after clamping — the gear button, at minimum — MUST also have its width demand yielded when the pane is clamped.
- **clamp-is-one-way**: Setting `clampsToContainer` back to `false` after it was `true` MUST NOT restore the title bar's original compression resistance.

### Title

- **title-follows-content**: `resolvedTitle` MUST equal `(contentViewController as? PaneTitleProviding)?.paneTitle`, falling back to `fallbackTitle` when the content does not implement `PaneTitleProviding`.
- **title-change-callback-installed**: The pane MUST install its own closure into the content's `onPaneTitleChange` (when implemented) once, during the pane's initial setup, so the title bar updates without polling.
- **title-refresh-updates-three-readers**: Calling `refreshTitle()` MUST update the title bar's title, the open options dialog's heading (when one is presented), and MUST invoke `onTitleChange`.
- **fallback-title-default**: `fallbackTitle` MUST be `"Pane"` when not overridden by a subclass.

### Accessories and gear

- **accessories-from-content**: `refreshAccessories()` MUST set the title bar's accessory views to `(contentViewController as? PaneAccessoryProviding)?.makePaneAccessoryViews()`, or an empty array when the content does not implement `PaneAccessoryProviding`.
- **gear-installed-trailing**: The pane MUST install a gear button in the title bar's trailing slot during `viewDidLoad`.
- **gear-menu-order**: The gear's menu MUST list the pane's own `makeMenuItems()` first, followed by a separator only when that list is non-empty, followed by a `"Settings…"` item.
- **bare-pane-menu-is-settings-only**: A pane whose `makeMenuItems()` returns an empty array MUST raise a menu containing exactly one item, `"Settings…"`, with no leading separator.
- **menu-items-self-validate**: The options menu MUST set `autoenablesItems` to `false`, so every item's enabled state is decided by the item itself rather than by AppKit's default validation chain.
- **settings-opens-options-dialog**: Choosing `"Settings…"` MUST present an `OptionsDialogViewController` as a sheet, seeded with `makeOptionRows()` and headed by `resolvedTitle`.
- **options-rows-order**: `makeOptionRows()` MUST return the pane's own spacing control and reset button first, followed by `(contentViewController as? PaneOptionsProviding)?.makePaneOptionRows()`.
- **options-dialog-close-flushes-spacing**: Dismissing the options dialog MUST flush any pending spacing-override write immediately, before the dialog closes.

### Spacing

- **spacing-defaults-to-inherited**: A pane with no stored spacing override MUST apply `inheritedPaneSpacing`. When the content implements `PaneContentSpacingConsuming`, that value MUST be exactly the content's own `inheritedPaneSpacing` (whatever the content itself reports, zero or not). When the content does not implement it, `inheritedPaneSpacing` MUST be an all-zero `Spacing`, unconditionally.
- **spacing-consumer-applies-its-own-gap**: When the content implements `PaneContentSpacingConsuming`, the pane MUST call `applyPaneSpacing(_:)` on it with the resolved spacing and MUST hold `contentSpacingInsets` at zero.
- **spacing-non-consumer-gets-pane-applied-gap**: When the content does not implement `PaneContentSpacingConsuming`, the pane MUST hold the content off `contentContainer`'s edges by the resolved spacing's four insets itself.
- **spacing-control-range**: The pane's spacing control MUST offer the range `0...40` on every edge.
- **spacing-clamped-on-read**: A stored spacing value outside `0...40` on any edge (written by an older build, or edited by hand) MUST be clamped back into range when read from the state store, never rejected outright.
- **spacing-decode-failure-is-absent**: A spacing-override JSON string that fails to decode MUST be treated the same as no stored override, not as an error.
- **spacing-reset-restores-inheritance**: Activating the spacing reset button MUST delete the pane's stored override rather than writing the current inherited value, and MUST leave the reset button disabled immediately afterward.
- **spacing-reset-enabled-only-when-overridden**: The spacing reset button MUST be enabled exactly when the pane currently has a stored override.
- **apply-resolved-spacing-is-idempotent**: Calling `applyResolvedSpacing()` more than once with nothing changed MUST leave the resolved spacing, the spacing control's displayed value, and the content insets unchanged.

### Minimize / restore appearance

- **minimize-vertical-hides-content-only**: Minimizing to `.top` or `.bottom` MUST hide `contentContainer` and the content's view while leaving the title bar visible, showing its minimized (restore) control state.
- **minimize-horizontal-replaces-with-rail**: Minimizing to `.leading` or `.trailing` MUST hide the title bar and content, and MUST show a `PaneMinimizedStripView` docked to that edge.
- **rail-glyph-from-content**: The minimized rail's symbol and tooltip MUST come from `(contentViewController as? PaneMinimizedRepresenting)?.paneMinimizedSymbolName`/`paneMinimizedTooltip`, falling back to `PaneMinimizedStripView.defaultSymbolName` and `resolvedTitle` respectively.
- **rail-rebuilt-on-edge-change**: Flipping directly from one minimized horizontal edge to the other MUST remove the existing rail and build a new one docked to the new edge, rather than repositioning the existing view.
- **restore-clears-minimized-chrome**: Restoring (`setMinimized(to: nil)`) MUST unhide the title bar and content, remove any rail, and reactivate the content's four edge constraints.
- **minimized-content-pins-deactivated**: While minimized to any edge, the four constraints pinning the content's view to `contentContainer` MUST be deactivated, not merely left active on a hidden view.
- **minimize-before-load-is-lossless**: Calling `setMinimized(to:)` before the pane's view has loaded MUST record the edge and MUST NOT force the view to load; the recorded edge MUST be applied exactly once when the view does load.
- **appearance-methods-noop-before-load**: `applyMinimizedAppearance()`'s effects MUST NOT occur, and MUST NOT force the view to load, while the view is not loaded.
- **title-bar-trailing-active-except-rail**: The title bar MUST span the container's full width for every pane shape except a pane minimized to a horizontal (leading/trailing) edge, where its trailing edge MUST be released so it can collapse to its own width instead of being stretched to match the (now much narrower) rail.

