---
id: 52e34f70-c3d8-4ec6-a753-d9d3cea11789
title: ComposableTabsViewRegistry
domain: agentictoolkit://recipes/composable-tabs-view-registry
type: ingredient
version: 1.1.2
status: review
language: en
created: '2026-09-23'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Per-project factory registry that vends a composable-tabs pane's content
  view controller by view id, falling back to a numbered placeholder pane.
platforms:
- swift
- macos
tags:
- registry
- view-factory
- placeholder
- appkit
- macos
depends-on: []
related: []
references:
- https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum.html
- https://developer.apple.com/documentation/appkit/nsviewcontroller
approved-by: ''
approved-date: ''
---

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

## States

| State | Appearance change |
|-------|------------------|
| Default | Numbered title centered over a container tinted by the pane's chart-series color at 0.15 alpha (or untinted if the series is empty). |
| Pressed | Not applicable: neither the container nor the title is a control; the source attaches no click/press handling to either. |
| Disabled | Not applicable: the source defines no enabled/disabled state for this view. |
| Focused | Not applicable: the title is a non-editable, non-interactive `ThemedLabel`; the source gives the container no focus ring or key-view behavior. |
| Loading | Not applicable: the view has no asynchronous content or loading affordance; it is populated synchronously in `loadView()`. |

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

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| CTVR-01 | placeholder-registration | A freshly constructed `ComposableTabsViewRegistry` | `isRegistered(.placeholder)` is `true` |
| CTVR-02 | register-overwrite | Register a view id, then register it again with a different descriptor/factory | `descriptor(for:)` reflects the second registration; the first factory is never invoked |
| CTVR-03 | placeholder-protection | `unregister(.placeholder)` | Returns `false`; `isRegistered(.placeholder)` remains `true`; an error is logged |
| CTVR-04 | unregister-removal | Register a non-placeholder view id, then `unregister` it | Returns `true`; `isRegistered(_:)` is `false` afterward |
| CTVR-05 | unregister-absence | `unregister` a view id that was never registered | Returns `false` |
| CTVR-06 | view-id-ordering | Register `"z.view"`, `"a.view"`, `"m.view"` | `registeredViewIDs` returns `[a.view, m.view, .placeholder, z.view]` in ascending `rawValue` order — `.placeholder`'s `rawValue` is `"whippet.placeholder"`, which sorts between `"m.view"` and `"z.view"` |
| CTVR-07 | registration-presence | Query `isRegistered(_:)` for a registered and an unregistered id | Returns `true` and `false` respectively |
| CTVR-08 | descriptor-default | `descriptor(for:)` for an unregistered view id | Returns `ComposableTabsViewDescriptor.unknown` (`displayName == "Unknown"`) |
| CTVR-09 | factory-dispatch | Register a view id with a factory returning a distinguishable view controller, then call `makeContentViewController` for it | The returned view controller is the one the factory produced |
| CTVR-10 | unregistered-fallback | Call `makeContentViewController` for an unregistered view id with `paneNumber: 3` | Returns a `PlaceholderPaneViewController` showing "Pane 3"; an error is logged |
| CTVR-11 | tree-id-default | Call `makeContentViewController` with `treeID: nil` and a given `nodeID` | The factory's `ComposableTabsViewContext.treeID` equals that `nodeID` |
| CTVR-12 | context-passthrough | Call `makeContentViewController` with distinct `project`, `workingDirectory`, `paneNumber`, `ownerNodeID` values | The factory's `ComposableTabsViewContext` carries each value unchanged |
| CTVR-13 | state-store-owner | Call `makeStateStore(prefix:)` on a context built with a non-nil `ownerNodeID` | The returned `ProjectPaneStateStore.ownerNodeID` equals the context's `ownerNodeID` |
| CTVR-14 | explicit-holding-priority | A descriptor with `holdingPriority: .defaultHigh` and `preferredThicknessFraction: 0.5` | `resolvedHoldingPriority` equals `.defaultHigh` |
| CTVR-15 | fractioned-priority-boost | A descriptor with `holdingPriority: nil`, `preferredThicknessFraction: 0.3` | `resolvedHoldingPriority.rawValue` equals `NSLayoutConstraint.Priority.defaultLow.rawValue + 10` |
| CTVR-16 | default-low-priority | A descriptor with `holdingPriority: nil`, `preferredThicknessFraction: nil` | `resolvedHoldingPriority` equals `.defaultLow` |
| CTVR-17 | optional-teardown | A content type does not adopt `PaneContentTeardown` | Casting an instance to `PaneContentTeardown?` yields `nil`; nothing in this file requires or assumes the cast succeeds |
| CTVR-18 | optional-removal-confirmation | A content type adopts `PaneContentRemovalConfirmation` and returns `nil` from `removalConfirmationMessage`, and separately a content type that does not adopt the protocol at all | `removalConfirmationMessage` is `nil` in the adopting case; casting to `PaneContentRemovalConfirmation?` is `nil` in the non-adopting case — both mean "nothing would be lost" per this file's protocol contract |
| CTVR-19 | placeholder-pane-number | Construct `PlaceholderPaneViewController(paneNumber: 5)` and load its view | The title label's `stringValue` is "Pane 5" |
| CTVR-20 | placeholder-series-tint | Load a placeholder for `paneNumber: 2` under a theme whose `chartSeriesNSColors` has at least 2 entries | The container layer's `backgroundColor` equals `series[1]` at 0.15 alpha |
| CTVR-21 | empty-series-no-tint | Load a placeholder under a theme whose `chartSeriesNSColors` is empty | The container layer's `backgroundColor` is unchanged from its default |
| CTVR-22 | placeholder-retint | Load a placeholder, then switch the active theme | The container's tint is recomputed against the new theme's `chartSeriesNSColors` |
| CTVR-23 | placeholder-title-centering | Load a placeholder's view and lay it out | The title's center X and center Y equal the container's center X and center Y |
| CTVR-24 | coder-init-unavailable | Attempt to instantiate `PlaceholderPaneViewController` via `init(coder:)` (e.g. from a storyboard/XIB unarchive) | The process traps with a fatal error |
| CTVR-25 | stale-tint-persistence | Load a placeholder under a theme with a non-empty `chartSeriesNSColors`, note the container's tint, then switch to a theme whose `chartSeriesNSColors` is empty | The container layer's `backgroundColor` remains the tint set under the prior theme, unchanged |

