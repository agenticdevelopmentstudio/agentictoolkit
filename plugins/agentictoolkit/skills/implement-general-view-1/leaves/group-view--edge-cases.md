<!-- leaf: implement-general-view-1/group-view--edge-cases · source: group-view.md -->

# GroupView

**Rules** (cite as `implement-general-view-1/group-view--edge-cases#<slug>`):

- `out-nil-either-initializer-needs-nil-handling` MUST — Null/empty input: title (String, init(withTitle:)) and header (NSView, init(withHeaderView:)) are non-optional, typed …
- `remain-layout-regardless-per-header-from-title` MUST — Empty title string (""): header-from-title still runs unconditionally, constructing a HeaderView whose label renders …
- `strip-beneath-caption-per-row-area-edge` MUST — Zero rows added: rowStack is pinned to cardView's edges with pinToEdges, so with no arranged subviews cardView's size …
- `twice-precondition-callers-not-add-same-view-instance` MUST — Passing the same content view instance to addSettingSubview twice: Precondition — callers MUST NOT add the same view …
- `widths-ever-differ-level-consequence-source-groupview` MUST — Moving a GroupView between two different superviews: superview-width- match activates a fresh self.widthAnchor == …

## Edge Cases

- Null/empty input: `title` (`String`, `init(withTitle:)`) and `header`
  (`NSView`, `init(withHeaderView:)`) are non-optional, typed constructor
  parameters; Swift's type system rules out `nil` for either (MUST — the
  initializer needs no nil-handling path because neither parameter can be
  `nil`).
- Empty `title` string (`""`): `header-from-title` still runs
  unconditionally, constructing a `HeaderView` whose label renders empty; the
  caption band and its 6pt spacing from the card remain in layout regardless
  (MUST, per `header-from-title` and `header-card-spacing` — the source has
  no guard against an empty string).
- Boundary values: Not applicable — `GroupView`'s only numeric behavior comes
  from the fixed `SettingsLayout` constants (10pt corner radius, 6pt caption
  spacing, 14pt horizontal inset, 9pt vertical inset, 1pt divider
  thickness); it exposes no caller-configurable numeric range of its own.
- Concurrent access: Not applicable — the class is `@MainActor` (see
  `main-actor-confinement`), so `addSettingSubview`, `updateSeparators`, and
  every constraint activation are serialized on the main actor.
- Error states: Not applicable — every operation in `GroupView.swift`
  (adding a row, updating separators, syncing visibility) is a synchronous,
  non-throwing call; no `try`, `Result`, or error-producing API appears in
  source.
- Offline/disconnected: Not applicable — the component performs no
  networking of its own.
- Zero rows added: `rowStack` is pinned to `cardView`'s edges with
  `pinToEdges`, so with no arranged subviews `cardView`'s size is exactly
  `rowStack`'s size; nothing in `GroupView.swift` enforces a nonzero row
  count or a minimum card height, so an unpopulated group renders as an
  empty rounded, elevated-surface strip beneath its caption (MUST, per
  `row-area-edge-pinning` — no minimum-height constraint exists anywhere in
  source).
- All rows hidden simultaneously: `NSStackView` omits layout space for
  hidden arranged subviews, and separator recomputation only ever toggles a
  row's own separator visibility on rows still present in `rows` — nothing
  in `GroupView.swift` ever sets `cardView.isHidden`. The card itself
  remains present, still painted with its elevated-surface fill and rounded
  corners (see `card-surface`), collapsed to near-zero height, rather than
  disappearing. Whether a fully collapsed card should hide itself is an open
  decision the source does not make — see Design Decisions.
- Passing the same content view instance to `addSettingSubview` twice:
  Precondition — callers MUST NOT add the same view instance to a
  `GroupView` more than once. AppKit's `addSubview(_:)` always detaches a
  view from its previous superview before adding it to a new one, so a
  second call wrapping the same instance in a new row silently removes it
  from the first row, leaving that row's own content constraints referencing
  a view no longer inside its subtree — Auto Layout then has no common
  ancestor left to satisfy them. `GroupView.swift` contains no guard against
  this; honoring the precondition is the caller's responsibility, not a
  behavior `row-append` is required to produce.
- Moving a `GroupView` between two different superviews: `superview-width-
  match` activates a fresh `self.widthAnchor == parent.widthAnchor`
  constraint on every call to `viewDidMoveToSuperview`, without deactivating
  any constraint created for a previous superview. Re-parenting the same
  `GroupView` instance leaves both width constraints active simultaneously,
  which conflicts if the two superviews' widths ever differ (MUST-level
  consequence of source; `GroupView.swift` never stores or deactivates a
  previously created width constraint — see Design Decisions).
