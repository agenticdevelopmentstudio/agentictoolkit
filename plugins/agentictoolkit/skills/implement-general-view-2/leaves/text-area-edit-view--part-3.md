<!-- leaf: implement-general-view-2/text-area-edit-view--part-3 · source: text-area-edit-view.md -->

# TextAreaEditView — continued (part 3)

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
