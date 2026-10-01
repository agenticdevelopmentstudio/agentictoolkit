---
id: 29b3f716-ad00-4aff-9dd4-fc7c2e5cf17d
title: Log Viewer
domain: agentictoolkit://cookbook/workspace/logs/log-viewer
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'A themed log view paired with a toolbar: pause, clear, and a themed
  connection-status indicator, hosting any log controller.'
platforms:
- swift
- macos
tags:
- log-view
- toolbar
- status-indicator
- streaming
depends-on:
- agentictoolkit://cookbook/workspace/logs/log-view
related:
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
references: []
approved-by: ''
approved-date: ''
---

# Log Viewer

## Overview

This component pairs a log view with a toolbar strip carrying the controls
a streaming log needs: a Pause button, a Clear button, and a
connection-status indicator (a colored dot plus a text label). It hosts any
log controller, so the source of rows (SSE, file tail, test fixture) is
swappable without changing the component. A subclass or extension point
splices in domain-specific toolbar items via a leading-toolbar-items hook
and an extra-trailing-toolbar-items hook, and can override the minimum
content size and the toolbar height. The log view itself — the scrolling
table of log rows — is a separate component with its own concerns (columns,
row click dispatch, tail-follow scrolling); this recipe covers only what
this component itself renders, lays out, and wires around that hosted view.

## Behavioral Requirements

- **layout-stack**: The component MUST render, top to bottom,
  a toolbar strip, a 1pt divider, and the hosted log view, filling the
  component's root view.
- **container-background**: The component MUST fill the root
  container with the `.windowBackground` theme role.
- **minimum-content-size**: The component MUST constrain the root
  view's width and height to each be at least `minimumContentSize` (default
  `600×400`, overridable).
- **fixed-toolbar-height**: The component MUST give the toolbar strip a fixed
  height equal to `toolbarHeight` (default `40pt`, overridable).
- **divider-below-toolbar**: The component MUST place a 1pt, `.divider`-role
  separator directly below the toolbar, spanning the root view's leading and
  trailing edges.
- **log-view-fills-remaining-space**: The component MUST size the hosted
  log view to fill the root view's leading, trailing, and bottom edges below
  the divider.
- **leading-toolbar-items-rendered**: The component MUST render every view
  returned by the leading-toolbar-items hook, in the order returned, in a
  single horizontal stack (8pt spacing, vertically centered) pinned 12pt
  from the toolbar's leading edge.
- **leading-toolbar-items-overridable**: The default implementation of
  the leading-toolbar-items hook MUST return an empty list; an extension
  point MAY override it to supply additional leading toolbar views.
- **trailing-toolbar-items-rendered**: The component MUST render every view
  returned by the extra-trailing-toolbar-items hook immediately before the
  built-in Pause button, Clear button, status dot, and status label, all in
  one horizontal stack (8pt spacing, vertically centered) pinned 12pt from
  the toolbar's trailing edge.
- **trailing-toolbar-items-overridable**: The default implementation of
  the extra-trailing-toolbar-items hook MUST return an empty list; an
  extension point MAY override it to insert additional trailing toolbar
  views before the built-ins.
- **lifecycle-start**: The component MUST start the controller each
  time the view appears, which may happen more than once over the
  component's lifetime (hide/show, tab switching, window re-ordering).
  The controller's start operation is documented safe to call repeatedly —
  implementations are expected to tear down any previous stream first — so
  no additional guard against repeated appearances is needed here.
- **lifecycle-stop**: The component MUST stop the controller each
  time the view is about to disappear, which — like the view-appeared
  event — may fire more than once over the component's lifetime.
- **indicator-state-refresh**: The component MUST refresh the
  status dot color, status label text/tooltip, and pause button title
  whenever the controller's state-change notification fires.
- **indicator-theme-refresh**: The component MUST refresh the
  status dot color, status label text/tooltip, and pause button title
  whenever the active theme palette changes.
- **connected-indicator**: When the controller's connected flag is `true`,
  the component MUST fill the status dot with the `.success` role color and
  set the status label's text and tooltip to `Connected`.
