---
id: 29b3f716-ad00-4aff-9dd4-fc7c2e5cf17d
title: Log View Controller
domain: agentictoolkit://recipes/log-view-controller
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
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
- macos
depends-on: []
related: []
references:
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
approved-by: ''
approved-date: ''
---

# Log View Controller

## Overview

`LogViewController` is an `NSViewController` that pairs a `LogView` with a
toolbar strip carrying the controls a streaming log needs: a Pause button, a
Clear button, and a connection-status indicator (a colored dot plus a text
label). It hosts any `LogController`, so the source of rows (SSE, file tail,
test fixture) is swappable without changing this file. Subclasses splice in
domain-specific toolbar items via `leadingToolbarItems()` /
`extraTrailingToolbarItems()` and can override `minimumContentSize` and
`toolbarHeight`. `LogView` itself — the scrolling table of log rows — is a
separate component with its own concerns (columns, row click dispatch,
tail-follow scrolling); this recipe covers only what `LogViewController.swift`
itself renders, lays out, and wires around that hosted view.

## Behavioral Requirements

- **pairs-log-view-with-toolbar**: The component MUST render, top to bottom,
  a toolbar strip, a 1pt divider, and the hosted `LogView`, filling the
  controller's root view.
- **windowbackground-container-fill**: The component MUST fill the root
  container with the `.windowBackground` theme role.
- **enforces-minimum-content-size**: The component MUST constrain the root
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
- **leading-toolbar-items-overridable**: `leadingToolbarItems()` MAY be
  overridden by a subclass to supply additional leading toolbar views; the
  default implementation returns an empty array.
- **trailing-toolbar-items-rendered**: The component MUST render every view
  returned by `extraTrailingToolbarItems()` immediately before the built-in
  Pause button, Clear button, status dot, and status label, all in one
  horizontal stack (8pt spacing, vertically centered) pinned 12pt from the
  toolbar's trailing edge.
- **trailing-toolbar-items-overridable**: `extraTrailingToolbarItems()` MAY
  be overridden by a subclass to insert additional trailing toolbar views
  before the built-ins; the default implementation returns an empty array.
- **starts-controller-on-appear**: The component MUST call `controller.start()`
  when the view appears (`viewDidAppear`).
- **stops-controller-on-disappear**: The component MUST call
  `controller.stop()` when the view is about to disappear
  (`viewWillDisappear`).
- **refreshes-indicators-on-state-change**: The component MUST refresh the
  status dot color, status label text/tooltip, and pause button title
  whenever `controller.onStateChange` fires.
- **refreshes-indicators-on-theme-change**: The component MUST refresh the
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
- **pause-button-title-tracks-pause-state**: The component MUST set the pause
  button's title to `Resume` when `controller.isPaused` is `true`, and to
  `Pause` when it is `false`.
- **pause-button-toggles-controller-pause**: Clicking the pause button MUST
  call `controller.togglePause()`.
- **clear-button-clears-controller**: Clicking the clear button MUST call
  `controller.clear()`.
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
  in this file sets a corner radius directly; the pause/clear buttons'
  corner radius (if any) belongs to `ThemedSecondaryButton`, a separate
  themed control.
- **Padding**: Leading toolbar cluster — 12pt from the toolbar container's
  leading edge, vertically centered. Trailing toolbar cluster — 12pt from
  the toolbar container's trailing edge, vertically centered. Within each
  cluster, 8pt spacing between arranged views.
- **Font**: Not applicable directly. `pauseButton`/`clearButton`
  (`ThemedSecondaryButton`) and `statusLabel` (`ThemedLabel`, constructed
  with `textRole: .caption`) resolve their own font from the active theme's
  text roles; `LogViewController.swift` sets no font itself.
- **Background**: Root container — `.windowBackground` theme role, via
  `ThemedBackgroundView`. The toolbar container is a plain `NSView` with no
  explicit fill set in this file. The status dot's fill is a `CALayer`
  background color driven by connection state (`.success` / `.warning` /
  `.danger`), not a static background.
