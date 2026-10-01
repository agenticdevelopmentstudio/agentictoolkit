---
id: 4d75a371-181e-4d80-a16b-022d37dc0d48
title: Composable Tabs Leaf Pane
domain: agentictoolkit://cookbook/ui/layout/composable-tabs/leaf-pane-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A leaf pane in a composable-tabs split tree that hosts registry-vended
  content, draws the active-pane outline, offers an arrange-mode overlay, and
  provides move/add/remove actions and pane accessibility identifiers.
platforms:
- swift
- macos
tags:
- composable-tabs
- pane
- view-controller
- accessibility
depends-on:
- agentictoolkit://cookbook/ui/layout/pane-view
related:
- agentictoolkit://cookbook/ui/layout/composable-tabs/arrange-overlay-view
- agentictoolkit://cookbook/ui/layout/composable-tabs/active-pane
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
references: []
approved-by: ''
approved-date: ''
---

# Composable Tabs Leaf Pane

## Overview

The composable-tabs leaf pane is one leaf of a composable-tabs split tree:
registry-vended content under a pane title bar, plus — while arrange mode is
on — a dimming scrim and a small toolbar that let the user reshape the
layout around it.

It builds on a shared pane concept that owns the common chrome — the title
bar, the gear button, the minimize/zoom/close controls, and per-pane
spacing — for every kind of pane in the framework, not only composable-tabs
leaves. That shared pane chrome is out of this recipe's scope; only the
three things this leaf adds are documented here: which registry vends its
content, the backdrop that draws the active-pane outline, and what arrange
mode does over the top of an otherwise ordinary pane. The layout can be
rearranged two ways that answer different needs: the gear menu always
carries a Move submenu for a user who knows exactly which pane goes where,
and arrange mode dims the content and puts the same four directions in a
central toolbar for a user who is looking at the window deciding. Both read
the same underlying move-menu source, so there is one answer to what Move
means.

## Behavioral Requirements

### Identity & construction

- **nodeid-identity**: The pane MUST expose `nodeID`, a UUID given at
  construction, unchanged for the pane's lifetime.
- **pane-number-identity**: The pane MUST expose `paneNumber`, an integer
  given at construction, unchanged for the pane's lifetime.
- **view-id-identity**: The pane MUST expose `viewID`, the view identifier
  given at construction, unchanged for the pane's lifetime.
- **working-directory-identity**: The pane MUST expose `workingDirectory`,
  the file-system location given at construction, unchanged for the pane's
  lifetime, shared by every pane in the same split tree.

### Content hosting

- **content-from-registry**: The pane MUST build its content by asking the
  resolved layout's registry for content keyed by `viewID`, passing
  `nodeID`, the project, `workingDirectory`, `paneNumber`,
  `stateOwnerNodeID`, and the enclosing tab's root split node id.
- **content-nil-without-project**: The pane MUST return no content, without
  consulting any registry, when the project it depends on is no longer
  available.
- **content-layout-override-precedence**: The pane MUST resolve content
  against `layoutOverride`'s registry when `layoutOverride` is set, and
  against the project's own layout registry otherwise.
- **container-draws-active-outline**: The pane MUST use a container view
  keyed by `nodeID` that draws the active-pane outline described below.
- **content-inset-matches-border**: The pane MUST hold its title bar and
  content off the container's edges by the border inset (2pt), so the
  chrome never overlaps the active-pane border. This is the one place this
  inset is defined as a literal; every other requirement and the Appearance
  section below refer to it by name rather than repeating the number.

### Naming & identity strings

- **fallback-title-from-registry**: `fallbackTitle` MUST return the display
  name the resolved layout's registry has registered for `viewID`.
- **fallback-title-placeholder-layout**: When `layoutOverride` is unset and
  the project has already released, `fallbackTitle` MUST resolve the
  display name against a placeholder-only layout rather than crashing or
  returning an empty string.
- **accessibility-id-from-view-id**: `paneAccessibilityIdentifier` MUST be
  `"pane."` followed by the kebab-case slug of the last dot-separated
  component of `viewID`'s raw value.
- **accessibility-id-includes-pane-index**: When a pane index has been
  assigned, `paneAccessibilityIdentifier` MUST append `".<index>"` to the
  type identifier.
- **pane-index-update-is-idempotent**: Assigning a pane index MUST leave
  the container view's accessibility identifier untouched when the new
  index equals the index already assigned.
- **pane-index-update-refreshes-identifier**: Assigning a pane index MUST
  update the container view's accessibility identifier immediately when the
  index changes and the view is already loaded, and MUST NOT force the view
  to load when it is not.

### Lifecycle notifications

- **arrange-mode-change-scoped-to-own-window**: The pane MUST show or hide
  its arrange overlay in response to arrange mode's change notification
  only when that notification's window is this pane's own window.
