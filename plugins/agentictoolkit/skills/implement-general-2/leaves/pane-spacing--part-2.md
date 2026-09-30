<!-- leaf: implement-general-2/pane-spacing--part-2 · source: pane-spacing.md -->

# PaneSpacing — continued (part 2)

## Platform Notes

- **SwiftUI**: There is no SwiftUI type here to translate directly — `PaneSpacing` is a plain `enum` of settings and `PaneSplitView` is an `NSSplitView` subclass. A SwiftUI-first rebuild would keep the six values behind `@AppStorage`-backed (or `ObservableObject`-wrapped) properties mirroring `UserSetting`'s `@Published currentValue`, apply the four edges with `.padding(EdgeInsets(top:leading:bottom:trailing:))`, and replace the gutter with a custom draggable divider view sized from `betweenColumns`/`betweenRows` and filled from the same semantic backdrop color, since SwiftUI's own `HSplitView`/`VSplitView` divider is not restylable the way overriding `drawDivider(in:)` allows.
- **Compose**: Model the four insets as `Modifier.padding(start = , top = , end = , bottom = )` on the pane container, and each gutter as a `Spacer`-sized `Box`/`Canvas` element between panes in a `Row`/`Column`, colored from the `MaterialTheme` surface-variant token that plays the role `projectPaneBackdrop` plays here. Persist the six values with `DataStore`/`SharedPreferences` and observe changes via a `Flow`, mirroring `UserSetting`'s Combine `@Published` publisher.
- **React/Web**: Represent the four insets as CSS custom properties (`--pane-spacing-top`, etc.) applied as padding on the pane container, and each gutter as a resizable divider element (`cursor: col-resize` / `row-resize`) whose background is the app's panel-backdrop CSS variable rather than a hardcoded color — reproducing the "backdrop, not a stripe" choice `drawDivider(in:)` makes. Give the divider element a `min-width`/`min-height` matching `minimumDividerGrab` so a zero-width gutter stays draggable, and persist the six values to `localStorage`, observed with a `storage` event listener for cross-tab updates.
- **AppKit / UIKit**: This is the source. `PaneSpacing.swift` defines the enum, the `UserSettings` extension, and `PaneSplitView : ThemedSplitView : NSSplitView`; specific to AppKit here are `NSEdgeInsets`, the `dividerThickness`/`drawDivider(in:)` overrides, and using `NSSplitView.DividerStyle`'s stock `.thin`/`.paneSplitter` cases purely as a nudge — reassigning `dividerStyle` off and back is what makes AppKit discard the constraint constants an `NSSplitViewController` built from the old `dividerThickness`. UIKit has no direct analog to this per-pixel divider-drawing hook; `UISplitViewController`'s separator styling would be the nearest translation target, relevant only if this component is ever asked to run on iOS (`platforms` here lists macOS only).
- **WinUI 3**: Represent the four insets as `Margin`/`Padding` on the content `Border`, and each gutter as a `GridSplitter` (from `CommunityToolkit.WinUI.Controls` — the Windows Community Toolkit's Sizers package, not `Microsoft.UI.Xaml.Controls`; the app takes a package dependency on the toolkit to get it) sitting in its own zero-content `ColumnDefinition`/`RowDefinition` between panes — `GridSplitter.Width`/`Height` plays the role `betweenColumns`/`betweenRows` play here. `GridSplitter.Background` swaps between the theme's default thin divider brush and an explicit pane-backdrop `ThemeResource` brush depending on whether the configured width is `<= 1` or greater, reproducing the hairline-vs-fill choice in `drawDivider(in:)`. Unlike AppKit's constraint-cached `NSSplitViewController`, WinUI's `Grid` recomputes column/row sizes as soon as a `ColumnDefinition.Width`/`RowDefinition.Height` changes, so no `spacingDidChange()`-style "toggle a style off and back" nudge is needed — binding the `GridSplitter`'s governing `GridLength` to the setting is enough. Persist the six values with `ApplicationDataContainer.LocalSettings`, the closest analog to `UserDefaultsSettingsStorageProvider`. `GridSplitter`'s built-in `Thumb` already exposes a wider drag/hover hit area than its visual thickness, which is the WinUI equivalent of `minimumDividerGrab`.

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
