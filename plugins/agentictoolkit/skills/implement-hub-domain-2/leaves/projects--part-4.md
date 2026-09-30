<!-- leaf: implement-hub-domain-2/projects--part-4 · source: hub-domain-projects.md -->

# Hub Domain: Projects — continued (part 4)

**Rules** (cite as `implement-hub-domain-2/projects--part-4#<slug>`):

- `triage-membership-is-a-timestamp` MUST
- `triage-opt-in-via-create-flag` MUST
- `triage-no-decline-verb` MUST
- `triage-accept-idempotent-on-stamp` MUST
- `triage-list-for-project-vs-cross-board-partition` MUST
- `triage-cross-board-signpost-carries-owning-prefix` MUST
- `triage-cross-board-limit-is-clamped-and-exact` MUST
- `search-blank-query-short-circuits` MUST
- `search-query-trimmed-before-send` MUST
- `search-optional-params-omitted-when-unset` MUST
- `search-result-order-is-servers` MUST
- `search-echoed-limit-may-differ-from-requested` MUST
- `search-hit-defaults-snippet-and-rank` MUST
- `search-is-not-an-in-board-filter` MUST
- `activity-newest-first-keyset-paginated` MUST
- `activity-before-token-is-opaque-composite` MUST
- `activity-legacy-token-without-id-still-works` MUST
- `activity-next-before-full-page-heuristic` MUST
- `activity-writes-live-elsewhere` MUST
- `comment-list-oldest-first` MUST
- `comment-threading-one-level-deep` MUST
- `comment-orphan-promoted-not-dropped` MUST
- `comment-author-kind-unknown-falls-back-to-customer` MUST
- `comment-edit-gated-by-authorship` MUST
- `comment-remove-leaves-replies-standing` MUST
- `comment-add-omits-parent-id-for-top-level` MUST
- `comment-reaction-kind-is-a-named-constant` MUST
- `artifact-link-id-distinct-from-target-id` MUST
- `artifact-link-idempotent-per-triple` MUST
- `artifact-unresolvable-target-kept-as-null` MUST
- `artifact-list-server-order-preserved` MUST
- `artifact-attachable-limit-is-per-kind` MUST
- `artifact-kind-vocabulary-is-backend-owned` MUST
- `artifact-unlink-addresses-link-not-target` MUST

### triage.ts — `projectTriageApi`

- **triage-membership-is-a-timestamp**: A card MUST be considered "in
  triage" exactly when `WorkItem.triagedAt === null`; this is the entire
  membership rule — no separate status enum exists for it (file header,
  `WorkItem.triagedAt` doc comment).
- **triage-opt-in-via-create-flag**: A card MUST land in the triage queue
  only when `triage: true` is passed to `projectWorkItemsApi.create`; a
  board that never passes it has an unchanged, always-empty inbox (file
  header).
- **triage-no-decline-verb**: There MUST be no `decline` method or
  parameter; declining a card is expressed as `accept`ing it into a status
  in the `canceled` category — "leaves the card findable and says what
  happened to it" (file header, `TriageAcceptBody` doc comment in
  `wire.ts`).
- **triage-accept-idempotent-on-stamp**: `accept(ref, placement)` on an
  already-accepted card MUST apply the given placement but MUST leave the
  original `triagedAt` timestamp unchanged — "a double-click must not
  rewrite it" (`accept` doc comment).
- **triage-list-for-project-vs-cross-board-partition**: `listForProject`
  (one board, full cards) and `projectWorkItemsApi.listForProject` MUST
  partition a board's cards exactly — every card is in exactly one of the
  two lists unless `includeUntriaged` is passed to the latter (`listForProject`
  doc comment).
- **triage-cross-board-signpost-carries-owning-prefix**: `TriageHit.itemKey`
  MUST already be rendered against the OWNING board's prefix (or `""` when
  that board has none) — the cross-board caller has no prefix of its own to
  render it with (`TriageHit.itemKey` doc comment).
