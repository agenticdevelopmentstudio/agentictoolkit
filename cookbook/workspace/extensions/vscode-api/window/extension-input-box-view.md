---
id: b85dc186-31e9-472b-99ea-2c097fc926c8
title: Extension Input Box
domain: agentictoolkit://cookbook/workspace/extensions/vscode-api/window/extension-input-box-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Presents one VS Code showInputBox request: an optional title and prompt,
  a text or secure field, and live validation.'
platforms:
- swift
- macos
tags:
- extensions
- form-control
- text-input
- validation
depends-on: []
related:
- agentictoolkit://cookbook/workspace/extensions/vscode-api/window/extension-quick-pick-view
references: []
approved-by: ''
approved-date: ''
---

# Extension Input Box

## Overview

This component presents one `vscode.window.showInputBox` request: an
optional title, an optional prompt, a single text (or secure) field, and a
validation message below it. It reads its content from an
`ExtensionInputBoxModel`/`ExtensionInputBoxRequest`, revalidates on every
edit (and once for a pre-filled value), and reports the user's decision
through the `onAccept`, `onCancel`, and `onValueChanged` callbacks its owner
assigns.

## Behavioral Requirements

- **optional-title-label**: Component MUST display a title, in the
  theme's `primaryText` role and `heading` text role, populated with
  `model.request.title`, when `model.request.title` is non-nil and
  non-empty. Component MUST NOT display a title otherwise.
- **optional-prompt-label**: Component MUST display a prompt, in the
  theme's `secondaryText` role and `caption` text role, populated with
  `model.request.prompt`, when `model.request.prompt` is non-nil and
  non-empty. Component MUST NOT display a prompt otherwise.
- **secure-field-selection**: Component MUST construct its field as a
  secure (masked) text field when `model.request.isPassword` is `true`,
  and as a plain text field otherwise, and MUST make that choice exactly
  once, during construction, never re-evaluating or rebuilding the field
  afterward.
- **field-placeholder-seed**: Component MUST set the field's placeholder
  text to `model.request.placeHolder`, or to an empty string when
  `model.request.placeHolder` is `nil`.
- **initial-field-value**: Component MUST seed the field's text with
  `model.value` when the view is first loaded.
- **prefill-validation-once**: Component MUST, only
  the first time the view appears for a given component instance, call
  `model.beginValidating()` followed by `onValueChanged(model.value)`.
  Component MUST NOT repeat that call on any subsequent appearance of the
  same component instance.
- **value-commit-and-revalidation**: Component MUST, on every
  change to the field's text, set `model.value` to the field's current
  text, call `model.beginValidating()`, and invoke `onValueChanged` with
  that same new value, as one round trip per edit.
- **pending-acceptance-reset**: Component MUST discard any Return held
  pending validation on every change to the field's text, before
  performing the commit-and-revalidate round trip.
- **model-gated-acceptance**: Component MUST invoke
  `onAccept(model.value)` when Return is pressed while `model.canAccept`
  is `true`. Component MUST NOT invoke `onAccept` when `model.canAccept`
  is `false`.
- **acceptance-deferral**: Component MUST, when Return is
  pressed while `model.isValidating` is `true`, record that Return as
  pending rather than accepting immediately or discarding the keystroke,
  and MUST replay it — invoking
  `onAccept(model.value)` — the next time `showValidation(_:)` runs and
  finds `model.canAccept` `true`.
- **return-drop-under-error**: Component MUST silently drop a
  Return pressed while `model.canAccept` is `false` and
  `model.isValidating` is also `false` (a standing `.error` validation),
  without recording it for later replay.
- **escape-cancellation**: Component MUST invoke `onCancel()` when Escape is
  pressed while this component's window is the active (focused) window,
  for as long as the component is on screen.
- **validation-message-shown**: Component MUST, when `showValidation(_:)`
  is called with a non-nil validation, show the validation message, set
  its text to `validation.message`, and set its color role to `danger`
  for `error` severity, `warning` for `warning` severity, or
  `secondaryText` for `information` severity.
