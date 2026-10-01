---
id: 4c528e38-b70a-4ed3-bedc-9009292ad908
title: Pane Spacing
domain: agentictoolkit://cookbook/ui/layout/composable-tabs/pane-spacing
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: App-wide, user-configurable spacing around and between composable-tabs panes,
  and the pane divider that paints and redraws to reflect it.
platforms:
- swift
- macos
tags:
- composable-tabs
- spacing
- split-view
- settings
depends-on: []
related:
- agentictoolkit://cookbook/ui/layout/composable-tabs
- agentictoolkit://cookbook/ui/layout/composable-tabs/leaf-pane-view
- agentictoolkit://cookbook/ui/layout/composable-tabs/settings-view
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
references: []
approved-by: ''
approved-date: ''
---

# Pane Spacing

## Overview

Pane Spacing is the single source of truth for how much room a project window keeps around and between its composable-tabs panes: four edge insets between the pane area and the tab bars framing it, and two gutters — one for panes standing side by side, one for panes stacked. It stores those six numbers as app settings, reads them back on demand as a spacing value, and converts them into the content-inset structure the window's chrome applies. The same concept covers the pane split view: a divider that reports its own thickness from the gutter settings and paints a divider wider than a hairline as the pane backdrop rather than a system seam.

Use this ingredient wherever a split-view-based pane layout needs consistent, user-configurable spacing that survives a relaunch and applies identically to every open window, rather than per-window or per-layout spacing values. Consumers that install the pane split view, apply content insets to window chrome, or expose a settings UI over these six values — the composable-tabs view, its window, and its settings view — are documented in their own recipes and are out of this recipe's scope except where cited here for traceability.

## Behavioral Requirements

### Setting definitions

- **edge-inset-default-zero**: Each of the four edge settings (`pane_spacing_top`, `pane_spacing_leading`, `pane_spacing_bottom`, `pane_spacing_trailing`) MUST default to `0` points until a value has been stored for it.
- **gutter-default-one-point**: Each of the two gutter settings (`pane_spacing_between_columns`, `pane_spacing_between_rows`) MUST default to `1` point until a value has been stored for it.
- **settings-not-secure**: The six `pane_spacing_*` settings MUST be stored as non-secure settings, never through a secure/sensitive-data storage path.

### Aggregation

- **current-reads-live-value-per-field**: Reading the current spacing value MUST read each of the six settings' live value at the moment it is accessed, rather than returning a value cached elsewhere.
- **current-populates-all-six-fields**: Reading the current spacing value MUST return a spacing structure whose `top`, `leading`, `bottom`, `trailing`, `betweenColumns`, and `betweenRows` each equal the corresponding setting's current value.
- **content-insets-maps-fields-to-edge-insets**: Converting the current spacing value into content insets MUST return a structure whose `top`, `left`, `bottom`, and `right` equal `current.top`, `current.leading`, `current.bottom`, and `current.trailing` respectively.
- **minimum-divider-grab-fixed**: The minimum interactive width guaranteed for a divider's hit-test region MUST equal `6` points regardless of the current values of `betweenColumns` or `betweenRows`.

### Divider thickness and paint

- **divider-thickness-selects-axis-gutter**: The pane split view's divider thickness MUST equal the current spacing value's `betweenColumns` when panes are arranged side by side (a vertical split), and `betweenRows` when panes are stacked (a horizontal split).
- **divider-paint-defers-when-hairline**: Painting the divider MUST defer to the platform's own default divider rendering, and MUST NOT fill the divider area itself, when the divider thickness is `1` point or less.
- **divider-paint-fills-with-pane-backdrop**: Painting the divider MUST fill the entire divider area with the active theme's pane-backdrop color when the divider thickness is greater than `1` point, and MUST NOT defer to the platform's default divider rendering in that case.

### Spacing-change refresh

