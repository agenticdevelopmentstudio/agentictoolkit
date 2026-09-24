---
id: b85dc186-31e9-472b-99ea-2c097fc926c8
title: ExtensionInputBoxViewController
domain: agentictoolkit://recipes/extension-input-box-view-controller
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: An AppKit NSViewController presenting one vscode.window.showInputBox request
  - an optional title and prompt, a text or secure field, and a live validation message.
platforms:
- swift
- macos
tags:
- extensions
- form-control
- text-input
- validation
- macos
- appkit
depends-on: []
related: []
references: []
approved-by: ''
approved-date: ''
---

# ExtensionInputBoxViewController

## Overview

`ExtensionInputBoxViewController` is an AppKit `NSViewController` from
AgenticToolkit's VS Code extension-host UI
(`packages/apple/AgenticToolkit/macOS/Features/Extensions/UI/ExtensionInputBoxViewController.swift`)
that presents one `vscode.window.showInputBox` request: an optional title,
an optional prompt, a single text (or secure) field, and a validation
message below it. It is built AppKit-rather-than-SwiftUI on
`ExtensionQuickPickViewController`'s precedent, sharing that class's
presentation panel and its `PickerKeyboardController` keyboard-dispatch
helper. It reads its content from an `ExtensionInputBoxModel`/
`ExtensionInputBoxRequest`, revalidates on every edit (and once for a
pre-filled value), and reports the user's decision through the `onAccept`,
`onCancel`, and `onValueChanged` callbacks its owner assigns.

## Behavioral Requirements

- **renders-optional-title-label**: Component MUST create and display
  `titleLabel` as a `ThemedLabel` in the `.primaryText` role and `.heading`
  text role, populated with `model.request.title`, when
  `model.request.title` is non-nil and non-empty. Component MUST NOT
  create a title label otherwise.
- **renders-optional-prompt-label**: Component MUST create and display
  `promptLabel` as a `ThemedLabel` in the `.secondaryText` role and
  `.caption` text role, populated with `model.request.prompt`, when
  `model.request.prompt` is non-nil and non-empty. Component MUST NOT
  create a prompt label otherwise.
- **selects-secure-field-once-at-init**: Component MUST construct its
  field as `NSSecureTextField` when `model.request.isPassword` is `true`,
  and as `NSTextField` otherwise, and MUST make that choice exactly once,
  during `init(model:)`, never re-evaluating or rebuilding the field
  afterward.
- **seeds-field-placeholder**: Component MUST set the field's
  `placeholderString` to `model.request.placeHolder`, or to an empty
  string when `model.request.placeHolder` is `nil`.
- **seeds-field-value-on-load**: Component MUST set the field's
  `stringValue` to `model.value` in `viewDidLoad`.
- **validates-prefill-once-per-appearance-cycle**: Component MUST, only
  the first time `viewDidAppear` runs for a given presentation, call
  `model.beginValidating()` followed by `onValueChanged(model.value)`.
  Component MUST NOT repeat that call on any subsequent `viewDidAppear`
  invocation for the same presentation.
- **commits-value-and-revalidates-on-edit**: Component MUST, on every
  change to the field's text (`controlTextDidChange`), set `model.value`
  to the field's current `stringValue`, call `model.beginValidating()`,
  and invoke `onValueChanged` with that same new value, as one round trip
  per edit.
- **clears-pending-acceptance-on-edit**: Component MUST reset
  `acceptWhenValidationLands` to `false` on every change to the field's
  text, before performing the commit-and-revalidate round trip.
- **accepts-only-when-model-permits**: Component MUST invoke
  `onAccept(model.value)` when Return is pressed while `model.canAccept`
  is `true`. Component MUST NOT invoke `onAccept` when `model.canAccept`
  is `false`.
- **defers-acceptance-while-validating**: Component MUST, when Return is
  pressed while `model.isValidating` is `true`, record that Return as
  pending (`acceptWhenValidationLands = true`) rather than accepting
  immediately or discarding the keystroke, and MUST replay it — invoking
  `onAccept(model.value)` — the next time `showValidation(_:)` runs and
  finds `model.canAccept` `true`.