- **validation-message-hidden**: Component MUST hide the validation
  message when `showValidation(_:)` is called with `nil`.
- **focus-then-initial-selection**: Component MUST, when
  `focusField()` is called, first give the field keyboard focus, and only
  then set the field's text selection to
  `model.initialSelectionUTF16Range()`.
- **panel-size-from-fitted-layout**: Component MUST set the panel's
  preferred size to a fixed width of 480pt and a height equal to the root
  view's fitted content height, floored at 72pt.

## Appearance

- **Corner radius**: Not applicable — no corner radius (or other
  layer-drawing property) is set on the root view.
- **Padding**: 12pt leading/trailing padding on every subview. Vertically,
  each present subview's top is pinned 12pt below the previous one — the
  first present view (title, or prompt, or the field) sits 12pt below the
  root's top; the field sits 12pt below whichever of title/prompt is last
  present. The validation message sits 8pt below the field and is pinned
  12pt above the root's bottom edge.
- **Font**: The title resolves the theme's `heading` text style — 15pt,
  semibold, proportional font. The prompt and validation message both
  resolve the theme's `caption` text style — 11pt, regular weight; the
  validation message's text style never changes with severity, only its
  color role does. Both scale with the active theme's `sizeScale` and
  repaint on a theme change. The field itself has no font set of its
  own — it renders in the platform's stock default font for a text field,
  not driven by the theme's typography at all.
- **Background**: The root view has no background color set on it. The
  title, prompt, and validation message are all transparent, with no
  border or bezel of their own. The field's fill is the platform's stock
  control chrome; no background-color override is set on it.
- **Foreground/Text**: The title uses the theme's `primaryText` role (the
  active theme's foreground color at full strength). The prompt uses
  `secondaryText`. The validation message's role switches with severity —
  `danger`/`warning`/`secondaryText` for `error`/`warning`/`information` —
  recomputed live on every `showValidation(_:)` call and on theme change.
  The field's text color is never set of its own; it renders in the
  platform's stock default text color, not theme-driven.
- **Border**: Not applicable for the title, prompt, and validation
  message — none has a border or bezel. The field's border is the
  platform's stock control bezel; no custom border is configured.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere
  in this component.
- **Min/Max size**: The panel's preferred size fixes width at 480pt
  exactly (no min/max range around it) and sets height to the root
  content's fitted height, floored at 72pt with no explicit ceiling.

## States

| State | Appearance change |
|-------|------------------|
| Default | Title/prompt shown per `model.request` (or omitted, per those requirements); field shows `model.value`; validation message starts hidden. |
| Pressed | Not applicable — no button or other pressable control appears in this component; the field is a text-entry control, not a press target. |
| Disabled | Not applicable — the field (and the title/prompt) is never disabled; it is always enabled once the panel is on screen. |
| Focused | The field can become focused (via normal keyboard/click focus, or via `focusField()`). No custom focus-ring styling is set of its own — the platform's default focus indicator for a text field applies. `focusField()` additionally applies `model.initialSelectionUTF16Range()` as the field's text selection, but only when explicitly invoked — not automatically on every focus event. |
| Loading | No loading indication — `model.isValidating` (set true by `beginValidating()`, cleared by `recordValidation(_:)`) changes only the acceptance logic (Return is held and replayed — see `acceptance-deferral`); no visual property (opacity, a spinner, a disabled state, or any other visual cue) is read from or set based on `model.isValidating` anywhere in this component. |

## Accessibility

- **Role/trait**: Not observable beyond the platform's defaults — no
  explicit accessibility role is set. The field carries a test identifier
  (`extension-input-box.field`), which is an identifier for UI testing,
  not a role or label. The field carries the platform's built-in
  text-field accessibility role automatically.
- **Label requirements**: Nothing explicitly links the field to the title
  or prompt as its accessibility label; a screen reader announces only
  whatever the platform derives on its own when focus lands in the field —
  the field has no text-derived label of its own beyond its placeholder.