- **layout-change-refreshes-overlay-globally**: The pane MUST refresh its
  installed arrange overlay's availability whenever any tab's layout
  changes, regardless of which window that change occurred in.
- **window-close-removes-overlay**: The pane MUST remove its arrange
  overlay when its own window closes.
- **pane-appearance-reevaluates-overlay**: The pane MUST re-evaluate
  whether the arrange overlay should be installed each time its view
  appears.

### Arrange overlay

- **overlay-tracks-arrange-mode**: The pane MUST install the arrange
  overlay when arrange mode is enabled for its window, and MUST remove it
  when arrange mode is disabled.
- **overlay-install-idempotent**: Installing the overlay when one already
  exists MUST NOT create a second overlay; it MUST instead refresh the
  existing overlay's availability.
- **overlay-inset-from-border**: The overlay MUST be inset from every edge
  of the pane by the border inset (see **content-inset-matches-border**),
  so it sits above content but inside the border.
- **overlay-shows-pane-name**: The overlay MUST display the pane's resolved
  title.
- **overlay-add-availability**: The overlay's Add control MUST report
  available exactly when at least one distinct, non-placeholder view id can
  legally be inserted beside this pane.
- **overlay-remove-availability**: The overlay's Remove control MUST report
  available exactly when the enclosing split reports this pane may be
  removed as a leaf.
- **overlay-move-availability**: The overlay's Move control MUST offer
  exactly the set of directions the enclosing split reports as legal for
  this pane.
- **overlay-done-disables-arrange-mode**: Activating the overlay's Done
  control MUST disable arrange mode for the pane's window.
- **overlay-installs-key-monitor**: Installing the overlay MUST install a
  mechanism that intercepts key-down events before the pane's content sees
  them; removing the overlay MUST remove that mechanism.

### Keyboard handling

- **exit-keys-disable-arrange-mode**: The pane MUST disable arrange mode
  for its window and consume the key event when Return, Enter, or Escape
  is pressed while arrange mode is enabled in the pane's own window.
- **arrow-key-moves-active-pane-only**: While arrange mode is enabled in
  the pane's own window, an arrow key matching one of the four move
  directions (Left, Right, Up, Down) MUST move this pane and consume the
  event only when this pane is that window's active pane (per the
  active-pane tracker); it MUST NOT act, and MUST NOT consume the event,
  otherwise.
- **key-monitor-ignores-other-windows**: The pane's key-event interception
  MUST take no action and MUST leave the event unconsumed when the event's
  window is not the pane's own window, or arrange mode is not enabled in
  that window.

### Move / gear menu

- **move-delegates-to-split**: Requesting a move MUST ask the enclosing
  split to move this pane in the given direction.
- **move-refusal-announced**: The pane MUST announce a refusal and take no
  other action when there is no enclosing split, or the enclosing split
  refuses the move.
- **gear-menu-move-submenu**: The gear menu MUST include exactly one "Move"
  item carrying the four move directions as its submenu, built from the
  same move-menu items the arrange overlay uses.
- **gear-menu-move-enablement**: The "Move" item MUST be enabled exactly
  when at least one of its four submenu items is enabled.

### Add

- **add-choices-exclude-placeholder**: The computed set of addable choices
  MUST exclude the placeholder view id.
- **add-choices-deduplicated**: The computed set of addable choices MUST
  contain at most one entry per distinct view id, even when the enclosing
  split reports that id insertable in more than one direction.
- **add-refused-when-empty**: Requesting Add MUST announce a refusal and
  MUST NOT present a picker when there are no addable choices.
- **add-picker-presentation**: The pane MUST present the add picker as a
  popover anchored to the overlay's Add button when the overlay is
  installed, and as a sheet when it is not.
- **add-selection-splits-pane**: Choosing a view id and direction from the
  add picker MUST ask the enclosing split to split this pane, inserting the
  chosen view id in the chosen direction.

### Remove

- **remove-refused-when-not-removable**: Requesting Remove MUST announce a
  refusal and MUST NOT remove the pane when the enclosing split reports
  this pane cannot be removed as a leaf.
- **remove-skips-confirmation-when-silent**: The pane MUST remove itself
  immediately, without a confirmation dialog, when its content supplies no
  removal-confirmation message.
- **remove-confirms-when-content-warns**: The pane MUST present a warning
  alert, titled "Remove this pane?" with the content's message and
  Remove/Cancel buttons, before removing, when its content supplies a
  removal-confirmation message.
- **remove-confirmation-modal-without-window**: The pane MUST run the
  confirmation alert as a blocking modal, and remove itself only if Remove
  is chosen, when it has no window.
