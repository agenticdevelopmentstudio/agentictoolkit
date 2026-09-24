---
id: e9c10ff7-4e13-4007-a963-d2a9e4006745
title: CheckboxView
domain: agentictoolkit://recipes/checkbox-view
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'A macOS ComposableSettings row: title label leading, trailing NSSwitch bound to a Bool view model.'
platforms:
- swift
- macos
tags:
- settings
- form-control
- toggle
- macos
- appkit
depends-on: []
related:
- agentictoolkit://recipes/popup-menu-choice-view
- agentictoolkit://recipes/stepper-view
references: []
approved-by: ''
approved-date: ''
---

# CheckboxView

## Overview

`CheckboxView` is a macOS `ComposableSettings` row
(`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/CheckboxView.swift`):
a title label leading and an `NSSwitch` trailing, in the same row shape System
Settings uses for a boolean setting. Despite the file and type name
`CheckboxView`, the control it draws is an `NSSwitch`, not a checkbox button —
the source's own doc comment explains the switch replaced a
checkbox-with-title button because a checkbox puts its control on the left,
the one row shape that cannot line up with the popups, steppers, and sliders
beside it in the same settings card. The row is driven by a
`ComposableSettings.ViewModel<Bool>`: the view reflects the view model's
title/value on construction and whenever the view model reports an external
change, and it writes the user's switch interactions back into the view
model's `settingObserver`.

## Behavioral Requirements

- **arranges-row-layout**: Component MUST arrange the title label and the
  toggle in a single horizontal row (`label`, then `toggle`), MUST place the
  toggle at the row's trailing edge with a flexible spacer absorbing the
  leftover width between `label` and `toggle`, and MUST pin that row to the
  edges of the view.
- **links-toggle-accessibility-title**: Component MUST set the toggle's
  accessibility title UI element to the label
  (`toggle.setAccessibilityTitleUIElement(label)`).
- **initializes-from-view-model**: Component MUST, at the end of
  initialization, set the label's text to `viewModel.title` and the toggle's
  state to `.on` when `viewModel.value` is `true` and `.off` when it is
  `false`.
- **commits-toggle-value**: Component MUST write the toggle's new boolean
  value (`sender.state == .on`) into `viewModel.settingObserver.value`
  whenever the toggle's action fires and the new value differs from the
  current `settingObserver.value`.
- **skips-redundant-commits**: Component MUST NOT write to
  `viewModel.settingObserver.value` when the toggle's new value equals the
  current `settingObserver.value`.
- **syncs-on-external-change**: Component MUST re-set the label's text to
  `viewModel.title` and the toggle's state to reflect `viewModel.value`
  whenever `viewModel.onChange` fires.
- **exposes-constituent-views**: Component MUST expose `label` and `toggle`
  as public, directly-accessible properties.
- **requires-designated-initializer**: Component MUST NOT support
  construction via `init(coder:)`; that initializer MUST trigger a fatal
  error.
- **rejects-frame-only-initialization**: Component MUST NOT support
  construction via the frame-only `init(frame:)`; that initializer MUST
  trigger a fatal error.
- **confines-to-main-actor**: Component MUST be usable only on the main
  actor; the class is declared `@MainActor`.
- **claims-sole-onchange-observer**: Component MUST assign its own handler
  to `viewModel.onChange` during initialization
  (`viewModel.onChange = { [weak self] _ in self?.update() }`), superseding
  any handler already registered on that view model instance (see
  **overwritten external observer** in Edge Cases).
- **inherits-native-keyboard-focus**: Component MUST NOT override `toggle`'s
  or `label`'s default `NSControl` focus, tabbing, or key-handling behavior;
  no `acceptsFirstResponder`, `keyDown`, or focus-ring override appears in
  source, so keyboard operability follows `NSSwitch`'s native behavior
  unchanged.

## Appearance

