---
id: afa90dd0-0ee6-435b-8cac-f5c6065e7496
title: Settings Card Views
domain: agentictoolkit://recipes/settings-card-views
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: SwiftUI caption, card, row, divider, and native search-field views composing
  a ComposableSettings panel, sharing SettingsLayout metrics with the AppKit GroupView.
platforms:
- swift
- macos
tags:
- card
- settings
- group
- swiftui
- macos
depends-on: []
related:
- agentictoolkit://recipes/header-view
references:
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
approved-by: ''
approved-date: ''
---

# Settings Card Views

## Overview

`ComposableSettings`'s SwiftUI view vocabulary, at `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/SettingsCardViews.swift`, is the SwiftUI half of the same panel chrome the AppKit `GroupView`/`ThemedBox`/`CardRow`/`ThemedSearchField` types draw: a caption above a rounded, elevated card (`SettingsGroup`), the rounded card itself (`SettingsCard`), one row's padding inside the card (`SettingsCardRow`), the hairline between two rows (`SettingsCardDivider`), a live-filtering search field bridged from AppKit's `NSSearchField` (`SettingsSearchField`), and a panel-level padding modifier (`View.settingsPanelInset()`). All six read the same `ComposableSettings.SettingsLayout.default` metrics the AppKit views use, so a panel written either way lands on the same grid. Rows are composed by the caller rather than collected by the container, so a card can hold a run of uniform rows, an action row, and an empty state without the container needing to know which is which.

## Behavioral Requirements

- **group-renders-caption-when-title-present**: `SettingsGroup` MUST render a `Text(title)` styled with the `.caption` text role and the `secondaryText` foreground color above the card when its `title` parameter is non-nil.
- **group-omits-caption-when-title-absent**: `SettingsGroup` MUST NOT render any caption view when `title` is nil.
- **group-spaces-caption-from-card**: `SettingsGroup` MUST separate its caption, when rendered, from the card beneath it by exactly `SettingsLayout.default[.captionSpacing]` (6pt).
- **group-stretches-full-width**: `SettingsGroup` MUST stretch to the full width offered by its container, leading-aligned.
- **group-title-not-auto-localized**: `SettingsGroup` MUST NOT localize `title` automatically; because it is passed to `Text` as a `String` value rather than a `LocalizedStringKey` literal, it MUST render verbatim, exactly as the caller supplied it.
- **card-fills-rounded-elevated-surface**: `SettingsCard` MUST paint its content's background with the `elevatedSurface` theme color, clipped to a continuous corner radius of `SettingsLayout.default[.cardCornerRadius]` (10pt).
- **card-stretches-full-width**: `SettingsCard` MUST stretch its content to the full width offered by its container, leading-aligned.
- **card-row-insets-content**: `SettingsCardRow` MUST inset its content by `SettingsLayout.default[.cardHorizontalInset]` (14pt) horizontally and `SettingsLayout.default[.cardVerticalInset]` (9pt) vertically.
- **card-row-stretches-full-width**: `SettingsCardRow` MUST stretch its content to the full width offered by its container, leading-aligned.
- **divider-renders-hairline**: `SettingsCardDivider` MUST render a horizontal hairline exactly `SettingsLayout.default[.dividerThickness]` (1pt) tall, filled with the `divider` theme color, filling the width offered by its container.
- **divider-insets-from-leading-edge**: `SettingsCardDivider` MUST inset its hairline from the leading edge by `SettingsLayout.default[.cardHorizontalInset]` (14pt), with no trailing inset.
- **panel-inset-pads-uniformly**: `View.settingsPanelInset()` MUST apply `SettingsLayout.default[.panelInset]` (20pt) of padding uniformly on all four edges of the view it modifies.
- **search-field-wraps-native-control**: `SettingsSearchField` MUST render its text-entry surface using a genuine `NSSearchField` subclass (`ThemedSearchField`), not a custom-drawn substitute.
- **search-field-filters-live**: `SettingsSearchField` MUST configure the wrapped field so a keystroke sends the search action immediately (`sendsSearchStringImmediately = true`) rather than waiting for Return (`sendsWholeSearchString = false`).
- **search-field-writes-through-binding**: `SettingsSearchField` MUST write the field's current `stringValue` to the caller-supplied `text` binding whenever the field's search action fires.
- **search-field-avoids-cursor-jump**: `SettingsSearchField` MUST assign `stringValue` on the underlying field during an update only when it differs from the current `text` value, so reassigning an unchanged value does not move the insertion point.
- **search-field-coordinator-rebinds-on-update**: `SettingsSearchField` MUST reassign its coordinator's `text` binding to the current `_text` on every `updateNSView` call, so the field's action always writes through the binding the current SwiftUI body captured.
- **search-field-sizes-to-fitting-height**: `SettingsSearchField` MUST report `nsView.fittingSize.height` as its height from `sizeThatFits`, and the proposed width when one is offered, falling back to `nsView.fittingSize.width` otherwise.
- **search-field-placeholder-not-auto-localized**: `SettingsSearchField` MUST render `placeholder` verbatim via `ThemedSearchField`'s `placeholderString`, with no automatic localization applied.
- **card-and-search-field-stay-internal**: `SettingsCard` and `SettingsSearchField` MUST NOT be given `public` access; both are declared with no access modifier, restricting their use to code inside the defining module.

