<!-- leaf: implement-general-view-2/key-command-row-view--part-2 · source: key-command-row-view.md -->

# KeyCommandRowView — continued (part 2)

## Appearance

- **Corner radius**: Not applicable to `KeyCommandRowView` itself — the row
  sets no `wantsLayer`/`cornerRadius` of its own; it only arranges four
  subviews in stack views. The capture field and the confirm/cancel pair
  each draw their own 5pt-corner-radius chrome, but that is those
  components' own appearance, not this file's.
- **Padding**: The main row's `NSStackView` (built by `NSView.makeRow`) uses
  `SettingsLayout.default[.rowSpacing]` = 8pt between the title label and
  the flexible spacer `makeRow` inserts after it, with the spacer-to-field
  gap zeroed (`setCustomSpacing(0, after: spacer)`), so the spacer's own
  width is the only room between the label and the capture field; the
  capture field, confirm/cancel pair, and toggle then sit with the same 8pt
  `rowSpacing` between each of them. The readout row is built the same way,
  from a blank value label and the status label, so its own leading gap is
  likewise the spacer's width. The outer vertical stack (main row over
  readout row) uses a spacing of 4pt, set directly in
  `KeyCommandRowView.swift`. `pinToEdges` pins that outer stack to the
  component's top/leading/trailing/bottom with no additional constant, so
  the component contributes 0pt of outer padding beyond its internal 8pt /
  4pt spacing.
- **Font**: The title label (`ComposableSettings.makeRowLabel`, `textRole:
  .button`) resolves to 13pt, medium weight. The status label and the blank
  spacer label (`ComposableSettings.makeValueLabel`, `textRole: .caption`)
  resolve to 11pt, regular weight. Neither the capture field's internal
  label nor the confirm/cancel pair's buttons are styled by this file; they
  are those components' own appearance.
- **Background**: None (transparent) on `KeyCommandRowView` itself — no
  `wantsLayer` or background color is set anywhere in
  `KeyCommandRowView.swift`. The capture field and confirm/cancel pair each
  paint their own themed background layer, but that is their own chrome.
- **Foreground/Text**: The title label uses the primary-text role. The
  status label's role switches between secondary-text, success, and danger
  depending on pending-chord availability (see States and
  **colors-status-label-by-availability**); the blank spacer label in the
  readout row keeps its default secondary-text role, unused for display.
