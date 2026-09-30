<!-- leaf: implement-general-view-2/tab-pane-view--part-4 · source: tab-pane-view.md -->

# TabPaneView — continued (part 4)

## Platform Notes

- **SwiftUI**: Model the open-sided outline as a custom `Shape` (a
  `path(in:)` implementation tracing the same four points
  `TabCardBackgroundView.corners(of:)` does, per edge, and never closing back
  across the workspace-facing side), composed as a `.background`/`.overlay`
  pair (fill, then stroke) behind a `VStack` mirroring `content`'s order
  (header `HStack`, then the four remaining labels, then a `Spacer()` in
  place of the trailing spacer). Drive `isFrontCard`/`recession`/`overhang`
  from a passed-in `depth: Int`, and wrap the shape's frame/offset change in
  `.animation(.easeOut(duration: 0.16), value: depth)` — gated behind
  `@Environment(\.accessibilityReduceMotion)` per the Reduce Motion gap noted
  above. Use `.lineLimit(1)` with `.truncationMode(.middle)`/`.head`/`.tail`
  to match the per-label truncation modes.
- **Compose**: Draw the same open-sided outline with a `Canvas`/`Path` in a
  `Box`, sized by a `Modifier.widthIn(min = 240.dp, max = 340.dp)` /
  `heightIn(min = 136.dp)`. Represent front/behind with an `animateDpAsState`
  (or `animateFloatAsState`) driving inset/offset over `160.milliseconds`
  with an `EaseOut` easing curve, checked against the system animator
  duration scale (`Settings.Global.ANIMATOR_DURATION_SCALE`, read via
  `ContentResolver` — a scale of zero means Reduce Motion is on;
  `LocalAccessibilityManager` does not expose this setting) before animating.
  Lay out the header as a `Row` with a `Spacer(Modifier.weight(1f))`
  in place of `gap`, and the remaining lines in a `Column`, each using
  `TextOverflow.StartEllipsis`, `TextOverflow.MiddleEllipsis`, or
  `TextOverflow.Ellipsis` to match the per-label head/middle/tail truncation
  mode (`Modifier.basicMarquee()` scrolls text rather than truncating it, so
  it does not apply here).
- **React/Web**: Build the card as a `<div>` whose `background` fills the
  full rect but whose `border` is set on only three sides (the CSS
  longhands `border-top`/`border-left`/`border-right`, omitting the
  workspace-facing side) — or, for the exact open-path stroke, an inline SVG
  `<path>` built from the same four points. Transition `margin`/`transform`
  over `0.16s ease-out` for the depth change, gated behind a
  `prefers-reduced-motion: reduce` media query per the Reduce Motion gap
  above. Use CSS `text-overflow: ellipsis` for tail truncation, `direction:
  rtl` on an inner span for head truncation (the `directoryLabel` case), and
  a `<button aria-label="Close">` for `closeButton`.
- **AppKit/UIKit** (source platform): Implemented in
  `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/MultiTabbedViewController/TabPane/TabPaneView.swift`
  (`TabPaneView`, plus the file-private `InsetBox`, `CardSides`, and
  `TabCardBackgroundView` types), hosted by `TabPaneViewController.swift` in
  the same directory. This is a macOS-only, AppKit `NSView` component with no
  UIKit code path in source. A UIKit port has no first-class analog to an
  `NSBezierPath`-drawn, three-sided open card that overhangs a sibling view by
  a point; it would use a plain `UIView` with a `CAShapeLayer` (a
  `UIBezierPath` built the same four-point, open-path way, `fillColor` and
  `strokeColor` set from the palette) and `UIView.animate(withDuration:)` (or
  `UIViewPropertyAnimator` with an ease-out curve) for the depth transition,
  checking `UIAccessibility.isReduceMotionEnabled` first.
