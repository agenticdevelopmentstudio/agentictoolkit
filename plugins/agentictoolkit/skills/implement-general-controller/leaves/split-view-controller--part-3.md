<!-- leaf: implement-general-controller/split-view-controller--part-3 · source: split-view-controller.md -->

# SplitViewController — continued (part 3)

**Rules** (cite as `implement-general-controller/split-view-controller--part-3#<slug>`):

- `clears-search-on-programmatic-navigation` MUST
- `propagates-navigation-change-upward` MUST
- `reports-current-panel-from-detail-container` MUST
- `reports-effective-help-from-current-panel` MUST
- `refreshes-help-through-detail-chrome-and-outward` MUST
- `hosts-self-managing-panels-without-wrapper` MUST
- `wraps-other-panels-in-scroll-view` MUST
- `updates-help-and-floor-on-every-show` MUST
- `locates-enclosing-split-by-parent-chain` MUST
- `keyboard-assistive-technology-navigation` MUST — The component MUST redirect Down/Up inside the sidebar search field to sidebar-row selection …

- **clears-search-on-programmatic-navigation**: Showing a panel via
  `goBack()`, `goForward()`, `selectPanel(_:)`, or `selectPanel(at:)` MUST
  clear the sidebar search field and query first, so the target row is
  never hidden by a stale filter.
- **propagates-navigation-change-upward**: Whenever this instance's
  selection, history availability, or panel title changes, it MUST invoke
  its own `onNavigationChange` and MUST also invoke the enclosing
  `SplitViewController`'s navigation-change notification, if one exists.
- **reports-current-panel-from-detail-container**: `currentPanel` MUST
  always reflect whichever panel is currently hosted in the detail pane,
  recomputed from the detail pane's actual content rather than from any
  separately tracked selection state (see the source mechanism in Platform
  Notes).
- **reports-effective-help-from-current-panel**: `effectiveHelp` MUST
  return the current panel's own `effectiveHelpContent`.
- **refreshes-help-through-detail-chrome-and-outward**: `refreshHelp()`
  MUST hand `effectiveHelp` to `panelHost.setHelp(_:)` and MUST also call
  the enclosing split's `refreshHelp()`, if one exists.
- **hosts-self-managing-panels-without-wrapper**: `show(_:)` MUST host a
  panel directly in `panelHost` (no wrapping scroll view) when that panel
  is itself a `SplitViewController` or reports `hostsOwnScroll == true`.
- **wraps-other-panels-in-scroll-view**: `show(_:)` MUST wrap every other
  panel's view in a `PanelScrollView` before hosting it in `panelHost`.
- **updates-help-and-floor-on-every-show**: Every call to `show(_:)`,
  including `show(nil)`, MUST refresh the detail chrome's help content and
  MUST re-apply the detail-pane minimum-thickness floor.
- **locates-enclosing-split-by-parent-chain**: `enclosingSettingsSplit`
  MUST always reflect the current view-controller hierarchy — recomputed
  from the live containment relationship each time it is read, not cached
  — returning `nil` when no enclosing split exists (see the source
  mechanism in Platform Notes).
## Appearance

- **Corner radius**: Not applicable — this file draws no chrome of its own;
  any corner radius shown by hosted panel content belongs to that content's
  own recipe.
- **Padding**: The detail pane's content view (`panelHost`) is pinned to
  its container's safe-area top and to the container's leading, trailing,
  and bottom edges with zero additional inset (`viewDidLoad`'s
  `NSLayoutConstraint.activate` block); no other padding constant is set in
  this file.
- **Font**: Not applicable — this file sets no font of its own; the search
  field's font is `ThemedSearchField`'s own responsibility.
- **Background**: `view.window?.backgroundColor` and
  `detailContainer.view.layer?.backgroundColor` are both set to the active
  `SemanticPalette`'s `windowBackgroundColor` role, in `applyTheme(_:)`.
- **Foreground/Text**: Not applicable — this file sets no text color of its
  own.
- **Border**: Not applicable — no border is configured in this file.
- **Shadow**: Not applicable — no shadow is configured in this file.
- **Min/Max size**: `detailMinimumThickness` defaults to `400`pt and floors
  the detail item's `minimumThickness` (raised to `nestedDetailFloor` when
  larger). The sidebar item is either draggable between `160` and `360`pt
  (`contentSizedSidebar == false`) or pinned at
  `min(minimumSidebarWidthOverride ?? listViewController.preferredWidth(), 480)`pt
  (`contentSizedSidebar == true`). No maximum is set on the detail item.

