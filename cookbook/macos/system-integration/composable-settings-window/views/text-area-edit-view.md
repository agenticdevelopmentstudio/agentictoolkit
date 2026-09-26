---
id: 8d944856-8dbe-4af8-8141-e44381500dc7
title: TextAreaEditView
domain: agentictoolkit://cookbook/macos/system-integration/composable-settings-window/views/text-area-edit-view
type: ingredient
version: 1.1.2
status: review
language: en
created: '2026-09-23'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A macOS ComposableSettings row that edits a multi-line String setting in
  a scrolling NSTextView, committing on focus loss rather than per keystroke.
platforms:
- swift
- macos
tags:
- settings
- text-input
- form-control
- scroll-view
- appkit
depends-on: []
related:
- agentictoolkit://cookbook/macos/system-integration/composable-settings-window/views/text-edit-view
- agentictoolkit://cookbook/macos/system-integration/composable-settings-window/views/secure-text-edit-view
references:
- https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum.html
approved-by: ''
approved-date: ''
---

# TextAreaEditView

## Overview

`TextAreaEditView` is a macOS `ComposableSettings` row
(`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/TextAreaEditView.swift`):
a multi-line editor for settings whose value is "a body of text rather than a
field's worth" — per the source's own doc comment, an LLM prompt, a template,
or a script snippet. It pairs a title label with a scrolling `NSTextView` in a
vertical stack, and unlike the single-line `TextEditView` (which commits on
Return via target/action), it writes the value back only when editing *ends*
— the text view loses first responder, its window closes, the app
terminates, or the view is detached from its window — because Return inserts
a newline rather than submitting. `TextAreaEditView` conforms to
`SettingsViewProtocol` (an empty `NSView`-constrained marker protocol with no
requirements of its own) and `NSTextViewDelegate`, and is driven by a
`ComposableSettings.ViewModel<String>` exactly as `TextEditView` and
`SecureTextEditView` are, reusing only `TextEditView.createLabel(title:)` from
that family rather than subclassing it. The class is declared `public` and not
`final`, so — unlike `SecureTextEditView`, which forecloses subclassing — it
may be subclassed.

## Behavioral Requirements

- **initializer-parameters**: Component MUST accept `viewModel:
  ViewModel<String>` as a required initializer parameter, plus `visibleLines:
  Int` defaulting to `6` and `monospaced: Bool` defaulting to `false` when the
  caller omits them.
- **row-label-text**: Component MUST display `viewModel.title` as the row's
  label text, built via the shared row-label helper
  (`TextEditView.createLabel(title:)` / `ComposableSettings.makeRowLabel`).
- **editor-font-role**: Component MUST render the editor's text in the active
  theme's `.code`-role font when `monospaced` is `true`, or its `.body`-role
  font when `monospaced` is `false`, both immediately at construction and
  again on every subsequent theme change.
- **initial-editor-text**: Component MUST display `viewModel.value` as the
  editor's text content at construction.
- **editor-theme-colors**: Component MUST render the editor's text,
  background, insertion-point (caret), and selection-highlight colors from
  the active theme's `primaryText`, `controlBackground`, `cursor`, and
  `selection`/`selectionText` roles respectively, immediately at construction
  and again on every theme change.
- **text-view-delegate**: Component MUST handle the editor's own
  text-editing callbacks — specifically end-of-editing (see
  end-editing-commit) — itself, rather than routing them through a separate
  delegate object (see Platform Notes for the AppKit wiring).
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
  scroll view's content area.
- **text-wrapping**: Component MUST wrap text to the available width rather
  than scrolling horizontally.
- **text-container-inset**: Component MUST inset the typed text 4pt from the
  text container's edges on every side.
- **scrolling-container**: Component MUST host the editor inside a container
  that scrolls vertically, with a visible vertical scroll indicator and a
  bezeled border, so text beyond the visible height scrolls instead of
  growing the row without bound.