- **Corner radius**: Not applicable — the component adds no custom layer or
  drawing code; it only composes a stock `NSTextField` label and a stock
  `NSSwitch` into a row.
- **Padding**: `ComposableSettings.makeRow` inserts a flexible spacer between
  `label` and `toggle` (`[label, spacer, toggle]`) and sets the
  `NSStackView`'s `spacing` to `SettingsLayout.default[.rowSpacing]` = 8pt,
  which applies to the label→spacer gap; `makeRow` explicitly zeroes the
  spacer→toggle gap (`setCustomSpacing(0, after: spacer)`), so the spacer's
  own width is the only thing between the label and the toggle. `toggle`
  keeps `NSSwitch`'s own default content-hugging priority (higher than the
  spacer's `defaultLow`-minus-one), so the spacer, not the toggle, absorbs
  the row's leftover width. `pinToEdges` pins the row's top/leading/trailing/
  bottom directly to `CheckboxView`'s edges with no additional constant, so
  the component contributes 0pt of its own outer padding beyond that
  internal 8pt / 0pt spacing.
- **Font**: The label (`ComposableSettings.makeRowLabel`, `textRole:
  .button`) resolves to `ThemeTypography.defaultStyle(.button)`: 13pt,
  medium weight, proportional system font. The size scales with the active
  theme's `sizeScale` (`1.0` by default) and the label repaints
  automatically on a theme change via `ThemePaletteObserver`. `NSSwitch`
  draws no text of its own.
- **Background**: None (transparent) — `ThemedLabel.init` sets
  `drawsBackground = false`, `isBordered = false`, and `isBezeled = false`
  on the label, and neither `CheckboxView` nor the row `NSStackView` sets
  `wantsLayer` or a background color of its own.
- **Foreground/Text**: The label (`role: .primaryText`) resolves to the
  active theme's foreground color at full strength
  (`SemanticPalette.derive(.primaryText)` returns `theme.foreground`
  unchanged), recomputed live on a theme change via `ThemePaletteObserver`.
  `NSSwitch`'s on/off track and thumb colors are AppKit's own system
  rendering; `CheckboxView` sets no color on `toggle`.
- **Border**: Not applicable — no border is drawn or configured anywhere in
  `CheckboxView.swift`.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere in
  `CheckboxView.swift`.
- **Min/Max size**: Not applicable — no explicit min/max width or height
  constraint is set in `CheckboxView.swift`; sizing is governed entirely by
  the label's and `NSSwitch`'s own intrinsic content sizes, the row's 8pt
  spacing, and `pinToEdges`.

## States

| State | Appearance change |
|-------|------------------|
| Default | Label shows `viewModel.title`; toggle state reflects `viewModel.value`. |
| On | `toggle.state == .on`, drawn as `NSSwitch`'s system on-track appearance; set on init when `viewModel.value == true`, and on any user or external change that sets the value `true`. |
| Off | `toggle.state == .off`, drawn as `NSSwitch`'s system off-track appearance; set on init when `viewModel.value == false`, and on any user or external change that sets the value `false`. |
| Pressed | Not applicable: the component renders no button; the toggle's own drag/press animation while switching on or off is `NSSwitch`'s default AppKit rendering, not custom to this file. |
| Disabled | Not implemented in `CheckboxView`; `isEnabled` is never read or set on `label` or `toggle` in source. A caller may set `toggle.isEnabled` directly through the public `toggle` property, at which point `NSSwitch`'s native disabled dimming applies. |
| Focused | Not styled by `CheckboxView`; any focus ring when the toggle is tabbed to is `NSSwitch`'s own native `NSControl` focus appearance. |
| Loading | Not applicable: the component has no asynchronous operation and no loading indicator in source. |

## Accessibility

- **Role/trait**: Not customized beyond the title-element link below — no
  `setAccessibilityRole` call appears in source; `NSSwitch` carries AppKit's
  own built-in accessibility role for a switch/toggle control.
