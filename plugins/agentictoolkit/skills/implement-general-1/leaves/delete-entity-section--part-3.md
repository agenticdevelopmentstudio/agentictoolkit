<!-- leaf: implement-general-1/delete-entity-section--part-3 · source: delete-entity-section.md -->

# DeleteEntitySection — continued (part 3)

## Design Decisions

**Decision**: Collapse the section and stay neutral until disclosed; show
`apt-red` only when open.
**Rationale**: Least-astonishment — a closed settings pane should not shout its
most destructive control; the red accent is earned by the user opening it.
**Approved**: pending

**Decision**: Two phases — acknowledge, then type-to-confirm.
**Rationale**: The first phase communicates the blast radius (the
`childEntities` cascade); the second forces deliberate intent, so an accidental
double-click can never delete.
**Approved**: pending

**Decision**: Require an exact, case-sensitive, untrimmed match of the entity's
unique identifier.
**Rationale**: The identifier is unique and unambiguous; a fuzzy match would
weaken the guard, and guarding the empty-`confirmValue` case prevents arming
with no input at all.
**Approved**: pending

**Decision**: Lock the dialog while the delete is in flight and surface
failures inline.
**Rationale**: A destructive operation must not be abandoned half-way or fail
silently; keeping the dialog open on error lets the user retry without
re-typing.
**Approved**: pending

**Decision**: Keep the warning glyph `apt-gold` in both states.
**Rationale**: The glyph marks the zone as sensitive even while closed, without
recruiting the red destructive accent before the user commits.
**Approved**: pending

**Decision**: Support a reversible `actionVerb` variant (e.g. Archive) that
swaps every permanence-asserting phrase and the trigger glyph, while keeping
the Danger Zone's red palette unconditional regardless of `reversible`.
**Rationale**: A reversible action still belongs in the Danger Zone — it is
destructive-adjacent and deserves the same visual weight and two-phase confirm
ceremony — but its copy must never claim an irreversibility it doesn't have;
decoupling the palette from `reversible` keeps the section's visual language
consistent no matter which verb a caller passes.
**Approved**: pending