- **error-indicator**: When the controller's connected flag is `false` and
  its last-error value is set, the component MUST fill the status dot
  with the `.danger` role color and set the status label's text and tooltip
  to that error value verbatim.
- **connecting-indicator**: When the controller's connected flag is `false`
  and its last-error value is unset, the component MUST fill the status dot
  with the `.warning` role color and set the status label's text and tooltip
  to `Connecting…`.
- **connection-state-in-text**: The component MUST expose the
  connection state to assistive technology through text, not color alone —
  the status label's displayed text and tooltip are both set to the same
  string (`Connected` / `Connecting…` / the error text) that also selects
  the dot's color, so the status dot's color is never the only carrier of
  the state.
- **pause-button-title-tracks-pause-state**: The component MUST set the pause
  button's title to `Resume` when the controller's paused flag is `true`,
  and to `Pause` when it is `false`.
- **pause-action**: Clicking the pause button MUST
  call the controller's toggle-pause operation.
- **clear-action**: Clicking the clear button MUST call the controller's
  clear operation.
- **default-start-size-floor**: The root view's initial frame MUST be sized
  to at least `900×600`, or to `minimumContentSize` where that is larger on
  either dimension.
- **status-dot-fixed-size**: The status dot MUST be sized to a fixed
  `8×8pt`, independent of any theme size scaling.

## Appearance

- **Corner radius**: `4pt` on the status dot's backing layer, which on an
  8×8pt square renders as a filled circle. No other view sets a corner
  radius directly; the pause/clear buttons' corner radius (if any) belongs
  to the themed secondary button, a separate themed control.
- **Padding**: Leading toolbar cluster — 12pt from the toolbar container's
  leading edge, vertically centered. Trailing toolbar cluster — 12pt from
  the toolbar container's trailing edge, vertically centered. Within each
  cluster, 8pt spacing between arranged views.
- **Font**: Not applicable directly. The pause/clear buttons (the themed
  secondary button) and the status label (the themed label, constructed
  with a caption text role) resolve their own font from the active
  theme's text roles; the component sets no font of its own.
- **Background**: Root container — `.windowBackground` theme role, via the
  themed background view. The toolbar container has no explicit fill of its
  own. The status dot's fill is a background color driven by connection
  state (`.success` / `.warning` / `.danger`), not a static background.
- **Foreground/Text**: The status label is constructed with the
  secondary-text role, so its text color tracks that role; its text
  content is the same three-way connection string used for the tooltip.
  Pause/Clear button title colors are the themed secondary button's own
  concern, not set by the component.
- **Border**: The divider between the toolbar and the log view is a themed
  separator view with the `.divider` role, a 1pt hairline spanning the root
  view's width.
- **Shadow**: None specified.
- **Min/Max size**: The root view enforces a floor, equal to
  `minimumContentSize` (default `600×400`, overridable), on its own width
  and height. No maximum size is set.
- **Status dot size**: Fixed `8×8pt` (see Behavioral Requirements).

## States

| State | Appearance change |
|-------|------------------|
| Default | Toolbar (leading items, Pause, Clear, status dot, status label) above a 1pt divider above the log view, filling the root view; root view background is `.windowBackground`. |
| Pressed | Not applicable: the pause/clear buttons' pressed-state fill (a swap between the `.elevatedSurface` and `.selection` role colors while pressed) is owned by the themed secondary button, a separate themed control; the component applies no pressed-state styling of its own. |
| Disabled | Not applicable: the component never disables the pause or clear button; both remain enabled regardless of connection, pause, or error state. |
| Focused | Not applicable: the component sets no custom focus-ring appearance on any control; whatever focus ring the platform draws by default for a standard button is unmodified. |
| Loading | Represented by the Connecting state below; there is no separate loading spinner or progress indicator. |
| Connected | Connected flag `true`: status dot fills with the `.success` role color; status label text and tooltip read `Connected`. |
| Connecting | Connected flag `false` and no last-error value: status dot fills with the `.warning` role color; status label text and tooltip read `Connecting…`. |
| Error | Connected flag `false` and a last-error value present: status dot fills with the `.danger` role color; status label text and tooltip read the error string verbatim. |
| Paused | Paused flag `true`: pause button title reads `Resume`. Paused flag `false`: pause button title reads `Pause`. |