- **spacing-change-toggles-divider-style**: Notifying the split view that spacing changed MUST set its divider style to a value other than its current one and then set it back to its original value, in that order, forcing the split view to recompute its divider layout from the new thickness.
- **spacing-change-requests-redraw**: Notifying the split view that spacing changed MUST mark the divider for redraw.

### Scope

- **spacing-shared-across-windows**: The spacing values and their underlying settings MUST be process-wide, not held per window, per project, or per pane instance, so every pane split view and every reader of the content insets observes the same six values.
- **setting-changes-persist-via-shared-store**: Assigning a new value to any of the six settings MUST write through the shared settings store, persisting to whatever storage provider backs it rather than to an in-memory cache local to the setting object.

## Appearance

- **Corner radius**: Not applicable — this component draws a rectangular divider fill and defines no corner radius anywhere.
- **Padding**: Not a single vertical × horizontal pair. Four independent edge insets — `top`, `leading`, `bottom`, `trailing` — each an integer in points, default `0`, individually configurable, and converted together into the content-inset structure applied to the window's pane chrome.
- **Font**: Not applicable — this component renders no text.
- **Background**: Painting the divider fills it with the active theme's pane-backdrop color whenever the divider thickness is greater than `1` point, so a wide gutter reads as the same backdrop plane as the frame spacing rather than a colored bar. At `1` point or less, the divider falls back to the platform's own default hairline-divider paint, whose color is the theme's divider role — inherited behavior, out of this component's scope.
- **Foreground/Text**: Not applicable — this component renders no text.
- **Border**: Not applicable — the pane split view paints a divider fill, not a stroked border, and this component defines no border of its own.
- **Shadow**: Not applicable — no shadow appears anywhere in this component.
- **Min/Max size**: `minimumDividerGrab` (`6pt`) is a minimum *interactive* width guarantee used by consumers to widen a divider's hit-test region (see the composable-tabs pane view's own divider-grab widening, out of this recipe's scope) — it does not change what the divider thickness draws. This component's own drawn thickness has no declared minimum or maximum; any clamping of a user-entered value happens in the settings-control layer, not here. (Platform-specific guidance on published minimum divider/gutter widths is in Platform Notes.)

## States

| State | Appearance change |
|-------|------------------|
| Default — hairline gutter (divider thickness ≤ 1pt) | The platform's own default hairline divider paint. |
| Default — wide gutter (divider thickness > 1pt) | Divider area filled with the theme's pane-backdrop color. |
| Pressed | Not applicable: dragging a divider is the platform's own built-in split-view behavior; this component paints no pressed/highlighted state of its own. |
| Disabled | Not applicable: neither the pane spacing settings nor the split view expose a disabled state; a `0`-point gutter is a valid, still-draggable style choice (see minimum-divider-grab-fixed), not a disabled divider. |
| Focused | Not applicable: no focus ring or focus-driven appearance change appears in this component. |
| Loading | Not applicable: all six settings are read synchronously from local storage; this component has no async operation and no loading state. |

## Accessibility

