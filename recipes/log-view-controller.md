---
id: 29b3f716-ad00-4aff-9dd4-fc7c2e5cf17d
title: Log View Controller
domain: agentictoolkit://recipes/log-view-controller
type: ingredient
version: 1.1.1
status: review
language: en
created: '2026-09-23'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'AppKit view controller pairing a themed LogView with a toolbar: pause, clear,
  and a themed connection-status indicator, hosting any LogController.'
platforms:
- swift
- macos
tags:
- log-view
- toolbar
- status-indicator
- view-controller
- streaming
depends-on:
- agentictoolkit://recipes/log-view
related:
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
references: []
approved-by: ''
approved-date: ''
---

# Log View Controller

## Overview

`LogViewController` is an `NSViewController` that pairs a `LogView` with a
toolbar strip carrying the controls a streaming log needs: a Pause button, a
Clear button, and a connection-status indicator (a colored dot plus a text
label). It hosts any `LogController`, so the source of rows (SSE, file tail,
test fixture) is swappable without changing the component. Subclasses splice in
domain-specific toolbar items via `leadingToolbarItems()` /
`extraTrailingToolbarItems()` and can override `minimumContentSize` and
`toolbarHeight`. `LogView` itself — the scrolling table of log rows — is a
separate component with its own concerns (columns, row click dispatch,
tail-follow scrolling); this recipe covers only what the component itself
renders, lays out, and wires around that hosted view.

## Behavioral Requirements

- **layout-stack**: The component MUST render, top to bottom,
  a toolbar strip, a 1pt divider, and the hosted `LogView`, filling the
  controller's root view.
- **container-background**: The component MUST fill the root
  container with the `.windowBackground` theme role.
- **minimum-content-size**: The component MUST constrain the root
  view's width and height to each be at least `minimumContentSize` (default
  `600×400`, an overridable `open var`).
- **fixed-toolbar-height**: The component MUST give the toolbar strip a fixed
  height equal to `toolbarHeight` (default `40pt`, an overridable `open
  var`).
- **divider-below-toolbar**: The component MUST place a 1pt, `.divider`-role
  separator directly below the toolbar, spanning the root view's leading and
  trailing edges.
- **log-view-fills-remaining-space**: The component MUST size the hosted
  `LogView` to fill the root view's leading, trailing, and bottom edges below
  the divider.
- **leading-toolbar-items-rendered**: The component MUST render every view
  returned by `leadingToolbarItems()`, in the order returned, in a single
  horizontal stack (8pt spacing, vertically centered) pinned 12pt from the
  toolbar's leading edge.
- **leading-toolbar-items-overridable**: The default implementation of
  `leadingToolbarItems()` MUST return an empty array; a subclass MAY override
  it to supply additional leading toolbar views.
- **trailing-toolbar-items-rendered**: The component MUST render every view
  returned by `extraTrailingToolbarItems()` immediately before the built-in
  Pause button, Clear button, status dot, and status label, all in one
  horizontal stack (8pt spacing, vertically centered) pinned 12pt from the
  toolbar's trailing edge.
- **trailing-toolbar-items-overridable**: The default implementation of
  `extraTrailingToolbarItems()` MUST return an empty array; a subclass MAY
  override it to insert additional trailing toolbar views before the
  built-ins.
- **lifecycle-start**: The component MUST call `controller.start()` each
  time the view appears (`viewDidAppear`), which may happen more than once
  over the controller's lifetime (hide/show, tab switching, window
  re-ordering). `LogController.start()` is documented safe to call
  repeatedly — implementations are expected to tear down any previous
  stream first — so no additional guard against repeated appearances is
  needed here.
- **lifecycle-stop**: The component MUST call `controller.stop()` each
  time the view is about to disappear (`viewWillDisappear`), which — like
  `viewDidAppear` — may fire more than once over the controller's lifetime.
- **indicator-state-refresh**: The component MUST refresh the
  status dot color, status label text/tooltip, and pause button title
  whenever `controller.onStateChange` fires.
