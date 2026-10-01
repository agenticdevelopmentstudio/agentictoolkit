---
id: 6263d5af-d0c7-456b-903a-762581ae5dbb
title: Projects
domain: agentictoolkit://cookbook/adh/hub/projects
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Projects (work-tracking) domain logic: boards, cards, iterations, programs,
  milestones, status updates, templates, triage, cross-board search, activity, comments,
  and artifacts, plus a payload-less live-change wake, wired to a typed project data
  surface.'
platforms:
- typescript
- web
tags:
- hub
- projects
- work-items
- kanban
- iterations
- programs
- milestones
- triage
- sse
depends-on: []
related:
- agentictoolkit://cookbook/adh/hub/ecosystems/ecosystems
references:
- packages/web/packages/data/src/projects/activity.ts (agentictoolkit)
- packages/web/packages/data/src/projects/artifacts.ts (agentictoolkit)
- packages/web/packages/data/src/projects/comments.ts (agentictoolkit)
- packages/web/packages/data/src/projects/index.ts (agentictoolkit)
- packages/web/packages/data/src/projects/iterations.ts (agentictoolkit)
- packages/web/packages/data/src/projects/live.ts (agentictoolkit)
- packages/web/packages/data/src/projects/milestones.ts (agentictoolkit)
- packages/web/packages/data/src/projects/programs.ts (agentictoolkit)
- packages/web/packages/data/src/projects/projects.ts (agentictoolkit)
- packages/web/packages/data/src/projects/search.ts (agentictoolkit)
- packages/web/packages/data/src/projects/status-updates.ts (agentictoolkit)
- packages/web/packages/data/src/projects/templates.ts (agentictoolkit)
- packages/web/packages/data/src/projects/triage.ts (agentictoolkit)
- packages/web/packages/data/src/projects/wire.ts (agentictoolkit)
- packages/web/packages/data/src/projects/work-items.ts (agentictoolkit)
- packages/web/packages/data/src/http.ts (agentictoolkit)
- packages/web/packages/data/src/client-helpers.ts (agentictoolkit)
- packages/web/packages/data/src/stream/index.ts (agentictoolkit)
- packages/web/packages/data/src/projects/__tests__/projects.test.ts (agentictoolkit)
- packages/web/packages/data/src/projects/__tests__/search.test.ts (agentictoolkit)
- packages/web/packages/data/src/projects/__tests__/live.test.ts (agentictoolkit)
- packages/web/packages/data/src/projects/__tests__/programs-milestones-health.test.ts
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Projects

## Overview

This is the Projects ("work-tracking") domain logic of the hub: the logic
that models a *board* (a `Project`), the *cards* on it (a `WorkItem`), and
the surrounding scaffolding a board needs to run — columns
(`ProjectStatus`), participants, saved views, labels, plan points
(`Milestone`), cross-board time-boxes (`Iteration`), cross-board roll-ups
(`Program`), signed health reports (`ProjectStatusUpdate`), repeatable shapes
(`Template`), an intake inbox, a cross-board search, an append-only audit
trail, a threaded conversation, polymorphic pointers to content elsewhere in
the platform, and a payload-less live wake. This recipe has one reference
implementation today (see Platform Notes); the responsibilities below are
grouped by role rather than by source file:

- **Boards** — root board CRUD, plus `statuses`/`participants`/`savedViews`
  sub-groupings, `labels`, and a key-prefix validator with a client-side
  mirror of the backend's work-item-key shape rule.
- **Cards** — card CRUD, `move`, `children`, `dependencies`, `relations`,
  field values, and a byte-order comparator for a card's opaque
  fractional-index rank.
- **Iterations** — the workspace-owned time-box a card is committed to.
- **Programs** — the workspace-owned roll-up of several boards.
- **Milestones** — the board-owned plan points and their derived,
  `canceled`-excluded progress.
- **Status updates** — the signed reports `Project.health` is derived from.
- **Templates** — the "stamp this shape out again" workspace templates and
  helpers that read a card count or narrow a stored body to its kind.
- **Triage** — the intake queue a card sits in while `triagedAt` is null.
- **Search** — cross-board full-text card search.
- **Activity** — the newest-first, keyset-paginated audit trail.
- **Comments** — the one-level-deep card conversation.
- **Artifacts** — the polymorphic ingested/produced content links.
- **Live wake** — the refcounted, coalesced, payload-less "something
  changed" signal and the hook that consumes it.
- **Wire shapes** — the backend row and request-body shapes every mapper and
  call site above reads and writes; type-only.
- **Public surface** — every grouping above, plus the closed-set
  vocabularies (`StatusCategory`, `RelationKind`, `EstimateScale`,
  `PriorityScale`, `IterationState`, `ProjectHealth`, `TemplateKind`,
  `MilestoneCounts`, `WorkItemMoveTarget`, `TriageAcceptBody`) a consumer must
  be able to name in a signature without already holding a row.

Every grouping shares one shape: a mapper from a wire row type to a public
entity, a route constant, and a plain object of asynchronous methods over an
authenticated request helper. Two cross-cutting conventions recur throughout
and are stated once here rather than at each site: a shared "compact" helper
drops only `undefined` keys and preserves an explicit `null`, which is what
lets a partial update clear a column (`assigneeId: null`, `archivedAt:
null`) while an omitted key leaves it untouched; and every single-item fetch
resolves to `null` on a thrown 404 rather than rethrowing, so "not found" is
a value, not a `catch` a caller must write everywhere.

## Behavioral Requirements

### Boards