## Accessibility

- Pause and Clear are buttons (via the themed secondary button) constructed
  with a non-empty title (`Pause`/`Resume`, `Clear`), so the platform's
  default accessibility exposes each button's own title text as its
  accessible name; no explicit accessibility label or identifier call is
  made.
- Both buttons are standard buttons in the default key-view/tab-focus loop,
  so they receive Tab-key focus and Space/Return activation from the
  platform's ordinary focus and activation handling; no custom key
  equivalent is assigned to either.
- The status dot is a plain view with no accessibility role, label, or
  identifier of its own; its state is exposed through text instead (see
  **connection-state-in-text**).
- A connection-state change rewrites the status label's text, but no
  accessibility-announcement call accompanies it, so a screen-reader user
  currently gets no announcement when the stream connects, reconnects, or
  fails.
- Not applicable: minimum tap target. This is a pointer-driven control,
  not a touch surface, so the template's 44×44pt touch-target guidance
  does not apply; the toolbar buttons get no explicit width/height beyond
  the themed secondary button's own title-driven intrinsic size.
- **contrast**: NEEDS REVIEW: Not implemented in source. The status dot's
  `.success`/`.warning`/`.danger` fills and the status label's
  `.secondaryText`-on-`.windowBackground` text pairing resolve from
  whichever theme palette is active at runtime, so whether a given
  theme's resolved color pair meets a target contrast ratio (3:1 for the
  non-text dot, 4.5:1 for the caption-sized label text) can't be determined
  by inspecting the component alone; auditing each concrete palette's
  resolved colors against the platform's contrast guidance would settle it.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| log-view-controller-001 | layout-stack | Load the view. | Toolbar, then a 1pt divider, then the log view, stacked top to bottom, filling the root view. |
| log-view-controller-002 | container-background | Load the view, inspect the root view's background. | Background color equals the current theme's `.windowBackground` role color. |
| log-view-controller-003 | minimum-content-size | Load the view with the default `minimumContentSize` (`600×400`), then attempt to resize the root view's frame to `300×200`. | The root view's effective width and height never fall below `600×400`. |
| log-view-controller-004 | fixed-toolbar-height | Load the view. | The toolbar view's height constraint equals `toolbarHeight` (`40pt` by default). |
| log-view-controller-005 | divider-below-toolbar | Load the view, inspect the divider view. | A 1pt-tall view filled with the `.divider` role color sits directly below the toolbar, pinned to the root view's leading and trailing edges. |
| log-view-controller-006 | log-view-fills-remaining-space | Load the view, resize the root view. | The hosted log view fills the area below the divider, pinned to the root view's leading, trailing, and bottom edges. |
| log-view-controller-007 | leading-toolbar-items-rendered | Override the leading-toolbar-items hook to return two views, load the view. | Both views appear, in the order returned, in a horizontal stack pinned 12pt from the toolbar's leading edge. |
| log-view-controller-008 | leading-toolbar-items-overridable | Construct the base component (no override), load the view. | The leading stack contains zero extension-supplied views. |
| log-view-controller-009 | trailing-toolbar-items-rendered | Override the extra-trailing-toolbar-items hook to return one view, load the view. | That view appears before Pause, Clear, the status dot, and the status label, in that left-to-right order, in the trailing stack. |
| log-view-controller-010 | trailing-toolbar-items-overridable | Construct the base component (no override), load the view. | The trailing stack contains exactly Pause, Clear, the status dot, and the status label — no extra views. |
| log-view-controller-011 | lifecycle-start | Add the component's view to a window and let it appear. | The controller's start operation is called exactly once. |
| log-view-controller-012 | lifecycle-stop | With the view appeared, remove it from the window (trigger the view-about-to-disappear event). | The controller's stop operation is called exactly once. |
| log-view-controller-013 | indicator-state-refresh | Load the view, then set the controller's connected flag to false, its paused flag to true, and its last-error value to `Disconnected`, then fire the controller's state-change notification. | The status dot fills `.danger`, the status label text/tooltip read `Disconnected`, and the pause button title reads `Resume` — all three indicators reflect the new combined state. |
| log-view-controller-014 | indicator-theme-refresh | Load the view, then trigger the active-theme-changed notification the component observes to re-apply the palette. | The status dot, status label, and pause button title are repainted using the new theme's role colors/fonts, still reflecting the current controller state. |
| log-view-controller-015 | connected-indicator | Set the controller's connected flag to true, trigger a refresh. | Status dot color equals the `.success` role color; status label text and tooltip equal `Connected`. |
| log-view-controller-016 | error-indicator | Set the controller's connected flag to false and its last-error value to `Disconnected`, trigger a refresh. | Status dot color equals the `.danger` role color; status label text and tooltip equal `Disconnected`. |
| log-view-controller-017 | connecting-indicator | Set the controller's connected flag to false and clear its last-error value, trigger a refresh. | Status dot color equals the `.warning` role color; status label text and tooltip equal `Connecting…`. |
| log-view-controller-018 | pause-button-title-tracks-pause-state | Set the controller's paused flag to true, trigger a refresh; then set it to false and refresh again. | Pause button title reads `Resume`, then `Pause`. |
| log-view-controller-019 | pause-action | Click the pause button. | The controller's toggle-pause operation is called exactly once. |
| log-view-controller-020 | clear-action | Click the clear button. | The controller's clear operation is called exactly once. |
| log-view-controller-022 | default-start-size-floor | Construct the component with default `minimumContentSize`, load the view, inspect the root view's initial frame. | Initial frame size is at least `900×600`. |
| log-view-controller-023 | status-dot-fixed-size | Load the view under a theme with an increased size scale. | The status dot's width and height constraints remain `8pt` each, unaffected by size scaling. |
| log-view-controller-024 | connection-state-in-text | Trigger the connected, connecting, and error states in turn. | The status label's text/tooltip read `Connected`, `Connecting…`, and the error string respectively — never the same string across states, and never conveyed by dot color alone. |
| log-view-controller-025 | lifecycle-start, lifecycle-stop | Add the component's view to a window, let it appear, remove it from the window (disappear), then re-add it and let it appear again. | The controller's start operation is called twice and its stop operation is called once, in appear → disappear → appear order. |
| log-view-controller-026 | default-start-size-floor | Override `minimumContentSize` to `1000×700` (larger than `900×600` on both dimensions), load the view, inspect the root view's initial frame. | Initial frame size equals `1000×700`, not `900×600`. |

