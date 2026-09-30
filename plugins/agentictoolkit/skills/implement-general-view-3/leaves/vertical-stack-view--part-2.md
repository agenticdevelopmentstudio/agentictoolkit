<!-- leaf: implement-general-view-3/vertical-stack-view--part-2 · source: vertical-stack-view.md -->

# Vertical Stack View — continued (part 2)

**Rules** (cite as `implement-general-view-3/vertical-stack-view--part-2#<slug>`):

- `decision` SHOULD — init(frame frameRect: NSRect) discards its frameRect argument and always calls super.init(frame: .zero). Rationale: …

## Design Decisions

**Decision**: `init(frame frameRect: NSRect)` discards its `frameRect` argument and always calls `super.init(frame: .zero)`.
**Rationale**: `VerticalStackView` positions itself entirely through Auto Layout (`translatesAutoresizingMaskIntoConstraints = false` plus the activated edge-pinning constraints). The inherited frame-based initializer exists only so the type can still be constructed through it at all; the source ignores the caller-supplied rect rather than reconciling it with the Auto Layout constraints that take over immediately afterward. This is the same pattern used by the sibling `HorizontalStackView` and `DividerView`, so a port SHOULD keep discarding the caller's rect for parity with those siblings rather than reconcile it with the constraints that immediately override it (see **ignores-explicit-frame**).
**Approved**: pending

**Decision**: `stackView` is declared `public`, unlike the otherwise structurally identical `HorizontalStackView`, whose `stackView` property is `private`.
**Rationale**: Not explained in source comments. This is a genuine asymmetry between the two sibling wrappers: a caller of `VerticalStackView` can reach the internal `NSStackView` to reconfigure it (e.g. alignment or distribution) or to remove an arranged subview directly, while a caller of `HorizontalStackView` cannot. Recorded here rather than smoothed over, since the two types would otherwise read as interchangeable except for orientation.
**Approved**: pending

**Decision**: `addArrangedSubview(_:)` is the only mutation method the source defines; no counterpart method for removing an arranged subview is exposed (though, unlike `HorizontalStackView`, the public `stackView` property gives a caller an indirect path to one).
**Rationale**: Not explained in source comments. This is consistent with the ComposableSettingsWindow pattern of assembling a settings row or panel once, at construction time, rather than mutating it afterward. Recorded here as a known limitation of the public method surface rather than an intended, documented contract, since nothing in the source states it was deliberate.
**Approved**: pending