- **drops-return-under-standing-error**: Component MUST silently drop a
  Return pressed while `model.canAccept` is `false` and
  `model.isValidating` is also `false` (a standing `.error` validation),
  without recording it for later replay.
- **cancels-on-escape**: Component MUST invoke `onCancel()` when Escape is
  pressed while the view's window is the event's window, via the
  window-level Escape monitor started in `viewDidAppear` and stopped in
  `viewWillDisappear`.
- **shows-validation-message**: Component MUST, when `showValidation(_:)`
  is called with a non-nil validation, set `validationLabel.isHidden` to
  `false`, set its `stringValue` to `validation.message`, and set its
  `role` to `.danger` for `.error` severity, `.warning` for `.warning`
  severity, or `.secondaryText` for `.information` severity.
- **hides-validation-message-when-valid**: Component MUST set
  `validationLabel.isHidden` to `true` when `showValidation(_:)` is called
  with `nil`.
- **focuses-field-then-applies-initial-selection**: Component MUST, when
  `focusField()` is called, first make the field the window's first
  responder, and only then set the field editor's `selectedRange` to
  `model.initialSelectionUTF16Range()`.
- **sizes-panel-from-fitted-layout**: Component MUST set
  `preferredContentSize` to a fixed width of 480pt and a height equal to
  the root view's fitted Auto Layout height (`root.fittingSize.height`),
  floored at 72pt.

## Appearance

- **Corner radius**: Not applicable — the root view sets `wantsLayer =
  true` but no `cornerRadius` (or any other layer-drawing property) is set
  anywhere in `ExtensionInputBoxViewController.swift`.
- **Padding**: 12pt leading/trailing padding on every subview (`leadingAnchor`/
  `trailingAnchor` constants of `12`/`-12` against the root view). Vertically,
  each present subview's top is pinned 12pt below the previous one — the
  first present view (title, or prompt, or the field) sits 12pt below the
  root's top; the field sits 12pt below whichever of title/prompt is last
  present. `validationLabel` sits 8pt below the field
  (`validationLabel.topAnchor` = `field.bottomAnchor + 8`) and is pinned
  12pt above the root's bottom edge.
