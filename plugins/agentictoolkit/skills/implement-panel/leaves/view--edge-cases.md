<!-- leaf: implement-panel/view--edge-cases · source: panel-view.md -->

# PanelView

## Edge Cases

- **Null/empty input**: `group` (`GroupView`, `addGroup(_:)`) and `title`
  (`String`, `addHeading(_:caption:)`) are non-optional, typed parameters;
  Swift's type system rules out `nil` for either, so no nil-handling path is
  needed. `caption` (`String?`) defaults to `nil`; an explicit empty
  string (`caption: ""`) is passed straight through to
  `PanelHeadingView(title:caption:)`, which — per that recipe — still
  constructs a caption view whose label renders empty.
- **Boundary values**: Not applicable in the numeric sense — `PanelView`
  exposes no caller-configurable numeric range of its own; its only numeric
  behavior comes from the fixed `SettingsLayout` constants (20pt panel
  inset, 20pt group spacing, the fixed `1.5×` heading-gap multiplier).
- **Concurrent access**: Not applicable — the class is `@MainActor` (see
  `main-actor-confinement`), so `addGroup`, `addHeading`, and every
  constraint activation are serialized on the main actor.
- **Error states**: Not applicable — every operation in `PanelView.swift`
  (adding a group, adding a heading, repainting the background) is a
  synchronous, non-throwing call; no `try`, `Result`, or error-producing API
  appears in source.
- **Offline/disconnected state**: Not applicable — the component performs no
  networking of its own.
- **`addHeading` called on an empty panel**: Per
  **empty-stack-spacing-skip**, the first heading in a panel sits with no
  extra gap above it, because there is no prior arranged subview at that
  point and the spacing-adjustment guard simply does not run — no fallback
  spacing is applied in its place.
- **The view's own frame is unreachable by construction**: Per the design
  decision on frame handling (see Design Decisions), any `NSRect` passed to
  `PanelView(frame:)` — including a non-zero one supplied directly by a
  caller who bypasses the `init()` convenience initializer — is discarded;
  the view always begins at `.zero` regardless: `super.init(frame: .zero)`
  never references its own `frameRect` parameter.
- **Re-adding an already-parented `GroupView`**: AppKit's
  `addArrangedSubview` always detaches a view from its previous superview
  before adding it to a new one; adding the same `GroupView` instance to a
  second `PanelView` (or a second time to the same one) silently removes it
  from its first location. `PanelView.swift` contains no guard against this
  — the same source-traceable consequence the sibling `GroupView` recipe
  documents for `addSettingSubview` (see **group-arranged-subview-append**).
- **A superview taller than the panel's content**: Because
  **bottom-inset-inequality** constrains the internal stack view's bottom
  with an inequality rather than an equality, a `PanelView` given more
  height than its groups require leaves visible, unpainted-by-content slack
  between the last arranged subview and the panel's bottom edge, rather than
  stretching the stack to fill it: no equality or centering constraint
  exists to distribute the extra space.
