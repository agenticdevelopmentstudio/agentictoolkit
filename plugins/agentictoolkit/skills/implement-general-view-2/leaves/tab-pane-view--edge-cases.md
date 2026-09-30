<!-- leaf: implement-general-view-2/tab-pane-view--edge-cases · source: tab-pane-view.md -->

# TabPaneView

**Rules** (cite as `implement-general-view-2/tab-pane-view--edge-cases#<slug>`):

- `null-empty-input-setstatussymbols-leave-statusstack-arranged` MUST — Null/empty input (MUST): setStatusSymbols([]) MUST leave statusStack with no arranged subviews and statusViews == []. …
- `edge-depth-more-produce-same-12pt-recession` MUST — Boundary values (documented behavior, not a gap): stackDepth accepts any Int with no lower or upper clamp in this file. …
- `error-states-setstatussymbols-substitute-empty-nsimage` MUST — Error states (MUST): setStatusSymbols(_:) MUST substitute an empty NSImage() when …

## Edge Cases

- Null/empty input (MUST): `setStatusSymbols([])` MUST leave `statusStack`
  with no arranged subviews and `statusViews == []`. `contentSize` MUST still
  return at least `240×136pt` even when every label's `stringValue` is empty
  and no status symbols are set, because of the unconditional `min`/`max`
  floor in `contentSize`.
- Boundary values (documented behavior, not a gap): `stackDepth` accepts any
  `Int` with no lower or upper clamp in this file. `recession(atDepth:)`
  treats any depth `≤ 0` as zero recession, while `isFrontCard` requires
  `stackDepth == 0` exactly — so a negative `stackDepth` draws the
  non-front palette (`windowBackground`/`border`/`tertiaryText`) at zero
  inset and zero overhang, a combination no depth of `0` or greater produces.
  See Design Decisions. On a vertical edge, any depth of `3` or more MUST
  produce the same `12pt` recession (`min(depth, maxStackDepth)`).
- Concurrent access: Not applicable — `TabPaneView` is `@MainActor`; every
  mutable property (`stackDepth`, `onClose`, `contextMenuProvider`) and every
  method in this file is confined to the main actor, so source provides no
  path for two threads to mutate one instance at the same time.
- Error states (MUST): `setStatusSymbols(_:)` MUST substitute an empty
  `NSImage()` when `NSImage(systemSymbolName:accessibilityDescription:)`
  returns `nil` for an unrecognized symbol name, rather than crashing.
  `TabCardBackgroundView.draw(_:)` MUST draw nothing when `strokeBounds()` has
  zero or negative width or height, rather than constructing a degenerate
  `NSBezierPath`.
- Offline/disconnected: Not applicable — this view performs no networking of
  any kind; every value it displays is handed to it in-process (by
  `TabPaneViewController.reload()`, outside this source).