- **Font**: `titleLabel` resolves `ThemeTypography.defaultStyle(.heading)`
  — 15pt, semibold, proportional system font. `promptLabel` and
  `validationLabel` both resolve `defaultStyle(.caption)` — 11pt, regular
  weight; `validationLabel`'s `textRole` never changes with severity, only
  its `role` (color) does. Both scale with the active theme's `sizeScale`
  and repaint on a theme change (`ThemedLabel`'s own `ThemePaletteObserver`).
  The field itself (`NSTextField`/`NSSecureTextField`) has no font set
  anywhere in this file — it renders in AppKit's stock system-font default
  for a text field, not driven by `ThemeTypography` at all.
- **Background**: The root view is layer-backed (`wantsLayer = true`) but
  no background color is set on it in this file. `titleLabel`,
  `promptLabel`, and `validationLabel` are transparent —
  `ThemedLabel.init` sets `drawsBackground = false`, `isBordered = false`,
  `isBezeled = false`. The field's fill is AppKit's stock bezeled
  `NSTextField`/`NSSecureTextField` chrome; no `drawsBackground` or
  `backgroundColor` override is set on it in source.
- **Foreground/Text**: `titleLabel` uses role `.primaryText` (the active
  theme's foreground color at full strength). `promptLabel` uses
  `.secondaryText`. `validationLabel`'s role switches with severity —
  `.danger` / `.warning` / `.secondaryText` for `.error` / `.warning` /
  `.information` — recomputed live on every `showValidation(_:)` call and
  on theme change. The field's text color is never set in this file; it
  renders in AppKit's stock default text color, not theme-driven.
- **Border**: Not applicable for the labels — each is `isBordered = false`,
  `isBezeled = false`. The field's border is AppKit's stock
  `NSTextField`/`NSSecureTextField` bezel; no custom border is configured
  in source.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere
  in `ExtensionInputBoxViewController.swift`.
- **Min/Max size**: `preferredContentSize` fixes width at 480pt exactly
  (no min/max range around it) and sets height to
  `max(root.fittingSize.height, 72)` — a 72pt floor with no explicit
  ceiling.

## States

| State | Appearance change |
|-------|------------------|
| Default | `titleLabel`/`promptLabel` shown per `model.request` (or omitted, per those requirements); field shows `model.value`; `validationLabel` starts `isHidden = true`. |
| Pressed | Not applicable — no `NSButton` or other pressable control appears anywhere in `ExtensionInputBoxViewController.swift`; the field is a text-entry control, not a press target. |
| Disabled | Not applicable — `isEnabled` is never set on the field (or on either label) anywhere in source; the field is always enabled once the panel is on screen. |
| Focused | The field can become first responder (via normal Tab/click focus, or via `focusField()`). No custom focus-ring styling is set in source — AppKit's default `NSTextField`/`NSSecureTextField` focus ring applies. `focusField()` additionally applies `model.initialSelectionUTF16Range()` as the field's text selection, but only when explicitly invoked — not automatically on every focus event. |
| Loading | NEEDS REVIEW: Not implemented in source. Behavior undefined. `model.isValidating` (set true by `beginValidating()`, cleared by `recordValidation(_:)`) changes only the acceptance logic (Return is held and replayed — see `defers-acceptance-while-validating`); no view property (opacity, a spinner, a disabled state, or any other visual cue) is read from or set based on `model.isValidating` anywhere in `ExtensionInputBoxViewController.swift`. What is missing: whether a user should see any indication that the extension's `validateInput` is in flight for the currently-typed value. What would settle it: a design decision on whether to add a visible in-progress indicator (e.g. dim the validation area or show a small progress indicator) while `model.isValidating` is true, or confirmation that no indicator is intended because the round trip is expected to be fast. |

## Accessibility

- **Role/trait**: Not observable beyond AppKit's defaults — no
  `setAccessibilityRole` or similar call appears in source. The field
  calls `.accessibilityID("extension-input-box.field")` (an accessibility
  *identifier*, for UI testing, not a role or label). `NSTextField`/
  `NSSecureTextField` each carry AppKit's built-in text-field accessibility
  role automatically.
- **Label requirements**: NEEDS REVIEW: Not implemented in source.
  Behavior undefined. No `accessibilityLabel`, `setAccessibilityLabel`, or
  `setAccessibilityTitleUIElement` call links the field to `titleLabel` or
  `promptLabel` anywhere in `ExtensionInputBoxViewController.swift`. What
  is missing: whether VoiceOver announces the panel's title/prompt text
  when focus lands in the field, or only whatever AppKit derives on its
  own (the field has no `stringValue`-derived label of its own beyond its
  placeholder). What would settle it: a VoiceOver pass over an
  instantiated panel, or a decision to call something equivalent to
  `field.setAccessibilityTitleUIElement(promptLabel ?? titleLabel)` in
  `loadView`.
- **Announce state changes (e.g., loading, disabled)**: Not applicable for
  Disabled — the component never disables itself (see States). For the
  validation message: NEEDS REVIEW: Not implemented in source. Behavior
  undefined. `showValidation(_:)` toggles `validationLabel.isHidden` and
  its text with no explicit accessibility notification call (e.g. an
  `NSAccessibility.post` equivalent) anywhere in source. What is missing:
  confirmation that VoiceOver announces the validation message appearing
  or disappearing without an explicit notification. What would settle it:
  a VoiceOver pass over a live validation round trip, or an explicit
  accessibility-announcement call added alongside the
  `isHidden`/`stringValue` changes.
- **Minimum tap target**: Not applicable — this is a macOS,
  pointer/trackpad-driven `NSViewController`/`NSControl` composition (no
  touch input path in source); the 44×44pt minimum is iOS/touch guidance,
  not a macOS pointer-interface requirement.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| extension-input-box-view-controller-001 | renders-optional-title-label | `model.request.title = "Enter API Key"` | `titleLabel` is created, non-nil, `role == .primaryText`, `textRole == .heading`, `stringValue == "Enter API Key"` |
| extension-input-box-view-controller-002 | renders-optional-title-label | `model.request.title = nil` (and, separately, `= ""`) | `titleLabel` is `nil`; no title view is added to `root`'s subviews |
| extension-input-box-view-controller-003 | renders-optional-prompt-label | `model.request.prompt = "Used only for this session."` | `promptLabel` is created, non-nil, `role == .secondaryText`, `textRole == .caption`, `stringValue` matches |
| extension-input-box-view-controller-004 | renders-optional-prompt-label | `model.request.prompt = nil` | `promptLabel` is `nil`; no prompt view is added to `root`'s subviews |
| extension-input-box-view-controller-005 | selects-secure-field-once-at-init | Construct with `model.request.isPassword = true` | `field` is an `NSSecureTextField` instance |
| extension-input-box-view-controller-006 | selects-secure-field-once-at-init | Construct with `model.request.isPassword = false` | `field` is a plain `NSTextField` instance, not `NSSecureTextField` |
| extension-input-box-view-controller-007 | seeds-field-placeholder | `model.request.placeHolder = "org/repo"` | `field.placeholderString == "org/repo"` after `loadView` |
| extension-input-box-view-controller-008 | seeds-field-placeholder | `model.request.placeHolder = nil` | `field.placeholderString == ""` after `loadView` |
| extension-input-box-view-controller-009 | seeds-field-value-on-load | `model.value = "prefilled"` | After `viewDidLoad`, `field.stringValue == "prefilled"` |
| extension-input-box-view-controller-010 | validates-prefill-once-per-appearance-cycle | Call `viewDidAppear()` twice in succession on a fresh instance | `model.beginValidating()`/`onValueChanged(model.value)` fire exactly once, on the first call only |
| extension-input-box-view-controller-011 | commits-value-and-revalidates-on-edit | Set `field.stringValue = "abc"` and invoke `controlTextDidChange(_:)` | `model.value == "abc"`; `model.isValidating == true`; `onValueChanged` is invoked once with `"abc"` |
| extension-input-box-view-controller-012 | clears-pending-acceptance-on-edit | With `acceptWhenValidationLands == true`, invoke `controlTextDidChange(_:)` | `acceptWhenValidationLands == false` after the call |
| extension-input-box-view-controller-013 | accepts-only-when-model-permits | `model.canAccept == true`; invoke `control(_:textView:doCommandBy: #selector(NSResponder.insertNewline(_:)))` | `onAccept` is invoked exactly once, with `model.value` |
| extension-input-box-view-controller-014 | accepts-only-when-model-permits | `model.canAccept == false`; invoke the same Return command | `onAccept` is not invoked |
| extension-input-box-view-controller-015 | defers-acceptance-while-validating | `model.isValidating == true`; press Return; then call `showValidation(nil)` (making `model.canAccept == true`) | `acceptWhenValidationLands` is set `true` on the Return press, then `onAccept(model.value)` fires exactly once inside the `showValidation(nil)` call |
| extension-input-box-view-controller-016 | drops-return-under-standing-error | `model.isValidating == false`, `model.canAccept == false` (standing `.error`); press Return | `onAccept` is not invoked; `acceptWhenValidationLands` remains `false` |
| extension-input-box-view-controller-017 | cancels-on-escape | With the monitor started (`viewDidAppear` ran) and the view's window key, dispatch a `keyDown` with `keyCode == 53` for that window | `onCancel()` is invoked exactly once |
| extension-input-box-view-controller-018 | shows-validation-message | Call `showValidation(ExtensionInputValidation(message: "Required", severity: .error))` | `validationLabel.isHidden == false`; `stringValue == "Required"`; `role == .danger` |
| extension-input-box-view-controller-019 | shows-validation-message | Call `showValidation(ExtensionInputValidation(message: "Heads up", severity: .warning))` (and, separately, `.information`) | `role == .warning` for `.warning` (and `role == .secondaryText` for `.information`) |
| extension-input-box-view-controller-020 | hides-validation-message-when-valid | Call `showValidation(nil)` | `validationLabel.isHidden == true` |
| extension-input-box-view-controller-021 | focuses-field-then-applies-initial-selection | Call `focusField()` with `model.initialSelectionUTF16Range()` resolving to `NSRange(location: 2, length: 3)` | The field is first responder, and `field.currentEditor()?.selectedRange == NSRange(location: 2, length: 3)` |
| extension-input-box-view-controller-022 | sizes-panel-from-fitted-layout | Load the view with content whose fitted Auto Layout height is 40pt (below the 72pt floor) | `preferredContentSize == NSSize(width: 480, height: 72)` |
| extension-input-box-view-controller-023 | sizes-panel-from-fitted-layout | Load the view with content whose fitted Auto Layout height is 160pt | `preferredContentSize == NSSize(width: 480, height: 160)` |

## Edge Cases

- Null/empty input — title/prompt: `model.request.title`/`prompt` being
  `nil` or `""` suppresses that label entirely (see
  `renders-optional-title-label`/`renders-optional-prompt-label`). MUST.
- Null/empty input — value: `model.value` may be `""` (an empty pre-filled
  or typed value). Per `ExtensionInputBoxModel.onAccept`'s own contract,
  "an empty string is a value, and Return accepts it" — Return with an
  empty field and `model.canAccept == true` MUST invoke `onAccept("")`,
  not be treated as "nothing entered." MUST.
- Boundary values — initial selection: `model.initialSelectionUTF16Range()`
  (called directly by `focusField()`) clamps an out-of-bounds
  `valueSelection` to the value's length, and falls back to a zero-length
  range at the very end of the value (`NSRange(location: value.utf16.count,
  length: 0)`) when the Character-offset-to-`String.Index` conversion
  cannot resolve. `focusField()` MUST apply whatever range this returns
  without additional validation of its own. MUST.
- Concurrent access: Not applicable — the class is `@MainActor`-isolated,
  so all field-delegate callbacks, keyboard dispatch, and validation
  replies are serialized on the main actor; there is no code path by
  which two threads mutate the controller's state simultaneously.
- Error states: The only failure mode that reaches this file is a
  `.error`-severity `ExtensionInputValidation`, which it MUST always
  render via `shows-validation-message` and MUST always block acceptance
  for via `accepts-only-when-model-permits`/`drops-return-under-standing-error`.
  This file calls no throwing or networked API itself; the extension's
  `validateInput` call and any failure within it are owned by
  `ExtensionPickerPresenter`/the `ExtensionInputBoxPresenting` conformer
  above this controller, not by `ExtensionInputBoxViewController`. MUST.
- Offline/disconnected: Not applicable — the component performs no
  networking of its own; validation answers arrive as already-resolved
  `ExtensionInputValidation` values passed into `showValidation(_:)`.
- Return held, then superseded by a further edit: a Return pressed while
  `model.isValidating` is `true` sets `acceptWhenValidationLands = true`;
  if the user types again before the answer lands,
  `clears-pending-acceptance-on-edit` resets that flag to `false`, so the
  held Return is discarded rather than replayed against a value the field
  no longer holds. MUST.
- Repeated `viewDidAppear` for one presentation: guarded by
  `hasValidatedPrefill` so the pre-filled value is validated once per
  presentation, not once per `viewDidAppear` call (see
  `validates-prefill-once-per-appearance-cycle`). MUST.
- `isPassword` cannot change mid-presentation: the field's class is fixed
  in `init(model:)` from `model.request.isPassword`; there is no code
  path in this file that rebuilds or reclasses the field afterward, so a
  hypothetical later change to that flag on the same model has no effect.
  MUST NOT re-evaluate.
- Arrow keys (up/down) inside the field are consumed with no visible
  effect: `control(_:textView:doCommandBy:)` routes every `doCommandBy:`
  selector through the shared `PickerKeyboardController.handle(_:)`, which
  also recognizes `moveUp`/`moveDown` and reports them handled
  (`onMoveSelection` is invoked and the selector is treated as consumed).
  This controller never assigns `onMoveSelection`, so pressing the up or
  down arrow while the field has focus is swallowed (marked handled, so it
  does not fall through to the field's default behavior) but produces no
  observable change. MUST — this is the shared controller's defined
  behavior, not an accidental gap in this file (see Design Decisions).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `model` | `ExtensionInputBoxModel` | — (required, `init(model:)`) | Supplies `request.title`/`prompt`/`placeHolder`/`isPassword`/`valueSelection`, the current `value`, and validation state. Read once for the field's class at init; read again in `loadView`/`viewDidLoad` to seed content; read continuously via `model.value`/`canAccept`/`isValidating` for the lifetime of the panel. |
| `onAccept` | `(String) -> Void` | no-op (`{ _ in }`) | Called with `model.value` when Return is accepted (see `accepts-only-when-model-permits`/`defers-acceptance-while-validating`). |
| `onCancel` | `() -> Void` | no-op (`{}`) | Called when Escape is pressed (see `cancels-on-escape`). |
| `onValueChanged` | `(String) -> Void` | no-op (`{ _ in }`) | Called with the field's new value whenever it needs (re)validating — on every edit and once for the pre-filled value (see `commits-value-and-revalidates-on-edit`/`validates-prefill-once-per-appearance-cycle`). |

## Deep Linking

Not applicable: `ExtensionInputBoxViewController` is modal panel content
instantiated by `ExtensionPickerPresenter` in direct response to one
`vscode.window.showInputBox` call, not a navigable or URL-addressable
screen; no URL scheme, route, or deep-link handler appears anywhere in
`ExtensionInputBoxViewController.swift`.

## Localization

Not applicable: every user-facing string this component surfaces — title,
prompt, placeholder, value, and validation message — is passed in at
runtime from `model.request`/`showValidation(_:)`'s parameter, i.e. text
the requesting extension itself already chose in whatever locale it
targets. `ExtensionInputBoxViewController.swift` contains no user-facing
string literal of its own to localize (this is AppKit, not SwiftUI, so a
literal assigned to `stringValue`/`placeholderString` would be unlocalized
if one existed — none does).

## Accessibility Options

- **Reduce Motion**: Not applicable — no animation, transition, or
  `NSAnimationContext` call appears anywhere in
  `ExtensionInputBoxViewController.swift`; every state change (label
  text, `isHidden`, `role`) is an instantaneous property assignment.
- **Increase Contrast**: Not applicable — the file sets no custom
  `NSColor` of its own; `titleLabel`/`promptLabel`/`validationLabel`
  colors all come from `ThemedLabel`'s role-based palette lookup, which
  follows the active theme/system Increase Contrast automatically. The
  field's coloring is AppKit's own default control appearance, likewise
  system-managed.
- **Differentiate Without Color**: NEEDS REVIEW: Not implemented in
  source. Behavior undefined. `validationLabel`'s three severities
  (`.error`/`.warning`/`.information`) are distinguished only by `role`
  (color) in `showValidation(_:)` — no icon, prefix, or other non-color
  cue is added anywhere in source. What is missing: whether Differentiate
  Without Color requires an additional non-color cue to distinguish
  severities. What would settle it: a decision on whether/how to add a
  severity icon or text prefix when Differentiate Without Color is
  enabled.

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears
anywhere in `ExtensionInputBoxViewController.swift`; the panel always
renders once constructed.

## Analytics

Not applicable: `ExtensionInputBoxViewController.swift` contains no
analytics or telemetry call.

## Privacy

- **Data collected**: The field's typed value — potentially a secret
  (e.g. a token or password) when `model.request.isPassword` is `true`,
  in which case `NSSecureTextField` masks it on screen. The component
  does not otherwise classify or redact this value; it holds it in
  `model.value` and returns it verbatim via `onAccept`.
- **Storage**: Not applicable — `ExtensionInputBoxViewController` and
  `ExtensionInputBoxModel` hold the value only in memory (a `String`
  property) for the panel's lifetime; no write to disk, `UserDefaults`,
  or any other persistent store appears in source.
- **Transmission**: Not applicable within this file — the accepted value
  is handed to the caller-supplied `onAccept` closure; this file performs
  no networking itself. Where that value goes afterward (back across the
  extension-host bridge to the requesting extension) is owned by
  `ExtensionPickerPresenter`/the VS Code API bridge, not by
  `ExtensionInputBoxViewController.swift`.
- **Retention**: The value lives only in `model.value` and the field's own
  `stringValue` for as long as the panel is on screen. No explicit
  zeroing or secure-erasure call is made on the string anywhere in this
  file; the value is simply released along with the controller and its
  model when the panel closes.

## Logging

Not applicable: `ExtensionInputBoxViewController.swift` contains no
logging call (no `print`, `os_log`, or logger reference anywhere in
source).

## Platform Notes

- **SwiftUI**: Compose a `Form`/`VStack` with an optional
  `Text(title).font(.headline)`, an optional
  `Text(prompt).font(.caption).foregroundStyle(.secondary)`, a
  `SecureField`/`TextField` bound to `@State` and driving validation from
  `.onChange(of:)`, and an optional `Text(validationMessage)` styled per
  severity (`.foregroundStyle(.red)`/`.orange`/`.secondary`), shown only
  when a message is present — mirroring `shows-validation-message`/
  `hides-validation-message-when-valid`. Gate `.onSubmit`'s action on the
  SwiftUI-side equivalent of `model.canAccept`, mirroring
  `accepts-only-when-model-permits`/`defers-acceptance-while-validating`,
  and cancel via a `.keyboardShortcut(.cancelAction)` button, mirroring
  `cancels-on-escape`.
- **Compose**: Use a `Column` with an optional title `Text` (`titleMedium`),
  an optional prompt `Text` (`bodySmall`, `onSurfaceVariant`), an
  `OutlinedTextField` (with `visualTransformation = PasswordVisualTransformation()`
  when secure) driving validation from `onValueChange`, and a `Text`
  colored by `MaterialTheme.colorScheme.error`/tertiary/`onSurfaceVariant`
  for the validation message, shown only when non-null. Gate the IME
  "Done" action and a confirm button the same way `model.canAccept` gates
  Return here, and map system back-press to cancellation, mirroring
  `cancels-on-escape`.
- **React/Web**: A `<form>` with an optional `<h2>`/`<p>` for title/prompt,
  an `<input type={isPassword ? "password" : "text"}>` wired to `onChange`
  for per-keystroke validation, and a `role="alert"` `<span>` for the
  validation message (colored by severity), rendered only when a message
  exists — mirroring the show/hide and severity-color requirements. Gate
  the form's `onSubmit` on the same "not currently validating and no
  active error" condition `model.canAccept` expresses, and bind an Escape
  `keydown` handler (or a Cancel button) to cancellation, mirroring
  `cancels-on-escape`.
- **AppKit/UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/Features/Extensions/UI/ExtensionInputBoxViewController.swift`
  — macOS-only (`import AppKit`), `@MainActor` `NSViewController`, laid
  out entirely with programmatic Auto Layout (no XIB/Storyboard), sharing
  `PickerKeyboardController` with `ExtensionQuickPickViewController`.
  There is no UIKit code path in source; a UIKit port would replace
  `NSSecureTextField`/`NSTextField` with `UITextField`
  (`isSecureTextEntry`), `NSTextFieldDelegate` with
  `UITextFieldDelegate`'s `textField(_:shouldChangeCharactersIn:
  replacementString:)`/`textFieldDidEndEditing`, and the window-level
  Escape `NSEvent` monitor with a Cancel bar item or interactive dismissal
  (iOS has no Escape-key equivalent).
- **WinUI 3** (the reason this recipe exists): Build the panel as a
  `StackPanel` inside the picker's shared content host: an optional
  `TextBlock` (`Style="{StaticResource BodyStrongTextBlockStyle}"`) for
  the title, an optional `TextBlock`
  (`Style="{StaticResource CaptionTextBlockStyle}"`, `Opacity="0.7"`) for
  the prompt, a `PasswordBox` when the request is a password field or a
  `TextBox` otherwise (`Text="{x:Bind Value, Mode=TwoWay}"`), and a
  `TextBlock` for the validation message whose `Visibility` is bound to
  "message present" and whose `Foreground` switches between the theme's
  error/caution/tertiary brushes for `.error`/`.warning`/`.information` —
  mirroring `shows-validation-message`/`hides-validation-message-when-valid`.
  Wire the `TextBox`/`PasswordBox`'s `TextChanged`/`PasswordChanged` event
  to the same commit-and-revalidate round trip
  `commits-value-and-revalidates-on-edit` describes; gate the dialog's
  default `Button` (`IsDefault="True"`) — or a `KeyDown` handler for
  `VirtualKey.Enter` — on the WinUI equivalent of `model.canAccept`,
  mirroring `accepts-only-when-model-permits` and
  `defers-acceptance-while-validating`; and give the Cancel button
  `IsCancel="True"` (or handle `VirtualKey.Escape` in `KeyDown`) so it
  fires unconditional cancellation, mirroring `cancels-on-escape`. Map
  focus and initial selection to `TextBox`/`PasswordBox.Focus
  (FocusState.Programmatic)` followed by `Select(start, length)`,
  preserving `focuses-field-then-applies-initial-selection`'s
  focus-then-select order.

## Design Decisions

- Decision: Choose the field's concrete class (`NSSecureTextField` vs.
  `NSTextField`) once, in `init(model:)`, from
  `model.request.isPassword`, rather than allowing it to change later.
  Rationale: Source's own comment: a field that changes class after
  gaining focus loses its caret and typed text, and `isPassword` cannot
  change during one `showInputBox` request, so there is exactly one
  moment this decision needs to be made.
  Approved: pending
- Decision: Hold a Return pressed while `model.isValidating` is `true`
  and replay it once validation lands, rather than accepting it
  immediately or dropping the keystroke.
  Rationale: Source's own comment on `choose()`: a Return pressed
  mid-validation is "not yet," not "no" — replaying it once the answer
  arrives lets a slow validator delay acceptance instead of silently
  swallowing the user's keystroke.
  Approved: pending
- Decision: Validate the pre-filled `model.value` once, on the first
  `viewDidAppear` of a presentation, via the `hasValidatedPrefill` guard,
  rather than in `viewDidLoad`.
  Rationale: Source's own comment: `viewDidAppear` can run more than once
  for one panel, so the guard keeps a re-appearance from re-triggering a
  validation round trip for a value that never changed; `viewDidLoad` was
  rejected because the presenter assigns `onValueChanged` only after
  `viewDidLoad` can already have run, leaving nothing to call yet.
  Approved: pending
- Decision: Route the field's `doCommandBy:` selectors through the shared
  `PickerKeyboardController`, which also recognizes `moveUp`/`moveDown`
  (arrow keys), even though this controller never sets
  `onMoveSelection`.
  Rationale: `PickerKeyboardController` is shared byte-for-byte with the
  picker views that do use `onMoveSelection` to move a row selection;
  reusing it here consumes the up/down arrow key events (marked handled,
  so they do not propagate further) but produces no visible effect in
  this single-field panel, since `onMoveSelection` is left at its default
  no-op closure.
  Approved: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | platform-compliance |
| [platform-design-language](agenticdevelopercookbook://compliance/platform-compliance#platform-design-language) | passed | platform-compliance |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | accessibility |
| [semantic-markup](agenticdevelopercookbook://compliance/accessibility#semantic-markup) | partial | accessibility |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | reliability |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial ingredient recipe for ExtensionInputBoxViewController, covering layout, per-edit revalidation, the Return accept/defer/drop three-way logic, and four open accessibility/UX review points (loading indicator, field accessibility label, validation-change announcement, Differentiate Without Color) for review. |
