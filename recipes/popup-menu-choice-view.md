---
id: 3a3e4da0-e900-4281-a19c-e29cbd34cbab
title: PopupMenuChoiceView
domain: agentictoolkit://recipes/popup-menu-choice-view
type: ingredient
version: 1.0.0
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

- **arranges-row-layout**: Component MUST arrange the title label and the
  popup button in a single horizontal row (`label`, then `popUpButton`), and
  MUST pin that row to the edges of the view.
- **populates-menu-items-from-choices**: Component MUST, during
  initialization, add one popup menu item per entry in `viewModel.choices`,
  in the array's order, titled with that choice's `label`.
- **attaches-choice-value-to-item**: Component MUST set each added item's
  `representedObject` to that choice's `value`.
- **attaches-choice-image**: Component MUST set an added item's `image` to
  `NSImage(systemSymbolName: choice.imageSystemName, accessibilityDescription:
  nil)` when that choice's `imageSystemName` is non-`nil`.
- **omits-choice-image-when-absent**: Component MUST NOT set an image on an
  added item when that choice's `imageSystemName` is `nil`.
- **suppresses-popup-bezel**: Component MUST set `popUpButton.isBordered =
  false`.
- **resists-popup-stretch**: Component MUST set the popup button's
  horizontal content-hugging priority to `.defaultHigh`.
- **links-popup-accessibility-title**: Component MUST set the popup button's
  accessibility title UI element to the label
  (`popUpButton.setAccessibilityTitleUIElement(label)`).
- **wires-popup-action**: Component MUST set `popUpButton.target` to itself
  and `popUpButton.action` to its `popupChanged(_:)` selector.
- **initializes-from-view-model**: Component MUST, at the end of
  initialization, set the label's text to `viewModel.title` and, when
  `viewModel.choices` contains an entry whose `value` equals
  `viewModel.value`, select that entry's item in `popUpButton`.
- **commits-selection-value**: Component MUST write the newly selected
  item's `representedObject`, cast to `Value`, into
  `viewModel.settingObserver.value` whenever `popupChanged(_:)` fires and
  the cast succeeds and the new value differs from the current
  `settingObserver.value`.
- **ignores-non-matching-representedObject**: Component MUST NOT write to
  `viewModel.settingObserver.value` when the selected item's
  `representedObject` cannot be cast to `Value` (including a `nil` selected
  item).
- **skips-redundant-commits**: Component MUST NOT write to
  `viewModel.settingObserver.value` when the newly selected item's cast
  value equals the current `settingObserver.value`.
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
| Item Selected | The item the user clicks becomes `popUpButton.selectedItem`; `popupChanged(_:)` then commits its `representedObject` (cast to `Value`) to `viewModel.settingObserver.value` per **commits-selection-value**, **ignores-non-matching-representedObject**, and **skips-redundant-commits**. |
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

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| popup-menu-choice-view-001 | arranges-row-layout | Construct `PopupMenuChoiceView` with any `viewModel` | `label` and `popUpButton` are both subviews of a single row view that is pinned to the component's edges; no other layout container appears |
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
| popup-menu-choice-view-012 | ignores-non-matching-representedObject | Select an item whose `representedObject` is not of type `Value` (or with no item selected), then invoke `popupChanged(popUpButton)` | `viewModel.settingObserver.value`'s setter is not invoked; the value is unchanged |
| popup-menu-choice-view-013 | skips-redundant-commits | `viewModel.settingObserver.value = .dark`; select the item whose `representedObject == .dark` (same value) and invoke `popupChanged(popUpButton)` | `viewModel.settingObserver.value`'s setter is not invoked a second time (e.g. no additional write/observer notification is recorded) |
| popup-menu-choice-view-014 | syncs-on-external-change | After construction, externally change `viewModel.title` and `viewModel.value` to a different choice, then invoke `viewModel.onChange(newValue)` | `label.stringValue` and `popUpButton.indexOfSelectedItem` both update to reflect the new `viewModel` state |
| popup-menu-choice-view-015 | exposes-constituent-views | Construct the component, then access `.label` and `.popUpButton` from outside the type | Both properties are accessible and return the same `NSTextField`/`NSPopUpButton` instances built during init |
| popup-menu-choice-view-016 | fixes-choice-set-at-construction | Construct `PopupMenuChoiceView` with a fixed `choices` array | No public API on the component adds, removes, or reorders `popUpButton`'s items after construction; `popUpButton.numberOfItems` stays equal to `viewModel.choices.count` for the component's lifetime |
| popup-menu-choice-view-017 | requires-designated-initializer | Attempt `PopupMenuChoiceView(coder: someCoder)` | The call traps with a fatal error; no instance is returned |
| popup-menu-choice-view-018 | rejects-frame-only-initialization | Attempt `PopupMenuChoiceView(frame: .zero)` | The call traps with a fatal error; no instance is returned |
| popup-menu-choice-view-019 | confines-to-main-actor | Attempt to construct or mutate a `PopupMenuChoiceView` from off the main actor | Compiler rejects the call at compile time under Swift's `@MainActor` isolation checking |

