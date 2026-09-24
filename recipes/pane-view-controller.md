---
id: 2b4d0f95-dbdf-48a9-8579-a3e5b7d488fe
title: PaneViewController
domain: agentictoolkit://recipes/pane-view-controller
type: ingredient
version: 1.1.1
status: review
language: en
created: '2026-09-23'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'AppKit pane chrome: title bar, content hosting, host-mediated close/minimize/zoom/restore,
  and per-pane spacing, probing content for six optional capabilities.'
platforms:
- swift
- macos
tags:
- pane
- view-controller
- appkit
- macos
- accessibility
depends-on:
- agenticdevelopertoolkit://recipes/pane-title-bar-view
- agenticdevelopertoolkit://recipes/pane-minimize-picker
- agenticdevelopertoolkit://recipes/pane-minimized-strip-view
- agenticdevelopertoolkit://recipes/options-dialog-view-controller
related:
- agentictoolkit://recipes/composable-tabs-pane-view-controller
- agenticdevelopertoolkit://recipes/window-options-dialog
- agenticdevelopertoolkit://recipes/pane-control-cluster
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
references: []
approved-by: ''
approved-date: ''
---

# PaneViewController

## Overview

`PaneViewController` (`packages/apple/AgenticToolkit/macOS/UI/ViewControllers/Panes/PaneViewController.swift`) is a pane: a title bar, some content, and enough memory to come back the way it was left. It knows nothing about split views, layout trees, tabs, projects, or SQLite — it reaches the world outside itself through exactly three seams: a `PaneHost` it sends requests to (close, zoom, minimize, restore, and two questions about what is currently legal), a `PaneStateStore` it remembers itself through (minimize edge, zoomed flag, spacing override), and content it probes for six optional capability protocols (`PaneTitleProviding`, `PaneAccessoryProviding`, `PaneOptionsProviding`, `PaneMinimizedRepresenting`, `PaneSearchable`, `PaneSelectionDescribing`). Every one of those is supplied from outside, which is what lets the same class be dropped into a container with different rules and still be correct. A seventh protocol, `PaneContentSpacingConsuming`, is counted separately: it is not a content-capability the pane probes for chrome, but the spacing hook (see `inheritedPaneSpacing` under Spacing) — the source's own class doc names it apart from "six optional capabilities" for the same reason.

It exposes seven `open` subclass hooks — `makeContentViewController()`, `makeContainerView()`, `makeOptionRows()`, `makeMenuItems()`, `fallbackTitle`, `contentInset`, and `paneAccessibilityIdentifier` — and a subclass that overrides none of them still gets a working, empty pane. Content that implements none of the six capability protocols is a supported case, not a degraded one: it gets `fallbackTitle`, no accessories, no pane-specific options beyond the universal spacing control, the generic minimized glyph, and a search field the window leaves disabled. `ComposableTabsPaneViewController` (see `related`) is the framework's own subclass, adding registry-vended content, an active-pane outline, and arrange-mode chrome on top of everything documented here.

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

### Persistence

- **minimize-edge-persisted**: `setMinimized(to:)` MUST write the edge's raw value to the state store under `PaneStateKey.minimizeEdge`, or delete that key when set to `nil`.
- **zoom-persisted**: `setZoomed(_:)` MUST write `"1"` to the state store under `PaneStateKey.zoomed` when `true`, or delete that key when `false`.
- **state-restored-on-load**: `viewDidLoad` MUST restore `minimizedEdge` and `isZoomed` from the state store via `restorePersistedState()`.
- **unparseable-stored-edge-ignored**: A stored minimize-edge value that does not match a `PaneEdge` raw value MUST be treated as absent — the pane opens whole — rather than crashing or raising an error.

### Search and selection

- **search-reaches-searchable-content-only**: `isSearchable` MUST be `true` exactly when the content implements `PaneSearchable`; `search(for:)` MUST forward to the content when searchable and MUST be a no-op otherwise.
- **selection-description-reported**: `selectionDescription` MUST equal `(contentViewController as? PaneSelectionDescribing)?.paneSelectionDescription`, or `nil` when the content does not implement the protocol.
- **selection-change-forwarded**: The pane MUST install its own closure into the content's `onPaneSelectionChange` (when implemented) and MUST call its own `onSelectionChange` whenever that fires.

### Sizing for the host

