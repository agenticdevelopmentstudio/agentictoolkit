<!-- leaf: implement-general-1/font-chooser-button--edge-cases · source: font-chooser-button.md -->

# FontChooserButton

## Edge Cases

- **Null/empty input**: `show(_:title:)`'s `font` parameter is optional and
  `nil` is an explicit, handled case (falls back to the system font — see
  #requirements/system-font-fallback). `title` is a non-optional `String`;
  an empty string is drawn as an empty title with no crash — already
  covered by #requirements/caller-supplied-title, which sets `title` to
  whatever is passed verbatim, empty or not.
- **Boundary values**: `init(width:)`'s `width` is an unconstrained
  `CGFloat` passed straight into
  `widthAnchor.constraint(equalToConstant: width)` with no clamping or
  validation. A zero or negative width is passed through unchanged and
  produces a zero-width or Auto-Layout-unsatisfiable constraint; this is
  not validated (current behavior) — the component performs no
  bounds-checking of its own on `width`.
- **Concurrent access**: Not applicable — the class is `@MainActor`, so
  Swift's concurrency checker serializes all construction and mutation to
  the main actor; there is no code path by which two threads mutate the
  same instance simultaneously.
- **Error states**: Not applicable for `show`/panel wiring — every
  operation in this file is a synchronous, non-throwing call; no `try`,
  `Result`, or error-producing API appears in source. There is a related,
  documented memory-safety hazard rather than an error state:
  `NSFontManager.target` is declared `unowned(unsafe)` (per the test
  suite's own comment), so a `FontChooserButton` deallocated while still
  registered as the manager's target would leave the manager writing into
  freed memory. `viewDidMoveToWindow()`'s target-release (see
  #requirements/font-manager-target-release) is the source's only guard
  against this, and it fires on window removal, not on `deinit` directly
  (see Design Decisions for the accepted residual risk).
- **Offline/disconnected state**: Not applicable — the component performs
  no networking of its own.
- **Multiple instances sharing the font manager**: `NSFontManager.shared`
  has one `target` at a time. WHEN two `FontChooserButton` instances exist
  and both have opened the panel, the most recently opened one owns the
  target; the earlier one's later `removeFromSuperview()` is guarded by
  `NSFontManager.shared.target === self` and so correctly does nothing,
  leaving the panel's current target untouched — already covered by
  #requirements/font-manager-target-release, whose "target is still this
  instance" condition is exactly this `===` identity check.
- **Panel opened before any font is ever chosen**: `openFontPanel(_:)`'s
  `panelFont` falls back to `NSFont.systemFont(ofSize: NSFont.systemFontSize)`
  when `selectedFont` is `nil`, so opening the panel on a
  freshly-constructed, never-`show`-called button does not crash and seeds
  the panel with the system font at the system's default point size
  (which is not `sampleSize`) — already covered by #requirements/panel-seed,
  whose "otherwise the system font at `NSFont.systemFontSize`" branch is
  exactly this nil-coalescing fallback.
