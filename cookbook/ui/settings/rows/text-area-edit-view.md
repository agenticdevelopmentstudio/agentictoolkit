---
id: 8d944856-8dbe-4af8-8141-e44381500dc7
title: Text Area Edit View
domain: agentictoolkit://cookbook/ui/settings/rows/text-area-edit-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A settings row that edits a multi-line text setting in a scrolling text
  editor, committing when editing ends rather than on every keystroke.
platforms:
- swift
- macos
tags:
- settings
- text-input
- form-control
- scroll-view
depends-on: []
related:
- agentictoolkit://cookbook/ui/settings/rows/text-edit-view
- agentictoolkit://cookbook/ui/settings/rows/secure-text-edit-view
references:
- https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum.html
approved-by: ''
approved-date: ''
---

# Text Area Edit View

## Overview

The Text Area Edit View is a settings row: a multi-line editor for a setting
whose value is "a body of text rather than a field's worth" — an LLM prompt, a
template, or a script snippet. It pairs a title label with a scrolling text
editor in a vertical stack, and unlike the single-line Text Edit View (which
commits on Return), it writes the value back only when editing *ends* — the
editor loses focus, its window closes, the host application terminates, or the
component is detached from its window — because Return inserts a newline
rather than submitting. The component is driven by a view model exactly as the
Text Edit View and the Secure Text Edit View are, reusing only the Text Edit
View's label-construction helper rather than composing the label
independently (see Design Decisions).

## Behavioral Requirements

- **initializer-parameters**: Component MUST accept a view model as a
  required construction parameter, plus a visible-line count defaulting to
  `6` and a monospaced flag defaulting to `false` when the caller omits them.
- **row-label-text**: Component MUST display the view model's title as the
  row's label text, built via the shared row-label helper.
- **editor-font-role**: Component MUST render the editor's text in the
  active theme's code-role font when monospaced is `true`, or its body-role
  font when monospaced is `false`, both immediately at construction and
  again on every subsequent theme change.
- **initial-editor-text**: Component MUST display the view model's current
  value as the editor's text content at construction.
- **editor-theme-colors**: Component MUST render the editor's text,
  background, insertion-point (caret), and selection-highlight colors from
  the active theme's primary-text, control-background, cursor, and
  selection/selection-text roles respectively, immediately at construction
  and again on every theme change.
- **plain-text-mode**: Component MUST treat typed content as plain text: no
  rich-text formatting (bold, color, embedded attachments) is applied or
  preserved.
- **undo-support**: Component MUST support standard undo/redo of typed
  edits.
- **automatic-substitution-suppression**: Component MUST NOT apply automatic
  quote, dash, or text-replacement substitutions to typed text, so prose
  intended to be sent elsewhere verbatim is not silently rewritten before it
  leaves the editor.
- **vertical-growth**: Component MUST let the editor's content grow
  vertically without limit as text is typed, and MUST NOT grow horizontally
  with content — its width instead automatically follows its enclosing
  scrolling container.
- **text-wrapping**: Component MUST wrap text to the available width rather
  than scrolling horizontally.
- **text-container-inset**: Component MUST inset the typed text 4pt from the
  editor's edges on every side.
- **scrolling-container**: Component MUST host the editor inside a container
  that scrolls vertically, with a visible vertical scroll indicator and a
  bezeled border, so text beyond the visible height scrolls instead of
  growing the row without bound.
- **scroll-view-theme-background**: Component MUST draw the scrolling
  container's background using the active theme's control-background color,
  immediately at construction and again on every theme change.
- **label-scroll-view-layout**: Component MUST arrange the label above the
  scrolling container in a vertical, leading-aligned layout with the row's
  standard spacing (8pt) between them, and MUST pin that layout to all four
  edges of the component with no additional inset.
- **visible-height**: Component MUST fix the scrolling container's width to
  match the surrounding layout's width, and its visible height to a value
  computed from the active font's line height times the visible-line count,
  so exactly that many lines are visible before scrolling begins.
- **superview-width-claim**: Component MUST, once placed within a host view,
  claim that host's full width as a low-priority preference, so the editor
  is never narrower than its host without conflicting with a host that
  constrains it more strongly.
- **label-resync**: Component MUST, whenever the view model's change
  notification fires, set the label's text to the view model's title.
