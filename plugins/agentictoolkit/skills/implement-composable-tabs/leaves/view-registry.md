<!-- leaf: implement-composable-tabs/view-registry · source: composable-tabs-view-registry.md -->

**Rules** (cite as `implement-composable-tabs/view-registry#<slug>`):

- `placeholder-registration` MUST
- `register-overwrite` MUST
- `placeholder-protection` MUST
- `unregister-removal` MUST
- `unregister-absence` MUST
- `view-id-ordering` MUST
- `registration-presence` MUST
- `descriptor-default` MUST
- `factory-dispatch` MUST
- `unregistered-fallback` MUST
- `tree-id-default` MUST
- `context-passthrough` MUST
- `state-store-owner` MUST
- `explicit-holding-priority` MUST
- `fractioned-priority-boost` MUST
- `default-low-priority` MUST
- `optional-teardown` MUST
- `optional-removal-confirmation` MUST
- `placeholder-pane-number` MUST
- `placeholder-series-tint` MUST
- `empty-series-no-tint` MUST
- `placeholder-retint` MUST
- `stale-tint-persistence` MUST
- `placeholder-title-centering` MUST
- `coder-init-unavailable` MUST

# ComposableTabsViewRegistry

## Overview

`ComposableTabsViewRegistry`
(`packages/apple/AgenticToolkit/macOS/UI/ViewControllers/ComposableTabs/ComposableTabsViewRegistry.swift`)
is a `@MainActor` class that maps a `ComposableTabsViewID` to a
`ComposableTabsViewDescriptor` (the pane facts a split needs before it has
content — display name, symbol, preferred axis, minimum thickness, preferred
thickness fraction, collapsibility, holding priority) and a `Factory` closure
that builds the `NSViewController` a pane hosts for that id. It is an
**instance**, not a namespace of statics, because two different projects in
the same process (a demo project and a real app project, per the source's own
comment) need different view sets, and a single global registry would let the
last registrant win. Each project reaches its own instance through
`ComposableTabsLayout`.

The same file defines two supporting protocols pane content may optionally
adopt — `PaneContentTeardown` (release live resources, such as a child
process or a file watcher, the moment a pane closes) and
`PaneContentRemovalConfirmation` (say what would be lost if the pane were
closed, or `nil` for nothing) — and `PlaceholderPaneViewController`, the
numbered, tinted rectangle shown both for the registry's own `.placeholder`
entry and for any view id the registry has no entry for.

The registry itself renders nothing; `PlaceholderPaneViewController` is the
only visual content this file owns, and the Appearance/States/Accessibility
sections below describe that view. Everything else a pane's chrome shows
(title bar, gear menu, split behavior) belongs to
`ComposableTabsPaneViewController` and `ComposableTabsViewController`, which
consume this registry but are out of scope for this recipe.

## Behavioral Requirements

- **placeholder-registration**: `init()` MUST register `.placeholder`,
  mapped to a factory that builds `PlaceholderPaneViewController`, before any
  caller can register or query anything else.
- **register-overwrite**: `register(_:descriptor:factory:)`
  MUST replace any descriptor and factory already registered for that view id.
- **placeholder-protection**: `unregister(_:)` MUST NOT remove the
  entry for `.placeholder`, MUST return `false` when called with it, and MUST
  log an error.
- **unregister-removal**: `unregister(_:)` MUST remove the
  entry and return `true` for any registered view id other than `.placeholder`.
- **unregister-absence**: `unregister(_:)` MUST return `false` for a
  view id that has no registered entry.
- **view-id-ordering**: `registeredViewIDs` MUST return
  every registered view id, sorted ascending by `rawValue`.
- **registration-presence**: `isRegistered(_:)` MUST return `true`
  only for a view id that has a registered entry.
- **descriptor-default**: `descriptor(for:)` MUST return
  `ComposableTabsViewDescriptor.unknown` for a view id with no registered
  entry, and MUST return the registered descriptor otherwise.
- **factory-dispatch**:
  `makeContentViewController(for:nodeID:project:workingDirectory:paneNumber:ownerNodeID:treeID:)`
  MUST invoke the factory registered for that view id, passing it a
  `ComposableTabsViewContext` built from the call's parameters and that
  entry's descriptor.
- **unregistered-fallback**:
  `makeContentViewController(...)` MUST return a `PlaceholderPaneViewController`
  carrying the call's `paneNumber`, and MUST log an error, for a view id with
  no registered entry, rather than throwing or trapping.
- **tree-id-default**: `makeContentViewController(...)` MUST set
  the context's `treeID` to the call's `nodeID` when the `treeID` parameter is
  `nil`.
- **context-passthrough**: `makeContentViewController(...)`
  MUST pass `nodeID`, `project`, `workingDirectory`, `paneNumber`, and
  `ownerNodeID` through to the `ComposableTabsViewContext` exactly as given.
- **state-store-owner**: `ComposableTabsViewContext.makeStateStore(prefix:)`
  MUST construct the returned `ProjectPaneStateStore` with the context's
  `project`, `nodeID`, and the given `prefix`, and MUST set the store's
  `ownerNodeID` to the context's `ownerNodeID`.
- **explicit-holding-priority**:
  `ComposableTabsViewDescriptor.resolvedHoldingPriority` MUST return
  `holdingPriority` when it is non-`nil`, regardless of `preferredThicknessFraction`.
- **fractioned-priority-boost**: When `holdingPriority`
  is `nil` and `preferredThicknessFraction` is non-`nil`,
  `resolvedHoldingPriority` MUST return
  `NSLayoutConstraint.Priority(rawValue: NSLayoutConstraint.Priority.defaultLow.rawValue + 10)`.