- **project-list-workspace-scoping**: Listing boards scoped to a workspace
  MUST pin the result to that workspace's owning principal; omitted, the
  caller sees every board their reach admits ("`workspace` pins list/create
  to the WORKSPACE'S owning principal").
- **project-list-sorted-by-name**: Listing boards MUST return them sorted by
  `name` using locale-aware comparison, never in the server's raw order
  (confirmed by `hub-domain-projects-001`).
- **project-get-null-on-not-found**: Fetching a single board by id MUST
  resolve to `null` when the backend reports it missing (404), never
  rethrow — "the UI contract is null-for-missing".
- **project-subject-lookup-first-row**: Looking up a board by its subject
  (kind, id) MUST query for that subject and return the FIRST row mapped, or
  `null` when the array is empty — the auto-provisioned subject board of one
  ecosystem or persona.
- **project-create-compacts-optionals**: Creating a board MUST send `name`
  plus only the defined optionals of `description`/`color`, omitting
  optionals that were never set.
- **project-update-preserves-explicit-null**: Updating a board MUST send an
  explicit `archivedAt: null` (un-archive) through rather than stripping it,
  while an unset field (e.g. an untouched `description`) is dropped
  (confirmed by `hub-domain-projects-004`).
- **project-key-prefix-shape**: Validating a key prefix MUST trim and
  upper-case the input, return `"A key prefix is required."` for an empty
  value, `"Use 2-8 characters: a letter, then letters or digits."` for a
  value not matching the pattern "one letter, then 1-7 more letters or
  digits", and `null` when the (trimmed, upper-cased) value is valid
  (confirmed by `hub-domain-projects-006`/`007`/`008`).
- **project-key-prefix-empty-refused-not-cleared**: An empty prefix MUST be
  refused by validation rather than treated as "clear the prefix" — "there
  is no way to un-name a project's cards once they are named".
- **project-item-noun-defaults**: A board MUST default its singular/plural
  item noun to the fixed pair `"work item"`/`"work items"` when the backend
  sends an empty or absent value, never derive a plural from a singular
  ("no client can turn \"story\" into \"stories\" reliably").
- **project-estimate-scale-default**: A board MUST default a missing
  estimate scale to `"none"` — meaning "this board does not estimate" —
  never leave it unset.
- **project-priority-scale-default**: A board MUST default a missing
  priority scale to `"standard"`, the value a backend that predates the
  column implies, matching that backend's own default.
- **project-lead-both-or-neither**: A board's lead MUST be read as a
  (kind, id) pair — both set or both `null` — treating a row carrying only
  one half as unset, because "the backend cannot write one".
- **project-health-derived-not-cached**: A board's health and its
  last-updated timestamp MUST be read exactly as the backend sends them
  (derived from the newest live status update, `null` = "nobody has
  reported yet") and this component MUST NOT compute or cache a health
  value itself.
- **project-statuses-server-ordered**: Listing a board's statuses MUST
  return the rows in the server's order (by position), never re-sorted.
- **project-labels-is-a-suggestion-list**: Reading a board's labels MUST be
  read-only and MUST be treated as a non-exhaustive vocabulary — "a card may
  carry a label that is not in it yet" — never as a closed enum a form
  validates against.
- **project-participant-remove-addressing**: Removing a participant MUST
  address the row by the participant's `(kind, participantId)` pair — the
  addressed identifier is the actor's id, NOT the participant row's own id,
  and the kind is a required parameter (confirmed by
  `hub-domain-projects-002`).
- **project-saved-views-are-shared**: A saved view MUST be treated as shared
  across every caller who can read the board — "there are no private
  views" — and its `config` MUST be passed through opaquely, decoded only by
  the feature package that owns the filter vocabulary, never interpreted
  here.

### Cards

- **work-item-list-excludes-untriaged-by-default**: Listing a board's cards
  MUST return only ACCEPTED cards (a non-null triage timestamp) unless an
  "include untriaged" option is passed, because an untriaged card "has had
  no column decision made about it" and showing it would assert a placement
  nobody made.
- **work-item-list-rank-ordered**: Listing a board's cards, and listing a
  card's children, MUST return cards in rank order as the server sends
  them, never re-sorted.
- **work-item-rank-is-opaque-byte-order**: Comparing two rank strings MUST
  use a plain less-than/greater-than comparison (never subtraction, never
  locale-aware comparison), because the backend's rank column is stored in
  byte order and the rank alphabet's characters sort in that same order
  (confirmed by `hub-domain-projects-010`/`011`: byte-order comparison
  places `"aZ"` before `"az"`, while locale-aware comparison places `"aZ"`
  after `"az"`).
- **work-item-update-clears-via-explicit-null**: Updating a card MUST send
  an explicit `null` for assignee kind/id, due date, parent id, iteration
  id, milestone id, or estimate (never stripped), while an unset field
  (e.g. an untouched title) IS stripped (confirmed by
  `hub-domain-projects-012`).
- **work-item-move-by-named-neighbor**: Moving a card MUST send a move
  target naming a sibling by id/key, never an index — the five legal shapes
  are "after this id", "before this id", "after this id and before that id"
  (between, already-ordered), "after nothing" (to the top), and "before
  nothing" (to the bottom); naming neither, or nulling both, is a 400.
- **work-item-move-null-survives-compact**: Moving a card MUST let an
  explicit "after nothing" (`{afterId: null}`) reach the request body —
  distinct from an omitted `afterId`, which means "I didn't say" —
  confirmed by `hub-domain-projects-013` (`{afterId: null, beforeId:
  undefined}` sends `{"afterId":null}`).
- **work-item-move-returns-moved-card-only**: Moving a card MUST return only
  the moved card, carrying its new rank; no sibling in the response
  changes, so a caller re-sorts the list it already holds rather than
  refetching.
- **work-item-key-derivation**: A card's item key MUST default to `""` when
  the backend omits it (an older backend, or a board with no assigned
  prefix yet), and MUST be treated as read-only — never sent back on an
  update (confirmed by `hub-domain-projects-014`/`015`).
- **work-item-estimate-null-distinct-from-zero**: A card's estimate MUST
  distinguish `null` (un-estimated) from `0` (estimated at zero); an update
  with `estimate: null` un-estimates the card.
- **work-item-relations-uniform-from-either-end**: Listing or adding a
  relation MUST describe a link from THIS card's end (an "outgoing" or
  "incoming" direction, the far card's fields joined in), and removing a
  relation MUST address the far card's id alone (no kind argument) — "a
  pair carries one relation".
- **work-item-dependency-add-returns-raw-edge**: Adding a dependency MUST
  return the raw edge (no joined title/status) — a caller refetches the
  dependency list for the joined view.

### Iterations

- **iteration-owned-by-workspace-not-project**: An iteration MUST be
  addressed only by workspace (list/create) or by its own id (everything
  else) — there is no board-scoped iteration route, because one time-box
  holds cards from every board its owner runs.
- **iteration-state-is-server-derived**: An iteration's state
  (`"upcoming"|"active"|"completed"`) MUST be read exactly as the backend
  computes it from its start/end dates and today's date; this component
  MUST NOT recompute it — "the server's \"today\" is the one every other
  client sees".
- **iteration-both-dates-required**: Creating an iteration MUST require
  both a start date and an end date — an iteration with an open end is not
  a time-box because its state could not be derived from one.
- **iteration-work-items-carry-cross-board-fields**: A card listed under an
  iteration MUST carry its board name, status name, status category,
  estimate scale, and priority scale alongside the plain card fields,
  because the list spans boards and cannot be read against a single board
  header or a single status/scale set.
- **iteration-remove-returns-unassigned-count**: Removing an iteration MUST
  return an unassigned-card count rather than the affected cards — the
  sweep is a workspace-level verb and returning the rows would report cards
  the caller may not be allowed to read.
- **iteration-remove-never-refuses**: Removing an iteration MUST NOT refuse
  when the box holds cards — "no iteration" is the backlog, an ordinary
  state, unlike a board column which every card must have one of.
- **iteration-rollover-reads-status-category**: Rolling an iteration over
  to another MUST move every card whose status category is not
  `done`/`canceled` (including `backlog`) into the target iteration or the
  backlog (`null`); a board's own column labels never affect this.
- **iteration-work-items-reach-filtered**: Unlike removal/rollover, listing
  an iteration's cards MUST be reach-filtered — a card on a board the
  caller cannot open MUST NOT appear even though the caller can see the
  cycle.

### Programs

- **program-owned-by-workspace-not-project**: A program MUST be addressed
  only by workspace (list/create) or by its own id (everything else) — no
  board-scoped program route exists.
- **program-dates-independent**: A program's start date and target date
  MUST each be independently nullable — "a standing program... has
  neither".
- **program-remove-returns-unassigned-count-never-refuses**: Removing a
  program MUST return an unassigned-board count and MUST NOT refuse — "in
  no program" is an ordinary state a board may be in.
- **program-projects-no-folded-health**: Listing a program's member boards
  MUST return each with its OWN health, never a single folded verdict —
  "three at-risk boards and one off-track board have no honest single
  colour".
- **program-projects-reach-filtered**: Listing a program's member boards
  MUST be reach-filtered, unlike removal, which is a workspace-level sweep.

### Milestones

- **milestone-owned-by-project**: A milestone MUST be addressed under its
  owning board — unlike an iteration or a program, a milestone belongs to
  ONE board, and a milestone id from another board is a 404, never a
  cross-board edit.
- **milestone-counts-derived-not-stored**: A milestone's counts MUST be
  derived by the backend on every list read and MUST NOT be computed,
  cached, or written to by this component — "moving a card writes nothing
  to the milestone".
- **milestone-counts-null-means-not-reported-here**: A `null` counts value
  (as returned by an update) MUST be read as "not reported here", never as
  "zero cards" — a caller must refetch the list rather than render a
  zeroed bar.
- **milestone-undated-sorts-last**: Listing milestones MUST return them
  ordered by target date ascending with undated ones (`targetDate: null`)
  LAST, never first.
- **milestone-progress-excludes-canceled**: Computing a milestone's
  progress MUST exclude the `canceled` status category from BOTH the
  numerator (done) and the denominator (total) — a canceled card is neither
  outstanding nor finished work.
- **milestone-progress-empty-is-zero-not-nan**: Computing a milestone's
  progress MUST return `ratio: 0` (never `NaN`) when the total is `0` — "an
  empty milestone has not been achieved, it has not been populated".
- **milestone-progress-null-when-counts-absent**: Computing a milestone's
  progress MUST return `null` (never a zeroed object) when its counts are
  `null`.
- **milestone-remove-returns-unassigned-count-never-refuses**: Removing a
  milestone MUST return an unassigned-card count and MUST NOT refuse when
  the milestone has cards — "counts toward no milestone" is an ordinary
  state.

### Status Updates

- **status-update-only-writable-health-source**: Status updates MUST be the
  only writable source of a board's health — every create/update/remove of
  a report here MOVES the board's derived health.
- **status-update-list-newest-first**: Listing a board's status updates
  MUST return reports newest-first — "the first row is the one the board's
  health is read from".
- **status-update-create-requires-both-fields**: Creating a status update
  MUST require both a health value and a body — "a health with no
  explanation is a colour nobody can act on".
- **status-update-edit-gated-by-authorship**: Updating a status update MUST
  be refused (403) for anyone but the report's author, regardless of what
  verbs the caller otherwise holds — "rewriting someone else's report over
  their name is a forgery".
- **status-update-remove-rolls-health-back**: Removing the newest report
  MUST move the board's health BACK to the previous live report, or to
  `null` when none remains — "the honest outcome of withdrawing a claim".
- **status-update-caller-must-refetch-project**: A caller holding a board
  alongside its status updates MUST refetch the board after any
  create/update/remove of a report, rather than patching a health value it
  never owned.

### Templates

- **template-owned-by-workspace-not-board**: A template MUST be addressed
  only by workspace (list/create) or by its own id (everything else) — a
  template pinned to one board could only ever rebuild that board.
- **template-body-validated-strictly-against-kind**: The backend MUST
  reject (400) a stored body carrying an unrecognized key for its kind,
  rather than silently discarding it — "a discarded key in a template is a
  step of a checklist that quietly stopped existing".
- **template-body-narrowing-never-throws**: Narrowing a template's stored
  body to a card-shaped or board-shaped body MUST return `null` (never
  throw) for a template of the other kind, so a renderer handed a mixed
  list can skip what it cannot draw.
- **template-card-count-is-a-preview-not-a-promise**: Reading a card-shaped
  template's card count MUST read "1 plus its children count" from the
  STORED body, `0` for a board-shaped template — a preview, not a
  guarantee.
- **template-update-body-replaces-not-merges**: Updating a template's body
  MUST replace the whole stored shape, never merge into it — "merging would
  leave no way to delete a checklist step".
- **template-update-cannot-rekind**: Updating a template MUST NOT carry a
  kind field — re-kinding would re-read a stored body against a schema it
  was never written for.
- **template-remove-is-non-cascading**: Removing a template MUST NOT touch
  anything the template previously made — "ordinary rows that stopped
  being related to it the moment they were written".
- **template-instantiate-work-item-title-scoped-to-parent**: A title
  supplied when instantiating a card-shaped template MUST re-title only the
  parent card, never its children — "renaming a checklist's steps at
  instantiation is editing the template, not using it".
- **template-instantiate-project-milestones-undated**: Instantiating a
  board-shaped template MUST return milestones UNDATED, in the template
  body's order — seeding a stored date would hand back a plan already
  overdue.

### Triage

- **triage-membership-is-a-timestamp**: A card MUST be considered "in
  triage" exactly when its triage timestamp is `null`; this is the entire
  membership rule — no separate status enum exists for it.
- **triage-opt-in-via-create-flag**: A card MUST land in the triage queue
  only when a "triage" flag is passed on creation; a board that never
  passes it has an unchanged, always-empty inbox.
- **triage-no-decline-verb**: There MUST be no "decline" method or
  parameter; declining a card is expressed as accepting it into a status in
  the `canceled` category — "leaves the card findable and says what
  happened to it".
- **triage-accept-idempotent-on-stamp**: Accepting an already-accepted card
  MUST apply the given placement but MUST leave the original triage
  timestamp unchanged — "a double-click must not rewrite it".
- **triage-list-for-project-vs-cross-board-partition**: Listing a single
  board's triage queue (full cards) and listing its accepted cards MUST
  partition the board's cards exactly — every card is in exactly one of the
  two lists unless "include untriaged" is passed to the latter.
- **triage-cross-board-signpost-carries-owning-prefix**: A cross-board
  triage hit's item key MUST already be rendered against the OWNING
  board's prefix (or `""` when that board has none) — the cross-board
  caller has no prefix of its own to render it with.
- **triage-cross-board-limit-is-clamped-and-exact**: Listing the
  cross-board triage queue's returned page limit MUST be the value the
  server actually applied (it clamps 1..200, default 50, rather than
  refusing), and its "has more" flag MUST be computed by the server
  over-fetching one row, so it is exact.

### Search

- **search-blank-query-short-circuits**: Searching cards MUST return an
  empty result without issuing a network call when the query, trimmed, is
  empty — "an empty search box is the ordinary state of a search box, not
  an error to render" (confirmed by `hub-domain-projects-018`).
- **search-query-trimmed-before-send**: A query with leading/trailing
  whitespace MUST be trimmed before it is sent, so trailing whitespace is
  never a different search from its trimmed form (confirmed by
  `hub-domain-projects-019`).
- **search-optional-params-omitted-when-unset**: The workspace and limit
  parameters MUST be OMITTED from the query when unset, never sent empty —
  an empty workspace value is fail-closed on the server, so an empty slug
  and no slug must not mean the same thing on the wire (confirmed by
  `hub-domain-projects-020`).
- **search-result-order-is-servers**: The returned page's results order
  MUST be the server's own (a keyed hit first, then rank, then recency);
  this component MUST NOT re-sort by rank — "a client holding one page
  cannot rank a result set it only partly has" (confirmed by
  `hub-domain-projects-021`).
- **search-echoed-limit-may-differ-from-requested**: The returned page's
  limit MUST be read from the server's response, never assumed equal to
  the requested limit — the server clamps rather than refusing an
  out-of-range value (confirmed by `hub-domain-projects-021`).
- **search-hit-defaults-snippet-and-rank**: A search hit MUST default a
  missing snippet to `""` and a missing rank to `0`, never leave either
  unset (confirmed by `hub-domain-projects-022`).
- **search-is-not-an-in-board-filter**: This component MUST NOT be used for
  an in-board text filter — a board's own list is already loaded and
  filtered locally; this reaches across boards the caller has not loaded.

### Activity

- **activity-newest-first-keyset-paginated**: Both board-level and
  card-level activity MUST page newest-first using a `{ limit?, before? }`
  keyset.
- **activity-before-token-is-opaque-composite**: The "before" cursor MUST be
  treated as opaque by callers and, internally, MUST be split on the LAST
  `"|"` into a timestamp and an id for the backend's composite keyset, so
  millisecond-tied rows never straddle a page boundary (confirmed by
  `hub-domain-projects-023`).
- **activity-legacy-token-without-id-still-works**: A "before" token with no
  `"|"` (a legacy token) MUST still send the timestamp alone, with no id.
- **activity-next-before-full-page-heuristic**: The "next before" token MUST
  be the last row's composite `"<createdAt>|<id>"` token when the returned
  page's length equals the requested limit (implying more may exist), and
  `null` otherwise (a short/last page, or no limit given at all) (confirmed
  by `hub-domain-projects-023`/`024`).
- **activity-writes-live-elsewhere**: Writing a comment MUST NOT go through
  this component — the comments grouping owns the write, and the resulting
  "comment added/edited/deleted" action still appears in this trail because
  the backend writes both in one transaction.

### Comments

- **comment-list-oldest-first**: Listing a card's comments MUST return them
  in the server's oldest-first order and MUST NOT re-sort them — "a
  conversation only reads correctly forward" (confirmed by
  `hub-domain-projects-025`).
