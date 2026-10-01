---
id: aea5e7b2-00d2-4f23-bfc5-8dc64e8d0d2a
title: Composable Tabs Add Pane Sheet
domain: agentictoolkit://cookbook/ui/layout/composable-tabs/add-pane-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A dialog behind arrange mode's Add button that lets the user choose a
  view and a placement direction, defaulting to Right, through two separate choices.
platforms:
- swift
- macos
tags:
- dialog
- sheet
- form-control
depends-on:
- agentictoolkit://cookbook/ui/layout/composable-tabs
related: []
references: []
approved-by: ''
approved-date: ''
---

# Composable Tabs Add Pane Sheet

## Overview

The add pane sheet is presented behind arrange mode's Add button. It asks
two independent questions: which view to add (an "Add" choice built from the
entries the caller supplies) and which side of the current pane to put it on
(a "Where" choice among four fixed directions, defaulting to "Right"). These
are two separate choices rather than one flattened list (e.g. "Add Terminal
Below") because the second answer is the same four options whatever the
first one is — a cross product of eight or twelve items is a list to read
rather than a choice to make. Each offerable entry carries three fields: a
view identifier, a display name (the choice item's title), and an optional
icon shown alongside it. The direction is one of four fixed values: left,
right, above, below. Confirming with a valid selection dismisses the sheet
and then reports the chosen view identifier and direction to the caller;
canceling dismisses without reporting anything.

## Behavioral Requirements

- **populates-view-popup-from-choices**: The "Add" choice list MUST contain
  exactly one item per offerable entry, in the order given, titled with that
  entry's display name.
- **sets-choice-icon-when-symbol-present**: When an offerable entry's icon is
  set, the "Add" choice list MUST set that item's image to the named icon,
  with an accessibility description equal to the entry's display name.
- **omits-choice-icon-when-symbol-absent**: When an offerable entry's icon is
  unset, the "Add" choice list MUST leave that item without an image.
- **populates-where-popup-in-fixed-order**: The "Where" choice list MUST
  contain exactly four items, titled "Left", "Right", "Above", "Below" in
  that fixed order, regardless of the offered entries.
- **defaults-where-selection-to-right**: The "Where" choice list's initial
  selection MUST be "Right".
- **arranges-add-and-where-as-two-row-grid**: The "Add" and "Where"
  label/choice pairs MUST be laid out as a two-row, two-column grid, not a
  form list or stack.
- **add-row-precedes-where-row**: The "Add" row MUST appear above the "Where"
  row in the grid.
- **ok-button-disabled-when-choices-empty**: The OK button MUST be disabled
  at load time when no entries are offered.
- **ok-button-enabled-when-choices-present**: The OK button MUST be enabled
  at load time when at least one entry is offered.
- **ok-button-enabled-state-fixed-at-load**: The OK button's enabled state
  MUST be computed once, from the offered entries, at load time; enablement
  depends only on whether entries were offered, not on either choice's
  selection.
- **cancel-precedes-ok-in-button-order**: The Cancel button MUST be
  positioned before the OK button, left to right.
- **cancel-bound-to-escape-key**: The Cancel button's key equivalent MUST be
  the Escape key.
- **ok-bound-to-return-key**: The OK button's key equivalent MUST be the
  Return key.
- **cancel-dismisses-without-invoking-onadd**: Activating Cancel MUST
  dismiss the sheet and MUST NOT report a selection.
- **confirm-dismisses-before-invoking-onadd**: Activating OK with a valid
  selection MUST dismiss the sheet before reporting the selection to the
  caller.
- **confirm-invokes-onadd-with-selection**: Activating OK MUST, when both
  choices have a valid selected index, report to the caller the view
  identifier of the selected entry and the direction at the selected "Where"
  index.
- **confirm-dismisses-without-onadd-on-invalid-selection**: Activating OK
  MUST dismiss the sheet without reporting a selection when the "Add"
  choice's selected index is not a valid index into the offered entries, or
  the "Where" choice's selected index is not a valid index into the four
  fixed directions.
- **enforces-minimum-container-width**: The container view's width MUST be
  constrained to at least 320 points.
- **root-view-accessibility-identifier**: The root container view MUST
  carry the accessibility identifier "composable-tabs.add-pane".
- **view-popup-accessibility-identifier**: The "Add" choice list MUST carry
  the accessibility identifier "composable-tabs.add-pane.view".
- **where-popup-accessibility-identifier**: The "Where" choice list MUST
  carry the accessibility identifier "composable-tabs.add-pane.where".
- **cancel-button-accessibility-identifier**: The Cancel button MUST carry
  the accessibility identifier "composable-tabs.add-pane.cancel".
- **ok-button-accessibility-identifier**: The OK button MUST carry the
  accessibility identifier "composable-tabs.add-pane.ok".
- **add-row-label-text**: The "Add" row's label MUST display the
  right-aligned text "Add:".
- **where-row-label-text**: The "Where" row's label MUST display the
  right-aligned text "Where:".
- **associates-popup-with-row-caption**: Each choice list SHOULD be
  associated with its row's caption ("Add:" / "Where:") so a screen reader
  announces the caption together with the choice's current value.

## Appearance

- **Corner radius**: Not applicable — the container is a plain, filled
  backdrop with no corner radius set anywhere in source.
- **Padding**: Root container: 20pt top and leading around the grid, and
  the container's trailing edge is constrained at least 20pt past the
  grid's trailing edge. Between the grid and the button row: 20pt vertical
  gap. Around the button row: the container's trailing edge sits exactly
  20pt past the buttons' trailing edge, the buttons' leading edge is
  constrained at least 20pt past the container's leading edge, and the
  container's bottom edge sits exactly 20pt past the buttons' bottom edge.
  Within the grid: 12pt row spacing, 8pt column spacing.
- **Font**: The "Add:"/"Where:" row labels use the active theme's body text
  role; no custom font is set beyond that role.
- **Background**: The theme's window-background role, resolved dynamically
  from the active theme's palette.
- **Foreground/Text**: Row labels use the theme's primary-text role,
  resolved dynamically from the active theme's palette.
- **Border**: None — no border is configured on any view in source.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere in
  source.
- **Min/Max size**: Container width is constrained to at least 320pt; no
  explicit height and no maximum width or height constraint exists in
  source.

## States

| State | Appearance change |
|-------|--------------------|
| Default (initial load) | "Add" choice list lists all offered entries in order; "Where" choice list lists Left/Right/Above/Below and selects "Right"; OK's enabled state is fixed from whether any entry was offered. |
| Choices non-empty | OK button is enabled. |
| Choices empty | OK button is disabled; "Add" choice list has zero items. |
| Selection changed (user) | The chosen item shows as selected; no other view updates in response — OK's enabled state does not react to the change. |
| Pressed | Not applicable — Cancel/OK use the platform's standard button style; source overrides no pressed/highlight rendering. |
| Focused | Not applicable — source sets no custom focus ring or explicit key-view loop; whichever control is focused uses the platform's default focus indicator and the default subview tab order. |
| Disabled | Applies only to OK, per "Choices empty" above; the disabled appearance is the platform's standard dimmed style, not custom-drawn. |
| Loading | Not applicable — the offered entries are supplied synchronously at construction, and the whole view hierarchy is built synchronously when the sheet loads; source defines no asynchronous or pending state. |

## Accessibility

- **Role/trait**: Not explicitly set anywhere in source; the two choice
  lists and two buttons use the platform's default pop-up/button roles, and
  the two row captions use the default static-text role.
- **Label requirements**: A test-automation identifier is set on the
  container ("composable-tabs.add-pane"), both choice lists
  ("composable-tabs.add-pane.view", "composable-tabs.add-pane.where"), and
  both buttons ("composable-tabs.add-pane.cancel",
  "composable-tabs.add-pane.ok") — these back UI-test lookup, not a screen
  reader's spoken label. Cancel and OK derive their spoken label from their
  own visible titles ("Cancel", "OK"). Each offered entry with an icon gets
  an explicit accessibility description (the entry's display name) on its
  item's image. Per **associates-popup-with-row-caption**, neither choice
  list is associated with its row caption ("Add:" / "Where:") anywhere in
  source, so a screen reader announces only the choice's current value
  (e.g. "Right") without the "Where" context a sighted user gets from the
  adjacent label.
- **Announce state changes**: Not applicable — the sheet has no dynamic
  reload or asynchronous state; the only state changes are direct results
  of the user's own selections and button activations, which the platform
  announces on its own via the controls' native accessibility behavior.
- **Minimum tap target**: Not applicable in the touch sense — this is a
  pointer/keyboard-driven sheet; both choice lists and buttons use the
  platform's default control metrics, with no custom frame or height
  override in source. Touch tap-target minimum guidance does not apply here,
  since this is not a touch-driven control.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| add-pane-001 | populates-view-popup-from-choices | Two entries are offered: A with no icon, B with an icon | "Add" choice list has 2 items, titled A's display name then B's, in that order |
| add-pane-002 | sets-choice-icon-when-symbol-present | An offered entry has an icon set | That item's image is the icon, with accessibility description equal to its display name |
| add-pane-003 | omits-choice-icon-when-symbol-absent | An offered entry has no icon set | That item's image is unset |
| add-pane-004 | populates-where-popup-in-fixed-order | Any set of offered entries | "Where" choice list contains exactly 4 items titled "Left", "Right", "Above", "Below" in that order |
| add-pane-005 | defaults-where-selection-to-right | Load the sheet | The "Where" choice's selected item is "Right" |
| add-pane-006 | arranges-add-and-where-as-two-row-grid | Inspect the grid after the sheet loads | The grid has exactly 2 rows and 2 columns |
| add-pane-007 | add-row-precedes-where-row | Inspect the grid's rows | Row 0 holds the Add label/choice; row 1 holds the Where label/choice |
| add-pane-008 | ok-button-disabled-when-choices-empty | No entries are offered | The OK button is disabled |
| add-pane-009 | ok-button-enabled-when-choices-present | One entry is offered | The OK button is enabled |
| add-pane-010 | ok-button-enabled-state-fixed-at-load | Load with one entry offered; change the Where selection, then the Add selection | The OK button remains enabled, unchanged by either selection |
| add-pane-011 | cancel-precedes-ok-in-button-order | Inspect the button row's order | Cancel appears before OK |
| add-pane-012 | cancel-bound-to-escape-key | Inspect Cancel's key equivalent | Equals the Escape key |
| add-pane-013 | ok-bound-to-return-key | Inspect OK's key equivalent | Equals the Return key |
| add-pane-014 | cancel-dismisses-without-invoking-onadd | Click Cancel | The sheet is dismissed; the caller is never notified |
| add-pane-015 | confirm-dismisses-before-invoking-onadd | Select a valid Add and Where combination; click OK | Dismissal happens before the selection is reported to the caller (observable via call-order instrumentation) |
| add-pane-016 | confirm-invokes-onadd-with-selection | "Add" choice selects the second entry; "Where" choice selects "Above" | The caller is notified once, with that entry's view identifier and "above" |
| add-pane-017 | confirm-dismisses-without-onadd-on-invalid-selection | No entries are offered; the confirm action is force-invoked directly, leaving the "Add" choice's selected index invalid | The sheet is dismissed; the caller is never notified |
| add-pane-018 | enforces-minimum-container-width | Measure the container's width constraint after the sheet loads | A minimum-width constraint of 320pt exists on the container |
| add-pane-019 | root-view-accessibility-identifier | Inspect the container's accessibility identifier | Equals "composable-tabs.add-pane" |
| add-pane-020 | view-popup-accessibility-identifier | Inspect the "Add" choice list's accessibility identifier | Equals "composable-tabs.add-pane.view" |
| add-pane-021 | where-popup-accessibility-identifier | Inspect the "Where" choice list's accessibility identifier | Equals "composable-tabs.add-pane.where" |
| add-pane-022 | cancel-button-accessibility-identifier | Inspect the Cancel button's accessibility identifier | Equals "composable-tabs.add-pane.cancel" |
| add-pane-023 | ok-button-accessibility-identifier | Inspect the OK button's accessibility identifier | Equals "composable-tabs.add-pane.ok" |
| add-pane-024 | add-row-label-text | Inspect the Add row's label | Text reads "Add:"; alignment is right |
| add-pane-025 | where-row-label-text | Inspect the Where row's label | Text reads "Where:"; alignment is right |

## Edge Cases

- Null/empty input (MUST): no entries offered yields an "Add" choice list
  with zero items and a selected index of -1; per
  **ok-button-disabled-when-choices-empty** OK is disabled at load, and per
  **confirm-dismisses-without-onadd-on-invalid-selection** even a forced
  confirm dismisses without reporting a selection, since -1 is never a valid
  index into the offered entries.
- Null/empty input (MUST): the caller-supplied selection callback and the
  offered entries are both required inputs, so there is no path where either
  is missing; the component provides, and needs, no nil-handling path for
  them.
- Boundary values (observed): the "Where" choice always contains exactly the
  four fixed directions, so its selected index is always valid (0 through
  3) through ordinary interaction; the bounds guard in the confirm action
  only ever fails, for "Where", in a hypothetical, non-interactive case.
- Boundary values (observed): the fallback that picks index 0 if "Right"
  were ever absent from the fixed direction list is unreachable in the
  current source, since that list is a fixed four-case list that always
  contains "Right" (see **Design Decisions**).
- Concurrent access: Not applicable — the component confines all reads and
  writes of its offered entries, its two choices, and its two buttons to a
  single thread.
- Error states: Not applicable — the component performs no I/O, no
  throwing call, and no asynchronous work; its only defensive path is the
  index-bounds guard in the confirm action, documented above as a
  boundary-value case rather than an error state.
- Offline/disconnected: Not applicable — the component makes no network
  call anywhere in source.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|--------------|
| `choices` | list of offerable entries | — (required) | The offerable views, in display order; empty disables OK and leaves the "Add" choice list empty. |
| `onAdd` | callback (view identifier, direction) → none | — (required) | Invoked once, after dismissal, when OK is activated with a valid selection. |

Each offerable entry (not a top-level configuration option itself) carries
three fields: a view identifier, a display name (the choice item's title),
and an optional icon name shown as that item's image.

## Deep Linking

Not applicable: this is a transient sheet with no URL scheme, route, or
deep-link handler in source; arrange mode's Add button presents it
programmatically.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| n/a (literal) | "Add:" | Row caption for the view-choice list |
| n/a (literal) | "Where:" | Row caption for the direction choice list |
| n/a (literal) | "Left" | Direction choice item |
| n/a (literal) | "Right" | Direction choice item (default selection) |
| n/a (literal) | "Above" | Direction choice item |
| n/a (literal) | "Below" | Direction choice item |
| n/a (literal) | "Cancel" | Cancel button title |
| n/a (literal) | "OK" | OK button title |

Every string above is a plain literal in source, none routed through a
localization function, so none reaches a string catalog.

Not applicable beyond the table above: each offered entry's own display
name shown in the "Add" choice list is supplied by the caller, not
hardcoded in this file, so localizing it is the caller's responsibility, not
this component's.

## Accessibility Options

- **Reduce Motion**: Not applicable — source defines no animation or
  transition of any kind; the sheet's content is built once, synchronously,
  when it loads.
- **Increase Contrast**: Every color in this file comes from a theme role
  (window-background, primary-text) resolved by the shared theme system;
  the file itself sets no literal color and performs no contrast-specific
  branching. Whether the resolved colors meet a minimum contrast ratio is
  determined by theme resolution, not this file — see Compliance's
  **contrast-ratio** check, marked partial for the same reason.
- **Differentiate Without Color**: Not applicable — the component conveys
  no state through color alone; the Add/Where choices and the OK/Cancel
  actions are identified by text and icons, not color.

## Feature Flags

Not applicable: the source contains no feature-flag or config-gating
lookup.

## Analytics

Not applicable: the source contains no analytics or telemetry call.

## Privacy

- **Data collected**: None beyond the in-memory selections the user makes
  while the sheet is open.
- **Storage**: None — selections live only in the two choices' selection
  state for the sheet's lifetime; nothing is written to disk, persistent
  settings storage, or any other store by this file.
- **Transmission**: None — the selection is handed directly to the caller
  in-process; this file makes no network or IPC call.
- **Retention**: None beyond the sheet's lifetime; the selection is
  discarded once the sheet is dismissed, whether via Cancel, OK, or an
  invalid-selection confirm.

## Logging

Not applicable: the source contains no logging call of any kind anywhere in
this file.

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
  state seeded to the first entry, or to no selection when `choices` is
  empty, one to a `selectedDirection` state seeded to the "right"
  direction. Render each Add-menu item with an
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
- **AppKit / UIKit** (source platform): Implemented in
  `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/ComposableTabs/ComposableTabsAddPaneViewController.swift`
  as a `@MainActor`, `final` `NSViewController` with no nib/XIB —
  `loadView()` builds an `NSGridView` of two `NSPopUpButton`s and their
  `ThemedLabel` captions, plus an `NSStackView` of Cancel/OK `NSButton`s,
  laid out with Auto Layout against a `ThemedBackgroundView` root. Arrange
  mode presents it as a sheet from its Add button. It also does not support
  construction via a coder-based initializer — Cocoa's `NSCoder`-driven
  `init(coder:)` — which this type overrides to trigger a fatal error
  immediately, since no code path in this app constructs this sheet from an
  archived storyboard/xib. There is no UIKit code path in source; a UIKit
  port would replace the two `NSPopUpButton`s with `UIButton`s presenting
  menus (or two rows of a grouped table/picker view), replace the grid with
  a stack view of horizontal rows, and present the whole thing as a small
  view controller in a form-sheet presentation, since UIKit has no direct
  analog of `NSGridView`/`NSPopUpButton`.
- **WinUI 3**: Build the sheet as a
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

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/ComposableTabs/ComposableTabsAddPaneViewController.swift` |

## Design Decisions

**Decision**: Split "what to add" and "where to put it" into two independent
popups rather than one flattened list (e.g. "Add Terminal Below").
**Rationale**: Per the type's doc comment, the second answer (the four
directions) is the same regardless of the first, so a flattened list would
force the user to read a cross product of eight or twelve items instead of
making two small choices.
**Approved**: pending

**Decision**: Default the "Where" popup's selection to "Right" rather than
the first item ("Left") or no selection.
**Rationale**: Per the source comment, the pane the user is looking at is on
the left of a document more often than not, so placing the new pane to its
right is the least surprising default.
**Approved**: pending

**Decision**: Dismiss the sheet before invoking `onAdd` in the confirm
action, rather than invoking `onAdd` first.
**Rationale (AppKit)**: Per the source comment, `onAdd` re-parents view
controllers by splitting the pane; doing that while the sheet is still
presented would leave the sheet anchored to a window whose content has
already moved out from under it.
**Approved**: pending

**Decision**: Fix the direction list to the hardcoded order left, right,
above, below and reuse that same list both to populate the "Where" popup
and to map its selected index back to a direction.
**Rationale**: Per the source comment, a fixed order makes the popup read
the way the pane visually looks; reusing one list for both population and
index-mapping keeps the two in sync by construction rather than by
convention.
**Approved**: pending

**Decision**: Center-align the grid's rows instead of using `NSGridView`'s
default first-baseline row alignment.
**Rationale (AppKit)**: Per the source comment, a label baseline-aligned
against a popup sits high in it, which reads as a row that did not quite
line up; centering both views in the row instead makes the label and popup
look vertically aligned.
**Approved**: pending

**Decision**: Leave a defensive fallback to index 0 for the "Right" lookup,
even though the direction list is a hardcoded literal that always contains
"Right".
**Rationale**: Not explained in source; recorded here as an observed,
currently-unreachable defensive path, so other-platform implementations do
not need to reproduce a "what if Right is missing" branch.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | accessibility |
| [focus-management](agenticdevelopercookbook://compliance/accessibility#focus-management) | passed | accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | accessibility |
| [string-externalization](agenticdevelopercookbook://compliance/internationalization#string-externalization) | failed | internationalization |

Keyboard-navigable passes because Cancel/OK carry the Escape/Return key
equivalents and every other control is a stock, natively keyboard-accessible
`NSPopUpButton`/`NSButton`. Screen-reader-support is partial: accessibility
identifiers back automation on every control and the SF Symbol images carry
descriptions, but neither popup is associated with its row caption via
`setAccessibilityTitleUIElement` (see **associates-popup-with-row-caption**).
Focus-management passes on the strength of AppKit's native sheet
presentation and dismissal, which this file does not override.
Contrast-ratio is partial because colors come entirely from
`ThemeRole` tokens resolved by the shared theme system, whose actual
contrast values are not stated in this file (see Accessibility Options'
Increase Contrast). String-externalization is failed because every label
in this file ("Add:",
"Where:", "Left", "Right", "Above", "Below", "Cancel", "OK") is a hardcoded
English literal with no localization key.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Claude Sonnet 5 | Initial ingredient recipe for ComposableTabsAddPaneViewController: two-popup Add/Where sheet, fixed direction order and Right default, dismiss-before-invoke confirm ordering, fixed-at-load OK enablement, and one open accessibility question (popup-to-caption label association) for review. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: reworded the confirm-dismisses-before-invoking-onadd requirement and its vector to assert that `dismiss(_:)` is invoked rather than completed; added a SHOULD requirement for popup-to-caption accessibility association, cited by the existing open-question marker; reformatted all Design Decisions into the canonical three-line block and trimmed the unreachable-fallback rationale to an observed path; added the ComposableTabsViewController recipe to depends-on; removed the inapplicable touch-target-size compliance row and reconciled the contrast-ratio/Increase Contrast cross-reference; fixed the AppKit / UIKit platform-note label and removed the WinUI 3 aside; clarified the Compose note's empty-choices seeding; relabeled two unreachable boundary-value edge cases as observations; gave literal key-equivalent values for add-pane-012/013; and named the confirm-action selector for add-pane-017. |
| 1.1.1 | 2026-09-23 | Mike Fullerton | Compliance: removed rows for checks absent from the cookbook catalog, remapped modal-dismissal-and-focus to focus-management |
| 1.1.2 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.3 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/layout/composable-tabs/. |
