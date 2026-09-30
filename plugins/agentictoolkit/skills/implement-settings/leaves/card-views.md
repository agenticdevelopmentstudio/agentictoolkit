<!-- leaf: implement-settings/card-views · source: settings-card-views.md -->

**Rules** (cite as `implement-settings/card-views#<slug>`):

- `group-caption` MUST
- `group-omits-caption-when-title-absent` MUST
- `group-caption-spacing` MUST
- `group-stretches-full-width` MUST
- `group-title-not-auto-localized` MUST
- `card-fills-rounded-elevated-surface` MUST
- `card-stretches-full-width` MUST
- `card-row-insets-content` MUST
- `card-row-stretches-full-width` MUST
- `divider-renders-hairline` MUST
- `divider-insets-from-leading-edge` MUST
- `panel-inset-pads-uniformly` MUST
- `search-field-wraps-native-control` MUST
- `search-field-filters-live` MUST
- `search-field-writes-through-binding` MUST
- `search-field-avoids-cursor-jump` MUST
- `search-field-coordinator-binding` MUST
- `search-field-sizes-to-fitting-height` MUST
- `search-field-placeholder-not-auto-localized` MUST
- `card-stays-internal` MUST
- `search-field-stays-internal` MUST

# Settings Card Views

## Overview

`ComposableSettings`'s SwiftUI view vocabulary, at `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/SettingsCardViews.swift`, is the SwiftUI half of the same panel chrome the AppKit `GroupView`/`ThemedBox`/`CardRow`/`ThemedSearchField` types draw: a caption above a rounded, elevated card (`SettingsGroup`), the rounded card itself (`SettingsCard`), one row's padding inside the card (`SettingsCardRow`), the hairline between two rows (`SettingsCardDivider`), a live-filtering search field bridged from AppKit's `NSSearchField` (`SettingsSearchField`), and a panel-level padding modifier (`View.settingsPanelInset()`). All six read the same `ComposableSettings.SettingsLayout.default` metrics the AppKit views use, so a panel written either way lands on the same grid. Rows are composed by the caller rather than collected by the container, so a card can hold a run of uniform rows, an action row, and an empty state without the container needing to know which is which.

## Behavioral Requirements

- **group-caption**: `SettingsGroup` MUST render a `Text(title)` styled with the `.caption` text role and the `secondaryText` foreground color above the card when its `title` parameter is non-nil.
- **group-omits-caption-when-title-absent**: `SettingsGroup` MUST NOT render any caption view when `title` is nil.
- **group-caption-spacing**: `SettingsGroup` MUST separate its caption, when rendered, from the card beneath it by exactly `SettingsLayout.default[.captionSpacing]`.
- **group-stretches-full-width**: `SettingsGroup` MUST stretch to the full width offered by its container, leading-aligned.
- **group-title-not-auto-localized**: `SettingsGroup` MUST NOT localize `title` automatically; because it is passed to `Text` as a `String` value rather than a `LocalizedStringKey` literal, it MUST render verbatim, exactly as the caller supplied it.
- **card-fills-rounded-elevated-surface**: `SettingsCard` MUST paint its content's background with the `elevatedSurface` theme color, clipped to a continuous corner radius of `SettingsLayout.default[.cardCornerRadius]`.
- **card-stretches-full-width**: `SettingsCard` MUST stretch its content to the full width offered by its container, leading-aligned.
- **card-row-insets-content**: `SettingsCardRow` MUST inset its content by `SettingsLayout.default[.cardHorizontalInset]` horizontally and `SettingsLayout.default[.cardVerticalInset]` vertically.
- **card-row-stretches-full-width**: `SettingsCardRow` MUST stretch its content to the full width offered by its container, leading-aligned.
- **divider-renders-hairline**: `SettingsCardDivider` MUST render a horizontal hairline exactly `SettingsLayout.default[.dividerThickness]` tall, filled with the `divider` theme color, filling the width offered by its container.
- **divider-insets-from-leading-edge**: `SettingsCardDivider` MUST inset its hairline from the leading edge by `SettingsLayout.default[.cardHorizontalInset]`, with no trailing inset.
- **panel-inset-pads-uniformly**: `View.settingsPanelInset()` MUST apply `SettingsLayout.default[.panelInset]` of padding uniformly on all four edges of the view it modifies.
- **search-field-wraps-native-control**: `SettingsSearchField` MUST render its text-entry surface using a genuine `NSSearchField` subclass (`ThemedSearchField`), not a custom-drawn substitute.
- **search-field-filters-live**: `SettingsSearchField` MUST configure the wrapped field so a keystroke sends the search action immediately (`sendsSearchStringImmediately = true`) rather than waiting for Return (`sendsWholeSearchString = false`).
- **search-field-writes-through-binding**: `SettingsSearchField` MUST write the field's current `stringValue` to the caller-supplied `text` binding whenever the field's search action fires.
- **search-field-avoids-cursor-jump**: `SettingsSearchField` MUST assign `stringValue` on the underlying field during an update only when it differs from the current `text` value, so reassigning an unchanged value does not move the insertion point.
- **search-field-coordinator-binding**: `SettingsSearchField` MUST reassign its coordinator's `text` binding to the current `_text` on every `updateNSView` call, so the field's action always writes through the binding the current SwiftUI body captured.
- **search-field-sizes-to-fitting-height**: `SettingsSearchField` MUST report `nsView.fittingSize.height` as its height from `sizeThatFits`, and the proposed width when one is offered, falling back to `nsView.fittingSize.width` otherwise.
- **search-field-placeholder-not-auto-localized**: `SettingsSearchField` MUST render `placeholder` verbatim via `ThemedSearchField`'s `placeholderString`, with no automatic localization applied.
- **card-stays-internal**: `SettingsCard` MUST NOT be given `public` access; it is declared with no access modifier, restricting its use to code inside the defining module (see Design Decisions).
- **search-field-stays-internal**: `SettingsSearchField` MUST NOT be given `public` access; it is declared with no access modifier, restricting its use to code inside the defining module.

