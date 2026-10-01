---
id: 3a3e4da0-e900-4281-a19c-e29cbd34cbab
title: Popup Menu Choice View
domain: agentictoolkit://cookbook/ui/settings/rows/popup-menu-choice-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A settings row pairing a title label with a borderless popup control
  bound to a choice view model's choices, mirroring System Settings' popup row.
platforms:
- swift
- macos
tags:
- settings
- form-control
- choice
depends-on: []
related:
- agentictoolkit://cookbook/ui/settings/rows/choice-slider-view
- agentictoolkit://cookbook/ui/settings/rows/checkbox-view
references: []
approved-by: ''
approved-date: ''
---

# Popup Menu Choice View

## Overview

The Popup Menu Choice View is a settings row: a title label leading and a
borderless popup control trailing, matching System Settings' card-drawn
popup convention where the current value reads as secondary text followed
by a chevron pair, with no bezel boxing the control a second time inside a
card that already provides the surface. The popup's menu items are built
once, at construction, from the view model's ordered list of choices — each
item's title, value, and optional symbol image come from one choice. The
view reflects the view model's title/value on construction and whenever the
view model reports an external change, and it writes the user's menu
selection back into the view model.

## Behavioral Requirements

- **arranges-row-layout**: Component MUST arrange the title label, a
  flexible spacer, and the popup button — in that order — in a single
  horizontal row, and MUST pin that row to the edges of the view.
- **populates-menu-items-from-choices**: Component MUST, during
  initialization, add one popup menu item per entry in the view model's
  choices, in the list's order, titled with that choice's label.
- **attaches-choice-value-to-item**: Component MUST associate each added
  item with that choice's value, so the value can be retrieved when the
  item becomes selected. (Mechanism: see Platform Notes.)
- **attaches-choice-image**: Component MUST attach that choice's symbol
  image to the added item when that choice's image name is supplied.
  (Mechanism: see Platform Notes.)
- **omits-choice-image-when-absent**: Component MUST NOT attach an image to
  an added item when that choice's image name is absent.
- **suppresses-popup-bezel**: Component MUST render the popup as a
  borderless control, with no bezel/box around it. (Mechanism: see
  Platform Notes.)
- **resists-popup-stretch**: Component MUST size the popup to its own
  content rather than stretching to absorb the row's leftover horizontal
  space. (Mechanism: see Platform Notes.)
- **links-popup-accessibility-title**: Component MUST associate the
  popup's accessible name with the visible label, so assistive technology
  announces the popup using the label's text instead of with no name.
  (Mechanism: see Platform Notes.)
- **wires-popup-action**: Component MUST route the popup's
  selection-changed event to the component's own internal handler.
  (Mechanism: see Platform Notes.)
- **initializes-from-view-model**: Component MUST, at the end of
  initialization, set the label's text to the view model's title and,
  when the view model's choices contain an entry whose value equals the
  view model's value, select that entry in the popup.
- **commits-selection-value**: Component MUST commit the newly selected
  item's value into the view model's value whenever the popup's selection
  changes, provided that value resolves to the component's declared value
  type and differs from the current value. (Mechanism: see Platform
  Notes.)
- **ignores-unresolvable-selection**: Component MUST NOT write to the view
  model's value when the selected item's value cannot be resolved to the
  component's declared value type (including when no item is selected).
- **skips-redundant-commits**: Component MUST NOT write to the view
  model's value when the newly selected item's resolved value equals the
  current value.
- **syncs-on-external-change**: Component MUST re-set the label's text to
  the view model's title and re-select the popup item matching the view
  model's value (per **initializes-from-view-model**'s matching rule)
  whenever the view model's change-notification callback fires.
- **exposes-constituent-views**: Component MUST expose the label and the
  popup as public, directly-accessible properties.
- **fixes-choice-set-at-construction**: Component MUST NOT add, remove, or
  reorder popup menu items after initialization; the view model's choices
  are consumed only during construction.