- **Role/trait**: Not applicable at this level — the pane spacing values are configuration state, not a view. The split view overrides no accessibility API and inherits whatever role/trait the platform's own split view exposes by default.
- **Label requirements**: Not applicable — this component assigns no accessibility label or identifier to anything; a pane's own accessible content and identifier are a different component's concern (see the composable-tabs pane view).
- **Announce state changes**: Not applicable — notifying of a spacing change only redraws the divider after the user changes a spacing setting themselves; the change is purely visual, carries no information a screen-reader user needs, and the user who made it already knows it happened.
- **Minimum interactive target**: Dragging a divider is a pointer-driven interaction here; this component has no touch-target concept analogous to the minimum used on touch-driven platforms. The minimum divider grab width (`6pt`) is this component's own minimum draggable width, applied by consumers widening the hit-test region (out of this recipe's scope; not applicable here as a marker, consistent with the composable-tabs pane view's own treatment of touch-target size for the same divider).

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| pane-spacing-001 | edge-inset-default-zero | Fresh store, no `pane_spacing_top` value ever set | The top edge inset setting reads `0` |
| pane-spacing-002 | gutter-default-one-point | Fresh store, no `pane_spacing_between_columns` value ever set | The between-columns gutter setting reads `1` |
| pane-spacing-003 | settings-not-secure | Inspect whether each of the six spacing settings is marked secure/sensitive storage | Every one reports as non-secure |
| pane-spacing-004 | current-reads-live-value-per-field | Set the leading edge inset setting to `12`, then read the current spacing value | The current spacing value's `leading` equals `12` |
| pane-spacing-005 | current-populates-all-six-fields | Set all six settings to distinct nonzero values, then read the current spacing value | `top`, `leading`, `bottom`, `trailing`, `betweenColumns`, and `betweenRows` each equal the value set for that field |
| pane-spacing-006 | content-insets-maps-fields-to-edge-insets | Set edges to `top: 1, leading: 2, bottom: 3, trailing: 4` | The computed content insets equal `top: 1, left: 2, bottom: 3, right: 4` |
| pane-spacing-007 | minimum-divider-grab-fixed | Set `betweenColumns` to `0`, then to `50` | The minimum divider grab width equals `6` in both cases |
| pane-spacing-008 | divider-thickness-selects-axis-gutter | The split view is arranged with panes side by side (vertical split), `betweenColumns = 8` | The divider thickness equals `8` |
| pane-spacing-009 | divider-thickness-selects-axis-gutter | The split view is arranged with panes stacked (horizontal split), `betweenRows = 2` | The divider thickness equals `2` |
| pane-spacing-010 | divider-paint-defers-when-hairline | Gutter at its `1`pt default; observe whether the platform's own default divider painting ran when the divider is painted | The platform's own default divider painting ran, and sampling a pixel inside the divider area afterward does not show the theme's pane-backdrop color |
| pane-spacing-011 | divider-paint-fills-with-pane-backdrop | Vertical split, `betweenColumns = 10`; observe whether the platform's own default divider painting ran, then render the divider into a bitmap | The platform's own default divider painting did not run, and sampling pixels across the full divider area in the rendered bitmap shows the theme's pane-backdrop color |
| pane-spacing-012 | spacing-change-toggles-divider-style | The divider style is at its default; observe every value assigned to the divider style, then notify that spacing changed | The recorded assignments show the divider style set to a value other than its original one and then back to the original, in that order (any other-than-original intermediate value satisfies the requirement); alternatively, the hosting split-view controller observably re-reads the divider thickness after the call |
| pane-spacing-013 | spacing-change-requests-redraw | The view is not currently marked for redraw; notify that spacing changed | The view becomes marked for redraw |
| pane-spacing-014 | spacing-shared-across-windows | Two split-view instances, each arranged with panes side by side, in two different windows; change the between-columns gutter setting once | Both instances' divider thickness reflect the new value |
| pane-spacing-015 | setting-changes-persist-via-shared-store | Set the top edge inset setting to `5`, then read it back directly from the shared settings store | Returns `5`, showing the write reached the shared store rather than only a local cached value |

## Edge Cases