- **Label requirements**: Component MUST set
  `toggle.setAccessibilityTitleUIElement(self.label)` — per the source's own
  comment, AppKit gives a bare switch no name, so VoiceOver would otherwise
  announce it as an unlabelled control; the visible label supplies the
  accessible name instead of a separate `accessibilityLabel` string.
- **Announce state changes (e.g., loading, disabled)**: Not applicable — the
  component has no loading state and never disables itself in source (see
  States); on/off is announced by `NSSwitch`'s own native accessibility
  value reporting when `state` changes, which `CheckboxView` does not
  override.
- **Minimum tap target**: Not applicable — this is a macOS, pointer/
  trackpad-driven `NSView`/`NSControl` composition (no touch input path in
  source); the 44×44pt minimum is iOS/touch guidance, not a macOS
  pointer-interface requirement. `CheckboxView` sets no `controlSize` on
  `toggle`, so it keeps `NSSwitch`'s regular system click-target metrics.
- **Keyboard operability**: `CheckboxView` sets no `acceptsFirstResponder`,
  key-handling, or focus-ring override on `toggle` or `label` in source, so
  `toggle` keeps `NSSwitch`'s inherited `NSControl` tab order and its native
  Space/Return activation (see **inherits-native-keyboard-focus**).

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| checkbox-view-001 | arranges-row-layout | Construct `CheckboxView` with any `viewModel` | `label` and `toggle` are both subviews of a single row view that is pinned to the component's edges; a flexible spacer sits between `label` and `toggle`, so `toggle` sits at the row's trailing edge; no other layout container appears |
| checkbox-view-002 | links-toggle-accessibility-title | Construct `CheckboxView` with any `viewModel` | `toggle`'s accessibility title UI element is `label` |
| checkbox-view-003 | initializes-from-view-model | `viewModel.title = "Enable Sync"`, `viewModel.value = true` | After init, `label.stringValue == "Enable Sync"` and `toggle.state == .on` |
| checkbox-view-004 | initializes-from-view-model | `viewModel.value = false` | After init, `toggle.state == .off` |
| checkbox-view-005 | commits-toggle-value | `viewModel.settingObserver.value = false`; set `toggle.state = .on` and invoke `toggleChanged(toggle)` | `viewModel.settingObserver.value == true` after the call |
| checkbox-view-006 | skips-redundant-commits | Wrap `viewModel.settingObserver.value`'s setter with a spy; set `viewModel.settingObserver.value = true`, then set `toggle.state = .on` (same value) and invoke `toggleChanged(toggle)` | The spy records zero calls: `viewModel.settingObserver.value`'s setter is not invoked, and `viewModel.settingObserver.value` remains `true` |
| checkbox-view-007 | syncs-on-external-change | After construction, externally change `viewModel.title` and `viewModel.value`, then invoke `viewModel.onChange(newValue)` | `label.stringValue` and `toggle.state` both update to reflect the new `viewModel` state |
| checkbox-view-008 | exposes-constituent-views | Construct the component, then access `.label` and `.toggle` from outside the type | Both properties are accessible and return the same `NSTextField`/`NSSwitch` instances built during init |
| checkbox-view-009 | requires-designated-initializer | Attempt `CheckboxView(coder: someCoder)` | The call traps with a fatal error; no instance is returned |
| checkbox-view-010 | rejects-frame-only-initialization | Attempt `CheckboxView(frame: .zero)` | The call traps with a fatal error; no instance is returned |
| checkbox-view-011 | confines-to-main-actor | Attempt to construct or mutate a `CheckboxView` from off the main actor | Compiler rejects the call at compile time under Swift's `@MainActor` isolation checking |
| checkbox-view-012 | claims-sole-onchange-observer | Register an observer closure on `viewModel.onChange`, then construct a `CheckboxView` against that same `viewModel` | `viewModel.onChange` now points at `CheckboxView`'s own handler; invoking it no longer calls the previously registered closure |
| checkbox-view-013 | inherits-native-keyboard-focus | Construct `CheckboxView` in a running app, tab focus to `toggle`, then press Space | `toggle` receives keyboard focus in the window's tab order and its state flips on Space, per `NSSwitch`'s native `NSControl` behavior (unmodified by source) |