- **confines-to-ui-thread**: Component MUST be usable only from the UI
  thread.
- **tolerates-empty-choices**: Component MUST construct without error when
  the view model's choices are empty, adding zero popup menu items and
  leaving no item selected.
- **leaves-unmatched-selection**: Component MUST leave the popup's current
  selection uncorrected (neither cleared nor forced to a fallback) when
  the view model's value matches no choice's value.
- **replaces-onchange-handler**: Component MUST assign its own handler to
  the view model's change-notification callback during initialization;
  doing so replaces any handler already registered on that view model
  instance (see Design Decisions).

## Appearance

- **Corner radius**: Not applicable — the component adds no custom layer or
  drawing code; it only composes a stock label and a stock popup control
  into a row.
- **Padding**: The row layout inserts a flexible spacer between the label
  and the popup (label, spacer, popup, in that order) and sets the row's
  spacing to `SettingsLayout.default[.rowSpacing]` = 8pt, which applies to
  the label→spacer gap; the spacer→popup gap is explicitly zeroed, so the
  spacer's own width is the only thing between the label and the popup.
  The component additionally pins the popup's horizontal content-hugging
  priority high (see **resists-popup-stretch**), so the spacer — not the
  popup — absorbs the row's leftover width. The row is pinned to the
  component's edges with no additional constant, so the component
  contributes 0pt of its own outer padding beyond that internal 8pt/0pt
  spacing.
- **Font**: The label uses the button text role, resolving to 13pt, medium
  weight, proportional system font. The size scales with the active
  theme's size scale (`1.0` by default) and the label repaints
  automatically on a theme change. The popup is a stock control; no font
  is set on it in source, so it renders with the platform's own default
  control font.
- **Background**: None (transparent) — the label draws no background or
  border of its own, and neither the view nor the row layout sets a
  background color of its own. The popup draws no bezel background once
  borderless (see Border).
- **Foreground/Text**: The label (`.primaryText` role) resolves to the
  active theme's foreground color at full strength, recomputed live on a
  theme change. The popup's selected-item text color is the platform's own
  borderless popup rendering (the design rationale describes it reading as
  "secondary text"); this component sets no color on the popup.
- **Border**: None — the popup's borderless setting removes its default
  bezel; no other border is drawn or configured anywhere in this
  component.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere in
  this component.
- **Min/Max size**: Not applicable — no explicit min/max width or height
  constraint is set in source; sizing is governed by the label's and the
  popup's own intrinsic content sizes, the row's 8pt spacing, the popup's
  high horizontal hugging, and the row's edge pinning.

## States

| State | Appearance change |
|-------|------------------|
| Default | Label shows the view model's title; the popup's selected item matches the choice whose value equals the view model's value, if one exists. |
| Menu Open | Not styled by this component; the popup's own native menu presentation (item list, chevron pair) when clicked — not custom in source. |
| Item Selected | The item the user clicks becomes the popup's selected item; the component's internal handler then commits its associated value to the view model per **commits-selection-value**, **ignores-unresolvable-selection**, and **skips-redundant-commits**. |
| Pressed | Not applicable: the component renders no button of its own; the popup's own press/active bezel-less appearance while its menu is open is the platform's default rendering, not custom to this component. |
| Disabled | Not implemented in this component; the enabled state is never read or set on either control in source. A caller may set the popup's enabled state directly through the public popup property, at which point the platform's native disabled dimming applies. |
| Focused | Not styled by this component; any focus ring when the popup is tabbed to is the popup's own native focus appearance. |
| Loading | Not applicable: the component has no asynchronous operation and no loading indicator in source. |

## Accessibility

- **Role/trait**: Not customized beyond the title-element link below — no
  explicit accessibility role override appears in source; the popup
  carries the platform's own built-in accessibility role for a pop-up
  button control.