- **Announce state changes (e.g., loading, disabled)**: Not applicable for
  Disabled — the component never disables itself (see States). For the
  validation message: `showValidation(_:)` toggles its visibility and
  text with no explicit accessibility change notification of its own; any
  screen-reader announcement of the change comes from the platform's own
  default behavior on visibility/text changes, not from an explicit call
  this component makes.
- **Minimum tap target**: Not applicable — this component targets
  pointer/trackpad input, not touch; the 44×44pt minimum is
  touch-interface guidance, not a pointer-interface requirement.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| extension-input-box-view-controller-001 | optional-title-label | `model.request.title = "Enter API Key"` | The title is displayed, in the `primaryText` role and `heading` text role, with text `"Enter API Key"` |
| extension-input-box-view-controller-002 | optional-title-label | `model.request.title = nil` (and, separately, `= ""`) | No title is displayed |
| extension-input-box-view-controller-003 | optional-prompt-label | `model.request.prompt = "Used only for this session."` | The prompt is displayed, in the `secondaryText` role and `caption` text role, with matching text |
| extension-input-box-view-controller-004 | optional-prompt-label | `model.request.prompt = nil` | No prompt is displayed |
| extension-input-box-view-controller-005 | secure-field-selection | Construct with `model.request.isPassword = true` | The field is constructed as a secure (masked) field |
| extension-input-box-view-controller-006 | secure-field-selection | Construct with `model.request.isPassword = false` | The field is constructed as a plain (unmasked) field |
| extension-input-box-view-controller-007 | field-placeholder-seed | `model.request.placeHolder = "org/repo"` | The field's placeholder text is `"org/repo"` once the view loads |
| extension-input-box-view-controller-008 | field-placeholder-seed | `model.request.placeHolder = nil` | The field's placeholder text is empty once the view loads |
| extension-input-box-view-controller-009 | initial-field-value | `model.value = "prefilled"` | Once the view loads, the field's text is `"prefilled"` |
| extension-input-box-view-controller-010 | prefill-validation-once | The view appears twice in succession on a fresh component instance | `model.beginValidating()`/`onValueChanged(model.value)` fire exactly once, on the first appearance only |
| extension-input-box-view-controller-011 | value-commit-and-revalidation | Set the field's text to `"abc"` | `model.value == "abc"`; `model.isValidating == true`; `onValueChanged` is invoked once with `"abc"` |
| extension-input-box-view-controller-012 | pending-acceptance-reset, acceptance-deferral | `model.isValidating == true`; press Return (deferring acceptance); then change the field's text (an edit); then supply a validation that makes `model.canAccept == true` | `onAccept` is not invoked — the edit discarded the held Return before validation landed |
| extension-input-box-view-controller-013 | model-gated-acceptance | `model.canAccept == true`; press Return | `onAccept` is invoked exactly once, with `model.value` |
| extension-input-box-view-controller-014 | model-gated-acceptance | `model.canAccept == false`; press Return | `onAccept` is not invoked |
| extension-input-box-view-controller-015 | acceptance-deferral | `model.isValidating == true`; press Return; then supply a `nil` validation result, which clears `model.isValidating` and makes `model.canAccept == true` | `onAccept(model.value)` is not invoked on the Return press itself; it fires exactly once, once that validation result lands |
| extension-input-box-view-controller-016 | return-drop-under-error | `model.isValidating == false`, `model.canAccept == false` (standing error); press Return | `onAccept` is not invoked, and a validation that subsequently lands with `model.canAccept == true` does not retroactively invoke it either — the Return was dropped, not deferred |
| extension-input-box-view-controller-017 | escape-cancellation | With the component on screen and its window active, press Escape in that window | `onCancel()` is invoked exactly once |
| extension-input-box-view-controller-018 | validation-message-shown | Supply a validation of message `"Required"`, severity error | The validation message is shown, with text `"Required"` and color role `danger` |
| extension-input-box-view-controller-019 | validation-message-shown | Supply a validation of message `"Heads up"`, severity warning (and, separately, information) | Color role is `warning` for warning severity (and `secondaryText` for information severity) |
| extension-input-box-view-controller-020 | validation-message-hidden | Supply a `nil` validation result | The validation message is hidden |
| extension-input-box-view-controller-021 | focus-then-initial-selection | Call `focusField()` with `model.initialSelectionUTF16Range()` resolving to a selection starting at position 2, length 3 | The field has keyboard focus, and its text selection starts at position 2, length 3 |
| extension-input-box-view-controller-022 | panel-size-from-fitted-layout | Load the view with content whose fitted content height is 40pt (below the 72pt floor) | The panel's preferred size is 480×72 |
| extension-input-box-view-controller-023 | panel-size-from-fitted-layout | Load the view with content whose fitted content height is 160pt | The panel's preferred size is 480×160 |
| extension-input-box-view-controller-024 | model-gated-acceptance | `model.value == ""`, `model.canAccept == true`; press Return | `onAccept("")` is invoked exactly once — an empty value is still accepted, not treated as nothing entered |
| extension-input-box-view-controller-025 | escape-cancellation | With the component on screen, press Escape in a window that is not the component's window | `onCancel()` is not invoked |

