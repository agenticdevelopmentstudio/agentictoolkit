<!-- leaf: implement-settings/card-views--part-2 · source: settings-card-views.md -->

# Settings Card Views — continued (part 2)

## Localization

`title` (`SettingsGroup`) and `placeholder` (`SettingsSearchField`) are the only user-facing strings in this file, and both are opaque, caller-supplied values with no fixed key or default of their own — there is no string catalog entry to list. Neither is localized automatically: `title` reaches `Text` as a `String` value (not a `LocalizedStringKey` literal), so it resolves through `Text`'s un-localized initializer and renders verbatim; `placeholder` reaches AppKit's `placeholderString` the same way `HeaderView`'s `stringValue` does — a plain string set at runtime, never looked up against a localization table. Producing an already-localized string before it reaches either parameter is the caller's responsibility.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: none of the six APIs applies an animation, transition, or motion effect of its own — every one is built once from static modifiers, with no animator proxy, `withAnimation`, or looping effect anywhere in the source. |
| Increase Contrast | Applies, but is not handled in source: `SettingsGroup`'s caption reuses the `secondaryText` role (3.0 minimum-contrast floor) and 11pt caption size that `HeaderView`'s caption also uses — the open question about raising that floor for Increase Contrast is tracked in the `header-view` recipe and not re-raised here. `SettingsCardDivider`'s `divider` role (10% blend, no stated minimum-contrast floor) raises the same open question independently — see the open question on minimum-contrast-ratio. |
| Differentiate Without Color | Not applicable: none of the six APIs conveys state or meaning through color alone — each renders exactly one presentation, with no color-coded distinction for an alternate cue to replace. |

## Privacy

- **Data collected**: `SettingsSearchField`'s `text` binding holds whatever search string the user types; it exists only in memory for the lifetime of the SwiftUI view and the state it is bound to. Nothing else in this file collects data.
- **Storage**: Not applicable — no view in this file persists `text`, `title`, or `placeholder` anywhere; any persistence is entirely the caller's concern, outside this file.
- **Transmission**: Not applicable — no network or IPC call appears anywhere in the source.
- **Retention**: Not applicable — no data outlives the view instances that hold it in memory.

## Platform Notes