- **Null/empty input**: Not applicable — each setting's own default guarantees a concrete value is always returned even when nothing has been stored yet (see edge-inset-default-zero/gutter-default-one-point); there is no nil or missing-value case for any of the six settings.
- **Boundary values — zero-point gutter**: A `0`-point gutter is a legitimate, source-supported look. It is drawn via the hairline-or-less branch (the platform's own hairline paint) and stays draggable only because consumers widen the hit-test region to the minimum divider grab width; this component itself does no widening.
- **Boundary values — exactly `1` point**: Painting the divider treats `1` as the hairline case, not the filled case — the boundary is inclusive of `1` on the hairline side.
- **Boundary values — negative or unusually large stored settings**: The settings accept and pass through any stored value — including a negative value or one set outside whatever range a settings UI would offer (for example via a direct write to the underlying store) — with no clamping or validation anywhere in this component before it reaches the content insets or the divider thickness. This is by design (see Design Decisions: clamping ownership): the spacing value is a thin passthrough over the underlying setting, and range validation on interactively-entered values is the settings-control layer's job — a mechanism this component's current-value read never invokes.
- **Concurrent access**: Not applicable — every read and write of the six settings in this component is confined to a single thread, so there is no concurrent-access hazard by construction.
- **Error states**: Not applicable — the settings store's read/write operations return and accept concrete values with no failure path; this component exposes no failure path to handle.
- **Offline/disconnected state**: Not applicable — this component performs only local, synchronous settings storage; it makes no network call and has no dependency on connectivity.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `pane_spacing_top` | Integer (points) | `0` | Inset between the pane area's top edge and the tab bar framing it. |
| `pane_spacing_leading` | Integer (points) | `0` | Inset between the pane area's leading edge and the tab bar framing it. |
| `pane_spacing_bottom` | Integer (points) | `0` | Inset between the pane area's bottom edge and the tab bar framing it. |
| `pane_spacing_trailing` | Integer (points) | `0` | Inset between the pane area's trailing edge and the tab bar framing it. |
| `pane_spacing_between_columns` | Integer (points) | `1` | Whole gap between two panes standing side by side (not each pane's half). |
| `pane_spacing_between_rows` | Integer (points) | `1` | Whole gap between two panes stacked one above the other. |

## Deep Linking

Not applicable: this concept is process-internal layout configuration with no screen, route, or URL of its own. No URL scheme, universal link, or activity-continuation handling appears anywhere in this component.

## Localization

Not applicable: this component defines no user-facing string. The six setting keys (`pane_spacing_top`, `pane_spacing_leading`, `pane_spacing_bottom`, `pane_spacing_trailing`, `pane_spacing_between_columns`, `pane_spacing_between_rows`) are internal storage identifiers, not display text, and no displayed string literal appears anywhere in this component.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable — notifying of a spacing change and painting the divider apply and paint immediately; this component defines no animation, transition, or motion-driven change for a Reduce Motion substitute to replace. |
| Increase Contrast | Inherited, not a choice made in this component — painting the divider always uses the active theme's pane-backdrop color; any Increase Contrast adaptation happens wherever the theme system resolves that token, outside this recipe's scope. |
| Differentiate Without Color | Not applicable — the signal a wide gutter carries is its drawn width (the divider thickness), not color alone; the backdrop fill matches the surrounding plane rather than encoding information only through color. |

## Feature Flags

Not applicable: no feature-flag or remote-config lookup of any kind appears in this component.

## Analytics

Not applicable: no analytics event is emitted anywhere in this component.

## Privacy

- **Data collected**: The six `pane_spacing_*` integers only — window-chrome layout preferences, not personal or sensitive data.
- **Storage**: Local only, via the app's settings store. None of the six settings is marked secure, so each routes to the non-secure settings path, which defaults to the platform's standard local-preferences storage unless the host app configures a different provider — a choice made outside this component.
- **Transmission**: None. No network call appears anywhere in this component.
- **Retention**: Persists until explicitly changed or removed; this component defines no expiration or automatic cleanup.

## Logging

Not applicable: no logging call of any kind appears anywhere in this component.

## Platform Notes

- **SwiftUI**: There is no SwiftUI type here to translate directly — Pane Spacing is a plain set of settings and the pane split view is a subclass of the platform's own split view. A SwiftUI-first rebuild would keep the six values behind `@AppStorage`-backed (or `ObservableObject`-wrapped) properties mirroring the source's `@Published currentValue`, apply the four edges with `.padding(EdgeInsets(top:leading:bottom:trailing:))`, and replace the gutter with a custom draggable divider view sized from `betweenColumns`/`betweenRows` and filled from the same semantic backdrop color, since SwiftUI's own `HSplitView`/`VSplitView` divider is not restylable the way overriding the divider-drawing hook allows.
- **Compose**: Model the four insets as `Modifier.padding(start = , top = , end = , bottom = )` on the pane container, and each gutter as a `Spacer`-sized `Box`/`Canvas` element between panes in a `Row`/`Column`, colored from the `MaterialTheme` surface-variant token that plays the role the pane-backdrop color plays here. Persist the six values with `DataStore`/`SharedPreferences` and observe changes via a `Flow`, mirroring the source's `Combine`-based publisher.
- **React/Web**: Represent the four insets as CSS custom properties (`--pane-spacing-top`, etc.) applied as padding on the pane container, and each gutter as a resizable divider element (`cursor: col-resize` / `row-resize`) whose background is the app's panel-backdrop CSS variable rather than a hardcoded color — reproducing the "backdrop, not a stripe" choice this component makes. Give the divider element a `min-width`/`min-height` matching the minimum divider grab width so a zero-width gutter stays draggable, and persist the six values to `localStorage`, observed with a `storage` event listener for cross-tab updates.
- **AppKit / UIKit**: This is the source. `PaneSpacing.swift` defines the enum, the `UserSettings` extension, and `PaneSplitView : ThemedSplitView : NSSplitView`; specific to AppKit here are `NSEdgeInsets`, the `dividerThickness`/`drawDivider(in:)` overrides, and using `NSSplitView.DividerStyle`'s stock `.thin`/`.paneSplitter` cases purely as a nudge — reassigning `dividerStyle` off and back is what makes AppKit discard the constraint constants an `NSSplitViewController` built from the old `dividerThickness`. `PaneSpacing`, `PaneSplitView`, and `UserSetting` are all `@MainActor`-isolated. Each of the six settings converts its underlying `Int` value to `CGFloat` when building `NSEdgeInsets`/`dividerThickness`. Settings default to `UserDefaultsSettingsStorageProvider` (`UserDefaults`) unless the host app configures `UserSettings.shared` with a different provider. macOS's HIG has no published minimum divider/gutter width, so this component's own drawn thickness has no declared minimum or maximum of its own. UIKit has no direct analog to this per-pixel divider-drawing hook; `UISplitViewController`'s separator styling would be the nearest translation target, relevant only if this component is ever asked to run on iOS (`platforms` here lists macOS only).
- **WinUI 3**: Represent the four insets as `Margin`/`Padding` on the content `Border`, and each gutter as a `GridSplitter` (from `CommunityToolkit.WinUI.Controls` — the Windows Community Toolkit's Sizers package, not `Microsoft.UI.Xaml.Controls`; the app takes a package dependency on the toolkit to get it) sitting in its own zero-content `ColumnDefinition`/`RowDefinition` between panes — `GridSplitter.Width`/`Height` plays the role `betweenColumns`/`betweenRows` play here. `GridSplitter.Background` swaps between the theme's default thin divider brush and an explicit pane-backdrop `ThemeResource` brush depending on whether the configured width is `<= 1` or greater, reproducing the hairline-vs-fill choice in the divider-drawing hook. Unlike AppKit's constraint-cached `NSSplitViewController`, WinUI's `Grid` recomputes column/row sizes as soon as a `ColumnDefinition.Width`/`RowDefinition.Height` changes, so no "toggle a style off and back" nudge is needed — binding the `GridSplitter`'s governing `GridLength` to the setting is enough. Persist the six values with `ApplicationDataContainer.LocalSettings`, the closest analog to `UserDefaultsSettingsStorageProvider`. `GridSplitter`'s built-in `Thumb` already exposes a wider drag/hover hit area than its visual thickness, which is the WinUI equivalent of the minimum divider grab width.

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
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/layout/composable-tabs/. |