- **scroll-view-theme-background**: Component MUST draw the scrolling
  container's background using the active theme's `controlBackground` color,
  immediately at construction and again on every theme change.
- **label-scroll-view-layout**: Component MUST arrange the label above the
  scrolling container in a vertical, leading-aligned layout with
  `SettingsLayout.default[.rowSpacing]` (8pt) of spacing between them, and
  MUST pin that layout to all four edges of the component with no additional
  inset.
- **visible-height**: Component MUST fix the scrolling container's width to
  match the surrounding layout's width, and its visible height to a value
  computed from the active font's line height times `visibleLines`, so
  exactly that many lines are visible before scrolling begins.
- **superview-width-claim**: Component MUST, once added to a superview,
  claim that superview's full width through a layout constraint one priority
  level below required, so the editor is never narrower than its host
  without conflicting with a host that constrains it further.
- **label-resync**: Component MUST, whenever `viewModel.onChange` fires, set
  `label.stringValue` to `viewModel.title`.
- **self-inflicted-onchange-guard**: Component MUST NOT overwrite
  `textView.string` when `viewModel.onChange` fires while an internal
  `isCommitting` flag is `true`, and MUST NOT overwrite it when
  `textView.string` already equals the incoming `viewModel.value`.
- **external-value-adoption**: Component MUST, on a `viewModel.onChange`
  that is not self-inflicted (per self-inflicted-onchange-guard), set
  `textView.string` to the new `viewModel.value`.
- **caret-position-on-external-change**: Component MUST, when adopting an
  external value change (per external-value-adoption) while `textView` is
  the window's first responder, move the caret with
  `textView.setSelectedRange(NSRange(location: viewModel.value.count,
  length: 0))`.
- **accessibility-label**: Component MUST call
  `textView.setAccessibilityLabel(viewModel.title)` at construction, so
  VoiceOver announces the editor by the row's title instead of as an
  unnamed text area.
- **end-editing-commit**: Component MUST commit (write `textView.string`
  toward `viewModel.settingObserver.value`, per redundant-commit-guard) when
  `textDidEndEditing` fires.
- **window-detachment-commit**: Component MUST commit when the view is
  about to move to a `nil` window (`viewWillMove(toWindow: nil)`).
- **teardown-notification-observers**: Component MUST, whenever the view
  moves to a non-nil window, register observers on that window for
  `NSWindow.willCloseNotification` and, app-wide, for
  `NSApplication.willTerminateNotification`, each invoking `commit()` when it
  fires.
- **stale-observer-deregistration**: Component MUST remove any previously
  registered `NSWindow.willCloseNotification` and
  `NSApplication.willTerminateNotification` observers on itself every time
  the view is about to move to a window — including a `nil` one — before
  registering new ones.
- **redundant-commit-guard**: Component MUST NOT write to
  `viewModel.settingObserver.value` when `textView.string` already equals
  the current `settingObserver.value`.
- **commit-echo-guard**: Component MUST set an internal `isCommitting` flag
  to `true` for the duration of a `commit()` write to
  `viewModel.settingObserver.value`, and back to `false` immediately after,
  so the resulting `onChange` echo is recognized as self-inflicted (per
  self-inflicted-onchange-guard).
- **frame-init-rejection**: Component MUST NOT support construction via the
  frame-only `init(frame:)`; that initializer MUST trigger a fatal error.
- **coder-init**: Component MUST NOT support construction via
  `init(coder:)`; that initializer MUST trigger a fatal error.
- **main-actor-confinement**: Component MUST be usable only on the main
  actor; the class is declared `@MainActor`.
- **constituent-view-exposure**: Component MUST expose `label` and
  `textView` as public, directly-accessible properties.

## Appearance

- **Corner radius**: Not applicable — the source adds no custom layer or
  drawn shape to `textView` or the scroll view; the scroll view keeps
  whatever corner rendering AppKit's `.bezelBorder` border type draws.
