<!-- leaf: implement-general-view-2/text-area-edit-view--edge-cases · source: text-area-edit-view.md -->

# TextAreaEditView

**Rules** (cite as `implement-general-view-2/text-area-edit-view--edge-cases#<slug>`):

- `non-bmp-multi-scalar-characters-in-the-caret-calculation` SHOULD — SHOULD be revisited. caret-position-on-external-change computes the caret location as viewModel.value.count — Swift's …

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
