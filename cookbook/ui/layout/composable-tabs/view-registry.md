---
id: 52e34f70-c3d8-4ec6-a753-d9d3cea11789
title: Composable Tabs View Registry
domain: agentictoolkit://cookbook/ui/layout/composable-tabs/view-registry
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Per-project factory registry that vends a composable-tabs pane's content
  by view id, falling back to a numbered placeholder pane.
platforms:
- swift
- macos
tags:
- registry
- view-factory
- placeholder
depends-on: []
related: []
references:
- https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum.html
- https://developer.apple.com/documentation/appkit/nsviewcontroller
approved-by: ''
approved-date: ''
---

# Composable Tabs View Registry

## Overview

The view registry maps a view id to a descriptor (the pane facts a split
needs before it has content — display name, icon, preferred axis, minimum
thickness, preferred thickness fraction, collapsibility, holding priority)
and a factory that builds the content a pane hosts for that id. It is an
**instance**, not a namespace of statics, because two different projects in
the same process (a demo project and a real app project, per the source's
own comment) need different view sets, and a single global registry would
let the last registrant win. Each project reaches its own instance through
its composable-tabs layout.

The same concept defines two supporting capabilities pane content may
optionally adopt — a teardown capability (release live resources, such as a
child process or a file watcher, the moment a pane closes) and a removal-
confirmation capability (say what would be lost if the pane were closed, or
nothing for nothing lost) — and the placeholder pane, the numbered, tinted
rectangle shown both for the registry's own reserved `placeholder` entry
and for any view id the registry has no entry for.

The registry itself renders nothing; the placeholder pane is the only
visual content this concept owns, and the Appearance/States/Accessibility
sections below describe that view. Everything else a pane's chrome shows
(title bar, gear menu, split behavior) belongs to the pane view and the
tabbed content view, which consume this registry but are out of scope for
this recipe.

## Behavioral Requirements

- **placeholder-registration**: Constructing the registry MUST register the
  `placeholder` view id, mapped to a factory that builds the placeholder
  pane, before any caller can register or query anything else.
- **register-overwrite**: Registering a view id MUST replace any descriptor
  and factory already registered for that view id.
- **placeholder-protection**: Unregistering MUST NOT remove the entry for
  the `placeholder` view id, MUST return false when called with it, and
  MUST log an error.
- **unregister-removal**: Unregistering MUST remove the entry and return
  true for any registered view id other than `placeholder`.
- **unregister-absence**: Unregistering MUST return false for a view id
  that has no registered entry.
- **view-id-ordering**: Listing registered view ids MUST return every
  registered view id, sorted ascending by its raw string value.
- **registration-presence**: Checking whether a view id is registered MUST
  return true only for a view id that has a registered entry.
- **descriptor-default**: Resolving a view id's descriptor MUST return the
  `unknown` descriptor for a view id with no registered entry, and MUST
  return the registered descriptor otherwise.
- **factory-dispatch**: Building content for a view id MUST invoke the
  factory registered for that view id, passing it a context built from the
  call's parameters and that entry's descriptor.
- **unregistered-fallback**: Building content for a view id with no
  registered entry MUST return a placeholder pane carrying the call's pane
  number, and MUST log an error, rather than throwing or trapping.
- **tree-id-default**: Building content MUST set the context's tree id to
  the call's node id when no tree id is given.
- **context-passthrough**: Building content MUST pass the node id, project,
  working directory, pane number, and owner node id through to the context
  exactly as given.
- **state-store-owner**: Constructing a state store from a context MUST
  build it with the context's project, node id, and the given prefix, and
  MUST set the store's owner node id to the context's owner node id.
- **explicit-holding-priority**: Resolving a pane's holding priority MUST
  return the descriptor's explicit holding-priority value when one is set,
  regardless of the preferred-thickness-fraction.
- **fractioned-priority-boost**: When no explicit holding-priority value is
  set and a preferred-thickness-fraction is set, resolving MUST return a
  priority value 10 points above the platform's default-low
  resize-priority level.
- **default-low-priority**: When neither an explicit holding-priority value
  nor a preferred-thickness-fraction is set, resolving MUST return the
  platform's default-low resize-priority level.