## Edge Cases

- Null/empty input: `descriptor(for:)` for a view id with no entry MUST
  return `.unknown` rather than throwing or crashing — traced to
  `entries[viewID]?.descriptor ?? .unknown`.
- Null/empty input: `makeContentViewController(...)` for a view id with no
  entry MUST return a placeholder rather than throwing — traced to the
  `guard let entry = entries[viewID] else { ... return PlaceholderPaneViewController(...) }`.
- Null/empty input: `makeContentViewController(...)` called with `treeID: nil`
  MUST fall back to `nodeID` per **tree-id-default**, rather than
  leaving `treeID` `nil` or generating a new identifier — traced to
  `treeID: treeID ?? nodeID`.
- Null/empty input: `PlaceholderPaneViewController` loaded while the theme's
  `chartSeriesNSColors` is empty MUST leave the container untinted per
  **empty-series-no-tint** — traced to
  `guard !series.isEmpty else { return }`.
- Boundary values: A theme switch from a chart-series list that is non-empty
  to one that is empty MUST leave the container's previously set tint in
  place, per **stale-tint-persistence** — traced to the same
  `guard !series.isEmpty else { return }` in the `observeTheme` closure, which
  makes no assignment on that path rather than clearing the layer's
  `backgroundColor`.
- Boundary values: `unregister(.placeholder)` MUST always be refused,
  regardless of how many other view ids are registered — the only view id the
  registry hard-codes as non-removable.
