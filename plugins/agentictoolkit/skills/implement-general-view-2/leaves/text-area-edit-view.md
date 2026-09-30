<!-- leaf: implement-general-view-2/text-area-edit-view · source: text-area-edit-view.md -->

**Rules** (cite as `implement-general-view-2/text-area-edit-view#<slug>`):

- `initializer-parameters` MUST
- `row-label-text` MUST
- `editor-font-role` MUST
- `initial-editor-text` MUST
- `editor-theme-colors` MUST
- `text-view-delegate` MUST
- `plain-text-mode` MUST
- `undo-support` MUST
- `automatic-substitution-suppression` MUST
- `vertical-growth` MUST
- `text-wrapping` MUST
- `text-container-inset` MUST
- `scrolling-container` MUST
- `scroll-view-theme-background` MUST
- `label-scroll-view-layout` MUST
- `visible-height` MUST
- `superview-width-claim` MUST
- `label-resync` MUST
- `self-inflicted-onchange-guard` MUST
- `external-value-adoption` MUST
- `caret-position-on-external-change` MUST
- `accessibility-label` MUST
- `end-editing-commit` MUST
- `window-detachment-commit` MUST
- `teardown-notification-observers` MUST
- `stale-observer-deregistration` MUST
- `redundant-commit-guard` MUST
- `commit-echo-guard` MUST
- `frame-init-rejection` MUST
- `coder-init` MUST
- `main-actor-confinement` MUST
- `constituent-view-exposure` MUST

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

