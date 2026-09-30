<!-- leaf: implement-settings/window--part-3 · source: settings-window.md -->

# SettingsWindow — continued (part 3)

## Platform Notes

- **SwiftUI**: build the two-pane shape as a `NavigationSplitView` with a
  `List(selection:)` sidebar (sorted alphabetically to match
  `sortsPanelsByTitle`) and a `.searchable` modifier for the sidebar search.
  `NavigationSplitView`'s selection model has no back/forward concept, so
  that has to be rebuilt explicitly: a small observable object exposing
  `canGoBack`/`canGoForward` and a small history stack, driving two
  `.toolbar` `Button`s. The panel-title toolbar item becomes a
  `.principal`-placement `Text` (or the detail column's `.navigationTitle`
  read back into the toolbar), and the help toggle is a `.toolbar` button
  bound to `@State private var isHelpVisible`, swapping
  `Image(systemName:)` between `"questionmark.circle"` and
  `"questionmark.circle.fill"`.
- **Compose (Desktop/Android)**: model the window as one top-level
  composable with a `Row` of a `LazyColumn` sidebar (Material 3
  `NavigationRail`/`PermanentDrawerSheet`, alphabetically sorted, with a
  search `TextField` at its top) and a detail pane. Compose Navigation's
  back stack does not map directly to a two-pane split's back/forward, so
  mirror it with a small view-model exposing `canGoBack`/`canGoForward`
  booleans backing two `IconButton`s in the top app bar. The help toggle
  maps to an `IconToggleButton` swapping between an outlined and a filled
  help icon, tinted via `MaterialTheme.colorScheme.secondary`/`primary`.
- **React/Web**: a two-pane layout (`<nav>` sidebar + `<main>` detail);
  because browser back/forward already exists at the tab level, the
  in-window back/forward here maps to two `<button>` elements bound to
  `disabled={!canGoBack}` / `disabled={!canGoForward}` state, not to
  `history.back()`. The help toggle is a `<button aria-pressed={isOpen}>`
  swapping an inline SVG icon and its `title` attribute, opening the help
  drawer as a `role="complementary"` panel or a `<dialog>`.
- **AppKit / UIKit**: this is the source platform, and it is AppKit-only —
  no UIKit counterpart exists in source. Files: this file
  (`SettingsWindow.swift`), `SplitViewController.swift` (sidebar/detail
  split, search, navigation history — a separate ingredient),
  `ComposableSettingsPanel.swift` / `SettingsPanelViewController.swift`
  (the per-panel contract — a separate ingredient), `Help/HelpDrawerController.swift`
  (the deprecated `NSDrawer`-backed help presenter),
  `WindowToolbarBuilder.swift` (icon-button construction and the
  disclosure-glyph helper), `SingleWindowController.swift` /
  `WindowController.swift` (window lifecycle and frame persistence),
  `ThemedViews.swift` (`ThemedLabel`), and `QuietWindowPresentation.swift`
  (test/automation activation suppression). The private `updateToolbarState()`
  method is what couples the help button's refresh to navigation changes: it
  is the shared refresh path behind both `syncs-navigation-control-enablement`
  and **updates-help-glyph-on-navigation-change**, called from the
  `onNavigationChange` closure installed in `installToolbar(on:)`.