- **default-low-priority**: When both `holdingPriority`
  and `preferredThicknessFraction` are `nil`, `resolvedHoldingPriority` MUST
  return `NSLayoutConstraint.Priority.defaultLow`.
- **optional-teardown**: Pane content MAY adopt
  `PaneContentTeardown` to be told, via `paneContentWillBeDiscarded()`, the
  moment its pane is discarded; content that does not adopt it MUST NOT be
  assumed to need teardown.
- **optional-removal-confirmation**: Pane content MAY adopt
  `PaneContentRemovalConfirmation` to supply a `removalConfirmationMessage`
  describing what would be lost if its pane were closed; content that returns
  `nil`, or does not adopt the protocol, MUST be treated as having nothing to
  lose.
- **placeholder-pane-number**: `PlaceholderPaneViewController` MUST
  display the literal text "Pane N", where N is the 1-based `paneNumber` it
  was constructed with.
- **placeholder-series-tint**: `PlaceholderPaneViewController` MUST
  set its container's layer background to
  `palette.chartSeriesNSColors[(paneNumber - 1) % series.count]` at 0.15 alpha
  whenever the active theme's chart-series color list is non-empty.
- **empty-series-no-tint**:
  `PlaceholderPaneViewController` MUST NOT set a background tint when the
  active theme's chart-series color list is empty.
- **placeholder-retint**: `PlaceholderPaneViewController`
  MUST re-evaluate its tint, via `observeTheme`, every time the active theme
  changes.
- **stale-tint-persistence**: When **placeholder-retint**'s handler
  re-evaluates and the newly active theme's chart-series color list is empty,
  `PlaceholderPaneViewController` MUST leave the container's existing
  background tint unchanged rather than clearing it — the early-return guard
  makes no assignment on that path, so a tint set under a prior, non-empty
  theme persists after the switch.
- **placeholder-title-centering**: `PlaceholderPaneViewController` MUST
  center its title label both horizontally and vertically within its
  container view.
- **coder-init-unavailable**: `PlaceholderPaneViewController.init(coder:)`
  MUST be unavailable and MUST trap with a fatal error if ever called.

## Appearance

- **Corner radius**: None. `PlaceholderPaneViewController`'s container is a
  plain `NSView` with `wantsLayer = true` and no `cornerRadius` set on its
  layer.
- **Padding**: Not applicable. The title label is positioned by centering
  constraints (`centerXAnchor`, `centerYAnchor`) against the container, not by
  an edge inset.
- **Font**: Determined by the theme, not this file: the title is a
  `ThemedLabel` constructed with `textRole: .heading`, so its resolved font
  (family, size, weight) is whatever `SemanticPalette.font(.heading)` returns
  for the active theme. `ThemedLabel` has its own recipe; this component only
  selects the `.heading` role.
- **Background**: The container's `CALayer.backgroundColor` is set to
  `palette.chartSeriesNSColors[(paneNumber - 1) % series.count].withAlphaComponent(0.15)`
  when the theme's chart-series list is non-empty (per
  **placeholder-series-tint**); otherwise the layer's background is
  left at its default (unset/transparent).
- **Foreground/Text**: The title's text color is `palette.nsColor(.primaryText)`,
  set by `ThemedLabel`'s own `role: .primaryText` (the default the source
  passes explicitly).
- **Border**: None. No border width or color is set on the container or the
  title.
- **Shadow**: None. No shadow is set on the container's layer.
- **Min/Max size**: The container is created with an initial frame of
  300×200 points in `loadView()`; this is only the view's starting size; it is
  actually sized by the pane layout that hosts it (auto-layout constraints
  applied by `ComposableTabsPaneViewController`, outside this file). Separately,
  `ComposableTabsViewDescriptor.placeholder`'s `minimumThickness` is the
  default `120` points, inherited from `ComposableTabsViewDescriptor.init`'s
  default parameter value, since the placeholder descriptor supplies only
  `displayName`.

## Accessibility

- **Role/traits**: Not applicable as a distinct requirement of this file:
  neither the container `NSView` nor the title `ThemedLabel` sets an explicit
  `accessibilityRole`, `accessibilityLabel`, or `accessibilityElement` value.
  The title is an `NSTextField` subclass (`ThemedLabel`), so it carries
  `NSTextField`'s own default accessibility exposure (a static-text element
  whose accessibility label is its `stringValue`, "Pane N") without any
  additional code in this file.
- **Label requirements**: The only text this view shows, "Pane N", is also
  what AppKit exposes as the label by the default behavior above; there is no
  separate accessibility label to keep in sync with the displayed text.
- **Announce state changes**: Not applicable. This view has no loading,
  disabled, or other transient state (see States); there is nothing for it to
  announce.
- **Minimum tap target**: Not applicable. The container and title are not
  tappable controls; the source treats both as inert display content, not a
  button or a control with a hit target.
- **contrast**: NEEDS REVIEW: Not implemented in source. `palette.chartSeriesNSColors` and `palette.nsColor(.primaryText)` are theme-derived tokens (see `SemanticPalette+NSColor.swift` in `agenticdevelopertoolkit`) whose actual RGB values are chosen per theme, so whether the primary-text title reaches a sufficient contrast ratio (WCAG 1.4.3, 4.5:1) against a chart-series tint at 0.15 alpha cannot be computed from `ComposableTabsViewRegistry.swift` alone; resolvable only by auditing each shipped theme's chart-series and primary-text token values against that threshold.

