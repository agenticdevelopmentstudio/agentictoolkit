<!-- leaf: implement-general-view-2/key-command-row-view--part-3 · source: key-command-row-view.md -->

# KeyCommandRowView — continued (part 3)

## Platform Notes

- **SwiftUI**: Compose a `VStack` of an `HStack` (title `Text`, a custom
  chord-recorder view, a confirm/cancel `HStack` shown conditionally, and a
  `Toggle("", isOn: $isEnabled).labelsHidden()`) over a conditionally
  visible status `Text`. Drive `isEditing`/`pendingShortcut`/`refusal` as
  `@State` on the row's own view rather than on the recorder subview, for
  the same reason the source keeps this state on the row: the recorder can
  lose focus mid-edit. Give the toggle
  `.accessibilityLabel(command.title)` as the SwiftUI analog of
  `setAccessibilityTitleUIElement`, and drive the recorder's own
  accessibility label and role explicitly rather than leaving them
  implicit — see the Accessibility gaps this recipe flags.
- **Compose**: Use a `Column` of a `Row` (title `Text`, a custom
  chord-recorder composable, a confirm/cancel `Row` shown conditionally,
  and a trailing `Switch(checked = isEnabled, onCheckedChange = { ... })`)
  over a conditionally visible status `Text`. Hold the pending-chord and
  refusal state in the row's own `remember`/view-model scope, not the
  recorder's, mirroring the row-owns-the-edit design decision. Give the
  `Switch` a `Modifier.semantics { contentDescription = command.title }`.
- **React/Web**: A flex column containing a flex row (`<label>` for the
  title, a `<button>`- or `<div role="textbox">`-based chord recorder that
  listens for `keydown` while focused, a conditionally rendered
  confirm/cancel button pair, and a styled checkbox/switch input with
  `aria-labelledby` pointing at the title) above a conditionally rendered
  status `<div>` with `aria-live="polite"` — an explicit stand-in for the
  announcement path this recipe flags as unresolved in the AppKit source.
  Keep `isEditing`/`pendingShortcut`/`refusal` in the row component's own
  state, not the recorder's.
- **AppKit/UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/Features/KeyCommands/KeyCommandRowView.swift`.
  A macOS-only (`import AppKit`) `NSView` subclass, `@MainActor`, composing
  a `ThemedLabel`, a `KeyCommandCaptureField`, a `ConfirmCancelControl`, and
  an `NSSwitch` into a two-row vertical `NSStackView` via
  `ComposableSettings`'s `makeRow`/`pinToEdges` helpers, and observing
  `KeyCommandRegistry.bindingsDidChangeNotification` to stay in sync with
  bindings committed elsewhere. There is no UIKit code path in source; a
  UIKit port would replace `NSSwitch` with `UISwitch`, replace the
  target/action wiring with `.addTarget(_:action:for: .valueChanged)`, and
  would need its own chord-recording input surface since `UIKit` has no
  `performKeyEquivalent`-based hardware-keyboard capture equivalent to
  `KeyCommandCaptureField`'s.
- **WinUI 3** (the reason this recipe exists): Build the row as a `Grid`
  with columns `Auto,*,Auto,Auto,Auto`: a `TextBlock` for the title in
  column 0; a custom focusable key-capture control (a `Border` wrapping a
  `TextBlock`, focusable via `IsTabStop="True"`, overriding
  `OnKeyDown`/`OnPreviewKeyDown` to capture the chord the same way
  `performKeyEquivalent`/`keyDown` do here) in column 1; a two-button
  confirm/cancel `StackPanel` (two `Button`s with `FontIcon` glyphs,
  `Visibility` bound to an `IsEditing` property) in column 2; and a
  `ToggleSwitch` (restyled with empty `OnContent`/`OffContent` to match
  `NSSwitch`'s minimal chrome) bound `IsOn="{x:Bind IsEnabled, Mode=TwoWay}"`
  in column 3. Add a `TextBlock` for the status readout in a second `Grid`
  row, its `Visibility` bound to `IsEditing OR HasRefusal`. Hold
  `IsEditing`, `PendingShortcut`, and `Refusal` as properties on the row's
  own code-behind or view model — not on the recorder control — mirroring
  the row-owns-the-edit decision below, since a WinUI `UserControl` can
  just as easily lose logical focus mid-edit as an AppKit view can lose
  first responder. Set `AutomationProperties.LabeledBy` on the `ToggleSwitch`
  to the `TextBlock`, the WinUI analog of `setAccessibilityTitleUIElement`,
  and set `AutomationProperties.Name` explicitly on the chord-recorder
  `Border` — WinUI's analog of the accessibility label this recipe flags as
  missing on the AppKit capture field. Raise a
  `Microsoft.UI.Xaml.Automation.Peers.AutomationPeer`
  `RaiseNotificationEvent` (or set
  `AutomationProperties.LiveSetting="Polite"` on the status `TextBlock`)
  when the refusal or availability text changes — the WinUI analog of the
  announcement gap this recipe flags in the AppKit source.

## Design Decisions

- **Decision**: The row, not `KeyCommandCaptureField`, owns the pending-edit
  state (`isEditing`, `pendingShortcut`) and the confirm/cancel pair's
  visibility.
  **Rationale**: Per the source's own doc comment, "a captured chord is
  pending until the user commits it, and focus can leave in the middle of
  that (they click the checkmark, after all), so the state that decides
  whether ✓ and ✗ are on screen cannot live in the thing that loses focus."
  **Approved**: pending
- **Decision**: `commitEdit()` sets the committed binding's enabled flag to
  `true` whenever the command has no authored binding or its current
  shortcut is `nil`, but preserves the existing enabled flag when
  re-recording an already-authored, already-bound command.
  **Rationale**: Per the source's own comment, "recording a chord is
  unambiguous intent to use it, so the command comes on — unless the user
  themselves switched it off, in which case the switch stays where they
  put it. A shipped 'off' is not the user's choice: the suggested global
  chords ship off, and recording over one must not save a chord that
  silently never fires."
  **Approved**: pending
- **Decision**: `toggleChanged()` snaps the switch back to off and shows a
  refusal message, rather than silently ignoring the attempt, when turning
  a command on would collide with another command's chord.
  **Rationale**: Per the source's own comments, "switching on puts the chord
  back in play, so it has to be free: a chord two commands hold fires
  both," and "the switch snapping back by itself would otherwise read as a
  control that is broken rather than one that said no."
  **Approved**: pending
- **Decision**: The readout row's visibility is driven by `isEditing ||
  refusal != nil`, not by `isEditing` alone.
  **Rationale**: `toggleChanged()`'s refusal path never sets `isEditing`, so
  without this the toggle's refusal message would have nowhere visible to
  appear; the refusal persists on screen until the next edit begins,
  because `isEditing`'s `didSet` is what clears `refusal`.
  **Approved**: pending
- **Decision**: `onRecordingChanged(false)` clears the mid-edit state only
  when no chord is pending; when a chord is pending, the mid-edit state is
  left untouched.
  **Rationale**: Per the source's own comment, "clicked in and straight
  back out without pressing anything: there is nothing to confirm, so the
  pair should not linger" — but when a chord *is* pending, the mid-edit
  state must survive the field resigning first responder, since clicking
  the confirm/cancel pair itself moves focus off the capture field before
  the commit or cancel runs.
  **Approved**: pending
