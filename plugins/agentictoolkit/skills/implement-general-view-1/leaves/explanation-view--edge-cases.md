<!-- leaf: implement-general-view-1/explanation-view--edge-cases · source: explanation-view.md -->

# ExplanationView

**Rules** (cite as `implement-general-view-1/explanation-view--edge-cases#<slug>`):

- `very-long-text-with-no-width-constraint` MUST — with both horizontal priorities set to .defaultLow and vertical compression-resistance set to .required, the label …

## Edge Cases

- **Null/empty input**: `text` is a non-optional `String` constructor
  parameter, so Swift's type system rules out `nil`. An empty string (`""`)
  renders an empty label with no guard against it in source.
- **Boundary values**: Not applicable in the numeric-input sense —
  `ExplanationView`'s only input is a caller-supplied string; it has no
  length limit, minimum/maximum, or other caller-configurable numeric range
  for a boundary to test.
- **Concurrent access**: Not applicable — the class is `@MainActor`-isolated;
  the Swift compiler rejects construction or mutation of `self`/`label` from
  off the main actor, so there is no concurrent-access surface to define
  behavior for.
- **Error states (dependency/network failure)**: Not applicable — the
  source performs no I/O, network call, or dependency lookup of any kind.
- **Offline/disconnected state**: Not applicable — `ExplanationView`
  performs no network operation of its own.
- **Very long text with no width constraint**: with both horizontal
  priorities set to `.defaultLow` and vertical compression-resistance set
  to `.required`, the label wraps and grows taller only once something
  constrains `ExplanationView`'s own width (a superview's width constraint,
  or a stack/grid cell) — `fills-view-edge-to-edge`'s edge-to-edge pins carry
  that width straight through to the label. The source sets no
  `preferredMaxLayoutWidth` and no width constraint of its own
  (`compresses-and-hugs-loosely-horizontally`), so Auto Layout has no
  authoritative width to wrap against until the container supplies one: a
  container that does not constrain the view's width leaves the label's
  wrapped height ambiguous at that layout pass. The container MUST constrain
  the view's width for `wraps-across-lines`/`resists-vertical-compression`
  to produce a determinate multi-line height.
- **Text reassigned after construction**: callers mutate `label.stringValue`
  directly (e.g. `ExtensionsBrowsePanel.swift`'s
  `selectionName.label.stringValue = ...`); each reassignment triggers
  `NSTextField`'s standard intrinsic-content-size invalidation, which
  re-wraps and re-measures the label at its next layout pass — this is
  standard `NSTextField` behavior reached through the public `label`
  property, not custom code in `ExplanationView.swift` itself (see
  Configuration).
