<!-- leaf: implement-panel/heading-view--part-2 · source: panel-heading-view.md -->

# PanelHeadingView — continued (part 2)

## Platform Notes

- **SwiftUI**: Compose a `VStack(alignment: .leading, spacing: 6)` with a
  `Text(title)` styled from the app's `.heading` theme token (the SwiftUI
  analog of `ThemeTypography.defaultStyle(.heading)`, not the built-in
  `.headline` text style, which is a different size/weight on this platform)
  for the title, and — only when `caption` is non-`nil` — a `Text(caption)
  .font(.caption).foregroundStyle(.secondary)
  .fixedSize(horizontal: false, vertical: true)` beneath it, mirroring
  `stacks-title-and-caption-vertically-leading-aligned` and
  `creates-caption-view-when-caption-given`/
  `omits-caption-view-when-caption-nil`. Give the caption `Text` no fixed
  frame beyond the parent's own width so it wraps to it, the SwiftUI analog
  of `matches-caption-width-to-stack`; leave the title unconstrained in width
  to match the source's clipped, single-line title.
- **Compose**: Use a `Column(verticalArrangement = Arrangement
  .spacedBy(6.dp), horizontalAlignment = Alignment.Start)` with a
  `Text(title, style = MaterialTheme.typography.titleMedium)` for the
  heading, and conditionally (`if (caption != null)`) a
  `Text(caption, style = MaterialTheme.typography.bodySmall, color =
  MaterialTheme.colorScheme.onSurfaceVariant)` that wraps within the
  column's own width — Compose `Text` wraps by default, mirroring the
  caption's wrapping behavior without extra configuration.
- **React/Web**: A `<hgroup>` or `<div>` containing a heading element (e.g.
  `<h3>`) styled from the primary-text/heading tokens, followed — only when
  `caption` is provided — by a `<p>` styled from the
  secondary-text/caption tokens with `white-space: normal; overflow-wrap:
  break-word` and `width: 100%` so it wraps to the container, mirroring
  `matches-caption-width-to-stack`; use `gap: 6px` (flex or grid column) for
  the title-to-caption spacing, matching `spaces-title-from-caption`.
- **AppKit / UIKit** (source platform): Source at
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/PanelHeadingView.swift`
  (this recipe's source): a macOS-only (`import AppKit`) `NSView` subclass,
  `@MainActor`, `final`, inside the `ComposableSettings` namespace, composing
  one `ThemedLabel` and, conditionally, one `ExplanationView` inside an
  `NSStackView`. `uses-auto-layout-exclusively` is met by setting
  `translatesAutoresizingMaskIntoConstraints = false` on the view itself, the
  stack, and `titleLabel` (`captionView` opts itself in inside
  `ExplanationView`'s own initializer). `fills-bounds-with-zero-inset` is met
  by activating four `NSLayoutConstraint`s pinning the stack's top, leading,
  trailing, and bottom anchors to the matching anchors of the view itself,
  each with a zero constant. `rejects-frame-initializer` is met by overriding
  `init(frame frameRect: NSRect)` to `fatalError("init(frame frameRect:
  NSRect)")` unconditionally, and `rejects-coder-initializer` by overriding
  `init?(coder: NSCoder)` to `fatalError("init(coder:) has not been
  implemented")`. There is no UIKit code path in source. A UIKit port would
  replace `NSStackView` with `UIStackView`, `ThemedLabel`(`NSTextField`) with
  a `UILabel` styled for the heading role, and the conditionally-constructed
  `ExplanationView`/`UILabel` pairing for the caption; it would have no
  `NSCoder`-vs-frame initializer split to fatal-error on the way
  `rejects-frame-initializer` and `rejects-coder-initializer` do.
- **WinUI 3**: Build this as a vertical
  `StackPanel` with `Spacing="6"` (the analog of
  `SettingsLayout.default[.captionSpacing]` /
  `spaces-title-from-caption`) containing a `TextBlock` styled
  `Style="{StaticResource BodyStrongTextBlockStyle}"` (or a custom style
  matching the theme's `.heading` size/weight) bound to `title`, mirroring
  `styles-title-as-primary-heading`/`sets-title-text-from-caller`. Add a
  second `TextBlock` — constructed and added to the `StackPanel.Children`
  only when `caption` is non-null, not merely hidden via `Visibility`, to
  mirror `creates-caption-view-when-caption-given`/
  `omits-caption-view-when-caption-nil` and to keep `PanelHeadingView`'s own
  `captionLabel == nil` contract honest for a null caption — styled
  `Style="{StaticResource CaptionTextBlockStyle}"` with
  `TextWrapping="WrapWholeWords"` and `HorizontalAlignment="Stretch"` so it
  wraps to the `StackPanel`'s own width, mirroring
  `matches-caption-width-to-stack` (a `StackPanel`'s children stretch to its
  width by default when no narrower `Width` is set, unlike `titleLabel`,
  which should keep `TextWrapping="NoWrap"` and `TextTrimming="Clip"` to
  match the source's untouched, single-line `ThemedLabel` default). There is
  no WinUI equivalent of `NSLayoutConstraint`-based edge pinning needed
  beyond placing the `StackPanel` alone in its parent cell with no `Margin`,
  reproducing `fills-bounds-with-zero-inset` directly.

## Design Decisions

- **Decision**: The caption, when supplied, is wrapped in an
  `ExplanationView` rather than being built as a second `ThemedLabel` local
  to `PanelHeadingView`.
  **Rationale**: per the source's own comment on `captionView`, this is "so
  it wraps inside the panel by the one policy every settings blurb shares
  instead of a copy of it" — the wrapping, compression, and hugging behavior
  a multi-line settings caption needs is owned once, by `ExplanationView`,
  and reused here rather than re-implemented.
  **Approved**: pending
- **Decision**: `titleLabel`'s width is never constrained to the stack's
  width, while `captionView`'s width is (`matches-caption-width-to-stack`).
  **Rationale**: not explained in source comments beyond the code itself.
  `titleLabel` keeps `ThemedLabel`'s default single-line, clipped
  configuration and needs no width constraint to wrap correctly; `captionView`
  wraps by design (per `ExplanationView`'s own configuration) and needs a
  known width to wrap *against* — without the constraint, a wrapping label
  reports its one-line intrinsic width instead of the width the panel
  actually gives it, the same reasoning the `ExplanationView` recipe
  documents for that view's own horizontal-compression decision.
  **Approved**: pending
- **Decision**: The gap above a `PanelHeadingView` inside a panel is widened
  to `1.5×` the panel's group spacing by `PanelView.addHeading(_:caption:)`,
  not by `PanelHeadingView` itself.
  **Rationale**: `PanelView.swift`'s own comment on `addHeading` states "the
  gap above a heading is wider than the gap between two cards, because that
  gap is what says the heading belongs to what comes *after* it — at the
  stack's own spacing it reads as a caption trailing the card above." This
  spacing decision is recorded here for context because it is the one call
  site that constructs this component, but `PanelView.swift` is not part of
  this recipe's source, so it is not a requirement of `PanelHeadingView`
  itself.
  **Approved**: pending