- **optional-teardown**: Pane content MAY adopt an optional teardown
  capability to be told, the moment its pane is discarded, that it is time
  to release live resources; content that does not adopt it MUST NOT be
  assumed to need teardown.
- **optional-removal-confirmation**: Pane content MAY adopt an optional
  removal-confirmation capability to supply a message describing what
  would be lost if its pane were closed; content that returns nothing, or
  does not adopt the capability, MUST be treated as having nothing to lose.
- **placeholder-pane-number**: The placeholder pane MUST display the
  literal text "Pane N", where N is the 1-based pane number it was
  constructed with.
- **placeholder-series-tint**: The placeholder pane MUST tint its
  container's background using the active theme's chart-series color list,
  indexed by (pane number − 1) modulo the list's count, at 15% opacity,
  whenever that list is non-empty.
- **empty-series-no-tint**: The placeholder pane MUST NOT set a background
  tint when the active theme's chart-series color list is empty.
- **placeholder-retint**: The placeholder pane MUST re-evaluate its tint
  every time the active theme changes.
- **stale-tint-persistence**: When **placeholder-retint**'s re-evaluation
  finds the newly active theme's chart-series color list empty, the
  placeholder pane MUST leave its container's existing background tint
  unchanged rather than clearing it — the guard makes no assignment on
  that path, so a tint set under a prior, non-empty theme persists after
  the switch.
- **placeholder-title-centering**: The placeholder pane MUST center its
  title label both horizontally and vertically within its container.

## Appearance

- **Corner radius**: None. The placeholder's container has no corner
  radius set.
- **Padding**: Not applicable. The title label is positioned by centering
  against the container, not by an edge inset.
- **Font**: Determined by the theme, not this file: the title uses a
  heading text role, so its resolved font (family, size, weight) is
  whatever the active theme returns for that role. The label component
  that resolves theme fonts has its own recipe; this component only
  selects the heading role.
- **Background**: The container's background is tinted using the active
  theme's chart-series color list, indexed by (pane number − 1) modulo the
  list's count, at 15% opacity, when the list is non-empty (per
  **placeholder-series-tint**); otherwise the background is left at its
  default (unset/transparent).
- **Foreground/Text**: The title's text color resolves to the active
  theme's primary-text role.
- **Border**: None. No border width or color is set on the container or
  the title.
- **Shadow**: None. No shadow is set on the container.
- **Min/Max size**: The container is created with an initial frame of
  300×200 points; this is only the view's starting size — it is actually
  sized by the pane layout that hosts it (outside this file). Separately,
  the placeholder descriptor's minimum thickness is the default 120
  points, since the placeholder descriptor supplies only a display name.

## States

| State | Appearance change |
|-------|------------------|
| Default | Numbered title centered over a container tinted by the pane's chart-series color at 0.15 alpha (or untinted if the series is empty). |
| Pressed | Not applicable: neither the container nor the title is a control; the source attaches no click/press handling to either. |
| Disabled | Not applicable: the source defines no enabled/disabled state for this view. |
| Focused | Not applicable: the title is a non-editable, non-interactive label; the source gives the container no focus ring or key-view behavior. |
| Loading | Not applicable: the view has no asynchronous content or loading affordance; it is populated synchronously when the view loads. |

## Accessibility

- **Role/traits**: Not applicable as a distinct requirement of this file:
  neither the container nor the title label sets an explicit accessibility
  role, label, or element value. The title is a text-label component, so
  it carries that component's own default accessibility exposure (a
  static-text element whose accessibility label is its displayed text,
  "Pane N") without any additional code in this file.
- **Label requirements**: The only text this view shows, "Pane N", is also
  what the platform exposes as the label by the default behavior above;
  there is no separate accessibility label to keep in sync with the
  displayed text.
- **Announce state changes**: Not applicable. This view has no loading,
  disabled, or other transient state (see States); there is nothing for it
  to announce.
- **Minimum tap target**: Not applicable. The container and title are not
  tappable controls; the source treats both as inert display content, not
  a button or a control with a hit target.
