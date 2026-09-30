<!-- leaf: implement-general-view-2/popup-menu-choice-view · source: popup-menu-choice-view.md -->

**Rules** (cite as `implement-general-view-2/popup-menu-choice-view#<slug>`):

- `arranges-row-layout` MUST
- `populates-menu-items-from-choices` MUST
- `attaches-choice-value-to-item` MUST
- `attaches-choice-image` MUST
- `omits-choice-image-when-absent` MUST
- `suppresses-popup-bezel` MUST
- `resists-popup-stretch` MUST
- `links-popup-accessibility-title` MUST
- `wires-popup-action` MUST
- `initializes-from-view-model` MUST
- `commits-selection-value` MUST
- `ignores-unresolvable-selection` MUST
- `skips-redundant-commits` MUST
- `syncs-on-external-change` MUST
- `exposes-constituent-views` MUST
- `fixes-choice-set-at-construction` MUST
- `requires-designated-initializer` MUST
- `rejects-frame-only-initialization` MUST
- `confines-to-main-actor` MUST
- `tolerates-empty-choices` MUST
- `leaves-unmatched-selection` MUST
- `replaces-onchange-handler` MUST
- `label-requirements` MUST — Component MUST set popUpButton.setAccessibilityTitleUIElement(self.label) — per the source's own comment, "the visible …

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
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented in source. The `label` text color resolves from the active theme's `.primaryText` role against the hosting background at runtime; the component performs no contrast check, so whether a given theme's resolved pair meets 4.5:1 cannot be determined from this file — settled by a theme-level contrast audit of `.primaryText` against the backgrounds it sits on.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | `ComposableSettings.ChoiceViewModel<Value>` | — (required) | Supplies the row's title, ordered `choices` (each a `label`/`value`/optional `imageSystemName`), and current value; receives committed selection changes via `settingObserver.value`. The initializer also overwrites this view model's `onChange` closure with the component's own `syncSelection` handler (see Edge Cases and **replaces-onchange-handler**). `viewModel.explanation` (inherited from `AbstractViewModel`) is accepted by the initializer chain but is unsupported: `PopupMenuChoiceView` never reads or displays it. |

