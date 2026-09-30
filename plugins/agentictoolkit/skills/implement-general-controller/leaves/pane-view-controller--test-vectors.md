<!-- leaf: implement-general-controller/pane-view-controller--test-vectors · source: pane-view-controller.md -->

# PaneViewController

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