## Edge Cases

- Null/empty input — title/prompt: `model.request.title`/`prompt` being
  `nil` or `""` suppresses that label entirely (see
  `optional-title-label`/`optional-prompt-label`). MUST.
- Null/empty input — value: `model.value` may be `""` (an empty pre-filled
  or typed value). Per `ExtensionInputBoxModel.onAccept`'s own contract,
  "an empty string is a value, and Return accepts it" — Return with an
  empty field and `model.canAccept == true` MUST invoke `onAccept("")`,
  not be treated as "nothing entered." MUST.
- Boundary values — initial selection: `model.initialSelectionUTF16Range()`
  (called directly by `focusField()`) clamps an out-of-bounds
  `valueSelection` to the value's length, and falls back to a zero-length
  range at the very end of the value when it cannot resolve a requested
  offset within the value. `focusField()` MUST apply whatever range this
  returns without additional validation of its own. MUST.
- Concurrent access: Not applicable — access to the component's state is
  serialized onto a single, consistent execution context, so all field
  change notifications, keyboard dispatch, and validation replies happen
  one at a time; there is no code path by which two threads mutate the
  component's state simultaneously.
- Error states: The only failure mode that reaches this component is an
  error-severity validation, which it MUST always render via
  `validation-message-shown` and MUST always block acceptance for via
  `model-gated-acceptance`/`return-drop-under-error`. This component
  performs no throwing or networked call itself; the extension's
  `validateInput` call and any failure within it are owned by the
  presenter above this component, not by the component itself. MUST.
- Offline/disconnected: Not applicable — the component performs no
  networking of its own; validation answers arrive as already-resolved
  values passed into `showValidation(_:)`.
- Return held, then superseded by a further edit: a Return pressed while
  `model.isValidating` is `true` is held pending validation (see
  `acceptance-deferral`); if the user types again before the answer
  lands, `pending-acceptance-reset` discards that held Return, so it is
  never replayed against a value the field no longer holds. MUST.
- Repeated appearance for one component instance: the pre-filled value is
  validated once per component instance, not once per appearance of the
  view (see `prefill-validation-once`). MUST.
- `isPassword` cannot change mid-presentation: the field's kind is fixed
  at construction from `model.request.isPassword`; nothing rebuilds or
  reclasses the field afterward, so a hypothetical later change to that
  flag on the same model has no effect. MUST NOT re-evaluate.