## Edge Cases

- Null/empty input: `viewModel` (`ComposableSettings.ChoiceViewModel<Value>`)
  is a non-optional, typed constructor parameter; Swift's type system rules
  out `nil`. An empty `viewModel.choices` array is a MUST: the component
  constructs without crashing, adds zero menu items, and `syncSelection`'s
  `firstIndex(where:)` finds no match, so no item is selected — the popup
  renders AppKit's native empty-menu appearance.
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
  (**ignores-non-matching-representedObject**), not as an error state.
- Offline/disconnected: Not applicable — the component performs no
  networking of its own; it only reads from and writes to an in-process
  `ComposableSettings.ChoiceViewModel<Value>`.
- Non-matching current value: When `viewModel.value` does not equal any
  choice's `value`, `syncSelection`'s `firstIndex(where:)` returns `nil`
  and `selectItem(at:)` is never called. This is a MUST-level,
  source-traceable consequence: the popup's displayed selection is left
  uncorrected — whatever item `NSPopUpButton` selects by default (its first
  added item) — rather than being cleared or forced to a fallback.
- Overwritten external observer: `viewModel.onChange` is a single closure
  property. `PopupMenuChoiceView`'s initializer unconditionally assigns
  `viewModel.onChange = { [weak self] _ in self?.syncSelection() }`,
  replacing whatever handler (if any) was previously registered on that
  `viewModel`. This is a MUST-level, source-traceable consequence of plain
  closure-property assignment: the component MUST NOT be assumed to
  coexist with another `onChange` observer already registered on the same
  view model instance — constructing a second `PopupMenuChoiceView` (or any
  other observer) against the same view model silently drops the earlier
  handler.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | `ComposableSettings.ChoiceViewModel<Value>` | — (required) | Supplies the row's title, ordered `choices` (each a `label`/`value`/optional `imageSystemName`), and current value; receives committed selection changes via `settingObserver.value`. The initializer also overwrites this view model's `onChange` closure with the component's own `syncSelection` handler (see Edge Cases). `viewModel.explanation` (inherited from `AbstractViewModel`) is accepted but never read or displayed by `PopupMenuChoiceView` — see Design Decisions. |

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
| Increase Contrast | Not applicable: `PopupMenuChoiceView.swift` sets no custom `NSColor` of its own on `popUpButton`; the label's color comes from the theme's `.primaryText` role, and `NSPopUpButton`'s borderless rendering follows AppKit's default, which tracks the system's Increase Contrast setting automatically. |
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
  built from `ForEach(viewModel.choices, id: \.value)` rows, each
  `Label(choice.label, systemImage: choice.imageSystemName ?? "")` (or
  plain `Text(choice.label)` when no symbol name is given), with
  `.pickerStyle(.menu)` to match the borderless popup affordance; wrap it
  with a leading `Text(viewModel.title)` in an `HStack` (or a
  `LabeledContent`) if the row shape from `makeRow` should be kept
  literally rather than relying on `Picker`'s own built-in label. Commit
  the selection to the underlying setting from the `Binding`'s setter with
  an equality guard, mirroring skips-redundant-commits; a selection whose
  raw value doesn't decode to a known choice mirrors
  ignores-non-matching-representedObject by leaving the setting unchanged.
- **Compose**: Use an `ExposedDropdownMenuBox` (or a plain `Row` opening a
  `DropdownMenu`) with a leading `Text(title)` and a trailing read-only
  field/anchor showing the current choice's label; each `DropdownMenuItem`
  renders `choice.label`, with an optional leading `Icon` when an icon
  resource is supplied (the Compose analog of `imageSystemName`). Commit
  the tapped item's value to the backing state/view-model in
  `onClick`/`onItemSelected` with an equality check before writing,
  mirroring skips-redundant-commits, and leave the state unchanged if the
  clicked item's value can't be resolved, mirroring
  ignores-non-matching-representedObject.
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
  ignores-non-matching-representedObject.