## Accessibility

- **Role/trait**: Not applicable — this file assigns no accessibility role
  of its own; the sidebar rows (`PanelListViewController`), the detail
  chrome's help button (`PanelHostView`), and each hosted panel each own
  their own accessibility semantics in their own recipes.
- **Keyboard/assistive technology navigation**: The component MUST redirect
  Down/Up inside the sidebar search field to sidebar-row selection
  (**redirects-arrow-keys-to-selection**), leaving every other command
  (Return, Escape, Left/Right, text editing) to the field's default
  behavior. Beyond that redirect, this file adds no keyboard handling of
  its own; the standard `NSSplitViewController`/`NSOutlineView` tab order
  is unmodified.
- **Label requirements**: Supported for the search field: `NSSearchField`
  exposes its `placeholderString` as the field's accessible description by
  default, and this file sets no additional label of its own. That
  placeholder text is not itself localized (see Localization).
- **Announce state changes (e.g., loading, disabled)**: Not applicable —
  this file has no loading or disabled state to announce (see States).
- **Minimum tap target**: Not applicable — this is a pointer-driven macOS
  container; no touch-target constant is set anywhere in this file. Hit
  sizing for the search field and split divider is standard AppKit sizing,
  not a value this file chooses.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `detailMinimumThickness` | `CGFloat` (open, overridable) | `400` | Floor on the detail pane's `NSSplitViewItem.minimumThickness`. |
| `sidebarAutosaveName` | `String?` (open, overridable) | `"ComposableSettings.RootSidebar"` | `NSSplitView.autosaveName` used when `contentSizedSidebar == false`. |
| `contentSizedSidebar` | `Bool` (open, overridable) | `false` | `true` pins the sidebar to its content width and disables dragging/autosave; `false` keeps the draggable, autosaved band. |
| `minimumSidebarWidthOverride` | `CGFloat?` | `nil` | External floor for a content-sized sidebar's width, set by a parent split to unify nested siblings. |
| `sidebarTitle` | `String?` | `nil` | Header title shown above the sidebar's panel list. |
| `showsSidebarSearch` | `Bool` | `false` | Whether the sidebar leads with a search field; read once, in `viewDidLoad`. |
| `sortsPanelsByTitle` | `Bool` | `false` | Whether `setPanels`/`addPanel` alphabetize panels (within section) instead of keeping supplied order. |
| `showsInlineHelpButton` | `Bool` | `true` | Whether the detail pane's own `panelHost` draws its `?` button. |
| `helpPresenter` | `SettingsHelpPresenting?` | `nil` | Where help content and visibility are shown; forwarded to `panelHost.helpPresenter`. |
| `listViewController` | `PanelListViewController` | `PanelListViewController()` | The sidebar controller; injectable via `init(listViewController:)`. |

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| `"Search"` | Search | Placeholder text for the sidebar's search field, passed as `ThemedSearchField(placeholder: "Search")` and stored as AppKit's `placeholderString` — a literal `String`, not routed through any localization lookup in this file. |

The `"Search"` placeholder is not localized: `SplitViewController.swift`
passes it as a hardcoded literal to `ThemedSearchField(placeholder:)`,
never routing it through `NSLocalizedString`/`String(localized:)`, both of
which are used elsewhere in this Swift package (outside this file).

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: no animation, transition, or motion effect appears anywhere in this file. |
| Increase Contrast | Not applicable to this file: colors come from `SemanticPalette` via `ThemePaletteObserver`; any Increase Contrast adaptation is that type's responsibility, not something this file computes. |
| Differentiate Without Color | Not applicable: this file has no color-only state indicator; row selection is `PanelListViewController`'s concern. |

## Privacy

- **Data collected**: None beyond the panels and search text the host
  supplies at runtime; the sidebar search query lives only in memory.
- **Storage**: When `contentSizedSidebar == false` (the default), the
  sidebar's dragged width is persisted locally via `NSSplitView`'s built-in
  `autosaveName` mechanism (backed by `UserDefaults`), keyed by
  `sidebarAutosaveName`. No other state in this file is persisted; the
  search query and navigation history are in-memory only and are discarded
  on `setPanels(_:)`, `clear()`, or app relaunch.
- **Transmission**: Not applicable — no networking call appears anywhere in
  this file.
- **Retention**: The autosaved sidebar width persists under its key
  indefinitely, until the user drags it again or the underlying
  `UserDefaults` entry is cleared by the OS or the app; it is never written
  by this file when `contentSizedSidebar == true`.

