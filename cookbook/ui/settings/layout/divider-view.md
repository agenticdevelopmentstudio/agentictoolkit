---
id: 18ad68ea-187b-463d-9f5c-b855b9bc36a9
title: Divider View
domain: agentictoolkit://cookbook/ui/settings/layout/divider-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A fixed-height divider line for a settings window, colored from
  the theme's divider role and kept live on every theme or scope change.
platforms:
- swift
- macos
tags:
- ui
- divider
- settings
depends-on: []
related:
- agentictoolkit://cookbook/ui/settings/rows/button-view
references: []
approved-by: ''
approved-date: ''
---

# Divider View

## Overview

The divider view is a fixed-height, theme-colored hairline separator for a
settings window. It belongs to the same family of settings-row views as
its sibling button view, and draws a single divider line wherever a
settings panel places it. It has no caller-configurable options: it takes
no construction parameters, its height is fixed to the divider-thickness
design token, and its color always tracks the current theme's divider
role, reapplied on every theme or scope change.

## Behavioral Requirements

- **constrains-height-to-divider-thickness**: The component MUST fix its
  height to the divider-thickness design token (1.0pt) at initialization.
- **applies-divider-color-on-init**: The component MUST apply the resolved
  palette's divider color to its fill immediately upon construction.
- **resolves-color-through-nearest-theme-scope**: Whenever the component
  applies its divider color (on initialization, on a theme change, on its
  own scope's change, or on a repaint), it MUST resolve the color from the
  nearest enclosing theme scope's palette — walking outward from itself to
  find the nearest ancestor declaring a scope, and falling back to the
  app-wide scope when none exists.
- **reapplies-divider-color-on-theme-change**: The component MUST reapply
  its divider color from the resolved palette whenever the active theme
  changes.
- **reapplies-divider-color-on-own-scope-change**: The component MUST
  reapply its divider color from the resolved palette when its own
  resolved theme scope changes.
- **ignores-other-scope-change-notifications**: The component MUST NOT
  reapply its divider color when a theme scope other than its own resolved
  scope changes.
- **retains-theme-observer-for-view-lifetime**: The component's
  theme-change and scope-change repaint subscriptions MUST remain active
  for as long as the component exists, with no separate reference to an
  observer required from the caller.
- **ignores-settings-layout-changes**: The component's height MUST NOT
  update after initialization if the divider-thickness design token
  changes later; the height stays fixed to the value read once at
  construction time.

## Appearance

- **Corner radius**: None; the component never applies a corner radius.
- **Padding**: Not set by the component itself; it has no internal content
  to pad. The space around the line is entirely up to whatever container
  lays it out.
- **Font**: Not applicable — the component renders no text or other
  font-dependent content.
- **Background**: The component's fill color is set to the resolved theme
  scope's divider role. This is reapplied on initialization, on every
  theme change, and on the component's own scope change (and, in the
  source implementation, on every native repaint pass — see Platform
  Notes).
- **Foreground/Text**: Not applicable — the component has no text or
  foreground content; its fill is its only visual surface.
- **Border**: None; the component never applies a border.
- **Shadow**: None; the component never applies a shadow.
- **Min/Max size**: Height fixed at 1.0pt (the divider-thickness design
  token); no width constraint of its own — width is determined entirely
  by whatever layout the container applies.

## States

| State | Appearance change |
|-------|------------------|
| Default | Renders as a solid fill, 1.0pt tall, colored by the resolved theme scope's divider role; there is no other state. |
| Pressed | Not applicable: the component wires no interaction handling of any kind — it cannot receive or respond to a press. |
| Disabled | Not applicable: the component has no enabled/disabled concept — an enabled/disabled state is never read or set. |
| Focused | Not applicable: the component never participates in keyboard focus — it cannot become focused or show a focus ring. |
| Loading | Not applicable: the component performs no asynchronous work and defines no loading indicator. |

## Accessibility

- **Role/trait**: Not applicable — the component is a purely decorative
  separator; it sets no custom accessibility role, label, or element
  flag, so it exposes nothing distinguishable to assistive technology
  beyond the visual boundary it draws.