- **remove-confirmation-sheet-reresolves-split**: The pane MUST present the
  confirmation alert as a window-attached sheet when it has a window, and
  MUST re-resolve the enclosing split at the sheet's completion — rather
  than reusing the split resolved before the sheet opened — before
  removing.

### Teardown & state

- **removal-notifies-content-teardown**: When the pane is about to be
  removed, it MUST remove the arrange overlay and MUST notify content
  implementing the teardown capability that its content will be discarded.
- **state-owner-retargets-store**: Setting `stateOwnerNodeID` MUST retarget
  the pane's persisted-state store to attribute state to the new value.
- **focus-check-skips-unloaded-view**: Checking whether this pane contains
  the input focus MUST report false without loading the pane's view when
  the view has not yet been loaded.
- **focus-check-walks-hierarchy**: When the view is loaded, checking
  whether this pane contains the input focus MUST report true exactly when
  the window's focused element is the pane's view or a descendant of it.
- **title-bar-bottom-constant**: `titleBarBottom` MUST equal the border
  inset (see **content-inset-matches-border**) plus the title bar's fixed
  26pt height (28pt total).

### Appearance fact

- **active-pane-cue-is-color-only**: As built, the pane's backdrop
  distinguishes the active pane from an inactive one by border color alone
  (`projectActivePaneOutline` vs. `projectPaneOutline`), with a constant
  2pt border width in both states. This describes the current
  implementation; it is not a constraint against adding a secondary cue —
  see Differentiate Without Color in Accessibility Options, which records
  that no such cue is implemented.

## Appearance

- **Corner radius**: None on the pane's own backdrop or title bar. The
  arrange-mode toolbar uses an 8pt corner radius.
- **Padding**: Content and title bar are held off the container's edges by
  the border inset (2pt — see **content-inset-matches-border**). The
  arrange overlay is inset from the pane by that same border inset on
  every side. Inside the overlay's toolbar, the button stack is inset 8pt
  on every side and the buttons are spaced 8pt apart; the pane-name label
  and the toolbar are stacked with 10pt spacing between them.
- **Font**: Not set directly in this file. The overlay's pane-name label
  uses a semantic heading text style resolved by the theme system, not a
  literal point size.
- **Background**: The pane's own fill uses the theme's window-background
  role, drawn inside the pane's container view. While arranging, the
  scrim's background is the window-background role at 72% alpha (dims
  content toward the window background rather than toward black, so a
  light theme stays light); the toolbar's background is the theme's
  elevated-surface role.
- **Foreground/Text**: The overlay's pane-name label uses the `primaryText`
  semantic role. Border colors are theme-resolved semantic tokens, not
  literal values: `projectActivePaneOutline` for the active pane,
  `projectPaneOutline` otherwise.
- **Border**: The pane backdrop draws a constant 2pt border on every pane,
  colored per the active-pane rule above. The arrange toolbar draws a 1pt
  border in the `border` semantic color.
- **Shadow**: None. No shadow is drawn on the container, the arrange
  overlay, or its toolbar anywhere in these sources.
- **Min/Max size**: The overlay's pane-name label is constrained to at most
  (overlay width − 16pt), so a long name is clipped rather than widening
  the pane. No other min/max size is set by this file; the pane's own
  bounds are governed by the enclosing split, which is out of scope here.

## States