- **Padding**: The vertical `NSStackView` uses `spacing =
  SettingsLayout.default[.rowSpacing]` = 8pt between `label` and the scroll
  view, and `pinToEdges` pins the stack's top/leading/trailing/bottom
  directly to the component's own edges with no additional constant — 0pt of
  outer padding beyond that 8pt internal gap. Inside the text view,
  `textContainerInset` adds 4pt on the top and 4pt on the bottom (and,
  since AppKit applies `NSSize` insets symmetrically, 4pt on each side) of
  the typed text within the scroll view's content area.
- **Font**: The label (`textRole: .button`) resolves to `TextRole.button`'s
  default style: 13pt, medium weight, proportional system font. `textView`'s
  typed text uses `TextRole.body`'s style (13pt, regular weight, proportional
  system font) when `monospaced` is `false`, or `TextRole.code`'s style
  (12pt, regular weight, monospaced system font) when `monospaced` is `true`
  (`palette.font(monospaced ? .code : .body)`). Both scale with the active
  theme's size scale and repaint on a theme change.
- **Background**: `textView.backgroundColor` and the scroll view's
  `backgroundColor` both resolve to the theme's `controlBackground` color —
  the theme's background blended 9% toward its foreground
  (`SemanticPalette.derive(.controlBackground)`) — recomputed on every theme
  change; the scroll view's `drawsBackground` is explicitly `true`.
