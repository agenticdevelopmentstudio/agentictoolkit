<!-- leaf: implement-general-controller/log-view-controller · source: log-view-controller.md -->

**Rules** (cite as `implement-general-controller/log-view-controller#<slug>`):

- `layout-stack` MUST
- `container-background` MUST
- `minimum-content-size` MUST
- `fixed-toolbar-height` MUST
- `divider-below-toolbar` MUST
- `log-view-fills-remaining-space` MUST
- `leading-toolbar-items-rendered` MUST
- `leading-toolbar-items-overridable` MUST
- `trailing-toolbar-items-rendered` MUST
- `trailing-toolbar-items-overridable` MUST
- `lifecycle-start` MUST
- `lifecycle-stop` MUST
- `indicator-state-refresh` MUST
- `indicator-theme-refresh` MUST
- `connected-indicator` MUST
- `error-indicator` MUST
- `connecting-indicator` MUST
- `connection-state-in-text` MUST
- `pause-button-title-tracks-pause-state` MUST
- `pause-action` MUST
- `clear-action` MUST
- `coder-init-unavailable` MUST
- `default-start-size-floor` MUST
- `status-dot-fixed-size` MUST

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