- **Accessibility exposure**: Not exposed — the component is a plain
  container view that never marks itself as an accessibility element, and
  is not one by default, so assistive technology skips the decorative
  hairline.
- **Label requirements**: Not applicable — the component renders no text
  and carries no semantic content of its own to name.
- **Announce state changes**: Not applicable — the component defines no
  state that changes (see States); there is nothing for an announcement
  to report.
- **Minimum tap target**: Not applicable — the component is not an
  interactive control; it wires no interaction handling, so it has no tap
  target to size.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| divider-view-001 | constrains-height-to-divider-thickness | Any initialized component, attached on screen | The component's height resolves to `1.0` (the divider-thickness design token) |
| divider-view-002 | applies-divider-color-on-init | Construct the component while a known palette is active, before it is attached to any container | The component's fill color equals the palette's divider color immediately after construction |
| divider-view-003 | resolves-color-through-nearest-theme-scope | Add the component as a descendant of a container that declares its own theme scope, whose palette differs from the app-wide scope's | The divider's applied color matches the ancestor scope's divider role, not the app-wide scope's |
| divider-view-004 | reapplies-divider-color-on-theme-change | Construct the component, switch the active theme, then trigger a theme-change notification | The component's fill color updates to the new theme's divider role |
| divider-view-005 | reapplies-divider-color-on-own-scope-change | Construct the component resolved to scope A; change scope A's underlying theme/palette to one whose divider role differs from its previous value, then trigger a scope-change notification for scope A | The component's fill color updates to scope A's new divider role |
| divider-view-006 | ignores-other-scope-change-notifications | Construct the component resolved to scope A; trigger a scope-change notification for a different scope B | The component's fill color does not change |
| divider-view-007 | retains-theme-observer-for-view-lifetime | Construct the component, keep only the component itself (no separate reference to any observer), then trigger a theme-change notification | The component's fill color still updates, showing its internal subscriptions survived |
| divider-view-008 | ignores-settings-layout-changes | Construct the component, attach it on screen, then change the divider-thickness design token's underlying value | The component's existing height remains unchanged at the value read during construction; it does not update to the new value |

## Edge Cases

