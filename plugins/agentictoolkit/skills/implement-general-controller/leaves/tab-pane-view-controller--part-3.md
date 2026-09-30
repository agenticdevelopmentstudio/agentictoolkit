<!-- leaf: implement-general-controller/tab-pane-view-controller--part-3 · source: tab-pane-view-controller.md -->

# TabPaneViewController — continued (part 3)

## Design Decisions

**Decision**: An unhighlighted card's drawn depth is clamped to at least `1` (`max(1, stackDepth)`) rather than trusting `stackDepth` directly, including its own default value of `0`.
**Rationale**: Per `applyDepth()`'s own doc comment, the `max` "is what keeps [selection and depth] from contradicting each other: a card that is not the selected one is never the card in front, whatever depth it was last told - including the initial zero, before any bar has said anything," because the hosting bar communicates selection and depth as two independent signals that can arrive in either order.
**Approved**: pending

**Decision**: A card with no window takes a new depth immediately and without animation, while a card in a window animates the move.
**Rationale**: Per `animatesDepthChanges`'s doc comment, "a card with no window is not on screen: there is nothing to watch move, and an animated constraint reads its old value until the animation ends," so measuring an off-screen card immediately after a depth change would read a stale, mid-animation value instead of the settled one.
**Approved**: pending

**Decision**: On a horizontal edge every card behind the front one recedes by exactly one step, while on a vertical edge the recession accumulates per depth up to `maxStackDepth`.
**Rationale**: Per `recession(atDepth:)`'s doc comment, a horizontal bar "lays its cards out along their long side" with no column to fan them down, so there is nothing for a deeper card to recede further into, whereas a vertical bar's cards overlap down a column and can visually "fan away" like a deck.
**Approved**: pending

**Decision**: The card's open-sided background stroke insets its three drawn sides by `0.5` pt but gives the workspace-facing side its half-point back while the card is in front.
**Rationale**: Per `strokeBounds()`'s doc comment, a `1` pt line otherwise straddles the view's own edge; while the front card's paint reaches out over the workspace's outline, "the fill and the two side strokes have to run all the way out through the overhang," or a visible seam would appear where the two surfaces are meant to read as one.
**Approved**: pending