- **triage-cross-board-limit-is-clamped-and-exact**: `list()`'s returned
  `TriagePage.limit` MUST be the value the server actually applied (it
  clamps 1..200, default 50, rather than refusing), and `hasMore` MUST be
  computed by the server over-fetching one row, so it is exact (`list` doc
  comment).

### search.ts — `projectSearchApi`

- **search-blank-query-short-circuits**: `workItems(q)` MUST return
  `EMPTY_WORK_ITEM_SEARCH` without issuing a network call when `q.trim()` is
  empty — "an empty search box is the ordinary state of a search box, not
  an error to render" (`workItems` doc comment, confirmed by
  `hub-domain-projects-018`).
- **search-query-trimmed-before-send**: A query with leading/trailing
  whitespace MUST be trimmed before it is sent, so trailing whitespace is
  never a different search from its trimmed form (confirmed by
  `hub-domain-projects-019`).
- **search-optional-params-omitted-when-unset**: `workspace`/`limit` MUST be
  OMITTED from the query string when unset, never sent empty — `?workspace=`
  is fail-closed on the server, so an empty slug and no slug must not mean
  the same thing on the wire (`search.test.ts` header comment, confirmed by
  `hub-domain-projects-020`).
- **search-result-order-is-servers**: The returned page's `results` order
  MUST be the server's own (a keyed hit first, then rank, then recency);
  this client MUST NOT re-sort by `rank` — "a client holding one page cannot
  rank a result set it only partly has" (file header, confirmed by
  `hub-domain-projects-021`).
- **search-echoed-limit-may-differ-from-requested**: The returned
  `WorkItemSearchPage.limit` MUST be read from the server's response, never
  assumed equal to the requested `opts.limit` — the server clamps rather
  than refusing an out-of-range value (`WorkItemSearchOptions.limit` doc
  comment, confirmed by `hub-domain-projects-021`).
- **search-hit-defaults-snippet-and-rank**: `toWorkItemSearchHit` MUST
  default a missing `snippet` to `""` and a missing `rank` to `0`, never
  leave either `undefined` (`toWorkItemSearchHit`, confirmed by
  `hub-domain-projects-022`).
- **search-is-not-an-in-board-filter**: This client MUST NOT be used for an
  in-board text filter — a board's own list is already loaded and filtered
  client-side; this reaches across boards the caller has not loaded (file
  header).

### activity.ts — `projectActivityApi`

- **activity-newest-first-keyset-paginated**: `projectActivity`/
  `workItemActivity` MUST page newest-first using a `{ limit?, before? }`
  keyset (file header).
- **activity-before-token-is-opaque-composite**: The `before` cursor MUST be
  treated as opaque by callers and, internally, MUST be split on the LAST
  `"|"` into `(beforeTs, beforeId)` for the backend's composite keyset, so
  millisecond-tied rows never straddle a page boundary (`keysetQuery`,
  confirmed by `hub-domain-projects-023`).
- **activity-legacy-token-without-id-still-works**: A `before` token with no
  `"|"` (a legacy token) MUST still send `before` alone, with no `beforeId`
  (`keysetQuery` inline comment).
- **activity-next-before-full-page-heuristic**: `nextBefore` MUST be the
  last row's composite `"<createdAt>|<id>"` token when the returned page's
  length equals the requested `limit` (implying more may exist), and `null`
  otherwise (a short/last page, or no `limit` given at all) (`fetchActivityPage`,
  confirmed by `hub-domain-projects-023`/`024`).
- **activity-writes-live-elsewhere**: Writing a comment MUST NOT go through
  this client — `./comments` owns the write, and the resulting
  `comment.added`/`.edited`/`.deleted` action still appears in this trail
  because the backend writes both in one transaction (file header).

### comments.ts — `projectCommentsApi` / `threadOf`

- **comment-list-oldest-first**: `list(workItemId)` MUST return comments in
  the server's oldest-first order and MUST NOT re-sort them — "a
  conversation only reads correctly forward" (`list` doc comment, confirmed
  by `hub-domain-projects-025`).
