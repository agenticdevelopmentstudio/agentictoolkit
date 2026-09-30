<!-- leaf: implement-panel/host-view--part-3 · source: panel-host-view.md -->

# PanelHostView — continued (part 3)

## Platform Notes

- **SwiftUI**: Compose a `ZStack(alignment: .topTrailing)` with the
  swapped panel content as the base layer and a borderless `Button` as the
  overlay, offset `.padding(.top, 12).padding(.trailing, 12)`. Drive the
  button's `Image(systemName:)` between `"questionmark.circle.fill"` and
  `"questionmark.circle"`, and its `.foregroundStyle` between `.tint` and
  `.secondary`, from an observed `isHelpVisible` on whatever object plays
  the presenter's role; gate the button's presence on
  `showsHelpButton && helpPresenter != nil` the same way this view does.
  Content swap becomes whatever view a `@ViewBuilder`/enum-driven switch
  renders, since SwiftUI needs no manual subview teardown.
- **Compose**: A `Box` with the panel content filling it and an
  `IconButton` aligned `Alignment.TopEnd` with
  `Modifier.padding(top = 12.dp, end = 12.dp)`; swap between a filled and
  an outline "help" icon (e.g. `Icons.Filled.Help` /
  `Icons.Outlined.HelpOutline`) and between `MaterialTheme.colorScheme.primary`
  and `.onSurfaceVariant` tint from a `helpVisible: Boolean` state, and
  gate the button's presence on the same `showsHelpButton && helpPresenter
  != null` condition.
- **React/Web**: A relatively-positioned container `<div>` with the panel
  content as children and an absolutely positioned `<button>`
  (`position: absolute; top: 12px; right: 12px`) rendering an inline
  SVG/icon-font glyph that swaps between an outline and a filled variant;
  the button's `aria-label="Help"` stays fixed while a `title` attribute
  (or a tooltip component) swaps between "Show Help"/"Hide Help", mirroring
  the fixed-label/changing-tooltip split in source. CSS custom properties
  (or a theme context) supply the accent/secondary colors that swap with a
  `visible` boolean class or data attribute.
- **AppKit / UIKit** (source platform): Source at
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/PanelHostView.swift`
  (this recipe's source): a macOS-only (`import AppKit`), `@MainActor`
  `NSView` subclass. Specific to it: the manual subview teardown in
  `setContent(_:)` (`contentContainer.subviews.forEach { $0.removeFromSuperview() }`);
  the help button being added as a sibling of, and after, the content
  container so it always draws above swapped panels regardless of what
  they contain; the shared `NSView.pinToEdges(_:of:)` static helper
  (`ViewLayout.swift`) used for both the container's and the content
  view's edge constraints; the `buttonInset` constant (12pt) driving
  the button's own two constraints; and
  `translatesAutoresizingMaskIntoConstraints = false` set on
  `PanelHostView` itself, the content container, and the help button, per
  **constraint-based-layout-only**. A UIKit port would use a `UIView`
  overlaying a `UIButton(configuration: .plain())` pinned with
  `NSLayoutConstraint`s the same way, but no analogue currently exists
  elsewhere in this codebase's `ComposableSettingsWindow/` tree — the rest
  of it is AppKit-only.
- **WinUI 3**: Build this as a single-cell
  `Grid`: the swapped panel content (a `ContentControl` or `Frame` whose
  `Content` is reassigned the way `setContent(_:)` swaps subviews) fills
  the cell, and a borderless `Button` (`BorderThickness="0"`,
  `Background="Transparent"`, no `Style` resource applying a bezel) shares
  the same cell with `HorizontalAlignment="Right" VerticalAlignment="Top"
  Margin="0,12,12,0"` to match the 12px inset. The button's `Content` is a
  `FontIcon` bound to a Segoe Fluent Icons glyph; Segoe Fluent Icons has no
  built-in filled/outline question-mark pair the way SF Symbols does, so
  matching the source's filled-vs-outline distinction needs either two
  custom icon glyphs or a single glyph plus a `Fill`/`Stroke` visual-state
  swap — call this out as a deviation rather than a drop-in equivalent.
  Drive the two visual states with a `VisualStateManager`
  (`HelpHidden`/`HelpVisible`, swapping `Foreground` between
  `{ThemeResource AccentTextFillColorPrimaryBrush}` and
  `{ThemeResource TextFillColorSecondaryBrush}`) rather than imperative
  color assignment. Set `AutomationProperties.Name="Help"` (fixed, mirroring
  the source's static accessibility label) and bind `ToolTipService.ToolTip`
  to a string that swaps "Show Help"/"Hide Help" — WinUI's
  `AutomationProperties.Name` and `ToolTipService.ToolTip` are two separate
  properties, just as AppKit's accessibility label and `toolTip` are here,
  so the fixed-label/changing-tooltip split translates directly. Gate the
  button's `Visibility` on the same `showsHelpButton`-and-presenter
  condition used in source.

## Design Decisions

**Decision**: The help button is shown for every panel a split hosts, based
solely on `showsHelpButton` and whether a `helpPresenter` is assigned —
never on whether the panel currently on screen has any help content.
**Rationale**: per the source's own comment on `updateHelpButton()`, it used
to come and go with `help != nil`, which "put a control in the corner of
some panels and not others and made the drawer look like a property of
the panel rather than of the window."
**Approved**: pending

**Decision**: `claimHelpAnchorIfShown()` re-runs unconditionally on every
`helpPresenter` assignment and every `showsHelpButton` change, rather than
claiming the anchor once at construction.
**Rationale**: per the source's own comment on `claimHelpAnchorIfShown()`,
claiming the anchor only once meant a later `helpPresenter` reassignment
"silently took it back" from whoever held it, "and handed a popover
presenter a hidden, zero-size view to hang off."
**Approved**: pending

**Decision**: Route chrome outside this view (e.g. a toolbar help button)
through a dedicated `onHelpVisibilityChange` callback rather than sharing
`helpPresenter.onVisibilityChange` directly.
**Rationale**: per the source's own comment on `onHelpVisibilityChange`,
`onVisibilityChange` "has exactly one slot" on the presenter and this view
claims it for its own inline button; anything else that needs the same
notification has to be told by whoever holds that slot rather than
overwriting it.
**Approved**: pending
