<!-- leaf: implement-composable-tabs/settings-view-controller--part-2 · source: composable-tabs-settings-view-controller.md -->

# ComposableTabsSettingsViewController — continued (part 2)

## Appearance

- **Corner radius**: `SettingsLayout.default[.cardCornerRadius]` on every
  group's card, inherited by composing `ComposableSettings.GroupView`'s
  `ThemedBox` — see agentictoolkit://recipes/group-view#appearance for the
  current value. This file sets no corner radius of its own.
- **Padding**: The sheet itself contributes 0pt of padding around the topic
  list (pinned flush to the root view's top/leading/trailing) and fixed
  offsets around the Done button: 12pt above it (from the topic list), 20pt
  to its trailing edge, 16pt below it. Inside each panel,
  `SettingsLayout.default[.panelInset]` = 20pt insets the group stack from
  the panel's top/leading/trailing (bottom is `lessThanOrEqualTo`, so it
  never forces extra height), and
  `SettingsLayout.default[.groupSpacing]` = 20pt separates the Spacing
  panel's two groups (the Tabs panel has only one group, so this spacing is
  never visually exercised there) — both are this file's own panel-level
  settings, not `GroupView`'s. Inside each card,
  `SettingsLayout.default[.cardHorizontalInset]` and
  `SettingsLayout.default[.cardVerticalInset]` pad each row's content, and
  `SettingsLayout.default[.captionSpacing]` separates each group's caption
  from its card — see agentictoolkit://recipes/group-view#appearance for the
  current values, since `GroupView` is what consumes them.
- **Font**: Each group's caption ("Tab Bars", "Frame Spacing", "Pane Divider
  Spacing") renders as a `ThemedLabel` with `textRole: .caption`
  (`ComposableSettings.HeaderView`, which `GroupView` builds internally).
  Each Tabs checkbox's title is forced to `palette.font(.body)` by this
  file's own `observeTheme` closure. The Spacing panel's number/label fonts
  belong to `SpacingControl`'s own implementation, not to this file.
- **Background**: The sheet's root view paints `palette.nsColor(.windowBackground)`
  (`ThemedBackgroundView(role: .windowBackground)`). Each group's card
  paints the theme's `.elevatedSurface` role via a `ThemedBox` inside
  `GroupView` — see agentictoolkit://recipes/group-view#appearance for its
  exact construction. The topic list's own panel body additionally paints
  `palette.windowBackgroundColor` behind the cards (`PanelView`, composed by
  `SettingsPanelViewController`, not set directly by this file).
- **Foreground/Text**: Each Tabs checkbox's title is forced to
  `palette.nsColor(.primaryText)` by this file. Each group's caption
  resolves to the theme's `.secondaryText` role (`HeaderView`'s
  `ThemedLabel(role: .secondaryText, ...)`). The Done button's title uses
  `NSButton`'s own default system label color; this file sets no explicit
  color on it.
- **Border**: Each card's `ThemedBox` has no border stroke of its own, and a
  hairline divider separates a card row from the row above it — both are
  `GroupView`'s construction, not this file's; see
  agentictoolkit://recipes/group-view#appearance for the current values
  (`SettingsLayout.default[.dividerThickness]`, drawn by
  `ThemedSeparatorView(role: .divider)`).
- **Shadow**: Not applicable — no shadow, `NSShadow`, or layer shadow
  property is set anywhere in this file, nor in the `GroupView`/`PanelView`/
  `ThemedBox` types it composes.
- **Min/Max size**: `preferredContentSize` is fixed at 760×520pt; the topic
  list additionally floors the detail pane at 420pt
  (`detailMinimumThickness`). No maximum size is set anywhere in source.

## Accessibility

- **Role/trait**: Not customized beyond the identifiers below — no
  `setAccessibilityRole` call appears anywhere in this file. The four
  checkboxes use `NSButton(checkboxWithTitle:)`'s built-in AppKit checkbox
  role; the Done button uses stock `NSButton` push-button role.
- **Label requirements**: Each checkbox's visible title (`edge.displayName`
  — "Top", "Right", "Bottom", "Left") supplies its accessible name; the Done
  button's visible title ("Done") supplies its accessible name. The
  accessibility identifiers this file sets (`project-window.project-settings`,
  `project-window.project-settings.done`,
  `project-settings.tabs.<edge.rawValue>`, via `accessibilityID`, a wrapper
  over `setAccessibilityIdentifier`) are automation hooks, not accessible
  names, and are invisible to VoiceOver. This file sets no accessibility
  identifier or label on either `SpacingControl` instance or on the topic
  list's sidebar; whatever name each exposes is `SpacingControl`'s and
  `ComposableSettings.SplitViewController`'s own responsibility, outside
  this file.
