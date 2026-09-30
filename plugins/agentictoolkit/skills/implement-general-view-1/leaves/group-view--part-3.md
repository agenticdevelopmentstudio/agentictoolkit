<!-- leaf: implement-general-view-1/group-view--part-3 · source: group-view.md -->

# GroupView — continued (part 3)

## Design Decisions

**Decision**: Place the caption outside `cardView`, as a sibling in
`outerStack`, rather than as the card's own first row.
**Rationale**: per the source's own doc comment, "a title as the card's
first row reads as just another setting" — the caption sits outside the
card because that is what separates a group's name from its contents at a
glance.
**Approved**: pending

**Decision**: `addSettingSubview` takes an explicit `style: CardRowStyle`
parameter rather than inferring row style from the added view's type.
**Rationale**: per the source's own doc comment, inferring style from type
"was inferred from the view's type once — prose was assumed to annotate the
row above it — which turned a list of plugin load failures into an
unseparated run of jammed-together lines, and sliced one model description
into six divided rows." What a view means in a card is not knowable from
what class it is, so the caller states it.
**Approved**: pending

**Decision**: `viewDidMoveToSuperview` activates a width constraint
equating `GroupView` to its new superview, rather than giving `GroupView` an
intrinsic or fixed width.
**Rationale**: per the source's own comment, each group fills its parent
stack's width "so that any child that wants to span the full panel (sliders
with trailing captions, dividers, etc.) actually can," while items inside
the group still control their own horizontal layout via content-hugging
priorities.
**Approved**: pending

**Decision**: Drive `updateSeparators()` from `SelfHidingSettingsView`'s
`onVisibilityChange` callback, rather than observing `isHidden` via KVO or
polling it.
**Rationale**: per the source's own doc comment, `GroupView` "listens so the
card can close up around a row that has hidden itself — its padding and the
hairline above it go with it," because an `NSStackView` collapses a hidden
arranged subview but the row's own padding cell is not hidden just because
its content is; without the callback, a dismissed hint leaves an empty band
and a stray divider behind.
**Approved**: pending

**Decision**: `viewDidMoveToSuperview` neither stores nor deactivates a
width constraint from a previous superview before activating a new one.
**Rationale**: acceptable as shipped because every known call site adds a
`GroupView` to exactly one stable superview once and never re-parents it
afterward; documented here as the source-traceable technical debt that
surfaces specifically in the re-parenting scenario recorded under Edge
Cases, should a future caller move a `GroupView` between superviews.
**Approved**: pending

**Decision**: When every row in a `GroupView` is hidden, `cardView` is left
visible — collapsed to near-zero height — rather than being hidden or
removed along with its rows.
**Rationale**: `GroupView.swift` never sets `cardView.isHidden`;
`NSStackView` omits layout space for hidden arranged subviews, so the row
area's height collapses to zero, but no code path in source extends that
collapse to `cardView`'s own visibility. This is documented as undecided
behavior, not a chosen one — the source simply has no check either way, so
a caller sees an empty elevated-surface strip rather than nothing (see Edge
Cases).
**Approved**: pending