- **comment-threading-one-level-deep**: Threading comments MUST group a
  flat, oldest-first list into root/reply pairs with no recursion, because
  the backend already re-parents a reply-to-a-reply onto the root
  (confirmed by `hub-domain-projects-026`).
- **comment-orphan-promoted-not-dropped**: Threading comments MUST promote a
  reply whose parent id is not present in the list to a root of its own,
  appended after the real roots, rather than dropping it — "the parent was
  removed while this reply stands" (confirmed by `hub-domain-projects-027`).
- **comment-author-kind-unknown-falls-back-to-customer**: Reading a comment
  MUST map an unrecognized author-kind string to `"customer"` — "the
  reading that claims the least", never a synthetic value that could pose
  as an agent (confirmed by `hub-domain-projects-028`).
- **comment-edit-gated-by-authorship**: Editing a comment MUST be refused
  by the backend for anyone but the comment's author — "an editing verb on
  the board does not let a moderator put words in someone's mouth".
- **comment-remove-leaves-replies-standing**: Removing a comment MUST leave
  any replies to it in place — "a thread does not lose its answers along
  with its question".
- **comment-add-omits-parent-id-for-top-level**: Adding a top-level comment
  (no parent given) MUST send a body with no parent-id key at all, never an
  explicitly unset one serialized (confirmed by `hub-domain-projects-025`).