- **Foreground/Text**: `statusLabel` is constructed with `role:
  .secondaryText`, so its text color tracks that role; its text content is
  the same three-way connection string used for the tooltip. Pause/Clear
  button title colors are `ThemedSecondaryButton`'s own concern, not set by
  this file.
- **Border**: The divider between the toolbar and the log view is a
  `ThemedSeparatorView(role: .divider)`, a 1pt hairline spanning the root
  view's width.
- **Shadow**: None specified in source.
- **Min/Max size**: The root view enforces a floor via
  `greaterThanOrEqualToConstant` constraints on its own width and height
  anchors, equal to `minimumContentSize` (default `600×400`, overridable).
  No maximum size is set anywhere in this file.
- **Status dot size**: Fixed `8×8pt` (see Behavioral Requirements).

## States

| State | Appearance change |
|-------|------------------|
| Default | Toolbar (leading items, Pause, Clear, status dot, status label) above a 1pt divider above the log view, filling the root view; root view background is `.windowBackground`. |
| Pressed | Not applicable in this file: the pause/clear buttons' pressed-state fill (a swap between the `.elevatedSurface` and `.selection` role colors on `isHighlighted`) is owned by `ThemedSecondaryButton`, a separate themed control; `LogViewController.swift` sets no pressed-state styling of its own. |
| Disabled | Not applicable: `LogViewController.swift` never sets `isEnabled = false` on the pause or clear button; both remain enabled regardless of connection, pause, or error state. |
| Focused | Not applicable: this file sets no custom focus-ring appearance on any control; whatever focus ring AppKit draws by default for a standard `NSButton` is unmodified here. |
| Loading | Represented by the Connecting state below; there is no separate loading spinner or progress indicator in source. |
| Connected | `controller.isConnected == true`: status dot fills with the `.success` role color; status label text and tooltip read `Connected`. |
| Connecting | `controller.isConnected == false` and `controller.lastError == nil`: status dot fills with the `.warning` role color; status label text and tooltip read `Connecting…`. |
| Error | `controller.isConnected == false` and `controller.lastError != nil`: status dot fills with the `.danger` role color; status label text and tooltip read the error string verbatim. |
| Paused | `controller.isPaused == true`: pause button title reads `Resume`. `controller.isPaused == false`: pause button title reads `Pause`. |

## Accessibility

- Pause and Clear are `NSButton`s (via `ThemedSecondaryButton`) constructed
  with a non-empty `title` (`Pause`/`Resume`, `Clear`), so AppKit's default
  accessibility exposes each button's own title text as its accessible
  name; no explicit accessibility label or identifier call is made anywhere
  in this file.
- Both buttons are standard `NSButton`s in the default key-view loop, so
  they receive Tab-key focus and Space/Return activation from AppKit's
  ordinary responder chain; no custom key equivalent is assigned to either.
- The status dot (`statusDot`) is a plain, layer-backed `NSView` with no
  accessibility role, label, or identifier set in source.
- **connection-state-in-text**: The component MUST expose the
  connection state to assistive technology through text, not color alone —
  `statusLabel`'s `stringValue` and `toolTip` are both set to the same
  string (`Connected` / `Connecting…` / the error text) that also selects
  the dot's color, so the status dot's color is never the only carrier of
  the state.
- NEEDS REVIEW: Not implemented in source. A connection-state change
  rewrites `statusLabel`'s text, but no
  `NSAccessibility.post(element:notification:)` call accompanies it, so a
  VoiceOver user is not told the stream connected, reconnected, or failed;
  whether the component should post an announcement is an open question.
- Not applicable: minimum tap target. This is a pointer-driven macOS
  control, not a touch surface, so the template's 44×44pt touch-target
  guidance does not apply; source gives the toolbar buttons no explicit
  width/height beyond `ThemedSecondaryButton`'s own title-driven
  `intrinsicContentSize`.
