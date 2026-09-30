<!-- leaf: implement-general-2/pane-spacing · source: pane-spacing.md -->

**Rules** (cite as `implement-general-2/pane-spacing#<slug>`):

- `edge-inset-default-zero` MUST
- `gutter-default-one-point` MUST
- `settings-not-secure` MUST
- `current-reads-live-value-per-field` MUST
- `current-populates-all-six-fields` MUST
- `content-insets-maps-fields-to-nsedgeinsets` MUST
- `minimum-divider-grab-fixed` MUST
- `divider-thickness-selects-axis-gutter` MUST
- `divider-paint-defers-when-hairline` MUST
- `divider-paint-fills-with-pane-backdrop` MUST
- `spacing-change-toggles-divider-style` MUST
- `spacing-change-marks-needs-display` MUST
- `spacing-shared-across-windows` MUST
- `setting-changes-persist-via-shared-store` MUST

# PaneSpacing

## Overview

`PaneSpacing` (`packages/apple/AgenticToolkit/macOS/UI/ViewControllers/ComposableTabs/PaneSpacing.swift`) is the single source of truth for how much room a project window keeps around and between its `ComposableTabs` panes: four edge insets between the pane area and the tab bars framing it, and two gutters — one for panes standing side by side, one for panes stacked. It stores those six numbers as `UserSettings`, reads them back on demand as a `Spacing` value, and converts them into the `NSEdgeInsets` AppKit wants. The same file also defines `PaneSplitView`, an `NSSplitView` subclass that reports its divider's thickness from the gutter settings and paints a divider wider than a hairline as the pane backdrop rather than a system seam.

Use this ingredient wherever an AppKit split-view-based pane layout needs consistent, user-configurable spacing that survives a relaunch and applies identically to every open window, rather than per-window or per-layout spacing values. Consumers that install `PaneSplitView`, apply `contentInsets` to window chrome, or expose a settings UI over these six values — `ComposableTabsViewController`, `ComposableTabsWindowController`, and `ComposableTabsSettingsViewController` — are documented in their own recipes and are out of this recipe's scope except where cited here for traceability.

## Behavioral Requirements

### Setting definitions

- **edge-inset-default-zero**: Each of the four edge settings (`paneSpacingTop`, `paneSpacingLeading`, `paneSpacingBottom`, `paneSpacingTrailing`) MUST default to `0` points until a value has been stored for it.
- **gutter-default-one-point**: Each of the two gutter settings (`paneSpacingBetweenColumns`, `paneSpacingBetweenRows`) MUST default to `1` point until a value has been stored for it.
- **settings-not-secure**: The six `pane_spacing_*` settings MUST be stored through the non-secure settings provider — none of the six passes `isSecure: true` to `UserSetting`'s initializer, so each defaults to `isSecure == false`.

### Aggregation

- **current-reads-live-value-per-field**: `PaneSpacing.current` MUST read each of the six settings' `value` at the moment `current` is accessed; `value` (defined on `StorableSetting`, which `UserSetting` conforms to) reads through `UserSettings.shared.get(_:)` on every access rather than returning a value cached on `PaneSpacing` itself.
- **current-populates-all-six-fields**: `PaneSpacing.current` MUST return a `Spacing` whose `top`, `leading`, `bottom`, `trailing`, `betweenColumns`, and `betweenRows` each equal the corresponding setting's current value.
- **content-insets-maps-fields-to-nsedgeinsets**: `PaneSpacing.contentInsets` MUST return an `NSEdgeInsets` whose `top`, `left`, `bottom`, and `right` equal `current.top`, `current.leading`, `current.bottom`, and `current.trailing` respectively, each converted from the underlying `Int` setting value to the `CGFloat` `NSEdgeInsets` requires.
- **minimum-divider-grab-fixed**: `PaneSpacing.minimumDividerGrab` MUST equal `6` points regardless of the current values of `betweenColumns` or `betweenRows`.

### Divider thickness and paint

- **divider-thickness-selects-axis-gutter**: `PaneSplitView.dividerThickness` MUST return `PaneSpacing.current.betweenColumns` when the split view's `isVertical` is `true` (panes standing side by side), and `PaneSpacing.current.betweenRows` when `isVertical` is `false` (panes stacked), converting the underlying `Int` gutter setting to the `CGFloat` `dividerThickness` requires.
- **divider-paint-defers-when-hairline**: `PaneSplitView.drawDivider(in:)` MUST call `super.drawDivider(in:)` and MUST NOT fill the divider rect itself when `dividerThickness` is `1` point or less.
- **divider-paint-fills-with-pane-backdrop**: `PaneSplitView.drawDivider(in:)` MUST fill the entire divider rect with `NSColor(currentPalette.projectPaneBackdrop)` when `dividerThickness` is greater than `1` point, and MUST NOT call `super.drawDivider(in:)` in that case.

### Spacing-change refresh

- **spacing-change-toggles-divider-style**: `PaneSplitView.spacingDidChange()` MUST set `dividerStyle` to a value other than its current one and then set it back to its original value, in that order.
- **spacing-change-marks-needs-display**: `PaneSplitView.spacingDidChange()` MUST set `needsDisplay` to `true`.

### Scope