## Edge Cases

- **Null/empty input**: Whether the controller's last-error value is unset
  or set to a string is the sole discriminator, alongside the connected
  flag, for which of the three status branches (`connected-indicator` /
  `error-indicator` / `connecting-indicator`) applies; an empty string for
  the last-error value is treated as set and so is displayed verbatim as
  the error text — the same branch as any other set value. The
  leading-toolbar-items and extra-trailing-toolbar-items hooks returning an
  empty list (the default) is the normal case, not a special-cased branch:
  the corresponding stack view simply arranges zero subviews.
- **Boundary values**: An extension point overriding `minimumContentSize`
  or `toolbarHeight` with a value of zero or negative is not guarded
  against; the resulting layout constraints are built from that zero or
  negative constant and passed through to the layout system as-is. The
  resulting layout is undefined — this is an unguarded input, not
  documented behavior, and no precondition or assertion rejects it.
- **Concurrent access**: The controller contract and this component are
  both confined to the primary UI thread, and the controller's
  state-change notification is likewise required to fire there, so state
  refreshes are always serialized on the primary thread; there is no
  cross-thread mutation path to define behavior for.
- **Error states**: The controller's last-error string is displayed
  verbatim with no truncation, retry affordance, or dismiss action wired
  anywhere; clicking Pause or Clear while an error is present still calls
  the toggle-pause/clear operation unconditionally — neither call is gated
  on connection or error state.
- **Offline/disconnected state**: The Connecting state (connected flag
  `false`, no last-error value) is this component's sole representation of
  "not yet connected" or "reconnecting"; it renders identically whether the
  transport has never connected or has dropped and is retrying, because the
  controller contract exposes no separate signal for that distinction.
  Actual reconnecting/backoff behavior belongs to the injected controller
  implementation (SSE/HTTP/file-tail), a separate component out of this
  recipe's scope — the component only reads the three properties
  (connected, paused, last-error) it is given.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `controller` | the log controller | required (no default) | Owns the log's provider plus connection/pause/error state; the component starts/stops it and reads its state to drive the toolbar. See the Log Controller Contract below. |