## Edge Cases

- Null/empty input: `viewModel` (`ComposableSettings.ViewModel<Bool>`) is a
  non-optional, typed constructor parameter, so Swift's type system rules
  out `nil` entirely; the component needs no nil-handling path for its one
  initializer parameter. `viewModel.title` as an empty string produces a
  label with an empty string and no crash.
- Boundary values: Not applicable — the bound value is `Bool`, a two-value
  type with no minimum/maximum or intermediate range to bound.
- Concurrent access: Not applicable — the class is declared `@MainActor`,
  so all construction and mutation is serialized to the main actor by the
  compiler (see **confines-to-main-actor**).
- Error states: Not applicable — every operation in this file (the toggle's
  target-action and the `settingObserver.value` write) is a synchronous,
  non-throwing call; no `try`, `Result`, or error-producing API appears in
  source.
- Offline/disconnected: Not applicable — the component performs no
  networking of its own; it only reads from and writes to an in-process
  `ComposableSettings.ViewModel<Bool>`.
- Overwritten external observer: `viewModel.onChange` is a single closure
  property. `CheckboxView`'s initializer unconditionally assigns
  `viewModel.onChange = { [weak self] _ in self?.update() }`, replacing
  whatever handler (if any) was previously registered on that `viewModel`
  (see **claims-sole-onchange-observer**). Constructing a second
  `CheckboxView` (or any other observer) against the same view model
  silently drops the earlier handler.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | `ComposableSettings.ViewModel<Bool>` | — (required) | Supplies the row's title and current boolean value; receives committed toggle changes via `settingObserver.value`. The initializer also overwrites this view model's `onChange` closure with the component's own `update` handler (see **claims-sole-onchange-observer**). `viewModel.explanation` (inherited from `AbstractViewModel`) is accepted by the initializer chain but never read or rendered anywhere in `CheckboxView.swift`. |

## Deep Linking

Not applicable: `CheckboxView` is a row inside a composable settings window,
not a navigable screen; no URL scheme, route, or deep-link handler appears
anywhere in `CheckboxView.swift`.

## Localization

Not applicable: the file contains no user-facing string literals of its
own. The row's title comes entirely from `viewModel.title`, a value the
caller provides, so there is nothing for this component to localize itself.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: source contains no animation, transition, or `NSAnimationContext` call; every state change is an instantaneous property assignment (`label.stringValue`, `toggle.state`). |
| Increase Contrast | Not verified for the label: `CheckboxView.swift` sets no custom `NSColor` of its own on `toggle`, and the label's color comes from the theme's `.primaryText` role via `SemanticPalette.derive`, but nothing in this source, or in the theme code searched, shows that role responding to the system Increase Contrast setting. `NSSwitch`'s own track/thumb colors are unmodified system rendering, which does track Increase Contrast automatically. |
| Differentiate Without Color | Not applicable: the on/off state is communicated through `NSSwitch`'s own track position and system iconography, not through a color-only signal introduced by this component. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears anywhere
in `CheckboxView.swift`; the row always renders once constructed.

## Analytics

Not applicable: `CheckboxView.swift` contains no analytics or telemetry
call.

## Privacy

- **Data collected**: Not applicable — the component collects no data of
  its own; it only displays a value supplied by `viewModel` and reports
  toggle changes back through `viewModel.settingObserver`.
- **Storage**: Not applicable — source performs no read/write to disk,
  `UserDefaults`, or any other store; persistence, if any, is owned by the
  `ComposableSettings.ViewModel<Bool>`/`settingObserver`, which are not part
  of this file.