- **Null/empty input**: Not applicable — the component takes no
  construction parameters (see Platform Notes for the source
  implementation's inherited-initializer handling), so there is no
  caller-supplied value to be null or empty.
- **Boundary values**: the divider-thickness design token (1.0pt) is read
  exactly once, at construction time. The component never subscribes to
  later changes in that token, so if a caller mutates the token's
  underlying value after a component instance already exists, that
  instance's height does not update — it stays at whatever value was
  current when it was constructed (see **ignores-settings-layout-changes**).
  This staleness is a genuine limitation, also recorded in Design
  Decisions.
- **Concurrent access**: Not applicable — the component is confined to a
  single UI thread (see Platform Notes), so construction and all of its
  color-repaint paths are serialized to that thread.
- **Error states**: Not applicable — the component has no dependency on
  network, database, or file-system access, and defines no error path of
  any kind.
- **Offline/disconnected state**: Not applicable — the component performs
  no networking.
- **No theme system available**: the resolved scope's palette falls back
  to a built-in default theme's palette when no theme system is active
  (e.g. a preview or a unit test with no app host) — the component paints
  with that fallback's divider color rather than crashing or leaving its
  fill transparent.
- **No enclosing theme scope**: the ancestor walk finds no container
  declaring a scope and falls back to the app-wide scope, so the
  component paints with the app-wide palette rather than failing to
  resolve a color.

## Configuration

Not applicable: the component exposes no caller-configurable options; it
takes no construction parameters (see Platform Notes for the source
implementation's inherited-initializer handling).

## Deep Linking

Not applicable: the component is a decorative layout element with no
navigable identity of its own — it has no route, screen, or resource that
a deep link could target.

## Localization

Not applicable: the component renders no text and defines no string keys
of its own.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: the component applies no animation, transition, or motion effect of its own; each of its repaint paths assigns its fill color directly, with no animation wrapping it. |
| Increase Contrast | Not applicable: the component sets no custom Increase Contrast handling of its own; the color it paints comes entirely from the resolved palette's divider role, and any Increase Contrast adaptation is the palette/theme system's responsibility, not something this component could opt into or out of. |
| Differentiate Without Color | Not applicable: the component conveys no state or meaning through color — it renders exactly one visual presentation, a colored hairline, with no color-coded distinction for an alternate cue to replace. |

## Feature Flags

Not applicable: no feature-flag check applies; the component always
constructs and applies its fill color unconditionally.

## Analytics

Not applicable: the component emits no analytics, tracking, or telemetry
of its own, and has no user interaction to report.

## Privacy

- **Data collected**: None. The component holds only its internal
  theme-observing state; it holds no caller-supplied data at all.
- **Storage**: Not applicable — the component performs no persistence of
  any kind.
- **Transmission**: Not applicable — the component performs no network or
  IPC calls.
- **Retention**: Not applicable — nothing is retained beyond the
  component instance's own lifetime.

## Logging

Not applicable: the component performs no logging of its own.

## Platform Notes

- **SwiftUI**: `Divider()` is the built-in equivalent for the common case, but it paints the system separator color rather than a theme-supplied one. To match this source's per-theme `dividerColor`, use a `Rectangle().fill(...).frame(height: 1)` sized from the equivalent of `SettingsLayout.default[.dividerThickness]`, reading the fill color from the app's own palette environment value (SwiftUI's `@Environment` mechanism is the natural analog of this source's superview-walking `resolvedThemeScope`) so the color updates automatically when that environment value changes, with no manual notification subscription needed.
- **Compose**: Use `HorizontalDivider()` — Material 3's replacement for the deprecated `Divider()` — (or a plain `Box(Modifier.height(1.dp).fillMaxWidth().background(...))` for full control over the fixed thickness) reading its color from a `CompositionLocal` exposing the current palette. Compose's own recomposition on `CompositionLocal` change is the equivalent of this source's manual repaint paths — no observer object or notification bookkeeping is needed.
- **React/Web**: An `<hr>` styled with `border: none; height: 1px; background-color: var(--divider-color);` (or a plain `<div>` of the same height), where `--divider-color` is set by whatever theme-provider component wraps the tree. A CSS custom property's cascade already repaints on a theme-class change with no JS callback required, standing in for both the notification-driven repaint and the redundant repaint override in the source.
- **AppKit / UIKit (source)**: `DividerView.swift`
  (`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/DividerView.swift`)
  is macOS-only (`import AppKit`) — there is no iOS/UIKit counterpart in
  this file. It is an `NSView` nested in the `ComposableSettings`
  namespace, declared `@MainActor` (the source's implementation of thread
  confinement, formerly the normative requirement `confines-to-main-actor`,
  enforced at compile time by Swift's isolation checking) and conforming
  to `SettingsViewProtocol`, the marker protocol every settings-row view
  in this system adopts alongside its sibling `ButtonView` (formerly the
  normative requirement `conforms-to-settings-view-protocol`). It disables
  `translatesAutoresizingMaskIntoConstraints` on itself (formerly
  `disables-autoresizing-mask-translation`) and sets `wantsLayer = true`
  so it can be colored via its backing `CALayer` (formerly
  `enables-layer-backing`); its only content is a solid-fill
  `CALayer.backgroundColor`, sized by one Auto Layout height constraint
  and never given a width constraint of its own. Its only public
  initializer is a parameterless `convenience init()` that calls
  `self.init(frame: .zero)` (formerly `convenience-init-uses-zero-frame`);
  the inherited `init(frame:)` accepts but discards its `frameRect`
  argument, always yielding a `.zero` frame regardless of the
  caller-supplied rect (formerly `ignores-explicit-frame`), because the
  view positions itself entirely through Auto Layout; `required
  init?(coder:)` traps via `fatalError` with the message `init(coder:) has
  not been implemented` rather than returning a usable instance (formerly
  `rejects-coder-initializer`). Repainting is implemented through
  `ThemePaletteObserver` plus a redundant `updateLayer()` override that
  re-reads `resolvedThemeScope.palette.dividerColor` on every
  AppKit-triggered layer update (formerly the MAY-level requirement
  `reapplies-divider-color-on-layer-update`; see Design Decisions for why
  this second path exists alongside the notification-driven one). A UIKit
  port to `UIView`/`CALayer` would use `UIView.layer` directly (always
  present, unlike `NSView.layer?`) and needs no Dynamic Type
  accommodation, since a divider has no text.
- **WinUI 3**: Use a `Rectangle` (or a `Border` with only a bottom `BorderThickness`) with `Height="1"` bound to the equivalent of `SettingsLayout.Default[LayoutKey.DividerThickness]`, and `Fill`/`BorderBrush` bound to a `SolidColorBrush` `ThemeResource` keyed to the app's current theme's divider color — either adopting Fluent 2's own `DividerStrokeColorDefaultBrush` token, or a custom resource mirroring `palette.dividerColor` if the port keeps its own palette abstraction. Repaint on theme change by handling `FrameworkElement.ActualThemeChanged` (WinUI's per-element equivalent of `ThemeManager.didChangeNotification`) rather than a global notification; there is no WinUI analog to the source's `updateLayer()` override, since a `ThemeResource` brush lookup already re-resolves automatically when the active theme or resource dictionary changes, so that second repaint path can be dropped as redundant in the port.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/DividerView.swift` |

## Design Decisions

**Decision** (AppKit): `init(frame frameRect: NSRect)` discards its `frameRect` argument and always calls `super.init(frame: .zero)`.
**Rationale**: `DividerView` positions itself entirely through Auto Layout (`translatesAutoresizingMaskIntoConstraints = false` plus the activated height constraint). The inherited frame-based initializer exists only so `DividerView` can still be constructed through it at all; the source ignores the caller-supplied rect rather than reconciling it with the Auto Layout constraints that take over immediately afterward.
**Approved**: pending

**Decision** (AppKit): The divider color is applied through two independent paths — once via `ThemePaletteObserver`'s notification-driven callback, and again via an `updateLayer()` override that re-reads `resolvedThemeScope.palette.dividerColor` on every AppKit-triggered layer update.
**Rationale**: Not explained in source comments; there are none on this override. The two paths are not mutually exclusive — `updateLayer()` covers any AppKit-invoked layer refresh that does not route through either of `ThemePaletteObserver`'s two notifications, at the cost of reassigning `backgroundColor` a second time on paths that do overlap (e.g. a theme change that also triggers `updateLayer()`). This redundancy is real technical debt in the source, recorded here rather than smoothed into a single described path; **reapplies-divider-color-on-layer-update** states it as a MAY rather than a MUST so a port is not obligated to reproduce the redundancy.
**Approved**: pending

**Decision**: `SettingsLayout.default[.dividerThickness]` is read exactly once, into an `NSLayoutConstraint` activated at `init` time, even though `SettingsLayout` is `Observable`/`@Published`.
**Rationale**: Not explained in source comments. `DividerView` never subscribes to `SettingsLayout.default`'s publisher, so an existing `DividerView` does not resize if that value is later changed at runtime (see **ignores-settings-layout-changes** and Edge Cases → Boundary values). Recorded here as a known staleness limitation rather than an intended contract, since nothing in the source suggests it was deliberate.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | Accessibility |

`contrast-ratio` is partial: `DividerView` applies `dividerColor` exactly as the palette defines it and never computes a color itself, but this file contains no measured contrast ratio of `dividerColor` against the settings background it is drawn over — that verification is the palette/theme's responsibility, not something confirmable from `DividerView.swift` alone.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: restated three implementation-detail requirements as observable outcomes, weakened the redundant layer-update repaint to a MAY, added an ignores-settings-layout-changes requirement with a matching vector, tightened four ambiguous test vectors and labeled one as a static/compile-time check, fixed Design Decisions approval formatting, marked contrast-ratio partial, swapped the deprecated Compose Divider() for HorizontalDivider(), added the sibling Button View recipe to related, and stated that the decorative hairline stays out of the accessibility tree; removed Compliance rows for checks absent from the cookbook catalog |
| 1.1.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/settings/layout/. |
</content>