- **comment-reaction-kind-is-a-named-constant**: The comment reaction kind
  (`"project.comments"`) MUST be the single spelling every reaction call
  site uses, never a literal restated at each site — comments are reacted
  to through the shared polymorphic (target kind, target id) reaction
  store, not a comments-owned endpoint.

### Artifacts

- **artifact-link-id-distinct-from-target-id**: An artifact link's id MUST
  identify the LINK (what unlinking addresses), never the target — the
  same target can be linked twice (once "ingested", once "produced"), so
  the target id alone does not identify a row (confirmed by
  `hub-domain-projects-029`).
- **artifact-link-idempotent-per-triple**: Linking an artifact (direction,
  target kind, target id) MUST be idempotent per that triple — re-linking
  the same triple MUST return the existing row rather than create a
  duplicate — "a double-click cannot litter the list".
- **artifact-unresolvable-target-kept-as-null**: An artifact link whose
  target no longer resolves MUST be returned with a `null` target and its
  target kind/id intact, never dropped from the list — "the link is still
  a fact about the board" (confirmed by `hub-domain-projects-029`).
- **artifact-list-server-order-preserved**: Listing a board's artifact links
  MUST preserve the server's (newest-first) order, never re-sort — a
  client re-sort "would silently disagree with the pagination the endpoint
  is built for" (confirmed by `hub-domain-projects-029`).
