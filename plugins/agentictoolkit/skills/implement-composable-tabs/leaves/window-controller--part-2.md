<!-- leaf: implement-composable-tabs/window-controller--part-2 · source: composable-tabs-window-controller.md -->

# ComposableTabsWindowController — continued (part 2)

## Accessibility

- Role/traits: standard `NSWindow` with title-bar close/miniaturize/zoom
  buttons; toolbar and titlebar-accessory controls are plain `NSButton`s
  (custom-view toolbar items, since `NSToolbarItem` is not itself
  accessible) and a system `NSSearchField`.
- Accessibility identifiers: the search field and help button carry the
  toolbar identifiers `project.toolbar.search` and `project.toolbar.help`;
  the titlebar accessories carry `project-window.arrange-button` and
  `project-window.project-settings-button`.
- Label requirements: the help button's accessibility description is fixed
  at "Help" and does not change when its glyph/tooltip swap for open vs.
  closed; the arrange and settings buttons carry the accessibility
  descriptions "Arrange Panes" and "Project Settings"; the search field's
  placeholder is the search target's `searchPlaceholder` or "Search" when
  none applies.
- Announce state changes: the help toggle communicates its open/closed
  state through symbol shape (outline vs. filled) and tooltip text, not
  tint alone; the arrange toggle communicates its state through `NSButton`
  state (`.on`/`.off`, which AppKit renders as a pressed bezel on
  `.texturedRounded`) in addition to tint.
- Minimum control size: macOS is a pointer-driven platform with no mandated
  minimum touch-target size; the titlebar accessory buttons are built at
  36×24pt and the toolbar icon buttons follow `NSToolbar`'s standard
  icon-only sizing, consistent with this codebase's other toolbar/titlebar
  controls rather than a value this component decides on its own.
- Keyboard/focus: the titlebar and toolbar buttons are ordinary
  keyboard-focusable `NSButton`s (Space/Return activate); the search field
  is a standard `NSSearchField` with normal text-field key handling; the
  arrange action is additionally reachable through any menu item bound to
  `toggleArrangeMode(_:)`, validated by `NSMenuItemValidation`.
- Color/contrast: chrome colors are read from the shared theme palette
  (`ThemePaletteObserver`); contrast is a design-system-level concern
  outside this controller's own decisions, per
  `agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages`.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `project` | `ProjectWorkspace` | required | The project workspace this window displays; supplies id, display name, directory, initial tabs, and local settings storage. |
| `tabItemDataSource` | `ComposableTabsTabItemDataSource?` | `nil` | Supplies each tab's edge-bar item; `nil` falls back to a plain title button (see **title-tab-fallback**). |

## Localization

Applicable, and unmet: every user-facing string in this file — `"Search"`,
`"Help"`, `"Show Help"` / `"Hide Help"`, `"Arrange Panes"`, `"Project
Settings"`, `"Panes"`/`"Minimizing"`/`"Zoom"`/etc. help topic bodies, and the
default tab title `"Tab \(n)"` — is a hardcoded English literal. The source
contains no localization key lookup (no `NSLocalizedString`, no string
catalog reference). This is recorded as accepted debt in Design Decisions
above, and is reflected in Compliance below (`string-externalization`,
`no-hardcoded-strings`).

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: the window controller performs no animated transitions of its own; tab installation, arrangement mirroring, and drawer open/close are owned by `MultiTabbedViewController` and `WindowDrawer`, each a separate ingredient. |
| Increase Contrast | Not applicable: chrome colors are sourced from the shared theme palette (`ThemePaletteObserver`); contrast handling is a design-system-level concern this controller does not decide. |
| Differentiate Without Color | Handled: the help toggle differentiates open/closed by symbol shape (outline vs. filled `questionmark.circle`) and tooltip text, not by tint alone; the arrange toggle differentiates on/off by `NSButton.state` (rendered as a pressed bezel on `.texturedRounded`) in addition to tint. |

## Privacy

- **Data collected**: the window's frame (position and size) keyed by
  project id; the project's full tab layout (`TabRecord` list — split tree,
  titles, working directories, focused leaf id, active tab id, enabled
  edges); the help drawer's per-project preferences (`drawer.open`,
  `drawer.tab`, `drawer.width`, stored under `project_setting`).
