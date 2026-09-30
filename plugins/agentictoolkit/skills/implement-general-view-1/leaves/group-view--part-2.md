<!-- leaf: implement-general-view-1/group-view--part-2 · source: group-view.md -->

# GroupView — continued (part 2)

## Accessibility

- **Role/trait**: `GroupView`, `cardView` (a `ThemedBox`, itself an `NSView`
  subclass), and `rowStack` set no explicit accessibility role anywhere in
  `GroupView.swift`; each is exposed to assistive technology with `NSView`'s
  ordinary default, not as a distinguished "group" container. The header
  view's own accessibility behavior belongs to `HeaderView` (a
  `ThemedLabel`-based static-text label); `GroupView.swift` does not further
  style or role it.
- **Label requirements**: `GroupView.swift` never associates the
  header/caption text with `cardView` or `rowStack` through any
  accessibility API — no `setAccessibilityLabel`, no
  `accessibilityLabelledUIElements`, no `NSAccessibilityGroupRole` container
  — anywhere in source. A settings group's entire visual purpose is a named
  card of rows, so a VoiceOver user tabbing into the card's rows has no
  programmatic way to learn which caption group they belong to; only sighted
  proximity conveys that relationship.
- **Announce state changes**: Not applicable beyond AppKit's own default —
  hiding a row's content sets that `CardRow`'s own `isHidden` through
  `syncVisibility`, which removes it (and its content) from the
  accessibility tree automatically; `GroupView.swift` performs no explicit
  VoiceOver announcement of its own for a row appearing, disappearing, or a
  separator changing.
- **Minimum tap target**: Not applicable — `GroupView`, `cardView`, and
  `CardRow` are layout/presentation containers with no target/action or
  gesture recognizer of their own anywhere in `GroupView.swift`; whatever tap
  targets exist belong to each row's own caller-supplied content and that
  content's own recipe.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `title` | `String` | — (required, via `init(withTitle:)`) | The convenience initializer's caption text, forwarded into an internally-constructed `HeaderView`. |
| `header` | `NSView` | — (required, via `init(withHeaderView:)`) | The designated initializer's caption view, placed above `cardView`. `init(withTitle:)` supplies a `HeaderView` here. |
| `style` (per call to `addSettingSubview(_:style:)`) | `ComposableSettings.CardRowStyle` | `.row` | Whether the added view starts a new padded, divided row (`.row`) or continues the row above with no top padding and no divider (`.continuation`). |

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: `GroupView.swift` contains no animation, transition, or `NSAnimationContext` call; every layout change (adding a row, toggling `showsSeparator`, hiding a row) is an instantaneous assignment. |
| Increase Contrast | Not applicable to this component directly: `GroupView.swift` reads no system contrast setting; `cardView`'s fill and the divider's color are theme-resolved semantic roles (`.elevatedSurface`, `.divider`) supplied by `ThemedBox`/`ThemedSeparatorView`, neither of which this file adjusts for contrast itself. |
| Differentiate Without Color | Not applicable: `GroupView` conveys grouping and row separation through structure — padding and a hairline — not through color alone; whether a row shows a divider is driven by `showsSeparator`'s layout effect, never by a color-only cue. |

## Privacy

- **Data collected**: None — the component holds only the caller-supplied
  header view/title, `cardView`, and the row views it is given.
- **Storage**: Not applicable — `GroupView.swift` performs no read/write to
  disk, `UserDefaults`, or any other store.
- **Transmission**: Not applicable — no networking call appears anywhere in
  `GroupView.swift`.
- **Retention**: Not applicable — the view retains only `cardView`, its two
  internal stacks, and its `rows` array for its own lifetime; it persists
  nothing beyond that.

## Platform Notes

- **SwiftUI**: Use `Section` with a leading, `.caption`-styled header text
  above a `VStack` clipped to a `RoundedRectangle` (matching the 10pt
  `cardCornerRadius`) and filled with the elevated-surface color, mirroring
  `#requirements/card-surface`; insert `Divider()` between rows only where
  the source's own `#requirements/separator-visibility` rule would show one
  — SwiftUI's `Section` in a `List`/`Form` already renders this pattern
  close to natively on macOS/iOS, so a from-scratch `VStack` is only needed
  for a fully custom card. Give a `.continuation`-styled child no top
  padding and no `Divider()` above it, mirroring
  `#requirements/continuation-padding`. Drive a row's presence with
  structural conditional inclusion (`if !isHidden { row }`) rather than
  `.hidden()`, the same substitution the sibling
  `ConditionalView`/`DismissibleHintView` recipes make, so a hidden row's
  divider and padding close up the way `#requirements/row-visibility-
  binding` does here.