- **Transmission**: Not applicable — no networking call appears anywhere in
  source.
- **Retention**: Not applicable — the view retains only its own subviews
  (`label`, `toggle`) and its reference to `viewModel` for its own
  lifetime; it persists nothing beyond that.

## Logging

Not applicable: `CheckboxView.swift` contains no logging call (no `print`,
`os_log`, or logger reference anywhere in source).

## Platform Notes

- **SwiftUI**: Replace with an `HStack` containing `Text(viewModel.title)`
  and a trailing `Toggle("", isOn: $isOn).labelsHidden()`, giving the
  `Toggle` an `.accessibilityLabel(viewModel.title)` (SwiftUI's analog of
  `setAccessibilityTitleUIElement`) so the switch announces the row's title
  rather than being unlabelled. Write the user's flips back into the
  underlying setting from the `Binding`'s setter with an equality guard,
  mirroring skips-redundant-commits.
- **Compose**: Use a `Row` with `Text(title)` leading and a trailing
  `Switch(checked = value, onCheckedChange = { ... })`. Give the `Switch` a
  `Modifier.semantics { contentDescription = title }` (the Compose analog
  of the title-element link), and commit to the backing state/view-model
  from `onCheckedChange` with an equality check before writing, mirroring
  skips-redundant-commits.
- **React/Web**: A flex row (`display: flex; align-items: center;
  justify-content: space-between`) containing a `<label>` for the title and
  an `<input type="checkbox" role="switch">` (or a styled switch component)
  whose `aria-labelledby` points at the title `<label>`'s `id` — the web
  analog of `setAccessibilityTitleUIElement`. Commit the new value on the
  input's `onChange` handler, comparing against the previous value before
  calling the parent's setter to mirror skips-redundant-commits.
- **AppKit/UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/CheckboxView.swift`.
  A macOS-only (`import AppKit`) `NSView` subclass, `@MainActor`, inside the
  `ComposableSettings` namespace, conforming to `SettingsViewProtocol`. It
  composes two subviews — an `NSTextField` label from
  `ComposableSettings.makeRowLabel` and an `NSSwitch` — into one row via
  `ComposableSettings.makeRow` and `pinToEdges`, links the switch's
  accessibility title to the label, and wires the switch's target/action
  (`toggle.target = self`, `toggle.action = #selector(toggleChanged(_:))`) —
  the AppKit plumbing behind **commits-toggle-value** — to
  `toggleChanged(_:)`. There is no UIKit code path in source; a UIKit port
  would replace `NSSwitch` with `UISwitch` and the `target`/`action`
  pattern with `.addTarget(_:action:for: .valueChanged)` — UIKit has no
  `NSCoder`-vs-frame initializer split to fatal-error on both the way
  requires-designated-initializer and rejects-frame-only-initialization do.