- **spacing-shared-across-windows**: `PaneSpacing.current`, `edgeSettings`, and `gutterSettings` MUST be process-wide (`static`), not held per window, per project, or per pane instance, so every `PaneSplitView` and every reader of `contentInsets` observes the same six values.
- **setting-changes-persist-via-shared-store**: Assigning a new value to any of the six settings' `.value` MUST write through `UserSettings.shared` (`StorableSetting.value`'s setter calls `UserSettings.shared.set(_:for:)`), persisting to whatever `SettingsStorageProvider` backs it rather than to an in-memory cache local to the setting object.

## Appearance

- **Corner radius**: Not applicable — this source draws a rectangular divider fill and defines no corner radius anywhere.
- **Padding**: Not a single vertical × horizontal pair. Four independent edge insets — `top`, `leading`, `bottom`, `trailing` — each an `Int` in points, default `0`, individually configurable, and converted together into an `NSEdgeInsets` by `contentInsets`.
- **Font**: Not applicable — this source renders no text.
- **Background**: `PaneSplitView.drawDivider(in:)` fills the divider with `NSColor(currentPalette.projectPaneBackdrop)` whenever `dividerThickness` is greater than `1` point, so a wide gutter reads as the same backdrop plane as the frame spacing rather than a colored bar. At `1` point or less, the divider falls back to AppKit's own `.thin`-style paint, whose color is `ThemedSplitView.dividerColor` (`currentPalette.nsColor(.divider)`) — inherited behavior, out of this file's scope.
- **Foreground/Text**: Not applicable — this source renders no text.
- **Border**: Not applicable — `PaneSplitView` paints a divider fill, not a stroked border, and this source defines no border of its own.
- **Shadow**: Not applicable — no `NSShadow` or layer shadow appears anywhere in this source.
- **Min/Max size**: `minimumDividerGrab` (`6pt`) is a minimum *interactive* width guarantee used by consumers to widen a divider's hit-test rect (see `ComposableTabsViewController`'s `widen-divider-grab-area`, out of this recipe's scope) — it does not change what `dividerThickness` draws. Per platform-design-languages, macOS's HIG has no published minimum divider/gutter width, so this file's own drawn thickness has no declared minimum or maximum; any clamping of a user-entered value happens in the settings-control layer, not here.

## Accessibility

- **Role/trait**: Not applicable at this level — `PaneSpacing` is configuration state, not a view. `PaneSplitView` overrides no accessibility API and inherits whatever role/trait `NSSplitView` exposes by default.
- **Label requirements**: Not applicable — this source assigns no accessibility label or identifier to anything; a pane's own accessible content and identifier are a different component's concern (see `composable-tabs-pane-view-controller`).
- **Announce state changes**: Not applicable — `spacingDidChange()` only redraws the divider (`dividerStyle`, `needsDisplay = true`) after the user changes a spacing setting themselves; the change is purely visual, carries no information a VoiceOver user needs, and the user who made it already knows it happened.
- **Minimum interactive target**: Dragging a divider is mouse-driven on macOS; this platform has no touch-target concept analogous to iOS's 44×44pt minimum. `minimumDividerGrab` (`6pt`) is this file's own minimum draggable width, applied by consumers widening the hit-test rect (out of this recipe's scope; not applicable here as a marker, consistent with `composable-tabs-view-controller`'s own treatment of touch-target-size for the same divider).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `pane_spacing_top` | Int (points) | `0` | Inset between the pane area's top edge and the tab bar framing it. |
| `pane_spacing_leading` | Int (points) | `0` | Inset between the pane area's leading edge and the tab bar framing it. |
| `pane_spacing_bottom` | Int (points) | `0` | Inset between the pane area's bottom edge and the tab bar framing it. |
| `pane_spacing_trailing` | Int (points) | `0` | Inset between the pane area's trailing edge and the tab bar framing it. |
| `pane_spacing_between_columns` | Int (points) | `1` | Whole gap between two panes standing side by side (not each pane's half). |
| `pane_spacing_between_rows` | Int (points) | `1` | Whole gap between two panes stacked one above the other. |

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable — `spacingDidChange()` and `drawDivider(in:)` apply and paint immediately; this source defines no animation, transition, or `animator()` call for a Reduce Motion substitute to replace. |
| Increase Contrast | Inherited, not a choice made in this file — `drawDivider(in:)` always paints from `currentPalette.projectPaneBackdrop`; any Increase Contrast adaptation happens wherever `SemanticPalette` resolves that token, outside this recipe's scope. |
| Differentiate Without Color | Not applicable — the signal a wide gutter carries is its drawn width (`dividerThickness`), not color alone; the backdrop fill matches the surrounding plane rather than encoding information only through color. |

## Privacy

- **Data collected**: The six `pane_spacing_*` integers only — window-chrome layout preferences, not personal or sensitive data.
- **Storage**: Local only, via `UserSetting`/`UserSettings.shared`. None of the six settings sets `isSecure: true`, so each routes to `SettingsStore`'s non-secure `settingsProvider`, which defaults to `UserDefaultsSettingsStorageProvider` (`UserDefaults`) unless the host app configures `UserSettings.shared` with a different provider — a choice made outside this file.
- **Transmission**: None. No network call appears anywhere in this file.
- **Retention**: Persists until explicitly changed or removed (`StorableSetting.remove()`); this file defines no expiration or automatic cleanup.