| `minimumContentSize` | size (width × height) | `600×400` | Overridable floor enforced as constraints on the root view's own width/height. |
| `toolbarHeight` | number | `40` | Overridable fixed height of the toolbar strip above the log view. |
| leading-toolbar-items hook | a function returning a list of views | `[]` | Overridable hook for extension-supplied views placed left of the built-in controls. |
| extra-trailing-toolbar-items hook | a function returning a list of views | `[]` | Overridable hook for extension-supplied views inserted before the built-in Pause/Clear/status cluster. |
| (fixed, not an extension hook) | size (width × height) | `900×600` | Non-overridable floor combined with `minimumContentSize` (the larger of the two, per dimension) when computing the root view's initial frame; see **default-start-size-floor**. |

### Log Controller Contract

The log controller is a contract confined to the primary UI thread. The
component reads and calls:

| Member | Type | Notes |
|--------|------|-------|
| `provider` | the log provider | Backing store handed to the hosted log view. |
| `isConnected` | boolean | Selects the connected/connecting branch of the status dot and label. |
| `isPaused` | boolean | Drives the pause button's title. |
| `lastError` | optional text | Displayed verbatim in the status label/tooltip when set and `isConnected` is `false`. |
| `onStateChange` | an optional callback, invoked on the primary thread | Assigned at construction to trigger the status-indicator refresh. |
| `start()` | operation | Called when the view appears; documented safe to call repeatedly. |
| `stop()` | operation | Called when the view is about to disappear. |
| `togglePause()` | operation | Called by the pause button. |
| `clear()` | operation | Called by the clear button. |

## Deep Linking

Not applicable: the component contains no URL-scheme or route
handling of any kind.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none defined in source) | `Pause` | Pause button's initial title, and its title whenever the paused flag is `false`. |
| (none defined in source) | `Resume` | Pause button's title whenever the paused flag is `true`. |
| (none defined in source) | `Clear` | Clear button's title, a literal string. |
| (none defined in source) | `Connected` | Status label text/tooltip when the connected flag is `true`. |
| (none defined in source) | `Connecting…` | Status label text/tooltip when the connected flag is `false` and no last-error value is set. |

`Pause`, `Resume`, `Clear`, `Connected`, and `Connecting…` are all assigned
as plain string literals directly to the button's title or the label's
displayed text, not through a localization-key mechanism, so the component
is unlocalized as written: it defines no string-key scheme, and wiring one
in is the host app's localization owner's responsibility. (The last-error
string is displayed as-is and is excluded from this table: its content and
any localization are the injected controller implementation's concern, not
the component's.)

## Accessibility Options

- **Reduce Motion**: Not applicable. The component contains no animation —
  title changes, dot color changes, and layout all happen through
  immediate property assignment and layout constraints; there is no
  transition or motion effect to reduce.
- **Increase Contrast**: Not applicable at this component's level. Every
  color the component uses comes from a theme-palette role
  (`.windowBackground`, `.divider`, `.success`, `.warning`, `.danger`,
  `.secondaryText`); the component contains no branch on an
  increase-contrast accessibility setting, so any contrast adaptation
  would live in the theme/palette system, not here.
- **Differentiate Without Color**: Already satisfied. The connection state
  is conveyed through the status label's text (`Connected` / `Connecting…`
  / the error string) in addition to the status dot's color (see
  **connection-state-in-text** above), so no state in this
  component is communicated by color alone.

## Feature Flags

Not applicable: the component contains no feature-flag or
build-configuration check of any kind.

## Analytics

Not applicable: the component contains no analytics or
event-tracking calls.

## Privacy

- **Data collected**: None by this component directly. It displays
  whatever connection state, error text, and rows the injected
  controller/log view provide; it captures no input beyond Pause and
  Clear button clicks.
- **Storage**: This component writes nothing to disk or to any settings
  store.