- **WinUI 3**: the closest native shape is a single `Window` hosting a
  `NavigationView` in `Left` or `LeftCompact` `PaneDisplayMode` as the
  sidebar, with `NavigationView.MenuItems` sorted alphabetically to match
  `sortsPanelsByTitle` and `NavigationView.AutoSuggestBox` set to reproduce
  `showsSidebarSearch`, and a `Frame` in the content area navigating between
  per-panel `Page`s. `NavigationView` supplies its own back button
  (`IsBackButtonVisible`) but nothing for forward, so forward needs two
  custom `AppBarButton`s in the window's `TitleBar`/`CommandBar`, bound to a
  small navigation-history view-model exposing `CanGoBack`/`CanGoForward` to
  mirror `canGoBack`/`canGoForward`. Put the panel-title `TextBlock` in that
  same `CommandBar`, bound to `Frame.CurrentSourcePageType`'s title.
  `Window.ExtendsContentIntoTitleBar = true` plus
  `Window.SetTitleBar(commandBar)` reproduces
  `.fullSizeContentView` + `titlebarAppearsTransparent` +
  `titleVisibility = .hidden` together. The help toggle is an
  `AppBarToggleButton` swapping a `FontIcon`/`SymbolIcon` between an
  outline and filled help glyph via its `IsChecked` state, driving a
  `SplitView` (`DisplayMode="Inline"` or `"CompactOverlay"`) pinned to the
  window's trailing edge as the WinUI substitute for the AppKit help
  drawer — WinUI has no drawer primitive of its own, so `SplitView` is the
  standard stand-in, matching the pattern
  `agentictoolkit://recipes/composable-tabs-window-controller` already uses
  for its own drawer translation.

## Design Decisions

**Decision**: Give the sidebar's own top slot to the search field and remove
the sidebar title entirely, rather than showing a titled sidebar with search
below it.
**Rationale**: this matches System Settings' shape (source comment); the
name of what is on screen is shown once, in the toolbar's panel-title item
beside the back/forward control, exactly where a reader is already looking
to change it — a separate sidebar title would be a second answer to the same
question.
**Approved**: pending

**Decision**: Sort panels alphabetically, always, with no host-supplied
ordering option.
**Rationale**: the panels in a settings window are unrelated destinations,
and the only thing a reader hunting for one of them knows is its name;
whatever order a host happened to register panels in is an order only the
host can see (source comment on `sortsPanelsByTitle`).
**Approved**: pending

**Decision**: Represent back/forward as one two-segment `NSSegmentedControl`
rather than two independent `NSButton`s.
**Rationale**: it is one control with one meaning — where in the navigation
trail the reader is — and a single shared bezel is how System Settings
expresses that (source comment on `navigationControl`).
**Approved**: pending

**Decision**: `activatesOnShow` defaults to `true`, with an open override
point for hosts that don't want it.
**Rationale**: a settings window is normally opened to be used immediately,
and shown from an `LSUIElement`/menubar host the base `showWindow()` still
leaves the window visible but non-key, so its sidebar selection and text
fields don't respond until the user clicks it first; defaulting to
activation avoids that dead first click for the common case, while the
override keeps the behavior optional rather than forcing it on every
consumer (source comment on `activatesOnShow`).
**Approved**: pending

**Decision**: Under `QuietWindowPresentation`, make the window key without
activating the app or ordering it above other applications' windows.
**Rationale**: an automated session driving the app still needs the sidebar
selection and text fields to respond, which requires the window to be key,
but must not steal focus or draw over whatever the person at the keyboard is
doing — that is the entire distinction this file draws between a settings
window "opened to be used" and one "opened to be driven" (source comment on
`showWindow()`).
**Approved**: pending

**Decision**: Wire the help button reference, its theme observer, and the
help-anchor view only when `willBeInsertedIntoToolbar` is `true`.
**Rationale**: AppKit calls the toolbar item factory again to build a
customization-palette sample and on every toolbar rebuild; adopting one of
those non-live copies would point all three at a button that is never on
screen, leaving the real, visible help button unthemed and unreported
(source comment on the `.settingsHelp` case).
**Approved**: pending

**Decision**: Whether to update the class doc comment (which still shows
`override func makeSettingsPanels() -> [ComposableSettings.SettingsPanelViewController]`)
to describe `settingPanels`, or to restore a `makeSettingsPanels()` override
point, is not yet settled.
**Rationale**: `SettingsWindow.swift` illustrates subclassing
through a `makeSettingsPanels()` override that does not exist anywhere in
the class — the only subclass-facing configuration surface this version
actually exposes is the `settingPanels` property (see Overview and
Configuration). This is a documentation/implementation mismatch in the
source, not a behavior this recipe can decide on its own; it belongs to
whoever maintains `SettingsWindow.swift`.
**Approved**: pending
