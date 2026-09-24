---
id: 3a3e4da0-e900-4281-a19c-e29cbd34cbab
title: PopupMenuChoiceView
domain: agentictoolkit://recipes/popup-menu-choice-view
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A macOS ComposableSettings row pairing a title label with a borderless NSPopUpButton
  bound to a ChoiceViewModel's choices, mirroring System Settings' popup row.
platforms:
- swift
- macos
tags:
- settings
- form-control
- choice
- macos
- appkit
depends-on: []
related:
- agentictoolkit://recipes/choice-slider-view
- agentictoolkit://recipes/checkbox-view
references: []
approved-by: ''
approved-date: ''
---

# PopupMenuChoiceView

## Overview

`PopupMenuChoiceView` is a macOS `ComposableSettings` row
(`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/PopupMenuChoiceView.swift`):
a title label leading and a borderless `NSPopUpButton` trailing, matching
System Settings' card-drawn popup convention where the current value reads as
secondary text followed by a chevron pair, with no bezel boxing the control a
second time inside a card that already provides the surface. The popup's
menu items are built once, at construction, from a
`ComposableSettings.ChoiceViewModel<Value>`'s `choices` array — each item's
title, `representedObject`, and optional symbol image come from one `Choice`.
The view reflects the view model's title/value on construction and whenever
the view model reports an external change, and it writes the user's menu
selection back into the view model's `settingObserver`.

## Behavioral Requirements

- **arranges-row-layout**: Component MUST arrange the title label, a
  flexible spacer, and the popup button — in that order — in a single
  horizontal row, and MUST pin that row to the edges of the view.
- **populates-menu-items-from-choices**: Component MUST, during
  initialization, add one popup menu item per entry in `viewModel.choices`,
  in the array's order, titled with that choice's `label`.
- **attaches-choice-value-to-item**: Component MUST associate each added
  item with that choice's `value`, so the value can be retrieved when the
  item becomes selected. (AppKit mechanism: see Platform Notes.)
- **attaches-choice-image**: Component MUST attach that choice's symbol
  image to the added item when that choice's `imageSystemName` is
  non-`nil`. (AppKit mechanism: see Platform Notes.)
- **omits-choice-image-when-absent**: Component MUST NOT attach an image to
  an added item when that choice's `imageSystemName` is `nil`.
- **suppresses-popup-bezel**: Component MUST render the popup as a
  borderless control, with no bezel/box around it. (AppKit mechanism: see
  Platform Notes.)
- **resists-popup-stretch**: Component MUST size the popup to its own
  content rather than stretching to absorb the row's leftover horizontal
  space. (AppKit mechanism: see Platform Notes.)
- **links-popup-accessibility-title**: Component MUST associate the
  popup's accessible name with the visible label, so assistive technology
  announces the popup using the label's text instead of with no name.
  (AppKit mechanism: see Platform Notes.)
- **wires-popup-action**: Component MUST route the popup's
  selection-changed event to the component's own internal handler.
  (AppKit mechanism: see Platform Notes.)
- **initializes-from-view-model**: Component MUST, at the end of
  initialization, set the label's text to `viewModel.title` and, when
  `viewModel.choices` contains an entry whose `value` equals
  `viewModel.value`, select that entry in the popup.
- **commits-selection-value**: Component MUST commit the newly selected
  item's value into `viewModel.settingObserver.value` whenever the popup's
  selection changes, provided that value resolves to type `Value` and
  differs from the current `settingObserver.value`. (AppKit mechanism: see
  Platform Notes.)
- **ignores-unresolvable-selection**: Component MUST NOT write to
  `viewModel.settingObserver.value` when the selected item's value cannot
  be resolved to type `Value` (including when no item is selected).
- **skips-redundant-commits**: Component MUST NOT write to
  `viewModel.settingObserver.value` when the newly selected item's
  resolved value equals the current `settingObserver.value`.