- **Label requirements**: Component MUST associate the popup's accessible
  name with the visible label — per the design rationale, "the visible
  title label sits beside the popup but the platform doesn't associate
  them, so a screen reader would announce the popup with no name"; the
  visible label supplies the accessible name instead of a separate
  accessibility label string. Each menu item's own accessible name comes
  from its title (the choice's label); an attached symbol image is given
  no separate accessibility description, so the image itself contributes
  no separate spoken description beyond the item's title.
- **Announce state changes (e.g., loading, disabled)**: Not applicable —
  the component has no loading state and never disables itself in source
  (see States); the selected value is announced by the popup's own native
  accessibility value reporting when the selection changes, which this
  component does not override.
- **Minimum tap target**: Not applicable — this is a pointer/trackpad-driven
  control composition (no touch input path in source); the 44×44pt
  minimum is touch guidance, not a pointer-interface requirement. This
  component sets no reduced control size on the popup, so it keeps the
  platform's regular system click-target metrics.
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented in source. The
  label text color resolves from the active theme's `.primaryText` role
  against the hosting background at runtime; the component performs no
  contrast check, so whether a given theme's resolved pair meets 4.5:1
  cannot be determined from this component's definition — settled by a
  theme-level contrast audit of `.primaryText` against the backgrounds it
  sits on.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| popup-menu-choice-view-001 | arranges-row-layout | Construct the component with any view model | The row is pinned to the component's edges; its elements are exactly the label, a spacer, and the popup, in that order; no other nested layout container appears within the row |
| popup-menu-choice-view-002 | populates-menu-items-from-choices | View model's choices = `[Choice(label: "A", value: .a), Choice(label: "B", value: .b)]` | After init, the popup's item titles == `["A", "B"]` in that order |
| popup-menu-choice-view-003 | attaches-choice-value-to-item | Same choices as above | The popup's first item's associated value == `.a`; its second item's associated value == `.b` |
| popup-menu-choice-view-004 | attaches-choice-image | Choices = `[Choice(label: "A", value: .a, imageSystemName: "gearshape")]` | After init, the popup's first item has an image |
| popup-menu-choice-view-005 | omits-choice-image-when-absent | Choices = `[Choice(label: "A", value: .a, imageSystemName: none)]` | After init, the popup's first item has no image |
| popup-menu-choice-view-006 | suppresses-popup-bezel | Any initialized component | The popup renders borderless |
| popup-menu-choice-view-007 | resists-popup-stretch | Any initialized component | The popup's horizontal content-hugging priority is high |
| popup-menu-choice-view-008 | links-popup-accessibility-title | Construct the component with any view model | The popup's accessible name is associated with the label |
| popup-menu-choice-view-009 | wires-popup-action | Any initialized component | Selecting an item in the popup routes to the component's own selection-changed handler |
| popup-menu-choice-view-010 | initializes-from-view-model | View model's title = `"Theme"`, choices = `[Choice(label: "Light", value: .light), Choice(label: "Dark", value: .dark)]`, value = `.dark` | After init, the label's text == `"Theme"` and the popup's selected item is the second one ("Dark") |
| popup-menu-choice-view-011 | commits-selection-value | View model's value = `.light`; select the item whose value == `.dark` and trigger the popup's selection-changed handler | The view model's value == `.dark` after the call |
| popup-menu-choice-view-012 | ignores-unresolvable-selection | Select an item whose associated value is not of the declared value type (or with no item selected), then trigger the selection-changed handler | The view model's value is not written; it remains unchanged |
| popup-menu-choice-view-013 | skips-redundant-commits | View model's value = `.dark`; select the item whose value == `.dark` (same value) and trigger the selection-changed handler | The view model's value is not written a second time (e.g. no additional write/observer notification is recorded) |
| popup-menu-choice-view-014 | syncs-on-external-change | After construction, externally change the view model's title and value to a different choice, then invoke its change-notification callback | The label's text and the popup's selected item both update to reflect the new view-model state |
| popup-menu-choice-view-015 | exposes-constituent-views | Construct the component, then access the label and popup properties from outside the type | Both properties are accessible and return the same instances built during init |
| popup-menu-choice-view-016 | fixes-choice-set-at-construction | Construct the component with a fixed choices list, then trigger a selection change and an external view-model change | The component itself never mutates the popup's items after construction: the popup's item count immediately after construction equals its value after both invocations. (A caller may still mutate the popup's items directly through the public popup property — see **exposes-constituent-views** — this vector covers only the component's own code.) |
| popup-menu-choice-view-019 | confines-to-ui-thread | Attempt to construct or mutate the component from a thread other than the UI thread | The platform rejects or prevents the attempt (statically or at runtime, depending on platform — see Platform Notes) |
| popup-menu-choice-view-020 | tolerates-empty-choices | View model's choices = `[]` | Construction does not throw or trap; the popup has zero items; no item is selected |
| popup-menu-choice-view-021 | leaves-unmatched-selection | Choices = `[Choice(label: "A", value: .a)]`, view model's value set to a value matching no choice | After init, the popup's selection is left as whatever it selects by default (its first added item); no explicit selection call clears or overrides it |
| popup-menu-choice-view-022 | replaces-onchange-handler | Register a callback on the view model's change-notification property, then construct the component with that view model | After construction, invoking the view model's change-notification callback runs only the component's own sync handler; the previously registered callback is not invoked |

## Edge Cases

- Null/empty input: The view model is a required, non-optional constructor
  parameter, so a missing value is not possible. An empty choices list is
  handled per **tolerates-empty-choices**: the component constructs
  without crashing, adds zero menu items, and no item is selected — the
  popup renders the platform's native empty-menu appearance.
- Boundary values: Not applicable — choices is an ordered, arbitrary-length
  list of discrete label/value pairs with no numeric minimum or maximum to
  bound.
- Concurrent access: Not applicable — the component is confined to a
  single execution context (see **confines-to-ui-thread**), so all
  construction and mutation is serialized to that context.
- Error states: Not applicable — every operation in this component (menu
  item construction, the popup's selection handling, and the committed
  write) is a synchronous, non-throwing call; no error-producing API
  appears in source. The one failure-shaped path — an unresolvable
  selected value — is handled by a silent guard, not an error, and is
  documented as MUST (**ignores-unresolvable-selection**), not as an error
  state.
- Offline/disconnected: Not applicable — the component performs no
  networking of its own; it only reads from and writes to an in-process
  view model.
- Non-matching current value: When the view model's value does not equal
  any choice's value, no matching entry is found and no selection call is
  made — see **leaves-unmatched-selection**. The popup's displayed
  selection is left uncorrected: whatever item it selects by default (its
  first added item), rather than being cleared or forced to a fallback.
- Overwritten external observer: The view model's change-notification
  callback is a single property. This component's initializer
  unconditionally assigns its own sync handler — see
  **replaces-onchange-handler** and the corresponding Design Decision.
  Constructing a second instance of this component (or any other observer)
  against the same view model instance silently drops whatever handler was
  previously registered there.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | choice view model | — (required) | Supplies the row's title, ordered choices (each a label/value/optional symbol name), and current value; receives committed selection changes. The initializer also overwrites this view model's change-notification callback with the component's own sync handler (see Edge Cases and **replaces-onchange-handler**). An inherited `explanation` field is accepted by the initializer chain but is unsupported: this component never reads or displays it. |

## Deep Linking

Not applicable: this component is a row inside a composable settings
window, not a navigable screen; no URL scheme, route, or deep-link handler
applies.

## Localization

Not applicable: the component defines no user-facing string literals of
its own. The row's title and every menu item's title come entirely from
the view model's title and each choice's label, values the caller
provides, so there is nothing for this component to localize itself.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: this component contains no animation or transition; every state change is an instantaneous update (the label's text, the popup's selection). |
| Increase Contrast | Partial: this component sets no custom color of its own on the popup, so any Increase Contrast response for the popup itself comes from the platform's own default control rendering, not from this component. The label's color comes from the theme's `.primaryText` role, resolving to a fixed foreground color; the source does not show that role itself adapting to Increase Contrast, so a stronger claim than "partial" is not supported here. |
| Differentiate Without Color | Not applicable: the current choice is communicated through the popup's own item title text (and an optional symbol image), not through a color-only signal introduced by this component. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears
anywhere in this component; the row always renders once constructed.

## Analytics

Not applicable: this component contains no analytics or telemetry call.

## Privacy

- **Data collected**: Not applicable — the component collects no data of
  its own; it only displays choices and a value supplied by the view
  model and reports selection changes back through it.
- **Storage**: Not applicable — this component performs no read/write to
  disk, or any other persistent store; persistence, if any, is owned by
  the view model layer, which is not part of this component.
- **Transmission**: Not applicable — no networking call appears anywhere
  in source.
- **Retention**: Not applicable — the view retains only its own subviews
  (label, popup) and its reference to the view model for its own
  lifetime; it persists nothing beyond that.

## Logging

Not applicable: this component contains no logging call (no print, log,
or logger reference anywhere in source).

## Platform Notes

- **SwiftUI**: Replace with a `Picker(viewModel.title, selection: $value)`
  built from `ForEach(viewModel.choices, id: \.value)` rows, each branching
  on `choice.imageSystemName`: `Label(choice.label, systemImage:
  symbolName)` when it is non-`nil`, or plain `Text(choice.label)` when it
  is `nil` — never `systemImage: choice.imageSystemName ?? ""`, since an
  empty symbol name renders a broken image — with `.pickerStyle(.menu)` to
  match the borderless popup affordance; wrap it
  with a leading `Text(viewModel.title)` in an `HStack` (or a
  `LabeledContent`) if the row shape from `makeRow` should be kept
  literally rather than relying on `Picker`'s own built-in label. Commit
  the selection to the underlying setting from the `Binding`'s setter with
  an equality guard, mirroring skips-redundant-commits; a selection whose
  raw value doesn't decode to a known choice mirrors
  ignores-unresolvable-selection by leaving the setting unchanged.
- **Compose**: Use an `ExposedDropdownMenuBox` (or a plain `Row` opening a
  `DropdownMenu`) with a leading `Text(title)` and a trailing read-only
  field/anchor showing the current choice's label; each `DropdownMenuItem`
  renders `choice.label`, with an optional leading `Icon` when an icon
  resource is supplied (the Compose analog of `imageSystemName`). Commit
  the tapped item's value to the backing state/view-model in
  `onClick`/`onItemSelected` with an equality check before writing,
  mirroring skips-redundant-commits, and leave the state unchanged if the
  clicked item's value can't be resolved, mirroring
  ignores-unresolvable-selection.
- **React/Web**: A flex row (`display: flex; align-items: center;
  justify-content: space-between`) containing a `<label>` for the title and
  a `<select>` whose `<option>` elements are built from `choices` (value =
  the choice's serialized value, text = `choice.label`), with the
  `<select>`'s `aria-labelledby` (or an explicit `<label for>`) pointing at
  the title `<label>`'s `id` — the web analog of
  `setAccessibilityTitleUIElement`. Commit the new value on the `<select>`'s
  `onChange` handler, comparing against the previous value before calling
  the parent's setter to mirror skips-redundant-commits, and ignoring a
  value that doesn't map to a known option to mirror
  ignores-unresolvable-selection.
- **AppKit/UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/PopupMenuChoiceView.swift`.
  A macOS-only (`import AppKit`) `NSView` subclass, `@MainActor`, generic
  over `Value: Codable & Sendable & Equatable`, inside the
  `ComposableSettings` namespace, conforming to `SettingsViewProtocol`. It
  composes two subviews — an `NSTextField` label from
  `ComposableSettings.makeRowLabel` and a borderless `NSPopUpButton`
  populated from `ChoiceViewModel.choices` — into one row via
  `ComposableSettings.makeRow` and `pinToEdges`. Per added item,
  **attaches-choice-value-to-item** is implemented by setting
  `representedObject` to `choice.value`, and **attaches-choice-image** by
  setting `image` to `NSImage(systemSymbolName: choice.imageSystemName,
  accessibilityDescription: nil)` when non-`nil`.
  **suppresses-popup-bezel** is `popUpButton.isBordered = false`;
  **resists-popup-stretch** is
  `popUpButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)`.
  **links-popup-accessibility-title** is
  `popUpButton.setAccessibilityTitleUIElement(label)`.
  **wires-popup-action** sets `popUpButton.target` to `self` and
  `popUpButton.action` to `Selector("popupChanged:")`, whose handler reads
  `sender.selectedItem?.representedObject as? Value`, guarding on the cast
  to implement **ignores-unresolvable-selection**, and on an equality check
  against `settingObserver.value` to implement **skips-redundant-commits**
  before writing (**commits-selection-value**). It supports construction
  only through the `viewModel`-taking initializer: both `init(coder:)` and
  the frame-only `init(frame:)` trigger a fatal error rather than
  producing an instance, and the type is `@MainActor`-isolated, so the
  compiler rejects construction or mutation of `self` from off the main
  actor. There is no UIKit code path in source; a UIKit port would replace
  `NSPopUpButton` with a `UIButton` presenting a `UIMenu` (or a
  `UIPickerView`) and the `target`/`action` pattern with
  `.addTarget(_:action:for: .primaryActionTriggered)` or a `UIAction`
  handler per menu item. `UIView` inherits the same
  `init(coder:)`-vs-`init(frame:)` split that `NSView` does — a UIKit port
  would fatal-error both initializers the same way this source's
  designated-initializer-only construction rule does.
- **WinUI 3** (the reason this recipe exists): Build the row as a `Grid`
  with column definitions `*,Auto`: a `TextBlock` for the title in column 0
  (the `*` column lets the title claim the row's leading space, the WinUI
  analog of `makeRow`'s flexible spacer sitting between the label and the
  control); a `ComboBox` in column 1, `HorizontalAlignment="Right"`, styled
  without its default border/background (`BorderThickness="0"`,
  `Background="Transparent"`) to match `isBordered = false`'s bezel-less
  popup. Bind `ItemsSource` to the `choices` collection with
  `DisplayMemberPath="Label"` and `SelectedValuePath="Value"` (the WinUI
  analog of a menu item's title and `representedObject`); when a choice
  carries an icon, replace the plain `DisplayMemberPath` binding with a
  `ComboBoxItem` `DataTemplate` containing a `StackPanel` of a `FontIcon`
  (bound to the choice's icon glyph) followed by a `TextBlock` for
  `Label`, the WinUI analog of `NSImage(systemSymbolName:)`. Set
  `AutomationProperties.LabeledBy` on the `ComboBox` to the `TextBlock` —
  the WinUI analog of `setAccessibilityTitleUIElement` linking a bare
  control's name to its visible label. Commit the selection from
  `SelectionChanged`, first checking `SelectedValue` resolves to a known
  choice value (mirroring ignores-unresolvable-selection) and only
  then writing through a property setter that skips the assignment (and so
  skips raising `INotifyPropertyChanged`) when the incoming value already
  equals the current value, mirroring skips-redundant-commits.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/PopupMenuChoiceView.swift` |

## Design Decisions

**Decision**: Draw the popup fully borderless instead of the platform's
default bezeled popup control (AppKit/UIKit source: `isBordered = false`).
**Rationale**: Per the source's own comment, "System Settings draws a
popup inside a card without a bezel: the current value in secondary text
with the chevron pair after it. The card is the surface, so a second one
around the control just boxes a box."
**Approved**: pending

**Decision**: Pin the popup's horizontal content-hugging priority high
(AppKit/UIKit source: `.defaultHigh`).
**Rationale**: Keeps the popup sized to its content so the row's flexible
spacer, not the popup, absorbs the row's leftover width — the same
spacer-absorbs-slack layout the checkbox row relies on, made explicit here
because a borderless popup control's default hugging behavior is not
guaranteed to match a bordered one's.
**Approved**: pending

**Decision**: Link the popup's accessibility title to the label rather
than setting a separate accessibility label string (AppKit/UIKit source:
`setAccessibilityTitleUIElement`).
**Rationale**: Per the source's own comment, "the visible title label
sits beside the popup but AppKit doesn't associate them, so a screen
reader would announce the popup with no name."
**Approved**: pending

**Decision**: Silently ignore a selected item whose associated value
fails to resolve to the declared value type (**ignores-unresolvable-selection**).
**Rationale**: `guard let value = sender.selectedItem?.representedObject
as? Value else { return }` in `popupChanged(_:)` (AppKit/UIKit source) is
the only handling in source; this documents the actual, traceable behavior
rather than assuming an error-reporting path exists.
**Approved**: pending

**Decision**: Leave a view model value that matches no choice's value
uncorrected (**leaves-unmatched-selection**).
**Rationale**: `firstIndex(where:)` returning `nil` (AppKit/UIKit source,
in `syncSelection`) skips the `selectItem(at:)` call entirely; the source
neither clears the selection nor forces a default item, so the popup
keeps whatever item it selected by default — this documents the observed
behavior, not an idealized fallback.
**Approved**: pending

**Decision**: Unconditionally overwrite the view model's change-notification
callback with the component's own sync handler at construction, rather
than composing with any handler already registered on that view model
(**replaces-onchange-handler**).
**Rationale**: `viewModel.onChange = { [weak self] _ in
self?.syncSelection() }` (AppKit/UIKit source) is plain closure-property
assignment; the source has no list- or token-based observer mechanism to
compose with instead, so a second observer of the same view model silently
loses its handler. Recorded here as an explicit, approved trade-off rather
than left as an undocumented trap in edge-case prose.
**Approved**: pending

**Decision**: Force a construction failure from both out-of-band
initialization paths, leaving the view-model-taking initializer as the
only usable one (AppKit/UIKit source: `init(coder:)` and the frame-only
`init(frame:)` both trigger a fatal error).
**Rationale**: The view has no meaningful default state — it cannot
render a title, a choice list, or a value without a view model — so both
inherited initializers that could construct it without one are
intentionally disabled rather than left to produce a half-configured row.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | platform-compliance |
| [platform-design-language](agenticdevelopercookbook://compliance/platform-compliance#platform-design-language) | passed | platform-compliance |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | partial | accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | passed | accessibility |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | reliability |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |

`screen-reader-support` and `idempotent-operations` rest on
**links-popup-accessibility-title** and **skips-redundant-commits**/
**ignores-unresolvable-selection**, all traceable to source;
`keyboard-navigable` is `partial` because no requirement or test vector in
this file exercises keyboard input — the source relies entirely on
`NSPopUpButton`'s own inherited keyboard handling, which this file neither
configures nor overrides.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: reworded AppKit-specific requirements to platform-neutral behavior with API mechanics moved to Platform Notes; renamed ignores-non-matching-representedObject to ignores-unresolvable-selection; promoted the empty-choices, unmatched-selection, and onChange-overwrite edge cases to named requirements with test vectors; recorded the onChange overwrite as an approved Design Decision; reformatted Design Decisions to the three-line convention and dropped the doc-authoring-only entry and the unsupported-explanation entry; fixed test vectors 001, 016, and 019 and the arranges-row-layout requirement for the row's spacer and construction-time-only item mutation; corrected the false UIKit initializer-split claim and the SwiftUI empty-symbol-name fallback in Platform Notes; softened the Increase Contrast claim to partial; added checkbox-view to related; added the initial Change History row; cleaned up the Compliance table against the catalog; records the unverified theme-token contrast as an open question. |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/settings/rows/. |
