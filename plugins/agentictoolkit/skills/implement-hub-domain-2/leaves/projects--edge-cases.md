<!-- leaf: implement-hub-domain-2/projects--edge-cases · source: hub-domain-projects.md -->

# Hub Domain: Projects

**Rules** (cite as `implement-hub-domain-2/projects--edge-cases#<slug>`):

- `null-empty-input` MUST — A blank or whitespace-only search query is answered with EMPTY_WORK_ITEM_SEARCH without a network call …
- `boundary-malformed-values` MUST — A validateKeyPrefix input of exactly 2 or 8 characters MUST be accepted; 1 or 9 characters MUST be rejected …

## Edge Cases

- **Null/empty input**: A blank or whitespace-only search query is answered
  with `EMPTY_WORK_ITEM_SEARCH` without a network call
  (search-blank-query-short-circuits). An empty `validateKeyPrefix` input is
  refused with `"A key prefix is required."`, never treated as "clear the
  prefix" (project-key-prefix-empty-refused-not-cleared). A `Milestone` with
  `counts: null` MUST render as "unknown", never as a zeroed progress bar
  (milestone-progress-null-when-counts-absent).
- **Boundary/malformed values**: A `validateKeyPrefix` input of exactly 2 or
  8 characters MUST be accepted; 1 or 9 characters MUST be rejected
  (hub-domain-projects-006/008). A `WorkItemMoveTarget` naming neither
  neighbor, or explicitly nulling both `afterId` and `beforeId`, is a 400 —
  "nothing above and nothing below... is never the move anyone meant"
  (work-item-move-by-named-neighbor). A `before` activity cursor with no
  `"|"` separator (a legacy token) is still accepted, sent as `before` alone
  (activity-legacy-token-without-id-still-works).
- **Concurrent access**: Two closely-timed `link()` calls for the same
  `(direction, targetKind, targetId)` triple — the second returns the
  existing row rather than creating a duplicate
  (artifact-link-idempotent-per-triple). Two closely-timed `accept()` calls
  on the same card — the second applies its placement but does not disturb
  the original `triagedAt` stamp (triage-accept-idempotent-on-stamp). Two
  clients moving cards with `{afterId: X}` naming the SAME neighbor both
  land beside it, deliberately avoiding the race an index-based move would
  create (`WorkItemMoveTarget` doc comment: "two clients sending \"index 3\"
  race, whereas two clients naming the same neighbour both land beside it").
  A pending coalesced wake outlived by an unmounting subscriber is dropped
  rather than firing against a gone component
  (live-unsubscribe-during-pending-wake-is-silent,
  live-last-unsubscribe-drops-pending-timer).
- **Error states**: Every `get(id)` across every client
  (`projectsApi`/`projectIterationsApi`/`projectProgramsApi`/
  `projectWorkItemsApi`) resolves to `null` on a thrown 404 rather than
  rethrowing (project-get-null-on-not-found and its analogues per file). A
  `projectStatusUpdatesApi.update` by anyone but the report's author is a
  403 (status-update-edit-gated-by-authorship); a `projectCommentsApi.edit`
  by anyone but the comment's author is likewise refused
  (comment-edit-gated-by-authorship).
- **Ownership / scoping mismatches**: A `Milestone` id from a project other
  than the one addressed is a 404, never a cross-board edit
  (milestone-owned-by-project). A `Program` of another workspace named as a
  project's `programId` is a 400 (`ProjectPatchBody.programId` doc comment
  in `wire.ts`). An `Iteration`'s owner must match the committing card's
  project's owner (`Iteration.ownerKind`/`ownerId` doc comment).