- **syncs-on-external-change**: Component MUST re-set the label's text to
  `viewModel.title` and re-select the popup item matching `viewModel.value`
  (per **initializes-from-view-model**'s matching rule) whenever
  `viewModel.onChange` fires.
- **exposes-constituent-views**: Component MUST expose `label` and
  `popUpButton` as public, directly-accessible properties.
- **fixes-choice-set-at-construction**: Component MUST NOT add, remove, or
  reorder popup menu items after initialization; `viewModel.choices` is a
  `let` array consumed only inside `init`.
- **requires-designated-initializer**: Component MUST NOT support
  construction via `init(coder:)`; that initializer MUST trigger a fatal
  error.
- **rejects-frame-only-initialization**: Component MUST NOT support
  construction via the frame-only `init(frame:)`; that initializer MUST
  trigger a fatal error.
- **confines-to-main-actor**: Component MUST be usable only on the main
  actor; the class is declared `@MainActor`.
- **tolerates-empty-choices**: Component MUST construct without error when
  `viewModel.choices` is empty, adding zero popup menu items and leaving no
  item selected.
- **leaves-unmatched-selection**: Component MUST leave the popup's current
  selection uncorrected (neither cleared nor forced to a fallback) when
  `viewModel.value` matches no choice's `value`.
- **replaces-onchange-handler**: Component MUST assign its own handler to
  `viewModel.onChange` during initialization; doing so replaces any handler
  already registered on that view model instance (see Design Decisions).

## Appearance

- **Corner radius**: Not applicable — the component adds no custom layer or
  drawing code; it only composes a stock `NSTextField` label and a stock
  `NSPopUpButton` into a row.
- **Padding**: `ComposableSettings.makeRow` inserts a flexible spacer between
  `label` and `popUpButton` (`[label, spacer, popUpButton]`) and sets the
  `NSStackView`'s `spacing` to `SettingsLayout.default[.rowSpacing]` = 8pt,
  which applies to the label→spacer gap; `makeRow` explicitly zeroes the
  spacer→popup gap (`setCustomSpacing(0, after: spacer)`), so the spacer's
  own width is the only thing between the label and the popup. The
  component additionally pins `popUpButton`'s horizontal content-hugging
  priority to `.defaultHigh` (see **resists-popup-stretch**), so the
  spacer — not the popup — absorbs the row's leftover width. `pinToEdges`
  pins the row's top/leading/trailing/bottom directly to
  `PopupMenuChoiceView`'s edges with no additional constant, so the
  component contributes 0pt of its own outer padding beyond that internal
  8pt / 0pt spacing.
- **Font**: The label (`ComposableSettings.makeRowLabel`, `textRole:
  .button`) resolves to `ThemeTypography.defaultStyle(.button)`: 13pt,
  medium weight, proportional system font. The size scales with the active
  theme's `sizeScale` (`1.0` by default) and the label repaints
  automatically on a theme change via `ThemePaletteObserver`. `popUpButton`
  is a stock `NSPopUpButton`; no font is set on it in source, so it renders
  with AppKit's own default control font.
- **Background**: None (transparent) — `ThemedLabel.init` sets
  `drawsBackground = false`, `isBordered = false`, and `isBezeled = false`
  on the label, and neither `PopupMenuChoiceView` nor the row `NSStackView`
  sets `wantsLayer` or a background color of its own. `popUpButton` draws
  no bezel background once borderless (see Border).
- **Foreground/Text**: The label (`role: .primaryText`) resolves to the
  active theme's foreground color at full strength
  (`SemanticPalette.derive(.primaryText)` returns `theme.foreground`
  unchanged), recomputed live on a theme change via `ThemePaletteObserver`.
  `popUpButton`'s selected-item text color is AppKit's own borderless popup
  rendering (the source's comment describes it reading as "secondary
  text"); `PopupMenuChoiceView` sets no color on `popUpButton`.
- **Border**: None — `popUpButton.isBordered = false` removes
  `NSPopUpButton`'s default bezel; no other border is drawn or configured
  anywhere in `PopupMenuChoiceView.swift`.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere in
  `PopupMenuChoiceView.swift`.
- **Min/Max size**: Not applicable — no explicit min/max width or height
  constraint is set in `PopupMenuChoiceView.swift`; sizing is governed by
  the label's and `popUpButton`'s own intrinsic content sizes, the row's
  8pt spacing, the popup's `.defaultHigh` horizontal hugging, and
  `pinToEdges`.

## States

| State | Appearance change |
|-------|------------------|
| Default | Label shows `viewModel.title`; `popUpButton`'s selected item matches the choice whose `value` equals `viewModel.value`, if one exists. |
| Menu Open | Not styled by this file; `NSPopUpButton`'s own native menu presentation (item list, chevron pair) when clicked — not custom in source. |
| Item Selected | The item the user clicks becomes `popUpButton.selectedItem`; `popupChanged(_:)` then commits its `representedObject` (cast to `Value`) to `viewModel.settingObserver.value` per **commits-selection-value**, **ignores-unresolvable-selection**, and **skips-redundant-commits**. |
| Pressed | Not applicable: the component renders no button of its own; the popup's own press/active bezel-less appearance while its menu is open is `NSPopUpButton`'s default AppKit rendering, not custom to this file. |
| Disabled | Not implemented in `PopupMenuChoiceView`; `isEnabled` is never read or set on `label` or `popUpButton` in source. A caller may set `popUpButton.isEnabled` directly through the public `popUpButton` property, at which point `NSPopUpButton`'s native disabled dimming applies. |
| Focused | Not styled by `PopupMenuChoiceView`; any focus ring when the popup is tabbed to is `NSPopUpButton`'s own native `NSControl` focus appearance. |
| Loading | Not applicable: the component has no asynchronous operation and no loading indicator in source. |

## Accessibility

- **Role/trait**: Not customized beyond the title-element link below — no
  `setAccessibilityRole` call appears in source; `NSPopUpButton` carries
  AppKit's own built-in accessibility role for a pop-up button control.
- **Label requirements**: Component MUST set
  `popUpButton.setAccessibilityTitleUIElement(self.label)` — per the
  source's own comment, "the visible title label sits beside the popup but
  AppKit doesn't associate them, so VoiceOver would announce the popup with
  no name"; the visible label supplies the accessible name instead of a
  separate accessibility label string. Each menu item's own accessible name
  comes from its title (`choice.label`); an attached symbol image is given
  `accessibilityDescription: nil`, so the image itself contributes no
  separate spoken description beyond the item's title.
- **Announce state changes (e.g., loading, disabled)**: Not applicable —
  the component has no loading state and never disables itself in source
  (see States); the selected value is announced by `NSPopUpButton`'s own
  native accessibility value reporting when the selection changes, which
  `PopupMenuChoiceView` does not override.
- **Minimum tap target**: Not applicable — this is a macOS, pointer/
  trackpad-driven `NSView`/`NSControl` composition (no touch input path in
  source); the 44×44pt minimum is iOS/touch guidance, not a macOS
  pointer-interface requirement. `PopupMenuChoiceView` sets no
  `controlSize` on `popUpButton`, so it keeps `NSPopUpButton`'s regular
  system click-target metrics.
- **Minimum contrast ratio**: NEEDS REVIEW: Not implemented in source. The
  `label` text color resolves from the active theme's `.primaryText` role against
  the hosting background at runtime; the component performs no contrast
  check, so whether a given theme's resolved pair meets 4.5:1 cannot be
  determined from this file. This would be settled by a theme-level
  contrast audit of `.primaryText` against the backgrounds it sits on.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| popup-menu-choice-view-001 | arranges-row-layout | Construct `PopupMenuChoiceView` with any `viewModel` | The row view (an `NSStackView` from `makeRow`) is pinned to the component's edges; its subviews are exactly `[label, spacer, popUpButton]`, in that order; no other nested layout container appears within the row |
| popup-menu-choice-view-002 | populates-menu-items-from-choices | `viewModel.choices = [Choice(label: "A", value: .a), Choice(label: "B", value: .b)]` | After init, `popUpButton.itemArray.map(\.title) == ["A", "B"]` in that order |
| popup-menu-choice-view-003 | attaches-choice-value-to-item | Same `choices` as above | `popUpButton.item(at: 0)?.representedObject as? Value == .a`; `popUpButton.item(at: 1)?.representedObject as? Value == .b` |
| popup-menu-choice-view-004 | attaches-choice-image | `choices = [Choice(label: "A", value: .a, imageSystemName: "gearshape")]` | After init, `popUpButton.item(at: 0)?.image` is non-`nil` |
| popup-menu-choice-view-005 | omits-choice-image-when-absent | `choices = [Choice(label: "A", value: .a, imageSystemName: nil)]` | After init, `popUpButton.item(at: 0)?.image == nil` |
| popup-menu-choice-view-006 | suppresses-popup-bezel | Any initialized `PopupMenuChoiceView` | `popUpButton.isBordered == false` |
| popup-menu-choice-view-007 | resists-popup-stretch | Any initialized `PopupMenuChoiceView` | `popUpButton.contentHuggingPriority(for: .horizontal) == .defaultHigh` |
| popup-menu-choice-view-008 | links-popup-accessibility-title | Construct `PopupMenuChoiceView` with any `viewModel` | `popUpButton`'s accessibility title UI element is `label` |
| popup-menu-choice-view-009 | wires-popup-action | Any initialized `PopupMenuChoiceView` | `popUpButton.target === view`; `popUpButton.action == Selector("popupChanged:")` |
| popup-menu-choice-view-010 | initializes-from-view-model | `viewModel.title = "Theme"`, `viewModel.choices = [Choice(label: "Light", value: .light), Choice(label: "Dark", value: .dark)]`, `viewModel.value = .dark` | After init, `label.stringValue == "Theme"` and `popUpButton.indexOfSelectedItem == 1` |
| popup-menu-choice-view-011 | commits-selection-value | `viewModel.settingObserver.value = .light`; select the item whose `representedObject == .dark` and invoke `popupChanged(popUpButton)` | `viewModel.settingObserver.value == .dark` after the call |
| popup-menu-choice-view-012 | ignores-unresolvable-selection | Select an item whose `representedObject` is not of type `Value` (or with no item selected), then invoke `popupChanged(popUpButton)` | `viewModel.settingObserver.value`'s setter is not invoked; the value is unchanged |
| popup-menu-choice-view-013 | skips-redundant-commits | `viewModel.settingObserver.value = .dark`; select the item whose `representedObject == .dark` (same value) and invoke `popupChanged(popUpButton)` | `viewModel.settingObserver.value`'s setter is not invoked a second time (e.g. no additional write/observer notification is recorded) |
| popup-menu-choice-view-014 | syncs-on-external-change | After construction, externally change `viewModel.title` and `viewModel.value` to a different choice, then invoke `viewModel.onChange(newValue)` | `label.stringValue` and `popUpButton.indexOfSelectedItem` both update to reflect the new `viewModel` state |
| popup-menu-choice-view-015 | exposes-constituent-views | Construct the component, then access `.label` and `.popUpButton` from outside the type | Both properties are accessible and return the same `NSTextField`/`NSPopUpButton` instances built during init |
| popup-menu-choice-view-016 | fixes-choice-set-at-construction | Construct `PopupMenuChoiceView` with a fixed `choices` array, then invoke `popupChanged(_:)` with a selection change and `viewModel.onChange` with an external change | The component itself never mutates `popUpButton`'s items after `init`: `popUpButton.numberOfItems` immediately after construction equals its value after both invocations. (A caller may still mutate `popUpButton`'s items directly through the public `popUpButton` property — see **exposes-constituent-views** — this vector covers only the component's own code.) |
| popup-menu-choice-view-017 | requires-designated-initializer | Attempt `PopupMenuChoiceView(coder: someCoder)` | The call traps with a fatal error; no instance is returned |
| popup-menu-choice-view-018 | rejects-frame-only-initialization | Attempt `PopupMenuChoiceView(frame: .zero)` | The call traps with a fatal error; no instance is returned |
| popup-menu-choice-view-019 | confines-to-main-actor | Static/compile-time check, not a runtime vector: attempt to construct or mutate a `PopupMenuChoiceView` from off the main actor | The compiler rejects the call at compile time under Swift's `@MainActor` isolation checking; no runtime test applies |
| popup-menu-choice-view-020 | tolerates-empty-choices | `viewModel.choices = []` | Construction does not throw or trap; `popUpButton.numberOfItems == 0`; `popUpButton.indexOfSelectedItem == -1` (no item selected) |
| popup-menu-choice-view-021 | leaves-unmatched-selection | `viewModel.choices = [Choice(label: "A", value: .a)]`, `viewModel.value` set to a value matching no choice | After init, `popUpButton`'s selection is left as whatever `NSPopUpButton` selects by default (its first added item); no `selectItem(at:)` call clears or overrides it |
| popup-menu-choice-view-022 | replaces-onchange-handler | Register a closure on `viewModel.onChange`, then construct `PopupMenuChoiceView(viewModel: viewModel)` | After construction, invoking `viewModel.onChange` runs only the component's `syncSelection` handler; the previously registered closure is not invoked |

## Edge Cases

- Null/empty input: `viewModel` (`ComposableSettings.ChoiceViewModel<Value>`)
  is a non-optional, typed constructor parameter; Swift's type system rules
  out `nil`. An empty `viewModel.choices` array is handled per
  **tolerates-empty-choices**: the component constructs without crashing,
  adds zero menu items, and `syncSelection`'s `firstIndex(where:)` finds no
  match, so no item is selected — the popup renders AppKit's native
  empty-menu appearance.
- Boundary values: Not applicable — `choices` is an ordered, arbitrary-length
  list of discrete label/value pairs with no numeric minimum or maximum to
  bound.
- Concurrent access: Not applicable — the class is declared `@MainActor`,
  so all construction and mutation is serialized to the main actor by the
  compiler (see **confines-to-main-actor**).
- Error states: Not applicable — every operation in this file (menu item
  construction, the popup's target-action, and the `settingObserver.value`
  write) is a synchronous, non-throwing call; no `try`, `Result`, or
  error-producing API appears in source. The one failure-shaped path —
  `representedObject as? Value` failing — is handled by a silent `guard`
  return, not an error, and is documented as **MUST**
  (**ignores-unresolvable-selection**), not as an error state.
- Offline/disconnected: Not applicable — the component performs no
  networking of its own; it only reads from and writes to an in-process
  `ComposableSettings.ChoiceViewModel<Value>`.
- Non-matching current value: When `viewModel.value` does not equal any
  choice's `value`, `syncSelection`'s `firstIndex(where:)` returns `nil`
  and `selectItem(at:)` is never called — see **leaves-unmatched-selection**.
  The popup's displayed selection is left uncorrected: whatever item
  `NSPopUpButton` selects by default (its first added item), rather than
  being cleared or forced to a fallback.
- Overwritten external observer: `viewModel.onChange` is a single closure
  property. `PopupMenuChoiceView`'s initializer unconditionally assigns
  `viewModel.onChange = { [weak self] _ in self?.syncSelection() }` — see
  **replaces-onchange-handler** and the corresponding Design Decision.
  Constructing a second `PopupMenuChoiceView` (or any other observer)
  against the same view model instance silently drops whatever handler was
  previously registered there.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | `ComposableSettings.ChoiceViewModel<Value>` | — (required) | Supplies the row's title, ordered `choices` (each a `label`/`value`/optional `imageSystemName`), and current value; receives committed selection changes via `settingObserver.value`. The initializer also overwrites this view model's `onChange` closure with the component's own `syncSelection` handler (see Edge Cases and **replaces-onchange-handler**). `viewModel.explanation` (inherited from `AbstractViewModel`) is accepted by the initializer chain but is unsupported: `PopupMenuChoiceView` never reads or displays it. |

## Deep Linking

Not applicable: `PopupMenuChoiceView` is a row inside a composable settings
window, not a navigable screen; no URL scheme, route, or deep-link handler
appears anywhere in `PopupMenuChoiceView.swift`.

## Localization

Not applicable: the file contains no user-facing string literals of its
own. The row's title and every menu item's title come entirely from
`viewModel.title` and each `Choice.label`, values the caller provides, so
there is nothing for this component to localize itself.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: source contains no animation, transition, or `NSAnimationContext` call; every state change is an instantaneous property assignment (`label.stringValue`, `popUpButton.selectItem(at:)`). |
| Increase Contrast | Partial: `PopupMenuChoiceView.swift` sets no custom `NSColor` of its own on `popUpButton`, so any Increase Contrast response for the popup itself comes from AppKit's own default control rendering, not from code in this file. The label's color comes from the theme's `.primaryText` role (`SemanticPalette.derive`, resolving to a fixed `theme.foreground`); the source does not show that role itself adapting to Increase Contrast, so a stronger claim than "partial" is not supported here. |
| Differentiate Without Color | Not applicable: the current choice is communicated through the popup's own item title text (and an optional symbol image), not through a color-only signal introduced by this component. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears anywhere
in `PopupMenuChoiceView.swift`; the row always renders once constructed.

## Analytics

Not applicable: `PopupMenuChoiceView.swift` contains no analytics or
telemetry call.

## Privacy

- **Data collected**: Not applicable — the component collects no data of
  its own; it only displays choices and a value supplied by `viewModel`
  and reports selection changes back through `viewModel.settingObserver`.
- **Storage**: Not applicable — source performs no read/write to disk,
  `UserDefaults`, or any other store; persistence, if any, is owned by the
  `ComposableSettings.ChoiceViewModel<Value>`/`settingObserver`, which are
  not part of this file.
- **Transmission**: Not applicable — no networking call appears anywhere in
  source.
- **Retention**: Not applicable — the view retains only its own subviews
  (`label`, `popUpButton`) and its reference to `viewModel` for its own
  lifetime; it persists nothing beyond that.

## Logging

Not applicable: `PopupMenuChoiceView.swift` contains no logging call (no
`print`, `os_log`, or logger reference anywhere in source).

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
  before writing (**commits-selection-value**). There is no UIKit code path
  in source; a UIKit port would replace `NSPopUpButton` with a `UIButton`
  presenting a `UIMenu` (or a `UIPickerView`) and the `target`/`action`
  pattern with `.addTarget(_:action:for: .primaryActionTriggered)` or a
  `UIAction` handler per menu item. `UIView` inherits the same
  `init(coder:)`-vs-`init(frame:)` split that `NSView` does — a UIKit port
  would fatal-error both initializers the same way
  **requires-designated-initializer** and
  **rejects-frame-only-initialization** do on `NSView`.
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

## Design Decisions

**Decision**: Draw the popup fully borderless (`isBordered = false`)
instead of AppKit's default bezeled `NSPopUpButton`.
**Rationale**: Per the source's own comment, "System Settings draws a
popup inside a card without a bezel: the current value in secondary text
with the chevron pair after it. The card is the surface, so a second one
around the control just boxes a box."
**Approved**: pending

**Decision**: Pin the popup's horizontal content-hugging priority to
`.defaultHigh`.
**Rationale**: Keeps the popup sized to its content so `makeRow`'s
flexible spacer, not the popup, absorbs the row's leftover width — the
same spacer-absorbs-slack layout `CheckboxView`'s row relies on, made
explicit here because a borderless `NSPopUpButton`'s default hugging
behavior is not guaranteed to match a bordered one's.
**Approved**: pending

**Decision**: Link the popup's accessibility title to the label via
`setAccessibilityTitleUIElement` rather than setting a separate
accessibility label string.
**Rationale**: Per the source's own comment, "the visible title label
sits beside the popup but AppKit doesn't associate them, so VoiceOver
would announce the popup with no name."
**Approved**: pending

**Decision**: Silently ignore a selected item whose `representedObject`
fails the cast to `Value` (**ignores-unresolvable-selection**).
**Rationale**: `guard let value = sender.selectedItem?.representedObject
as? Value else { return }` in `popupChanged(_:)` is the only handling in
source; this documents the actual, traceable behavior rather than
assuming an error-reporting path exists.
**Approved**: pending

**Decision**: Leave a `viewModel.value` that matches no choice's value
uncorrected in `syncSelection` (**leaves-unmatched-selection**).
**Rationale**: `firstIndex(where:)` returning `nil` skips the
`selectItem(at:)` call entirely; the source neither clears the selection
nor forces a default item, so the popup keeps whatever item AppKit
selected by default — this documents the observed behavior, not an
idealized fallback.
**Approved**: pending

**Decision**: Unconditionally overwrite `viewModel.onChange` with the
component's own `syncSelection` handler at construction, rather than
composing with any handler already registered on that view model
(**replaces-onchange-handler**).
**Rationale**: `viewModel.onChange = { [weak self] _ in
self?.syncSelection() }` is plain closure-property assignment; the source
has no list- or token-based observer mechanism to compose with instead,
so a second observer of the same view model silently loses its handler.
Recorded here as an explicit, approved trade-off rather than left as an
undocumented trap in edge-case prose.
**Approved**: pending

**Decision**: Force a fatal error from both `init(coder:)` and the
frame-only `init(frame:)`, leaving the `viewModel`-taking initializer as
the only usable one.
**Rationale**: The view has no meaningful default state — it cannot
render a title, a choice list, or a value without a `viewModel` — so both
inherited `NSView` initializers that could construct it without one are
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