- **contrast**: NEEDS REVIEW: Not implemented in source. The chart-series
  colors and the primary-text color are theme-derived tokens whose actual
  RGB values are chosen per theme, so whether the primary-text title
  reaches a sufficient contrast ratio (WCAG 1.4.3, 4.5:1) against a
  chart-series tint at 15% opacity cannot be computed from this component
  alone; resolvable only by auditing each shipped theme's chart-series and
  primary-text token values against that threshold.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| CTVR-01 | placeholder-registration | A freshly constructed registry | Checking whether the `placeholder` view id is registered returns true |
| CTVR-02 | register-overwrite | Register a view id, then register it again with a different descriptor/factory | Resolving its descriptor reflects the second registration; the first factory is never invoked |
| CTVR-03 | placeholder-protection | Unregister the `placeholder` view id | Returns false; it remains registered; an error is logged |
| CTVR-04 | unregister-removal | Register a non-placeholder view id, then unregister it | Returns true; it is no longer registered afterward |
| CTVR-05 | unregister-absence | Unregister a view id that was never registered | Returns false |
| CTVR-06 | view-id-ordering | Register `"z.view"`, `"a.view"`, `"m.view"` | Listing registered view ids returns them in ascending order: a.view, m.view, placeholder, z.view — the placeholder id's underlying raw value is `"whippet.placeholder"`, which sorts between `"m.view"` and `"z.view"` |
| CTVR-07 | registration-presence | Query registration status for a registered and an unregistered id | Returns true and false respectively |
| CTVR-08 | descriptor-default | Resolve the descriptor for an unregistered view id | Returns the `unknown` descriptor (display name "Unknown") |
| CTVR-09 | factory-dispatch | Register a view id with a factory returning a distinguishable content object, then build content for it | The returned content is the one the factory produced |
| CTVR-10 | unregistered-fallback | Build content for an unregistered view id with pane number 3 | Returns a placeholder pane showing "Pane 3"; an error is logged |
| CTVR-11 | tree-id-default | Build content with no tree id given and a given node id | The factory's context tree id equals that node id |
| CTVR-12 | context-passthrough | Build content with distinct project, working-directory, pane-number, owner-node-id values | The factory's context carries each value unchanged |
| CTVR-13 | state-store-owner | Construct a state store on a context built with a non-empty owner node id | The returned state store's owner node id equals the context's owner node id |
| CTVR-14 | explicit-holding-priority | A descriptor with an explicit high holding-priority value and a preferred-thickness-fraction of 0.5 | Resolving holding priority returns the explicit high value |
| CTVR-15 | fractioned-priority-boost | A descriptor with no explicit holding-priority value and a preferred-thickness-fraction of 0.3 | Resolving holding priority returns a value 10 points above the platform's default-low resize-priority level |
| CTVR-16 | default-low-priority | A descriptor with neither an explicit holding-priority value nor a preferred-thickness-fraction | Resolving holding priority returns the platform's default-low resize-priority level |
| CTVR-17 | optional-teardown | A content type does not adopt the optional teardown capability | Attempting to use it as that capability yields nothing; nothing in this file requires or assumes it succeeds |
| CTVR-18 | optional-removal-confirmation | A content type adopts the optional removal-confirmation capability and returns nothing from its message, and separately a content type that does not adopt the capability at all | The message is empty in the adopting case; attempting to use the capability yields nothing in the non-adopting case — both mean "nothing would be lost" per this file's contract |
| CTVR-19 | placeholder-pane-number | Construct a placeholder pane with pane number 5 and load its view | The title label's displayed text is "Pane 5" |
| CTVR-20 | placeholder-series-tint | Load a placeholder for pane number 2 under a theme whose chart-series color list has at least 2 entries | The container's background equals series entry index 1 (0-indexed) at 15% opacity |
| CTVR-21 | empty-series-no-tint | Load a placeholder under a theme whose chart-series color list is empty | The container's background is unchanged from its default |
| CTVR-22 | placeholder-retint | Load a placeholder, then switch the active theme | The container's tint is recomputed against the new theme's chart-series color list |
| CTVR-23 | placeholder-title-centering | Load a placeholder's view and lay it out | The title's center point equals the container's center point |
| CTVR-25 | stale-tint-persistence | Load a placeholder under a theme with a non-empty chart-series color list, note the container's tint, then switch to a theme whose chart-series color list is empty | The container's background remains the tint set under the prior theme, unchanged |