| State | Appearance change |
|-------|------------------|
| Default | — |
| Pressed | Not applicable: the pane container itself has no pressed state; its individual controls (the gear button, the overlay's Add/Remove/Move/Done buttons) have their own, and those belong to the components that draw them. |
| Disabled | Not applicable: a pane is never disabled as a whole. Individual actions (Add, Remove, each move direction, the gear's Move item) are independently enabled or disabled — see Behavioral Requirements. |
| Focused | Not applicable as a visual state of this pane; the closest analog is "Active pane" below, which is a pane-level concept driven by the active-pane tracker, not an input-focus ring. |
| Loading | Not applicable: any loading state belongs to the hosted content, which has its own recipe; this class has no loading indicator of its own. |
| Active pane | 2pt border in the theme's active-pane accent color (`projectActivePaneOutline`), shown when the window has focus (or an attached confirmation dialog has focus) and this pane is that window's active pane. |
| Inactive pane | 2pt border in the theme's hairline outline color (`projectPaneOutline`). |
| Arranging | Content is dimmed behind a 72%-alpha scrim with a centered toolbar (pane name, Add, Remove, Move, Done); a key-event interception is installed. Exiting via Return, Enter, Escape, or Done removes the scrim and the interception. |

## Accessibility

- **Role/trait**: The container view carries an accessibility identifier
  equal to `paneAccessibilityIdentifier` (set during the pane's initial
  load); it is a plain view with no explicit accessibility-role override in
  this file. The gear's "Move" menu item carries the identifier
  `pane.options.move`; each of its four submenu items carries
  `pane.options.move.<direction-name-lowercased>` (`left`, `right`, `up`,
  `down`). The arrange overlay's own controls (`composable-tabs.arrange.*`)
  are identified inside the arrange overlay itself, which this pane
  installs but does not itself label.
- **Label requirements**: Each move-menu item's icon carries an
  accessibility description equal to the direction's movement name
  ("Left", "Right", "Up", "Down"). The overlay's Add/Remove/Done buttons
  carry accessibility descriptions equal to their titles ("Add", "Remove",
  "Done"). The gear button's own "Pane Options" label comes from the
  shared pane chrome, not from this leaf pane.
- **Announce state changes**: The only explicit state-change announcement
  this component performs is a refusal announcement (default: a system
  beep) on every refused action — a blocked move, an Add with no choices,
  a Remove that is not currently legal. Neither an active-pane change nor
  arrange mode turning on or off posts any accessibility
  change-notification, so a screen reader user has no non-visual cue that
  the active pane changed or that arrange mode started or stopped.
- **Minimum tap target**: Not overridden in this file. The gear button and
  the overlay's Add/Remove/Move/Done buttons are standard buttons sized by
  the platform's default intrinsic content size; touch tap-target minimum
  guidance does not apply here, since this is a pointer/keyboard-driven
  toolbar rather than a touch surface, and this source sets no explicit
  minimum of its own.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| ctpvc-001 | nodeid-identity | Read `nodeID` immediately after construction and again after several lifecycle callbacks | Both reads return the same UUID passed at construction |
| ctpvc-002 | pane-number-identity | Read `paneNumber` after construction | Equals the value passed at construction |
| ctpvc-003 | view-id-identity | Read `viewID` after construction | Equals the value passed at construction |
| ctpvc-004 | working-directory-identity | Read `workingDirectory` after construction | Equals the location passed at construction |
| ctpvc-006 | content-from-registry | A pane whose project is alive and `viewID` is registered | The content returned equals what the registry returns when asked for that view id with the same node id, project, working directory, pane number, state-owner node id, and root split node id |
| ctpvc-007 | content-nil-without-project | The project this pane depends on is no longer available before the view loads | No content is returned; the registry is never consulted |
| ctpvc-008 | content-layout-override-precedence | `layoutOverride` is set to a layout whose registry differs from the project's own layout's | Content is built from `layoutOverride`'s registry, not the project's own |
| ctpvc-009 | container-draws-active-outline | Load the pane's view | The pane's view is a container view whose `nodeID` equals the pane's `nodeID` |
| ctpvc-010 | content-inset-matches-border | Load the pane's view | The title bar's top/leading constraints and the content's trailing/bottom constraints all use a constant of 2pt |
| ctpvc-011 | fallback-title-from-registry | Content that does not provide its own title; `viewID` registered with display name "Terminal" | `fallbackTitle` (and therefore the resolved title) is "Terminal" |
| ctpvc-012 | fallback-title-placeholder-layout | `layoutOverride` unset, the project no longer available | `fallbackTitle` returns a name resolved from a placeholder-only layout rather than crashing |
| ctpvc-013 | accessibility-id-from-view-id | `viewID`'s raw value is "whippet.terminal", pane index unset | `paneAccessibilityIdentifier` == "pane.terminal" |
| ctpvc-014 | accessibility-id-includes-pane-index | Same as above, pane index = 2 | `paneAccessibilityIdentifier` == "pane.terminal.2" |
| ctpvc-015 | pane-index-update-is-idempotent | Assign the pane index to 3 twice in a row on a loaded view, while observing writes to the container view's accessibility identifier | The observer records exactly one write, not two |
| ctpvc-016 | pane-index-update-refreshes-identifier | Assign the pane index to 1, then to 2, on a loaded view | The container's accessibility identifier updates to reflect index 2 |
| ctpvc-017 | arrange-mode-change-scoped-to-own-window | Post the arrange-mode change notification with a different window as its object | This pane's overlay state is unchanged |
| ctpvc-018 | layout-change-refreshes-overlay-globally | Pane A has an overlay installed in window 1; post the layout-change notification from a change made in window 2 | Pane A's overlay availability is refreshed |
| ctpvc-019 | window-close-removes-overlay | Overlay installed; close the pane's own window | The overlay is removed and its key-event interception is torn down |
| ctpvc-020 | pane-appearance-reevaluates-overlay | Arrange mode already enabled for the window before the view appears (e.g. after a move rebuild) | The overlay is installed by the time the view finishes appearing |
| ctpvc-021 | overlay-tracks-arrange-mode | Toggle arrange mode on, then off, for the pane's window | Overlay is installed on enable, removed on disable |
| ctpvc-022 | overlay-install-idempotent | Install the overlay twice in a row while arrange mode stays enabled | Exactly one overlay view exists; the second call only refreshes availability |
| ctpvc-023 | overlay-inset-from-border | Overlay installed | Its four edge constraints each use a constant of 2pt from the pane's view |
| ctpvc-024 | overlay-shows-pane-name | The pane's resolved title == "Terminal" when the overlay installs | Overlay's `paneName` == "Terminal" |
| ctpvc-025 | overlay-add-availability | Enclosing split reports zero legal, non-placeholder insertions | Overlay's Add control is disabled |
| ctpvc-026 | overlay-remove-availability | Enclosing split reports this pane cannot be removed as a leaf | Overlay's Remove control is disabled |
| ctpvc-027 | overlay-move-availability | Enclosing split reports Left and Right as the only legal move directions for this pane | Overlay offers exactly Left and Right as enabled moves |
| ctpvc-028 | overlay-done-disables-arrange-mode | Activate the overlay's Done control | Arrange mode becomes disabled for the pane's window |
| ctpvc-029 | overlay-installs-key-monitor | Install, then remove, the overlay | Key-event interception exists after install and is removed after removal |
| ctpvc-030 | exit-keys-disable-arrange-mode | Arrange mode enabled in the pane's window; press the Escape key while that window has focus | Arrange mode becomes disabled; the event is consumed (not passed through) |
| ctpvc-030b | exit-keys-disable-arrange-mode | Same setup; press the Return key | Arrange mode becomes disabled; the event is consumed |
| ctpvc-030c | exit-keys-disable-arrange-mode | Same setup; press the Enter key | Arrange mode becomes disabled; the event is consumed |
| ctpvc-031 | arrow-key-moves-active-pane-only | Arrange mode enabled; this pane is the window's active pane; press the Up arrow key | The pane moves up and the event is consumed |
| ctpvc-031b | arrow-key-moves-active-pane-only | Same setup, but this pane is NOT the window's active pane | No move occurs; the event is not consumed |
| ctpvc-032 | key-monitor-ignores-other-windows | Press a matching key while a different window than the pane's has focus | No action taken; event left unconsumed |
| ctpvc-033 | move-delegates-to-split | Request a move to the right; the enclosing split allows it | The enclosing split is asked to move this pane to the right, and no refusal is announced |
| ctpvc-034 | move-refusal-announced | Enclosing split refuses a move to the right | A refusal is announced exactly once |
| ctpvc-035 | gear-menu-move-submenu | Build the gear menu's items | Returns exactly one item titled "Move" whose submenu has four items, one per direction |
| ctpvc-036 | gear-menu-move-enablement | All four submenu items disabled | The "Move" item itself is disabled |
| ctpvc-036b | gear-menu-move-enablement | Exactly one of the four submenu items enabled, the rest disabled | The "Move" item itself is enabled |
| ctpvc-037 | add-choices-exclude-placeholder | Enclosing split reports a legal insertion for the placeholder view id | That insertion is excluded from the computed choices |
| ctpvc-038 | add-choices-deduplicated | Enclosing split reports the same non-placeholder view id insertable in two directions | The computed choices contain exactly one entry for that view id |
| ctpvc-039 | add-refused-when-empty | Computed choices are empty | Requesting Add announces a refusal and presents no picker |
| ctpvc-040 | add-picker-presentation | Overlay installed, exposing an Add-button anchor | Picker is presented as a popover anchored to that view |
| ctpvc-040b | add-picker-presentation | No overlay installed | Picker is presented as a sheet |
| ctpvc-041 | add-selection-splits-pane | Picker returns a chosen view id and the right direction | Enclosing split is asked to split this pane, inserting that view id to the right |
| ctpvc-042 | remove-refused-when-not-removable | Enclosing split reports this pane cannot be removed as a leaf | Requesting Remove announces a refusal and does not remove the pane |
| ctpvc-043 | remove-skips-confirmation-when-silent | Content offers no removal-confirmation message | The pane is removed immediately with no alert shown |
| ctpvc-044 | remove-confirms-when-content-warns | Content's removal-confirmation message is "Unsaved changes will be lost." | A warning alert is shown titled "Remove this pane?" with that message and Remove/Cancel buttons |
| ctpvc-045 | remove-confirmation-modal-without-window | Pane has no window; the user picks the first (Remove) button | The pane is removed |
| ctpvc-045b | remove-confirmation-modal-without-window | Pane has no window; user picks Cancel | The pane is not removed |
| ctpvc-046 | remove-confirmation-sheet-reresolves-split | Pane has a window; the enclosing split changes while the confirmation sheet is up; user picks Remove | The pane removes itself from the split resolved at sheet-completion time, not the one captured before the sheet opened |
| ctpvc-047 | removal-notifies-content-teardown | Content implements the teardown capability; the pane is removed | The overlay is removed and the content is notified that it will be discarded |
| ctpvc-048 | state-owner-retargets-store | Set `stateOwnerNodeID = X` | The pane's persisted-state store is retargeted to attribute state to `X` |
| ctpvc-049 | focus-check-skips-unloaded-view | View not yet loaded; check whether this pane contains the input focus | Returns false; the view is not force-loaded as a side effect |
| ctpvc-050 | focus-check-walks-hierarchy | View loaded; the window's focused element is nested inside this pane's view | The focus-containment check returns true |
| ctpvc-050b | focus-check-walks-hierarchy | View loaded; the window's focused element belongs to a different pane | The focus-containment check returns false |
| ctpvc-051 | title-bar-bottom-constant | Read `titleBarBottom` | Equals 28 (2pt border inset + 26pt title bar height) |
| ctpvc-052 | active-pane-cue-is-color-only | Compare the backdrop's drawn border for the active pane vs. an inactive one | `borderWidth` is 2 in both; only `borderColor` differs |

## Edge Cases

- **Null/empty input**: The project a pane depends on may become
  unavailable before the view loads — content resolution returns no
  content rather than crashing (MUST, see `content-nil-without-project`).
  `layoutOverride` unset — content and the pane's display name fall back
  to the project's own layout, and the display name falls back further to
  a placeholder-only layout if the project is also gone. Computed Add
  choices empty — requesting Add refuses rather than presenting an empty
  picker (MUST, see `add-refused-when-empty`).
- **Boundary values**: A pane index left unset is the common case; an
  assigned index changes the accessibility identifier's shape (MUST, see
  `accessibility-id-includes-pane-index`). A tab with exactly one pane
  makes the enclosing split refuse removal of that pane. A pane at the top
  of a column has no Up direction available, so the corresponding
  gear-menu and overlay controls are disabled rather than absent.
- **Concurrent access**: This component confines all reads and writes of
  its mutable state (the pane index, the installed overlay, its
  subscriptions, its key-event interception, and the state-owner
  identifier) to a single thread, so there is no concurrent-access hazard
  by construction. The one boundary crossing is the key-event
  interception's own callback, which the platform may invoke off that
  thread; the source re-enters the component's thread to run its
  key-handling logic and only a plain boolean crosses back out, since the
  underlying key-event value itself is not safe to pass between threads.
- **Error states**: When the enclosing split refuses a move, reports Add
  has no legal choices, or reports Remove is not currently legal, the only
  surfaced error is a refusal announcement (default: a system beep) —
  there is no inline error message, banner, or thrown error anywhere in
  this file for these cases, and the recipe describes that as-is rather
  than as an idealized richer error UI.
- **Offline or disconnected state**: Not applicable. This component makes
  no network requests; its only persistence (pane chrome state, through
  the shared pane state store) goes into the project's local database, and
  nothing in this file or its immediate collaborators references a network
  resource.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewID` | view identifier | required at init | Which registered content kind this pane hosts. |
| `paneNumber` | integer | required at init | Identifying number passed through to the registry when building content. |
| `workingDirectory` | file-system location | required at init | The directory this pane's content is rooted in; shared by every pane in the same split tree. |
| `layoutOverride` | layout override or unset | unset | Overrides the project's own layout (and its registry) when resolving this pane's content and display name; set by the enclosing split when it is itself overridden, e.g. a pane nested inside another pane's tree. |
| `stateOwnerNodeID` | UUID or unset | unset | Redirects the pane's persisted chrome state to another layout node's row family, for a pane nested inside another pane's content. |
| `thicknessFraction` | number or unset | unset | The fraction of the enclosing split's thickness this pane should occupy; read by the enclosing split, not consulted within this file. |

## Deep Linking

Not applicable: a pane is chrome inside a project window's layout tree,
built entirely from an in-tree node id/view id/project triple handed to it
by the enclosing split. No URL scheme, universal link, or platform
deep-link handling appears anywhere in this file or its immediate
collaborators.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal string) | "Move" | Title of the gear-menu submenu. |
| (none — literal string) | "Left" / "Right" / "Up" / "Down" | Move-submenu item titles and accessibility descriptions. |
| (none — literal string) | "Add" / "Remove" / "Done" | Arrange-overlay button titles and accessibility descriptions. |
| (none — literal string) | "Remove this pane?" | Confirmation alert title when removing the pane. |
| (none — literal string) | "Remove" / "Cancel" | Confirmation alert button titles. |

No localization key or string-catalog mechanism exists for any user-facing
string in this file or its move-menu/arrange-overlay collaborators — every
string above is a hardcoded English literal.

## Accessibility Options

Document which accessibility display options this component responds to:

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: overlay install/removal and content dim/undim are immediate view add/remove operations; no animation context, layer animation, or transition appears anywhere in this file. |
| Increase Contrast | Not observed in this file: pane border and fill colors are resolved through the theme system's semantic-role lookup (e.g. the `projectActivePaneOutline` role), so any contrast adaptation belongs to the theme system, out of this ingredient's scope. |
| Differentiate Without Color | Not implemented: the active/inactive distinction is carried by border color alone (`projectActivePaneOutline` vs. `projectPaneOutline`; see the **active-pane-cue-is-color-only** requirement), with no accompanying change in border width, shape, or label, and the source never queries the platform's differentiate-without-color accessibility setting. |

## Feature Flags

Not applicable: no feature-flag or remote-config lookup of any kind appears
in this file or its immediate collaborators.

## Analytics

Not applicable: no analytics event is emitted anywhere in this file or its
immediate collaborators (the move menu, the arrange overlay). An unrelated
logger defined elsewhere belongs to the content registry, not to this pane,
and is out of this recipe's scope.

## Privacy

- **Data collected**: This pane introduces no new data collection. It
  contributes the pane's chrome state (minimize edge, zoomed flag —
  persisted by the shared pane chrome) and, when `stateOwnerNodeID` is
  set, redirects which layout node that state is attributed to. No
  personal or sensitive data is read or written by this file.
- **Storage**: Local only, via the project's own database, through the
  shared project workspace and pane state store. This file holds no
  storage of its own.
- **Transmission**: None. No network call appears anywhere in this file or
  its immediate collaborators.
- **Retention**: Tied to the owning layout node's lifetime — the pane
  state store documents that a sweep deletes every `pane_state` row whose
  `node_id` is no longer a layout node, so a closed pane's (or its owner's)
  state is deleted with it; this pane does not manage that lifetime
  itself.

## Logging

Not applicable: no logging call of any kind appears anywhere in this file
or its immediate collaborators (the move menu, the arrange overlay).

## Platform Notes

- **SwiftUI**: This is an `NSViewController`/AppKit subclass, not SwiftUI. A SwiftUI-first rebuild would replace the class hierarchy with a `View` driven by an `@Observable` pane view-model exposing the same `nodeID`/`paneNumber`/`viewID` identity and computed `fallbackTitle`/`paneAccessibilityIdentifier`, use `.overlay` plus a boolean "arranging" state for the scrim instead of manually inserting an `NSView`, and drive the active-pane border with `.border(color:width:)` fed by an environment or `@FocusedValue` "active pane id" instead of `NSWindow.didBecomeKeyNotification` plus a local event monitor.
- **Compose**: Model the active-pane accent with `Modifier.border()` toggled by a `CompositionLocal` or shared ViewModel holding "the active pane id per window" (mirroring `ComposableTabsActivePane`). Arrange mode becomes a boolean state driving an `AnimatedVisibility` scrim `Box` containing an `IconButton` row for Add/Remove/Done and a Material `DropdownMenu` for the four move directions. There is no Android equivalent of Return/Enter as a global "exit" gesture; map only Escape-equivalent (back gesture, via `BackHandler`) and the explicit Done button to the same effect.
- **React/Web**: A `<div>` pane wrapper with `role="group"`, keyed the same way for a `data-testid` (`pane.<slug>` / `pane.<slug>.<index>`) rather than an ARIA attribute. Track the active pane via a document-level `mousedown`/`focusin` listener registered once per window (mirroring the single local `NSEvent` monitor, not a per-pane listener) and switch a CSS custom property for the border color. Arrange mode is a sibling overlay `<div>` at `position: absolute; inset: 2px;` with its own `keydown` listener scoped to the pane for Escape/Enter/Return, matching the source's "local monitor, not global handler" behavior.
- **AppKit/UIKit**: This recipe's own platform. `ComposableTabsPaneViewController.swift` is macOS/AppKit-only (`NSViewController`, `NSMenu`, `NSAlert`, `NSEvent` local monitors); nothing in this file targets UIKit/iOS. It also does not support construction via a coder-based initializer — Cocoa's `NSCoder`-driven `init(coder:)` — which this type overrides to trigger a fatal error immediately, since no code path in this app constructs this pane from an archived storyboard/xib. Source encodes the exit and move keys as raw macOS virtual key codes rather than named constants: Return is 36, Enter is 76, and Escape is 53 for **exit-keys-disable-arrange-mode**; Left is 123, Right is 124, Down is 125, and Up is 126 for **arrow-key-moves-active-pane-only**. A UIKit port would replace `NSMenu`/`NSAlert` with `UIMenu`/`UIAlertController`, replace the local `NSEvent` `keyDown` monitor with a `UIKeyCommand` set registered on the responder chain (there is no direct UIKit equivalent of "consume a hardware key before the first responder sees it" outside `UIKeyCommand`), and replace the popover-vs-sheet choice for the add picker with `UIPopoverPresentationController` vs. a `.pageSheet` presentation.
- **WinUI 3**: Recreate the pane as a `UserControl` wrapping a two-row `Grid` — a fixed-height title-bar row (a `GridLength` matching `PaneTitleBarView.height`, 26px-equivalent) and a content row — surrounded by a 2px `Border` (`BorderThickness="2"`, `BorderBrush` bound to a `SolidColorBrush` resource that swaps between an `ActivePaneAccentBrush` and a `PaneOutlineBrush`, mirroring the AppKit layer border and its color-only state change). Track "the active pane in this window" with a small per-`Window` service (a dictionary keyed by `Window`, mirroring `ComposableTabsActivePane`) updated from `PointerPressed`/`GotFocus` handlers registered once on `Window.Content`'s root rather than per pane. Model arrange mode as a `VisualStateGroup` ("Arranging"/"Normal") that swaps in a scrim `Grid` (`Background` bound to a semi-transparent brush over the window background) hosting a `CommandBar` (or a `StackPanel` of `Button`s) for Add/Remove/Done, with Move as a `DropDownButton` whose flyout `MenuFlyoutItem`s are enabled or disabled per the available-directions set. Bind `AutomationProperties.AutomationId` to the same `pane.<slug>` / `pane.<slug>.<index>` scheme via a converter, and register the Return/Enter/Escape exit keys as `KeyboardAccelerator`s scoped to the arrange scrim's `UIElement`, since WinUI's accelerator system already scopes by focus tree the way the AppKit local monitor does by window.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/ComposableTabs/ComposableTabsPaneViewController.swift` |

## Design Decisions

**Decision**: The layout-change notification handler refreshes this pane's arrange-overlay availability for every tab's layout change, not only its own window's.
**Rationale**: One pane moving changes what every other pane in every open tab may legally do next (a column's last pane loses Up, a tab's last leaf loses Remove), and the source posts one unscoped notification for exactly this reason rather than one per window.
**Approved**: pending

**Decision**: Removing a pane behind a confirmation sheet re-resolves the enclosing split inside the sheet's completion handler instead of capturing the split reference before presenting the sheet.
**Rationale**: The tree can change while the sheet is up — another pane could be moved or removed — so acting on a reference captured before the sheet opened risks removing the wrong leaf or acting on one that already left the tree.
**Approved**: pending

**Decision**: Arrow-key handling for arrange mode is implemented as a local `NSEvent` monitor per pane rather than an override of `keyDown(_:)`.
**Rationale (AppKit)**: The pane's own content (a terminal, an editor) owns first responder and would consume the arrow key before a `keyDown` override on this controller ever saw it; a local monitor sees the event before AppKit's responder chain delivers it.
**Approved**: pending

**Decision**: The active/inactive pane cue is color-only; border width stays a constant 2pt in both states.
**Rationale**: The source's own comment states the intent — outlining only the active pane would read as one pane with a seam down the middle — but implements no additional cue (width, icon, or pattern) for a person who cannot rely on color alone; see Differentiate Without Color in Accessibility Options.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | Accessibility |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | Accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | Accessibility |
| [dynamic-type-support](agenticdevelopercookbook://compliance/accessibility#dynamic-type-support) | partial | Accessibility |
| [focus-management](agenticdevelopercookbook://compliance/accessibility#focus-management) | passed | Accessibility |
| [string-externalization](agenticdevelopercookbook://compliance/internationalization#string-externalization) | failed | Internationalization |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |
| [rtl-layout-support](agenticdevelopercookbook://compliance/internationalization#rtl-layout-support) | passed | Internationalization |

Accessibility statuses rest on the explicit `accessibilityDescription` labels alongside the unaddressed VoiceOver-notification and Differentiate-Without-Color gaps recorded in Accessibility and Accessibility Options, the theme-delegated colors and heading-style label recorded in Appearance, and the native `NSAlert` modal/sheet handling in `confirmAndRemove()`; internationalization statuses rest on the hardcoded literals listed in Localization and the `leadingAnchor`/`trailingAnchor` overlay constraints in `installArrangeOverlay()`.

## Change History

| Version | Date | Author | Summary |
|---|---|---|---|
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/layout/composable-tabs/. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: rebuilt Compliance with real accessibility/internationalization catalog checks, defined the border inset once and referenced it by name elsewhere, restated the color-only active-pane cue as a descriptive fact rather than a foreclosing MUST, listed all four arrow-key codes, split and sharpened several test vectors, reformatted Design Decisions, moved the cookbook reference into `related`, added `depends-on`/`related` for sibling artifacts, and trimmed tags |
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