- Boundary values: `paneNumber == 1` MUST index `chartSeriesNSColors[0]` (the
  `(number - 1) % series.count` formula's lowest input), and any `paneNumber`
  larger than the series length MUST wrap via the modulo rather than index out
  of bounds.
- Concurrent access: The registry, `ComposableTabsViewContext`, and
  `PlaceholderPaneViewController` are all `@MainActor`; registration,
  unregistration, lookup, and content creation all happen on the main actor,
  so concurrent mutation from multiple threads is not a case this file has to
  handle.
- Error states: The only error path in this file is an unregistered view id,
  and it is not surfaced as a thrown error or shown to the user — it is
  handled by falling back to `PlaceholderPaneViewController` and logging at
  `.error` (**unregistered-fallback**,
  **placeholder-protection**). Nothing in this file communicates that
  fallback to the caller beyond the placeholder itself and the log line.
- Offline/disconnected: Not applicable. The registry makes no network call
  and holds no server-backed state; it is a pure in-memory, single-process
  map from view id to descriptor and factory.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `displayName` | `String` | (required) | What the Split menu calls this view. |
| `symbolName` | `String?` | `nil` | Optional SF Symbol shown alongside menu items for this view. |
| `preferredAxis` | `ComposableTabsAxis` | `.horizontal` | The axis the Split menu proposes first for a new pane of this kind; does not forbid the other axis. |
| `minimumThickness` | `CGFloat` | `120` | Minimum width or height of the pane, in points. |
| `preferredThicknessFraction` | `CGFloat?` | `nil` | Share of the enclosing split this pane asks for on first layout; `nil` divides evenly. |
| `isCollapsible` | `Bool` | `false` | Whether AppKit may collapse the pane to nothing. |
| `holdingPriority` | `NSLayoutConstraint.Priority?` | `nil` | Explicit resize-resistance priority; `nil` derives it via `resolvedHoldingPriority`. |

## Deep Linking

Not applicable: the source defines no URL scheme, route, or deep-link
handling. A view id is resolved only from an in-memory registry lookup, never
from a URL.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — inline string literal) | `Pane \(paneNumber)` | `PlaceholderPaneViewController`'s title, shown for `.placeholder` and for any unregistered view id. |
| (none — inline string literal) | "Placeholder" | `ComposableTabsViewDescriptor.placeholder.displayName`, the name the Split menu shows. |
| (none — inline string literal) | "Unknown" | `ComposableTabsViewDescriptor.unknown.displayName`, shown for an unregistered view id. |

The source contains no localization mechanism for this string — no
`NSLocalizedString`, string catalog lookup, or similar — so it renders as the
literal English text "Pane N" regardless of the device's locale.

`"Pane \(paneNumber)"` (ComposableTabsViewRegistry.swift:279) and the
`"Placeholder"`/`"Unknown"` display names (:114, :118) are plain `String`
literals, none routed through `String(localized:)` or `NSLocalizedString`,
so none reaches a string catalog.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: the placeholder's tint and layout are set once, synchronously, with no animation or transition; there is no motion for this setting to reduce. |
| Increase Contrast | Not applicable as a distinct code path: the source performs no Increase-Contrast-specific branching of its own; all color comes from theme tokens whose actual values live outside this file (see Accessibility > Contrast). |
| Differentiate Without Color | Satisfied without a marker: each placeholder's identity is not conveyed by tint color alone — its title label always shows the pane's number, which is the primary identifying cue; the color tint is a secondary reinforcement, per **placeholder-pane-number** and **placeholder-series-tint**. |

## Feature Flags

Not applicable: the source contains no feature-flag or remote-config check of
any kind.

## Analytics

Not applicable: the source contains no analytics or telemetry call.

## Privacy

- **Data collected**: None. The registry holds only in-process configuration
  (descriptors and factory closures) supplied by the app itself, and the
  placeholder displays only a pane number computed by its caller — no user
  content or identifier.
- **Storage**: In-memory only, in the registry's private `entries` dictionary,
  for the life of the registry instance; nothing in this file writes to disk,
  `UserDefaults`, or a database.
- **Transmission**: None. Nothing in this file makes a network call or sends
  its state outside the process.
- **Retention**: Entries live only as long as the registry instance that
  holds them (per project, per `ComposableTabsLayout`); nothing here persists
  across a relaunch.

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (via `Loggable`) | Category: `ComposableTabsViewRegistry`

| Event | Level | Message |
|-------|-------|---------|
| `unregister(.placeholder)` called | error | `Refusing to unregister {viewID} — every registry resolves it` |
| `makeContentViewController(for:...)` called with an unregistered view id | error | `No view registered for {viewID} — showing a placeholder` |

Both messages interpolate the view id's `rawValue` with `privacy: .public`,
per `Self.logger.error(...)`. `Loggable`'s default (used unmodified here)
derives the subsystem from `Bundle.main.bundleIdentifier` and the category
from the conforming type's name, `ComposableTabsViewRegistry`.

## Platform Notes

- **SwiftUI**: There is no `NSViewController`-returning factory pattern in
  SwiftUI; model the registry as a small `@MainActor` class holding
  `[ComposableTabsViewID: (ComposableTabsViewDescriptor, (ComposableTabsViewContext) -> AnyView)]`
  and expose it via `.environmentObject` or an `@Environment` key, so a pane
  host resolves content with `registry.makeContent(for:context:)` returning
  `AnyView` instead of a view controller. The placeholder becomes a plain
  `View`: a `ZStack` with a `.background(color.opacity(0.15))` modifier and a
  centered `Text("Pane \(paneNumber)")` with its font resolved from the
  environment's theme — `.font(theme.font(for: .heading))`, read via an
  `@Environment` theme key — never a hardcoded `.font(.title)`, so it stays
  the SwiftUI analogue of the source's theme-token-only `.heading` role;
  retinting happens automatically when the environment's theme value changes
  rather than through an explicit `observeTheme` call.
