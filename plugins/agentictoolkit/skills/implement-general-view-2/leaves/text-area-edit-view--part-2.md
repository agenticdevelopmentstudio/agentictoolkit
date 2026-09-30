<!-- leaf: implement-general-view-2/text-area-edit-view--part-2 · source: text-area-edit-view.md -->

# TextAreaEditView — continued (part 2)

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | `ComposableSettings.ViewModel<String>` | — (required) | Supplies the row's title and current string value; receives committed edits via `settingObserver.value`. The initializer overwrites this view model's `onChange` closure with the component's own sync handler (see Edge Cases). `viewModel.explanation` (inherited from `AbstractViewModel`) is accepted but never read or displayed by `TextAreaEditView`. |
| `visibleLines` | `Int` | `6` | Height of the editor, in lines of the editing font; content beyond it scrolls rather than growing the row (see visible-height). |
| `monospaced` | `Bool` | `false` | Selects the theme's `.code`-role font (fixed-width) when `true`, or `.body` (proportional) when `false`; per source, right for prompts/code, wrong for prose. |

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: source contains no animation, transition, or `NSAnimationContext` call; every state change (label/text sync, theme restyle, commit) is an instantaneous property assignment. |
| Increase Contrast | Not applicable to this file directly: source sets no literal `NSColor`; text/background color come from the theme's `primaryText`/`controlBackground`/`selection`/`cursor` roles, whose actual resolved contrast is the theme layer's responsibility, not this component's. |
| Differentiate Without Color | Not applicable: the component conveys no state through color alone — selection is communicated by the standard highlighted-background text-selection affordance common to all text editors, not by a color-only signal distinguishing otherwise-identical content. |

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