- **indicator-theme-refresh**: The component MUST refresh the
  status dot color, status label text/tooltip, and pause button title
  whenever the active theme palette changes.
- **connected-indicator**: When `controller.isConnected` is `true`, the
  component MUST fill the status dot with the `.success` role color and set
  the status label's text and tooltip to `Connected`.
- **error-indicator**: When `controller.isConnected` is `false` and
  `controller.lastError` is non-`nil`, the component MUST fill the status dot
  with the `.danger` role color and set the status label's text and tooltip
  to `controller.lastError`'s value verbatim.
- **connecting-indicator**: When `controller.isConnected` is `false` and
  `controller.lastError` is `nil`, the component MUST fill the status dot
  with the `.warning` role color and set the status label's text and tooltip
  to `Connecting…`.
- **connection-state-in-text**: The component MUST expose the
  connection state to assistive technology through text, not color alone —
  `statusLabel`'s `stringValue` and `toolTip` are both set to the same
  string (`Connected` / `Connecting…` / the error text) that also selects
  the dot's color, so the status dot's color is never the only carrier of
  the state.
- **pause-button-title-tracks-pause-state**: The component MUST set the pause
  button's title to `Resume` when `controller.isPaused` is `true`, and to
  `Pause` when it is `false`.
- **pause-action**: Clicking the pause button MUST
  call `controller.togglePause()`.
- **clear-action**: Clicking the clear button MUST call `controller.clear()`.
- **coder-init-unavailable**: `init(coder:)` MUST be marked unavailable at
  compile time and MUST call `fatalError` if somehow invoked at runtime.
- **default-start-size-floor**: The root view's initial frame MUST be sized
  to at least `900×600`, or to `minimumContentSize` where that is larger on
  either dimension.
- **status-dot-fixed-size**: The status dot MUST be sized to a fixed
  `8×8pt`, independent of any theme size scaling.

## Appearance