- **artifact-attachable-limit-is-per-kind**: The attachable-picker's limit
  option MUST be understood as per-KIND, not per-response, so one kind
  cannot crowd the others out of the picker.
- **artifact-kind-vocabulary-is-backend-owned**: This component MUST NOT
  define or hard-code a list of valid target-kind values — the attachable
  picker is how a picker discovers what a board can hold, and a deployed
  client picks up a newly added kind on its next request without a code
  change.
- **artifact-unlink-addresses-link-not-target**: Unlinking an artifact MUST
  address the LINK's id; the target itself is untouched — "this removes
  the board's claim on it, never the thing" (confirmed by
  `hub-domain-projects-030`).

### Live Wake

- **live-payload-less-wake**: The board's live-change event MUST carry no
  payload and no change kind; the wake callback MUST take no arguments
  describing what changed — every subscriber re-reads through its own
  ordinary request under the access rules it already passes.
- **live-one-connection-per-board-refcounted**: Subscribing to a board's
  live wake MUST open exactly ONE underlying connection per distinct board
  id, shared by every subscriber, and MUST close it only when the LAST
  subscriber unsubscribes (confirmed by `hub-domain-projects-031`/`033`).
- **live-reopens-after-going-quiet**: Re-subscribing to a board after its
  connection was fully closed MUST open a fresh connection, never reuse
  the closed handle (confirmed by `hub-domain-projects-034`).
- **live-coalesces-burst-into-one-wake**: A burst of same-board live-change
  events within a 150ms trailing coalescing window MUST fold into exactly
  one wake call per subscriber, never one call per event (confirmed by
  `hub-domain-projects-035`).
- **live-wakes-again-after-window-closes**: The coalescing guard MUST be a
  window, not a once-per-connection latch — a change arriving after a
  previous window already fired MUST produce a second wake call (confirmed
  by `hub-domain-projects-036`).
- **live-poll-fallback-wakes-identically**: A polling fallback MUST wake
  subscribers exactly as a live event does, at a 60,000ms cadence, so a
  board with no live connection still updates each session (confirmed by
  `hub-domain-projects-037`).
- **live-unsubscribe-during-pending-wake-is-silent**: A subscriber that
  unsubscribes while a coalesced wake is pending MUST NOT receive that wake
  — the listener set is snapshotted at fire time (confirmed by
  `hub-domain-projects-038`/`039`).
- **live-last-unsubscribe-drops-pending-timer**: When the LAST subscriber of
  a board unsubscribes while a wake timer is pending, unsubscribing MUST
  clear that timer and close the connection, rather than letting a stale
  timer fire against a torn-down entry (confirmed by
  `hub-domain-projects-039`).
- **live-onwake-read-at-fire-time-not-closed-over**: The live-wake
  consuming hook MUST hold the latest wake callback and read it at fire
  time, rather than treating its identity as significant — a caller whose
  wake callback identity changes every render (a filter edit) MUST NOT
  tear down and reopen the shared connection on every keystroke.
- **live-null-project-id-subscribes-to-nothing**: The live-wake consuming
  hook, given no board id, MUST subscribe to nothing, so a pane may call
  it before its board has resolved.

## Appearance

Not applicable — this is domain logic (thirteen groupings of operations and
one live-wake subscription helper), not a visual component. Every value it
returns is handed to a separate, generic pane/board/kanban rendering layer
this recipe does not cover.

## States

Not applicable — this is domain logic, not a visual component. Its
observable "states" are the ordinary asynchronous-operation states a caller
already handles generically: pending, succeeded, and failed (a thrown error
carrying a numeric status code), plus the live-wake subscription's own
connected/reconnecting/polling states, which are entirely owned by the
underlying connection helper and merely consumed here.

## Accessibility

