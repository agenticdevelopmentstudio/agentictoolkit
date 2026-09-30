<!-- leaf: implement-general-view-2/path-view--edge-cases · source: path-view.md -->

# PathView

**Rules** (cite as `implement-general-view-2/path-view--edge-cases#<slug>`):

- `null-empty-input` MUST — path is a non-optional String constructor parameter, so Swift's type system rules out nil. An empty string ("") renders …
- `empty-non-nil-caption` MUST — caption is String?, and caption.map { … } treats Optional("") as present, not absent. Passing caption: "" produces the …
- `caption-alone-exceeds-the-available-width` MUST — byTruncatingMiddle truncates the whole rendered string ("<caption>: <path>") uniformly, not the path portion …
- `very-long-path-with-no-width-constraint` MUST — with both horizontal priorities set to .defaultLow and no minimum width declared, a superview or stack view that …

## Edge Cases

- **Null/empty input**: `path` is a non-optional `String` constructor
  parameter, so Swift's type system rules out `nil`. An empty string (`""`)
  renders an empty (or, with a caption, `"<caption>: "`-only) label with no
  guard against it in source (MUST, per `retains-untruncated-path` and
  `prefixes-optional-caption`).
- **Empty, non-nil caption**: `caption` is `String?`, and `caption.map { … }`
  treats `Optional("")` as present, not absent. Passing `caption: ""`
  produces the displayed and stored string `": <path>"` — a leading
  colon-space with nothing before it — since the source guards only against
  `caption == nil`, not `caption == ""` (MAY: this is observed behavior of
  `caption.map`'s emptiness-blind check, not a MUST asserted by
  `prefixes-optional-caption`, which only distinguishes nil from non-nil).
- **Boundary values**: Not applicable in the numeric-input sense —
  `PathView`'s inputs are caller-supplied strings; it has no length limit,
  minimum, or maximum for a numeric boundary to test.
- **Concurrent access**: Not applicable — the class is `@MainActor`-isolated;
  the Swift compiler rejects construction or mutation of `self`/`label` from
  off the main actor, so there is no concurrent-access surface to define
  behavior for.
- **Error states (dependency/network failure)**: Not applicable — the source
  performs no I/O, network call, or dependency lookup of any kind; it does
  not validate that `path` refers to anything that exists on disk.
- **Offline/disconnected state**: Not applicable — `PathView` performs no
  network operation of its own.
- **Caption alone exceeds the available width**: `byTruncatingMiddle`
  truncates the whole rendered string (`"<caption>: <path>"`) uniformly, not
  the path portion specifically. The source's doc comment describes the
  caption as sitting at "the head, which middle truncation never eats" — true
  whenever there is enough width to preserve some of the head, but at a
  width narrower than the caption text itself, `byTruncatingMiddle` will
  begin eliding characters from within the caption too, since no code in
  `PathView.swift` treats the caption boundary specially (MAY: this is
  observed fallthrough behavior of `byTruncatingMiddle` at extreme widths,
  not a MUST that `truncates-middle` itself asserts — the requirement only
  names which `lineBreakMode` is set).
- **Very long path with no width constraint**: with both horizontal
  priorities set to `.defaultLow` and no minimum width declared, a superview
  or stack view that constrains the view's width forces the label to
  truncate further; if nothing constrains the view's width, layout falls
  back to whatever the container gives it, since neither the label nor the
  view expresses a preferred or maximum width of its own in source (MUST,
  per `yields-width-to-container`).