- **Border**: Not applicable to `KeyCommandRowView` itself — no border is
  drawn or configured anywhere in `KeyCommandRowView.swift`. The capture
  field draws its own 1pt border (accent-colored while recording, otherwise
  the theme's border color) and the confirm/cancel pair draws its own 1pt
  border; both are those components' own appearance.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere in
  `KeyCommandRowView.swift`.
- **Min/Max size**: `KeyCommandRowView` sets no explicit min/max width or
  height constraint of its own; its size is the sum of its subviews'
  intrinsic sizes plus the row/stack spacing described under Padding. Of
  its children, the capture field fixes its own height to 22pt and its own
  minimum width to 132pt, and the confirm/cancel pair fixes its own height
  to 20pt with two 24pt-wide buttons — both are those components' own
  constraints, reflected here only because they set the row's effective
  minimum width and height.

## Accessibility

- **Role/trait**: `KeyCommandRowView` sets no accessibility role on itself.
  The toggle keeps `NSSwitch`'s native switch role via
  **links-toggle-accessibility-title**. The capture field's own role belongs
  to its component; see `agentictoolkit://recipes/key-command-capture-field`,
  which records the open question.
- **Label requirements**: The toggle's accessible name comes from the title
  label via **links-toggle-accessibility-title**. The capture field is given
  only an accessibility *identifier*
  (`"settings.key-commands.<id>.recorder"`, a UI-test hook) and no
  accessibility *label* or title-element link to the title label; whether a
  screen reader announces it meaningfully depends on AppKit's default
  exposure of its internal, unlabeled text field, which neither this file
  nor `KeyCommandCaptureField.swift` configures explicitly.
- **Announce state changes (e.g., loading, disabled)**: A refusal or an
  availability change updates the status label's `stringValue` and `role`
  (color) synchronously, but no call in `KeyCommandRowView.swift` posts an
  accessibility announcement (for example,
  `NSAccessibility.post(element:notification:)`). A sighted user sees the
  refusal appear immediately next to the switch; a VoiceOver user gets no
  announcement of it from this file.
- **Minimum tap target**: Not applicable — this is a macOS, pointer/
  trackpad-driven `NSView` composition with no touch input path in source;
  the 44×44pt minimum is iOS/touch guidance. `KeyCommandRowView` sets no
  `controlSize` on the toggle, so it keeps `NSSwitch`'s regular system
  click-target metrics.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `command` | `KeyCommandDescriptor` | — (required) | The one command this row edits: supplies the title, id, and default binding used throughout. |
| `registry` | `KeyCommandRegistry` | — (required) | The shared registry the row reads bindings from and writes committed bindings and toggle changes to; also the object the row observes for external binding changes. |

## Localization

None of the user-facing strings this file introduces route
through a localization mechanism (no `NSLocalizedString`, no String Catalog
key) — each is a Swift string literal or string interpolation written
directly in `KeyCommandRowView.swift`. `command.title` itself is a
caller-supplied value (populated by whatever feature declares the
`KeyCommandDescriptor`) and is out of this file's scope, matching how
sibling settings-row recipes treat a caller-supplied title. No String
Catalog or localization key exists for any of these literals; the table
below lists them as proposed keys, not keys present in source. The
`"available"` / `"unavailable"` availability labels shown in the status
label come from `KeyCommandAvailability`, not from this file, and so are
not listed below.

| Proposed String Key | Literal (en) | Context |
|-----------|-------------|---------|
| `key_command_row.title_format` | `"<title>:"` (trailing colon appended to `command.title`) | Title label text |
| `key_command_row.placeholder.click_to_record` | `Click to record` | Capture field placeholder when unbound |
| `key_command_row.status.press_a_key_combination` | `press a key combination` | Status label when a pending chord has not yet been captured |
| `key_command_row.status.refusal_prefix` | `can't switch on — ` | Prefix before the availability reason when a toggle-on attempt is refused |
| `key_command_row.status.reason_separator` | ` — ` | Separator concatenated between the availability label and its reason |

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: `KeyCommandRowView.swift` performs no animation, transition, or `NSAnimationContext` call anywhere — every visibility and state change (`isHidden`, `stringValue`, `role`, toggle `state`) is an instantaneous property assignment, not even an opacity fade. |
| Increase Contrast | Not implemented in source: this file sets no independent high-contrast styling of its own. The title and status labels' colors are `ThemeRole` tokens (`.primaryText`, `.secondaryText`, `.success`, `.danger`) resolved by the active `SemanticPalette`; whatever Increase Contrast adjustment that palette makes is inherited automatically and is that theming system's concern, not this file's. `NSSwitch`'s on/off rendering is AppKit's own, which tracks Increase Contrast natively. |
| Differentiate Without Color | Satisfied without a color-only signal: the status label's *text* changes with availability (`"available"`, `"unavailable — <reason>"`, `"press a key combination"`, or the refusal sentence) in addition to its color role, so availability is never communicated by color alone. |

## Privacy

- **Data collected**: The row surfaces the one piece of user-authored data
  it edits — the chord and enabled flag for `command.id` — but does not
  collect anything beyond what the user types into the capture field or
  toggles on the switch.
- **Storage**: `KeyCommandRowView` performs no storage of its own; it
  delegates persistence entirely to `registry.setBinding(_:for:)`, which
  writes into `UserSettings.keyCommandBindings`
  (`UserSettings+KeyCommands.swift`) — a component not covered by this
  file.
- **Transmission**: Not applicable — no networking call appears anywhere in
  `KeyCommandRowView.swift`.
- **Retention**: Not applicable to this file — the row retains only its own
  subviews, its `command`, its `registry` reference, and its own transient
  edit state (`pendingShortcut`, `isEditing`, `refusal`) for its own
  lifetime; how long the committed binding itself is retained is the
  registry/`UserSettings` layer's concern, not this file's.