## Appearance

- **Corner radius**: `SettingsCard` clips to `SettingsLayout.default[.cardCornerRadius]` = 10pt, using SwiftUI's `.continuous` (squircle) corner style (`ViewLayout.swift`, `SettingsCardViews.swift`).
- **Padding**: `SettingsCardRow` insets its content `SettingsLayout.default[.cardHorizontalInset]` = 14pt horizontal × `SettingsLayout.default[.cardVerticalInset]` = 9pt vertical; `SettingsGroup` spaces its caption from its card by `SettingsLayout.default[.captionSpacing]` = 6pt; `settingsPanelInset()` pads a whole panel `SettingsLayout.default[.panelInset]` = 20pt on all sides.
- **Font**: `SettingsGroup`'s caption uses the `.caption` `TextRole` — per `ThemeTypography.defaultStyle(.caption)` (`ThemeTypography.swift`), 11pt, `.regular` weight, system font family, scaled by the active theme's `sizeScale` unless the theme overrides the `.caption` style.
- **Background**: `SettingsCard` fills with the `elevatedSurface` theme color. Per `SemanticPalette.derive(_:theme:)` (`SemanticPalette.swift`), the default derivation is the theme's background blended 12% toward its foreground (`background.blended(withFraction: 0.12, of: foreground)`), unless the active `ColorTheme` supplies an explicit `roleOverrides["elevatedSurface"]` entry.
- **Foreground/Text**: `SettingsGroup`'s caption text color tracks the `secondaryText` role — the theme's foreground dimmed 32% toward its background with a 3.0 minimum-contrast floor (`foreground.dimmed(towards: background, by: 0.32, minContrast: 3.0)`), unless overridden. `SettingsCardDivider` fills with the `divider` role — the background blended 10% toward the foreground (`background.blended(withFraction: 0.10, of: foreground)`), unless overridden.
- **Border**: None on any of the six APIs; `SettingsCard` sets no stroke, and `SettingsCardDivider` is itself a filled hairline rather than a bordered shape.
- **Shadow**: None; no shadow modifier appears anywhere in the source.
- **Min/Max size**: None fixed by `SettingsGroup`, `SettingsCard`, `SettingsCardRow`, or `SettingsCardDivider` — each sizes to its content plus the padding above. `SettingsSearchField.sizeThatFits` reports the wrapped `ThemedSearchField`'s own `fittingSize.height` as its height, and the proposal's width (or the field's `fittingSize.width` if none is offered) — "its own height, the width it is offered," per the source comment.

## Accessibility

- **Role/trait**: `SettingsGroup`'s caption sets no explicit accessibility trait (no `.accessibilityAddTraits(.isHeader)`); it reuses `HeaderView`'s exact role assignment (`secondaryText` color, `.caption` text role — see Design Decisions), and the same open question about exposing it as a heading is tracked in the `header-view` recipe rather than re-raised here. `SettingsCard`, `SettingsCardRow`, and `SettingsCardDivider` set no accessibility role of their own; they are pure layout/paint containers, and SwiftUI applies its default container/decoration behavior. `SettingsSearchField` wraps a genuine `NSSearchField`, so the system's search-field accessibility role, VoiceOver rotor behavior, and Escape-to-clear are native to `NSSearchField` rather than code added here — exactly the alternative to "a hand-drawn stand-in" the source comment calls out.
- **Label requirements**: `SettingsGroup`'s caption text is both the visible and accessible content of its `Text`, since `title` is displayed verbatim with no separate accessibility label. `SettingsSearchField`'s `placeholder` becomes `ThemedSearchField.placeholderString`, which `NSSearchField` also exposes as part of its default accessibility description; no separate `accessibilityLabel` is set.
- **Announce state changes**: Not applicable — none of the six APIs defines a state that changes (see States); there is nothing for VoiceOver to announce beyond `NSSearchField`'s own native announcements of its text changing.
- **Minimum tap target**: Not applicable for `SettingsGroup`/`SettingsCard`/`SettingsCardRow`/`SettingsCardDivider`, none of which is an interactive control. `SettingsSearchField`'s tappable target (text field bezel, clear button) is entirely `NSSearchField`'s native sizing, not a size this file computes.
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented in source. `SettingsCardDivider` fills with the `divider` role, derived as the background blended only 10% toward the foreground, and the source never checks that blend against the 3:1 non-text contrast ratio WCAG 1.4.11 asks of a meaningful UI boundary. What is missing is a minimum-contrast floor on the `divider` role (as `secondaryText` has) or a per-theme contrast measurement. Settling it needs the divider-to-`elevatedSurface` ratio measured under every shipped theme, or a decision that the divider is decorative and exempt from 1.4.11.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `title` | `String?` | `nil` | `SettingsGroup`'s optional caption text, rendered above the card when non-nil |
| `content` | `@ViewBuilder () -> Content` | required | The rows `SettingsGroup`/`SettingsCard`/`SettingsCardRow` wrap and lay out |
| `placeholder` | `String` | `""` | `SettingsSearchField`'s placeholder text, passed to `ThemedSearchField(placeholder:)` |
| `text` | `Binding<String>` | required | `SettingsSearchField`'s two-way-bound current search string |

