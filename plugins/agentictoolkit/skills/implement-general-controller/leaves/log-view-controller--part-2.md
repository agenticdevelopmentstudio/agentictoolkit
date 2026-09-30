<!-- leaf: implement-general-controller/log-view-controller--part-2 · source: log-view-controller.md -->

# Log View Controller — continued (part 2)

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
