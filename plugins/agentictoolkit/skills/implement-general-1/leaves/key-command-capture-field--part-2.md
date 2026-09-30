<!-- leaf: implement-general-1/key-command-capture-field--part-2 · source: key-command-capture-field.md -->

# KeyCommandCaptureField — continued (part 2)

## Accessibility

- **Role/trait**: Not implemented in source. No
  `setAccessibilityRole`, `setAccessibilityLabel`, or accessibility
  title-element link — unlike `KeyCommandRowView`
  (`agentictoolkit://recipes/key-command-row-view`), whose sibling toggle
  control links to its label via `setAccessibilityTitleUIElement` — appears
  anywhere in `KeyCommandCaptureField.swift`; the view relies entirely on
  `NSView`'s default accessibility exposure. The view is an interactive,
  first-responder-accepting control whose whole purpose is recording user
  input, and this file assigns it no accessibility role or label of its
  own; any such assignment is left entirely to the caller.
- **Label requirements**: Not implemented in source. This file
  sets no accessibility label of its own; a caller may assign one externally
  (accessibility identifiers, not labels, are assigned by the hosting row
  outside this file), but nothing in `KeyCommandCaptureField.swift` guarantees
  VoiceOver announces this control's purpose. This is the same gap as the
  Role/trait item above.
- **Announce state changes**: Not implemented in source. No
  `NSAccessibility.post(element:notification:)` call (or equivalent)
  accompanies the `isRecording` transition or a captured/committed/cancelled
  chord anywhere in source, so a VoiceOver user is not told the control
  entered or left recording mode.
- **Minimum tap target**: Not applicable to the 44×44pt touch threshold — this
  is a macOS, pointer/keyboard-driven `NSView`/`NSResponder`, with no touch
  input path in source. Its actual click target is fixed at 22pt tall by a
  minimum of 132pt wide (see Min/Max size), matching this file's own layout
  constants, not a touch guideline.
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented in source. Every color this component draws (`controlBackgroundColor`, `accentColor`/`borderColor`, `primaryTextColor`/`placeholderTextColor`) is resolved at runtime from whichever `SemanticPalette` the active theme supplies, and `KeyCommandCaptureField.swift` performs no contrast check of its own, so whether text-on-background or border-on-background contrast meets a specific ratio (e.g. WCAG 4.5:1) cannot be determined from this source file alone — it would require auditing the contrast ratio of each theme's actual token values.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `onCapture` | `((KeyboardShortcuts.Shortcut) -> Void)?` | `nil` | Called for every chord captured while recording. |
| `onCancel` | `(() -> Void)?` | `nil` | Called when the user presses bare Escape while recording. |
| `onCommit` | `(() -> Void)?` | `nil` | Called when the user presses bare Return or keypad Enter while recording. |
| `onRecordingChanged` | `((Bool) -> Void)?` | `nil` | Called when recording starts (click/focus) or stops (resign focus/`endRecording()`). |
| `displayedShortcut` | `KeyboardShortcuts.Shortcut?` | `nil` | The shortcut the bound command is already assigned to; shown when nothing is pending. |
| `pendingShortcut` | `KeyboardShortcuts.Shortcut?` | `nil` | The chord captured but not yet saved; takes precedence over `displayedShortcut` when set. The component only reads this property to decide what to display — it never assigns or clears it itself. The caller sets it (typically from `onCapture`) and clears it once the edit is committed or abandoned. |
| `placeholder` | `String` | the literal `"Click to record"` | Shown when there is nothing pending, displayed, or being recorded. |

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (unassigned) | `Click to record` | Default value of the `placeholder` property, assigned directly to an AppKit `NSTextField.stringValue` when nothing is captured, displayed, or being recorded. |
| (unassigned) | `Press keys…` | Literal assigned directly to `label.stringValue` in `refreshText()` while recording with nothing pending or displayed. |

Both strings above are literal `String` values assigned to an AppKit
`stringValue`, which — unlike a string literal passed to a SwiftUI
`Text`/`Label` (a `LocalizedStringKey`) — does not localize on its own;
`KeyCommandCaptureField.swift` contains no `NSLocalizedString`,
string-catalog key reference, or other localization mechanism for either
literal.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: source contains no animation, transition, movement, scaling, or `CATransaction`/animator-proxy call; every appearance change (`refreshText()`, `applyTheme()`) is an instantaneous property assignment. |
| Increase Contrast | Not applicable to this component directly: `KeyCommandCaptureField.swift` reads no system contrast setting (e.g. `NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast`), and neither does the `SemanticPalette` color-resolution path it calls into; whether the resulting colors are contrasty enough is tracked once, under the open question on minimum-contrast-ratio in Accessibility above, not duplicated here. |
| Differentiate Without Color | During the "prior shortcut still showing" transition, the border color changing from `borderColor` to `accentColor` is the only indicator that recording has begun; no icon, text, or shape change accompanies it until a chord is captured, unlike every other state, where the text itself changes. The component does not respond to Differentiate Without Color. |

## Privacy

- **Data collected**: Not applicable — the component captures a keyboard
  chord configuration (a key plus modifiers), not personal data, and only
  for as long as it is held in `pendingShortcut`/`displayedShortcut`.
- **Storage**: Not applicable — `KeyCommandCaptureField.swift` performs no
  read or write to disk, `UserDefaults`, or any other store; the source's own
  doc comment is explicit that this component "records and reports; it never
  saves." Persistence, if any, is owned by whatever the hosting row commits
  the chord to, which is outside this file.