## Edge Cases

- Null/empty input: Resolving a descriptor for a view id with no entry
  MUST return the `unknown` descriptor rather than throwing or crashing
  (see **descriptor-default**).
- Null/empty input: Building content for a view id with no entry MUST
  return a placeholder rather than throwing (see **unregistered-fallback**).
- Null/empty input: Building content called with no tree id MUST fall back
  to the node id (see **tree-id-default**), rather than leaving it unset or
  generating a new identifier.
- Null/empty input: A placeholder pane loaded while the theme's
  chart-series color list is empty MUST leave the container untinted per
  **empty-series-no-tint**.
- Boundary values: A theme switch from a chart-series list that is
  non-empty to one that is empty MUST leave the container's previously set
  tint in place, per **stale-tint-persistence**.
- Boundary values: Unregistering the `placeholder` view id MUST always be
  refused, regardless of how many other view ids are registered — the only
  view id the registry hard-codes as non-removable.
- Boundary values: pane number 1 MUST index the first entry of the
  chart-series color list, and any pane number larger than the list's
  length MUST wrap via modulo rather than index out of bounds.
- Concurrent access: the registry and everything it constructs are
  confined to a single thread; registration, unregistration, lookup, and
  content creation all happen there, so concurrent mutation from multiple
  threads is not a case this file has to handle.
- Error states: The only error path in this file is an unregistered view
  id, and it is not surfaced as a thrown error or shown to the user — it
  is handled by falling back to a placeholder pane and logging an error
  (**unregistered-fallback**, **placeholder-protection**). Nothing in this
  file communicates that fallback to the caller beyond the placeholder
  itself and the log line.
- Offline/disconnected: Not applicable. The registry makes no network call
  and holds no server-backed state; it is a pure in-memory, single-process
  map from view id to descriptor and factory.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `displayName` | String | (required) | What the Split menu calls this view. |
| `symbolName` | String (optional) | absent | Optional icon identifier shown alongside menu items for this view. |
| `preferredAxis` | Axis (horizontal or vertical) | horizontal | The axis the Split menu proposes first for a new pane of this kind; does not forbid the other axis. |
| `minimumThickness` | Number (points) | `120` | Minimum width or height of the pane, in points. |
| `preferredThicknessFraction` | Number (optional, 0–1 fraction) | absent | Share of the enclosing split this pane asks for on first layout; absent divides evenly. |
| `isCollapsible` | Boolean | `false` | Whether the platform may collapse the pane to nothing. |
| `holdingPriority` | Layout priority value (optional) | absent | Explicit resize-resistance priority; absent derives it via the holding-priority resolution rules above. |

## Deep Linking

Not applicable: the source defines no URL scheme, route, or deep-link
handling. A view id is resolved only from an in-memory registry lookup, never
from a URL.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — inline string literal) | `Pane \(paneNumber)` | The placeholder pane's title, shown for the `placeholder` view id and for any unregistered view id. |
| (none — inline string literal) | "Placeholder" | The placeholder descriptor's display name, the name the Split menu shows. |
| (none — inline string literal) | "Unknown" | The unknown descriptor's display name, shown for an unregistered view id. |

The source contains no localization mechanism for this string — no key
lookup or string-catalog reference — so it renders as the literal English
text "Pane N" regardless of the device's locale.

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
- **Storage**: In-memory only, in the registry's own private entry map, for
  the life of the registry instance; nothing in this file writes to disk,
  a persistent key-value store, or a database.
- **Transmission**: None. Nothing in this file makes a network call or sends
  its state outside the process.
- **Retention**: Entries live only as long as the registry instance that
  holds them (per project, per composable-tabs layout); nothing here
  persists across a relaunch.

## Logging

Subsystem: the app's bundle identifier | Category: this component's own name

| Event | Level | Message |
|-------|-------|---------|
| Unregistering the `placeholder` view id | error | `Refusing to unregister {viewID} — every registry resolves it` |
| Building content for an unregistered view id | error | `No view registered for {viewID} — showing a placeholder` |