## Appearance

- **Corner radius**: `SettingsCard` clips to `SettingsLayout.default[.cardCornerRadius]` = 10pt, using SwiftUI's `.continuous` (squircle) corner style (`ViewLayout.swift`, `SettingsCardViews.swift`).
- **Padding**: `SettingsCardRow` insets its content `SettingsLayout.default[.cardHorizontalInset]` = 14pt horizontal × `SettingsLayout.default[.cardVerticalInset]` = 9pt vertical; `SettingsGroup` spaces its caption from its card by `SettingsLayout.default[.captionSpacing]` = 6pt; `settingsPanelInset()` pads a whole panel `SettingsLayout.default[.panelInset]` = 20pt on all sides.
- **Font**: `SettingsGroup`'s caption uses the `.caption` `TextRole` — per `ThemeTypography.defaultStyle(.caption)` (`ThemeTypography.swift`), 11pt, `.regular` weight, system font family, scaled by the active theme's `sizeScale` unless the theme overrides the `.caption` style.
- **Background**: `SettingsCard` fills with the `elevatedSurface` theme color. Per `SemanticPalette.derive(_:theme:)` (`SemanticPalette.swift`), the default derivation is the theme's background blended 12% toward its foreground (`background.blended(withFraction: 0.12, of: foreground)`), unless the active `ColorTheme` supplies an explicit `roleOverrides["elevatedSurface"]` entry.
- **Foreground/Text**: `SettingsGroup`'s caption text color tracks the `secondaryText` role — the theme's foreground dimmed 32% toward its background with a 3.0 minimum-contrast floor (`foreground.dimmed(towards: background, by: 0.32, minContrast: 3.0)`), unless overridden. `SettingsCardDivider` fills with the `divider` role — the background blended 10% toward the foreground (`background.blended(withFraction: 0.10, of: foreground)`), unless overridden.
- **Border**: None on any of the six views; `SettingsCard` sets no stroke, and `SettingsCardDivider` is itself a filled hairline rather than a bordered shape.
- **Shadow**: None; no shadow modifier appears anywhere in the source.
- **Min/Max size**: None fixed by `SettingsGroup`, `SettingsCard`, `SettingsCardRow`, or `SettingsCardDivider` — each sizes to its content plus the padding above. `SettingsSearchField.sizeThatFits` reports the wrapped `ThemedSearchField`'s own `fittingSize.height` as its height, and the proposal's width (or the field's `fittingSize.width` if none is offered) — "its own height, the width it is offered," per the source comment.

## States

| State | Appearance change |
|-------|------------------|
| Default | `SettingsGroup`/`SettingsCard`/`SettingsCardRow`/`SettingsCardDivider` render exactly the static appearance described above; there is no other visual state for any of them. `SettingsSearchField` shows the wrapped field's placeholder or current `text`. |
| Pressed | Not applicable: none of the six views wires a target/action, gesture recognizer, or tap handler of its own. `SettingsSearchField`'s clear button and magnifier icon are `NSSearchField`'s native chrome, not code in this file. |
| Disabled | Not applicable: the source never reads or sets `isEnabled` (or a dimmed equivalent) on any of the six views. |
| Focused | Not applicable for `SettingsGroup`/`SettingsCard`/`SettingsCardRow`/`SettingsCardDivider`, which accept no keyboard focus. For `SettingsSearchField`, no custom focus styling is coded — wrapping a real `NSSearchField` (via `ThemedSearchField`) means the system supplies the native focus ring automatically, which the source's own comment gives as the explicit reason not to hand-roll the control. |
| Loading | Not applicable: none of the six views performs asynchronous work or defines a loading indicator. |

## Accessibility

- **Role/trait**: `SettingsGroup`'s caption sets no explicit accessibility trait (no `.accessibilityAddTraits(.isHeader)`); it reuses `HeaderView`'s exact role assignment (`secondaryText` color, `.caption` text role — see Design Decisions), and the same open question about exposing it as a heading is tracked in the `header-view` recipe rather than re-raised here. `SettingsCard`, `SettingsCardRow`, and `SettingsCardDivider` set no accessibility role of their own; they are pure layout/paint containers, and SwiftUI applies its default container/decoration behavior. `SettingsSearchField` wraps a genuine `NSSearchField`, so the system's search-field accessibility role, VoiceOver rotor behavior, and Escape-to-clear are native to `NSSearchField` rather than code added here — exactly the alternative to "a hand-drawn stand-in" the source comment calls out.
- **Label requirements**: `SettingsGroup`'s caption text is both the visible and accessible content of its `Text`, since `title` is displayed verbatim with no separate accessibility label. `SettingsSearchField`'s `placeholder` becomes `ThemedSearchField.placeholderString`, which `NSSearchField` also exposes as part of its default accessibility description; no separate `accessibilityLabel` is set.
- **Announce state changes**: Not applicable — none of the six views defines a state that changes (see States); there is nothing for VoiceOver to announce beyond `NSSearchField`'s own native announcements of its text changing.
- **Minimum tap target**: Not applicable for `SettingsGroup`/`SettingsCard`/`SettingsCardRow`/`SettingsCardDivider`, none of which is an interactive control. `SettingsSearchField`'s tappable target (text field bezel, clear button) is entirely `NSSearchField`'s native sizing, not a size this file computes.
- **Contrast**: NEEDS REVIEW: `SettingsCardDivider` fills with the `divider` role, derived as the background blended only 10% toward the foreground — whether that blend clears the 3:1 non-text contrast ratio WCAG 1.4.11 asks of a meaningful UI boundary depends on the active theme's actual background/foreground colors, which this file cannot determine on its own. This is the same open category as the caption's `secondaryText` floor (see Accessibility Options).

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| settings-card-views-001 | group-renders-caption-when-title-present | Construct `SettingsGroup("Section") { Text("Row") }` | A caption view showing "Section" in `.caption` font and `secondaryText` color appears above the card |
| settings-card-views-002 | group-omits-caption-when-title-absent | Construct `SettingsGroup { Text("Row") }` (no title) | No caption view is rendered; only the card appears |
| settings-card-views-003 | group-spaces-caption-from-card | Construct `SettingsGroup("Section") { Text("Row") }` and measure the rendered layout | The vertical gap between the caption's bottom edge and the card's top edge is 6pt |
| settings-card-views-004 | group-stretches-full-width | Place `SettingsGroup` in a container 400pt wide | The rendered `SettingsGroup` occupies the full 400pt width, leading-aligned |
| settings-card-views-005 | group-title-not-auto-localized | Add a `Localizable.strings` entry mapping the literal string passed as `title` to a different translation, then render `SettingsGroup(titleVariable) { … }` where `titleVariable` is a `String` variable holding that same text | The caption displays the original untranslated string, not the localized entry |
| settings-card-views-006 | card-fills-rounded-elevated-surface | Render `SettingsCard { Color.red }` under a known theme | The card's background pixel color matches the theme's `elevatedSurface` value, and its corners are rounded to 10pt with a continuous curve |
| settings-card-views-007 | card-stretches-full-width | Place `SettingsCard` in a container 400pt wide | The rendered card occupies the full 400pt width, leading-aligned |
| settings-card-views-008 | card-row-insets-content | Render `SettingsCardRow { Text("Label") }` inside a card of known width | The label's frame is inset 14pt from each side edge and 9pt from top and bottom |
| settings-card-views-009 | card-row-stretches-full-width | Place `SettingsCardRow` in a container 400pt wide | The rendered row occupies the full 400pt width, leading-aligned |
| settings-card-views-010 | divider-renders-hairline | Render `SettingsCardDivider()` under a known theme | A horizontal bar exactly 1pt tall appears, filled with the theme's `divider` color |
| settings-card-views-011 | divider-insets-from-leading-edge | Render `SettingsCardDivider()` inside a card 400pt wide | The hairline starts 14pt from the leading edge and extends to the trailing edge with no trailing inset |
| settings-card-views-012 | panel-inset-pads-uniformly | Apply `.settingsPanelInset()` to a 300×300pt view | The modified view's content is inset 20pt on all four sides |
| settings-card-views-013 | search-field-wraps-native-control | Instantiate `SettingsSearchField("Search", text: $binding)` and inspect the produced `NSView` hierarchy | The produced view is (or contains) a `ThemedSearchField` instance, a subclass of `NSSearchField` |
| settings-card-views-014 | search-field-filters-live | Inspect the `ThemedSearchField` created by `makeNSView` | `sendsWholeSearchString == false` and `sendsSearchStringImmediately == true` |
| settings-card-views-015 | search-field-writes-through-binding | Type a character into the live field so its search action fires | The bound `text` value updates to the field's new `stringValue` |
| settings-card-views-016 | search-field-avoids-cursor-jump | Place the insertion point mid-string in the field, then trigger `updateNSView` with a `text` value equal to the field's current `stringValue` | The field's `stringValue` is not reassigned and the insertion point does not move |
| settings-card-views-017 | search-field-coordinator-rebinds-on-update | Re-render the SwiftUI parent with a new `text` binding instance, forcing `updateNSView` | The coordinator's `text` property equals the new binding, not the one captured at `makeCoordinator` |
| settings-card-views-018 | search-field-sizes-to-fitting-height | Call `sizeThatFits` with a proposal of `width: 200, height: nil` | The returned height equals the wrapped field's `fittingSize.height`, and the returned width is 200 |
| settings-card-views-019 | search-field-placeholder-not-auto-localized | Add a `Localizable.strings` entry mapping the literal string passed as `placeholder` to a different translation, then construct `SettingsSearchField(placeholderVariable, text: $binding)` | The field's `placeholderString` shows the original untranslated string |
| settings-card-views-020 | card-and-search-field-stay-internal | From a Swift file in a different module that imports the defining module, attempt to reference `SettingsCard` or `SettingsSearchField` by name | Compilation fails: the symbol is inaccessible from outside the defining module |

## Edge Cases

- **Null/empty input**: `SettingsGroup`'s `title` is `String?`; `nil` omits the caption entirely (settings-card-views-002), while `""` still renders an empty-but-present caption line — the source guards against `nil` only, not against an empty string, since an empty string is a valid, distinct value from `nil`. `SettingsSearchField`'s `text` binding starting at `""` is valid and shows the placeholder.
- **Boundary values**: `SettingsGroup`'s caption `Text` sets no `.lineLimit` or truncation mode, so a very long `title` wraps across multiple lines within the leading-aligned stack rather than clipping to one line the way the AppKit `HeaderView`'s single-line `ThemedLabel` does — a real behavioral difference between the two framework's caption rendering, not an idealization. `SettingsSearchField` imposes no maximum length on `text`.
- **Concurrent access**: Not applicable for the four pure SwiftUI views — SwiftUI's `View` protocol confines `body` evaluation to the main actor. `SettingsSearchField.Coordinator` is explicitly declared `@MainActor`, so `searchChanged(_:)` and the `text` reassignment on `updateNSView` are both serialized to the main actor by the Swift compiler.
- **Error states**: Not applicable — none of the six views has a dependency on network, database, or file-system access; the source contains no error path of any kind.
- **Offline/disconnected state**: Not applicable — none of the six views performs networking.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `title` | `String?` | `nil` | `SettingsGroup`'s optional caption text, rendered above the card when non-nil |
| `content` | `@ViewBuilder () -> Content` | required | The rows `SettingsGroup`/`SettingsCard`/`SettingsCardRow` wrap and lay out |
| `placeholder` | `String` | `""` | `SettingsSearchField`'s placeholder text, passed to `ThemedSearchField(placeholder:)` |
| `text` | `Binding<String>` | required | `SettingsSearchField`'s two-way-bound current search string |

## Deep Linking

Not applicable: `SettingsGroup`, `SettingsCard`, `SettingsCardRow`, `SettingsCardDivider`, `SettingsSearchField`, and `settingsPanelInset()` are chrome and layout for whatever content a caller places inside a settings panel — none of them has a navigable identity, route, or resource of its own that a deep link could target.

## Localization

`title` (`SettingsGroup`) and `placeholder` (`SettingsSearchField`) are the only user-facing strings in this file, and both are opaque, caller-supplied values with no fixed key or default of their own — there is no string catalog entry to list. Neither is localized automatically: `title` reaches `Text` as a `String` value (not a `LocalizedStringKey` literal), so it resolves through `Text`'s un-localized initializer and renders verbatim; `placeholder` reaches AppKit's `placeholderString` the same way `HeaderView`'s `stringValue` does — a plain string set at runtime, never looked up against a localization table. Producing an already-localized string before it reaches either parameter is the caller's responsibility.

## Accessibility Options

Document which accessibility display options (Rule 15) this component responds to:

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: none of the six views applies an animation, transition, or motion effect of its own — every one is built once from static modifiers, with no animator proxy, `withAnimation`, or looping effect anywhere in the source. |
| Increase Contrast | Applies, but is not handled in source: `SettingsGroup`'s caption reuses the `secondaryText` role (3.0 minimum-contrast floor) and 11pt caption size that `HeaderView`'s caption also uses — the open question about raising that floor for Increase Contrast is tracked in the `header-view` recipe and not re-raised here. `SettingsCardDivider`'s `divider` role (10% blend, no stated minimum-contrast floor) raises the same open question independently — see the Contrast entry in Accessibility. |
| Differentiate Without Color | Not applicable: none of the six views conveys state or meaning through color alone — each renders exactly one presentation, with no color-coded distinction for an alternate cue to replace. |

## Feature Flags

Not applicable: the source contains no feature-flag check; all six views and the panel-inset modifier construct and lay out unconditionally.

## Analytics

Not applicable: the source emits no analytics, tracking, or telemetry calls. `SettingsSearchField` forwards keystrokes to its bound `text` value only; it reports nothing about what the user typed or searched for.

## Privacy

- **Data collected**: `SettingsSearchField`'s `text` binding holds whatever search string the user types; it exists only in memory for the lifetime of the SwiftUI view and the state it is bound to. Nothing else in this file collects data.
- **Storage**: Not applicable — no view in this file persists `text`, `title`, or `placeholder` anywhere; any persistence is entirely the caller's concern, outside this file.
- **Transmission**: Not applicable — no network or IPC call appears anywhere in the source.
- **Retention**: Not applicable — no data outlives the view instances that hold it in memory.

## Logging

Not applicable: the source contains no logging calls (no `os_log`, `Logger`, or `print`) anywhere in the file.

## Platform Notes

- **SwiftUI (source)**: `SettingsCardViews.swift` is macOS-only SwiftUI, built entirely from stock view modifiers (`VStack`, `.background`, `.clipShape`, `.padding`, `.frame`) plus one `NSViewRepresentable` (`SettingsSearchField`) bridging AppKit's `NSSearchField`. Every metric it draws with comes from the same `ComposableSettings.SettingsLayout.default` subscript the AppKit `GroupView`/`CardRow` pair reads, which is what keeps a SwiftUI-authored panel on the same grid as an AppKit-authored one.
- **Compose**: Build the card with a Material 3 `Surface` (`shape = RoundedCornerShape(10.dp)`, `color = MaterialTheme.colorScheme.surfaceContainerHigh` or an equivalent elevated-surface token, `tonalElevation` for the raised look) holding a `Column` of rows, each an inset `Row`/`Box` with `Modifier.padding(horizontal = 14.dp, vertical = 9.dp)`; use `HorizontalDivider(modifier = Modifier.padding(start = 14.dp))` for the hairline, matching the source's leading-only inset. For the search field, Material 3's `SearchBar`/`DockedSearchBar` composable is the closest native equivalent — it already provides live `onQueryChange` callbacks and built-in accessibility, mirroring what wrapping a real `NSSearchField` buys the source over a hand-rolled `TextField`.
- **React/Web**: A `<section>` for the group with a `<h3>`/labelled `<span>` caption above it (matching the source's un-headinged caption unless the Increase Contrast/heading question above is resolved in favor of one), a `<div>` styled `border-radius: 10px` and a background CSS custom property for the card, `padding: 9px 14px` per row, and a 1px `<hr>`/bordered `<div>` inset `margin-left: 14px` for the divider. Use `<input type="search">` for the search field — its native type gives Escape-to-clear and a search accessibility role in supporting browsers, the same argument the source makes for wrapping `NSSearchField` instead of a bare `<input type="text">`.
- **AppKit / UIKit**: The AppKit translation of this exact vocabulary already exists in this repository as `GroupView` (caption + card), `ThemedBox` (the card's fill and corner radius), the private `CardRow` (row insets and separator), `ThemedSeparatorView` (the hairline), and `ThemedSearchField` (the search field) — this SwiftUI file exists specifically to mirror them. A UIKit port with no AppKit sibling to mirror would use `UIStackView` for composition, a `UIView` with `layer.cornerRadius = 10` and `layer.cornerCurve = .continuous` for the card (matching the source's continuous curve, unlike the AppKit sibling's default circular curve — see Design Decisions), and `UISearchTextField`/`UISearchBar` in place of `NSSearchField` for the live-filtering field.
- **WinUI 3**: Build the card as a `Border` with `CornerRadius="10"` and `Background` bound to a brush equivalent to `elevatedSurface` (Fluent 2's `CardBackgroundFillColorDefaultBrush` is the closest stock token), containing a `StackPanel` of rows; give each row a `Grid`/`StackPanel` with `Padding="14,9,14,9"` to match `cardHorizontalInset`/`cardVerticalInset`, and separate rows with a 1px-tall `Rectangle` (or a `MenuFlyoutSeparator`-style `Border`) whose `Margin="14,0,0,0"` reproduces the leading-only inset and whose `Fill` binds to a `divider`-equivalent brush. Put the caption above the `Border` as a `TextBlock` styled `Style="{StaticResource CaptionTextBlockStyle}"` (or a custom style matching the port's 11pt caption size) with `Margin="0,0,0,6"` for the caption-to-card gap, and foreground bound to a secondary-text brush (`TextFillColorSecondaryBrush` is Fluent 2's stock equivalent). For the live-filtering search field, use `AutoSuggestBox` with its `TextChanged` event (fires per keystroke, the WinUI analog of `sendsSearchStringImmediately`) rather than waiting for a submit action — or a plain `TextBox` with a magnifying-glass `FontIcon` prefix if `AutoSuggestBox`'s suggestion popup is not wanted. Apply the panel-level inset with `Padding="20"` on the panel's root container, matching `settingsPanelInset()`.

## Design Decisions

**Decision**: `SettingsCard` is declared with no access modifier (internal), while `SettingsGroup`, `SettingsCardRow`, and `SettingsCardDivider` are `public`.
**Rationale**: The source's own doc comment states it directly: "Internal: `SettingsGroup` is the way to draw one. A card without the caption above it is half a group, and the two were published together only because they were written together." The card is an implementation detail of the group, not a sanctioned standalone entry point.
**Approved: pending**

**Decision**: `SettingsCard` clips its content with `RoundedRectangle(cornerRadius: 10, style: .continuous)`, while the AppKit sibling `ThemedBox` (used by `GroupView.cardView`) sets `layer.cornerRadius = 10` using `CALayer`'s default (circular) corner curve.
**Rationale**: Not explained in source comments. Both land on the same 10pt radius from `SettingsLayout.default[.cardCornerRadius]`, but SwiftUI's continuous ("squircle") curve and `CALayer`'s default circular-arc curve are not pixel-identical — a real, minor divergence between the two render paths the file's own comment says exist "so a panel written either way lands on the same grid."
**Approved: pending**

**Decision**: `SettingsGroup`'s caption reuses `HeaderView`'s exact role assignment (`secondaryText` color, `.caption` text role) rather than defining its own style.
**Rationale**: The source doc comment frames these views as "SwiftUI's half of the panel vocabulary... that `GroupView` draws in AppKit," reading the same layout metrics so a panel lands on the same grid regardless of framework. The heading-trait accessibility question this raises is already tracked in the `header-view` recipe and is deliberately not re-raised here (see Accessibility).
**Approved: pending**

**Decision**: `title` and `placeholder` are plain `String`/`String?` parameters passed straight through to `Text` and `ThemedSearchField.placeholderString`, so neither is localized automatically.
**Rationale**: Not explained in source comments. `Text(title)`, where `title` is a `String` variable, resolves through SwiftUI's un-localized `Text(_:)` overload rather than the `LocalizedStringKey` overload a literal would use; producing an already-localized string is the caller's responsibility before either parameter is reached.
**Approved: pending**

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [main-actor-confined](agenticdevelopercookbook://compliance/architecture#main-actor-confined) | passed | Architecture |
| [no-raw-hex](agenticdevelopercookbook://compliance/ui-tokens#no-raw-hex) | passed | UI Tokens |
| [differentiate-without-color](agenticdevelopercookbook://compliance/accessibility#differentiate-without-color) | passed | Accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | Accessibility |

`main-actor-confined` passes because all four SwiftUI view types conform to `View`, whose `body` SwiftUI confines to the main actor, and `SettingsSearchField.Coordinator` is explicitly declared `@MainActor`. `no-raw-hex` passes because every color this file uses is a theme role (`elevatedSurface`, `secondaryText`, `divider`) rather than a literal `Color` or hex value. `differentiate-without-color` passes because none of the six views conveys state through color — each has exactly one presentation. `contrast-ratio` is partial because the `secondaryText` and `divider` roles each guarantee only a fixed minimum-contrast floor (3.0 and unstated, respectively) from their derivation formula, not a guarantee that any specific active theme clears WCAG's 4.5:1 (text) or 3:1 (non-text UI) thresholds — see the Contrast entry in Accessibility.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
