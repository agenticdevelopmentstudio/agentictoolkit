<!-- leaf: implement-extension/input-box-view-controller · source: extension-input-box-view-controller.md -->

**Rules** (cite as `implement-extension/input-box-view-controller#<slug>`):

- `optional-title-label` MUST
- `optional-prompt-label` MUST
- `secure-field-selection` MUST
- `field-placeholder-seed` MUST
- `initial-field-value` MUST
- `prefill-validation-once` MUST
- `value-commit-and-revalidation` MUST
- `pending-acceptance-reset` MUST
- `model-gated-acceptance` MUST
- `acceptance-deferral` MUST
- `return-drop-under-error` MUST
- `escape-cancellation` MUST
- `validation-message-shown` MUST
- `validation-message-hidden` MUST
- `focus-then-initial-selection` MUST
- `panel-size-from-fitted-layout` MUST

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

- **optional-title-label**: Component MUST create and display
  `titleLabel` as a `ThemedLabel` in the `.primaryText` role and `.heading`
  text role, populated with `model.request.title`, when
  `model.request.title` is non-nil and non-empty. Component MUST NOT
  create a title label otherwise.
- **optional-prompt-label**: Component MUST create and display
  `promptLabel` as a `ThemedLabel` in the `.secondaryText` role and
  `.caption` text role, populated with `model.request.prompt`, when
  `model.request.prompt` is non-nil and non-empty. Component MUST NOT
  create a prompt label otherwise.
- **secure-field-selection**: Component MUST construct its
  field as `NSSecureTextField` when `model.request.isPassword` is `true`,
  and as `NSTextField` otherwise, and MUST make that choice exactly once,
  during `init(model:)`, never re-evaluating or rebuilding the field
  afterward.
- **field-placeholder-seed**: Component MUST set the field's
  `placeholderString` to `model.request.placeHolder`, or to an empty
  string when `model.request.placeHolder` is `nil`.
- **initial-field-value**: Component MUST set the field's
  `stringValue` to `model.value` in `viewDidLoad`.
- **prefill-validation-once**: Component MUST, only
  the first time `viewDidAppear` runs for a given controller instance, call
  `model.beginValidating()` followed by `onValueChanged(model.value)`.
  Component MUST NOT repeat that call on any subsequent `viewDidAppear`
  invocation for the same controller instance.
- **value-commit-and-revalidation**: Component MUST, on every
  change to the field's text (`controlTextDidChange`), set `model.value`
  to the field's current `stringValue`, call `model.beginValidating()`,
  and invoke `onValueChanged` with that same new value, as one round trip
  per edit.
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
  pressed while the view's window is the event's window, via the
  window-level Escape monitor started in `viewDidAppear` and stopped in
  `viewWillDisappear`.
- **validation-message-shown**: Component MUST, when `showValidation(_:)`
  is called with a non-nil validation, set `validationLabel.isHidden` to
  `false`, set its `stringValue` to `validation.message`, and set its
  `role` to `.danger` for `.error` severity, `.warning` for `.warning`
  severity, or `.secondaryText` for `.information` severity.
- **validation-message-hidden**: Component MUST set
  `validationLabel.isHidden` to `true` when `showValidation(_:)` is called
  with `nil`.
- **focus-then-initial-selection**: Component MUST, when
  `focusField()` is called, first make the field the window's first
  responder, and only then set the field editor's `selectedRange` to
  `model.initialSelectionUTF16Range()`.
- **panel-size-from-fitted-layout**: Component MUST set
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

## Accessibility

- **Role/trait**: Not observable beyond AppKit's defaults — no
  `setAccessibilityRole` or similar call appears in source. The field
  calls `.accessibilityID("extension-input-box.field")` (an accessibility
  *identifier*, for UI testing, not a role or label). `NSTextField`/
  `NSSecureTextField` each carry AppKit's built-in text-field accessibility
  role automatically.
- **Label requirements**: No `accessibilityLabel`, `setAccessibilityLabel`,
  or `setAccessibilityTitleUIElement` call links the field to `titleLabel`
  or `promptLabel` anywhere in `ExtensionInputBoxViewController.swift`;
  VoiceOver announces only whatever AppKit derives on its own when focus
  lands in the field — the field has no `stringValue`-derived label of
  its own beyond its placeholder.
- **Announce state changes (e.g., loading, disabled)**: Not applicable for
  Disabled — the component never disables itself (see States). For the
  validation message: `showValidation(_:)` toggles
  `validationLabel.isHidden` and its text with no explicit accessibility
  notification call (e.g. an `NSAccessibility.post` equivalent) anywhere
  in source; any VoiceOver announcement of the change comes from AppKit's
  own default behavior on the label's text/visibility change, not from an
  explicit call in this file.
- **Minimum tap target**: Not applicable — this is a macOS,
  pointer/trackpad-driven `NSViewController`/`NSControl` composition (no
  touch input path in source); the 44×44pt minimum is iOS/touch guidance,
  not a macOS pointer-interface requirement.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `model` | `ExtensionInputBoxModel` | — (required, `init(model:)`) | Supplies `request.title`/`prompt`/`placeHolder`/`isPassword`/`valueSelection`, the current `value`, and validation state. Read once for the field's class at init; read again in `loadView`/`viewDidLoad` to seed content; read continuously via `model.value`/`canAccept`/`isValidating` for the lifetime of the panel. |
| `onAccept` | `(String) -> Void` | no-op (`{ _ in }`) | Called with `model.value` when Return is accepted (see `model-gated-acceptance`/`acceptance-deferral`). |
| `onCancel` | `() -> Void` | no-op (`{}`) | Called when Escape is pressed (see `escape-cancellation`). |
| `onValueChanged` | `(String) -> Void` | no-op (`{ _ in }`) | Called with the field's new value whenever it needs (re)validating — on every edit and once for the pre-filled value (see `value-commit-and-revalidation`/`prefill-validation-once`). |

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
- **Differentiate Without Color**: `validationLabel`'s three severities
  (`.error`/`.warning`/`.information`) are distinguished only by `role`
  (color) in `showValidation(_:)` — no icon, prefix, or other non-color
  cue is added anywhere in source.