- **self-inflicted-onchange-guard**: Component MUST NOT overwrite the
  editor's text when the view model's change notification fires while an
  internal commit is in progress, and MUST NOT overwrite it when the
  editor's text already equals the incoming value.
- **external-value-adoption**: Component MUST, on a change notification that
  is not self-inflicted (per self-inflicted-onchange-guard), set the
  editor's text to the new value.
- **caret-position-on-external-change**: Component MUST, when adopting an
  external value change (per external-value-adoption) while the editor has
  focus, move the caret to the end of the new text.
- **accessibility-label**: Component MUST label the editor with the view
  model's title at construction, so a screen reader announces the editor by
  the row's title instead of as an unnamed text area.
- **end-editing-commit**: Component MUST commit (write the editor's text
  toward the view model's committed value, per redundant-commit-guard) when
  editing ends.
- **window-detachment-commit**: Component MUST commit when the component is
  about to be detached from its window.
- **teardown-notification-observers**: Component MUST, whenever the
  component is attached to a window, register to be notified when that
  window closes or the host application terminates, committing in either
  case.
- **stale-observer-deregistration**: Component MUST remove any previously
  registered window-close and application-termination notifications on
  itself every time the component is about to move to a window — including
  detachment — before registering new ones.
- **redundant-commit-guard**: Component MUST NOT write to the view model's
  committed value when the editor's text already equals it.
- **commit-echo-guard**: Component MUST mark a commit as in progress for the
  duration of writing the view model's committed value, and clear that
  marker immediately after, so the resulting change notification is
  recognized as self-inflicted (per self-inflicted-onchange-guard).
- **constituent-view-exposure**: Component MUST expose its label and its
  editor as accessible sub-components, so a caller may inspect or extend
  them directly.

## Appearance

- **Corner radius**: Not applicable — no custom layer or drawn shape is
  added to the editor or its scrolling container; the scrolling container
  keeps whatever corner rendering its default bordered style draws.
- **Padding**: The vertical layout uses 8pt of spacing between the label and
  the scrolling container, pinned directly to the component's own edges with
  no additional constant — 0pt of outer padding beyond that 8pt internal
  gap. Inside the editor, the typed text is inset 4pt on the top and 4pt on
  the bottom, and symmetrically 4pt on each side, within the scrolling
  container's content area.
- **Font**: The label resolves to the button role's default style: 13pt,
  medium weight, proportional. The editor's typed text uses the body role's
  style (13pt, regular weight, proportional) when monospaced is `false`, or
  the code role's style (12pt, regular weight, monospaced) when monospaced
  is `true`. Both scale with the active theme's size scale and repaint on a
  theme change.
- **Background**: The editor's and the scrolling container's backgrounds
  both resolve to the theme's control-background color — the theme's
  background blended 9% toward its foreground — recomputed on every theme
  change; the scrolling container's background is always drawn.
- **Foreground/Text**: The editor's text resolves to the theme's
  primary-text color (the theme's foreground, unchanged), matching the
  label's own role. The caret uses the theme's cursor color; selected text
  uses the theme's selection color as its background and that color's own
  contrast-chosen counterpart as its foreground.
- **Border**: Not customized beyond the scrolling container's bezeled border
  style; the editor itself draws no border of its own.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere.
- **Min/Max size**: The editor's content can grow without limit inside the
  scrolling container; the component's own visible height is fixed by
  visible-height rather than by any min/max constraint on the component
  itself.

## States

| State | Appearance change |
|-------|------------------|
| Default | Label shows the view model's title; the editor's text equals the view model's value, rendered in the theme's body/code font and colors described in Appearance. |
| Focused | Not styled by the component — no focus-ring customization is applied; the platform's own default focus indicator applies when the editor gains focus. |
| Committed | After a commit runs (per end-editing-commit, window-detachment-commit, or teardown-notification-observers) and the editor's text differs from the committed value, the new value is written through (see commit-echo-guard). |
| External value adopted | When the view model's change notification fires with a value the component did not itself just write, the editor's text is replaced with the new value (see external-value-adoption), and the caret jumps to its end if the editor currently has focus (see caret-position-on-external-change). |
| Disabled | Not implemented: the editor's editable/selectable state is never set (both default to enabled, so the field is always editable). A caller may disable it directly through the component's exposed editor (see constituent-view-exposure), though doing so produces no automatic visual dimming the way disabling a standard control would. |
| Pressed | Not applicable: a text editor has no discrete pressed state distinct from gaining focus and placing the caret; no such state is drawn. |
| Loading | Not applicable: the component performs no asynchronous operation and shows no loading indicator. |

## Accessibility

- **Role/trait**: Not customized — no explicit accessibility role is set;
  the editor carries the platform's own built-in text-area accessibility
  role.
- **Label requirements**: The editor is labeled with the view model's title
  once, at construction (accessibility-label), so a screen reader announces
  the editor by the row's title. This does not go stale: the view model's
  title cannot change after construction — the same invariant that makes
  label-resync's repeated assignment always a no-op (see Design Decisions).
- **Announce state changes**: Not applicable — the component has no loading
  state and never disables itself (see States); typed and deleted characters
  are announced through the editor's own native accessibility value
  reporting, unmodified by the component.
- **Minimum tap target**: Not applicable — this is a pointer/trackpad-driven
  composition with no touch input path; the 44×44pt minimum is touch-
  interface guidance. The component's clickable area is the full scrolling
  container, sized by visible-height.
- **Keyboard navigation**: Not customized beyond the platform's defaults —
  no exclusion from the window's tab order appears, so the editor
  participates in the window's normal tab order like any other control.
  Within the editor, the platform's own default behavior inserts a tab
  character on Tab rather than moving focus to the next control — correct
  for a multi-line text/code editor, where a literal tab is valid content.
  The component does not itself document or test how a keyboard user leaves
  the editor once inside it; the platform's own default key-view-loop
  binding is what would apply, but nothing in the component asserts or
  overrides this, so it is recorded here as resting on a platform default
  rather than on this component (see Compliance: `keyboard-navigable` is
  `partial`, not `passed`, for this reason).
- **Contrast**: Not set independently by this component — the editor's
  typed text resolves to the theme's primary-text role (unchanged
  foreground; no minimum contrast computed for this role), matching the
  label. Whether an active theme's resolved primary-text-on-control-
  background pairing clears WCAG 2.1 SC 1.4.3's 4.5:1 threshold for normal
  text is a property of the chosen theme, not of this component.
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented by the
  component. The label and editor text color resolve from the active
  theme's primary-text role against the hosting background at runtime; the
  component performs no contrast check, so whether a given theme's resolved
  pair meets 4.5:1 cannot be determined from the component alone. This would
  be settled by a theme-level contrast audit of primary-text against the
  backgrounds it sits on.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| text-area-edit-view-001 | initializer-parameters | Construct with only the view model supplied | The visible-line count defaults to 6 and monospaced defaults to false |
| text-area-edit-view-002 | row-label-text | View model's title is "Prompt" | The label's text is "Prompt" after construction |
| text-area-edit-view-003 | editor-font-role | Construct with monospaced set to true, then trigger a theme change | The editor's font equals the theme's code-role font both immediately after construction and after the theme change |
| text-area-edit-view-004 | initial-editor-text | View model's value is "hello" | The editor's text is "hello" after construction |
| text-area-edit-view-005 | editor-theme-colors | Construct the component, then trigger a theme change | The editor's text, background, caret, and selection colors all equal the theme's corresponding roles, both immediately after construction and after the change |
| text-area-edit-view-007 | plain-text-mode | Construct the component | The editor accepts only plain text; no rich-text formatting is applied or preserved |
| text-area-edit-view-008 | undo-support | Construct the component | Standard undo and redo are available for typed edits |
| text-area-edit-view-009 | automatic-substitution-suppression | Construct the component | Quote, dash, and text-replacement substitutions are all disabled |
| text-area-edit-view-010 | vertical-growth | Construct the component | The editor grows vertically without limit as text is typed and does not grow horizontally; its width follows its scrolling container |
| text-area-edit-view-011 | text-wrapping | Construct the component | Text wraps to the available width rather than scrolling horizontally |
| text-area-edit-view-012 | text-container-inset | Construct the component | The typed text is inset 4pt from the editor's edges on every side |
| text-area-edit-view-013 | scrolling-container | Construct the component | The editor is hosted in a container that scrolls vertically, with a visible scroll indicator and a bezeled border |
| text-area-edit-view-014 | scroll-view-theme-background | Construct the view, then trigger a theme change | The scrolling container's background is always drawn and equals the theme's control-background color both times |
| text-area-edit-view-015 | label-scroll-view-layout | Construct the component | The label precedes the scrolling container in a single vertical, leading-aligned layout with 8pt spacing, pinned to the component's edges |
| text-area-edit-view-016 | visible-height | Construct with a visible-line count of 6 and a known font | The scrolling container's height equals (line height × 6), rounded, plus 8; its width equals the surrounding layout's width |
| text-area-edit-view-017 | superview-width-claim | Add the component to a host view | A low-priority width preference equal to the host's width becomes active |
| text-area-edit-view-018 | label-resync | Trigger the view model's change notification with a new value | The label's text equals the view model's title after the call |
| text-area-edit-view-019 | self-inflicted-onchange-guard | Call commit while the editor's text differs from the committed value | During the resulting change notification, the editor's text is not overwritten and the caret is not moved |
| text-area-edit-view-020 | external-value-adoption | With no commit in progress, externally change the view model's value and trigger its change notification with a value that differs from the editor's current text | The editor's text equals the new value after the call |
| text-area-edit-view-021 | caret-position-on-external-change | Give the editor focus, then trigger an external change notification with a new value | The caret moves to the end of the new text |
| text-area-edit-view-022 | accessibility-label | Construct with the view model's title set to "Script" | The editor's accessibility label is "Script" |
| text-area-edit-view-023 | end-editing-commit | Set the editor's text to "new" where the committed value is "old", then end editing | The committed value becomes "new" |
| text-area-edit-view-024 | window-detachment-commit | With the editor's text differing from the committed value, detach the component from its window | The committed value equals the editor's text after the move |
| text-area-edit-view-025 | teardown-notification-observers | Attach the component to a window, diverge the editor's text from the committed value, then close that window | The committed value equals the editor's text after the window closes |
| text-area-edit-view-026 | stale-observer-deregistration | Move the component from window A to window B, then close window A | Closing window A no longer triggers a commit for the component |
| text-area-edit-view-027 | redundant-commit-guard | With a write-counting observer on the committed value, set the committed value and the editor's text to the same value, then call commit | Zero additional writes are recorded; the committed value is unchanged |
| text-area-edit-view-028 | commit-echo-guard | With a write-counting observer on the committed value, set the editor's text to a value different from the committed value, then call commit | Exactly one write is recorded, carrying the new value |
| text-area-edit-view-032 | constituent-view-exposure | Construct the component, then access its label and its editor externally | Both are accessible and return the instances built during construction |

## Edge Cases

- **Null/empty input**: The view model is a required, non-optional
  construction parameter, so there is no null case to handle; the component
  performs no null-handling of its own. An empty title or value produces an
  empty label or empty editor with no crash.
- **Boundary values**: Not applicable to the value's length — it has no
  minimum or maximum enforced anywhere in the component; any length is
  accepted, wraps, and scrolls. The visible-line count has no lower-bound
  guard either: a caller passing `0` or a negative value produces a
  degenerate but non-crashing height (per visible-height's formula), not a
  value the component rejects.
- **Non-BMP / multi-scalar characters in the caret calculation**: SHOULD be
  revisited. The caret-position calculation on an external change counts
  characters by grapheme cluster and applies that count directly as a
  text-position offset, which the editor's underlying text storage measures
  in a smaller unit than a grapheme cluster. For a value containing
  characters whose grapheme clusters span more than one such unit (emoji,
  many combining-mark or CJK-extension sequences), the caret lands short of
  the true end of the text rather than at it. Because the grapheme count
  never exceeds that finer-grained length, the position stays within bounds
  — this is a documented precision quirk (technical debt), not a crash risk
  (see Design Decisions).
- **Concurrent access**: Not applicable — the component is confined to
  construction and mutation from a single, serialized execution context (see
  Platform Notes).
- **Error states**: Not applicable — every operation (the editor's commit
  path and the committed-value write) is a synchronous, non-throwing call;
  no error-producing path exists.
- **Offline/disconnected**: Not applicable — the component performs no
  networking of its own; it only reads from and writes to an in-process view
  model.
- **Overwritten external observer**: The view model's change notification is
  a single callback, and construction unconditionally assigns the
  component's own handler to it, replacing whatever handler, if any, was
  previously registered on that view model instance. Constructing a second
  observer against the same view model instance silently drops the earlier
  handler — a known limitation of a single-callback property, not a
  validated or guarded interaction (see Design Decisions).
- **Component torn down mid-edit**: Handled explicitly, not left undefined —
  detachment from a window commits immediately, and window-close/
  application-termination notifications commit before the window actually
  closes or the application actually quits (see window-detachment-commit and
  teardown-notification-observers), specifically because the end-of-editing
  signal never fires for a component that is torn down with the caret still
  inside it.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | View model | — (required) | Supplies the row's title and current string value; receives committed edits. The initializer overwrites this view model's change-notification callback with the component's own sync handler (see Edge Cases). An explanation field the view model may carry is accepted but never read or displayed by this component. |
| `visibleLines` | Integer | `6` | Height of the editor, in lines of the editing font; content beyond it scrolls rather than growing the row (see visible-height). |
| `monospaced` | Boolean | `false` | Selects the theme's code-role font (fixed-width) when `true`, or body-role (proportional) when `false` — right for prompts/code, wrong for prose. |

## Deep Linking

Not applicable: the component is a row inside a settings panel, not a
navigable screen; no URL scheme, route, or deep-link handler applies.

## Localization

Not applicable: the component defines no user-facing string literal of its
own. The row's title comes entirely from the view model's title, and its
text content from the view model's value — both values the caller provides
— so there is nothing for this component to localize itself.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: the component performs no animation or transition; every state change (label/text sync, theme restyle, commit) is an instantaneous property assignment. |
| Increase Contrast | Not applicable to this component directly: it sets no literal color; text/background color come from the theme's primary-text/control-background/selection/cursor roles, whose actual resolved contrast is the theme layer's responsibility, not this component's. |
| Differentiate Without Color | Not applicable: the component conveys no state through color alone — selection is communicated by the standard highlighted-background text-selection affordance common to all text editors, not by a color-only signal distinguishing otherwise-identical content. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate applies; the row
always renders once constructed.

## Analytics

Not applicable: the component performs no analytics or telemetry.

## Privacy

- **Data collected**: The text typed into the editor — typically an LLM
  prompt, a template, or a script snippet. The component does not classify
  or redact this value; it holds it in the editor and the view model's
  committed value, and passes it through unchanged.
- **Storage**: Not applicable within this component — the value is held
  only in the editor and the view model's committed value for the
  component's lifetime. Persistence, when it happens, is owned by the
  caller-supplied view model's backing setting; unlike the secure variant's
  documented behavior, this component says nothing about routing to secure
  storage, so the default storage provider applies unless the caller's
  setting specifies otherwise — none of which is this component's own
  concern.
- **Transmission**: Not applicable within this component — no networking
  occurs here. That automatic text substitutions are disabled "because text
  gets sent to a model verbatim" describes a downstream consumer's behavior,
  not anything this component itself transmits.
- **Retention**: The value lives only in the editor and the view model's
  committed value for as long as the row is on screen and its view model is
  retained. No explicit clearing or secure-erasure is performed on the
  string; it is released with the component and its view model like any
  other property.

## Logging

Not applicable: the component performs no logging.

## Platform Notes

- **SwiftUI**: Pair a `Text(viewModel.title)` above a `TextEditor(text:
  $value)`, sized with `.frame(minHeight: lineHeight * CGFloat(visibleLines))`
  and wrapped in a bordered container to stand in for the scroll view's
  bezel chrome. Do not commit on every `TextEditor` keystroke; instead track
  focus with `@FocusState` and commit (write through an equality guard,
  mirroring redundant-commit-guard) when focus leaves the editor, and again
  from a `.onDisappear`/scene-teardown hook, mirroring
  window-detachment-commit and teardown-notification-observers. Disable
  autocorrection/smart substitutions with `.autocorrectionDisabled()` as the
  SwiftUI analog of automatic-substitution-suppression, and add an explicit
  `.accessibilityLabel(viewModel.title)`, carrying over accessibility-label
  rather than treating it as optional.
- **Compose**: Use a `Column` with `Text(title)` above an `OutlinedTextField`
  (or `BasicTextField` inside a `Box` with `verticalScroll`) configured
  `singleLine = false`, height-capped to `visibleLines` rows. Commit inside
  `Modifier.onFocusChanged { if (!it.isFocused) commit() }` — Compose's
  analog of end-editing-commit — with an equality check before writing,
  mirroring redundant-commit-guard, and again from `DisposableEffect`'s
  `onDispose`, mirroring window-detachment-commit. Give it
  `Modifier.semantics { contentDescription = title }`, mirroring
  accessibility-label, and drive font/color from
  `MaterialTheme.typography`/`colorScheme` tokens equivalent to
  `.body`/`.code`, `primaryText`, and `controlBackground`.
- **React/Web**: A `<label>` above a `<textarea rows={visibleLines}>` whose
  `id` the label's `htmlFor` references — carrying over accessibility-label
  rather than introducing a gap. Commit on the textarea's `onBlur` (not
  `onChange`, which fires per keystroke) and again from a component-unmount
  effect / `beforeunload` handler, mirroring end-editing-commit and
  teardown-notification-observers, each guarded by an equality check
  mirroring redundant-commit-guard. Set `spellCheck={false}` and avoid any
  smart-quote/dash text-processing library as the web analog of
  automatic-substitution-suppression, and style font/color from theme
  tokens equivalent to `.body`/`.code`, `primaryText`, and
  `controlBackground`.
- **AppKit/UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/TextAreaEditView.swift`
  — a macOS-only (`import AppKit`), `@MainActor`, non-`final` `NSView`
  subclass inside the `ComposableSettings` namespace, conforming to
  `SettingsViewProtocol` and `NSTextViewDelegate` directly (not by
  subclassing `TextEditView`, though it reuses that class's static
  `createLabel(title:)` helper). Being non-`final`, it may itself be
  subclassed. It is constructed only via `init(viewModel:visibleLines:
  monospaced:)`; the frame-only `init(frame:)` and the fatal-erroring
  `init?(coder:)` are the only other initializers, so construction is
  restricted to the one path that supplies a view model. The `@MainActor`
  declaration confines construction and mutation to the main actor under
  Swift's concurrency checking. `NSTextViewDelegate` conformance is how the
  editor's own end-of-editing callback reaches the component directly
  (`textView.delegate = self`, `textDidEndEditing` as the commit path)
  rather than through a separate delegate object. There is no UIKit code
  path in source. A UIKit port would replace `NSTextView`/`NSScrollView`
  with a `UITextView` (which is natively scrolling, so no separate scroll
  view is needed), implement `UITextViewDelegate.textViewDidEndEditing(_:)`
  as the commit path, and disable `autocorrectionType`/`smartQuotesType`/
  `smartDashesType`/`smartInsertDeleteType` as the substitution-disabling
  analog. Concretely, the AppKit source satisfies plain-text-mode via
  `textView.isRichText = false`; undo-support via `textView.allowsUndo =
  true`; automatic-substitution-suppression via
  `isAutomaticQuoteSubstitutionEnabled`,
  `isAutomaticDashSubstitutionEnabled`, and
  `isAutomaticTextReplacementEnabled`, all `false`; vertical-growth via
  `isVerticallyResizable = true`, `isHorizontallyResizable = false`,
  `autoresizingMask = [.width]`, `minSize = .zero`, `maxSize =
  NSSize(width: .greatestFiniteMagnitude, height:
  .greatestFiniteMagnitude)`; text-wrapping via
  `textView.textContainer.widthTracksTextView = true` and `containerSize =
  NSSize(width: 0, height: .greatestFiniteMagnitude)`; text-container-inset
  via `textView.textContainerInset = NSSize(width: 4, height: 4)`;
  scrolling-container via an `NSScrollView` with `documentView = textView`,
  `hasVerticalScroller = true`, `borderType = .bezelBorder`;
  scroll-view-theme-background via the scroll view's `drawsBackground =
  true` and its themed `backgroundColor`; label-scroll-view-layout via an
  `NSStackView`; visible-height via the scroll view's height constraint
  constant `(textView.font!.boundingRectForFont.height *
  CGFloat(visibleLines)).rounded() + 8` (the trailing `+ 8` matching
  `textContainerInset`'s 4pt top and 4pt bottom insets, per Design
  Decisions) and a width constraint equal to the stack's width; and
  superview-width-claim via a `widthAnchor` constraint at priority
  `.required - 1` (999). The caret-position quirk in Edge Cases stems from
  computing `viewModel.value.count` (a grapheme-cluster count) and passing
  it as an `NSRange` location, which `NSTextView` interprets in UTF-16 code
  units.
- **WinUI 3** (the reason this recipe exists): Build the row as a vertical
  `StackPanel` (8px `Spacing`, the WinUI analog of the row's standard
  spacing) containing a `TextBlock` for the title and a `TextBox` with
  `AcceptsReturn="True"` and `TextWrapping="Wrap"` — WinUI's own scrolling,
  multi-line text control, so no separate `ScrollViewer` is required the way
  `NSTextView` requires `NSScrollView` (set
  `ScrollViewer.VerticalScrollBarVisibility="Auto"` on the `TextBox` if an
  explicit scrollbar affordance is wanted). Give the `TextBox` a fixed
  `Height` computed the same way as visible-height (line height ×
  `visibleLines`), plus the `TextBox`'s own default vertical `Padding` and
  `BorderThickness` (from the `TextBoxPadding` and
  `TextControlBorderThemeThickness` theme resources) rather than reusing
  AppKit's `+ 8` constant, which is specific to `NSTextView`'s 4pt top/bottom
  `textContainerInset` — so overflow scrolls internally rather than growing
  the row. Commit on the `TextBox.LostFocus` event — WinUI's analog of
  `textDidEndEditing` — and also from the `Window.Closed` event and
  `AppWindow.Closing` (a WinUI 3 desktop app receives neither of UWP's
  `Application.Current.Suspending`), plus a process-exit handler for the
  case neither fires, mirroring window-detachment-commit and
  teardown-notification-observers, each guarded by an equality check
  mirroring redundant-commit-guard. Bind `TextBox.Foreground` and
  `Background` to theme resource brushes equivalent to
  `primaryText`/`controlBackground`, and `SelectionHighlightColor`/
  `SelectionHighlightColorWhenNotFocused` to a brush equivalent to
  `selection`, mirroring editor-theme-colors. Set `AutomationProperties.Name`
  on the `TextBox` to the title — the WinUI analog of
  `setAccessibilityLabel`, and one this AppKit source already implements,
  so carry it over rather than treating it as a gap to fix. `TextBox` has no
  direct equivalent of AppKit's quote/dash auto-substitution toggles; the
  nearest analog, `TextBox.IsSpellCheckEnabled = false`, only covers
  spell-check underlining, not autocorrection — note this as a platform gap
  rather than claiming full parity with automatic-substitution-suppression.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/TextAreaEditView.swift` |

## Design Decisions

- **Decision**: Document caret-position-on-external-change's use of the
  value's grapheme-cluster count as a text-position location measured in a
  finer-grained unit (AppKit: a UTF-16 offset via `NSRange`) as a known
  precision quirk rather than idealizing it into "moves the caret to the
  exact end."
  **Rationale**: for text containing graphemes that span more than one such
  unit (emoji, some combining sequences, many CJK-extension characters),
  grapheme count is strictly less than that finer-grained length, so the
  computed position lands short of the true end. It never exceeds the
  string's bounds (grapheme count is never greater than the finer-grained
  length), so this is reduced caret precision for such text, not a crash —
  technical debt affecting behavioral correctness, recorded per
  source-fidelity rather than smoothed over. (AppKit source.)
  **Approved**: pending
