<!-- leaf: implement-composable-tabs/pane-view-controller--test-vectors · source: composable-tabs-pane-view-controller.md -->

# ComposableTabsPaneViewController

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| ctpvc-001 | nodeid-identity | Read `nodeID` immediately after construction and again after several lifecycle callbacks | Both reads return the same UUID passed to `init` |
| ctpvc-002 | pane-number-identity | Read `paneNumber` after construction | Equals the value passed to `init` |
| ctpvc-003 | view-id-identity | Read `viewID` after construction | Equals the value passed to `init` |
| ctpvc-004 | working-directory-identity | Read `workingDirectory` after construction | Equals the URL passed to `init` |
| ctpvc-005 | coder-init-unsupported | Call `init(coder:)` | Call `fatalError`s (process traps rather than returning) |
| ctpvc-006 | content-from-registry | A pane whose `project` is alive and `viewID` is registered | The content view controller returned equals what `registry.makeContentViewController(for:nodeID:project:workingDirectory:paneNumber:ownerNodeID:treeID:)` returns for those exact arguments |
| ctpvc-007 | content-nil-without-project | `project` has been deallocated before `loadView()` runs | `contentViewController` is nil; the registry is never consulted |
| ctpvc-008 | content-layout-override-precedence | `layoutOverride` is set to a layout whose registry differs from `project.layout`'s | Content is built from `layoutOverride`'s registry, not `project.layout`'s |
| ctpvc-009 | container-draws-active-outline | Load the pane's view | `view` is a `ComposableTabsPaneBackgroundView` whose `nodeID` equals the pane's `nodeID` |
| ctpvc-010 | content-inset-matches-border | Load the pane's view | The title bar's top/leading constraints and the content's trailing/bottom constraints all use a constant of 2pt |
| ctpvc-011 | fallback-title-from-registry | Content that does not implement `PaneTitleProviding`; `viewID` registered with display name "Terminal" | `fallbackTitle` (and therefore `resolvedTitle`) is "Terminal" |
| ctpvc-012 | fallback-title-placeholder-layout | `layoutOverride` nil, `project` deallocated | `fallbackTitle` returns a name resolved from a placeholder-only layout rather than crashing |
| ctpvc-013 | accessibility-id-from-view-id | `viewID.rawValue` = "whippet.terminal", `paneIndex` nil | `paneAccessibilityIdentifier` == "pane.terminal" |
| ctpvc-014 | accessibility-id-includes-pane-index | Same as above, `paneIndex` = 2 | `paneAccessibilityIdentifier` == "pane.terminal.2" |
| ctpvc-015 | pane-index-update-is-idempotent | Call `assignPaneIndex(3)` twice in a row on a loaded view, with a spy/KVO observer on the container view's `setAccessibilityIdentifier` | The observer records exactly one call, not two |
| ctpvc-016 | pane-index-update-refreshes-identifier | Call `assignPaneIndex(1)` then `assignPaneIndex(2)` on a loaded view | The container's accessibility identifier updates to reflect index 2 |
| ctpvc-017 | arrange-mode-change-scoped-to-own-window | Post the arrange-mode change notification with a different window as its object | This pane's overlay state is unchanged |
| ctpvc-018 | layout-change-refreshes-overlay-globally | Pane A has an overlay installed in window 1; post the layout-change notification from a change made in window 2 | Pane A's overlay `refreshAvailability()` runs |
| ctpvc-019 | window-close-removes-overlay | Overlay installed; post `NSWindow.willCloseNotification` for the pane's own window | The overlay is removed and the key monitor is torn down |
| ctpvc-020 | view-did-appear-reevaluates-overlay | Arrange mode already enabled for the window before `viewDidAppear()` runs (e.g. after a move rebuild) | The overlay is installed by the time `viewDidAppear()` returns |
| ctpvc-021 | overlay-tracks-arrange-mode | Toggle arrange mode on, then off, for the pane's window | Overlay is installed on enable, removed on disable |
| ctpvc-022 | overlay-install-idempotent | Call the overlay-install path twice while arrange mode stays enabled | Exactly one overlay view exists; the second call only calls `refreshAvailability()` |
| ctpvc-023 | overlay-inset-from-border | Overlay installed | Its four edge constraints each use a constant of 2pt from the pane's view |
| ctpvc-024 | overlay-shows-pane-name | `resolvedTitle` == "Terminal" when the overlay installs | Overlay's `paneName` == "Terminal" |
| ctpvc-025 | overlay-add-availability | Enclosing split reports zero legal, non-placeholder insertions | Overlay's Add control is disabled |
| ctpvc-026 | overlay-remove-availability | Enclosing split's `canRemoveLeaf(self)` returns false | Overlay's Remove control is disabled |
| ctpvc-027 | overlay-move-availability | Enclosing split's `availableMoveDirections(for:)` returns `{.left, .right}` | Overlay offers exactly Left and Right as enabled moves |
| ctpvc-028 | overlay-done-disables-arrange-mode | Activate the overlay's Done control | `ComposableTabsArrangeMode.shared.isEnabled(in: window)` becomes false |
| ctpvc-029 | overlay-installs-key-monitor | Install, then remove, the overlay | A key monitor exists after install and is nil after removal |
| ctpvc-030 | exit-keys-disable-arrange-mode | Arrange mode enabled in the pane's window; post a keyDown with key code 53 (Escape) to that window | Arrange mode becomes disabled; the event is consumed (not passed through) |
| ctpvc-030b | exit-keys-disable-arrange-mode | Same setup; post a keyDown with key code 36 (Return) | Arrange mode becomes disabled; the event is consumed |
| ctpvc-030c | exit-keys-disable-arrange-mode | Same setup; post a keyDown with key code 76 (Enter) | Arrange mode becomes disabled; the event is consumed |
| ctpvc-031 | arrow-key-moves-active-pane-only | Arrange mode enabled; this pane is the window's active pane; post keyDown with key code 126 (Up/above) | `move(.above)` runs and the event is consumed |
| ctpvc-031b | arrow-key-moves-active-pane-only | Same setup, but this pane is NOT the window's active pane | No move occurs; the event is not consumed |
| ctpvc-032 | key-monitor-ignores-other-windows | Post a matching keyDown whose `event.window` is a different window than the pane's | No action taken; event left unconsumed |
| ctpvc-033 | move-delegates-to-split | Request a move to `.right`; enclosing split's `move(self, .right)` returns true | `split.move(self, .right)` is called with that exact direction, and no refusal is announced |
| ctpvc-034 | move-refusal-announced | Enclosing split's `move(self, .right)` returns false | `RefusalFeedback.announce()` is called exactly once |
| ctpvc-035 | gear-menu-move-submenu | Call `makeMenuItems()` | Returns exactly one item titled "Move" whose submenu has four items, one per `Direction.allCases` |
| ctpvc-036 | gear-menu-move-enablement | All four submenu items disabled | The "Move" item itself is disabled |
| ctpvc-036b | gear-menu-move-enablement | Exactly one of the four submenu items enabled, the rest disabled | The "Move" item itself is enabled |
| ctpvc-037 | add-choices-exclude-placeholder | Enclosing split's `allowedInsertions(beside:)` includes an insertion with `viewID == .placeholder` | That insertion is excluded from the computed choices |
| ctpvc-038 | add-choices-deduplicated | `allowedInsertions(beside:)` reports the same non-placeholder view id insertable in two directions | The computed choices contain exactly one entry for that view id |
| ctpvc-039 | add-refused-when-empty | Computed choices are empty | `presentAddSheet()` announces a refusal and presents no picker |
| ctpvc-040 | add-picker-presentation | Overlay installed with a non-nil `addButtonView` | Picker is presented as a popover anchored to that view |
| ctpvc-040b | add-picker-presentation | No overlay installed (`arrangeOverlay` is nil) | Picker is presented as a sheet |
| ctpvc-041 | add-selection-splits-pane | Picker returns `(viewID: X, direction: .right)` | Enclosing split's `split(self, adding: X, direction: .right)` is called |
| ctpvc-042 | remove-refused-when-not-removable | Enclosing split's `canRemoveLeaf(self)` is false | `confirmAndRemove()` announces a refusal and does not remove the pane |
| ctpvc-043 | remove-skips-confirmation-when-silent | Content is not `PaneContentRemovalConfirmation`, or its `removalConfirmationMessage` is nil | The pane is removed immediately with no alert shown |
| ctpvc-044 | remove-confirms-when-content-warns | Content's `removalConfirmationMessage` == "Unsaved changes will be lost." | An `NSAlert` is shown titled "Remove this pane?" with that message and Remove/Cancel buttons |
| ctpvc-045 | remove-confirmation-modal-without-window | Pane has no window; user picks the first (Remove) button in `runModal()` | The pane is removed |
| ctpvc-045b | remove-confirmation-modal-without-window | Pane has no window; user picks Cancel | The pane is not removed |
| ctpvc-046 | remove-confirmation-sheet-reresolves-split | Pane has a window; the enclosing split changes while the confirmation sheet is up; user picks Remove | The pane removes itself from the split resolved at sheet-completion time, not the one captured before the sheet opened |
| ctpvc-047 | removal-notifies-content-teardown | Content implements `PaneContentTeardown`; call `paneWillBeRemoved()` | The overlay is removed and `paneContentWillBeDiscarded()` is called on the content |
| ctpvc-048 | state-owner-retargets-store | Set `stateOwnerNodeID = X` | The pane's `ProjectPaneStateStore.ownerNodeID` becomes `X` |
| ctpvc-049 | contains-first-responder-unloaded | View not yet loaded; read `containsFirstResponder` | Returns `false`; the view is not force-loaded as a side effect |