Not applicable — this is domain logic, not a visual component. Every string
this component defines (the key-prefix validator's two error messages, the
default singular/plural item nouns) is plain text handed to a separate
rendering layer, which owns accessibility presentation.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| hub-domain-projects-001 | project-list-sorted-by-name | List boards over rows named `["Beta","Alpha"]` | Result names `["Alpha","Beta"]` (`"list GETs the base URL and sorts by name"`) |
| hub-domain-projects-002 | project-participant-remove-addressing | Remove participant `"cust1"` (kind `"customer"`) from board `"p1"` | `DELETE /api/project/projects/p1/participants/cust1?kind=customer` |
| hub-domain-projects-004 | project-update-preserves-explicit-null | Update board `"1"` with `{name:"Renamed", description: undefined, archivedAt: null}` | Body `{"name":"Renamed","archivedAt":null}` — `description` dropped, `archivedAt` kept (`"dropping undefined but KEEPING explicit null"`) |
| hub-domain-projects-006 | project-key-prefix-shape | Validate key prefixes `"AB"`, `"WEB"`, `"ADH2"`, `"A1B2C3D4"` | All `null` (`"accepts 2-8 characters starting with a letter"`) |
| hub-domain-projects-007 | project-key-prefix-shape, project-key-prefix-empty-refused-not-cleared | Validate key prefixes `""`, `"   "` | Both match `/required/i` |
| hub-domain-projects-008 | project-key-prefix-shape | Validate key prefixes `"A"`, `"ABCDEFGHI"`, `"1AB"`, `"A-B"`, `"A B"`, `"AB!"` | All non-null (`"refuses a single character, a 9th character, a leading digit, and punctuation"`) |
| hub-domain-projects-010 | work-item-rank-is-opaque-byte-order | Compare ranks `"aZ"` and `"az"` by byte order, then by locale-aware comparison | Byte-order result `< 0`; locale-aware result `> 0` (`"sorts by BYTES, so a capital letter sorts before every lower-case one"`) |
| hub-domain-projects-011 | work-item-rank-is-opaque-byte-order | Sort ranks `["V1","V0","V0V","V2"]` by byte order | `["V0","V0V","V1","V2"]` (`"orders the keys the backend actually mints"`) |
| hub-domain-projects-012 | work-item-update-clears-via-explicit-null | Update card `"w1"` with `{assigneeKind:null, assigneeId:null, dueDate:null, parentId:null, title:undefined}` | Body `{"assigneeKind":null,"assigneeId":null,"dueDate":null,"parentId":null}` |
| hub-domain-projects-013 | work-item-move-null-survives-compact | Move card `"w1"` with `{afterId:null, beforeId:undefined}` | Body `{"afterId":null}` (`"to an END sends an explicit null rather than stripping it"`) |
| hub-domain-projects-014 | work-item-key-derivation | Fetch a board whose row carries no key prefix | Board's key prefix reads as `""` |
| hub-domain-projects-015 | work-item-key-derivation | List a board's cards where a row carries item key `"WEB-42"` | Card's item key reads as `"WEB-42"` |
| hub-domain-projects-018 | search-blank-query-short-circuits | Search cards for `""` and for `"   "` | Both resolve to an empty result; no network call is issued |
| hub-domain-projects-019 | search-query-trimmed-before-send | Search cards for `"  tungsten  "` | Request query `?q=tungsten` |
| hub-domain-projects-020 | search-optional-params-omitted-when-unset | Search cards for `"tungsten"` with `{workspace:"acme", limit:5}`, then with no options | First: `?q=tungsten&workspace=acme&limit=5`; second: `?q=tungsten` alone |
| hub-domain-projects-021 | search-result-order-is-servers, search-echoed-limit-may-differ-from-requested | Server returns a weaker hit (rank 0.1) then a stronger hit (rank 0.6), with `limit:50, hasMore:true`, for a request of `limit:500` | Result ids stay in the server's order (weaker first); result limit reads as `50` (`"keeps the server's order and reports the limit the server ACTUALLY applied"`) |
| hub-domain-projects-022 | search-hit-defaults-snippet-and-rank | Read a search hit row with snippet and rank both unset | Hit's snippet reads as `""`, rank reads as `0` |
| hub-domain-projects-023 | activity-before-token-is-opaque-composite, activity-next-before-full-page-heuristic | Fetch board `"p1"`'s activity with `{limit:2, before:"2026-01-02T00:00:00.000Z"}`, returning 2 rows | Query `?limit=2&before=2026-01-02T00%3A00%3A00.000Z`; the returned page's next-before token is the last row's composite token |
| hub-domain-projects-024 | activity-before-token-is-opaque-composite | Fetch board `"p1"`'s activity with a composite before token | Query splits the token into a timestamp and an id parameter |
| hub-domain-projects-025 | comment-list-oldest-first, comment-add-omits-parent-id-for-top-level | List card `"w1"`'s comments; add a top-level comment `"hello"` | Listed ids stay oldest-first; add body is `{"body":"hello"}` (no parent-id key) |
| hub-domain-projects-026 | comment-threading-one-level-deep | Thread a flat list: root, a reply to it, a second root, another reply to the first root | Roots in order; the first root's replies both attach to it, one level deep |
| hub-domain-projects-027 | comment-orphan-promoted-not-dropped | Thread a flat list containing a reply whose parent is not present | The orphaned reply is promoted to a root, appended after the real roots — not dropped |
| hub-domain-projects-028 | comment-author-kind-unknown-falls-back-to-customer | List a card's comments where a row carries an unrecognized author kind | Comment's author kind reads as `"customer"` |
| hub-domain-projects-029 | artifact-link-id-distinct-from-target-id, artifact-unresolvable-target-kept-as-null, artifact-list-server-order-preserved | List board `"p1"`'s artifact links in server order, then with one link's target no longer resolving | Order is preserved (not re-sorted); the unresolvable link keeps its target kind/id with a `null` target |
| hub-domain-projects-030 | artifact-unlink-addresses-link-not-target | Unlink artifact `"a/1"` from board `"p/1"` | `DELETE /api/project/projects/p%2F1/artifacts/a%2F1` |
| hub-domain-projects-031 | live-one-connection-per-board-refcounted | Subscribe to board `"p1"`'s live wake three times | Exactly one underlying connection opens (`"opens ONE stream for a board however many panes are watching it"`) |
| hub-domain-projects-033 | live-one-connection-per-board-refcounted | Two subscribers on board `"p1"`; unsubscribe one, then the other | Connection not closed after the first unsubscribe; closed once after the second (`"closes only when the LAST watcher goes away"`) |
| hub-domain-projects-034 | live-reopens-after-going-quiet | Subscribe then unsubscribe from board `"p1"` (closing it), then subscribe again | A second, distinct connection opens |
| hub-domain-projects-035 | live-coalesces-burst-into-one-wake | Three same-board change signals in a burst, then the coalescing window elapses | The wake callback fires exactly once (`"folds a BURST of changes into a single refetch"`) |
| hub-domain-projects-036 | live-wakes-again-after-window-closes | A change signal and elapsed window, then another change signal and elapsed window | The wake callback fires twice total |
| hub-domain-projects-037 | live-poll-fallback-wakes-identically | The polling fallback fires, then the coalescing window elapses | The wake callback fires once (`"wakes on the poll fallback exactly as it does on a live event"`) |
| hub-domain-projects-038 | live-unsubscribe-during-pending-wake-is-silent | Two subscribers; one receives a change signal then unsubscribes before the window elapses | The unsubscribed watcher's wake callback never fires; the staying one fires once |
| hub-domain-projects-039 | live-last-unsubscribe-drops-pending-timer | A single subscriber receives a change signal, then unsubscribes before the window elapses | The wake callback never fires; the connection closes once (`"drops a pending wake when the last watcher leaves"`) |