- **SwiftUI (source)**: `SettingsCardViews.swift` is macOS-only SwiftUI, built entirely from stock view modifiers (`VStack`, `.background`, `.clipShape`, `.padding`, `.frame`) plus one `NSViewRepresentable` (`SettingsSearchField`) bridging AppKit's `NSSearchField`. Every metric it draws with comes from the same `ComposableSettings.SettingsLayout.default` subscript the AppKit `GroupView`/`CardRow` pair reads, which is what keeps a SwiftUI-authored panel on the same grid as an AppKit-authored one.
- **Compose**: Build the card with a Material 3 `Surface` (`shape = RoundedCornerShape(10.dp)`, `color = MaterialTheme.colorScheme.surfaceContainerHigh` or an equivalent elevated-surface token, `tonalElevation` for the raised look) holding a `Column` of rows, each an inset `Row`/`Box` with `Modifier.padding(horizontal = 14.dp, vertical = 9.dp)`; use `HorizontalDivider(modifier = Modifier.padding(start = 14.dp))` for the hairline, matching the source's leading-only inset. For the search field, Material 3's `SearchBar`/`DockedSearchBar` composable is the closest native equivalent — it already provides live `onQueryChange` callbacks and built-in accessibility, mirroring what wrapping a real `NSSearchField` buys the source over a hand-rolled `TextField`.
- **React/Web**: A `<section>` for the group with a labelled `<span>` caption above it — matching the source, which gives its caption no heading trait (see the open question under Accessibility) — a `<div>` styled `border-radius: 10px` and a background CSS custom property for the card, `padding: 9px 14px` per row, and a 1px `<hr>`/bordered `<div>` inset `margin-left: 14px` for the divider. Use `<input type="search">` for the search field — its native type gives Escape-to-clear and a search accessibility role in supporting browsers, the same argument the source makes for wrapping `NSSearchField` instead of a bare `<input type="text">`.
- **AppKit / UIKit**: The AppKit translation of this exact vocabulary already exists in this repository as `GroupView` (caption + card), `ThemedBox` (the card's fill and corner radius), the private `CardRow` (row insets and separator), `ThemedSeparatorView` (the hairline), and `ThemedSearchField` (the search field) — this SwiftUI file exists specifically to mirror them. A UIKit port with no AppKit sibling to mirror would use `UIStackView` for composition, a `UIView` with `layer.cornerRadius = 10` and `layer.cornerCurve = .continuous` for the card (matching the source's continuous curve, unlike the AppKit sibling's default circular curve — see Design Decisions), and `UISearchTextField`/`UISearchBar` in place of `NSSearchField` for the live-filtering field.
- **WinUI 3**: Build the card as a `Border` with `CornerRadius="10"` and `Background` bound to a brush equivalent to `elevatedSurface` (Fluent 2's `CardBackgroundFillColorDefaultBrush` is the closest stock token), containing a `StackPanel` of rows; give each row a `Grid`/`StackPanel` with `Padding="14,9,14,9"` to match `cardHorizontalInset`/`cardVerticalInset`, and separate rows with a 1px-tall `Rectangle` (or a `MenuFlyoutSeparator`-style `Border`) whose `Margin="14,0,0,0"` reproduces the leading-only inset and whose `Fill` binds to a `divider`-equivalent brush. Put the caption above the `Border` as a `TextBlock` styled `Style="{StaticResource CaptionTextBlockStyle}"` (or a custom style matching the port's 11pt caption size) with `Margin="0,0,0,6"` for the caption-to-card gap, and foreground bound to a secondary-text brush (`TextFillColorSecondaryBrush` is Fluent 2's stock equivalent). For the live-filtering search field, use `AutoSuggestBox` with its `TextChanged` event (fires per keystroke, the WinUI analog of `sendsSearchStringImmediately`) rather than waiting for a submit action — or a plain `TextBox` with a magnifying-glass `FontIcon` prefix if `AutoSuggestBox`'s suggestion popup is not wanted. Apply the panel-level inset with `Padding="20"` on the panel's root container, matching `settingsPanelInset()`.

## Design Decisions

**Decision**: `SettingsCard` is declared with no access modifier (internal), while `SettingsGroup`, `SettingsCardRow`, and `SettingsCardDivider` are `public`.
**Rationale**: The source's own doc comment states it directly: "Internal: `SettingsGroup` is the way to draw one. A card without the caption above it is half a group, and the two were published together only because they were written together." The card is an implementation detail of the group, not a sanctioned standalone entry point.
**Approved**: pending

**Decision**: `SettingsCard` clips its content with `RoundedRectangle(cornerRadius: 10, style: .continuous)`, while the AppKit sibling `ThemedBox` (used by `GroupView.cardView`) sets `layer.cornerRadius = 10` using `CALayer`'s default (circular) corner curve.
**Rationale**: Not explained in source comments. Both land on the same 10pt radius from `SettingsLayout.default[.cardCornerRadius]`, but SwiftUI's continuous ("squircle") curve and `CALayer`'s default circular-arc curve are not pixel-identical — a real, minor divergence between the two render paths the file's own comment says exist "so a panel written either way lands on the same grid."
**Approved**: pending

**Decision**: `SettingsGroup`'s caption reuses `HeaderView`'s exact role assignment (`secondaryText` color, `.caption` text role) rather than defining its own style.
**Rationale**: The source doc comment frames these views as "SwiftUI's half of the panel vocabulary... that `GroupView` draws in AppKit," reading the same layout metrics so a panel lands on the same grid regardless of framework. The heading-trait accessibility question this raises is already tracked in the `header-view` recipe and is deliberately not re-raised here (see Accessibility).
**Approved**: pending

**Decision**: `title` and `placeholder` are plain `String`/`String?` parameters passed straight through to `Text` and `ThemedSearchField.placeholderString`, so neither is localized automatically.
**Rationale**: Not explained in source comments. `Text(title)`, where `title` is a `String` variable, resolves through SwiftUI's un-localized `Text(_:)` overload rather than the `LocalizedStringKey` overload a literal would use; producing an already-localized string is the caller's responsibility before either parameter is reached.
**Approved**: pending