- **Storage**: window frame is stored locally via
  `WindowManager.shared.frames`, keyed by `windowID(for:)`; tab layout and
  drawer preferences are stored locally via `project.persistTabs(...)` and
  `project.setSetting(_:to:)` in the project's own settings/database. No
  networked store is used anywhere in this file.
- **Transmission**: none. No networking import or call appears in this file;
  everything persisted here stays on the local device.
- **Retention**: the window frame persists until the project's saved window
  state is cleared (`WindowFrameManager.clearSavedState(for:)`, per the
  comment on `windowID(for:)`). Tab layout and drawer preferences persist
  until overwritten or the project is deleted. Drawer tab/width are written
  only after help has been disclosed at least once
  (`hasDisclosedHelp`); a project whose help was never opened stores none of
  that preference.

## Platform Notes

- **SwiftUI**: not the source form. A SwiftUI rebuild would key a
  `WindowGroup`/`Scene` by project id for per-window state, with one
  `TabView`-like construct per enabled edge, all reading the same
  `[TabGroup]` model so a "project tab" still means one logical entry drawn
  on every enabled bar — SwiftUI's `TabView` has no native concept of
  multiple, independently dockable tab bars sharing one selection, so this
  would need a custom container rather than a bare `TabView`.
- **Compose (Android/Desktop)**: model the window as one
  `Activity`/`ComposeWindow`; represent each enabled edge as a `TabRow` (top)
  or a side rail composable (left/right) or a bottom bar, all driven by one
  shared `[TabGroup]`-equivalent state holder in a `ViewModel`; the
  250ms focused-leaf debounce and the persist-on-structural-change split map
  onto `SavedStateHandle` writes gated the same way.
- **React/Web**: the window becomes a page or route; each edge's tab strip
  is a component reading from one shared tab-groups store (Redux/Zustand);
  the toolbar search field maps to an `<input type="search">` wired to
  whichever pane component is currently "the search target," mirroring
  `searchTargetNodeID`; window-frame persistence has no web equivalent
  (the browser owns window chrome) and would be dropped, keeping only the
  tab-layout and drawer-preference persistence.
- **AppKit / UIKit**: this is the source platform, and it is AppKit-only —
  no UIKit counterpart exists in source. Files: this file
  (`ComposableTabsWindowController.swift`), `PaneSpacing.swift`,
  `ComposableTabsPaneViewController.swift` (for `titleBarBottom`),
  `SingleWindowController.swift` / `WindowController.swift` /
  `WindowSpec.swift` (window lifecycle and geometry persistence),
  `WindowToolbarBuilder.swift` (toolbar items and the disclosure-glyph
  helper), `Edge.swift`, `ComposableTabsTabItemDataSource.swift`, and
  `LayoutNode.swift` (`TabRecord`).
- **WinUI 3**: the closest native shape is a single `Window` whose primary
  edge uses `Microsoft.UI.Xaml.Controls.TabView` — WinUI 3's `TabView` only
  docks along the top, so the other three edges (right/bottom/left) have no
  built-in equivalent and need a custom `ItemsRepeater`/`ListView` styled as
  a side or bottom tab strip, all bound to one shared tab-group view-model
  list so a "project tab" still means one logical entry represented on every
  enabled strip. Persisted window geometry maps to `AppWindow.Resize`/`Move`
  saved to `ApplicationData.LocalSettings` keyed by project id, mirroring
  `windowID(for:)`. There is no WinUI drawer primitive for the help panel;
  use a `SplitView` in `Inline` or `CompactOverlay` display mode pinned to a
  window edge, with `IsPaneOpen`/`OpenPaneLength` bound to the same
  per-project `drawer.open`/`drawer.width` settings keys, written only after
  first disclosure exactly as `hasDisclosedHelp` gates it here. The unified
  toolbar's search field maps to an `AutoSuggestBox` in the window's
  `TitleBar`/`CommandBar`, toggling `IsEnabled` the same way
  `NSSearchField.isEnabled` is toggled; the arrange and settings buttons map
  to two `AppBarButton`s in a `CommandBar`, with the arrange toggle using an
  `AppBarToggleButton`'s `IsChecked` visual state in place of AppKit's
  tint-plus-`NSButton.state` combination.