## Edge Cases

- **Null/empty input**: A blank or whitespace-only search query is answered
  with an empty result without a network call
  (search-blank-query-short-circuits). An empty key-prefix input is refused
  with `"A key prefix is required."`, never treated as "clear the prefix"
  (project-key-prefix-empty-refused-not-cleared). A milestone with `null`
  counts MUST render as "unknown", never as a zeroed progress bar
  (milestone-progress-null-when-counts-absent).
- **Boundary/malformed values**: A key-prefix input of exactly 2 or 8
  characters MUST be accepted; 1 or 9 characters MUST be rejected
  (hub-domain-projects-006/008). A move target naming neither neighbor, or
  explicitly nulling both, is a 400 — "nothing above and nothing below...
  is never the move anyone meant" (work-item-move-by-named-neighbor). A
  "before" activity cursor with no separator (a legacy token) is still
  accepted, sent as the timestamp alone
  (activity-legacy-token-without-id-still-works).
- **Concurrent access**: Two closely-timed link calls for the same
  (direction, target kind, target id) triple — the second returns the
  existing row rather than creating a duplicate
  (artifact-link-idempotent-per-triple). Two closely-timed accept calls on
  the same card — the second applies its placement but does not disturb
  the original triage timestamp (triage-accept-idempotent-on-stamp). Two
  clients moving cards with the same named neighbor both land beside it,
  deliberately avoiding the race an index-based move would create ("two
  clients sending \"index 3\" race, whereas two clients naming the same
  neighbour both land beside it"). A pending coalesced wake outlived by an
  unmounting subscriber is dropped rather than firing against a gone
  component (live-unsubscribe-during-pending-wake-is-silent,
  live-last-unsubscribe-drops-pending-timer).
- **Error states**: Every single-item fetch across every grouping (boards,
  iterations, programs, cards) resolves to `null` on a thrown 404 rather
  than rethrowing (project-get-null-on-not-found and its analogues per
  grouping). Updating a status update by anyone but the report's author is
  a 403 (status-update-edit-gated-by-authorship); editing a comment by
  anyone but the comment's author is likewise refused
  (comment-edit-gated-by-authorship).
- **Ownership / scoping mismatches**: A milestone id from a board other
  than the one addressed is a 404, never a cross-board edit
  (milestone-owned-by-project). A program from another workspace named as a
  board's program id is a 400. An iteration's owner must match the
  committing card's board's owner.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `workspace` (list/create, most groupings) | `string \| undefined` | `undefined` | Pins the op to that workspace's owning principal; omitted falls back to the caller's ownership reach |
| `includeUntriaged` (listing a board's cards) | `boolean \| undefined` | `false` | Include cards still sitting in the triage inbox in the board's own list |
| `direction` (listing artifact links) | `"ingested" \| "produced" \| undefined` | `undefined` (both) | Narrow the link list to one side |
| `limit`/`query`/`kind` (the attachable-artifact picker) | `number \| string \| string \| undefined` | all `undefined` | Narrow the attachable picker; `limit` is per-kind |
| `workspace`/`limit` (card search) | `string \| number \| undefined` | `undefined` / server default `20` | Narrow the search reach and clamp the page size (server clamps 1–50) |
| `workspace`/`limit` (cross-board triage list) | `string \| number \| undefined` | `undefined` / server default `50` | Narrow the cross-board inbox reach and clamp the page size (server clamps 1–200) |
| `limit` (activity, keyset) | `number \| undefined` | `undefined` (no page limit, no next-before) | Page size for the newest-first activity keyset |
| `before` (activity, keyset) | `string \| undefined` | `undefined` | Opaque `"<createdAt>\|<id>"` composite cursor for the next older page |
| Poll interval (live wake) | internal constant | `60_000` (ms) | Poll cadence while a live connection is unavailable |
| Coalescing window (live wake) | internal constant | `150` (ms) | Trailing coalescing window folding a burst of wakes into one |
| Key-prefix pattern (board key validation) | pattern constant | one letter, then 1–7 more letters or digits | Client-side mirror of the backend's work-item key-prefix shape rule |
| Priority bounds (card priority, `"standard"` scale) | `number` constants | `0` / `4` | Bounds a card's priority is written and read within |

## Deep Linking

Not applicable — this component owns no URL scheme, Android intent filter,
or platform deep-link registration. The `/api/project/*` routes it calls are
HTTP API routes, not front-end deep links; a project/work-item/card detail
route is a concern of whatever front-end router hosts a pane built on this
data.

## Localization

- **Hardcoded English strings**: The key-prefix validator's two messages —
  `"A key prefix is required."` and `"Use 2-8 characters: a letter, then
  letters or digits."` — and the default singular/plural item nouns
  (`"work item"`/`"work items"`) are fixed English literals.

No file in this domain defines an i18n key, a lookup table, or a locale
parameter — every user-facing string above is plain, fixed English. This is
a plain, honestly-reported fact about the current source, not a hidden gap
(see Compliance).

## Accessibility Options

Not applicable — this component renders no UI and defines no Reduce Motion,
Increase Contrast, or Differentiate-Without-Color behavior. Those act on
whatever UI a host renders around the entities and query/mutation results
this component returns.

## Feature Flags

Not applicable — no file in this domain defines or reads a feature-flag key.
Every conditional path (triage membership, health derivation, ranking
on/off, estimation on/off) is derived from a model field, a thrown error's
shape, or a caller-supplied option, never from a flag this component owns.

## Analytics

Not applicable — no file in this domain emits a client-side analytics or
telemetry event.

## Privacy

- **Data collected**: Board/work-item/plan administrative metadata — names,
  descriptions, statuses, dates, labels, health reports, comment bodies, and
  the `(kind, id)` participant/assignee/author references this domain
  carries but does not itself resolve to a person's profile. `authorLabel`
  on a comment ("how the author was named at the time of writing") and
  `createdBy` on a status update are the closest this domain comes to
  personal data, and both are opaque display strings the backend supplies,
  never computed or enriched here.
- **Storage**: This component holds no cache of its own — every call is a
  live round trip through an authenticated request helper. Whatever caching
  a consumer layers on top (a query-caching layer, as the sibling
  `hub-domain-ecosystems` recipe documents for its reference implementation)
  is outside this domain's files.
- **Transmission**: Every call travels through an authenticated,
  Bearer-token request helper; this domain itself attaches no credentials
  and reads no cookies.
- **Retention**: This domain retains nothing between calls; it is a
  stateless set of functions over the network. The live-wake subscription
  helper is the one exception — a connection/listener-set entry per
  actively-watched board id, which is discarded the moment the last
  subscriber unsubscribes, holding no data, only a handle and callbacks.

## Logging

No file in this domain calls a logger or any platform logging facility.
Every failure this component detects (a thrown 404 mapped to `null`, an
unrecognized author kind mapped to `"customer"`, a network error) is either
resolved to a documented fallback value or surfaced to the caller as a
thrown error; any logging of that failure is the responsibility of the
caller or host application, not of this domain component.

## Platform Notes

- **SwiftUI / AppKit / UIKit**: Not applicable — no Swift declaration exists
  in this domain; there is no Apple-side Projects implementation to note
  concurrency behavior for.
- **React/Web**: This is the sole reference implementation. Every client is
  a plain `async` function object over `fetch` (via `authedJson`/
  `authedRequest`); `useProjectLive` is the one React-specific export (a
  `useEffect`/`useRef` hook), and every other export is framework-agnostic
  and usable from a plain script, a test, or a non-React renderer.
- **Windows / WinUI 3**: No WinUI 3 implementation exists in this domain.
  A WinUI 3 port would need to reproduce the module-scope refcounting
  `subscribeToProject` performs with a `Map`/`Set` (`live.ts`) using
  whatever this platform's equivalent of a singleton connection registry is
  (e.g. a static dictionary keyed by `projectId` guarding one
  `Windows.Web.Http`/`HttpClient`-backed SSE-equivalent connection), since
  the "one connection per board, closed only by the last watcher" contract
  (live-one-connection-per-board-refcounted) is a behavioral requirement of
  this domain, not an artifact of the browser `EventSource` API.
- **Android**: No Android implementation exists in this domain. A Kotlin
  port would face the identical refcounting requirement as Windows above,
  and would need `compareRank`'s byte-order comparator (never a locale
  string comparator) to stay compatible with the backend's `COLLATE "C"`
  column (work-item-rank-is-opaque-byte-order).
- **Python**: No Python implementation exists in this domain.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/data/src/projects/` |

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | best-practices |
| [api-design-conventions](agenticdevelopercookbook://compliance/access-patterns#api-design-conventions) | passed | access-patterns |
| [pagination-support](agenticdevelopercookbook://compliance/access-patterns#pagination-support) | passed | access-patterns |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | reliability |
| [error-recovery](agenticdevelopercookbook://compliance/reliability#error-recovery) | partial | reliability |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | internationalization |
| [secure-transport](agenticdevelopercookbook://compliance/security#secure-transport) | passed | security |
| [secure-log-output](agenticdevelopercookbook://compliance/security#secure-log-output) | passed | security |

Every logic component in this cookbook is held to at least
`separation-of-concerns` and `unit-test-coverage`, and both pass here on
their own terms. **`separation-of-concerns`** passes because each of the
fourteen files owns exactly one route stem/entity family with no
cross-file reach-in beyond the small, explicit `import { toX } from
"./y"` re-mapping calls that `programs.ts`/`triage.ts`/`templates.ts`
deliberately make (e.g. `toProject` reused by `programs.projects()`).
**`unit-test-coverage`** passes because four real `*.test.ts` files
(`projects.test.ts`, `search.test.ts`, `live.test.ts`,
`programs-milestones-health.test.ts`) exercise the wire contract, the
mappers, `compareRank`, `threadOf`, `milestoneProgress`, and the live-wake
refcounting/coalescing/poll-fallback/unsubscribe-race behavior directly —
the Conformance Test Vectors above are drawn from those real assertions,
not invented. **`api-design-conventions`** passes: every client follows one
`toX`/`BASE`/CRUD-object shape, and PATCH bodies uniformly use `compact` for
undefined-vs-null semantics. **`pagination-support`** passes: three
distinct, well-documented pagination strategies coexist correctly for their
different needs (activity's newest-first opaque composite keyset, triage/
search's clamped-limit-with-`hasMore` pages, and iteration/program/board
lists' unpaginated-but-reach-filtered full lists). **`idempotent-operations`**
passes: `artifacts.link` (per `(direction,kind,id)`) and `triage.accept`
(stamp preserved) are both explicitly, deliberately idempotent, each with a
doc comment and a dedicated behavior. **`error-recovery`** is `partial`: a
404 on `get()` recovers to a documented `null` and a search/triage/artifacts
list recovers to an empty result shape, but there is no retry or backoff
anywhere in this domain — a single network failure on any write (a `create`,
a `move`, an `accept`) surfaces immediately as a thrown error with no
built-in retry, which is a fact about the current source (see Edge Cases:
Error states), not a marker-worthy gap, since no doc comment or type
signature in this domain promises retry behavior it fails to deliver.
**`no-hardcoded-strings`** is `failed`, honestly: `validateKeyPrefix`'s two
messages and the two default item nouns are fixed English literals with no
i18n key anywhere in these fourteen files (see Localization) — a real,
reported gap in this vocabulary, not a marker, because it is a plain,
observable fact about the source rather than an unresolvable contract
question. **`secure-transport`** passes: every call goes through
`authedJson`/`authedRequest`'s Bearer-token client, and this domain attaches
no credential or cookie of its own. **`secure-log-output`** passes because
there is no logging at all in this domain (see Logging) — nothing here can
leak a secret into a log it never writes to.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to adh/hub/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial recipe: the Projects (work-tracking) domain — projects, work items, iterations, programs, milestones, status updates, templates, triage, cross-board search, activity, comments, artifacts, and the live wake. |
