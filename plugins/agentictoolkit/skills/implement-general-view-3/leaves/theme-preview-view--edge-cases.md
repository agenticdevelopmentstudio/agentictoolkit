<!-- leaf: implement-general-view-3/theme-preview-view--edge-cases · source: theme-preview-view.md -->

# ThemePreviewView

**Rules** (cite as `implement-general-view-3/theme-preview-view--edge-cases#<slug>`):

- `explicitly-concrete-colortheme-empty-initial-state-crash` MUST — Null/empty input: theme defaults to nil in init(theme:). When nil, container remains empty and self's background is …
- `show-teardown-rebuild-traceable-unconditional-arrangedsubviews-foreach` MUST — Boundary values — repeated/idempotent show(_:): calling show(_:) multiple times, including twice with the same theme, …

## Edge Cases

- Null/empty input: `theme` defaults to `nil` in `init(theme:)`. When `nil`,
  `container` remains empty and `self`'s background is never painted until
  `show(_:)` is called explicitly with a concrete `ColorTheme` — this is a
  MUST (`empty-initial-state`), not a crash or a placeholder theme.
- Boundary values — repeated/idempotent `show(_:)`: calling `show(_:)`
  multiple times, including twice with the same theme, produces the same
  visual result each time because every call tears down all existing
  arranged subviews before rebuilding (`show-teardown-and-rebuild`).
  This is a MUST, traceable to the unconditional
  `arrangedSubviews.forEach { $0.removeFromSuperview() }` at the top of
  `show(_:)`.
- Boundary values — long or narrow content: cards are forced to exactly
  `container`'s width (`card-width-stretch`), but no label anywhere in
  `ThemePreviewView.swift` sets `lineBreakMode`, `maximumNumberOfLines`, or
  `usesSingleLineMode`, so in a very narrow host or with an enlarged
  typography scale, list-row detail labels, badge text, or the chrome
  sample's content can be clipped or compressed rather than reflowed, per
  each plain `NSTextField(labelWithString:)`'s AppKit default.
- Concurrent access: Not applicable — the class is `@MainActor`-isolated, so
  Swift's concurrency checker serializes every call to `show(_:)` and every
  private `make*Sample` helper; there is no code path by which two threads
  mutate `container` simultaneously.
- Error states: Not applicable — every operation in `show(_:)` and its
  helpers is a synchronous, non-throwing property assignment or view
  construction. `TerminalAppearance.resolvedFont(theme:)`,
  `resolvedPadding(theme:)` and `resolvedCursor(theme:)` are non-throwing,
  total functions over `theme` and `UserSettings` defaults (verified in
  `TerminalAppearance.swift`) and always resolve to a concrete value; no
  `try`, `Result`, or optional is propagated to `ThemePreviewView` from any
  of them.
- Offline/disconnected state: Not applicable — the component performs no
  networking of its own; it only renders values resolved from the supplied
  `ColorTheme` and local `UserSettings` defaults.
- Quirk — swatch grid excluded from the width stretch: `show(_:)` activates
  the `widthAnchor == container.widthAnchor` constraint only over the `cards`
  array (the five sample boxes); the `SwatchGridView` appended afterward is
  never included in that `.map`, so it is left at its own content-driven
  width. With the hardcoded `columns: 8` and exactly 16 ANSI colors this
  always renders two full rows regardless, so the omission has no visible
  effect today, but it is a documented, source-traceable asymmetry rather
  than something this recipe assumes is intentional design.
- Quirk — chrome sample's divider/inner-panel width constraints reference
  the outer `box`: `fill(box, with: [...])` returns the same `box` instance
  it was given (not a wrapper), which is what lets
  `divider.widthAnchor.constraint(equalTo: box.widthAnchor, constant: -24)`
  and the equivalent `inner` constraint — both activated *after* `fill(...)`
  returns — resolve correctly against the final card width.