- **AppKit/UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/PopupMenuChoiceView.swift`.
  A macOS-only (`import AppKit`) `NSView` subclass, `@MainActor`, generic
  over `Value: Codable & Sendable & Equatable`, inside the
  `ComposableSettings` namespace, conforming to `SettingsViewProtocol`. It
  composes two subviews — an `NSTextField` label from
  `ComposableSettings.makeRowLabel` and a borderless `NSPopUpButton`
  populated from `ChoiceViewModel.choices` — into one row via
  `ComposableSettings.makeRow` and `pinToEdges`, links the popup's
  accessibility title to the label, and wires the popup's target/action to
  `popupChanged(_:)`. There is no UIKit code path in source; a UIKit port
  would replace `NSPopUpButton` with a `UIButton` presenting a `UIMenu` (or
  a `UIPickerView`) and the `target`/`action` pattern with
  `.addTarget(_:action:for: .primaryActionTriggered)` or a `UIAction`
  handler per menu item — UIKit has no `NSCoder`-vs-frame initializer split
  to fatal-error on both the way requires-designated-initializer and
  rejects-frame-only-initialization do.
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
  choice value (mirroring ignores-non-matching-representedObject) and only
  then writing through a property setter that skips the assignment (and so
  skips raising `INotifyPropertyChanged`) when the incoming value already
  equals the current value, mirroring skips-redundant-commits.

## Design Decisions

- Decision: Draw the popup fully borderless (`isBordered = false`) instead
  of AppKit's default bezeled `NSPopUpButton`.
  Rationale: Per the source's own comment, "System Settings draws a popup
  inside a card without a bezel: the current value in secondary text with
  the chevron pair after it. The card is the surface, so a second one
  around the control just boxes a box."
  Approved: pending
- Decision: Pin the popup's horizontal content-hugging priority to
  `.defaultHigh`.
  Rationale: Keeps the popup sized to its content so `makeRow`'s flexible
  spacer, not the popup, absorbs the row's leftover width — the same
  spacer-absorbs-slack layout `CheckboxView`'s row relies on, made explicit
  here because a borderless `NSPopUpButton`'s default hugging behavior is
  not guaranteed to match a bordered one's.
  Approved: pending
- Decision: Link the popup's accessibility title to the label via
  `setAccessibilityTitleUIElement` rather than setting a separate
  accessibility label string.
  Rationale: Per the source's own comment, "the visible title label sits
  beside the popup but AppKit doesn't associate them, so VoiceOver would
  announce the popup with no name."
  Approved: pending
- Decision: Silently ignore a selected item whose `representedObject` fails
  the cast to `Value` (**ignores-non-matching-representedObject**).
  Rationale: `guard let value = sender.selectedItem?.representedObject as?
  Value else { return }` in `popupChanged(_:)` is the only handling in
  source; this documents the actual, traceable behavior rather than
  assuming an error-reporting path exists.
  Approved: pending
- Decision: Leave a `viewModel.value` that matches no choice's value
  uncorrected in `syncSelection`.
  Rationale: `firstIndex(where:)` returning `nil` skips the
  `selectItem(at:)` call entirely; the source neither clears the selection
  nor forces a default item, so the popup keeps whatever item AppKit
  selected by default — this documents the observed behavior, not an
  idealized fallback.
  Approved: pending
- Decision: `ComposableSettings.ChoiceViewModel<Value>`'s inherited
  `AbstractViewModel.explanation` property is accepted by the initializer
  chain but never read or rendered anywhere in
  `PopupMenuChoiceView.swift`.
  Rationale: `syncSelection` reads `viewModel.title` and `viewModel.value`
  only; documenting this here, rather than omitting it, keeps the recipe
  faithful to what the source actually renders versus what the view model
  type happens to carry.
  Approved: pending
- Decision: Force a fatal error from both `init(coder:)` and the
  frame-only `init(frame:)`, leaving the `viewModel`-taking initializer as
  the only usable one.
  Rationale: The view has no meaningful default state — it cannot render a
  title, a choice list, or a value without a `viewModel` — so both
  inherited `NSView` initializers that could construct it without one are
  intentionally disabled rather than left to produce a half-configured
  row.
  Approved: pending
- Decision: Carry more behavioral requirements (19) than the sibling
  `CheckboxView` recipe (11), despite both being single-row
  `ComposableSettings` controls.
  Rationale: `PopupMenuChoiceView` manages a variable-length, per-item
  choice list (a title, a `representedObject`, and an optional symbol
  image per entry) plus a `representedObject`-to-`Value` cast guard that
  `CheckboxView`'s fixed two-state `Bool` toggle has no analog for; the
  added depth is warranted by genuinely more source behavior, not
  over-specification.
  Approved: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | platform-compliance |
| [platform-design-language](agenticdevelopercookbook://compliance/platform-compliance#platform-design-language) | passed | platform-compliance |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | passed | accessibility |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | reliability |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
