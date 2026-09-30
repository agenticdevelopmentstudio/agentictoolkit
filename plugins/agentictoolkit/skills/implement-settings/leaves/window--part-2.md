<!-- leaf: implement-settings/window--part-2 · source: settings-window.md -->

# SettingsWindow — continued (part 2)

## Appearance

- **Corner radius**: Not applicable — a standard `NSWindow`; this file draws
  no custom-cornered chrome.
- **Padding**: Not decided in this file — toolbar item spacing is AppKit's
  standard `NSToolbar` layout, and a panel's own content padding is decided
  by that `SettingsPanelViewController` subclass, a separate ingredient.
- **Font**: The panel-title label's font is the active theme palette's
  `.heading` text-role font (`ThemedLabel` reads it from
  `SemanticPalette.font(_:)`), not a literal point size chosen in this file.
  The help button's SF Symbol is rendered at 15pt, `.regular` weight
  (`NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)`, applied
  in `WindowToolbarBuilder.applyDisclosureAppearance`).
- **Background**: The window's background color is set once, at window
  creation, by the inherited `SingleWindowController.loadWindow()` to
  `ThemePaletteObserver.currentPalette.windowBackgroundColor` — not by this
  file. With `titlebarAppearsTransparent = true` and no titlebar separator,
  the sidebar's and detail pane's own fills read as one continuous color
  under the toolbar band rather than a strip of system chrome laid across
  both.
- **Foreground/Text**: The panel-title label's text color is the theme
  palette's `.primaryText` color role, re-applied live on theme change; the
  help button's tint switches between the palette's `secondaryTextColor`
  and `accentColor` as described above.
- **Border**: `titlebarSeparatorStyle` is explicitly set to `.none`, so no
  separator line is drawn between the toolbar and the sidebar/detail panes.
- **Shadow**: Not applicable — standard system window shadow; this file
  configures no custom shadow.
- **Min/Max size**: Not decided in this file — no `minSize`/`maxSize`
  override is set here. Window sizing comes entirely from the inherited
  `SingleWindowController`/`WindowManager` machinery (a default of 600×480pt
  absent a registered `WindowSpec` for the `"settings"` id), not from any
  value in `SettingsWindow.swift` itself.

## Accessibility

- Role/traits: a standard `NSWindow` with title-bar close/miniaturize/zoom
  buttons; the toolbar's navigation and help controls are plain
  `NSSegmentedControl`/`NSButton` instances hosted in custom-view toolbar
  items (`NSToolbarItem` itself is not accessible), and the panel-title
  item hosts a plain `ThemedLabel` (`NSTextField` subclass).
- Accessibility identifiers: the help button's identifier is the toolbar
  item identifier's raw value, `"ComposableSettings.help"`, set by
  `WindowToolbarBuilder.iconButtonItem`. Neither the navigation control nor
  the panel-title label is given an explicit accessibility identifier in
  this file.
- Label requirements: the navigation control's combined accessibility label
  is "Back and forward"; its two segment images carry the accessibility
  descriptions "Back" and "Forward" from their `NSImage` construction. The
  help button's accessibility description is fixed at "Help" for its whole
  lifetime (see **keeps-help-accessibility-name-stable**).
- Announce state changes: the help toggle communicates open/closed through
  symbol shape (outline vs. filled) and tooltip text, not tint alone (see
  **swaps-help-tooltip-by-drawer-state** and
  **shows-filled-glyph-when-drawer-open**).
- Minimum control size: macOS is a pointer-driven platform with no mandated
  minimum touch-target size; this file sets no explicit frame for the
  navigation control or help button, so both size themselves per AppKit's
  standard icon-only toolbar sizing, consistent with this codebase's other
  toolbar controls rather than a value this file decides on its own.
- Keyboard/focus: the navigation control and help button are ordinary
  keyboard-focusable AppKit controls (Tab to focus, Space/Return to
  activate); `NSSegmentedControl` provides its own arrow-key segment
  navigation. This file customizes neither the key-view loop nor any
  keyboard shortcut for these controls.
- Color/contrast: toolbar and label colors are read from the shared theme
  palette (`ThemePaletteObserver`); contrast is a design-system-level
  concern this file does not decide, per
  `agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages`.
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented in source. The panel-title label draws its text in the `.primaryText` role and the help button tints itself with `secondaryTextColor`/`accentColor`, each against whichever theme surface renders behind it under the transparent, unified toolbar (see Appearance, Background); no contrast ratio between those roles and their background is computed or asserted anywhere in this file. Settling this needs a theme-level contrast audit of `SemanticPalette`'s roles against the surfaces they are drawn over, not a change to `SettingsWindow.swift` itself.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `settingPanels` | `[any ComposableSettingsPanel]` | `[]` | Panels shown in the sidebar; assigning replaces the hosted split's full panel set. Each panel is a separate `ComposableSettingsPanel`/`SettingsPanelViewController` ingredient. |
| `activatesOnShow` | `Bool` (open, overridable) | `true` | Whether `showWindow()` activates the app and makes the window key; a subclass overrides it to `false` to avoid stealing focus from an `LSUIElement`/menubar host. |

## Localization

Every user-facing string in this file is a hardcoded English literal passed
directly to AppKit APIs, not a localization key: `"Settings"` (window
title), `"Back"` / `"Forward"` (segment image accessibility descriptions),
`"Back and forward"` (navigation control accessibility label),
`"Back/Forward"` / `"Panel"` (toolbar item labels), `"Help"` (toolbar item
label and the help button's stable accessibility name), and `"Show Help"` /
`"Hide Help"` (tooltip text). None of these pass through
`NSLocalizedString` or a String Catalog lookup anywhere in this file.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: this file performs no animation of any kind (not even an opacity fade) — the help glyph swap is an instantaneous image/tint/tooltip change with no transition to reduce. |
| Increase Contrast | Not applicable: every color used here is read from the shared theme palette (`ThemePaletteObserver`); contrast handling is a design-system-level concern this file defers to that shared, separately-recipe'd system. |
| Differentiate Without Color | Handled: the help toggle differentiates open/closed by symbol shape (outline vs. filled `questionmark.circle`) and by tooltip text, not by tint alone (see **shows-filled-glyph-when-drawer-open** and **swaps-help-tooltip-by-drawer-state**). |

## Privacy

- **Data collected**: This file collects no data directly. It constructs a
  `HelpDrawerController` and assigns it as the hosted split's help
  presenter; that controller independently persists whether the settings
  help drawer is visible — that persistence belongs to `HelpDrawerController`,
  a separate ingredient, not to this file. This file's own state
  (`activatesOnShow`, the assigned `settingPanels`) is held in memory only.
- **Storage**: Not decided in this file. Window-frame geometry for the
  `"settings"` window id is persisted locally by the inherited
  `SingleWindowController`/`WindowManager` machinery; this file contains no
  storage call of its own.
- **Transmission**: None — no networking import or call appears in this
  file.
- **Retention**: Not decided in this file; see Storage and Data collected
  above for which components own the data this window causes to be
  persisted.

