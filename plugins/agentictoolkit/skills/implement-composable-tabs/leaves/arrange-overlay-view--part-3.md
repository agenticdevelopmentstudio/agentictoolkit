<!-- leaf: implement-composable-tabs/arrange-overlay-view--part-3 · source: composable-tabs-arrange-overlay-view.md -->

# ComposableTabsArrangeOverlayView — continued (part 3)

## Design Decisions

**Decision**: Implement the scrim as a real `NSView` subview with its own
translucent layer background, rather than as an alpha applied to the pane's
existing content.
**Rationale**: An alpha applied to the content would still let clicks reach
it, defeating the point of arrange mode; a real covering view intercepts
pointer clicks, while still remaining a subview of the pane's backdrop so an
unhandled click can travel up the responder chain to select the pane.
**Approved**: pending

**Decision**: Dim toward `SemanticPalette.nsColor(.windowBackground)` at 72%
opacity rather than toward black.
**Rationale**: Dimming toward the window background keeps a light theme
light — the content should read as behind something, not as switched off,
which dimming toward black would suggest regardless of the active theme.
**Approved**: pending

**Decision**: Give the Done button no key equivalent, even though Return,
Enter, and Escape already leave arrange mode.
**Rationale**: None of those existing shortcuts is visible, and a toolbar
that shows every other action arrange mode supports owes the way out the
same billing; no single button can claim the default `\r` equivalent
window-wide, since every pane in the window carries one of these buttons and
a window with four default buttons would have none.
**Approved**: pending

**Decision**: Reuse `ComposableTabsMoveMenu` for the Move pull-down's items
instead of building the four-direction list, labels, icons, and enablement
rule inline in this view.
**Rationale**: The pane's gear menu needs the identical four directions,
labels, arrows, and legality rule; keeping that knowledge in one shared
object avoids a second place to miss when a direction is added or a name
changes.
**Approved**: pending