- **minimized-thickness-formula**: `minimizedThickness(for:)` MUST return `PaneMinimizedStripView.thickness + contentInset * 2` for a horizontal edge and `PaneTitleBarView.height + contentInset * 2` for a vertical edge.

## Appearance

- **Corner radius**: None drawn by this class. The default container, `ThemedBackgroundView(role: .windowBackground)`, is a plain rectangle; a subclass overriding `makeContainerView()` may add one, out of scope here.
- **Padding**: `contentInset` (default `0`pt) holds both the title bar and the content off the container's edges. The title bar is a fixed `PaneTitleBarView.height` = 26pt tall. A minimized-to-a-side rail is a fixed `PaneMinimizedStripView.thickness` = 28pt thick.
- **Font**: Not set directly in this file; the title bar's own label typography belongs to `PaneTitleBarView` (`depends-on`), out of this recipe's scope.
- **Background**: The pane's own fill is whatever `makeContainerView()` returns; the default is `ThemedBackgroundView(role: .windowBackground)`.
- **Foreground/Text**: Not set directly in this file; delegated to the title bar and to the content.
- **Border**: None drawn by this class anywhere in this file.
- **Shadow**: None drawn by this class anywhere in this file.
- **Min/Max size**: None set by this class. The container view is given an explicit `NSRect(x: 0, y: 0, width: 300, height: 200)` frame at `loadView()`, before Auto Layout resolves its real size from the constraints installed immediately after; no min/max width or height constraint is authored anywhere in this file.
- **Gear button**: Built by `WindowOptionsDialog.makeGearButton(tooltip: "Pane options")` — borderless, `.accessoryBarAction` bezel, the `gearshape` SF Symbol shown image-only, tinted with the theme's secondary-text color.

## States

| State | Appearance change |
|-------|------------------|
| Default | — |
| Pressed | Not applicable: the pane container itself has no pressed state; its close/minimize/zoom buttons, the gear, and the spacing control and its reset button each have their own recipe and their own pressed appearance. |
| Disabled | Not applicable as a whole-pane state; the close and minimize controls are independently enabled or disabled per `canClose`/`canMinimize` — see Behavioral Requirements. |
| Focused | Not applicable as a visual state of this view; this class draws no focus ring of its own. |
| Loading | Not applicable: any loading indicator belongs to the hosted content view controller, which has its own recipe. |
| Whole | Title bar over content; both held `contentInset` off the container's edges. |
| Minimized (top/bottom) | Content and its container are hidden; the title bar stays visible, and its minimize control shows the restore glyph (`plus`) and tooltip "Restore Pane". |
| Minimized (leading/trailing) | Title bar and content are hidden; a `PaneMinimizedStripView` rail is docked to that edge, showing the content's glyph and tooltip or the generic defaults. |
| Zoomed | The zoom control's glyph and tooltip flip (`arrow.up.left.and.arrow.down.right` ↔ `arrow.down.right.and.arrow.up.left`, "Zoom Pane" ↔ "Unzoom Pane"); the pane's own size and position are unaffected by this class — resizing is the host's responsibility. |
| Clamped to container | The title bar, every view already inside it, and any chrome installed into it afterward carries the lowest horizontal content-compression-resistance priority (`1`), so the pane never forces its container wider. |

## Accessibility