- **Transmission**: None. The component makes no network calls
  itself — any transport (SSE, HTTP, file-tail) belongs to the injected
  controller implementation, a separate component out of this recipe's
  scope.
- **Retention**: Not applicable. This component keeps no state of its own
  beyond the controller/view references it is constructed with.

## Logging

Not applicable: the component contains no logging calls of any kind.

## Platform Notes

- **SwiftUI**: A SwiftUI port would express the toolbar as an `HStack`
  (leading items, a `Spacer()`, then Pause/Clear `Button`s, a small
  `Circle().fill(...)` for the status dot, and `Text` for the label) above
  a `Divider()` above the hosted log view, with the state-indicator refresh
  expressed as a computed `(Color, String)` derived from
  `@ObservedObject`/`@Published` controller state, and the start/stop calls
  moved to `.onAppear`/`.onDisappear`.
- **Compose**: Start from a `Column` with a `Row` toolbar (leading items, a
  `Spacer`, `TextButton`s for Pause/Clear, a small circular `Box` for the
  dot, `Text` for the label), a `HorizontalDivider`, then the hosted log
  composable below. `isConnected`/`lastError`/`isPaused` become `StateFlow`
  fields on a `ViewModel`; `start()`/`stop()` map to a `DisposableEffect`
  keyed on composition entering/leaving, matching the view-appeared/
  view-about-to-disappear lifecycle.
- **React/Web**: The toolbar becomes a flex row (a leading slot, a flexible
  spacer, Pause/Clear `<button>`s, a small colored `<span>`/`<div>` circle
  for the dot, a status `<span>` for the label) above a `<hr>`/border-top
  divider above the log component. `isConnected`/`lastError`/`isPaused`
  become props or store fields driving the same three-way branch;
  `start()`/`stop()` map to a `useEffect` mount/unmount pair opening and
  closing the underlying stream (SSE/WebSocket).
- **AppKit / UIKit**: This is the source platform (AppKit/macOS). The
  component is `NSViewController`-based (`LogViewController`), pairing an
  `NSView`-based log view (`LogView`) with an `NSStackView` toolbar; the
  themed secondary button, themed separator view, themed label, and themed
  background view are `ThemedSecondaryButton`, `ThemedSeparatorView`,
  `ThemedLabel`, and `ThemedBackgroundView` respectively. The
  leading/trailing toolbar-item hooks are `leadingToolbarItems()` and
  `extraTrailingToolbarItems()`; the start/stop lifecycle hooks are
  `viewDidAppear`/`viewWillDisappear`. On iOS, `NSViewController` becomes
  `UIViewController`, `NSView`/`NSStackView` become `UIView`/`UIStackView`,
  and the four themed view types need UIKit counterparts;
  `viewDidAppear`/`viewWillDisappear` map directly to the
  identically-named `UIViewController` lifecycle methods, so the
  start/stop-on-lifecycle behavior ports unchanged. The log controller
  contract, `LogController`, is a `@MainActor`-isolated protocol, this
  component is itself `@MainActor`, and its `onStateChange` member is
  typed `(@MainActor () -> Void)?`, so the state refreshes described under
  Edge Cases (Concurrent access) are serialized via Swift's actor
  isolation. The reference implementation also marks its `NSCoder`-based
  initializer (`init(coder:)`) unavailable at compile time and calls
  `fatalError` if it is ever invoked at runtime — a Cocoa/Interface-Builder
  construction rule with no counterpart on platforms without an
  NSCoder-based storyboard/XIB system: a call to construct the controller
  that way fails to compile, or hits that `fatalError` at runtime if the
  unavailability check is somehow bypassed.