- **WinUI 3** (the reason this recipe exists): There is no single WinUI 3
  control for an open-sided, overhanging tab card, so build it as a
  `UserControl`/`Grid` whose background is a plain `Rectangle`/`Border`
  `Fill` (WinUI's `Border` strokes all four sides at once, so reproduce the
  open workspace-facing side with a `Path`/`Geometry` built from the same
  four corner points `corners(of:)` computes, or by drawing three separate
  `Line`/`Rectangle` strokes and simply omitting the fourth) sized between
  `MinWidth="240" MaxWidth="340" MinHeight="136"`. Drive the front/behind
  recession and the front card's one-pixel overhang with a `Margin` bound to
  a view-model property, animated by a `Storyboard`
  `DoubleAnimation`/`ThicknessAnimation` (`Duration="0:0:0.16"`, an
  `EasingFunction` matching `easeOut`, e.g. `CubicEase EasingMode="EaseOut"`),
  skipped in favor of an immediate `Margin` set when
  `Windows.UI.ViewManagement.UISettings.AnimationsEnabled` (or the app's own
  Reduce Motion setting) is off — mirroring the Reduce Motion gap noted above,
  which this port should not repeat. Swap `Background`/`Foreground`
  `SolidColorBrush`es between the front and behind palettes with a
  `VisualStateManager` `FrontCard`/`BehindCard` state group, the way
  `applyDepth()` swaps palette roles. Lay out the header as a `Grid` with
  `Auto,Auto,*,Auto` columns (agent label, status stack, gap, close button) —
  a horizontal `StackPanel` cannot host a star-sized column, so the third
  column's `*` sizing takes the place of `gap`, absorbing the header's extra
  width — followed by a close `Button` in the fourth column, styled borderless
  (`Style="{StaticResource TransparentButtonStyle}"` or equivalent), sized
  `14x14`, using the Segoe Fluent Icons `&#xE711;` ("Cancel") glyph, with
  `AutomationProperties.Name="Close"`. Represent the status symbols as a
  horizontal `ItemsRepeater`/`StackPanel` of `14x14` `FontIcon`s, each with
  its own `AutomationProperties.Name` bound to the caller-supplied label.
  Bind `MinWidth`/`MinHeight` growth to the hosted content's measured
  `DesiredSize` plus the recession slack, mirroring `contentSize`.

## Design Decisions

- Decision: `init?(coder:)` is `@available(*, unavailable)` and its body
  returns `nil` rather than calling `fatalError()`.
  Rationale: The `unavailable` attribute already makes this initializer
  uncallable from Swift source, so the body is unreachable in practice;
  returning `nil` here (and in the file-private `TabCardBackgroundView`'s own
  `init?(coder:)`) is what this file does, rather than the `fatalError()`
  pattern used by some other AppKit types in the codebase — noted here per
  source fidelity rather than smoothed over.
  Approved: pending
- Decision: `stackDepth` accepts any `Int` with no clamp, and
  `recession(atDepth:)` treats any non-positive depth as zero recession while
  `isFrontCard` still requires `stackDepth == 0` exactly.
  Rationale: `TabBarStackedItem.stackDepth`'s own doc comment defines depth as
  "0 for the selected item itself, 1 for either neighbour, and on outward" —
  non-negative by contract — and the one caller in this codebase
  (`TabPaneViewController.applyDepth()`) always passes `max(1, stackDepth)` or
  `0`, so a negative depth never currently reaches this view. Nothing in
  `TabPaneView.swift` itself enforces that contract, so the combination is
  recorded here per source fidelity rather than assumed away.
  Approved: pending
- Decision: `recession(atDepth:)` grows with depth only on a vertical
  (`.left`/`.right`) edge; a horizontal (`.top`/`.bottom`) edge gets the same
  flat `4pt` inset at every depth greater than zero.
  Rationale: Per `Edge.isVertical`'s and `TabPaneView.recession`'s own doc
  comments, only a vertical bar lays its cards in a column with room to
  recede down; a horizontal bar's cards sit side by side along their long
  axis with no depth to show, so there is nothing for a second or third step
  to add.
  Approved: pending
- Decision: The card's own view is left unpinned on both axes — no
  self-constraint on width or height.
  Rationale: Per `setUp()`'s inline comment, the cross axis is the hosting
  bar's own required-priority constraint (`TabBarView.rebuildButtons()`) and
  the length axis is AppKit's own priority-501
  `NSViewController.preferredContentSize` constraint, driven by
  `contentSize`; a required self-pin here would restate one of those two
  numbers at required priority and risk an unsatisfiable conflict with
  whichever one wins.
  Approved: pending
- Decision: `contentSize` measures `content.fittingSize`, not the card's own
  `fittingSize`.
  Rationale: Per the property's doc comment, `TabPaneViewController` installs
  AppKit's priority-501 `preferredContentSize` constraints onto the card
  itself, and the labels resist compression at only `.defaultLow` — so asking
  the card for its own `fittingSize` after a first measurement would return
  that first answer again, and a card whose text grows on a later `reload()`
  would never widen. The stack (`content`) carries none of those constraints,
  so it is measured instead.
  Approved: pending
