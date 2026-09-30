<!-- leaf: implement-hub-domain-2/projects--part-6 · source: hub-domain-projects.md -->

# Hub Domain: Projects — continued (part 6)

## Design Decisions

**Decision**: The board's live wake (`live.ts`) carries no payload and no
change kind.
**Rationale**: The SSE connection is opened outside the tenant transaction
(a connection is held for minutes; a transaction cannot be), so the sending
side has no caller to authorize a row against and cannot honestly put one
on the wire. A wake with no data cannot leak any; the cost is an occasionally
unnecessary refetch, which is cheaper than a card appearing on a screen that
should not see it (file header).
**Approved**: pending

**Decision**: A card's board position (`rank`) and audit-trail pagination
cursor (`before`) are both opaque strings compared/split, never numeric
indices.
**Rationale**: An index-based move or page boundary races under concurrent
writers — two clients both computing "index 3" collide, while two clients
naming the same neighbor (a rank comparison) or the same composite cursor
both resolve consistently. The backend's `COLLATE "C"` rank column and its
composite `(before, beforeId)` keyset are the source of truth this client
mirrors exactly rather than re-deriving (`compareRank`, `keysetQuery` doc
comments).
**Approved**: pending

**Decision**: `Project.health` is derived by the backend from the newest
`ProjectStatusUpdate` and stored nowhere; this client never computes or
caches it.
**Rationale**: A health value that could drift from its source report would
let two panes disagree about a board's status. Making every write to
`status-updates.ts` responsible for invalidating the project keeps exactly
one place — the backend's derivation on read — as the single source of
truth (file header of `status-updates.ts`, `Project.health` doc comment).
**Approved**: pending

**Decision**: Triage membership is a nullable timestamp (`triagedAt`)
rather than a sixth `StatusCategory`, and there is no `decline` verb.
**Rationale**: "Waiting to be looked at" is a statement about whether a
board's columns apply yet, not a column itself, and the timestamp doubles
as the queue's own sort key (how long a card has waited). Declining is
`accept`ing into a `canceled`-category status, which leaves the card
findable and self-documenting, rather than adding a second verb that would
either delete the card or need its own undo path (`triage.ts` file header).
**Approved**: pending

**Decision**: `estimateScale`/`priorityScale` are advisory, never
validated against `WorkItem.estimate`/`.priority` on write.
**Rationale**: Freezing the set of numbers a board's picker offers into a
server-side constraint would mean every scale change (fibonacci → linear)
invalidates every card's existing estimate. Treating the scale as a
rendering hint only means a board can change its mind about presentation
without a data migration (`EstimateScale`/`PriorityScale` doc comments in
`wire.ts`).
**Approved**: pending

**Decision**: A template's stored body never carries board-specific ids
(`statusId`, `milestoneId`, `iterationId`, an assignee).
**Rationale**: A template belongs to the workspace and must be usable on
any board in it. Storing an id that exists on only one board would make the
template work only on the board it was authored from and fail — silently
or with a 400 — on every other (`TemplateCardSpec` doc comment in
`wire.ts`).
**Approved**: pending
