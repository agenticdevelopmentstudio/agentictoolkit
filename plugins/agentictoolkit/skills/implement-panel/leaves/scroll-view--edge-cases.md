<!-- leaf: implement-panel/scroll-view--edge-cases · source: panel-scroll-view.md -->

# PanelScrollView

**Rules** (cite as `implement-panel/scroll-view--edge-cases#<slug>`):

- `instance-already-installed-first-remove-instance-via` MUST — Boundary values (re-installing the same instance): calling setContent(_:) a second time with the same view instance …

## Edge Cases

- Null/empty input: `setContent(_:)` takes a non-optional `NSView`; Swift's
  type system rules out `nil` for `view`, so source contains no null-check
  path. When an empty (zero-intrinsic-size) view is installed, the
  `equalTo`/`greaterThanOrEqualTo` constraints in `setContent` still stretch
  it to `contentView`'s width and to at least its height (see
  **content-width-matches-viewport** and **content-min-height-viewport**), so
  the visible area is always filled.
- Boundary values (no content installed): before `setContent` is ever called,
  the document view carries only the top/leading constraints activated in
  `init`; it has no width or height constraint of its own, so its size
  resolves to zero in this state, since nothing else constrains it.
- Boundary values (re-installing the same instance): calling `setContent(_:)`
  a second time with the same view instance that is already installed MUST
  first remove that instance via `removeFromSuperview()` and then re-add and
  re-constrain it, per the unconditional `document.subviews.forEach {
  $0.removeFromSuperview() }` in source.
- Concurrent access: Not applicable — `PanelScrollView` is `@MainActor`-
  isolated (see main-actor-isolated), so every read and write of its state,
  including calls to `setContent`, is serialized on the main actor; source
  provides no additional synchronization because none is needed.
- Error states: `setContent(_:)` has no error return path and performs no
  validation of `view`. If `view` already carries constraints or a superview
  relationship that conflicts with the four edge constraints `setContent`
  activates, `NSLayoutConstraint.activate` does not throw (the API is
  non-throwing); any conflict surfaces only as an Auto Layout console
  diagnostic at runtime, since source contains no conflict detection or
  recovery.
- Offline/disconnected: Not applicable — `PanelScrollView` performs no
  networking of its own; its behavior does not depend on connectivity.
