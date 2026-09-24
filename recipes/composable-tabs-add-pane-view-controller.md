---
id: aea5e7b2-00d2-4f23-bfc5-8dc64e8d0d2a
title: ComposableTabsAddPaneViewController
domain: agentictoolkit://recipes/composable-tabs-add-pane-view-controller
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'AppKit sheet behind arrange mode''s Add button: separate Add/Where popups
  choose a view and a placement direction, defaulting to Right.'
platforms:
- swift
- macos
tags:
- dialog
- sheet
- form-control
- macos
- appkit
depends-on: []
related: []
references: []
approved-by: ''
approved-date: ''
---

# ComposableTabsAddPaneViewController

## Overview

`ComposableTabsAddPaneViewController` is a macOS `NSViewController` presented
as the sheet behind arrange mode's Add button. It asks two independent
questions: which view to add (an "Add" popup built from the `choices` the
caller supplies) and which side of the current pane to put it on (a "Where"
popup of the four fixed directions, defaulting to "Right"). Per the type's own
doc comment, these are two separate popups rather than one flattened list
(e.g. "Add Terminal Below") because the second answer is the same four
options whatever the first one is — a cross product of eight or twelve items
is a menu to read rather than a choice to make. `Choice` (a nested public
struct) carries the three fields each offerable entry needs: `viewID` (a
`ComposableTabsViewID`), `displayName` (the popup item's title), and an
optional `symbolName` (an SF Symbol shown as that item's image). `Direction`
is a type alias for `ComposableTabsViewController.Direction`
(`left`/`right`/`above`/`below`). Activating OK with a valid selection
dismisses the sheet and then invokes the caller-supplied `onAdd` closure with
the chosen `ComposableTabsViewID` and `Direction`; activating Cancel dismisses
without invoking it.

## Behavioral Requirements

- **populates-view-popup-from-choices**: The "Add" popup MUST contain exactly
  one item per entry in `choices`, in the order given, titled with that
  entry's `displayName`.
- **sets-choice-icon-when-symbol-present**: When a `choices` entry's
  `symbolName` is non-nil, the "Add" popup MUST set that item's image to the
  SF Symbol named by `symbolName`, with an accessibility description equal to
  the entry's `displayName`.
- **omits-choice-icon-when-symbol-absent**: When a `choices` entry's
  `symbolName` is `nil`, the "Add" popup MUST leave that item without an
  image.
- **populates-where-popup-in-fixed-order**: The "Where" popup MUST contain
  exactly four items, titled "Left", "Right", "Above", "Below" in that fixed
  order, regardless of `choices`.
- **defaults-where-selection-to-right**: The "Where" popup's initial
  selection MUST be "Right".
- **arranges-add-and-where-as-two-row-grid**: The "Add" and "Where"
  label/popup pairs MUST be laid out as a two-row, two-column grid, not a
  form list or stack.
- **add-row-precedes-where-row**: The "Add" row MUST appear above the "Where"
  row in the grid.
- **ok-button-disabled-when-choices-empty**: The OK button's `isEnabled`
  MUST be `false` at load time when `choices` is empty.
- **ok-button-enabled-when-choices-present**: The OK button's `isEnabled`
  MUST be `true` at load time when `choices` is non-empty.
- **ok-button-enabled-state-fixed-at-load**: The OK button's enabled state
  MUST be computed once, from `choices`, at `loadView()` time, and MUST NOT
  be re-evaluated afterward in response to either popup's selection
  changing.
- **cancel-precedes-ok-in-button-order**: The Cancel button MUST be
  positioned before the OK button, left to right.
- **cancel-bound-to-escape-key**: The Cancel button's key equivalent MUST be
  the Escape key.
- **ok-bound-to-return-key**: The OK button's key equivalent MUST be the
  Return key.
- **cancel-dismisses-without-invoking-onadd**: Activating Cancel MUST
  dismiss the view controller and MUST NOT invoke `onAdd`.
- **confirm-dismisses-before-invoking-onadd**: Activating OK with a valid
  selection MUST dismiss the view controller before invoking `onAdd`.
- **confirm-invokes-onadd-with-selection**: Activating OK MUST, when both
  popups have a valid selected index, invoke `onAdd` with the `viewID` of
  the selected `Choice` and the `Direction` at the selected "Where" index.
- **confirm-dismisses-without-onadd-on-invalid-selection**: Activating OK
  MUST dismiss the view controller without invoking `onAdd` when the "Add"
  popup's selected index is not a valid index into `choices`, or the
  "Where" popup's selected index is not a valid index into the four fixed
  directions.
- **enforces-minimum-container-width**: The container view's width MUST be
  constrained to at least 320 points.
- **root-view-accessibility-identifier**: The root container view MUST
  carry the accessibility identifier "composable-tabs.add-pane".
- **view-popup-accessibility-identifier**: The "Add" popup MUST carry the
  accessibility identifier "composable-tabs.add-pane.view".
- **where-popup-accessibility-identifier**: The "Where" popup MUST carry
  the accessibility identifier "composable-tabs.add-pane.where".
- **cancel-button-accessibility-identifier**: The Cancel button MUST carry
  the accessibility identifier "composable-tabs.add-pane.cancel".
- **ok-button-accessibility-identifier**: The OK button MUST carry the
  accessibility identifier "composable-tabs.add-pane.ok".
- **add-row-label-text**: The "Add" row's label MUST display the
  right-aligned text "Add:".
- **where-row-label-text**: The "Where" row's label MUST display the
  right-aligned text "Where:".
- **coder-initialization-unsupported**: The component MUST NOT support
  initialization via `init(coder:)` and MUST fail fast (fatal error) if it
  is invoked.

## Appearance

- **Corner radius**: Not applicable — the container is a
  `ThemedBackgroundView`, a plain layer-backed fill with no corner radius
  set anywhere in source.
- **Padding**: Root container: 20pt top and leading around the grid, and
  the container's trailing edge is constrained at least 20pt past the
  grid's trailing edge. Between the grid and the button row: 20pt vertical
  gap. Around the button row: the container's trailing edge sits exactly
  20pt past the buttons' trailing edge, the buttons' leading edge is
  constrained at least 20pt past the container's leading edge, and the
  container's bottom edge sits exactly 20pt past the buttons' bottom edge.
  Within the grid: 12pt row spacing, 8pt column spacing.
- **Font**: The "Add:"/"Where:" row labels use `ThemedLabel`'s `.body`
  `TextRole` (the active theme's body text style); no custom font is set
  beyond that role.
- **Background**: `ThemeRole.windowBackground`, resolved dynamically from
  the active theme's palette (`ThemedBackgroundView(role: .windowBackground)`).
- **Foreground/Text**: Row labels use `ThemeRole.primaryText`, resolved
  dynamically from the active theme's palette.
- **Border**: None — no border is configured on any view in source.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere in
  source.
- **Min/Max size**: Container width is constrained to at least 320pt; no
  explicit height and no maximum width or height constraint exists in
  source.

## States

| State | Appearance change |
|-------|--------------------|
| Default (initial load) | "Add" popup lists all `choices` in order; "Where" popup lists Left/Right/Above/Below and selects "Right"; OK's enabled state is fixed from `!choices.isEmpty`. |
| Choices non-empty | OK button `isEnabled == true`. |
| Choices empty | OK button `isEnabled == false`; "Add" popup has zero items. |
| Selection changed (user) | The chosen popup item shows as selected; no other view updates in response — OK's enabled state does not react to the change. |
| Pressed | Not applicable — Cancel/OK use the stock `.rounded` `NSButton` bezel; source overrides no pressed/highlight rendering. |
| Focused | Not applicable — source sets no custom focus ring or explicit key-view loop; whichever control is focused uses AppKit's default focus-ring appearance and the default subview tab order. |
| Disabled | Applies only to OK, per "Choices empty" above; the disabled appearance is AppKit's stock dimmed bezel, not custom-drawn. |
| Loading | Not applicable — `choices` is supplied synchronously at `init`, and `loadView()` builds the whole view hierarchy synchronously; source defines no asynchronous or pending state. |

## Accessibility

- **Role/trait**: Not explicitly set via `setAccessibilityRole`/
  `accessibilityElement` anywhere in source; the two `NSPopUpButton`s and
  two `NSButton`s use AppKit's default pop-up-button/button roles, and the
  two `ThemedLabel`/`NSTextField` row captions use the default static-text
  role.
- **Label requirements**: `accessibilityID(_:)` sets a test-automation
  identifier on the container ("composable-tabs.add-pane"), both popups
  ("composable-tabs.add-pane.view", "composable-tabs.add-pane.where"), and
  both buttons ("composable-tabs.add-pane.cancel",
  "composable-tabs.add-pane.ok") — these back UI-test lookup, not
  VoiceOver's spoken label. Cancel and OK derive their spoken label from
  their own visible titles ("Cancel", "OK"). Each `choices` entry with a
  `symbolName` gets an explicit accessibility description (the entry's
  `displayName`) on its popup-item image. NEEDS REVIEW: Not implemented in
  source. Behavior undefined. Neither popup is associated with its row
  caption ("Add:" / "Where:") via `setAccessibilityTitleUIElement` or an
  explicit `accessibilityLabel` override, so VoiceOver announces only the
  popup's current value (e.g. "Right") without the "Where" context a
  sighted user gets from the adjacent label. What is missing: whether a
  VoiceOver user can distinguish the two popups without first exploring the
  visual layout. What would settle it: a VoiceOver pass over an
  instantiated sheet, or an explicit decision to wire
  `setAccessibilityTitleUIElement` from each popup to its row's
  `ThemedLabel`.
- **Announce state changes**: Not applicable — the sheet has no dynamic
  reload or asynchronous state; the only state changes are direct results
  of the user's own popup selections and button activations, which AppKit
  announces on its own via the controls' native accessibility behavior.
- **Minimum tap target**: Not applicable in the touch sense — this is a
  pointer/keyboard-driven macOS sheet; `NSPopUpButton` and `NSButton`
  (`.rounded` bezel) all use AppKit's default control metrics, with no
  custom frame or height override in source. The 44×44pt (iOS) / 48×48dp
  (Android) minimum applies to the touch-platform translations in Platform
  Notes, not to this AppKit sheet.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| add-pane-001 | populates-view-popup-from-choices | `choices = [A (no symbol), B (symbol "terminal")]` | "Add" popup has 2 items, titled A's `displayName` then B's, in that order |
| add-pane-002 | sets-choice-icon-when-symbol-present | `choices` includes an entry with `symbolName == "terminal"` | That item's image is the "terminal" SF Symbol, with accessibility description equal to its `displayName` |
| add-pane-003 | omits-choice-icon-when-symbol-absent | `choices` includes an entry with `symbolName == nil` | That item's image is `nil` |
| add-pane-004 | populates-where-popup-in-fixed-order | Any `choices` value | "Where" popup contains exactly 4 items titled "Left", "Right", "Above", "Below" in that order |
| add-pane-005 | defaults-where-selection-to-right | Load the sheet | The "Where" popup's selected item is "Right" |
| add-pane-006 | arranges-add-and-where-as-two-row-grid | Inspect the grid after `loadView()` | The grid has exactly 2 rows and 2 columns |
| add-pane-007 | add-row-precedes-where-row | Inspect the grid's rows | Row 0 holds the Add label/popup; row 1 holds the Where label/popup |
| add-pane-008 | ok-button-disabled-when-choices-empty | `choices = []` | `okButton.isEnabled == false` |
| add-pane-009 | ok-button-enabled-when-choices-present | `choices = [A]` | `okButton.isEnabled == true` |
| add-pane-010 | ok-button-enabled-state-fixed-at-load | Load with `choices = [A]`; change the Where selection, then the Add selection | `okButton.isEnabled` remains `true`, unchanged by either selection |
| add-pane-011 | cancel-precedes-ok-in-button-order | Inspect the button stack's `views` | `views[0]` is Cancel, `views[1]` is OK |
| add-pane-012 | cancel-bound-to-escape-key | Inspect `cancel.keyEquivalent` | Equals the Escape character |
| add-pane-013 | ok-bound-to-return-key | Inspect `okButton.keyEquivalent` | Equals the Return character |
| add-pane-014 | cancel-dismisses-without-invoking-onadd | Click Cancel | The sheet is dismissed; `onAdd` is never called |
| add-pane-015 | confirm-dismisses-before-invoking-onadd | Select a valid Add and Where combination; click OK | The sheet's dismissal completes before `onAdd` runs (observable via call-order instrumentation) |
| add-pane-016 | confirm-invokes-onadd-with-selection | "Add" popup selects `choices[1]`; "Where" popup selects "Above" | `onAdd` is called once, with `(choices[1].viewID, .above)` |
| add-pane-017 | confirm-dismisses-without-onadd-on-invalid-selection | `choices = []`; force-invoke the confirm action with the "Add" popup's selected index `== -1` | The sheet is dismissed; `onAdd` is never called |
| add-pane-018 | enforces-minimum-container-width | Measure the container's width constraint after `loadView()` | A `greaterThanOrEqualToConstant` constraint of 320pt exists on the container's width |
| add-pane-019 | root-view-accessibility-identifier | Inspect the container's accessibility identifier | Equals "composable-tabs.add-pane" |
| add-pane-020 | view-popup-accessibility-identifier | Inspect the "Add" popup's accessibility identifier | Equals "composable-tabs.add-pane.view" |
| add-pane-021 | where-popup-accessibility-identifier | Inspect the "Where" popup's accessibility identifier | Equals "composable-tabs.add-pane.where" |
| add-pane-022 | cancel-button-accessibility-identifier | Inspect the Cancel button's accessibility identifier | Equals "composable-tabs.add-pane.cancel" |
| add-pane-023 | ok-button-accessibility-identifier | Inspect the OK button's accessibility identifier | Equals "composable-tabs.add-pane.ok" |
| add-pane-024 | add-row-label-text | Inspect the Add row's label | Text reads "Add:"; alignment is right |
| add-pane-025 | where-row-label-text | Inspect the Where row's label | Text reads "Where:"; alignment is right |
| add-pane-026 | coder-initialization-unsupported | Attempt to construct the component via its coder initializer | Execution traps with a fatal error; no instance is produced |

## Edge Cases

- Null/empty input (MUST): `choices == []` yields an "Add" popup with zero
  items and a selected index of -1; per **ok-button-disabled-when-choices-empty**
  OK is disabled at load, and per
  **confirm-dismisses-without-onadd-on-invalid-selection** even a forced
  confirm dismisses without invoking `onAdd`, since -1 is never a valid
  index into `choices`.
- Null/empty input (MUST): `onAdd` and `choices` are both non-optional
  initializer parameters, so Swift's type system rules out passing `nil`
  for either; the component provides, and needs, no nil-handling path for
  them.
- Boundary values (MUST): the "Where" popup always contains exactly the
  four fixed directions, so its selected index is always valid (0 through
  3) through ordinary UI interaction; the bounds guard in the confirm
  action only ever fails, for "Where", in a hypothetical, non-UI-driven
  case.
- Boundary values (MUST): the fallback that picks index 0 if "Right" were
  ever absent from the fixed direction list is unreachable dead code in
  the current source, since that list is a hardcoded four-case literal
  that always contains "Right" (see Design Decisions).
- Concurrent access: Not applicable — the class is declared `@MainActor`,
  so Swift's concurrency checker confines all reads and writes of
  `choices`, the two popups, and the two buttons to the main actor.
- Error states: Not applicable — the component performs no I/O, no
  throwing call, and no asynchronous work; its only defensive path is the
  index-bounds guard in the confirm action, documented above as a
  boundary-value case rather than an error state.
- Offline/disconnected: Not applicable — the component makes no network
  call anywhere in source.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|--------------|
| `choices` | `[Choice]` | — (required) | The offerable views, in display order; empty disables OK and leaves the "Add" popup empty. |
| `onAdd` | `(ComposableTabsViewID, Direction) -> Void` | — (required) | Invoked once, after dismissal, when OK is activated with a valid selection. |

`Choice` (a nested public struct, not a top-level init option) carries three
fields per offerable entry: `viewID` (`ComposableTabsViewID`), `displayName`
(`String`, the popup item's title), and `symbolName` (`String?`, an optional
SF Symbol name shown as that item's image).

## Deep Linking

Not applicable: this is a transient sheet view controller with no URL
scheme, route, or deep-link handler in source; arrange mode's Add button
presents it programmatically.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| n/a (literal) | "Add:" | Row caption for the view-choice popup |
| n/a (literal) | "Where:" | Row caption for the direction popup |
| n/a (literal) | "Left" | Direction popup item |
| n/a (literal) | "Right" | Direction popup item (default selection) |
| n/a (literal) | "Above" | Direction popup item |
| n/a (literal) | "Below" | Direction popup item |
| n/a (literal) | "Cancel" | Cancel button title |
| n/a (literal) | "OK" | OK button title |

Not applicable beyond the table above: each `choices` entry's own
`displayName` shown in the "Add" popup is supplied by the caller, not
hardcoded in this file, so localizing it is the caller's responsibility, not
this component's.

## Accessibility Options

- **Reduce Motion**: Not applicable — source defines no animation,
  transition, or `NSAnimationContext` call; the sheet's content is built
  once, synchronously, in `loadView()`.
- **Increase Contrast**: Not applicable — every color in this file comes
  from a `ThemeRole` (`.windowBackground`, `.primaryText`) resolved by the
  shared theme system; the file itself sets no literal `NSColor` and
  performs no contrast-specific branching.
- **Differentiate Without Color**: Not applicable — the component conveys
  no state through color alone; the Add/Where choices and the OK/Cancel
  actions are identified by text and icons, not color.

## Feature Flags

Not applicable: the source contains no feature-flag or config-gating
lookup.

## Analytics

Not applicable: the source contains no analytics or telemetry call.

## Privacy

- **Data collected**: None beyond the in-memory popup selections the user
  makes while the sheet is open.
- **Storage**: None — selections live only in the two popups' selection
  state for the sheet's lifetime; nothing is written to disk,
  `UserDefaults`, or any other store by this file.
- **Transmission**: None — `onAdd` hands the selected
  `ComposableTabsViewID` and `Direction` directly to the caller in-process;
  this file makes no network or IPC call.
- **Retention**: None beyond the sheet's lifetime; the selection is
  discarded once the sheet is dismissed, whether via Cancel, OK, or an
  invalid-selection confirm.

## Logging

Not applicable: the source contains no logging call (no `print`, `os_log`,
or logger reference anywhere in this file).

## Platform Notes

- **SwiftUI**: Model the sheet as a small form presented via
  `.sheet(isPresented:)`, with a `Picker("Add:", selection: $selectedChoice)`
  populated from `choices` and a `Picker("Where:", selection:
  $selectedDirection)` populated from the four `Direction` cases,
  defaulting `selectedDirection` to `.right`. Give an "Add" option a
  `Label(choice.displayName, systemImage: choice.symbolName)` when a symbol
  exists, mirroring the source's per-item image. A footer `Button("Cancel")`
  with `.keyboardShortcut(.cancelAction)` and `Button("OK")` with
  `.keyboardShortcut(.defaultAction)` reproduce the Escape/Return bindings,
  and `.disabled(choices.isEmpty)` computed once at sheet-open time
  reproduces the fixed-at-load OK enablement.
- **Compose**: Use two dropdown-menu composables inside an `AlertDialog`
  (or a `Dialog` with custom content) — one bound to a `selectedChoice`
  state seeded to the first entry, one to a `selectedDirection` state
  seeded to the "right" direction. Render each Add-menu item with an
  optional leading icon when a symbol equivalent exists, mirroring the
  source's per-item image. Wire the dialog's confirm/dismiss actions
  through its own confirm/dismiss slots, disabling the confirm action once,
  at open time, when `choices` is empty, mirroring the fixed-at-load
  `okButton.isEnabled`.
- **React/Web**: A small modal built on a dialog primitive, containing two
  native selection controls — one populated from `choices` (each option
  carrying the choice's `displayName`, with an optional leading icon
  rendered alongside if icons are needed), one populated from the four
  direction labels defaulting to "Right" — plus "Cancel" and "OK" buttons.
  Bind Escape to Cancel and Enter/form submit to OK, mirroring the AppKit
  key equivalents, and set the OK button's disabled state once, at open
  time, from `choices.length === 0`, mirroring the source's fixed-at-load
  enablement rather than a reactive binding.
- **AppKit/UIKit** (source platform): Implemented in
  `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/ComposableTabs/ComposableTabsAddPaneViewController.swift`
  as a `@MainActor`, `final` `NSViewController` with no nib/XIB —
  `loadView()` builds an `NSGridView` of two `NSPopUpButton`s and their
  `ThemedLabel` captions, plus an `NSStackView` of Cancel/OK `NSButton`s,
  laid out with Auto Layout against a `ThemedBackgroundView` root. Arrange
  mode presents it as a sheet from its Add button. There is no UIKit code
  path in source; a UIKit port would replace the two `NSPopUpButton`s with
  `UIButton`s presenting menus (or two rows of a grouped table/picker
  view), replace the grid with a stack view of horizontal rows, and present
  the whole thing as a small view controller in a form-sheet presentation,
  since UIKit has no direct analog of `NSGridView`/`NSPopUpButton`.
- **WinUI 3** (the reason this recipe exists): Build the sheet as a
  `ContentDialog` with `PrimaryButtonText="OK"` and
  `CloseButtonText="Cancel"` — `ContentDialog` already binds its primary
  button to Enter and its close button to Escape, the direct analogs of the
  source's Return/Escape key equivalents — and set `IsPrimaryButtonEnabled`
  once, at open time, from `Choices.Count > 0`, mirroring the fixed-at-load
  `okButton.isEnabled` rather than a live binding. Lay out two rows of
  `TextBlock` + `ComboBox` in a `Grid` with two `RowDefinitions` and two
  `ColumnDefinitions` (label column `HorizontalAlignment="Right"`,
  matching the source grid's trailing label placement) — an "Add:" row
  bound to a `ComboBox` populated from the choices collection (each item a
  horizontal panel of an optional icon glyph plus a text run for the
  display name, mirroring the source's per-item SF Symbol image) and a
  "Where:" row bound to a `ComboBox` of the four direction labels, with
  `SelectedIndex` initialized to the index of "Right". Handle the
  `ContentDialog`'s primary-button-click event to read both `ComboBox`
  selections and raise the add-pane event only after `ShowAsync()` has
  returned and the dialog has closed, mirroring the source's
  dismiss-before-invoke ordering in the confirm action.

## Design Decisions

- Decision: Split "what to add" and "where to put it" into two independent
  popups rather than one flattened list (e.g. "Add Terminal Below").
  Rationale: Per the type's doc comment, the second answer (the four
  directions) is the same regardless of the first, so a flattened list
  would force the user to read a cross product of eight or twelve items
  instead of making two small choices.
  Approved: pending
- Decision: Default the "Where" popup's selection to "Right" rather than
  the first item ("Left") or no selection.
  Rationale: Per the source comment, the pane the user is looking at is on
  the left of a document more often than not, so placing the new pane to
  its right is the least surprising default.
  Approved: pending
- Decision: Dismiss the sheet before invoking `onAdd` in the confirm
  action, rather than invoking `onAdd` first.
  Rationale: Per the source comment, `onAdd` re-parents view controllers by
  splitting the pane; doing that while the sheet is still presented would
  leave the sheet anchored to a window whose content has already moved out
  from under it.
  Approved: pending
- Decision: Fix the direction list to the hardcoded order left, right,
  above, below and reuse that same list both to populate the "Where"
  popup and to map its selected index back to a direction.
  Rationale: Per the source comment, a fixed order makes the popup read
  the way the pane visually looks; reusing one list for both population
  and index-mapping keeps the two in sync by construction rather than by
  convention.
  Approved: pending
- Decision: Center-align the grid's rows instead of using `NSGridView`'s
  default first-baseline row alignment.
  Rationale: Per the source comment, a label baseline-aligned against a
  popup sits high in it, which reads as a row that did not quite line up;
  centering both views in the row instead makes the label and popup look
  vertically aligned.
  Approved: pending
- Decision: Leave a defensive fallback to index 0 for the "Right" lookup,
  even though the direction list is a hardcoded literal that always
  contains "Right".
  Rationale: Not explained in source; recorded here as an observed,
  currently-unreachable defensive path so other-platform implementations
  do not need to reproduce a "what if Right is missing" branch, and so a
  future edit to the direction list that did drop "Right" would be caught
  by this recipe's boundary-value edge case rather than silently changing
  the default.
  Approved: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [source-fidelity](agenticdevelopercookbook://compliance/recipe-quality#source-fidelity) | passed | recipe-quality |
| [behavioral-requirements](agenticdevelopercookbook://compliance/recipe-quality#behavioral-requirements) | passed | recipe-quality |
| [completeness](agenticdevelopercookbook://compliance/recipe-quality#completeness) | passed | recipe-quality |
| [template-conformance](agenticdevelopercookbook://compliance/recipe-quality#template-conformance) | passed | recipe-quality |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | accessibility |
| [modal-dismissal-and-focus](agenticdevelopercookbook://compliance/accessibility#modal-dismissal-and-focus) | passed | accessibility |
| [differentiate-without-color](agenticdevelopercookbook://compliance/accessibility#differentiate-without-color) | passed | accessibility |
| [touch-target-size](agenticdevelopercookbook://compliance/accessibility#touch-target-size) | passed | accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | accessibility |
| [string-externalization](agenticdevelopercookbook://compliance/internationalization#string-externalization) | failed | internationalization |
| [main-actor-confined](agentictoolkit://compliance/architecture#main-actor-confined) | passed | architecture |

Keyboard-navigable passes because Cancel/OK carry the Escape/Return key
equivalents and every other control is a stock, natively keyboard-accessible
`NSPopUpButton`/`NSButton`. Screen-reader-support is partial: accessibility
identifiers back automation on every control and the SF Symbol images carry
descriptions, but neither popup is associated with its row caption via
`setAccessibilityTitleUIElement` (see the Accessibility section's NEEDS
REVIEW marker). Modal-dismissal-and-focus passes on the strength of AppKit's
native sheet presentation and dismissal, which this file does not override.
Differentiate-without-color passes because no state here is conveyed by
color alone. Touch-target-size passes because every control uses AppKit's
standard control metrics for a pointer/keyboard-driven macOS sheet, not a
custom undersized control; the 44×44pt/48×48dp minimum applies only to the
touch-platform translations in Platform Notes. Contrast-ratio is partial
because colors come entirely from `ThemeRole` tokens resolved by the shared
theme system, whose actual contrast values are not stated in this file.
String-externalization is failed because every label in this file ("Add:",
"Where:", "Left", "Right", "Above", "Below", "Cancel", "OK") is a hardcoded
English literal with no localization key. Main-actor-confined passes because
the class is declared `@MainActor`.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Claude Sonnet 5 | Initial ingredient recipe for ComposableTabsAddPaneViewController: two-popup Add/Where sheet, fixed direction order and Right default, dismiss-before-invoke confirm ordering, fixed-at-load OK enablement, and one open accessibility question (popup-to-caption label association) for review. |
