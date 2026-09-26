---
id: 4c528e38-b70a-4ed3-bedc-9009292ad908
title: PaneSpacing
domain: agentictoolkit://cookbook/macos/ui/view-controllers/composable-tabs/pane-spacing
type: ingredient
version: 1.1.1
status: review
language: en
created: '2026-09-23'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: App-wide, user-configurable spacing around and between ComposableTabs panes,
  and the split view that paints and redraws it.
platforms:
- swift
- macos
tags:
- composable-tabs
- spacing
- split-view
- settings
- appkit
depends-on: []
related:
- agentictoolkit://cookbook/macos/ui/view-controllers/composable-tabs/composable-tabs-view-controller
- agentictoolkit://cookbook/macos/ui/view-controllers/composable-tabs/composable-tabs-pane-view-controller
- agentictoolkit://cookbook/macos/ui/view-controllers/composable-tabs/composable-tabs-settings-view-controller
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
references: []
approved-by: ''
approved-date: ''
---

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

## States

| State | Appearance change |
|-------|------------------|
| Default — hairline gutter (`dividerThickness` ≤ 1pt) | AppKit's own `.thin`-style divider paint via `super.drawDivider(in:)`. |
| Default — wide gutter (`dividerThickness` > 1pt) | Divider rect filled with `currentPalette.projectPaneBackdrop`. |
| Pressed | Not applicable: dragging a divider is `NSSplitView`'s own built-in behavior; this file paints no pressed/highlighted state of its own. |
| Disabled | Not applicable: neither `PaneSpacing` nor `PaneSplitView` expose a disabled state; a `0`-point gutter is a valid, still-draggable style choice (see `minimumDividerGrab`), not a disabled divider. |
| Focused | Not applicable: no focus ring or focus-driven appearance change appears in this source. |
| Loading | Not applicable: all six settings are read synchronously from local storage; this source has no async operation and no loading state. |

## Accessibility