Both messages interpolate the view id's raw value, logged as public data.

## Platform Notes

- **SwiftUI**: There is no view-controller-returning factory pattern in
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
  It is macOS/AppKit-only: the registry (`ComposableTabsViewRegistry`), the
  context (`ComposableTabsViewContext`), and the placeholder
  (`PlaceholderPaneViewController`) are all `@MainActor`-isolated, which is
  the reason there is no defined cross-thread behavior in Edge Cases. The
  `Factory` typealias returns `NSViewController`; `NSColor`, and
  `NSLayoutConstraint.Priority` (whose `.defaultLow.rawValue + 10` is the
  concrete arithmetic behind **fractioned-priority-boost**) have no UIKit
  equivalent as written. `PlaceholderPaneViewController.init(coder:)` is
  marked unavailable and traps with a fatal error if ever invoked — a
  construction-time compiler/runtime rule of the platform, not an
  independently testable behavior of the registry (`coder-init-unavailable`
  in prior revisions of this recipe). The placeholder's container is a
  plain `NSView` with `wantsLayer = true`; its tint is set on
  `CALayer.backgroundColor` from `palette.chartSeriesNSColors[(paneNumber - 1) % series.count]`;
  its title is a `ThemedLabel` with `textRole: .heading` and
  `role: .primaryText`, so its font and color come from
  `SemanticPalette.font(.heading)` and `palette.nsColor(.primaryText)`, and
  retinting is driven by an `observeTheme` closure rather than a
  declarative environment binding. Logging uses `Loggable`, deriving its
  subsystem from `Bundle.main.bundleIdentifier` and its category from the
  conforming type's name (`ComposableTabsViewRegistry`), and logs through
  `Self.logger.error(...)` with the view id's `rawValue` interpolated at
  `privacy: .public`. A UIKit port would change `Factory` to return
  `UIViewController`, swap `NSColor` for `UIColor` and
  `NSLayoutConstraint.Priority` for `UILayoutPriority`, and would need its
  own container-view-controller embedding (`addChild`/`didMove(toParent:)`)
  in place of whatever AppKit-specific embedding the pane view controller
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

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/ComposableTabs/ComposableTabsViewRegistry.swift` |

## Design Decisions

- **Decision**: The view registry is an instance, obtained per project
  through its composable-tabs layout, not a global singleton or namespace
  of statics.
  **Rationale**: Per the source's own comment, the demo project and a real
  app project need different view sets in the same process, and with global
  registration the last registrant wins.
  **Approved**: pending
- **Decision**: The `placeholder` view id can never be unregistered.
  **Rationale**: Per the source's own comment, every registry must always be
  able to resolve `placeholder`, because losing it would lose the layout
  built on it — a project's stored layout can name `placeholder` explicitly.
  **Approved**: pending
- **Decision**: An unregistered view id resolves to a placeholder rather than
  throwing or trapping, but is still logged at error level.
  **Rationale**: The source's own comment: a project can legitimately name
  content the running app doesn't have (an uninstalled extension), so a hard
  failure would be wrong, but the same situation can also mean spec/registry
  drift, which the source treats as something that should stay visible rather
  than silently rendering "Pane N" with no trace.
  **Approved**: pending
- **Decision**: A factory vends a view controller, never a bare view.
  (AppKit/UIKit.)
  **Rationale**: Per the source's own comment, the pane view controller
  adopts the returned controller as a child, which is what puts the content
  in the responder chain, delivers its appearance callbacks, and keeps it
  alive; a bare view would leave its owner unowned and its appearance
  callback silent.
  **Approved**: pending
- **Decision**: The tree id defaults to the node id when the caller passes
  none, rather than generating a shared default or leaving it unset.
  **Rationale**: Per the source's own comment, a pane with no tree above it
  is its own tree, so its identity degrades to "pairs with nothing" instead
  of "pairs with a shared default every such lone pane would collide on."
  **Approved**: pending
- **Decision**: The context is a value type with a state-store-construction
  method, rather than each factory constructing its own state store.
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
| 1.1.3 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/layout/composable-tabs/. |
