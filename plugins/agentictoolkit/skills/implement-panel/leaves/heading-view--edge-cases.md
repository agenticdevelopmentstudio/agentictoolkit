<!-- leaf: implement-panel/heading-view--edge-cases · source: panel-heading-view.md -->

# PanelHeadingView

## Edge Cases

- **Null/empty input**: `title` is a required, non-optional `String`
  parameter, so Swift's type system rules out `nil`. An empty string (`""`)
  renders an empty `titleLabel`, with no guard against it in source — a
  consequence of `sets-title-text-from-caller`. `caption` is `String?` and
  defaults to `nil`; an explicit empty string (`caption: ""`) is non-`nil`,
  so it still constructs a caption view whose label renders empty, since
  `creates-caption-view-when-caption-given` does not special-case an empty
  but non-`nil` string.
- **Boundary values**: Not applicable in the numeric sense — the component's
  only inputs are the two caller-supplied strings; it has no
  caller-configurable numeric range. A very long `title` is clipped, not
  wrapped, because `PanelHeadingView.swift` never reconfigures `titleLabel`'s
  wrap settings; a very long `caption` wraps across more lines instead,
  because its width is matched to the stack (`matches-caption-width-to-stack`)
  while `ExplanationView` itself is configured to wrap.
- **Concurrent access**: Not applicable — the class is `@MainActor`-isolated;
  the Swift compiler rejects construction or mutation of `self`, `titleLabel`,
  or `captionView` from off the main actor.
- **Error states (dependency/network failure)**: Not applicable — the source
  performs no I/O, network call, or dependency lookup of any kind.
- **Offline/disconnected state**: Not applicable — `PanelHeadingView`
  performs no networking of its own.
- **Caption text reassigned after construction**: `PanelHeadingView` exposes
  `captionLabel` as `NSTextField?`, so a caller with a non-`nil` caption can
  reassign `captionLabel?.stringValue` directly, reached through the
  forwarding `captionLabel` computed property rather than any
  `update`/`setText` method `PanelHeadingView` itself defines. This mirrors
  the pattern the `ExplanationView` recipe's own
  `updates-text-via-label-property` requirement documents for that view (see
  `agentictoolkit://recipes/explanation-view#requirements/updates-text-via-label-property`;
  also Design Decisions).
- **Constructed with `caption: nil` and later needing one**: `captionView`
  is constructed once at `init` time and never reassigned; the source
  provides no way to add a caption to a `PanelHeadingView` that was built
  without one — a caller that needs a caption supplies it at construction.
  This is a source-traceable consequence of
  `omits-caption-view-when-caption-nil`: no method exists to set
  `captionView` after `init` returns.