- **Corner radius**: `4pt` on the status dot's layer (`statusDot.layer?.cornerRadius
  = 4`), which on an 8×8pt square renders as a filled circle. No other view
  sets a corner radius directly; the pause/clear buttons'
  corner radius (if any) belongs to `ThemedSecondaryButton`, a separate
  themed control.
- **Padding**: Leading toolbar cluster — 12pt from the toolbar container's
  leading edge, vertically centered. Trailing toolbar cluster — 12pt from
  the toolbar container's trailing edge, vertically centered. Within each
  cluster, 8pt spacing between arranged views.
- **Font**: Not applicable directly. `pauseButton`/`clearButton`
  (`ThemedSecondaryButton`) and `statusLabel` (`ThemedLabel`, constructed
  with `textRole: .caption`) resolve their own font from the active theme's
  text roles; the component sets no font of its own.
- **Background**: Root container — `.windowBackground` theme role, via
  `ThemedBackgroundView`. The toolbar container is a plain `NSView` with no
  explicit fill of its own. The status dot's fill is a `CALayer`
  background color driven by connection state (`.success` / `.warning` /
  `.danger`), not a static background.
- **Foreground/Text**: `statusLabel` is constructed with `role:
  .secondaryText`, so its text color tracks that role; its text content is
  the same three-way connection string used for the tooltip. Pause/Clear
  button title colors are `ThemedSecondaryButton`'s own concern, not set by
  the component.
- **Border**: The divider between the toolbar and the log view is a
  `ThemedSeparatorView(role: .divider)`, a 1pt hairline spanning the root
  view's width.
- **Shadow**: None specified.
- **Min/Max size**: The root view enforces a floor via
  `greaterThanOrEqualToConstant` constraints on its own width and height
  anchors, equal to `minimumContentSize` (default `600×400`, overridable).
  No maximum size is set.
- **Status dot size**: Fixed `8×8pt` (see Behavioral Requirements).

## States

| State | Appearance change |
|-------|------------------|
| Default | Toolbar (leading items, Pause, Clear, status dot, status label) above a 1pt divider above the log view, filling the root view; root view background is `.windowBackground`. |
| Pressed | Not applicable: the pause/clear buttons' pressed-state fill (a swap between the `.elevatedSurface` and `.selection` role colors on `isHighlighted`) is owned by `ThemedSecondaryButton`, a separate themed control; the component applies no pressed-state styling of its own. |
| Disabled | Not applicable: the component never sets `isEnabled = false` on the pause or clear button; both remain enabled regardless of connection, pause, or error state. |
| Focused | Not applicable: the component sets no custom focus-ring appearance on any control; whatever focus ring AppKit draws by default for a standard `NSButton` is unmodified. |
| Loading | Represented by the Connecting state below; there is no separate loading spinner or progress indicator. |
| Connected | `controller.isConnected == true`: status dot fills with the `.success` role color; status label text and tooltip read `Connected`. |
| Connecting | `controller.isConnected == false` and `controller.lastError == nil`: status dot fills with the `.warning` role color; status label text and tooltip read `Connecting…`. |
| Error | `controller.isConnected == false` and `controller.lastError != nil`: status dot fills with the `.danger` role color; status label text and tooltip read the error string verbatim. |
| Paused | `controller.isPaused == true`: pause button title reads `Resume`. `controller.isPaused == false`: pause button title reads `Pause`. |

## Accessibility

- Pause and Clear are `NSButton`s (via `ThemedSecondaryButton`) constructed
  with a non-empty `title` (`Pause`/`Resume`, `Clear`), so AppKit's default
  accessibility exposes each button's own title text as its accessible
  name; no explicit accessibility label or identifier call is made.
- Both buttons are standard `NSButton`s in the default key-view loop, so
  they receive Tab-key focus and Space/Return activation from AppKit's
  ordinary responder chain; no custom key equivalent is assigned to either.
- The status dot (`statusDot`) is a plain, layer-backed `NSView` with no
  accessibility role, label, or identifier of its own; its state is exposed
  through text instead (see **connection-state-in-text**).
- A connection-state change rewrites `statusLabel`'s text, but no
  `NSAccessibility.post(element:notification:)` call accompanies it, so a
  VoiceOver user currently gets no announcement when the stream connects,
  reconnects, or fails.
- Not applicable: minimum tap target. This is a pointer-driven macOS
  control, not a touch surface, so the template's 44×44pt touch-target
  guidance does not apply; the toolbar buttons get no explicit
  width/height beyond `ThemedSecondaryButton`'s own title-driven
  `intrinsicContentSize`.
- **contrast**: NEEDS REVIEW: Not implemented in source. The status dot's `.success`/`.warning`/`.danger` fills and `statusLabel`'s `.secondaryText`-on-`.windowBackground` text pairing resolve from whichever `SemanticPalette` is active at runtime, so whether a given theme's resolved color pair meets a target contrast ratio (3:1 for the non-text dot, 4.5:1 for the caption-sized label text) can't be determined by inspecting the component alone; auditing each concrete `SemanticPalette`'s resolved colors against the platform's contrast guidance would settle it.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| log-view-controller-001 | layout-stack | Load the view. | Toolbar, then a 1pt divider, then the log view, stacked top to bottom, filling the root view. |
| log-view-controller-002 | container-background | Load the view, inspect the root view's layer background. | Background color equals the current theme's `.windowBackground` role color. |
| log-view-controller-003 | minimum-content-size | Load the view with the default `minimumContentSize` (`600×400`), then attempt to resize the root view's frame to `300×200`. | The root view's effective width and height never fall below `600×400`. |
| log-view-controller-004 | fixed-toolbar-height | Load the view. | The toolbar view's height constraint equals `toolbarHeight` (`40pt` by default). |
| log-view-controller-005 | divider-below-toolbar | Load the view, inspect the divider view. | A 1pt-tall view filled with the `.divider` role color sits directly below the toolbar, pinned to the root view's leading and trailing edges. |
| log-view-controller-006 | log-view-fills-remaining-space | Load the view, resize the root view. | The hosted `LogView` fills the area below the divider, pinned to the root view's leading, trailing, and bottom edges. |
| log-view-controller-007 | leading-toolbar-items-rendered | Override `leadingToolbarItems()` to return two views, load the view. | Both views appear, in the order returned, in a horizontal stack pinned 12pt from the toolbar's leading edge. |
| log-view-controller-008 | leading-toolbar-items-overridable | Construct the base class (no override), load the view. | The leading stack contains zero subclass-supplied views. |
| log-view-controller-009 | trailing-toolbar-items-rendered | Override `extraTrailingToolbarItems()` to return one view, load the view. | That view appears before Pause, Clear, the status dot, and the status label, in that left-to-right order, in the trailing stack. |
| log-view-controller-010 | trailing-toolbar-items-overridable | Construct the base class (no override), load the view. | The trailing stack contains exactly Pause, Clear, the status dot, and the status label — no extra views. |
| log-view-controller-011 | lifecycle-start | Add the controller's view to a window and let it appear. | `controller.start()` is called exactly once. |
| log-view-controller-012 | lifecycle-stop | With the view appeared, remove it from the window (trigger `viewWillDisappear`). | `controller.stop()` is called exactly once. |
| log-view-controller-013 | indicator-state-refresh | Load the view, then set `controller.isConnected = false`, `controller.isPaused = true`, and `controller.lastError = "Disconnected"`, then invoke `controller.onStateChange?()`. | The status dot fills `.danger`, the status label text/tooltip read `Disconnected`, and the pause button title reads `Resume` — all three indicators reflect the new combined state. |
| log-view-controller-014 | indicator-theme-refresh | Load the view, then post `ThemeManager.didChangeNotification` — the notification the `ThemePaletteObserver` registered on `view` in `viewDidLoad` observes to re-apply the palette. | The status dot, status label, and pause button title are repainted using the new theme's role colors/fonts, still reflecting the current controller state. |
| log-view-controller-015 | connected-indicator | Set `controller.isConnected = true`, trigger a refresh. | Status dot color equals the `.success` role color; status label text and tooltip equal `Connected`. |
| log-view-controller-016 | error-indicator | Set `controller.isConnected = false` and `controller.lastError = "Disconnected"`, trigger a refresh. | Status dot color equals the `.danger` role color; status label text and tooltip equal `Disconnected`. |
| log-view-controller-017 | connecting-indicator | Set `controller.isConnected = false` and `controller.lastError = nil`, trigger a refresh. | Status dot color equals the `.warning` role color; status label text and tooltip equal `Connecting…`. |
| log-view-controller-018 | pause-button-title-tracks-pause-state | Set `controller.isPaused = true`, trigger a refresh; then set it to `false` and refresh again. | Pause button title reads `Resume`, then `Pause`. |
| log-view-controller-019 | pause-action | Click the pause button. | `controller.togglePause()` is called exactly once. |
| log-view-controller-020 | clear-action | Click the clear button. | `controller.clear()` is called exactly once. |
| log-view-controller-021 | coder-init-unavailable | Attempt to build the controller via `NSCoder`-based decoding (e.g. from a storyboard/XIB). | Compilation fails (unavailable), or a runtime `fatalError` occurs if the unavailability is bypassed. |
| log-view-controller-022 | default-start-size-floor | Construct the controller with default `minimumContentSize`, load the view, inspect the root view's initial frame. | Initial frame size is at least `900×600`. |
| log-view-controller-023 | status-dot-fixed-size | Load the view under a theme with an increased `sizeScale`. | The status dot's width and height constraints remain `8pt` each, unaffected by `sizeScale`. |
| log-view-controller-024 | connection-state-in-text | Trigger the connected, connecting, and error states in turn. | `statusLabel`'s text/tooltip read `Connected`, `Connecting…`, and the error string respectively — never the same string across states, and never conveyed by dot color alone. |
| log-view-controller-025 | lifecycle-start, lifecycle-stop | Add the controller's view to a window, let it appear, remove it from the window (disappear), then re-add it and let it appear again. | `controller.start()` is called twice and `controller.stop()` is called once, in appear → disappear → appear order. |
| log-view-controller-026 | default-start-size-floor | Override `minimumContentSize` to `1000×700` (larger than `900×600` on both dimensions), load the view, inspect the root view's initial frame. | Initial frame size equals `1000×700`, not `900×600`. |

## Edge Cases

- **Null/empty input**: `controller.lastError` being `nil` versus a non-`nil`
  string is the sole discriminator, alongside `isConnected`, for which of
  the three status branches (`connected-indicator` /
  `error-indicator` / `connecting-indicator`) applies; an empty string
  (`""`) for `lastError` is treated as non-`nil` and so is displayed
  verbatim as the error text — the same branch as any other non-`nil`
  value. `leadingToolbarItems()`/`extraTrailingToolbarItems()` returning an
  empty array (the default) is the normal case, not a special-cased branch:
  the corresponding stack view simply arranges zero subviews.
- **Boundary values**: A subclass overriding `minimumContentSize` or
  `toolbarHeight` with a value of zero or negative is not guarded against;
  the resulting `NSLayoutConstraint`s are built from that zero or negative
  constant and passed through to Auto Layout as-is. The resulting layout is
  undefined — this is an unguarded input, not documented behavior, and no
  precondition or assertion rejects it.
- **Concurrent access**: `LogController` is a `@MainActor`-isolated
  protocol, `LogViewController` itself is `@MainActor`, and
  `controller.onStateChange` is typed `(@MainActor () -> Void)?`, so state
  refreshes are always serialized on the main actor; there is no
  cross-thread mutation path to define behavior for.
- **Error states**: `controller.lastError`'s string is displayed verbatim
  with no truncation, retry affordance, or dismiss action wired anywhere;
  clicking Pause or Clear while an error is present still calls
  `togglePause()`/`clear()` unconditionally — neither call is gated on
  connection or error state.
- **Offline/disconnected state**: The Connecting state
  (`isConnected == false`, `lastError == nil`) is this component's sole
  representation of "not yet connected" or "reconnecting"; it renders
  identically whether the transport has never connected or has dropped and
  is retrying, because `LogController` exposes no separate signal for that
  distinction. Actually reconnecting/backoff behavior belongs to the
  injected `LogController` implementation (SSE/HTTP/file-tail), a separate
  component out of this recipe's scope — the component only reads the three
  properties (`isConnected`, `isPaused`, `lastError`) it is given.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `controller` | `any LogController` | required (no default on the designated initializer) | Owns the log's provider plus connection/pause/error state; the component starts/stops it and reads its state to drive the toolbar. See the LogController Contract below. |
| `minimumContentSize` | `NSSize` | `NSSize(width: 600, height: 400)` | Overridable floor enforced as constraints on the root view's own width/height anchors. |
| `toolbarHeight` | `CGFloat` | `40` | Overridable fixed height of the toolbar strip above the log view. |
| `leadingToolbarItems()` | `() -> [NSView]` | `[]` | Overridable hook for subclass-supplied views placed left of the built-in controls. |
| `extraTrailingToolbarItems()` | `() -> [NSView]` | `[]` | Overridable hook for subclass-supplied views inserted before the built-in Pause/Clear/status cluster. |
| (fixed, not a subclass hook) | `NSSize` | `900×600` | Non-overridable floor combined via `max()` against `minimumContentSize` when computing the root view's initial frame in `loadView()`; see **default-start-size-floor**. |

### LogController Contract

`LogController` is a `@MainActor`-isolated protocol. The component reads and
calls:

| Member | Type | Notes |
|--------|------|-------|
| `provider` | `any LogProvider` | Backing store handed to the hosted `LogView`. |
| `isConnected` | `Bool` | Selects the connected/connecting branch of the status dot and label. |
| `isPaused` | `Bool` | Drives the pause button's title. |
| `lastError` | `String?` | Displayed verbatim in the status label/tooltip when non-`nil` and `isConnected` is `false`. |
| `onStateChange` | `(@MainActor () -> Void)?` | Assigned in `init` to trigger `updateStateIndicators()`. |
| `start()` | `() -> Void` | Called from `viewDidAppear`; documented safe to call repeatedly. |
| `stop()` | `() -> Void` | Called from `viewWillDisappear`. |
| `togglePause()` | `() -> Void` | Called by the pause button. |
| `clear()` | `() -> Void` | Called by the clear button. |

## Deep Linking

Not applicable: the component contains no URL-scheme or route
handling of any kind.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none defined in source) | `Pause` | Pause button's initial title, and its title whenever `controller.isPaused == false`. |
| (none defined in source) | `Resume` | Pause button's title whenever `controller.isPaused == true`. |
| (none defined in source) | `Clear` | Clear button's title, a literal `String` passed to `ThemedSecondaryButton(title:)`. |
| (none defined in source) | `Connected` | Status label text/tooltip when `controller.isConnected == true`. |
| (none defined in source) | `Connecting…` | Status label text/tooltip when `controller.isConnected == false` and `controller.lastError == nil`. |

`Pause`, `Resume`, `Clear`, `Connected`, and `Connecting…` are all assigned as
`String` literals directly to `NSButton.title` or `NSTextField.stringValue`
— AppKit properties, not a SwiftUI `Text`/`LocalizedStringKey` — so the
component is unlocalized as written: it defines no string-key scheme, and
wiring one in is the host app's localization owner's responsibility.
(`controller.lastError`'s string is displayed as-is and is excluded from
this table: its content and any localization are the injected
`LogController` implementation's concern, not the component's.)

## Accessibility Options

- **Reduce Motion**: Not applicable. The component contains no animation —
  title changes, dot color changes, and layout all happen through
  immediate property assignment and Auto Layout constraints; there is no
  `NSAnimationContext`, transition, or motion effect to reduce.
- **Increase Contrast**: Not applicable at this component's level. Every
  color the component uses comes from a `SemanticPalette` role
  (`.windowBackground`, `.divider`, `.success`, `.warning`, `.danger`,
  `.secondaryText`); the component contains no branch on
  `NSWorkspace.accessibilityDisplayShouldIncreaseContrast`, so any contrast
  adaptation would live in the theme/palette system, not here.
- **Differentiate Without Color**: Already satisfied. The connection state
  is conveyed through `statusLabel`'s text (`Connected` / `Connecting…` /
  the error string) in addition to `statusDot`'s color (see
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
  `LogController`/`LogView` provide; it captures no input beyond Pause and
  Clear button clicks.
- **Storage**: This component writes nothing to disk or `UserDefaults`.
- **Transmission**: None. The component makes no network calls
  itself — any transport (SSE, HTTP, file-tail) belongs to the injected
  `LogController` implementation, a separate component out of this
  recipe's scope.
- **Retention**: Not applicable. This component keeps no state of its own
  beyond the controller/view references it is constructed with.

## Logging

Not applicable: the component contains no `os_log`, `Logger`,
or other logging calls.

## Platform Notes

- **SwiftUI**: A SwiftUI port would express the toolbar as an `HStack`
  (leading items, a `Spacer()`, then Pause/Clear `Button`s, a small
  `Circle().fill(...)` for the status dot, and `Text` for the label) above
  a `Divider()` above the hosted log view, with `updateStateIndicators()`'s
  three-way branch expressed as a computed `(Color, String)` derived from
  `@ObservedObject`/`@Published` controller state, and `viewDidAppear`/
  `viewWillDisappear`'s `start()`/`stop()` calls moved to `.onAppear`/
  `.onDisappear`.
- **Compose**: Start from a `Column` with a `Row` toolbar (leading items, a
  `Spacer`, `TextButton`s for Pause/Clear, a small circular `Box` for the
  dot, `Text` for the label), a `HorizontalDivider`, then the hosted log
  composable below. `isConnected`/`lastError`/`isPaused` become `StateFlow`
  fields on a `ViewModel`; `start()`/`stop()` map to a `DisposableEffect`
  keyed on composition entering/leaving, matching `viewDidAppear`/
  `viewWillDisappear`.
- **React/Web**: The toolbar becomes a flex row (a leading slot, a flexible
  spacer, Pause/Clear `<button>`s, a small colored `<span>`/`<div>` circle
  for the dot, a status `<span>` for the label) above a `<hr>`/border-top
  divider above the log component. `isConnected`/`lastError`/`isPaused`
  become props or store fields driving the same three-way branch;
  `start()`/`stop()` map to a `useEffect` mount/unmount pair opening and
  closing the underlying stream (SSE/WebSocket).
- **AppKit / UIKit**: This is the source platform (AppKit/macOS). On iOS,
  `NSViewController` becomes `UIViewController`, `NSView`/`NSStackView`
  become `UIView`/`UIStackView`, and `ThemedSecondaryButton`/
  `ThemedSeparatorView`/`ThemedLabel`/`ThemedBackgroundView` need UIKit
  counterparts; `viewDidAppear`/`viewWillDisappear` map directly to the
  identically-named `UIViewController` lifecycle methods, so the
  start/stop-on-lifecycle behavior ports unchanged.
- **WinUI 3**: Model the whole controller as a `UserControl`/`Page` whose
  root `Grid` has two `RowDefinition`s — a toolbar row fixed at
  `toolbarHeight`, and a log row set to `*` — separated by a
  `<Border BorderThickness="0,0,0,1">` standing in for
  `ThemedSeparatorView`. The toolbar is a `Grid` (or a `DockPanel`-style
  pair of `StackPanel`s) with one `HorizontalAlignment="Left"` panel for
  `leadingToolbarItems()` and one `HorizontalAlignment="Right"` panel
  holding the extra-trailing items, Pause/Clear `Button`s, a small
  `Ellipse` (`Width="8" Height="8"`, `Fill` bound to a `SolidColorBrush`
  chosen by the same three-way connection state) for the status dot, and a
  `TextBlock` whose `Text` and `ToolTipService.ToolTip` both bind to that
  same state string. Drive the `Connected`/`Connecting`/`Error` visuals and
  the Pause/Resume title through `VisualStateManager` states toggled from a
  bound view-model exposing the same `isConnected`/`isPaused`/`lastError`
  surface as `LogController`, and start/stop the transport from the page's
  `Loaded`/`Unloaded` events, mirroring `viewDidAppear`/`viewWillDisappear`.

## Design Decisions

**Decision**: Route both theme-palette changes and controller state changes
through the same `updateStateIndicators()` method, rather than painting
theme colors in a separate observer callback.
**Rationale**: The source comment states the status dot's color and the pause
button's title both depend on controller state, so "a theme change and a
state change have to land in the same place or one overwrites the other
with the previous theme's colours."
**Approved**: pending

**Decision**: Use `ThemedSecondaryButton` for Pause and Clear instead of
`ThemedButton` (the accent-filled pill button).
**Rationale**: The source comment states two accent-filled pills in a toolbar
"would claim more emphasis than a log's controls deserve," so lower-emphasis
secondary styling was chosen deliberately.
**Approved**: pending

**Decision**: Use `ThemedSeparatorView` for the toolbar/log divider instead of
an `NSBox` separator.
**Rationale**: The source comment states an `NSBox` separator "draws a system
hairline, which is the one line in this window the palette could not
reach," so a themed view was substituted to keep the divider on-palette.
**Approved**: pending

**Decision**: Enforce `minimumContentSize` as `greaterThanOrEqualToConstant`
constraints on the root view's own width/height anchors.
**Rationale**: The source comment states `LogView` has no intrinsic width, so
without a floor `NSWindow` collapses the controller's view to `fittingSize`
after its async layout pass — "a 1pt-wide window."
**Approved**: pending

**Decision**: Give the pause/clear buttons no explicit width/height constraint.
**Rationale**: The source comment states `ThemedSecondaryButton` measures the
title it is about to draw, in the theme's own button font, and grows past
its stock 68×22 minimum rather than clipping at a large `sizeScale`.
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