- **comment-threading-one-level-deep**: `threadOf` MUST group a flat,
  oldest-first list into root/`replies` pairs with no recursion, because the
  backend already re-parents a reply-to-a-reply onto the root (`threadOf`
  doc comment, confirmed by `hub-domain-projects-026`).
- **comment-orphan-promoted-not-dropped**: `threadOf` MUST promote a reply
  whose `parentId` is not present in the list to a root of its own, appended
  after the real roots, rather than dropping it — "the parent was removed
  while this reply stands" (`threadOf` doc comment, confirmed by
  `hub-domain-projects-027`).
- **comment-author-kind-unknown-falls-back-to-customer**: `toProjectComment`
  MUST map an unrecognized `authorKind` string to `"customer"` via `narrow`
  — "the reading that claims the least", never a synthetic value that could
  pose as an agent (`CommentAuthorKind` doc comment, confirmed by
  `hub-domain-projects-028`).
- **comment-edit-gated-by-authorship**: `edit(commentId, body)` MUST be
  refused by the backend for anyone but the comment's author — "an editing
  verb on the project does not let a moderator put words in someone's
  mouth" (`edit` doc comment).
- **comment-remove-leaves-replies-standing**: `remove(commentId)` MUST leave
  any replies to it in place — "a thread does not lose its answers along
  with its question" (`remove` doc comment).
- **comment-add-omits-parent-id-for-top-level**: `add(workItemId, body)`
  with no `parentId` argument MUST send a body with no `parentId` key at
  all, never `parentId: undefined` serialized (`add`, confirmed by
  `hub-domain-projects-025`).
- **comment-reaction-kind-is-a-named-constant**: `COMMENT_REACTION_KIND`
  (`"project.comments"`) MUST be the single spelling every reaction call
  site imports, never a literal restated at each site — comments are
  reacted to through the shared polymorphic `(targetKind, targetId)`
  reaction store, not a comments-owned endpoint (`COMMENT_REACTION_KIND` doc
  comment).

### artifacts.ts — `projectArtifactsApi`

- **artifact-link-id-distinct-from-target-id**: `ProjectArtifact.id` MUST
  identify the LINK (what `unlink` addresses), never the target — the same
  target can be linked twice (once `ingested`, once `produced`), so the
  target id alone does not identify a row (`ProjectArtifact.id` doc
  comment, confirmed by `hub-domain-projects-029`).
- **artifact-link-idempotent-per-triple**: `link(projectId, {direction,
  targetKind, targetId})` MUST be idempotent per `(direction, kind, id)` —
  re-linking the same triple MUST return the existing row rather than create
  a duplicate — "a double-click cannot litter the list" (`link` doc
  comment).
- **artifact-unresolvable-target-kept-as-null**: A `ProjectArtifact` whose
  target no longer resolves MUST be returned with `target: null` and its
  `targetKind`/`targetId` intact, never dropped from the list — "the link is
  still a fact about the project" (`ProjectArtifact.target` doc comment,
  confirmed by `hub-domain-projects-029`).
- **artifact-list-server-order-preserved**: `list(projectId)` MUST preserve
  the server's (newest-first) order, never re-sort — a client re-sort "would
  silently disagree with the pagination the endpoint is built for" (`list`
  test comment, confirmed by `hub-domain-projects-029`).
- **artifact-attachable-limit-is-per-kind**: `attachable`'s `limit` option
  MUST be understood as per-KIND, not per-response, so one kind cannot
  crowd the others out of the picker (`attachable` doc comment).
- **artifact-kind-vocabulary-is-backend-owned**: This client MUST NOT
  define or hard-code a list of valid `targetKind` values — `attachable()`
  is how a picker discovers what a project can hold, and a deployed client
  picks up a newly added kind on its next request without a code change
  (file header).
- **artifact-unlink-addresses-link-not-target**: `unlink(projectId,
  artifactId)` MUST address the LINK's id; the target itself is untouched —
  "this removes the project's claim on it, never the thing" (`unlink` doc
  comment, confirmed by `hub-domain-projects-030`).