- **Role/trait**: Not applicable at this level — `PaneSpacing` is configuration state, not a view. `PaneSplitView` overrides no accessibility API and inherits whatever role/trait `NSSplitView` exposes by default.
- **Label requirements**: Not applicable — this source assigns no accessibility label or identifier to anything; a pane's own accessible content and identifier are a different component's concern (see `composable-tabs-pane-view-controller`).
- **Announce state changes**: Not applicable — `spacingDidChange()` only redraws the divider (`dividerStyle`, `needsDisplay = true`) after the user changes a spacing setting themselves; the change is purely visual, carries no information a VoiceOver user needs, and the user who made it already knows it happened.
- **Minimum interactive target**: Dragging a divider is mouse-driven on macOS; this platform has no touch-target concept analogous to iOS's 44×44pt minimum. `minimumDividerGrab` (`6pt`) is this file's own minimum draggable width, applied by consumers widening the hit-test rect (out of this recipe's scope; not applicable here as a marker, consistent with `composable-tabs-view-controller`'s own treatment of touch-target-size for the same divider).

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| pane-spacing-001 | edge-inset-default-zero | Fresh store, no `pane_spacing_top` value ever set | `UserSettings.paneSpacingTop.value == 0` |
| pane-spacing-002 | gutter-default-one-point | Fresh store, no `pane_spacing_between_columns` value ever set | `UserSettings.paneSpacingBetweenColumns.value == 1` |
| pane-spacing-003 | settings-not-secure | Inspect `isSecure` on each of the six `UserSettings.paneSpacing*` settings | Every one reports `isSecure == false` |
| pane-spacing-004 | current-reads-live-value-per-field | Set `UserSettings.paneSpacingLeading.value = 12`, then read `PaneSpacing.current` | `PaneSpacing.current.leading == 12` |
| pane-spacing-005 | current-populates-all-six-fields | Set all six settings to distinct nonzero values, then read `PaneSpacing.current` | `top`, `leading`, `bottom`, `trailing`, `betweenColumns`, and `betweenRows` each equal the value set for that field |
| pane-spacing-006 | content-insets-maps-fields-to-nsedgeinsets | Set edges to `top: 1, leading: 2, bottom: 3, trailing: 4` | `PaneSpacing.contentInsets == NSEdgeInsets(top: 1, left: 2, bottom: 3, right: 4)` |
| pane-spacing-007 | minimum-divider-grab-fixed | Set `betweenColumns` to `0`, then to `50` | `PaneSpacing.minimumDividerGrab == 6` in both cases |
| pane-spacing-008 | divider-thickness-selects-axis-gutter | `PaneSplitView.isVertical = true`, `betweenColumns = 8` | `dividerThickness == 8` |
| pane-spacing-009 | divider-thickness-selects-axis-gutter | `PaneSplitView.isVertical = false`, `betweenRows = 2` | `dividerThickness == 2` |
| pane-spacing-010 | divider-paint-defers-when-hairline | Gutter at its `1`pt default; a test subclass overrides `drawDivider(in:)` to record whether its `super` implementation ran, then calls `drawDivider(in:)` | The recorded `super.drawDivider(in:)` call happened, and sampling a pixel inside the divider rect after the call does not show `currentPalette.projectPaneBackdrop` |
| pane-spacing-011 | divider-paint-fills-with-pane-backdrop | `isVertical = true`, `betweenColumns = 10`; a test subclass overrides `drawDivider(in:)` to record whether its `super` implementation ran, then calls `drawDivider(in:)` and renders into a bitmap context | The recorded `super.drawDivider(in:)` call did not happen, and sampling pixels across the full divider rect in the rendered bitmap shows `NSColor(currentPalette.projectPaneBackdrop)` |
| pane-spacing-012 | spacing-change-toggles-divider-style | `dividerStyle == .thin`; a test subclass or KVO observer records every value assigned to `dividerStyle`, then calls `spacingDidChange()` | The recorded assignments show `dividerStyle` set to a value other than `.thin` and then back to `.thin`, in that order (any other-than-original intermediate value satisfies the requirement, not only `.paneSplitter`); alternatively, an `NSSplitViewController` observably re-reads `dividerThickness` after the call |
| pane-spacing-013 | spacing-change-marks-needs-display | `needsDisplay == false`, call `spacingDidChange()` | `needsDisplay == true` |
| pane-spacing-014 | spacing-shared-across-windows | Two `PaneSplitView` instances, each vertical, in two different windows; change `UserSettings.paneSpacingBetweenColumns.value` once | Both instances' `dividerThickness` reflect the new value |
| pane-spacing-015 | setting-changes-persist-via-shared-store | Set `UserSettings.paneSpacingTop.value = 5`, then read `UserSettings.shared.get(UserSettings.paneSpacingTop)` directly | Returns `5`, showing the write reached the shared store rather than only the setting object's cached `currentValue` |

## Edge Cases

