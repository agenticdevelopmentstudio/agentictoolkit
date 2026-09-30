<!-- leaf: implement-general-view-1/group-view--test-vectors · source: group-view.md -->

# GroupView

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| group-view-001 | card-surface | Construct `GroupView(withTitle: "Example")` | `cardView` is a `ThemedBox` with `fillRole == .elevatedSurface`, `strokeRole == nil`, and a 10pt layer corner radius |
| group-view-002 | card-view-access | Construct the component, then read `.cardView` from outside the type | Returns the same `ThemedBox` instance the view displays |
| group-view-003 | header-from-title | `GroupView(withTitle: "Example")` | The constructed header is a `HeaderView` whose `titleLabel.stringValue == "Example"` |
| group-view-004 | arbitrary-header-view | `GroupView(withHeaderView: someCustomNSView)` | `someCustomNSView` is the arranged subview above `cardView` in `outerStack` |
| group-view-005 | header-above-card | Construct the component | `outerStack.arrangedSubviews == [header, cardView]`, in that order |
| group-view-006 | header-card-spacing | Construct the component | `outerStack.spacing == 6.0` |
| group-view-007 | outer-stack-edge-pinning | Construct the component | Active constraints pin `outerStack`'s top/leading/trailing/bottom anchors to the view's corresponding anchors, each with constant `0` |
| group-view-008 | header-width-match | Construct the component | An active constraint equates the header's width to `outerStack.widthAnchor` |
| group-view-009 | card-width-match | Construct the component | An active constraint equates `cardView`'s width to `outerStack.widthAnchor` |
| group-view-010 | row-area-edge-pinning | Construct the component | Active constraints pin the internal row stack's top/leading/trailing/bottom anchors to `cardView`'s corresponding anchors, each with constant `0` |
| group-view-011 | row-stacking | Construct the component | The internal row stack's `orientation == .vertical`, `alignment == .leading`, `spacing == 0` |
| group-view-012 | autoresizing-mask-disabled | Construct the component | `translatesAutoresizingMaskIntoConstraints == false` on the view, `outerStack`, the row stack, the header, and `cardView` |
| group-view-013 | superview-width-match | Add the constructed view as a subview of a parent `NSView` | An active constraint equates the view's width to the parent's width |
| group-view-014 | width-match-skip-without-superview | Construct the component and call `viewDidMoveToSuperview()` without adding it to any parent | No width constraint is activated; no crash occurs from a nil superview |
| group-view-015 | row-append | `addSettingSubview(someView)` | `someView` is wrapped in a row that becomes the last row in the card; the number of rows in the card grows by one |
| group-view-016 | default-row-style | `addSettingSubview(someView)` with no `style` argument | The added row's `style == .row` |
| group-view-017 | added-row-width-match | `addSettingSubview(someView)` | An active constraint equates the new row's width to the row stack's width |
| group-view-018 | self-hiding-content-wiring | `addSettingSubview(aSelfHidingView)` where `aSelfHidingView` conforms to `SelfHidingSettingsView`, then invoke `aSelfHidingView.onVisibilityChange?()` | The wrapping row's `isHidden` re-syncs to `aSelfHidingView.isHidden` and separators are recomputed (observable via a subsequent row's separator state changing) |
| group-view-019 | separator-recompute-on-add | `addSettingSubview(viewA)` then `addSettingSubview(viewB)` | Recomputation after each call is observable — whether `viewB`'s row shows a separator reflects `viewA`'s row's hidden state at the time `viewB` was added |
| group-view-020 | separator-visibility | Add three `.row`-style, not-hidden views in sequence | The second and third rows' `showsSeparator == true`; only the first is `false` |
| group-view-021 | first-row-headless | `addSettingSubview(firstView)` as the only row | `firstView`'s row `showsSeparator == false` |
| group-view-022 | designated-initializer-requirement | Static check: inspect `GroupView.init?(coder:)` | Its body consists solely of a call to `fatalError`, so no code path returns a decoded instance |
| group-view-023 | main-actor-confinement | Static check: attempt to construct or mutate a `GroupView` from a non-isolated context | The compiler rejects the call at compile time under Swift's `@MainActor` isolation checking |
| group-view-024 | row-visibility-binding | Hide a row's wrapped content, then have the row resynchronize its visibility | The row's own hidden state becomes `true` |
| group-view-025 | row-visibility-at-construction | Construct a row whose wrapped content's hidden state is `true` | Immediately after construction returns, the row's own hidden state is `true` |
| group-view-026 | separator-collapse | Turn a row's separator visibility off (from on) | The row's divider becomes hidden; the space reserved for it becomes `0` |
| group-view-027 | separator-expansion | Turn a row's separator visibility on (from off) | The row's divider becomes visible; the space reserved for it becomes `1.0`pt |
| group-view-028 | separator-write-idempotency | Set a row's separator visibility to its own current value | Neither the divider's hidden state nor the reserved space's height changes as a result of this assignment |
| group-view-029 | separator-inset | Inspect a `.row`-style row's active constraints | The divider is inset 14pt from the row's leading edge; the divider reaches the row's trailing edge with no additional inset |
| group-view-030 | row-content-padding | Inspect a `.row`-style row's active constraints | The content's top edge is inset 9pt below the divider band; the content's bottom edge is inset 9pt from the row's bottom edge |
| group-view-031 | continuation-padding | Inspect a `.continuation`-style row's active constraints | The content's top edge has no inset from the divider band (`0`); the content's bottom edge is still inset 9pt from the row's bottom edge |
| group-view-032 | row-content-horizontal-inset | Inspect any row's active constraints | The content's leading edge is inset 14pt from the row's leading edge; the content's trailing edge is inset 14pt from the row's trailing edge |
| group-view-033 | row-designated-initializer-requirement | Static check: inspect the row type's `init?(coder:)` | Its body consists solely of a call to `fatalError`, so no code path returns a decoded instance |