- **Decision**: Treat the closure-overwrite behavior of the view model's
  change notification as a known limitation rather than contract behavior
  other code should rely on.
  **Rationale**: the change notification is a single callback property;
  construction unconditionally assigns its own handler to it, which
  silently drops whatever handler, if any, was previously registered on the
  same view model instance. That is a source-traceable hazard of plain
  single-callback assignment, not a deliberate feature — recording it as a
  design decision keeps it from being read as required behavior for other
  implementations to replicate, while acknowledging the source does behave
  this way today.
  **Approved**: pending
- **Decision**: Keep the label-resync (setting the label's text to the view
  model's title) inside the change-notification handler even though the
  view model's title cannot change after construction for this view model.
  **Rationale**: the title is immutable after construction, so for this
  component today the assignment is always a no-op. It exists because the
  same handler is also responsible for the value-sync and caret logic
  (external-value-adoption, caret-position-on-external-change) that must run
  regardless, and keeping the label resync alongside them means every
  settings row's change handler is written the same shape, so a reviewer or
  future editor of any row type does not have to remember which ones need
  it — a present-day consistency benefit, not a hedge against a hypothetical
  future view model.
  **Approved**: pending
- **Decision**: Accept the scroll view's height formula's `+ 8` constant
  (AppKit) as an undocumented magic number in source, while noting the most
  plausible explanation rather than asserting it as fact.
  **Rationale**: the AppKit source never comments why `8` specifically is
  added to `(lineHeight * visibleLines).rounded()`; the value matches the
  sum of the text container inset's 4pt top and 4pt bottom insets set a few
  lines earlier in the same initializer, which would make the `+ 8`
  compensation for that inset so all `visibleLines` lines remain fully
  visible — but source does not state this correlation explicitly, so it is
  recorded here as the most likely reading, not as verified fact.
  **Approved**: pending
- **Decision**: Restrict superview-width-claim's constraint to priority
  `.required - 1` (999, AppKit) rather than `.required` (1000).
  **Rationale**: per the source's own comment, the enclosing stack already
  aligns leading, so the component must claim the full width itself to be
  usable for editing — but a host that insets its hosted controls (the
  comment's example: a popover pinning `width == stack.width - 32`) would
  otherwise create two conflicting required-width constraints, which
  AppKit resolves by breaking whichever one it prefers. One priority level
  below required avoids that conflict while still winning against any
  lower-priority sizing.
  **Approved**: pending
- **Decision**: Reuse the Text Edit View's label-construction helper for the
  label rather than composing the label independently or subclassing the
  Text Edit View (AppKit: `TextEditView.createLabel(title:)`).
  **Rationale**: this component needs the Text Edit View's label
  construction (the shared row-label helper, button text role) but none of
  its row layout, single-line field, or Return-commit path, which are wrong
  for a multi-line, commit-on-focus-loss editor; calling the one static
  helper it needs avoids inheriting behavior that does not apply.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | platform-compliance |
| [platform-design-language](agenticdevelopercookbook://compliance/platform-compliance#platform-design-language) | passed | platform-compliance |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | partial | accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | passed | accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | accessibility |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | reliability |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |

`native-controls-preference` and `platform-design-language` pass because the
row is built entirely from stock `NSTextView`, `NSScrollView`, and
`NSStackView` controls with no custom-drawn chrome; `screen-reader-support`
passes on `textView.setAccessibilityLabel(viewModel.title)`
(accessibility-label); `keyboard-navigable` is `partial` because `textView`
joins the window's ordinary Tab order but source never asserts or overrides
how a keyboard user exits the editor once inside it (see Accessibility);
`contrast-ratio` is `partial` because color values resolve to theme roles
whose actual contrast is the active `ColorTheme`'s responsibility, not
something `TextAreaEditView.swift` computes (see Accessibility: Contrast);
`idempotent-operations` passes on redundant-commit-guard making a repeated
`commit()` with unchanged content a no-op; and `separation-of-concerns`
passes because the view only wires up `NSTextView`/`NSScrollView` UI, while
`ComposableSettings.ViewModel<String>` and its `settingObserver`/
`UserSetting<String>` own the data and persistence.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: renamed requirements to subject-form and updated all cross-references; reworded AppKit property-assignment requirements as observable outcomes and moved the concrete API calls into the AppKit/UIKit Platform Notes bullet; fixed the WinUI 3 bullet's lifecycle event and height-inset guidance; documented the unasserted keyboard-exit path and marked keyboard-navigable partial, and added a contrast-ratio compliance row; rewrote test vectors 027/028 around an observable write-counting observer instead of the private isCommitting flag; reformatted Design Decisions to the bold three-line form, dropped the document-scoped requirement-count decision, gave the label-resync decision a present-day rationale, and recorded the onChange-overwrite hazard as a decision instead of a MUST; removed normative "MUST" phrasing from Edge Cases; dropped the untestable permits-subclassing requirement and folded it into Overview; trimmed tags to 5, added related/references, and added the initial Change History row; records the unverified theme-token contrast as an open question. |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/settings/rows/. |