- NEEDS REVIEW: Not implemented in source. Behavior undefined. The status
  dot's `.success`/`.warning`/`.danger` fills and `statusLabel`'s
  `.secondaryText`-on-`.windowBackground` text pairing are resolved from
  whichever `SemanticPalette` is active at runtime; this file names theme
  roles, not concrete color values, so whether a given theme's resolved
  color pair meets a target contrast ratio (e.g. 3:1 for the non-text
  status dot, 4.5:1 for the caption-sized label text) cannot be determined
  by reading `LogViewController.swift` alone. This would be settled by
  auditing each concrete `SemanticPalette`'s resolved colors for these
  roles against the target platform's contrast guidance.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| log-view-controller-001 | pairs-log-view-with-toolbar | Load the view. | Toolbar, then a 1pt divider, then the log view, stacked top to bottom, filling the root view. |
| log-view-controller-002 | windowbackground-container-fill | Load the view, inspect the root view's layer background. | Background color equals the current theme's `.windowBackground` role color. |
| log-view-controller-003 | enforces-minimum-content-size | Load the view with the default `minimumContentSize`, then attempt to size the root view below `600×400`. | The root view's effective width and height never fall below `600×400`. |
| log-view-controller-004 | fixed-toolbar-height | Load the view. | The toolbar view's height constraint equals `toolbarHeight` (`40pt` by default). |
| log-view-controller-005 | divider-below-toolbar | Load the view, inspect the divider view. | A 1pt-tall view filled with the `.divider` role color sits directly below the toolbar, pinned to the root view's leading and trailing edges. |
| log-view-controller-006 | log-view-fills-remaining-space | Load the view, resize the root view. | The hosted `LogView` fills the area below the divider, pinned to the root view's leading, trailing, and bottom edges. |
| log-view-controller-007 | leading-toolbar-items-rendered | Override `leadingToolbarItems()` to return two views, load the view. | Both views appear, in the order returned, in a horizontal stack pinned 12pt from the toolbar's leading edge. |
| log-view-controller-008 | leading-toolbar-items-overridable | Construct the base class (no override), load the view. | The leading stack contains zero subclass-supplied views. |
| log-view-controller-009 | trailing-toolbar-items-rendered | Override `extraTrailingToolbarItems()` to return one view, load the view. | That view appears before Pause, Clear, the status dot, and the status label, in that left-to-right order, in the trailing stack. |
| log-view-controller-010 | trailing-toolbar-items-overridable | Construct the base class (no override), load the view. | The trailing stack contains exactly Pause, Clear, the status dot, and the status label — no extra views. |
| log-view-controller-011 | starts-controller-on-appear | Add the controller's view to a window and let it appear. | `controller.start()` is called exactly once. |
| log-view-controller-012 | stops-controller-on-disappear | With the view appeared, remove it from the window (trigger `viewWillDisappear`). | `controller.stop()` is called exactly once. |
| log-view-controller-013 | refreshes-indicators-on-state-change | Load the view, then invoke `controller.onStateChange?()` after changing `controller.isConnected`. | The status dot, status label, and pause button title are re-evaluated and reflect the new state. |
| log-view-controller-014 | refreshes-indicators-on-theme-change | Load the view, then post a theme-change notification via the active `ThemeManager`. | The status dot, status label, and pause button title are repainted using the new theme's role colors/fonts, still reflecting the current controller state. |
| log-view-controller-015 | connected-indicator | Set `controller.isConnected = true`, trigger a refresh. | Status dot color equals the `.success` role color; status label text and tooltip equal `Connected`. |
| log-view-controller-016 | error-indicator | Set `controller.isConnected = false` and `controller.lastError = "Disconnected"`, trigger a refresh. | Status dot color equals the `.danger` role color; status label text and tooltip equal `Disconnected`. |
| log-view-controller-017 | connecting-indicator | Set `controller.isConnected = false` and `controller.lastError = nil`, trigger a refresh. | Status dot color equals the `.warning` role color; status label text and tooltip equal `Connecting…`. |
| log-view-controller-018 | pause-button-title-tracks-pause-state | Set `controller.isPaused = true`, trigger a refresh; then set it to `false` and refresh again. | Pause button title reads `Resume`, then `Pause`. |
| log-view-controller-019 | pause-button-toggles-controller-pause | Click the pause button. | `controller.togglePause()` is called exactly once. |
| log-view-controller-020 | clear-button-clears-controller | Click the clear button. | `controller.clear()` is called exactly once. |
| log-view-controller-021 | coder-init-unavailable | Attempt to build the controller via `NSCoder`-based decoding (e.g. from a storyboard/XIB). | Compilation fails (unavailable), or a runtime `fatalError` occurs if the unavailability is bypassed. |
| log-view-controller-022 | default-start-size-floor | Construct the controller with default `minimumContentSize`, load the view, inspect the root view's initial frame. | Initial frame size is at least `900×600`. |
| log-view-controller-023 | status-dot-fixed-size | Load the view under a theme with an increased `sizeScale`. | The status dot's width and height constraints remain `8pt` each, unaffected by `sizeScale`. |

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
  `toolbarHeight` with a value of zero or negative is not guarded against
  in source; `NSLayoutConstraint`s built from a negative or zero constant
  are passed through to Auto Layout as-is, which MUST NOT be assumed to
  produce a usable layout — this is an unguarded input, not a documented
  behavior.
