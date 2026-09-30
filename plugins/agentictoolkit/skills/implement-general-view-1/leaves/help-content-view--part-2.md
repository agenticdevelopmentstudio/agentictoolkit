<!-- leaf: implement-general-view-1/help-content-view--part-2 · source: help-content-view.md -->

# HelpContentView — continued (part 2)

## Privacy

- **Data collected**: None — the view holds only the `HelpContent` struct
  (topic titles and bodies) passed to it by the caller; it originates no
  data of its own.
- **Storage**: Not applicable — the source performs no persistence of any
  kind.
- **Transmission**: Not applicable — no networking call appears anywhere in
  source.
- **Retention**: The most recently set `content` is held in memory as a
  private stored property for the view's own lifetime, and is replaced (not
  appended to) on every subsequent `setHelp(_:)` call; nothing persists
  across app launches.

## Platform Notes

- **SwiftUI**: Compose a `VStack(alignment: .leading, spacing: 0)` with a
  fixed `Text("Help").font(.headline)` (or a themed heading style) as the
  first child, and a `ScrollView { LazyVStack(alignment: .leading) {
  ForEach(topics) { topic in ... } } }` below it — the `VStack`'s own
  layout keeps the heading outside the `ScrollView`'s scroll content the
  same way `titleLabel` sits outside `PanelScrollView` here. Render each
  topic as a card-styled `GroupBox` or custom container plus a wrapping
  `Text` for the body, mirroring `GroupView` + `ExplanationView`. Show the
  fixed "No Help Yet" card when the topics array is empty, and drive the
  whole scroll content from a single `@State`/bound `HelpContent?` so
  reassigning it fully replaces the `ForEach` content the way
  `setHelp(_:)` does.
- **Compose**: Use a `Column { Text("Help", style =
  MaterialTheme.typography.titleMedium); Column(Modifier.verticalScroll(...))
  { topics.forEach { ... } } }` (or `LazyColumn` for long lists) — the
  outer `Column`'s heading stays fixed above the scrollable inner content
  the same way the AppKit heading sits above `PanelScrollView`. Render each
  topic as an `ElevatedCard` containing a title `Text` and a wrapping body
  `Text`, Compose's analog of `GroupView`/`ExplanationView`; recomposing
  with a new topics list naturally replaces the scrolled content the way
  `setHelp(_:)` rebuilds the panel.
- **React/Web**: A flex column with a non-scrolling `<h2>Help</h2>` header
  and a sibling `<div style="overflow-y: auto; flex: 1">` beneath it
  holding one card component per topic (a heading plus wrapping prose),
  re-rendered from whatever list state backs `content`; render a single
  "No Help Yet" card when that list is empty, and reset
  `scrollTop = 0` on the scrollable container whenever the topic list
  changes, mirroring **scroll-reset**.