- **Compose**: Hold the registry as a plain Kotlin class mapping a view id to
  a descriptor plus a `@Composable (ComposableTabsViewContext) -> Unit`
  factory (Compose has no view-controller-owning-child concept, so a
  composable function fills the factory's role directly). The placeholder
  becomes a `Box(Modifier.fillMaxSize().background(seriesColor.copy(alpha = 0.15f)))`
  with a centered `Text("Pane $paneNumber", style = MaterialTheme.typography.headlineSmall)`;
  teardown moves from an adopted protocol to a `DisposableEffect`'s `onDispose`
  block on the pane's composable, and confirmation-before-removal becomes a
  plain nullable-string-returning function called before dismissal.
- **React/Web**: Model the registry as a plain object or `Map` from a string
  view id to `{ descriptor, factory }`, where `factory` is a component
  constructor or render function (a component registry / plugin-map pattern,
  common in extensible web apps). The placeholder becomes a functional
  component rendering a `div` sized by its flex/grid pane, with
  `backgroundColor` set to the series color at 15% alpha via CSS
  `color-mix()` or an rgba string, and a centered `<span>Pane {n}</span>`
  styled from the app's heading token; teardown maps to a `useEffect` cleanup
  function in place of `PaneContentTeardown`, and removal confirmation to a
  plain callback prop returning a string or `undefined`.
- **AppKit/UIKit**: This is the source platform; see
  `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/ComposableTabs/ComposableTabsViewRegistry.swift`.
  It is macOS/AppKit-only: `NSViewController`, `NSColor`,
  `NSLayoutConstraint.Priority`, and the `Factory` typealias's `NSViewController`
  return type have no UIKit equivalent as written. A UIKit port would change
  `Factory` to return `UIViewController`, swap `NSColor` for `UIColor` and
  `NSLayoutConstraint.Priority` for `UILayoutPriority`, and would need its own
  container-view-controller embedding (`addChild`/`didMove(toParent:)`) in
  place of whatever AppKit-specific embedding `ComposableTabsPaneViewController`
  performs outside this file.
- **WinUI 3**: Model
  `ComposableTabsViewRegistry` as a C# class holding a
  `Dictionary<string, (ComposableTabsViewDescriptor Descriptor, Func<ComposableTabsViewContext, UserControl> Factory)>`
  (the `Factory` typealias becomes a `Func<...>` returning a `UserControl` or
  `Page`, since WinUI panes host XAML content rather than a
  `NSViewController`); `Register`, `Unregister` (refusing the placeholder key
  exactly as `placeholder-protection` requires), `RegisteredViewIds`
  (sorted with `OrderBy(id => id, StringComparer.Ordinal)`), `IsRegistered`,
  `Descriptor`, and `MakeContentView` mirror the six public members 1:1.
  `ComposableTabsViewDescriptor` becomes a C# record with `DisplayName`,
  `IconSource` (a `SymbolIconSource`/`FontIconSource` in place of an SF Symbol
  name), `PreferredAxis`, `MinimumThickness` (bound to a `GridSplitter`
  pane's `MinWidth`/`MinHeight`), `PreferredThicknessFraction` (mapped to a
  `GridLength` star value on the hosting `Grid.ColumnDefinitions`/`RowDefinitions`),
  `IsCollapsible`, and `HoldingPriority`; XAML's `Grid` has no holding-priority
  construct comparable to Auto Layout's, so `ResolvedHoldingPriority` has no
  direct WinUI analogue — the nearest equivalent is choosing which column gets
  a fixed `GridLength` versus a `*`-weighted one, which is a layout-time
  decision rather than a runtime priority value, and is the one part of this
  recipe with no 1:1 WinUI mapping. The placeholder becomes a `UserControl`
  with a `Border` whose `Background` is a `SolidColorBrush` built from the
  theme's chart-series brush resource at 15% `Opacity` (mirroring
  `withAlphaComponent(0.15)`), containing a `TextBlock`
  `HorizontalAlignment="Center" VerticalAlignment="Center"` bound via
  `x:Bind PaneNumber` and styled `Style="{StaticResource TitleTextBlockStyle}"`
  (the Fluent 2 analogue of the `.heading` `TextRole`); since the control has
  no interactive states, no `VisualStateGroup` beyond the default
  `CommonStates.Normal` is needed. Retinting on theme change replaces the
  source's `observeTheme` associated-object mechanism with `{ThemeResource}`
  brush bindings plus a handler on the app's own theme-store change event —
  the `observeTheme` analogue — rather than
  `FrameworkElement.ActualThemeChanged`, which only fires when the system
  switches between light and dark and would miss an in-app `SemanticPalette`
  theme change. Logging replaces `Loggable`/`OSLog` with
  `Microsoft.Extensions.Logging.ILogger<ComposableTabsViewRegistry>`, using
  the same category-equals-type-name convention.