- **Transmission**: Not applicable — no networking call appears anywhere in
  source.
- **Retention**: `pendingShortcut` and `displayedShortcut` are retained only
  in memory for the view's own lifetime. Neither is cleared by `endRecording()`
  or anywhere else in this file — `endRecording()` only stops recording (see
  end-recording-force-stop); assigning and clearing both properties is
  entirely the caller's responsibility. Either property is overwritten
  whenever the caller sets a new value, or released when the view is
  deallocated; this file writes nothing to persistent storage.

## Platform Notes

- **SwiftUI**: There is no built-in SwiftUI equivalent for raw key-equivalent
  interception. Wrap this exact AppKit type in an `NSViewRepresentable`
  rather than reimplementing it, because `onKeyPress`/`.focusable()`
  (macOS 14+) observe key events but do not intercept Cmd-chords ahead of the
  menu/window the way `performKeyEquivalent` does — the same problem the
  source's own doc comment describes for `NSTextField`'s field editor. Expose
  `onCapture`/`onCancel`/`onCommit`/`onRecordingChanged` as `Binding`s or
  closures passed through the representable's coordinator.
- **Compose**: There is no window-level "key equivalent" concept in Compose;
  the closest analog is a focusable composable with
  `Modifier.onPreviewKeyEvent { ... }` on a `FocusRequester`-focused node,
  which sees key events before children (and, at the platform level, before
  most system shortcut handling) the way `performKeyEquivalent` runs before
  the menu/window. Mirror unmodified-tab-passthrough by returning `false`
  (unhandled) for a bare Tab/Shift-Tab `KeyEvent` and drive the
  recording boolean from `Modifier.onFocusChanged`, the Compose analog of
  `becomeFirstResponder`/`resignFirstResponder`.
- **React/Web**: A `<div>` (or a read-only `<input>`, to get a native focus
  ring for free) with `tabIndex={0}` and an `onKeyDown` handler reading
  `event.key`/`event.code` plus the modifier booleans. Call
  `event.preventDefault()` for every combination the field decides to
  capture, since Cmd/Ctrl-chords can otherwise trigger the browser's or OS's
  own shortcuts — the DOM analog of intercepting a key equivalent before the
  menu claims it — but deliberately skip `preventDefault()` for a bare
  Tab/Shift-Tab so native focus order is preserved, mirroring
  unmodified-tab-passthrough. Add `role="button"` (or `role="group"` if the
  recorder is treated as a composite control) plus an explicit `aria-label` to
  supply the accessible label the source itself never assigns (see
  Accessibility above), and an `aria-live="polite"` region announcing
  recording start/stop and the captured-chord description to supply the
  state announcement the source itself never makes (see Announce state
  changes above) — `role="textbox"` would incorrectly tell assistive tech to
  expect editable text, which this control is not.
- **AppKit / UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/Features/KeyCommands/KeyCommandCaptureField.swift`.
  A macOS-only (`import AppKit`) `NSView` subclass, `@MainActor`, depending
  on the third-party `KeyboardShortcuts` package (github.com/sindresorhus/
  KeyboardShortcuts) for its `Shortcut` type and key constants, and on
  `AgenticToolkitCore`'s theming (`observeTheme`, `SemanticPalette`). There is
  no UIKit code path in source and none is implied — iOS has no
  key-equivalent chain or hardware-shortcut recording concept comparable to
  this component's purpose. click-focus is implemented as a direct
  `window?.makeFirstResponder(self)` call from `mouseDown(with:)`;
  redundant-recording-notification-suppression is implemented as an early
  return in the `isRecording` property's `didSet` observer when the new value
  equals the old; theme-change-repaint is driven by `observeTheme`, whose
  initializer applies the current palette synchronously before the
  initializer's own first `refreshText()` call runs.
- **WinUI 3**: Build a custom templated `Control` (or `UserControl`) styled to
  look like a `TextBox` — a rounded `Border` (`CornerRadius="5"`, matching this
  recipe's 5pt corner radius exactly, rather than Fluent's small-control
  default of 4) hosting a centered `TextBlock` — and NOT an actual `TextBox`,
  for the same reason the source avoids `NSTextField`: WinUI's
  `TextBox` consumes character input through its own composition/IME
  pipeline and would swallow the very keys being recorded. Override
  `OnPreviewKeyDown` — the WinUI analog of `performKeyEquivalent`, since it
  runs before a `KeyboardAccelerator` or menu can claim a Ctrl-chord — and
  set `e.Handled = true` for every combination the control decides to
  capture; read modifiers from `Windows.System.VirtualKeyModifiers` in place
  of `NSEvent.modifierFlags`. Drive the recording boolean from `GotFocus`/
  `LostFocus` (the WinUI analog of `becomeFirstResponder`/
  `resignFirstResponder`) with `IsTabStop="True"`, and leave `e.Handled =
  false` for a bare `VirtualKey.Tab` so normal `XYFocusKeyboardNavigation`
  still moves focus, mirroring unmodified-tab-passthrough. Represent a
  captured chord as a `VirtualKeyModifiers` + `VirtualKey` pair — WinUI has no
  ready-made equivalent to `KeyboardShortcuts.Shortcut` — and format it for
  display by joining modifier names with `+`, mirroring `Shortcut.description`.