- **WinUI 3**: Model the whole component as a `UserControl`/`Page` whose
  root `Grid` has two `RowDefinition`s — a toolbar row fixed at
  `toolbarHeight`, and a log row set to `*` — separated by a
  `<Border BorderThickness="0,0,0,1">` standing in for the themed separator
  view. The toolbar is a `Grid` (or a `DockPanel`-style pair of
  `StackPanel`s) with one `HorizontalAlignment="Left"` panel for the
  leading toolbar items and one `HorizontalAlignment="Right"` panel
  holding the extra-trailing items, Pause/Clear `Button`s, a small
  `Ellipse` (`Width="8" Height="8"`, `Fill` bound to a `SolidColorBrush`
  chosen by the same three-way connection state) for the status dot, and a
  `TextBlock` whose `Text` and `ToolTipService.ToolTip` both bind to that
  same state string. Drive the `Connected`/`Connecting`/`Error` visuals and
  the Pause/Resume title through `VisualStateManager` states toggled from a
  bound view-model exposing the same connected/paused/last-error surface
  as the log controller contract, and start/stop the transport from the
  page's `Loaded`/`Unloaded` events, mirroring the view-appeared/
  view-about-to-disappear lifecycle.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/LoggingWindow/LogViewController.swift` |

## Design Decisions

**Decision**: Route both theme-palette changes and controller state changes
through the same status-indicator refresh, rather than painting theme
colors in a separate observer callback.
**Rationale**: The source comment states the status dot's color and the pause
button's title both depend on controller state, so "a theme change and a
state change have to land in the same place or one overwrites the other
with the previous theme's colours."
**Approved**: pending

**Decision** (AppKit/macOS): Use `ThemedSecondaryButton` for Pause and Clear
instead of `ThemedButton` (the accent-filled pill button).
**Rationale**: The source comment states two accent-filled pills in a toolbar
"would claim more emphasis than a log's controls deserve," so lower-emphasis
secondary styling was chosen deliberately.
**Approved**: pending

**Decision** (AppKit/macOS): Use `ThemedSeparatorView` for the toolbar/log
divider instead of an `NSBox` separator.
**Rationale**: The source comment states an `NSBox` separator "draws a system
hairline, which is the one line in this window the palette could not
reach," so a themed view was substituted to keep the divider on-palette.
**Approved**: pending

**Decision**: Enforce `minimumContentSize` as constraints on the root
view's own width/height.
**Rationale**: The source comment states the hosted log view has no
intrinsic width, so without a floor the window collapses the component's
view to its fitting size after its async layout pass — "a 1pt-wide
window."
**Approved**: pending

**Decision** (AppKit/macOS): Give the pause/clear buttons no explicit
width/height constraint.
**Rationale**: The source comment states `ThemedSecondaryButton` measures the
title it is about to draw, in the theme's own button font, and grows past
its stock 68×22 minimum rather than clipping at a large size scale.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | passed | Accessibility |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | Accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | Accessibility |
| [string-externalization](agenticdevelopercookbook://compliance/internationalization#string-externalization) | failed | Internationalization |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |
| [rtl-layout-support](agenticdevelopercookbook://compliance/internationalization#rtl-layout-support) | passed | Internationalization |
| [text-expansion-tolerance](agenticdevelopercookbook://compliance/internationalization#text-expansion-tolerance) | passed | Internationalization |

Statuses rest on: Pause/Clear exposing their `NSButton` title as an accessible name and sitting in the standard key-view loop (screen-reader-support, keyboard-navigable); the status dot/label pairing's resolved contrast being undeterminable from `LogViewController.swift` alone, per the open question on `contrast` (contrast-ratio); `Pause`/`Resume`/`Clear`/`Connected`/`Connecting…` being `String` literals with no key scheme (string-externalization, no-hardcoded-strings); and the toolbar's `leadingAnchor`/`trailingAnchor` constraints plus unconstrained button widths accommodating RTL mirroring and translated-text growth (rtl-layout-support, text-expansion-tolerance).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: renamed verb-phrase requirements to subject nouns; moved connection-state-in-text into Behavioral Requirements with a new vector; documented start()/stop() lifecycle idempotency with a new vector; made toolbar-item-overridable requirements MUST-default/MAY-override; corrected vector precision (003, 013, 014) and named the real ThemeManager/ThemePaletteObserver mechanism; added the 900×600 start-size floor and a LogController contract table to Configuration; reworded the boundary-values edge case away from an RFC 2119 keyword; replaced "this file"/"in source" phrasing with behavior descriptions outside Design Decisions; reformatted Design Decisions to the bold convention; populated the Compliance table; moved the platform-design-languages reference to related and added log-view to depends-on; swapped the redundant macos tag for streaming. |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/logs/. |