- **Concurrent access**: `LogController` is a `@MainActor`-isolated
  protocol, `LogViewController` itself is `@MainActor`, and
  `controller.onStateChange` is typed `(@MainActor () -> Void)?`, so state
  refreshes are always serialized on the main actor; there is no
  cross-thread mutation path in this file to define behavior for.
- **Error states**: `controller.lastError`'s string is displayed verbatim
  with no truncation, retry affordance, or dismiss action wired anywhere in
  this file; clicking Pause or Clear while an error is present still calls
  `togglePause()`/`clear()` unconditionally — neither call is gated on
  connection or error state.
- **Offline/disconnected state**: The Connecting state
  (`isConnected == false`, `lastError == nil`) is this component's sole
  representation of "not yet connected" or "reconnecting"; it renders
  identically whether the transport has never connected or has dropped and
  is retrying, because `LogController` exposes no separate signal for that
  distinction. Actually reconnecting/backoff behavior belongs to the
  injected `LogController` implementation (SSE/HTTP/file-tail), a separate
  component out of this recipe's scope — this file only reads the three
  properties (`isConnected`, `isPaused`, `lastError`) it is given.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `controller` | `any LogController` | required (no default on the designated initializer) | Owns the log's provider plus connection/pause/error state; this file starts/stops it and reads its state to drive the toolbar. |
| `minimumContentSize` | `NSSize` | `NSSize(width: 600, height: 400)` | Overridable floor enforced as constraints on the root view's own width/height anchors. |
| `toolbarHeight` | `CGFloat` | `40` | Overridable fixed height of the toolbar strip above the log view. |
| `leadingToolbarItems()` | `() -> [NSView]` | `[]` | Overridable hook for subclass-supplied views placed left of the built-in controls. |
| `extraTrailingToolbarItems()` | `() -> [NSView]` | `[]` | Overridable hook for subclass-supplied views inserted before the built-in Pause/Clear/status cluster. |

## Deep Linking

Not applicable: `LogViewController.swift` contains no URL-scheme or route
handling of any kind.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none defined in source) | `Pause` | Pause button's initial title, and its title whenever `controller.isPaused == false`. |
| (none defined in source) | `Resume` | Pause button's title whenever `controller.isPaused == true`. |
| (none defined in source) | `Clear` | Clear button's title, a literal `String` passed to `ThemedSecondaryButton(title:)`. |
| (none defined in source) | `Connected` | Status label text/tooltip when `controller.isConnected == true`. |
| (none defined in source) | `Connecting…` | Status label text/tooltip when `controller.isConnected == false` and `controller.lastError == nil`. |