- **Compose**: Build a `Column` with a `.caption`-styled `Text` above a
  `Card`/`Surface` (`shape = RoundedCornerShape(10.dp)`,
  `colors = CardDefaults.cardColors(containerColor = <elevated-surface
  token>)`), and lay rows out in an inner `Column` inserting a thin
  `HorizontalDivider` between consecutive visible rows only — computed the
  same way the source walks its rows, tracking whether a not-hidden,
  non-continuation predecessor has been seen (see
  `#requirements/separator-visibility`). Apply `Modifier.padding` per row
  matching the 9dp/14dp vertical/horizontal insets, and `0.dp` top padding
  for a continuation row.
- **React/Web**: Render a `<fieldset>` or `<section role="group"
  aria-labelledby="...">` whose caption is a `<legend>`/heading with
  `id="..."` matching `aria-labelledby` — the explicit label association
  that `GroupView.swift`'s AppKit source never establishes (see Label
  requirements) — inside a `div` styled with `border-radius: 10px` and the
  elevated-surface background token. Give each `.row` child
  `padding: 9px 14px` and a `border-top: 1px solid var(--divider)` on every
  child except the first visible one, mirroring
  `#requirements/separator-visibility` / `#requirements/first-row-headless`;
  give a `.continuation` child `padding-top: 0` and no `border-top`. Toggle
  a row's presence with conditional rendering (removing the node), not
  `display: none` alone, so the surrounding gap actually closes, mirroring
  `#requirements/row-visibility-binding`.
- **AppKit/UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/GroupView.swift`,
  with layout constants from `ViewLayout.swift`, `ThemedBox`/
  `ThemedSeparatorView`/`ThemedLabel` from the `agenticdevelopertoolkit`
  submodule's `ThemedViews.swift`, and the caption view from
  `HeaderView.swift`. A macOS-only (`import AppKit`) `NSView` subclass,
  `@MainActor`, inside the `ComposableSettings` namespace, built entirely on
  `NSStackView` and Auto Layout. The rows live in a private `rowStack`, each
  wrapped in a private `CardRow` tracked in a private `rows` array; a row's
  divider is a private `line`/`separatorHeight` pair, and `showsSeparator`'s
  `didSet` short-circuits on an unchanged `oldValue` to skip redundant
  writes — the requirements above describe these mechanics only by their
  observable effect, since any of these names could change under a refactor
  without changing what the card looks like or does. There is no UIKit code
  path in source; a UIKit port would replace `NSStackView` with
  `UIStackView`, `NSView.isHidden` with `UIView.isHidden` (the same
  removal-from-layout semantics apply within a `UIStackView`), and would
  have no `NSCoder`-only initializer restriction to fatal-error on the way
  `#requirements/designated-initializer-requirement` and
  `#requirements/row-designated-initializer-requirement` do here.
- **WinUI 3** (the reason this recipe exists): Compose the group from a
  `TextBlock` caption (`Style="{StaticResource CaptionTextBlockStyle}"`)
  positioned above a rounded `Border` (`CornerRadius="10"`, matching
  `cardCornerRadius`, `Background="{ThemeResource
  CardBackgroundFillColorDefaultBrush}"`, `BorderThickness="0"`, matching
  `#requirements/card-surface`'s `stroke: nil`) containing a vertical
  `StackPanel` of row `Border`s. Reproduce `#requirements/separator-
  visibility` / `#requirements/first-row-headless` with a value converter,
  keyed on item index and visibility, that suppresses a row's top `Border`
  divider (`BorderThickness="0,1,0,0"`, `BorderBrush="{ThemeResource
  DividerStrokeColorDefaultBrush}"`) unless a prior, still-visible,
  non-continuation row exists. Bind each row `Border`'s own `Visibility` —
  not just its inner content's — to the wrapped content's visibility, since
  a `StackPanel` does not auto-collapse a row's own padding around a
  `Visibility="Collapsed"` child's slot the way an `NSStackView` collapses a
  hidden arranged `NSView`; this is the direct analog of
  `#requirements/row-visibility-binding` and is required for the
  divider-recompute analog above to see accurate "still-visible" state.
  Give each row `Padding="14,9,14,9"` (a continuation row
  `Padding="14,0,14,9"`), matching `#requirements/row-content-padding` /
  `#requirements/continuation-padding`.