- **Null/empty input**: Not applicable — `UserSetting<Int>`'s `default` guarantees a concrete `Int` is always returned even when nothing has been stored yet (see `edge-inset-default-zero`/`gutter-default-one-point`); there is no nil or missing-value case for any of the six settings.
- **Boundary values — zero-point gutter**: A `0`-point gutter is a legitimate, source-supported look. It is drawn via the `dividerThickness <= 1` branch (AppKit's own hairline paint) and stays draggable only because consumers widen the hit-test rect to `minimumDividerGrab`; this file itself does no widening.
- **Boundary values — exactly `1` point**: `drawDivider(in:)`'s own guard (`dividerThickness > 1`) treats `1` as the hairline case, not the filled case — the boundary is inclusive of `1` on the hairline side.
- **Boundary values — negative or unusually large stored settings**: `UserSetting<Int>` and `PaneSpacing.current` accept and pass through any stored `Int` — including a negative value or one set outside whatever range a settings UI would offer (for example via a direct write to the underlying store) — with no clamping or validation anywhere in this file before it reaches `NSEdgeInsets` or `dividerThickness`. This is by design (see Design Decisions: clamping ownership): `PaneSpacing` is a thin passthrough over `UserSetting<Int>`, and range validation on interactively-entered values is the settings-control layer's job, done through `Spacing.setting(_:to:in:)`/`Spacing.adjusting(_:by:in:)` and `Int.clamped(to:)` — mechanisms this file's `current` never calls.
- **Concurrent access**: Not applicable — `PaneSpacing`, `PaneSplitView`, and `UserSetting` are all `@MainActor`-isolated; every read and write of the six settings in this source is confined to the main actor.
- **Error states**: Not applicable — `UserSettings.shared.get`/`set` (reached through `StorableSetting.value`) return and accept concrete, non-optional, non-throwing values; this file exposes no failure path to handle.
- **Offline/disconnected state**: Not applicable — this component performs only local, synchronous settings storage; it makes no network call and has no dependency on connectivity.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `pane_spacing_top` | Int (points) | `0` | Inset between the pane area's top edge and the tab bar framing it. |
| `pane_spacing_leading` | Int (points) | `0` | Inset between the pane area's leading edge and the tab bar framing it. |
| `pane_spacing_bottom` | Int (points) | `0` | Inset between the pane area's bottom edge and the tab bar framing it. |
| `pane_spacing_trailing` | Int (points) | `0` | Inset between the pane area's trailing edge and the tab bar framing it. |
| `pane_spacing_between_columns` | Int (points) | `1` | Whole gap between two panes standing side by side (not each pane's half). |
| `pane_spacing_between_rows` | Int (points) | `1` | Whole gap between two panes stacked one above the other. |

## Deep Linking

Not applicable: `PaneSpacing` is process-internal layout configuration with no screen, route, or URL of its own. No URL scheme, universal link, or `NSUserActivity` handling appears anywhere in this file.

## Localization

Not applicable: this source defines no user-facing string. The six setting keys (`pane_spacing_top`, `pane_spacing_leading`, `pane_spacing_bottom`, `pane_spacing_trailing`, `pane_spacing_between_columns`, `pane_spacing_between_rows`) are internal storage identifiers, not display text, and no `Text`, `Label`, or `stringValue`/`title` literal appears in this file.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable — `spacingDidChange()` and `drawDivider(in:)` apply and paint immediately; this source defines no animation, transition, or `animator()` call for a Reduce Motion substitute to replace. |
| Increase Contrast | Inherited, not a choice made in this file — `drawDivider(in:)` always paints from `currentPalette.projectPaneBackdrop`; any Increase Contrast adaptation happens wherever `SemanticPalette` resolves that token, outside this recipe's scope. |
| Differentiate Without Color | Not applicable — the signal a wide gutter carries is its drawn width (`dividerThickness`), not color alone; the backdrop fill matches the surrounding plane rather than encoding information only through color. |

## Feature Flags

Not applicable: no feature-flag or remote-config lookup of any kind appears in this file.

## Analytics

Not applicable: no analytics event is emitted anywhere in this file.

## Privacy

- **Data collected**: The six `pane_spacing_*` integers only — window-chrome layout preferences, not personal or sensitive data.
- **Storage**: Local only, via `UserSetting`/`UserSettings.shared`. None of the six settings sets `isSecure: true`, so each routes to `SettingsStore`'s non-secure `settingsProvider`, which defaults to `UserDefaultsSettingsStorageProvider` (`UserDefaults`) unless the host app configures `UserSettings.shared` with a different provider — a choice made outside this file.
- **Transmission**: None. No network call appears anywhere in this file.
- **Retention**: Persists until explicitly changed or removed (`StorableSetting.remove()`); this file defines no expiration or automatic cleanup.

## Logging

Not applicable: no logging call (`Logger`, `os_log`, or otherwise) appears anywhere in this file.

## Platform Notes

- **SwiftUI**: There is no SwiftUI type here to translate directly — `PaneSpacing` is a plain `enum` of settings and `PaneSplitView` is an `NSSplitView` subclass. A SwiftUI-first rebuild would keep the six values behind `@AppStorage`-backed (or `ObservableObject`-wrapped) properties mirroring `UserSetting`'s `@Published currentValue`, apply the four edges with `.padding(EdgeInsets(top:leading:bottom:trailing:))`, and replace the gutter with a custom draggable divider view sized from `betweenColumns`/`betweenRows` and filled from the same semantic backdrop color, since SwiftUI's own `HSplitView`/`VSplitView` divider is not restylable the way overriding `drawDivider(in:)` allows.
- **Compose**: Model the four insets as `Modifier.padding(start = , top = , end = , bottom = )` on the pane container, and each gutter as a `Spacer`-sized `Box`/`Canvas` element between panes in a `Row`/`Column`, colored from the `MaterialTheme` surface-variant token that plays the role `projectPaneBackdrop` plays here. Persist the six values with `DataStore`/`SharedPreferences` and observe changes via a `Flow`, mirroring `UserSetting`'s Combine `@Published` publisher.
- **React/Web**: Represent the four insets as CSS custom properties (`--pane-spacing-top`, etc.) applied as padding on the pane container, and each gutter as a resizable divider element (`cursor: col-resize` / `row-resize`) whose background is the app's panel-backdrop CSS variable rather than a hardcoded color — reproducing the "backdrop, not a stripe" choice `drawDivider(in:)` makes. Give the divider element a `min-width`/`min-height` matching `minimumDividerGrab` so a zero-width gutter stays draggable, and persist the six values to `localStorage`, observed with a `storage` event listener for cross-tab updates.
- **AppKit / UIKit**: This is the source. `PaneSpacing.swift` defines the enum, the `UserSettings` extension, and `PaneSplitView : ThemedSplitView : NSSplitView`; specific to AppKit here are `NSEdgeInsets`, the `dividerThickness`/`drawDivider(in:)` overrides, and using `NSSplitView.DividerStyle`'s stock `.thin`/`.paneSplitter` cases purely as a nudge — reassigning `dividerStyle` off and back is what makes AppKit discard the constraint constants an `NSSplitViewController` built from the old `dividerThickness`. UIKit has no direct analog to this per-pixel divider-drawing hook; `UISplitViewController`'s separator styling would be the nearest translation target, relevant only if this component is ever asked to run on iOS (`platforms` here lists macOS only).
- **WinUI 3**: Represent the four insets as `Margin`/`Padding` on the content `Border`, and each gutter as a `GridSplitter` (from `CommunityToolkit.WinUI.Controls` — the Windows Community Toolkit's Sizers package, not `Microsoft.UI.Xaml.Controls`; the app takes a package dependency on the toolkit to get it) sitting in its own zero-content `ColumnDefinition`/`RowDefinition` between panes — `GridSplitter.Width`/`Height` plays the role `betweenColumns`/`betweenRows` play here. `GridSplitter.Background` swaps between the theme's default thin divider brush and an explicit pane-backdrop `ThemeResource` brush depending on whether the configured width is `<= 1` or greater, reproducing the hairline-vs-fill choice in `drawDivider(in:)`. Unlike AppKit's constraint-cached `NSSplitViewController`, WinUI's `Grid` recomputes column/row sizes as soon as a `ColumnDefinition.Width`/`RowDefinition.Height` changes, so no `spacingDidChange()`-style "toggle a style off and back" nudge is needed — binding the `GridSplitter`'s governing `GridLength` to the setting is enough. Persist the six values with `ApplicationDataContainer.LocalSettings`, the closest analog to `UserDefaultsSettingsStorageProvider`. `GridSplitter`'s built-in `Thumb` already exposes a wider drag/hover hit area than its visual thickness, which is the WinUI equivalent of `minimumDividerGrab`.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/ComposableTabs/PaneSpacing.swift` |

## Design Decisions

**Decision**: `PaneSplitView.dividerThickness` reads `PaneSpacing.current` — a fresh settings-store read — on every call rather than caching the gutter value on the instance.
**Rationale**: `dividerThickness` is a computed property with no invalidation hook of its own, and `spacingDidChange()`'s entire purpose is to force AppKit to re-ask this property after a setting changes; a cached value would go stale the moment either gutter setting changed and defeat that mechanism.
**Approved**: pending

**Decision**: `spacingDidChange()` forces a relayout by toggling `dividerStyle` to a different value and back, rather than calling an invalidation method such as `needsLayout`.
**Rationale**: the source comment explains that an `NSSplitViewController` lays its panes out with constraints built from `dividerThickness` at the moment items were installed, and only re-assigning `dividerStyle` is documented to make AppKit discard and re-ask for those constants.
**Approved**: pending

**Decision**: the two gutter settings default to `1` point (a hairline) while the four edge insets default to `0`.
**Rationale**: the source comment states this preserves the pre-existing hairline divider appearance so introducing the setting does not visibly re-space any window on the update that adds it, while frame insets start at `0` because the gap around panes is an opt-in look, not the prior house style.
**Approved**: pending

**Decision**: spacing is a single app-wide set of settings, not a per-window or per-project value.
**Rationale**: the source comment states that a window whose panes are spaced differently from the window beside it reads as a bug, and per-window spacing would have to be carried in every saved layout to survive a relaunch.
**Approved**: pending

**Decision**: `minimumDividerGrab` is a fixed `6` points regardless of the configured gutter thickness, including when the gutter is `0`.
**Rationale**: the source comment states a zero-point gutter is a legitimate look, and without a wider hit-test allowance it would be a layout the user cannot undo with the mouse; the value `6` itself is not derived from a cited platform minimum.
**Approved**: pending

**Decision**: `PaneSpacing` does not clamp or validate any of the six stored settings; range validation on a negative or implausibly large value is the settings-control layer's responsibility, not `PaneSpacing.current`'s.
**Rationale**: `PaneSpacing.current` builds its `Spacing` by assigning each setting's raw `value` straight into the edge/gutter subscript, never through `Spacing.setting(_:to:in:)` or `Spacing.adjusting(_:by:in:)` — the two methods that actually call `Int.clamped(to:)`. Those methods exist for, and are used by, the settings-control layer that presents the editable control; `PaneSpacing` itself is a thin passthrough with no comparable seam, so clamping lives where the value is entered, not where it is read back.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [data-minimization](agenticdevelopercookbook://compliance/privacy-and-data#data-minimization) | passed | Privacy and Data |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | Accessibility |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | partial | Accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | Accessibility |

Data-minimization passes because the six `pane_spacing_*` settings are window-chrome layout integers only — not personal or sensitive data, and nothing beyond what the layout needs is collected. Screen-reader-support and keyboard-navigable are partial because `PaneSplitView` overrides no accessibility or key-handling API for its divider and inherits whatever `NSSplitView` provides by default; the source cannot say whether that inherited behavior meets either check. Contrast-ratio is partial for the same reason: the divider fill always resolves through `currentPalette.projectPaneBackdrop`, a theme token, but the token's actual rendered color — and so its contrast against neighboring panes — is decided by `SemanticPalette`, outside this file. Touch-target-size and string-externalization are not listed: dragging a divider is mouse-driven on macOS, which has no touch-target concept, and this file defines no user-facing string for string-externalization to check.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial extraction from `PaneSpacing.swift`. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: add a Design Decision assigning clamping to the settings-control layer and resolve the negative/oversized-input edge case against it; drop the stale "flagged as an open question under Accessibility" claim; move the platform-design-languages reference from `references` to `related` and add the three sibling ComposableTabs recipes to `related`; drop the redundant `macos` tag; reformat Design Decisions into the bold three-line form; correct the WinUI 3 GridSplitter namespace; make three test vectors observable with a recording subclass/bitmap sampling instead of an unobservable claim; remove an unsupported "re-applies insets" claim from Accessibility; note the `Int`→`CGFloat` conversion in two requirements; and rebuild Compliance around checks that exist in the catalog. |
| 1.1.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