- **Announce state changes (e.g., loading, disabled)**: Not implemented in
  source. When a checkbox click is refused because it would disable the
  window's last enabled edge, this file changes the checkbox's `state` a
  second time within the same action handler
  (**reverts-checkbox-to-authoritative-state**), but no
  `NSAccessibility.post(element:notification:)` call, or any other explicit
  accessibility notification, accompanies that correction anywhere in
  source. A sighted user sees the checkbox spring back to checked; this
  file itself emits no notification of the reversal to VoiceOver, relying
  entirely on whatever announcement AppKit's own automatic accessibility
  observation of the state change produces, if any.
- **Minimum tap target**: Not applicable — this is a macOS, pointer/
  trackpad-driven composition of `NSButton`/`NSViewController` (no touch
  input path anywhere in this file); the 44×44pt minimum is iOS/touch
  guidance, not a macOS pointer-interface requirement. This file sets no
  `controlSize` on any button, so each keeps AppKit's regular system
  click-target metrics.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `isEdgeEnabled` | `(Edge) -> Bool` | — (required) | Read once per checkbox at panel construction, and again after every toggle, to decide each checkbox's displayed state. Ownership of the underlying storage is external to this file. |
| `setEdgeEnabled` | `(Edge, Bool) -> Void` | — (required) | Invoked with the toggled edge and the checkbox's clicked value whenever a Tabs checkbox's action fires. |
| `PaneSpacing.edgeSettings[.top/.leading/.bottom/.trailing]` | `UserSetting<Int>` | `0` | App-wide frame-spacing inset per side, bound live to the frame-spacing control; persisted keys `pane_spacing_top`/`pane_spacing_leading`/`pane_spacing_bottom`/`pane_spacing_trailing`. |
| `PaneSpacing.gutterSettings[.betweenColumns/.betweenRows]` | `UserSetting<Int>` | `1` | App-wide pane-divider gutter width, bound live to the divider-spacing control; persisted keys `pane_spacing_between_columns`/`pane_spacing_between_rows`. |

## Localization

Every user-facing string in this file is a hardcoded English literal with no
`NSLocalizedString` call or String Catalog lookup: the Done button's title
("Done"), the panel titles ("Tabs", "Spacing"), the sidebar title
("Project"), the group titles ("Tab Bars", "Frame Spacing", "Pane Divider
Spacing"), and every help-topic title and body paragraph in both panels'
`helpContent`. This file has no mechanism to supply a translated string for
any of them.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: no animation, transition, or `NSAnimationContext` call appears anywhere in this file; any sheet presentation/dismissal animation is owned by AppKit's own sheet-transition mechanism, outside this file. |
| Increase Contrast | Not applicable: this file sets no custom `NSColor` outside theme-role lookups (`.primaryText`, `.secondaryText`, `.elevatedSurface`, `.windowBackground`, `.divider`); those resolve through the active `SemanticPalette`, which is not overridden here. |
| Differentiate Without Color | Not applicable: each checkbox's on/off state is communicated through `NSButton`'s own check-mark glyph and track position, not through a color-only signal introduced by this file. |

## Privacy

- **Data collected**: None of its own. The component reads and writes local
  application settings only: per-edge tab-bar enablement (via the injected
  closures) and frame/divider spacing integers (via `PaneSpacing`'s
  `UserSetting<Int>` values).
- **Storage**: Frame and divider spacing persist through
  `PaneSpacing.edgeSettings`/`gutterSettings`, backed by `UserSetting<Int>`,
  whose default storage provider is `UserDefaultsSettingsStorageProvider`
  (`UserDefaults.standard`, per `SettingsStore`'s default parameter) — these
  values survive an app restart, live on the local Mac only (not
  iCloud-synced by default), and are shared across every project window, not
  scoped to one project. The storage for tab-bar edge-enabled state is NOT
  decided by this file: it is owned entirely by whatever backs the injected
  `isEdgeEnabled`/`setEdgeEnabled` closures. The Tabs panel's own help text
  states these edges "belong to this project... and are saved with the
  project," implying project-file persistence, but the write path itself is
  outside `ComposableTabsSettingsViewController.swift`.
- **Transmission**: Not applicable — no networking call appears anywhere in
  this file.
- **Retention**: Spacing settings are retained indefinitely in
  `UserDefaults` until explicitly changed again or the defaults domain is
  reset; this file codes no expiry or automatic clearing. Retention of
  edge-enabled state is likewise outside this file's control.