## Design Decisions

- **Decision**: `ComposableTabsViewRegistry` is an instance, obtained per
  project through `ComposableTabsLayout`, not a global singleton or namespace
  of statics.
  **Rationale**: Per the source's own comment, the demo project and a real
  app project need different view sets in the same process, and with global
  registration the last registrant wins.
  **Approved**: pending
- **Decision**: `.placeholder` can never be unregistered.
  **Rationale**: Per the source's own comment, every registry must always be
  able to resolve `.placeholder`, because losing it would lose the layout
  built on it — a project's stored layout can name `.placeholder` explicitly.
  **Approved**: pending
- **Decision**: An unregistered view id resolves to a placeholder rather than
  throwing or trapping, but is still logged at `.error`.
  **Rationale**: The source's own comment: a project can legitimately name
  content the running app doesn't have (an uninstalled extension), so a hard
  failure would be wrong, but the same situation can also mean spec/registry
  drift, which the source treats as something that should stay visible rather
  than silently rendering "Pane N" with no trace.
  **Approved**: pending
- **Decision**: A `Factory` vends an `NSViewController`, never a bare `NSView`.
  **Rationale**: Per the source's own comment, `ComposableTabsPaneViewController`
  adopts the returned controller as a child, which is what puts the content
  in the responder chain, delivers its appearance callbacks, and keeps it
  alive; a bare view would leave its owner unowned and its `viewWillAppear`
  silent.
  **Approved**: pending
- **Decision**: `treeID` defaults to `nodeID` when the caller passes `nil`,
  rather than generating a shared default or leaving it unset.
  **Rationale**: Per the source's own comment, a pane with no tree above it
  is its own tree, so its identity degrades to "pairs with nothing" instead
  of "pairs with a shared default every such lone pane would collide on."
  **Approved**: pending
- **Decision**: `ComposableTabsViewContext` is a struct with a
  `makeStateStore(prefix:)` method, rather than each factory constructing its
  own `ProjectPaneStateStore`.
  **Rationale**: Per the source's own comment, this keeps where a nested
  pane's rows live to one decision in one place, instead of a key every
  factory has to spell the same way.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | passed | accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | accessibility |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | internationalization |

`screen-reader-support` passes because the placeholder's only text, "Pane N", is
also its default AppKit accessibility label, with nothing shown that the
label omits. `contrast-ratio` is `partial` for the reason given in
Accessibility > Contrast: the actual color values behind
`chartSeriesNSColors` and `.primaryText` are chosen per theme, outside this
file, so the pairing cannot be confirmed to pass or shown to fail from this
source alone. `no-hardcoded-strings`
fails because `PlaceholderPaneViewController`'s title is the literal
`"Pane \(paneNumber)"`, with no localization mechanism, per Localization.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial extraction from source. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: replace the uncited HIG root reference with the two pages the contrast and containment claims actually rely on; drop the unsupported WinUI "reason this recipe exists" line; rename every requirement to a subject-only name and update every citation; fix the `text-contrast` status to `partial` and add a `no-hardcoded-strings` internationalization row marked `failed`; remove the leftover template instruction line from Accessibility Options; add a `stale-tint-persistence` requirement, edge case, and CTVR-25 for the non-empty-to-empty series transition; correct CTVR-06's expected sort order against `.placeholder`'s actual `"whippet.placeholder"` `rawValue`; rewrite CTVR-17/18 to test only this file's protocol shape instead of pane discard/close behavior owned elsewhere; fix the fractioned-holding-priority requirement's type to `NSLayoutConstraint.Priority(rawValue:)`; correct the WinUI member count to six and its retint bullet to the app's own theme-store event; and resolve the SwiftUI port's placeholder font from the environment's `.heading` token instead of a hardcoded `.font(.title)`. |
| 1.1.1 | 2026-09-23 | Mike Fullerton | Compliance: removed rows for checks absent from the cookbook catalog, remapped meaningful-labels to screen-reader-support, remapped text-contrast to contrast-ratio |
| 1.1.2 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