- **AppKit / UIKit** (source platform): Source at
  `packages/apple/AgenticToolkit/macOS/UI/Help/HelpContentView.swift` (this
  recipe's source): a macOS-only (`import AppKit`) `NSView` subclass,
  `@MainActor`, composing one `NSTextField` heading with a
  `ComposableSettings.PanelScrollView` hosting a `ComposableSettings.PanelView`
  built from `GroupView`/`ExplanationView` rows. A UIKit port replaces
  `NSTextField` with a `UILabel`, `PanelScrollView`/`PanelView` with a
  `UIScrollView` hosting a `UIStackView` of card views, and
  `ThemePaletteObserver`'s AppKit-side theme-change notification with
  UIKit's own trait-collection/theme-change hook. The constraint equations
  behind **fixed-help-heading** and **independently-scrolling-content**:
  `titleLabel.topAnchor == self.topAnchor + inset`,
  `titleLabel.leadingAnchor == self.leadingAnchor + inset`,
  `titleLabel.trailingAnchor <= self.trailingAnchor - inset`,
  `scrollView.topAnchor == titleLabel.bottomAnchor`, and
  `scrollView`'s leading/trailing/bottom anchors each equal to `self`'s
  with no constant, where `inset` is
  `ComposableSettings.SettingsLayout.default[.panelInset]` (20pt).
- **WinUI 3** (the reason this recipe exists): Build this as a two-row
  `Grid`: row 0, `Auto` height, holds a `TextBlock Text="Help"` styled with
  `SubtitleTextBlockStyle` (the Fluent 2 analog of the 15pt semibold
  heading font), inset from the grid's edges by a 20px `Margin` to match
  `panelInset`; row 1, `*` height, holds a `ScrollViewer` with
  `VerticalScrollBarVisibility="Auto"` containing an `ItemsRepeater` (or
  `ItemsControl`) bound to an `ObservableCollection<Topic>`. Template each
  topic as a `Border` styled with `CardBackgroundFillColorDefaultBrush` and
  `CornerRadius="10"` (matching `cardCornerRadius`), containing a
  `TextBlock` for the title (`BodyStrongTextBlockStyle`) and a wrapping
  `TextBlock` for the body (`BodyTextBlockStyle`,
  `TextWrapping="WrapWholeWords"`) — WinUI 3's analogs of `GroupView`'s
  header and `ExplanationView`. Swap the bound collection's contents (or
  reset it to a single "No Help Yet" item) on every call that plays the
  role of `setHelp(_:)`, and call
  `scrollViewer.ChangeView(null, 0, null, true)` immediately after, to
  reproduce **scroll-reset** — `ItemsRepeater`
  does not reset scroll position on its own the way `PanelScrollView`'s
  `setContent(_:)` does. Bind `Border.Background` (the topic card) to
  `{ThemeResource LayerFillColorDefaultBrush}` and `TextBlock.Foreground`
  to `{ThemeResource TextFillColorPrimaryBrush}`, but bind the outer
  `Grid`'s own `Background` to `{ThemeResource
  SolidBackgroundFillColorBaseBrush}` — the window's own ground, not a
  distinct layer color — to reproduce **window-background**: the cards
  read as elevated only because the grid behind them matches the window,
  the same way `windowBackgroundColor` does here. Bind all three through
  `{ThemeResource}` rather than a fixed color, so `RequestedTheme`/
  light-dark changes repaint automatically the way `ThemePaletteObserver`
  repaints this view on every theme change.

## Design Decisions

- **Decision**: `HelpContentView` composes `GroupView` and `ExplanationView`
  — types that still live under the `ComposableSettings` namespace — for
  help content, not settings.
  **Rationale**: the source's own doc comment states this is "the same two
  views the settings panels are built from," so help reads in the same
  type and rhythm as the controls it describes, and states plainly that the
  `ComposableSettings` naming for these shared views "is a naming debt, not
  a layering one (it is all one framework), and paying it off is a larger
  change than this file should make."
  **Approved: pending**
- **Decision**: When `setHelp(_:)` is given `nil` or an empty topics list,
  the view shows a fixed "No Help Yet" group instead of closing the drawer
  or leaving the scroll area blank.
  **Rationale**: the source's own doc comment on `emptyTitle`/`emptyBody`
  explains that the drawer previously closed itself in this case, which
  "made it slam shut on the way to a panel with nothing to say and slide
  open again on the way out, an animation nobody asked for that reads as
  the window flinching," and concludes "an honest sentence beats an empty
  pane that reads as a rendering failure."
  **Approved: pending**
- **Decision**: The view's background layer is painted with
  `palette.windowBackgroundColor` — the same color as the window and drawer
  around it — rather than a distinct background.
  **Rationale**: the source's inline comment states this is deliberate so
  that "the cards are what should stand out" and a heading-shaped band of a
  second near-identical grey above them "only reads as a misprint."
  **Approved: pending**
- **Decision**: `setHelp(_:)` always tears down and rebuilds the entire
  panel from scratch, with no comparison against the previously stored
  `content`, even though `HelpContent` is `Equatable`.
  **Rationale**: not stated in source; inferred from the absence of any
  equality check or partial-update path. `setHelp(_:)` is called only when
  the panel/topic selection changes — `SplitViewController.show(_:)` and
  `refreshHelp()`, in
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/SplitViewController/SplitViewController.swift`,
  are the only call sites (reached through `PanelHostView` and
  `HelpDrawerController.setHelp(_:)`), and both fire from the reader
  changing which panel or topic is selected — not on a hot or
  performance-sensitive path, so a full rebuild is the simplest correct
  behavior rather than a documented optimization trade-off.
  **Approved: pending**