- **WinUI 3** (the reason this recipe exists): Build the row as a `Grid`
  with column definitions `*,Auto`: a `TextBlock` for the title in column 0
  (the `*` column lets the title claim the row's leading space, the WinUI
  analog of `makeRow`'s flexible spacer sitting between the label and the
  control); a `ToggleSwitch` (or `ToggleSwitch` restyled with
  `OnContent=""`/`OffContent=""` to read as a plain switch, matching
  `NSSwitch`'s minimal chrome) bound `IsOn="{x:Bind IsOn, Mode=TwoWay}"` in
  column 1, `HorizontalAlignment="Right"`. Set
  `AutomationProperties.LabeledBy` on the `ToggleSwitch` to the `TextBlock`
  — the WinUI analog of `setAccessibilityTitleUIElement` linking a bare
  control's name to its visible label. Write the committed value through a
  property setter that skips the assignment (and so skips raising
  `INotifyPropertyChanged`) when the incoming value already equals the
  current value, mirroring skips-redundant-commits. `ToggleSwitch`'s
  built-in `Toggled` event is the WinUI analog of `toggleChanged(_:)`.

## Design Decisions

- Decision: Draw the row's control as an `NSSwitch`, not a checkbox button,
  despite the type being named `CheckboxView`.
  Rationale: Per the source's own doc comment, the switch replaced a
  checkbox-with-title button because a checkbox puts its control on the
  left, "the one row shape that cannot line up with the popups, steppers
  and sliders beside it in the same card — and left every group looking
  like two different lists interleaved."
  Approved: pending
- Decision: Name the public property `toggle`, not `checkbox`.
  Rationale: Per the source's own doc comment, the control "has not been a
  checkbox since the row was restyled, and a name that lies about a
  control's class is the kind that gets `state = .on` written against the
  wrong API."
  Approved: pending
- Decision: Link the switch's accessibility title to the label via
  `setAccessibilityTitleUIElement` rather than setting a separate
  accessibility label string.
  Rationale: Per the source's own comment, "AppKit gives a bare switch no
  name, so VoiceOver would announce it as an unlabelled control; the
  visible label is its title element."
  Approved: pending
- Decision: Force a fatal error from both `init(coder:)` and the
  frame-only `init(frame:)`, leaving `init(with:)` as the only usable
  initializer.
  Rationale: The view has no meaningful default state — it cannot render a
  title or value without a `viewModel` — so both inherited `NSView`
  initializers that could construct it without one are intentionally
  disabled rather than left to produce a half-configured row.
  Approved: pending
- **Decision**: Keep the public type name `CheckboxView` even though it
  draws an `NSSwitch`, not a checkbox.
  **Rationale**: The type is `SettingsViewProtocol`-conforming API surface
  read by callers across `ComposableSettingsWindow`; renaming it (e.g. to
  `SwitchRowView`) is a breaking rename with no behavioral upside, while the
  file's own doc comments already correct the mismatch at the
  `toggle`-vs-`checkbox` property level (see the `toggle` naming decision
  above) — VoiceOver, callers, and tests all read `toggle`, not the type
  name, so the outer name causes no runtime confusion today.
  **Approved**: pending
- **Decision**: Unconditionally overwrite `viewModel.onChange` with the
  component's own handler during initialization, rather than chaining it
  after any previously registered handler.
  **Rationale**: `ComposableSettings.ViewModel<Bool>`'s `onChange` is a
  single closure property with no built-in multicast support; chaining
  would require a broader change to the shared view-model type, which is
  out of scope for this row view. The source accepts the tradeoff that one
  `CheckboxView` (or other observer) per view model instance is the
  supported usage (see **claims-sole-onchange-observer**).
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | platform-compliance |
| [platform-design-language](agenticdevelopercookbook://compliance/platform-compliance#platform-design-language) | passed | platform-compliance |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | passed | accessibility |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | partial | reliability |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |

`keyboard-navigable` and `screen-reader-support` rest on `toggle` being an
unmodified `NSSwitch`/`NSControl` with `setAccessibilityTitleUIElement` set
(no focus, key-handling, or accessibility-role override anywhere in
source — see **inherits-native-keyboard-focus** and
**links-toggle-accessibility-title**); `idempotent-operations` is `partial`
because repeated commits of the same toggle value are a no-op
(**skips-redundant-commits**), but constructing a second observer against
the same `viewModel` is not idempotent — it silently overwrites the prior
`onChange` handler (**claims-sole-onchange-observer**).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: shorten summary; add related sibling recipes; split target/action wiring into Platform Notes and add trailing-edge/spacer detail to arranges-row-layout; add claims-sole-onchange-observer and inherits-native-keyboard-focus requirements with test vectors; move normative language out of Edge Cases; mark Increase Contrast label color as not verified; drop the non-decision explanation entry from Design Decisions; downgrade idempotent-operations to partial and add compliance evidence sentence; backfill initial Change History row |