- Arrow keys (up/down) inside the field are consumed with no visible
  effect: every keyboard command is routed through a shared
  keyboard-dispatch helper, which also recognizes move-up/move-down and
  reports them handled (a move-selection handler is invoked and the key
  is treated as consumed). This component never assigns that
  move-selection handler, so pressing the up or down arrow while the
  field has focus is swallowed (marked handled, so it does not fall
  through to the field's default behavior) but produces no observable
  change. MAY — this is a documented known quirk of reusing the shared
  helper, not a contract this component defines; whether it is wanted is
  the open question in Design Decisions, not a requirement every port
  must reproduce.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `model` | `ExtensionInputBoxModel` | — (required, set at construction) | Supplies `request.title`/`prompt`/`placeHolder`/`isPassword`/`valueSelection`, the current `value`, and validation state. Read once for the field's kind at construction; read again once the view loads to seed content; read continuously via `model.value`/`canAccept`/`isValidating` for the lifetime of the panel. |
| `onAccept` | callback taking the accepted value | no-op | Called with `model.value` when Return is accepted (see `model-gated-acceptance`/`acceptance-deferral`). |
| `onCancel` | callback taking no arguments | no-op | Called when Escape is pressed (see `escape-cancellation`). |
| `onValueChanged` | callback taking the current value | no-op | Called with the field's new value whenever it needs (re)validating — on every edit and once for the pre-filled value (see `value-commit-and-revalidation`/`prefill-validation-once`). |

## Deep Linking

Not applicable: this component is modal panel content instantiated by the
presenter above it in direct response to one `vscode.window.showInputBox`
call, not a navigable or URL-addressable screen; no URL scheme, route, or
deep-link handler is part of this component.

## Localization

Not applicable: every user-facing string this component surfaces — title,
prompt, placeholder, value, and validation message — is passed in at
runtime from `model.request`/`showValidation(_:)`'s parameter, i.e. text
the requesting extension itself already chose in whatever locale it
targets. This component defines no user-facing string literal of its own
to localize.

## Accessibility Options

- **Reduce Motion**: Not applicable — no animation or transition is part
  of this component; every state change (label text, visibility, color
  role) is an instantaneous property assignment.
- **Increase Contrast**: Not applicable — the component sets no custom
  color of its own; the title, prompt, and validation message colors all
  come from the theme's role-based palette lookup, which follows the
  active theme/system Increase Contrast automatically. The field's
  coloring is the platform's own default control appearance, likewise
  system-managed.
- **Differentiate Without Color**: The validation message's three
  severities (error/warning/information) are distinguished only by color
  role in `showValidation(_:)` — no icon, prefix, or other non-color cue
  is added.

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate is part of
this component; the panel always renders once constructed.

## Analytics

Not applicable: this component makes no analytics or telemetry call.

## Privacy

- **Data collected**: The field's typed value — potentially a secret
  (e.g. a token or password) when `model.request.isPassword` is `true`,
  in which case the secure field masks it on screen. The component does
  not otherwise classify or redact this value; it holds it in
  `model.value` and returns it verbatim via `onAccept`.
- **Storage**: Not applicable — the component and its model hold the
  value only in memory for the panel's lifetime; no write to disk,
  preference storage, or any other persistent store is part of this
  component.
- **Transmission**: Not applicable within this component — the accepted
  value is handed to the caller-supplied `onAccept` callback; this
  component performs no networking itself. Where that value goes
  afterward (back across the extension-host bridge to the requesting
  extension) is owned by the presenter/the VS Code API bridge above it,
  not by this component.
- **Retention**: The value lives only in `model.value` and the field's own
  text for as long as the panel is on screen. No explicit zeroing or
  secure-erasure of the string happens; the value is simply released
  along with the component and its model when the panel closes.

## Logging

Not applicable: this component makes no logging call.

## Platform Notes

- **SwiftUI**: Compose a `Form`/`VStack` with an optional
  `Text(title).font(.headline)`, an optional
  `Text(prompt).font(.caption).foregroundStyle(.secondary)`, a
  `SecureField`/`TextField` bound to `@State` and driving validation from
  `.onChange(of:)`, and an optional `Text(validationMessage)` styled per
  severity (`.foregroundStyle(.red)`/`.orange`/`.secondary`), shown only
  when a message is present — mirroring `validation-message-shown`/
  `validation-message-hidden`. `.onSubmit` alone only gates a Return
  against the current `canAccept` value; it cannot replay one pressed
  while validation is in flight. Mirror `model-gated-acceptance`/
  `acceptance-deferral` with a `@State pendingSubmit` flag: `.onSubmit`
  accepts immediately when the SwiftUI-side `canAccept` is already true,
  otherwise (while validating) sets `pendingSubmit = true` and does not
  accept; an `.onChange(of: canAccept)` (or the validation-result
  callback) checks `pendingSubmit` when `canAccept` turns true, accepts,
  and clears the flag — the same held-then-replayed Return the AppKit
  source implements, not a drop. Cancel via a
  `.keyboardShortcut(.cancelAction)` button, mirroring
  `escape-cancellation`.
- **Compose**: Use a `Column` with an optional title `Text` (`titleMedium`),
  an optional prompt `Text` (`bodySmall`, `onSurfaceVariant`), an
  `OutlinedTextField` (with `visualTransformation = PasswordVisualTransformation()`
  when secure) driving validation from `onValueChange`, and a `Text`
  colored by `MaterialTheme.colorScheme.error`/tertiary/`onSurfaceVariant`
  for the validation message, shown only when non-null. Gate the IME
  "Done" action and a confirm button the same way `model.canAccept` gates
  Return here, and map system back-press to cancellation, mirroring
  `escape-cancellation`.
- **React/Web**: A `<form>` with an optional `<h2>`/`<p>` for title/prompt,
  an `<input type={isPassword ? "password" : "text"}>` wired to `onChange`
  for per-keystroke validation, and a `role="alert"` `<span>` for the
  validation message (colored by severity), rendered only when a message
  exists — mirroring the show/hide and severity-color requirements. Gate
  the form's `onSubmit` on the same "not currently validating and no
  active error" condition `model.canAccept` expresses, and bind an Escape
  `keydown` handler (or a Cancel button) to cancellation, mirroring
  `escape-cancellation`.
- **AppKit/UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/Features/Extensions/UI/ExtensionInputBoxViewController.swift`
  — macOS-only (`import AppKit`), `@MainActor` `NSViewController`, laid
  out entirely with programmatic Auto Layout (no XIB/Storyboard), sharing
  `PickerKeyboardController` with `ExtensionQuickPickViewController`.
  The pending-Return and once-per-instance-prefill guards described by
  `acceptance-deferral`/`pending-acceptance-reset` and
  `prefill-validation-once` are backed by two private properties,
  `acceptWhenValidationLands` and `hasValidatedPrefill`.
  `focusField()` makes the field the window's first responder, then sets
  the field editor's `selectedRange` to `model.initialSelectionUTF16Range()`
  — the order matters because setting the range before the field has a
  field editor has no effect. `escape-cancellation` is backed by a
  window-level `NSEvent` monitor started in `viewDidAppear` and stopped in
  `viewWillDisappear`, so it exists only while the panel is actually on
  screen. There is no UIKit code path in source; a UIKit port would
  replace `NSSecureTextField`/`NSTextField` with `UITextField`
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
  mirroring `validation-message-shown`/`validation-message-hidden`.
  Wire the `TextBox`/`PasswordBox`'s `TextChanged`/`PasswordChanged` event
  to the same commit-and-revalidate round trip
  `value-commit-and-revalidation` describes; gate the panel's default
  action — a `ContentDialog.DefaultButton` set to `Primary` when the panel
  is hosted as a `ContentDialog`, or a `KeyboardAccelerator` for
  `VirtualKey.Enter` on the root otherwise — on the WinUI equivalent of
  `model.canAccept`, mirroring `model-gated-acceptance` and
  `acceptance-deferral`; and drive Cancel from
  `ContentDialog.CloseButton` (or a `KeyboardAccelerator` for
  `VirtualKey.Escape`) so it fires unconditional cancellation, mirroring
  `escape-cancellation` — WinUI 3 has no `IsDefault`/`IsCancel` button
  properties (those are WPF's). Map focus to
  `TextBox`/`PasswordBox.Focus(FocusState.Programmatic)`; initial
  selection via `Select(start, length)` applies only to `TextBox` —
  `PasswordBox` exposes no selection API, so a secure field can only be
  focused, not pre-selected, which is as far as
  `focus-then-initial-selection`'s focus-then-select order can carry over
  for a password field.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/Extensions/UI/ExtensionInputBoxViewController.swift` |

## Design Decisions

- **Decision**: Choose the field's concrete class (`NSSecureTextField` vs.
  `NSTextField`) once, in `init(model:)`, from
  `model.request.isPassword`, rather than allowing it to change later.
  **Rationale**: Source's own comment: a field that changes class after
  gaining focus loses its caret and typed text, and `isPassword` cannot
  change during one `showInputBox` request, so there is exactly one
  moment this decision needs to be made.
  **Approved**: pending