- **Role/trait**: The container view carries the accessibility identifier `paneAccessibilityIdentifier` returns (`"pane"` by default), set by `loadView()`. It is a plain view with no explicit AX role override in this file. The gear button carries identifier `pane.options`; the "Settings…" menu item carries `pane.options.settings`; the spacing control carries `pane.options.spacing`; the spacing reset button carries `pane.options.spacing.reset`. The close/minimize/zoom buttons, the minimize picker, the minimized rail, and the options dialog's own controls carry their identifiers inside their own components, each with its own recipe (see `depends-on`/`related`) — out of scope here.
- **Label requirements**: The gear button's `accessibilityDescription` and `toolTip` are both "Pane options"; its accessibility label is set separately to "Pane Options". The "Settings…" menu item's image carries `accessibilityDescription`: "Settings". The spacing reset button's accessibility label is "Use Default Spacing", distinct from its visible title "Use Default".
- **Announce state changes**: No `NSAccessibility` notification is posted anywhere in this file when the title changes, when the pane minimizes, restores, or zooms — every one of those is a silent property assignment. A VoiceOver user has no non-visual cue that any of these four things happened.
- **Minimum tap target**: Not overridden in this file. The gear button and the spacing reset button are standard `NSButton`s sized by AppKit's intrinsic content size; macOS's pointer-driven HIG does not carry the 44×44pt minimum that applies to iOS touch targets, and this source sets no explicit minimum of its own.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| pvc-001 | state-store-injection | Construct a pane with no `stateStore` argument | `stateStore` is an `EphemeralPaneStateStore` instance |
| pvc-002 | coder-init-unsupported | Call `init(coder:)` | `fatalError` is called (process traps rather than returning) |
| pvc-003 | host-weak-reference | Assign `host`, then release every other strong reference to that host object | `pane.host` becomes `nil` |
| pvc-004 | close-is-a-request | Click the title bar's close button | `host.paneDidRequestClose(_:)` is called once; no pane state changes |
| pvc-005 | zoom-is-a-request | Click the title bar's zoom button | `host.paneDidRequestZoom(_:)` is called once; `pane.isZoomed` remains `false` |
| pvc-006 | minimize-picker-uses-host-edges | `host.availableMinimizeEdges` returns `{.top, .bottom}`; click the minimize button | The picker's cross view has `availableEdges == {.top, .bottom}`; its `.top` button is enabled and its `.leading` button is disabled |
| pvc-007 | minimize-pick-is-a-request | Open the minimize picker; pick `.leading` | `host.paneDidRequestMinimize(_:to:)` is called with `.leading`; `pane.minimizedEdge` remains `nil` |
| pvc-008 | restore-is-a-request | Minimize the pane to `.trailing`; click the rail's restore button | `host.paneDidRequestRestore(_:)` is called once |
| pvc-009 | host-change-refreshes-controls | Set `host` to one whose `availableMinimizeEdges` returns `{}` | The minimize button is disabled immediately after the assignment, with no further call needed |
| pvc-010 | close-availability-defaults-true | A pane with no `host` assigned | `titleBar.controls.canClose == true` |
| pvc-011 | minimize-availability-empty-without-host | A pane with no `host` assigned | The minimize button is disabled |
| pvc-012 | title-bar-above-content | Load the pane's view with `contentInset == 0` | `titleBar`'s top/leading constraints and `contentContainer`'s top constraint (to the title bar's bottom) all resolve with a `0` constant |
| pvc-013 | content-child-hierarchy | `makeContentViewController()` returns a view controller | `pane.children` contains it; its view has exactly four active constraints pinning it to `contentContainer` |
| pvc-014 | no-content-is-supported | `makeContentViewController()` returns `nil` (the default) | The pane's view loads without error; `contentViewController` is `nil` |
| pvc-015 | accessibility-id-on-container | Load a pane whose `paneAccessibilityIdentifier` is not overridden | `pane.view.accessibilityIdentifier() == "pane"` |
| pvc-016 | clamped-pane-yields-width | Set `clampsToContainer = true` before loading the view (this fires the `didSet` at construction time), then load it | The title bar's, and its close button's, horizontal content-compression-resistance priority is already `1` before `loadView()` runs, and is still exactly `1` — not reset or reapplied — after `viewDidLoad()` completes, confirming the one `didSet` call was the only one |
| pvc-017 | clamp-covers-later-installed-chrome | Same setup, after `viewDidLoad` installs the gear | The gear view's horizontal content-compression-resistance priority is also `1` |
| pvc-018 | clamp-is-one-way | Set `clampsToContainer = true`, then set it back to `false` | The title bar's compression-resistance priority remains `1`, not restored to its original value |
| pvc-019 | title-follows-content, title-change-callback-installed | Content implementing `PaneTitleProviding` changes `paneTitle` from "Files" to "Sources", then synchronously invokes its own `onPaneTitleChange` closure | `titleBar.title` already reads "Sources" by the time that closure call returns — updated synchronously in response to the callback, not via a poll or a later run-loop turn |
| pvc-021 | title-refresh-updates-three-readers | An options dialog is open; call something that triggers `refreshTitle()` after the content's title changed | `titleBar.title`, the open dialog's `heading`, and `onTitleChange` all reflect the new title |
| pvc-022 | fallback-title-default | A `PaneViewController` subclass overriding nothing | `fallbackTitle == "Pane"` |
| pvc-023 | accessories-from-content | Content implementing `PaneAccessoryProviding` with one accessory view | `titleBar.accessoryViews` has exactly one element, identical to the content's view |
| pvc-024 | gear-installed-trailing | Load any pane | `titleBar.gearView` is non-nil, and its layout constraints pin it to `titleBar`'s own trailing edge (the trailing slot), not merely somewhere in the bar |
| pvc-025 | gear-menu-order | A pane overriding `makeMenuItems()` to return one "Move" item | `makeOptionsMenu().items.map(\.title) == ["Move", "", "Settings…"]`, with `items[1]` a separator |
| pvc-026 | bare-pane-menu-is-settings-only | A pane whose `makeMenuItems()` returns `[]` | The menu has exactly one item, titled "Settings…" |
| pvc-027 | menu-items-self-validate | Any pane's options menu | `menu.autoenablesItems == false` |
| pvc-028 | settings-opens-options-dialog | Choose "Settings…" from the gear menu | An `OptionsDialogViewController` is presented as a sheet, with `rows == makeOptionRows()` and `heading == resolvedTitle` |
| pvc-029 | options-rows-order | Content implementing `PaneOptionsProviding` with two rows | `makeOptionRows()` returns 4 rows: a `SpacingControl`, a view identified `pane.options.spacing.reset`, then the content's two rows in order |
| pvc-030 | options-dialog-close-flushes-spacing | A spacing drag has a pending coalesced write; close the options dialog | The pending write reaches the state store before the dialog finishes closing |
| pvc-031 | spacing-defaults-to-inherited | Content not implementing `PaneContentSpacingConsuming`, no stored override | `pane.inheritedPaneSpacing` is an all-zero `Spacing`, unconditionally |
| pvc-032 | spacing-consumer-applies-its-own-gap | Content implementing `PaneContentSpacingConsuming` | `applyPaneSpacing(_:)` is called on the content with the resolved spacing; `contentSpacingInsets` is all zero |
| pvc-033 | spacing-non-consumer-gets-pane-applied-gap | Content not implementing `PaneContentSpacingConsuming`; a stored override of `top: 10` | `pane.contentSpacingInsets.top == 10` |
| pvc-034 | spacing-control-range | Call `makeSpacingRows()` | The returned `SpacingControl`'s underlying range is `0...40` |
| pvc-035 | spacing-reset-restores-inheritance | Set an override, then click "Use Default" | The state store's `spacing.override` key is deleted (not rewritten with the current inherited value); the reset button becomes disabled |
| pvc-036 | spacing-reset-enabled-only-when-overridden | Toggle between an overridden and a non-overridden spacing state, calling `applyResolvedSpacing()` after each | The reset button's `isEnabled` matches `spacingOverride.isOverridden` at every check |
| pvc-037 | apply-resolved-spacing-is-idempotent | Call `applyResolvedSpacing()` twice in a row with nothing changed in between | The spacing control's displayed value, `spacingOverride.resolved`, and `contentSpacingInsets` are all identical after both calls |
| pvc-038 | minimize-vertical-hides-content-only | `setMinimized(to: .top)` | `titleBar.isHidden == false`; `contentViewController?.view.isHidden == true`; `titleBar.controls.isMinimized == true` |
| pvc-039 | minimize-horizontal-replaces-with-rail | `setMinimized(to: .leading)` | `titleBar.isHidden == true`; a `PaneMinimizedStripView` exists among the pane's subviews |
| pvc-040 | rail-glyph-from-content | Content implementing `PaneMinimizedRepresenting` with symbol "folder"; minimize to `.leading` | The rail's `symbolName == "folder"` and `tooltip` equals the content's `paneMinimizedTooltip` |
| pvc-041 | rail-rebuilt-on-edge-change | Minimize to `.leading`, then directly to `.trailing` | Exactly one rail exists afterward; it is a different instance from the first, docked to the trailing edge |
| pvc-042 | restore-clears-minimized-chrome | Minimize to `.leading`, then `setMinimized(to: nil)` | `minimizedEdge == nil`; `titleBar.isHidden == false`; no `PaneMinimizedStripView` remains among the subviews |
| pvc-043 | minimized-content-pins-deactivated | Minimize to `.leading`, then to `.top` | The count of active constraints pinning the content's view to `contentContainer` is `0` in both cases; it is `4` when whole |
| pvc-044 | minimize-before-load-is-lossless | Construct a pane; call `setMinimized(to: .leading)` before touching `view`; then load the view | `isViewLoaded` stays `false` until explicitly loaded; after loading, exactly one rail exists and `minimizedEdge == .leading` |
| pvc-045 | appearance-methods-noop-before-load | Same setup as pvc-044, checked immediately after `setMinimized` and before loading | `isViewLoaded == false`; no `PaneMinimizedStripView` has been created yet; the title bar's hidden state is untouched (nothing has run to hide or show it), because `applyMinimizedAppearance()` returned immediately |
| pvc-046 | title-bar-trailing-active-except-rail | Force a layout pass at a fixed container width, after minimizing to `.leading` versus after minimizing to `.top` | The title bar's `frame.width` equals the container's content width (minus insets) when minimized to `.top`; it is narrower than that after minimizing to `.leading`, because the trailing edge was released |
| pvc-047 | minimize-edge-persisted | `setMinimized(to: .bottom)` against a store | The store's value for `PaneStateKey.minimizeEdge` is `"bottom"` |
| pvc-048 | zoom-persisted | `setZoomed(true)` against a store | The store's value for `PaneStateKey.zoomed` is `"1"` |
| pvc-049 | state-restored-on-load | Pre-populate a store with `minimize.edge = "trailing"` and `zoomed = "1"`; load a pane against it | `pane.minimizedEdge == .trailing`; `pane.isZoomed == true` |
| pvc-050 | unparseable-stored-edge-ignored | Pre-populate a store with `minimize.edge = "sideways"`; load a pane against it | `pane.persistedMinimizeEdge == nil`; `pane.minimizedEdge == nil`; no crash |
| pvc-051 | search-reaches-searchable-content-only | Content implementing `PaneSearchable`; call `search(for: "main")` | `isSearchable == true`; the content receives the query "main" |
| pvc-052 | selection-description-reported | Content implementing `PaneSelectionDescribing` with `paneSelectionDescription == "README.md"` | `pane.selectionDescription == "README.md"` |
| pvc-053 | selection-change-forwarded | Set `onSelectionChange`; change the content's `paneSelectionDescription` | `onSelectionChange` fires exactly once |
| pvc-054 | minimized-thickness-formula | `contentInset == 0`; call `minimizedThickness(for: .leading)` and `minimizedThickness(for: .top)` | Returns `28` for `.leading`; returns `26` for `.top` |
| pvc-055 | spacing-clamped-on-read | Pre-populate a store with a `spacing.override` JSON row encoding `top: 999` | The resolved spacing's `top` is `40` (clamped into `0...40`), not `999` |
| pvc-056 | spacing-decode-failure-is-absent | Pre-populate a store with `spacing.override = "not valid json"` | `spacingOverride.isOverridden == false`; the resolved spacing equals `inheritedPaneSpacing` |
| pvc-057 | search-reaches-searchable-content-only | Content not implementing `PaneSearchable`; call `search(for: "main")` | `isSearchable == false`; the call neither crashes nor has any observable effect on the content |
| pvc-058 | selection-description-reported | Content not implementing `PaneSelectionDescribing` | `pane.selectionDescription == nil` |
| pvc-059 | accessories-from-content | Content not implementing `PaneAccessoryProviding`; call `refreshAccessories()` | `titleBar.accessoryViews == []` |
| pvc-060 | rail-glyph-from-content | Content not implementing `PaneMinimizedRepresenting`; minimize to `.leading` | The rail's `symbolName == PaneMinimizedStripView.defaultSymbolName`; its `tooltip == resolvedTitle` |
| pvc-061 | clamped-pane-yields-width | Construct a pane and never set `clampsToContainer` to `true`, then set it to `false` | The title bar's horizontal content-compression-resistance priority is unchanged from its default — `yieldWidthToContainer()` is never called |
| pvc-062 | spacing-defaults-to-inherited | Content implementing `PaneContentSpacingConsuming` with `inheritedPaneSpacing == Spacing(top: 10, leading: 0, bottom: 0, trailing: 0)`, no stored override | `pane.inheritedPaneSpacing` equals exactly the content's value, `Spacing(top: 10, leading: 0, bottom: 0, trailing: 0)` |

