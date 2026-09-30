<!-- leaf: implement-composable-tabs/add-pane-view-controller · source: composable-tabs-add-pane-view-controller.md -->

**Rules** (cite as `implement-composable-tabs/add-pane-view-controller#<slug>`):

- `populates-view-popup-from-choices` MUST
- `sets-choice-icon-when-symbol-present` MUST
- `omits-choice-icon-when-symbol-absent` MUST
- `populates-where-popup-in-fixed-order` MUST
- `defaults-where-selection-to-right` MUST
- `arranges-add-and-where-as-two-row-grid` MUST
- `add-row-precedes-where-row` MUST
- `ok-button-disabled-when-choices-empty` MUST
- `ok-button-enabled-when-choices-present` MUST
- `ok-button-enabled-state-fixed-at-load` MUST
- `cancel-precedes-ok-in-button-order` MUST
- `cancel-bound-to-escape-key` MUST
- `ok-bound-to-return-key` MUST
- `cancel-dismisses-without-invoking-onadd` MUST
- `confirm-dismisses-before-invoking-onadd` MUST
- `confirm-invokes-onadd-with-selection` MUST
- `confirm-dismisses-without-onadd-on-invalid-selection` MUST
- `enforces-minimum-container-width` MUST
- `root-view-accessibility-identifier` MUST
- `view-popup-accessibility-identifier` MUST
- `where-popup-accessibility-identifier` MUST
- `cancel-button-accessibility-identifier` MUST
- `ok-button-accessibility-identifier` MUST
- `add-row-label-text` MUST
- `where-row-label-text` MUST
- `coder-initialization-unsupported` MUST
- `associates-popup-with-row-caption` SHOULD

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
  MUST be computed once, from `choices`, at `loadView()` time; enablement
  depends only on `choices`, not on either popup's selection.
- **cancel-precedes-ok-in-button-order**: The Cancel button MUST be
  positioned before the OK button, left to right.
- **cancel-bound-to-escape-key**: The Cancel button's key equivalent MUST be
  the Escape key.
- **ok-bound-to-return-key**: The OK button's key equivalent MUST be the
  Return key.
- **cancel-dismisses-without-invoking-onadd**: Activating Cancel MUST
  dismiss the view controller and MUST NOT invoke `onAdd`.
- **confirm-dismisses-before-invoking-onadd**: Activating OK with a valid
  selection MUST invoke `dismiss(_:)` before invoking `onAdd`.
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
- **associates-popup-with-row-caption**: Each popup SHOULD be associated
  with its row's caption ("Add:" / "Where:") so VoiceOver announces the
  caption together with the popup's current value.

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
  `displayName`) on its popup-item image. Per
  **associates-popup-with-row-caption**, neither popup is associated with
  its row caption ("Add:" / "Where:") via `setAccessibilityTitleUIElement`
  or an explicit `accessibilityLabel` override anywhere in source, so
  VoiceOver announces only the popup's current value (e.g. "Right")
  without the "Where" context a sighted user gets from the adjacent label.
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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|--------------|
| `choices` | `[Choice]` | — (required) | The offerable views, in display order; empty disables OK and leaves the "Add" popup empty. |
| `onAdd` | `(ComposableTabsViewID, Direction) -> Void` | — (required) | Invoked once, after dismissal, when OK is activated with a valid selection. |

`Choice` (a nested public struct, not a top-level init option) carries three
fields per offerable entry: `viewID` (`ComposableTabsViewID`), `displayName`
(`String`, the popup item's title), and `symbolName` (`String?`, an optional
SF Symbol name shown as that item's image).

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

Every string above is a plain AppKit `String` literal (for example
`NSButton(title: "Cancel", …)` and `NSButton(title: "OK", …)` at
ComposableTabsAddPaneViewController.swift and :75, and the
`"Add:"`/`"Where:"` captions at :82–83), none routed through
`String(localized:)` or `NSLocalizedString`, so none reaches a string
catalog.

Not applicable beyond the table above: each `choices` entry's own
`displayName` shown in the "Add" popup is supplied by the caller, not
hardcoded in this file, so localizing it is the caller's responsibility, not
this component's.