- **Foreground/Text**: `textView.textColor` resolves to the theme's
  `primaryText` color (the theme's foreground, unchanged), matching the
  label's own `.primaryText` role. The insertion point uses the theme's
  `cursor` color; selected text uses the theme's `selection` color as its
  background and `selection.bestTextColor()` (the theme's own
  contrast-chosen counterpart) as its foreground.
- **Border**: Not customized beyond the scroll view's `borderType =
  .bezelBorder`; `textView` itself draws no border of its own — whatever
  bezel chrome AppKit's `.bezelBorder` scroll view style renders applies
  unmodified.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere in
  source.
- **Min/Max size**: `textView.minSize` is `.zero` and `maxSize` is
  unconstrained (`.greatestFiniteMagnitude` in both dimensions) so its
  content can grow without limit inside the scroll view; the component's own
  visible height is fixed by visible-height rather than by any min/max
  constraint on the component itself.

## States

| State | Appearance change |
|-------|------------------|
| Default | Label shows `viewModel.title`; `textView.string` equals `viewModel.value`, rendered in the theme's body/code font and colors described in Appearance. |
| Focused | Not styled by source — no focus-ring customization appears anywhere in `TextAreaEditView.swift`; AppKit's own default `NSTextView`/`NSScrollView` focus ring applies when `textView` becomes first responder. |
| Committed | After `commit()` runs (per end-editing-commit, window-detachment-commit, or teardown-notification-observers) and `textView.string` differs from `settingObserver.value`, the new value is written through (see commit-echo-guard). |
| External value adopted | When `viewModel.onChange` fires with a value the component did not itself just write, `textView.string` is replaced with the new value (see external-value-adoption), and the caret jumps to its end if the editor currently has focus (see caret-position-on-external-change). |
| Disabled | Not implemented in source: `textView.isEditable` and `isSelectable` are never set (both default `true`, so the field is always editable). A caller may set either directly through the public `textView` property; because `NSTextView` is not an `NSControl`, doing so produces no automatic visual dimming the way disabling an `NSControl` would. |
| Pressed | Not applicable: a text editor has no discrete pressed state distinct from becoming first responder and placing the caret; no such state is drawn in source. |
| Loading | Not applicable: the component performs no asynchronous operation and shows no loading indicator in source. |

## Accessibility

- **Role/trait**: Not customized — no `setAccessibilityRole` call appears in
  source; `textView` carries AppKit's own built-in text-area accessibility
  role.
- **Label requirements**: `textView.setAccessibilityLabel(viewModel.title)`
  is called once, at construction (accessibility-label), so VoiceOver
  announces the editor by the row's title. This does not go stale:
  `viewModel.title` is declared `public let title: String` on
  `AbstractViewModel`, so it cannot change after construction — the same
  invariant that makes `label-resync`'s repeated `label.stringValue =
  viewModel.title` assignment always a no-op (see Design Decisions).
- **Announce state changes**: Not applicable — the component has no loading
  state and never disables itself in source (see States); typed and deleted
  characters are announced through `NSTextView`'s own native accessibility
  value reporting, unmodified by source.
- **Minimum tap target**: Not applicable — this is a macOS,
  pointer/trackpad-driven `NSView`/`NSTextView` composition with no touch
  input path in source; the 44×44pt minimum is iOS/touch guidance. The
  component's clickable area is the full scroll view, sized by
  visible-height.
- **Keyboard navigation**: Not customized beyond AppKit's defaults — no
  `nextKeyView` wiring or key-view-loop exclusion appears in source, so
  `textView` participates in the window's normal Tab-order like any other
  `NSResponder`. Within the editor, `NSTextView`'s own default behavior
  inserts a tab character on Tab rather than moving focus to the next
  control — correct for a multi-line text/code editor, where a literal tab
  is valid content. Source does not itself document or test how a keyboard
  user leaves the editor once inside it; AppKit's own default key-view-loop
  binding (Ctrl+Tab / Ctrl+Shift+Tab moves to the next/previous key view once
  Tab itself is consumed by the control) is what would apply, but nothing in
  `TextAreaEditView.swift` asserts or overrides this, so it is recorded here
  as resting on an AppKit platform default rather than on this file (see
  Compliance: `keyboard-navigable` is `partial`, not `passed`, for this
  reason).
- **Contrast**: Not set independently by this component — `textView`'s typed
  text resolves to the theme's `primaryText` role (unchanged foreground; no
  minimum contrast computed for this role), matching the label. Whether an
  active theme's resolved `primaryText`-on-`controlBackground` pairing
  clears WCAG 2.1 SC 1.4.3's 4.5:1 threshold for normal text is a property
  of the chosen `ColorTheme`, not of `TextAreaEditView.swift`.
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented in source. The label and text-view text color resolves from the active theme's primaryText role against the hosting background at runtime; the component performs no contrast check, so whether a given theme's resolved pair meets 4.5:1 cannot be determined from this file. This would be settled by a theme-level contrast audit of primaryText against the backgrounds it sits on.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| text-area-edit-view-001 | initializer-parameters | Construct with only `viewModel` supplied | `visibleLines == 6` and `monospaced == false` |
| text-area-edit-view-002 | row-label-text | `viewModel.title = "Prompt"` | `label.stringValue == "Prompt"` after init |
| text-area-edit-view-003 | editor-font-role | Construct with `monospaced: true`, then trigger a theme change | `textView.font` equals the theme's `.code`-role font both immediately after construction and after the theme change |
| text-area-edit-view-004 | initial-editor-text | `viewModel.value = "hello"` | `textView.string == "hello"` after init |
| text-area-edit-view-005 | editor-theme-colors | Construct the view, then trigger a theme change | `textView.textColor`, `backgroundColor`, `insertionPointColor`, and `selectedTextAttributes` all equal the theme's corresponding colors, both immediately after construction and after the change |
| text-area-edit-view-006 | text-view-delegate | Construct the component | `textView.delegate === view` |
| text-area-edit-view-007 | plain-text-mode | Construct the component | `textView.isRichText == false` |
| text-area-edit-view-008 | undo-support | Construct the component | `textView.allowsUndo == true` |
| text-area-edit-view-009 | automatic-substitution-suppression | Construct the component | `isAutomaticQuoteSubstitutionEnabled`, `isAutomaticDashSubstitutionEnabled`, `isAutomaticTextReplacementEnabled` are all `false` |
| text-area-edit-view-010 | vertical-growth | Construct the component | `isVerticallyResizable == true`, `isHorizontallyResizable == false`, `autoresizingMask == [.width]` |
| text-area-edit-view-011 | text-wrapping | Construct the component | `textView.textContainer.widthTracksTextView == true`; `containerSize.height == .greatestFiniteMagnitude` |
| text-area-edit-view-012 | text-container-inset | Construct the component | `textView.textContainerInset == NSSize(width: 4, height: 4)` |
| text-area-edit-view-013 | scrolling-container | Construct the component | `textView.enclosingScrollView`'s `documentView === textView`, `hasVerticalScroller == true`, `borderType == .bezelBorder` |
| text-area-edit-view-014 | scroll-view-theme-background | Construct the view, then trigger a theme change | Scroll view's `drawsBackground == true` and `backgroundColor` equals the theme's `controlBackground` color both times |
| text-area-edit-view-015 | label-scroll-view-layout | Construct the component | `label` precedes the scroll view in a single vertical `NSStackView` with `spacing == 8`, pinned to the component's edges |
| text-area-edit-view-016 | visible-height | Construct with `visibleLines: 6` and a known font | Scroll view's height constraint constant equals `(lineHeight * 6).rounded() + 8`; its width constraint equals the stack's width |
| text-area-edit-view-017 | superview-width-claim | Add the component to a superview | A width constraint equal to the superview's width is active at priority `999` |
| text-area-edit-view-018 | label-resync | Invoke `viewModel.onChange(newValue)` | `label.stringValue == viewModel.title` after the call |
| text-area-edit-view-019 | self-inflicted-onchange-guard | Call `commit()` while `textView.string` differs from `settingObserver.value` | During the resulting `onChange` echo, `textView.string` is not overwritten and the caret is not moved |
| text-area-edit-view-020 | external-value-adoption | With no `commit()` in progress, externally set `viewModel`'s backing value and invoke `onChange(newValue)` where `newValue != textView.string` | `textView.string == newValue` after the call |
| text-area-edit-view-021 | caret-position-on-external-change | Make `textView` first responder, then trigger an external `onChange(newValue)` | `textView.selectedRange == NSRange(location: newValue.count, length: 0)` |
| text-area-edit-view-022 | accessibility-label | Construct with `viewModel.title = "Script"` | `textView.accessibilityLabel() == "Script"` |
| text-area-edit-view-023 | end-editing-commit | Set `textView.string = "new"` where `settingObserver.value == "old"`, then post `NSText.didEndEditingNotification` (deliver `textDidEndEditing`) | `settingObserver.value == "new"` |
| text-area-edit-view-024 | window-detachment-commit | With `textView.string` differing from `settingObserver.value`, move the component to a `nil` window | `settingObserver.value` equals `textView.string` after the move |
| text-area-edit-view-025 | teardown-notification-observers | Attach the component to a window, diverge `textView.string` from `settingObserver.value`, then post that window's `willCloseNotification` | `settingObserver.value` equals `textView.string` after the notification |
| text-area-edit-view-026 | stale-observer-deregistration | Move the component from window A to window B, then post window A's `willCloseNotification` | `commit()` is not triggered by window A's notification after the move |
| text-area-edit-view-027 | redundant-commit-guard | Wrap `settingObserver` with a write-counting observer; set `settingObserver.value = "same"` and `textView.string = "same"`; call `commit()` | The write-counting observer records zero additional writes; `settingObserver.value` remains `"same"` |
| text-area-edit-view-028 | commit-echo-guard | Wrap `settingObserver` with a write-counting observer; set `textView.string` to a value different from `settingObserver.value`; call `commit()` | The write-counting observer records exactly one write, carrying the new value |
| text-area-edit-view-029 | frame-init-rejection | Attempt `TextAreaEditView(frame: .zero)` | The call traps with a fatal error; no instance is returned |
| text-area-edit-view-030 | coder-init | Attempt `TextAreaEditView(coder: someCoder)` | The call traps with a fatal error; no instance is returned |
| text-area-edit-view-031 | main-actor-confinement | Attempt to construct or mutate a `TextAreaEditView` from off the main actor | Compiler rejects the call under Swift's `@MainActor` isolation checking |
| text-area-edit-view-032 | constituent-view-exposure | Construct the component, then access `.label` and `.textView` externally | Both properties are accessible and return the instances built during init |

## Edge Cases

- **Null/empty input**: `viewModel` (`ComposableSettings.ViewModel<String>`)
  is a non-optional, typed constructor parameter, so Swift's type system
  rules out `nil`; the component performs no null-handling of its own. An
  empty `viewModel.title` or `viewModel.value` produces an empty label or
  empty editor with no crash.
- **Boundary values**: Not applicable to `viewModel.value`'s length — it is
  a `String` with no minimum or maximum enforced anywhere in source; any
  length is accepted, wraps, and scrolls. `visibleLines` has no lower-bound
  guard either: a caller passing `0` or a negative value produces a height
  constraint constant of `8` or less (per visible-height's formula), which
  is a degenerate but non-crashing layout, not a value source rejects.
- **Non-BMP / multi-scalar characters in the caret calculation**: SHOULD be
  revisited. `caret-position-on-external-change` computes the caret location
  as `viewModel.value.count` — Swift's grapheme-cluster count — and passes
  it directly as an `NSRange` location, which `NSTextView` interprets in
  UTF-16 code units. For a value containing characters whose grapheme
  clusters span more than one UTF-16 unit (emoji, many combining-mark or
  CJK-extension sequences), the grapheme count is strictly less than the
  UTF-16 length, so the caret lands short of the true end of the text rather
  than at it. Because grapheme count never exceeds UTF-16 length, the range
  stays within bounds — this is a documented precision quirk (technical
  debt), not a crash risk (see Design Decisions).
- **Concurrent access**: Not applicable — the class is declared `@MainActor`,
  so all construction and mutation is serialized to the main actor by the
  compiler (see main-actor-confinement).
- **Error states**: Not applicable — every operation in source (the text
  view's commit path and the `settingObserver.value` write) is a
  synchronous, non-throwing call; no `try`, `Result`, or error-producing API
  appears anywhere in `TextAreaEditView.swift`.
- **Offline/disconnected**: Not applicable — the component performs no
  networking of its own; it only reads from and writes to an in-process
  `ComposableSettings.ViewModel<String>`.
- **Overwritten external observer**: `viewModel.onChange` is a single
  closure property, and `init` unconditionally assigns its own closure to
  it, replacing whatever handler, if any, was previously registered on that
  view model. Constructing a second observer against the same view model
  instance silently drops the earlier handler — a known limitation of plain
  closure-property assignment, not a validated or guarded interaction (see
  Design Decisions).
- **View torn down mid-edit**: Handled explicitly in source, not left
  undefined — `viewWillMove(toWindow:)` commits when the new window is `nil`,
  and window-close/app-termination notifications commit before the window
  actually closes or the app actually quits (see window-detachment-commit
  and teardown-notification-observers), specifically because
  `textDidEndEditing` never fires for a view that is torn down with the
  caret still inside it (per the source's own doc comment).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | `ComposableSettings.ViewModel<String>` | — (required) | Supplies the row's title and current string value; receives committed edits via `settingObserver.value`. The initializer overwrites this view model's `onChange` closure with the component's own sync handler (see Edge Cases). `viewModel.explanation` (inherited from `AbstractViewModel`) is accepted but never read or displayed by `TextAreaEditView`. |
| `visibleLines` | `Int` | `6` | Height of the editor, in lines of the editing font; content beyond it scrolls rather than growing the row (see visible-height). |
| `monospaced` | `Bool` | `false` | Selects the theme's `.code`-role font (fixed-width) when `true`, or `.body` (proportional) when `false`; per source, right for prompts/code, wrong for prose. |

## Deep Linking

Not applicable: `TextAreaEditView` is a row inside a composable settings
window, not a navigable screen; no URL scheme, route, or deep-link handler
appears anywhere in source.

## Localization

Not applicable: source contains no user-facing string literal of its own.
The row's title comes entirely from `viewModel.title`, and its text content
from `viewModel.value` — both values the caller provides — so there is
nothing for this component to localize itself.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: source contains no animation, transition, or `NSAnimationContext` call; every state change (label/text sync, theme restyle, commit) is an instantaneous property assignment. |
| Increase Contrast | Not applicable to this file directly: source sets no literal `NSColor`; text/background color come from the theme's `primaryText`/`controlBackground`/`selection`/`cursor` roles, whose actual resolved contrast is the theme layer's responsibility, not this component's. |
| Differentiate Without Color | Not applicable: the component conveys no state through color alone — selection is communicated by the standard highlighted-background text-selection affordance common to all text editors, not by a color-only signal distinguishing otherwise-identical content. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears anywhere
in source; the row always renders once constructed.

## Analytics

Not applicable: source contains no analytics or telemetry call.

## Privacy

- **Data collected**: The text typed into `textView` — per the source's own
  doc comment, typically an LLM prompt, a template, or a script snippet.
  The component does not classify or redact this value; it holds it in
  `textView.string` and `viewModel.settingObserver.value` and passes it
  through unchanged.
- **Storage**: Not applicable within `TextAreaEditView.swift` — the value is
  held only in `textView.string` and `viewModel.settingObserver.value` for
  the view's lifetime. Persistence, when it happens, is owned by the
  caller-supplied `ComposableSettings.ViewModel<String>`'s backing
  `UserSetting<String>`; unlike `SecureTextEditView`'s doc comment, source
  here says nothing about routing to secure/keychain storage, so the default
  `SettingsStore` provider applies unless the caller's `UserSetting`
  specifies otherwise — none of which is code in this file.
- **Transmission**: Not applicable within this file — no networking call
  appears anywhere in source. The doc comment's remark that automatic text
  substitutions are disabled "because text gets sent to a model verbatim"
  describes a downstream consumer's behavior, not anything this file itself
  transmits.
- **Retention**: The value lives only in `textView.string` and
  `viewModel.settingObserver.value` for as long as the row is on screen and
  its view model is retained. No explicit clearing or secure-erasure call is
  made on the string anywhere in source; it is released with the view and
  its view model like any other property.

## Logging

Not applicable: source contains no logging call (no `print`, `os_log`, or
logger reference anywhere in `TextAreaEditView.swift`).

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
  `createLabel(title:)` helper). There is no UIKit code path in source. A
  UIKit port would replace `NSTextView`/`NSScrollView` with a `UITextView`
  (which is natively scrolling, so no separate scroll view is needed),
  implement `UITextViewDelegate.textViewDidEndEditing(_:)` as the commit
  path, and disable `autocorrectionType`/`smartQuotesType`/
  `smartDashesType`/`smartInsertDeleteType` as the substitution-disabling
  analog. Concretely, the AppKit source satisfies text-view-delegate via
  `textView.delegate = self`; plain-text-mode via `textView.isRichText =
  false`; undo-support via `textView.allowsUndo = true`;
  automatic-substitution-suppression via
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
  `.required - 1` (999).
- **WinUI 3** (the reason this recipe exists): Build the row as a vertical
  `StackPanel` (8px `Spacing`, the WinUI analog of `SettingsLayout.default[
  .rowSpacing]`) containing a `TextBlock` for the title and a `TextBox` with
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

- **Decision**: Document caret-position-on-external-change's use of
  `viewModel.value.count` (a grapheme-cluster count) as an `NSRange`
  location (a UTF-16 offset) as a known precision quirk rather than
  idealizing it into "moves the caret to the exact end."
  **Rationale**: for text containing graphemes that span more than one
  UTF-16 code unit (emoji, some combining sequences, many CJK-extension
  characters), grapheme count is strictly less than UTF-16 length, so the
  computed range lands short of the true end. It never exceeds the string's
  bounds (grapheme count is never greater than UTF-16 length), so this is
  reduced caret precision for such text, not a crash — technical debt
  affecting behavioral correctness, recorded per source-fidelity rather than
  smoothed over.
  **Approved**: pending
- **Decision**: Treat the closure-overwrite behavior of `viewModel.onChange`
  as a known limitation rather than contract behavior other code should
  rely on.
  **Rationale**: `viewModel.onChange` is a single closure property; `init`
  unconditionally assigns its own handler to it, which silently drops
  whatever handler, if any, was previously registered on the same view
  model instance. That is a source-traceable hazard of plain
  closure-property assignment, not a deliberate feature — recording it as a
  design decision keeps it from being read as required behavior for other
  implementations to replicate, while acknowledging the source does behave
  this way today.
  **Approved**: pending
- **Decision**: Keep the `label.stringValue = viewModel.title` resync
  (label-resync) inside `viewModel.onChange` even though `viewModel.title`
  cannot change after construction for this view model.
  **Rationale**: `AbstractViewModel.title` is declared `public let`, so for
  `TextAreaEditView` today the assignment is always a no-op. It exists
  because the same `onChange` handler is also responsible for the
  value-sync and caret logic (external-value-adoption,
  caret-position-on-external-change) that must run regardless, and keeping
  the label resync alongside them means every `ComposableSettings` row's
  `onChange` handler is written the same shape, so a reviewer or future
  editor of any row type does not have to remember which ones need it — a
  present-day consistency benefit, not a hedge against a hypothetical
  future view model.
  **Approved**: pending
- **Decision**: Accept the scroll view's height formula's `+ 8` constant as
  an undocumented magic number in source, while noting the most plausible
  explanation rather than asserting it as fact.
  **Rationale**: `TextAreaEditView.swift` never comments why `8`
  specifically is added to `(lineHeight * visibleLines).rounded()`; the
  value matches the sum of `textContainerInset`'s 4pt top and 4pt bottom
  insets set a few lines earlier in the same initializer, which would make
  the `+ 8` compensation for that inset so all `visibleLines` lines remain
  fully visible — but source does not state this correlation explicitly, so
  it is recorded here as the most likely reading, not as verified fact.
  **Approved**: pending
- **Decision**: Restrict superview-width-claim's constraint to priority
  `.required - 1` (999) rather than `.required` (1000).
  **Rationale**: per the source's own comment, the enclosing stack already
  aligns `.leading`, so the component must claim the full width itself to
  be usable for editing — but a host that insets its hosted controls (the
  comment's example: a popover pinning `width == stack.width - 32`) would
  otherwise create two conflicting required-width constraints, which
  AppKit resolves by breaking whichever one it prefers. One priority level
  below required avoids that conflict while still winning against any
  lower-priority sizing.
  **Approved**: pending
- **Decision**: Reuse `TextEditView.createLabel(title:)` for the label
  rather than composing the label independently or subclassing
  `TextEditView`.
  **Rationale**: `TextAreaEditView` needs `TextEditView`'s label
  construction (`ComposableSettings.makeRowLabel`, `.button` text role) but
  none of its row layout, single-line field, or target/action commit path,
  which are wrong for a multi-line, commit-on-focus-loss editor; calling
  the one static helper it needs avoids inheriting behavior that does not
  apply.
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