## Edge Cases

- **Null/empty input** (MUST): `makeContentViewController()` returning `nil` results in a working, empty pane rather than a failure (`no-content-is-supported`). A spacing-override JSON string that fails to decode (`spacing-decode-failure-is-absent`), or a minimize-edge string that fails to parse as a `PaneEdge` (`unparseable-stored-edge-ignored`), is treated as absent rather than as an error.
- **Boundary values** (MUST): A stored spacing override outside the `0...40` range — written by an older build, or edited by hand — is clamped back into range on read, never rejected outright (`spacing-clamped-on-read`). `contentInset` of `0`, the default, means `minimizedThickness(for:)` reduces to exactly the docked chrome's own thickness (26pt for a vertical edge, 28pt for a horizontal one) with no border allowance added.
- **Concurrent access** (MUST): This class is `@MainActor`-isolated, and every piece of mutable state it owns is read and written only on the main actor, so there is no concurrent-access hazard by construction. The one timing subtlety is `PaneSpacingOverride`'s 300ms coalescing timer for persisted spacing writes: it still fires on the main queue, not a background thread, so it introduces no data race — only a bounded lag between a drag gesture and its write reaching the store (see Design Decisions).
- **Error states** (MUST): A `JSONEncoder`/`JSONDecoder` failure while persisting or reading the spacing override is silently ignored — the write or read simply does not happen, with no error surfaced to the caller or the user. This is the source's actual behavior, described as-is rather than as an idealized richer error path; `PaneStateStore`'s two methods return no error value at all, so there is no channel for this class to report through even if it wanted to.
- **Offline or disconnected state**: Not applicable. This component makes no network request of any kind; its only persistence goes through the injected `PaneStateStore`, and nothing in this file references a network resource.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stateStore` | `PaneStateStore` | `EphemeralPaneStateStore()` | Where the pane persists its minimize edge, zoomed flag, and spacing override; injected at construction. |
| `host` | `PaneHost?` (weak) | `nil` | The container the pane sends close/minimize/zoom/restore requests to and asks for available minimize edges and close permission. |
| `clampsToContainer` | `Bool` | `false` | When `true`, yields the title bar's — and any later-installed chrome's — width demand to the container instead of asking for its own; one-way once set. |
| `onSelectionChange` | `(() -> Void)?` | `nil` | Called when the content's selection description changes, for a host that shows a display path. |
| `onTitleChange` | `(() -> Void)?` | `nil` | Called when `resolvedTitle` would now answer differently, for a host that names the pane elsewhere (e.g. a window footer). |

## Deep Linking

Not applicable: a pane is chrome built entirely from constructor arguments and content supplied by whoever creates it. No URL scheme, universal link, or `NSUserActivity` handling appears anywhere in this file.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal string) | "Pane" | `fallbackTitle`'s default value. |
| (none — literal string) | "Pane options" | Gear button's tooltip and `accessibilityDescription`. |
| (none — literal string) | "Pane Options" | Gear button's separately-set accessibility label. |
| (none — literal string) | "Settings…" | Title of the gear menu's final item. |
| (none — literal string) | "Settings" | `accessibilityDescription` on that item's image. |
| (none — literal string) | "Use Default" | Title of the spacing reset button. |
| (none — literal string) | "Use Default Spacing" | Accessibility label of the spacing reset button. |

This file is AppKit, not SwiftUI: every string above is set through a plain `String`-typed property (`toolTip`, `title`, `setAccessibilityLabel`, `accessibilityDescription`), none of which resolve against a `.strings` catalog or `NSLocalizedString` automatically. Every one is a hardcoded English literal with no localization key.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: every appearance change in this file — minimize, restore, zoom, clamping — is an immediate property assignment (`isHidden`, constraint activation/deactivation, image swap); no `NSAnimationContext`, layer animation, or transition appears anywhere in this file. |
| Increase Contrast | Not observed in this file: colors are resolved through the theme system (`ThemedBackgroundView`, and `WindowOptionsDialog.makeGearButton`'s `observeTheme` tinting); any contrast adaptation belongs to that system, out of this ingredient's scope. |
| Differentiate Without Color | Not applicable: this class draws no state distinction using color alone anywhere in this file. Its container's fill comes entirely from `makeContainerView()`, which a subclass with a color-only cue (e.g. an active/inactive border) may override — that is `ComposableTabsPaneViewController`'s concern, documented in its own recipe, not this one's. |

## Feature Flags

Not applicable: no feature-flag or remote-config lookup of any kind appears anywhere in this file.

## Analytics

Not applicable: no analytics event is emitted anywhere in this file.

## Privacy

- **Data collected**: Only this pane's own chrome state — minimize edge, zoomed flag, and spacing override — written through the injected `PaneStateStore`. No personal or otherwise sensitive data is read or written by this file.
- **Storage**: Whatever the injected `PaneStateStore` implements. `EphemeralPaneStateStore`, the default, keeps values in memory only, for exactly as long as the pane exists. A persistent store is the caller's own choice and out of this recipe's scope.
- **Transmission**: None. No network call appears anywhere in this file.
- **Retention**: Governed entirely by whichever `PaneStateStore` is injected; this class defines no retention policy of its own.

## Logging

Not applicable: no logging call (`Logger`, `os_log`, `print`, or otherwise) appears anywhere in this file.

## Platform Notes

- **SwiftUI**: This is an `NSViewController`/AppKit subclass, not SwiftUI. A SwiftUI-first rebuild would replace the class hierarchy with a `View` driven by an `@Observable` pane view-model exposing `resolvedTitle`, `isZoomed`, and `minimizedEdge`; the title bar becomes a custom `HStack` (close/minimize/zoom buttons, a `Text(title).lineLimit(1).truncationMode(.middle)`, an accessory `HStack`, and a gear `Menu`); the six capability protocols continue to be probed with `as?` against an `AnyObject` content, the same idiom the source uses; spacing becomes a `.padding(EdgeInsets(...))` fed by the same `PaneSpacingOverride`; the minimized rail is swapped in with a plain `if`, not a transition, to preserve the source's "no animation" behavior.
- **Compose**: Model the pane as a `Column` with a fixed-height title `Row` (26dp-equivalent) over a `Box` holding the content. The six capability protocols become sealed interfaces the content composable optionally implements, probed the same way (`is`/`as` in Kotlin) rather than through compile-time generics. Minimizing to a side swaps the content `Row`/`Column` for a narrow `IconButton` column; persistence goes through a `PaneStateStore`-equivalent `DataStore` keyed the same way (`minimize.edge`, `zoomed`, `spacing.override`).
- **React/Web**: A `<div>` pane wrapper with a fixed-height header `<div>` (26px) holding the same left-to-right regions — window controls, title, accessory slot, gear. The capability protocols become optional props/callbacks (`onTitleChange`, `renderAccessories`, `renderOptionRows`) checked for existence the way `as?` is checked here. The minimized rail is a `<div>` swapped in by conditional render, not a CSS transition, matching the source's instant appearance change. Persisted chrome state goes to the same key-value abstraction (`localStorage`, or a server-backed store) keyed by the same three strings.
- **AppKit/UIKit**: This recipe's own platform (`NSViewController`, `NSView`, `NSButton`, `NSMenu`); nothing in this file targets UIKit/iOS. A UIKit port has no exact analogue for an `NSPopover`-anchored minimize picker or an app-modal sheet; it would present the minimize choices as a `UIMenu` on a long-press or a `UIPopoverPresentationController`-anchored sheet, and the "Settings…" dialog as a `UISheetPresentationController` detent sheet instead of `presentAsSheet`. The six probed capability protocols carry over unchanged — continuing to check with `as?` against `UIViewController` subclasses. Internally, the source wires the push-callback capabilities once in `wireContentCallbacks()`, re-evaluates control availability in `refreshControlAvailability()`, tracks the content's four edge pins in `contentEdgeConstraints`, and drops the title bar's `titleBarTrailing` constraint while docked to a rail — private mechanics specific to this file that a port reproduces by whatever means fits its own framework, not by name.
- **WinUI 3**: Recreate the pane as a `UserControl` with a two-row `Grid`: a fixed-height title row (a `GridLength` matching `PaneTitleBarView.height`, 26px-equivalent) hosting a `StackPanel` of close/minimize/zoom `Button`s at the left, a `TextBlock` with `TextTrimming="CharacterEllipsis"` for the middle-truncated title, an accessory `StackPanel`, and a trailing gear `Button` (a `FontIcon` glyph for the gearshape symbol) that opens a `ContentDialog` mirroring `OptionsDialogViewController` — an optional heading, a `StackPanel` of option rows (the spacing control plus its "Use Default" `Button`, then the content's own rows), and a single closing action. Model `clampsToContainer` by setting every child's `HorizontalAlignment="Stretch"` with `MinWidth="0"` rather than letting `Auto`-sized columns demand room, matching "the bar stops insisting on the width its contents would prefer." Minimizing to a vertical edge collapses the content row's `RowDefinition` to `Height="0"` while keeping the title row; minimizing to a horizontal edge swaps the whole `Grid` for a narrow rail `Border` (28px-equivalent width, matching `PaneMinimizedStripView.thickness`) hosting a single glyph `Button`, docked with `HorizontalAlignment="Left"` or `"Right"` per edge — the direct analogue of the source's dock-to-one-side-only rail. Persist `minimize.edge`, `zoomed`, and `spacing.override` through whatever local settings store the app uses (e.g. `ApplicationData.Current.LocalSettings`), matching the string-keyed, absent-means-default contract `PaneStateStore` defines.

## Design Decisions

**Decision**: A pane's four host-facing controls — close, minimize, zoom, restore — send requests rather than performing actions directly.
**Rationale**: The source's own doc comment states the host is free to refuse, substitute, or do something else entirely with the same click, and the pane changes its own state only when the host calls `setMinimized(to:)` / `setZoomed(_:)` back — this is what lets the same class be dropped into a container with different rules and still be correct.
**Approved**: pending

**Decision**: `clampsToContainer` only ever yields the title bar's width demand; it never restores it once set.
**Rationale**: The setter's `didSet` guards on `false` and does nothing there; the doc comment explains a pane does not stop being clamped once it starts, and that restoring would mean tracking a priority per view for a case that never happens.
**Approved**: pending

**Decision**: Resetting the spacing override deletes the stored row rather than writing the current inherited value into it.
**Rationale**: `PaneSpacingOverride.reset()`'s own comment states that overwriting with today's global would freeze it, so a later app-wide change would no longer reach the pane; deletion is what keeps "use default" meaning "inherit" rather than "freeze."
**Approved**: pending

**Decision**: Spacing-override writes are coalesced behind a 300ms timer instead of writing on every tick of a drag.
**Rationale**: The spacing steppers are continuous and produce roughly seventeen values a second; the source's comment traces the uncoalesced cost to a JSON encode plus a synchronous SQLite write on the main thread per tick, and accepts a lag no longer than the pause between two deliberate presses.
**Approved**: pending

**Decision**: `setMinimized(to:)` called before the view loads only records the edge; it does not force the view to load.
**Rationale**: The source's comment on `applyMinimizedAppearance()` explains that forcing a load would re-enter through `viewDidLoad`'s call to `restorePersistedState()`, building a second, untracked rail. Recording the edge now and applying it once at load time is lossless, because the edge and the store are already written by the time this method is called.
**Approved**: pending

**Decision**: A `JSONEncoder`/`JSONDecoder` failure while persisting or reading the spacing override (`spacing-decode-failure-is-absent`) is silently ignored rather than surfaced to any caller.
**Rationale**: `PaneStateStore`'s two methods, `setPaneStateValue(_:forKey:)` and `paneStateValue(forKey:)`, return no error value at all, so this class has no channel to report through even if it wanted to; failing open — treating unreadable or unwritable state as absent — keeps the pane opening whole rather than blocking on state it cannot use.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | Accessibility |
| [string-externalization](agenticdevelopercookbook://compliance/internationalization#string-externalization) | failed | Internationalization |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | Reliability |
| [state-recovery](agenticdevelopercookbook://compliance/reliability#state-recovery) | partial | Reliability |

Statuses rest on `PaneViewController.swift` and `PaneSpacingOverride.swift` as built: the gear and spacing-reset buttons carry real accessibility labels and identifiers, but no `NSAccessibility` notification is posted anywhere when the title, minimize state, or zoom state changes (`screen-reader-support`, partial); every user-facing string (`fallbackTitle`, the gear's tooltip/label, the "Settings…" and "Use Default" titles) is a hardcoded Swift literal with no localization key (`string-externalization`, failed); `PaneSpacingOverride`'s `JSONEncoder`/`JSONDecoder` calls are wrapped in `try?` so a corrupt or unwritable row is silently dropped rather than reported (`data-integrity`, partial); and the default `EphemeralPaneStateStore` keeps state in memory only, so nothing survives an actual process restart unless the caller injects a persistent store (`state-recovery`, partial).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: reformatted Design Decisions to the bold three-line form and added one for the swallowed spacing JSON errors; moved the cookbook guideline out of `references` into `related`; fixed the `PaneTitleBarView` cross-reference and removed leftover template-instruction text; clarified the seventh spacing protocol in the Overview and disambiguated `spacing-defaults-to-inherited`'s two cases; added named requirements and vectors for spacing clamp-on-read, spacing decode-failure, and other untested fallback paths; strengthened weak vectors and folded an unverifiable one into its pair; restated internals-coupled requirements and vectors as observable behavior; rebuilt the Compliance table against real catalog checks (compliance_fix.py cleanup) |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