- **Decision**: Hold a Return pressed while `model.isValidating` is `true`
  and replay it once validation lands, rather than accepting it
  immediately or dropping the keystroke.
  **Rationale**: Source's own comment on `choose()`: a Return pressed
  mid-validation is "not yet," not "no" — replaying it once the answer
  arrives lets a slow validator delay acceptance instead of silently
  swallowing the user's keystroke.
  **Approved**: pending
- **Decision**: Validate the pre-filled `model.value` once, on the first
  `viewDidAppear` after the controller instance is created, via the guard
  described in `prefill-validation-once`, rather than in `viewDidLoad`.
  **Rationale**: Source's own comment: `viewDidAppear` can run more than
  once for one panel, so the guard keeps a re-appearance from
  re-triggering a validation round trip for a value that never changed;
  `viewDidLoad` was rejected because the presenter assigns
  `onValueChanged` only after `viewDidLoad` can already have run, leaving
  nothing to call yet.
  **Approved**: pending
- **Decision**: Route the field's `doCommandBy:` selectors through the
  shared `PickerKeyboardController`, which also recognizes
  `moveUp`/`moveDown` (arrow keys), even though this controller never
  sets `onMoveSelection`.
  **Rationale**: `PickerKeyboardController` is shared byte-for-byte with
  the picker views that do use `onMoveSelection` to move a row selection;
  reusing it here consumes the up/down arrow key events (marked handled,
  so they do not propagate further) but produces no visible effect in
  this single-field panel, since `onMoveSelection` is left at its default
  no-op closure.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | platform-compliance |