NEEDS REVIEW: Not implemented in source. Behavior undefined. `Pause`,
`Resume`, `Clear`, `Connected`, and `Connecting…` are all assigned as
`String` literals directly to `NSButton.title` or `NSTextField.stringValue`
— AppKit properties, not a SwiftUI `Text`/`LocalizedStringKey` — so these
are genuinely unlocalized as written. What is missing is a defined
string-key scheme for this component; it would be settled by the host
app's localization owner choosing keys and wiring them in.
(`controller.lastError`'s string is displayed as-is and is excluded from
this table: its content and any localization are the injected
`LogController` implementation's concern, not this file's.)

## Accessibility Options

- **Reduce Motion**: Not applicable. Source contains no animation —
  title changes, dot color changes, and layout all happen through
  immediate property assignment and Auto Layout constraints; there is no
  `NSAnimationContext`, transition, or motion effect to reduce.
- **Increase Contrast**: Not applicable at this component's level. Every
  color in this file comes from a `SemanticPalette` role
  (`.windowBackground`, `.divider`, `.success`, `.warning`, `.danger`,
  `.secondaryText`); `LogViewController.swift` contains no branch on
  `NSWorkspace.accessibilityDisplayShouldIncreaseContrast`, so any contrast
  adaptation would live in the theme/palette system, not here.
- **Differentiate Without Color**: Already satisfied. The connection state
  is conveyed through `statusLabel`'s text (`Connected` / `Connecting…` /
  the error string) in addition to `statusDot`'s color (see
  `connection-state-in-text` above), so no state in this
  component is communicated by color alone.

## Feature Flags

Not applicable: `LogViewController.swift` contains no feature-flag or
build-configuration check of any kind.

## Analytics

Not applicable: `LogViewController.swift` contains no analytics or
event-tracking calls.

## Privacy

- **Data collected**: None by this component directly. It displays
  whatever connection state, error text, and rows the injected
  `LogController`/`LogView` provide; it captures no input beyond Pause and
  Clear button clicks.
- **Storage**: This component writes nothing to disk or `UserDefaults`.
- **Transmission**: None. `LogViewController.swift` makes no network calls
  itself — any transport (SSE, HTTP, file-tail) belongs to the injected
  `LogController` implementation, a separate component out of this
  recipe's scope.
- **Retention**: Not applicable. This component keeps no state of its own
  beyond the controller/view references it is constructed with.

## Logging

Not applicable: `LogViewController.swift` contains no `os_log`, `Logger`,
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

Decision: Route both theme-palette changes and controller state changes
through the same `updateStateIndicators()` method, rather than painting
theme colors in a separate observer callback.
Rationale: the source comment states the status dot's color and the pause
button's title both depend on controller state, so "a theme change and a
state change have to land in the same place or one overwrites the other
with the previous theme's colours."
Approved: pending.

Decision: Use `ThemedSecondaryButton` for Pause and Clear instead of
`ThemedButton` (the accent-filled pill button).
Rationale: the source comment states two accent-filled pills in a toolbar
"would claim more emphasis than a log's controls deserve," so lower-emphasis
secondary styling was chosen deliberately.
Approved: pending.

Decision: Use `ThemedSeparatorView` for the toolbar/log divider instead of
an `NSBox` separator.
Rationale: the source comment states an `NSBox` separator "draws a system
hairline, which is the one line in this window the palette could not
reach," so a themed view was substituted to keep the divider on-palette.
Approved: pending.

Decision: Enforce `minimumContentSize` as `greaterThanOrEqualToConstant`
constraints on the root view's own width/height anchors.
Rationale: the source comment states `LogView` has no intrinsic width, so
without a floor `NSWindow` collapses the controller's view to `fittingSize`
after its async layout pass — "a 1pt-wide window."
Approved: pending.

Decision: Give the pause/clear buttons no explicit width/height constraint.
Rationale: the source comment states `ThemedSecondaryButton` measures the
title it is about to draw, in the theme's own button font, and grows past
its stock 68×22 minimum rather than clipping at a large `sizeScale`.
Approved: pending.

## Compliance

No automated compliance checks have been run against this recipe yet. This
table will be populated by the cookbook's compliance tooling on review.

| Check | Status | Category |
|-------|--------|----------|

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