| [platform-design-language](agenticdevelopercookbook://compliance/platform-compliance#platform-design-language) | passed | platform-compliance |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | accessibility |
| [semantic-markup](agenticdevelopercookbook://compliance/accessibility#semantic-markup) | partial | accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | accessibility |
| [secure-storage](agenticdevelopercookbook://compliance/security#secure-storage) | partial | security |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | reliability |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |

`secure-storage` is partial because the field holds a potential secret
(`isPassword`) only in memory — masked on screen via
`NSSecureTextField`, never written to Keychain or any persistent store,
but also never explicitly zeroed on release. `contrast-ratio` is partial
because `validationLabel`'s three severities are distinguished by a
theme-role color change alone, with no non-color cue and no in-source
measurement of the resulting contrast ratio (see the Differentiate
Without Color entry under Accessibility Options).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial ingredient recipe for ExtensionInputBoxViewController, covering layout, per-edit revalidation, the Return accept/defer/drop three-way logic, and four open accessibility/UX review points (loading indicator, field accessibility label, validation-change announcement, Differentiate Without Color) for review. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: trimmed tags/summary to convention limits, added the sibling picker recipe to `related`, renamed every requirement to subject-only kebab-case, restated private-state requirements/vectors/edge cases as observable behavior, bolded the Design Decisions form, corrected the WinUI 3 bullet's WPF-only APIs and `PasswordBox` selection gap, described SwiftUI's pending-submit replay, added the secure-storage/contrast-ratio compliance rows, downgraded the arrow-key edge case from MUST to a documented known quirk, and added test vectors for empty-string acceptance and Escape from another window. |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/extensions/vscode-api/window/. |
