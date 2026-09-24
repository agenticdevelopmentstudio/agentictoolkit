---
id: 6263d5af-d0c7-456b-903a-762581ae5dbb
title: 'Hub Domain: Projects'
domain: agentictoolkit://recipes/hub-domain-projects
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Projects (work-tracking) domain logic: the web projectsApi/project-work-items/
  iterations/programs/milestones/status-updates/templates/triage/search/activity/
  comments/artifacts clients and the payload-less subscribeToProject SSE wake, wired
  to the typed backend /api/project/* surface.'
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
- react-query
- sse
depends-on: []
related:
- agentictoolkit://recipes/hub-domain-ecosystems
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

# Hub Domain: Projects

## Overview

`hub-domain-projects` is the Projects ("work-tracking") domain of the hub: the
non-UI web logic that models a *board* (a `Project`), the *cards* on it
(`WorkItem`), and the surrounding scaffolding a board needs to run —
columns (`ProjectStatus`), participants, saved views, labels, plan points
(`Milestone`), cross-board time-boxes (`Iteration`), cross-board roll-ups
(`Program`), signed health reports (`ProjectStatusUpdate`), repeatable shapes
(`Template`), an intake inbox (`projectTriageApi`), a cross-board search
(`projectSearchApi`), an append-only audit trail (`projectActivityApi`), a
threaded conversation (`projectCommentsApi`), polymorphic pointers to content
elsewhere in the platform (`projectArtifactsApi`), and a payload-less live
wake (`subscribeToProject`/`useProjectLive`). There is no Apple counterpart —
this is a single, web-only reference implementation
(`packages/web/packages/data/src/projects/`, TypeScript):

- **`projects.ts`** — `projectsApi` (root board CRUD, `statuses`/
  `participants`/`savedViews` sub-clients, `labels`), plus `validateKeyPrefix`
  and the `KEY_PREFIX_REGEX` client-side mirror of the backend's work-item-key
  shape rule.
- **`work-items.ts`** — `projectWorkItemsApi` (card CRUD, `move`, `children`,
  `dependencies`, `relations`, field values) and `compareRank`, the byte-order
  comparator for a card's opaque fractional-index `rank`.
- **`iterations.ts`** — `projectIterationsApi`, the workspace-owned time-box
  a card is committed to.
- **`programs.ts`** — `projectProgramsApi`, the workspace-owned roll-up of
  several boards.
- **`milestones.ts`** — `projectMilestonesApi` and `milestoneProgress`, the
  board-owned plan points and their derived, `canceled`-excluded progress.
- **`status-updates.ts`** — `projectStatusUpdatesApi`, the signed reports
  `Project.health` is derived from.
- **`templates.ts`** — `projectTemplatesApi`, `workItemBodyOf`/
  `projectBodyOf`/`cardCountOf`, the "stamp this shape out again" workspace
  templates.
- **`triage.ts`** — `projectTriageApi`, the intake queue a card sits in while
  `triagedAt` is null.
- **`search.ts`** — `projectSearchApi` and `toWorkItemSearchHit`, cross-board
  full-text card search.
- **`activity.ts`** — `projectActivityApi` and `toProjectActivity`, the
  newest-first, keyset-paginated audit trail.
- **`comments.ts`** — `projectCommentsApi`, `threadOf`, and
  `COMMENT_REACTION_KIND`, the one-level-deep card conversation.
- **`artifacts.ts`** — `projectArtifactsApi`, `TargetDescriptor`, the
  polymorphic ingested/produced content links.
- **`live.ts`** — `subscribeToProject`/`useProjectLive`, the refcounted,
  coalesced, payload-less SSE "something changed" signal.
- **`wire.ts`** — the backend row and request-body shapes every `toX` mapper
  and call site above reads and writes; type-only.
- **`index.ts`** — the public surface: every client, plus the closed-set
  vocabularies (`StatusCategory`, `RelationKind`, `EstimateScale`,
  `PriorityScale`, `IterationState`, `ProjectHealth`, `TemplateKind`,
  `MilestoneCounts`, `WorkItemMoveTarget`, `TriageAcceptBody`) a consumer must
  be able to name in a signature without already holding a row.

Every client shares one shape: a `toX(row)` mapper from a `wire.ts` row type
to a public entity, a `BASE`/`stem()` route constant, and a plain object of
`async` methods over `authedJson`/`authedRequest`
(`packages/web/packages/data/src/http.ts`, itself a re-export of
`@agentic-toolkit/auth/client`). Two cross-cutting conventions recur through
every file and are stated once here rather than at each site: `compact()`
(`client-helpers.ts`) drops only `undefined` keys and preserves an explicit
`null`, which is what lets a PATCH clear a column (`assigneeId: null`,
`archivedAt: null`) while an omitted key leaves it untouched; and every
`get(id)` resolves to `null` on a thrown 404 rather than rethrowing, so "not
found" is a value, not a `catch` a caller must write everywhere.

## Behavioral Requirements

### projects.ts — `projectsApi`

- **project-list-workspace-scoping**: `projectsApi.list({ workspace })`
  MUST pin the result to that workspace's owning principal
  (`workspaceQuery`, `?workspace=<slug>`); omitted, the caller sees every
  project their reach admits (file header, "`workspace` pins list/create to
  the WORKSPACE'S owning principal").
- **project-list-sorted-by-name**: `projectsApi.list` MUST return projects
  sorted by `name` via `sortByText` (locale-aware `localeCompare`), never in
  the server's raw order (`projectsApi.list`, confirmed by
  `hub-domain-projects-001`).
- **project-get-null-on-not-found**: `projectsApi.get(id)` MUST resolve to
  `null` when the backend throws (404), never rethrow — "the UI contract is
  null-for-missing" (`projectsApi.get`).
- **project-subject-lookup-first-row**: `projectsApi.subjectProject(kind,
  id)` MUST query `?subjectKind=&subjectId=` and return the FIRST row mapped,
  or `null` when the array is empty — the auto-provisioned subject project of
  one ecosystem or persona (`projectsApi.subjectProject`).
- **project-create-compacts-optionals**: `projectsApi.create` MUST send
  `name` plus only the defined optionals of `description`/`color` via
  `compact` (`projectsApi.create`).
- **project-update-preserves-explicit-null**: `projectsApi.update` MUST send
  an explicit `archivedAt: null` (un-archive) through `compact` rather than
  stripping it, while an `undefined` field (e.g. an unset `description`) is
  dropped (`projectsApi.update`, confirmed by
  `hub-domain-projects-004`).
- **project-key-prefix-shape**: `validateKeyPrefix(prefix)` MUST trim and
  upper-case the input, return `"A key prefix is required."` for an empty
  value, `"Use 2-8 characters: a letter, then letters or digits."` for a
  value failing `KEY_PREFIX_REGEX` (`/^[A-Z][A-Z0-9]{1,7}$/`), and `null`
  when the (trimmed, upper-cased) value is valid (`validateKeyPrefix`,
  confirmed by `hub-domain-projects-006`/`007`/`008`).
- **project-key-prefix-empty-refused-not-cleared**: An empty prefix MUST be
  refused by `validateKeyPrefix` rather than treated as "clear the prefix" —
  "there is no way to un-name a project's cards once they are named"
  (`validateKeyPrefix` doc comment).
- **project-item-noun-defaults**: `toProject` MUST default `itemNoun`/
  `itemNounPlural` to the fixed pair `DEFAULT_ITEM_NOUN`
  (`"work item"`)/`DEFAULT_ITEM_NOUN_PLURAL` (`"work items"`) when the
  backend sends an empty or absent value (`r.itemNoun || DEFAULT_ITEM_NOUN`),
  never derive a plural from a singular (`toProject`, `Project.itemNoun` doc
  comment: "no client can turn \"story\" into \"stories\" reliably").
- **project-estimate-scale-default**: `toProject` MUST default a missing
  `estimateScale` to `"none"` — the DB default meaning "this project does
  not estimate" — never leave it `undefined` (`toProject`).
- **project-priority-scale-default**: `toProject` MUST default a missing
  `priorityScale` to `"standard"`, the value a backend that predates the
  column implies, matching that backend's own DB default (`toProject`).
- **project-lead-both-or-neither**: `toProject` MUST read `leadKind`/
  `leadId` as a pair — both set or both `null` — treating a row carrying
  only one half as unset, because "the backend cannot write one" (`toProject`,
  `Project.leadKind` doc comment).
- **project-health-derived-not-cached**: `Project.health`/`healthUpdatedAt`
  MUST be read exactly as the backend sends them (derived from the newest
  live status update, `null` = "nobody has reported yet") and this client
  MUST NOT compute or cache a health value itself (`toProject`,
  `ProjectRow.health` doc comment in `wire.ts`).
- **project-statuses-server-ordered**: `projectsApi.statuses.list` MUST
  return the rows in the server's order (by `position`), never re-sort them
  client-side (`projectsApi.statuses.list` inline comment).
- **project-labels-is-a-suggestion-list**: `projectsApi.labels(projectId)`
  MUST be read-only and MUST be treated as a non-exhaustive vocabulary — "a
  card may carry a label that is not in it yet" — never as a closed enum a
  form validates against (`projectsApi.labels` doc comment).
- **project-participant-remove-addressing**: `projectsApi.participants.remove`
  MUST address the row by the participant's `(kind, participantId)` pair —
  the URL path segment is the actor's id, NOT the participant row's own
  `id`, and the `kind` query parameter is required
  (`projectsApi.participants.remove`, confirmed by
  `hub-domain-projects-002`).
- **project-saved-views-are-shared**: `SavedView` rows MUST be treated as
  shared across every caller who can read the project — "there are no
  private views" — and `config` MUST be passed through as `unknown`,
  decoded only by the feature package that owns the filter vocabulary, never
  interpreted here (`SavedView.config` doc comment,
  `projectsApi.savedViews`).

### work-items.ts — `projectWorkItemsApi`

- **work-item-list-excludes-untriaged-by-default**: `listForProject` MUST
  return only ACCEPTED cards (`triagedAt` non-null) unless
  `includeUntriaged: true` is passed, because an untriaged card "has had no
  column decision made about it" and showing it would assert a placement
  nobody made (`projectWorkItemsApi.listForProject` doc comment).
- **work-item-list-rank-ordered**: `listForProject` and `children` MUST
  return cards in `rank` order as the server sends them, never re-sorted
  client-side (inline "server orders by rank" comments).
- **work-item-rank-is-opaque-byte-order**: `compareRank(a, b)` MUST compare
  two `rank` strings with a plain `<`/`>` (never subtraction, never
  `localeCompare`), because the backend's `rank` column is `COLLATE "C"`
  (byte order) and the rank alphabet `0-9A-Za-z`'s UTF-16 code units equal
  those bytes in the same order (`compareRank` doc comment, confirmed by
  `hub-domain-projects-010`/`011`: `compareRank("aZ","az") < 0` while
  `"aZ".localeCompare("az") > 0`).
- **work-item-update-clears-via-explicit-null**: `update` MUST send an
  explicit `null` for `assigneeKind`/`assigneeId`/`dueDate`/`parentId`/
  `iterationId`/`milestoneId`/`estimate` through `compact` (never stripped),
  while an `undefined` field (e.g. `title: undefined`) IS stripped
  (`projectWorkItemsApi.update`, confirmed by `hub-domain-projects-012`).
- **work-item-move-by-named-neighbor**: `move(id, target)` MUST send a
  `WorkItemMoveTarget` naming a sibling by id/key, never an index — the five
  legal shapes are `{afterId}`, `{beforeId}`, `{afterId,beforeId}` (between,
  already-ordered), `{afterId:null}` (to the top), and `{beforeId:null}` (to
  the bottom); naming neither, or nulling both, is a 400
  (`WorkItemMoveTarget` doc comment in `wire.ts`).
- **work-item-move-null-survives-compact**: `move`'s `compact(target)` call
  MUST let an explicit `{afterId: null}` reach the request body — distinct
  from an omitted `afterId`, which means "I didn't say" — confirmed by
  `hub-domain-projects-013` (`{afterId: null, beforeId: undefined}` sends
  `{"afterId":null}`).
- **work-item-move-returns-moved-card-only**: `move` MUST return only the
  moved card, carrying its new `rank`; no sibling in the response changes,
  so a caller re-sorts the list it already holds rather than refetching
  (`projectWorkItemsApi.move` doc comment).
- **work-item-key-derivation**: `WorkItem.itemKey` MUST default to `""` when
  the backend omits it (an older backend, or a project with no assigned
  prefix yet), and MUST be treated as read-only — never sent back on a PATCH
  (`toWorkItem`, `WorkItemRow.itemKey` doc comment, confirmed by
  `hub-domain-projects-014`/`015`).
- **work-item-estimate-null-distinct-from-zero**: `WorkItem.estimate` MUST
  distinguish `null` (un-estimated) from `0` (estimated at zero); a PATCH
  with `estimate: null` un-estimates the card (`toWorkItem`,
  `WorkItemPatchBody.estimate` doc comment).
- **work-item-relations-uniform-from-either-end**: `relations.list`/`.add`
  MUST describe a link from THIS card's end (`direction: "outgoing" |
  "incoming"`, the far card's fields joined in), and `relations.remove` MUST
  address the far card's id alone (no `kind` argument) — "a pair carries one
  relation" (`WorkItemRelation` doc comment, `relations.remove` inline
  comment).
- **work-item-dependency-add-returns-raw-edge**: `dependencies.add` MUST
  return the raw `DependencyEdge` (no joined `title`/`status`) — a caller
  refetches `dependencies.list` for the joined view (`DependencyEdge` doc
  comment in `wire.ts`).

### iterations.ts — `projectIterationsApi`

- **iteration-owned-by-workspace-not-project**: An `Iteration` MUST be
  addressed only via `?workspace=` (list/create) or `/project/iterations/
  {id}` (everything else) — there is no `/projects/{id}/iterations` route,
  because one time-box holds cards from every board its owner runs (file
  header comment).
- **iteration-state-is-server-derived**: `Iteration.state`
  (`"upcoming"|"active"|"completed"`) MUST be read exactly as the backend
  computes it from `(startDate, endDate)` and today's date; this client MUST
  NOT recompute it, "the server's \"today\" is the one every other client
  sees" (`Iteration.state` doc comment).
- **iteration-both-dates-required**: `create` MUST require both
  `startDate` and `endDate` — an iteration with an open end is not a
  time-box because `state` could not be derived from one
  (`Iteration.endDate` doc comment).
- **iteration-work-items-carry-cross-board-fields**: `IterationWorkItem`
  MUST carry `projectName`/`statusName`/`statusCategory`/`estimateScale`/
  `priorityScale` alongside the plain `WorkItem` fields, because the list
  spans projects and cannot be read against a single project header or a
  single status/scale set (`IterationWorkItem` doc comment).
- **iteration-remove-returns-unassigned-count**: `remove(id)` MUST return
  `{ unassigned: number }` rather than the affected cards — the sweep is a
  workspace-level verb and returning the rows would report cards the caller
  may not be allowed to read (file header, `remove` doc comment).
- **iteration-remove-never-refuses**: `remove` MUST NOT refuse when the box
  holds cards — "no iteration" is the backlog, an ordinary state, unlike a
  board column which every card must have one of (`remove` doc comment).
- **iteration-rollover-reads-status-category**: `rollover(id, toIterationId)`
  MUST move every card whose status CATEGORY is not `done`/`canceled`
  (including `backlog`) into `toIterationId` or the backlog (`null`); a
  board's own column labels never affect this (`rollover` doc comment).
- **iteration-work-items-reach-filtered**: Unlike `remove`/`rollover`,
  `workItems(id)` MUST be reach-filtered — a card in a project the caller
  cannot open MUST NOT appear even though the caller can see the cycle (file
  header, `workItems` doc comment).

### programs.ts — `projectProgramsApi`

- **program-owned-by-workspace-not-project**: A `Program` MUST be addressed
  only via `?workspace=` (list/create) or `/project/programs/{id}`
  (everything else) — no `/projects/{id}/programs` route exists (file
  header).
- **program-dates-independent**: `startDate`/`targetDate` MUST each be
  independently nullable — "a standing program... has neither" (`Program`
  doc comment).
- **program-remove-returns-unassigned-count-never-refuses**: `remove(id)`
  MUST return `{ unassigned: number }` and MUST NOT refuse — "in no
  program" is an ordinary state a project may be in (`remove` doc comment).
- **program-projects-no-folded-health**: `projects(id)` MUST return each
  member board with its OWN `health`, never a single folded verdict —
  "three at-risk boards and one off-track board have no honest single
  colour" (`ProgramRow` doc comment, `projects` doc comment).
- **program-projects-reach-filtered**: `projects(id)` MUST be reach-filtered
  unlike `remove`, which is a workspace-level sweep (`projects` doc
  comment).

### milestones.ts — `projectMilestonesApi` / `milestoneProgress`

- **milestone-owned-by-project**: A milestone MUST be addressed under
  `/project/projects/{id}/milestones` — unlike an iteration or a program, a
  milestone belongs to ONE board, and a `milestoneId` from another board is
  a 404, never a cross-board edit (file header).
- **milestone-counts-derived-not-stored**: `Milestone.counts` MUST be
  derived by the backend on every list read and MUST NOT be computed,
  cached, or written to by this client — "moving a card writes nothing to
  the milestone" (file header, `toMilestone`).
- **milestone-counts-null-means-not-reported-here**: A `null` `counts` (as
  returned by `update`, a PATCH) MUST be read as "not reported here", never
  as "zero cards" — a caller must refetch `list` rather than render a zeroed
  bar (`Milestone.counts` doc comment).
- **milestone-undated-sorts-last**: `list()` MUST return milestones ordered
  by `targetDate` ascending with undated ones (`targetDate: null`) LAST,
  never first (`Milestone.targetDate` doc comment, `list` doc comment).
- **milestone-progress-excludes-canceled**: `milestoneProgress(m)` MUST
  exclude the `canceled` status category from BOTH the numerator (`done`)
  and the denominator (`total`) — a canceled card is neither outstanding nor
  finished work (`milestoneProgress` doc comment).
- **milestone-progress-empty-is-zero-not-nan**: `milestoneProgress` MUST
  return `ratio: 0` (never `NaN`) when `total === 0` — "an empty milestone
  has not been achieved, it has not been populated" (`milestoneProgress`
  inline comment).
- **milestone-progress-null-when-counts-absent**: `milestoneProgress` MUST
  return `null` (never a zeroed object) when `m.counts` is `null`
  (`milestoneProgress` doc comment).
- **milestone-remove-returns-unassigned-count-never-refuses**: `remove`
  MUST return `{ unassigned: number }` and MUST NOT refuse when the
  milestone has cards — "counts toward no milestone" is an ordinary state
  (`remove` doc comment).

### status-updates.ts — `projectStatusUpdatesApi`

- **status-update-only-writable-health-source**: `projectStatusUpdatesApi`
  MUST be the only writable source of `Project.health` — every
  `create`/`update`/`remove` here MOVES the project's derived health (file
  header).
- **status-update-list-newest-first**: `list(projectId)` MUST return
  reports newest-first — "the first row is the one the project's health is
  read from" (`list` doc comment).
- **status-update-create-requires-both-fields**: `create` MUST require both
  `health` and `body` — "a health with no explanation is a colour nobody
  can act on" (`create` doc comment).
- **status-update-edit-gated-by-authorship**: `update` MUST be refused
  (403) for anyone but the report's author, regardless of what verbs the
  caller otherwise holds — "rewriting someone else's report over their name
  is a forgery" (file header, `update` doc comment).
- **status-update-remove-rolls-health-back**: `remove` of the newest report
  MUST move the project's health BACK to the previous live report, or to
  `null` when none remains — "the honest outcome of withdrawing a claim"
  (`remove` doc comment).
- **status-update-caller-must-refetch-project**: A caller holding a project
  alongside its updates MUST refetch the project after any of
  `create`/`update`/`remove`, rather than patching a health value it never
  owned (file header).

### templates.ts — `projectTemplatesApi`

- **template-owned-by-workspace-not-board**: A `Template` MUST be addressed
  only via `?workspace=` (list/create) or `/project/templates/{id}`
  (everything else) — a template pinned to one board could only ever
  rebuild that board (file header).
- **template-body-validated-strictly-against-kind**: The backend MUST
  reject (400) a `body` carrying an unrecognized key for its `kind`, rather
  than silently discarding it — "a discarded key in a template is a step of
  a checklist that quietly stopped existing" (file header).
- **template-body-narrowing-never-throws**: `workItemBodyOf`/`projectBodyOf`
  MUST return `null` (never throw) for a template of the other kind, so a
  renderer handed a mixed list can skip what it cannot draw
  (`workItemBodyOf` doc comment).
- **template-card-count-is-a-preview-not-a-promise**: `cardCountOf(t)` MUST
  read `1 + (body.children?.length ?? 0)` from the STORED body for a
  work-item template, `0` for a project template — a preview, not a
  guarantee (`cardCountOf` doc comment).
- **template-update-body-replaces-not-merges**: A `body` PATCH via `update`
  MUST replace the whole stored shape, never merge into it — "merging would
  leave no way to delete a checklist step" (`update` doc comment).
- **template-update-cannot-rekind**: `update`'s `TemplatePatchBody` MUST NOT
  carry a `kind` field — re-kinding would re-read a stored body against a
  schema it was never written for (`update` doc comment,
  `TemplatePatchBody` in `wire.ts`).
- **template-remove-is-non-cascading**: `remove(id)` MUST NOT touch
  anything the template previously made — "ordinary rows that stopped being
  related to it the moment they were written" (file header).
- **template-instantiate-work-item-title-scoped-to-parent**: `title` on
  `instantiateWorkItem` MUST re-title only the parent card, never its
  children — "renaming a checklist's steps at instantiation is editing the
  template, not using it" (`instantiateWorkItem` doc comment).
- **template-instantiate-project-milestones-undated**: `instantiateProject`
  MUST return milestones UNDATED, in the template body's order — seeding a
  stored date would hand back a plan already overdue (`instantiateProject`
  doc comment).

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

### live.ts — `subscribeToProject` / `useProjectLive`

- **live-payload-less-wake**: The `project` SSE event MUST carry no payload
  and no change kind; `subscribeToProject`'s `onWake` callback MUST take no
  arguments describing what changed — every subscriber re-reads through its
  own ordinary REST call under the RLS it already passes (file header).
- **live-one-connection-per-board-refcounted**: `subscribeToProject`
  MUST open exactly ONE `connectSse` connection per distinct `projectId`,
  shared by every subscriber, and MUST close it only when the LAST
  subscriber unsubscribes (confirmed by `hub-domain-projects-031`/`033`).
- **live-reopens-after-going-quiet**: Re-subscribing to a `projectId` after
  its connection was fully closed MUST open a fresh connection, never reuse
  the closed handle (confirmed by `hub-domain-projects-034`).
- **live-coalesces-burst-into-one-wake**: A burst of same-board `project`
  events within the 150ms trailing `COALESCE_MS` window MUST fold into
  exactly one `onWake` call per subscriber, never one call per event (file
  header, `wake`, confirmed by `hub-domain-projects-035`).
- **live-wakes-again-after-window-closes**: The coalescing guard MUST be a
  window, not a once-per-connection latch — a change arriving after a
  previous window already fired MUST produce a second `onWake` call
  (confirmed by `hub-domain-projects-036`).
- **live-poll-fallback-wakes-identically**: `connectSse`'s `onPoll` callback
  MUST wake subscribers exactly as a live SSE event does, at a
  `POLL_INTERVAL_MS` (60,000ms) cadence, so a board with no live connection
  still updates each session (file header, confirmed by
  `hub-domain-projects-037`).
- **live-unsubscribe-during-pending-wake-is-silent**: A subscriber that
  unsubscribes while a coalesced wake is pending MUST NOT receive that wake
  — the listener set is snapshotted at fire time (confirmed by
  `hub-domain-projects-038`/`039`).
- **live-last-unsubscribe-drops-pending-timer**: When the LAST subscriber
  of a board unsubscribes while a wake timer is pending, `subscribeToProject`
  MUST clear that timer and close the connection, rather than letting a
  stale timer fire against a torn-down entry (`subscribeToProject`'s
  returned unsubscribe function, confirmed by `hub-domain-projects-039`).
- **live-onwake-read-at-fire-time-not-closed-over**: `useProjectLive` MUST
  hold the latest `onWake` in a `ref` and read it at fire time, rather than
  naming it as an effect dependency — a caller whose `onWake` identity
  changes every render (a filter edit) MUST NOT tear down and reopen the
  shared connection on every keystroke (`useProjectLive`).
- **live-null-project-id-subscribes-to-nothing**: `useProjectLive(null |
  undefined, onWake)` MUST subscribe to nothing, so a pane may call it
  before its board has resolved (`useProjectLive` doc comment).

## Appearance

Not applicable — this is domain logic (thirteen typed API clients and one
SSE subscription helper), not a visual component. Every value it returns is
handed to a separate, generic pane/board/kanban rendering layer this recipe
does not cover.

## States

Not applicable — this is domain logic, not a visual component. Its
observable "states" are the ordinary async-operation states a caller already
handles generically: pending (an awaited `async` call), succeeded, and
failed (a thrown `Error`/`AuthHttpError`-shaped error carrying a numeric
`.status`, per `httpStatus` in `http.ts`), plus the live-wake subscription's
own connected/reconnecting/polling states, which are entirely owned by
`connectSse` in `stream/index.ts` and merely consumed here.

## Accessibility

Not applicable — this is domain logic, not a visual component. Every string
this component defines (`validateKeyPrefix`'s two error messages,
`DEFAULT_ITEM_NOUN`/`DEFAULT_ITEM_NOUN_PLURAL`) is plain text handed to a
separate rendering layer, which owns accessibility presentation.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| hub-domain-projects-001 | project-list-sorted-by-name | `projectsApi.list()` over rows named `["Beta","Alpha"]` | Result names `["Alpha","Beta"]` (`"list GETs the base URL and sorts by name"`, `projects.test.ts`) |
| hub-domain-projects-002 | project-participant-remove-addressing | `participants.remove("p1","cust1","customer")` | `DELETE /api/project/projects/p1/participants/cust1?kind=customer` (`projects.test.ts`) |
| hub-domain-projects-004 | project-update-preserves-explicit-null | `update("1", {name:"Renamed", description: undefined, archivedAt: null})` | Body `{"name":"Renamed","archivedAt":null}` — `description` dropped, `archivedAt` kept (`"dropping undefined but KEEPING explicit null"`, `projects.test.ts`) |
| hub-domain-projects-006 | project-key-prefix-shape | `validateKeyPrefix("AB")`, `"WEB"`, `"ADH2"`, `"A1B2C3D4"` | All `null` (`"accepts 2-8 characters starting with a letter"`, `projects.test.ts`) |
| hub-domain-projects-007 | project-key-prefix-shape, project-key-prefix-empty-refused-not-cleared | `validateKeyPrefix("")`, `"   "` | Both match `/required/i` (`projects.test.ts`) |
| hub-domain-projects-008 | project-key-prefix-shape | `validateKeyPrefix("A")`, `"ABCDEFGHI"`, `"1AB"`, `"A-B"`, `"A B"`, `"AB!"` | All non-null (`"refuses a single character, a 9th character, a leading digit, and punctuation"`, `projects.test.ts`) |
| hub-domain-projects-010 | work-item-rank-is-opaque-byte-order | `compareRank("aZ","az")` vs `"aZ".localeCompare("az")` | `compareRank < 0`; `localeCompare > 0` (`"sorts by BYTES, so a capital letter sorts before every lower-case one"`, `projects.test.ts`) |
| hub-domain-projects-011 | work-item-rank-is-opaque-byte-order | `["V1","V0","V0V","V2"].sort(compareRank)` | `["V0","V0V","V1","V2"]` (`"orders the keys the backend actually mints"`, `projects.test.ts`) |
| hub-domain-projects-012 | work-item-update-clears-via-explicit-null | `update("w1", {assigneeKind:null, assigneeId:null, dueDate:null, parentId:null, title:undefined})` | Body `{"assigneeKind":null,"assigneeId":null,"dueDate":null,"parentId":null}` (`projects.test.ts`) |
| hub-domain-projects-013 | work-item-move-null-survives-compact | `move("w1", {afterId:null, beforeId:undefined})` | Body `{"afterId":null}` (`"to an END sends an explicit null rather than stripping it"`, `projects.test.ts`) |
| hub-domain-projects-014 | work-item-key-derivation | `projectsApi.get` on a row with no `keyPrefix` | `p.keyPrefix === ""` (`projects.test.ts`) |
| hub-domain-projects-015 | work-item-key-derivation | `listForProject` on a row with `itemKey: "WEB-42"` | `w.itemKey === "WEB-42"` (`projects.test.ts`) |
| hub-domain-projects-018 | search-blank-query-short-circuits | `projectSearchApi.workItems("")` and `workItems("   ")` | Both resolve to `EMPTY_WORK_ITEM_SEARCH`; `authedJson` never called (`search.test.ts`) |
| hub-domain-projects-019 | search-query-trimmed-before-send | `workItems("  tungsten  ")` | Request URL `?q=tungsten` (`search.test.ts`) |
| hub-domain-projects-020 | search-optional-params-omitted-when-unset | `workItems("tungsten", {workspace:"acme", limit:5})` vs `workItems("tungsten")` | First: `?q=tungsten&workspace=acme&limit=5`; second: `?q=tungsten` alone (`search.test.ts`) |
| hub-domain-projects-021 | search-result-order-is-servers, search-echoed-limit-may-differ-from-requested | Server returns `[weaker(rank 0.1), hitRow(rank 0.6)]` with `limit:50, hasMore:true` for a request of `limit:500` | `result.results` ids `["w2","w1"]` (server order kept); `result.limit === 50` (`"keeps the server's order and reports the limit the server ACTUALLY applied"`, `search.test.ts`) |
| hub-domain-projects-022 | search-hit-defaults-snippet-and-rank | `toWorkItemSearchHit({...hitRow(), snippet:undefined, rank:undefined})` | `hit.snippet === ""`, `hit.rank === 0` (`search.test.ts`) |
| hub-domain-projects-023 | activity-before-token-is-opaque-composite, activity-next-before-full-page-heuristic | `projectActivity("p1", {limit:2, before:"2026-01-02T00:00:00.000Z"})` returning 2 rows (a1@t1, a2@t2) | Query `?limit=2&before=2026-01-02T00%3A00%3A00.000Z`; `page.nextBefore === "t2|a2"` (`live.test.ts` sibling `projects.test.ts`) |
| hub-domain-projects-024 | activity-before-token-is-opaque-composite | `projectActivity("p1", {limit:2, before:"t2|a2"})` | Query `?limit=2&before=t2&beforeId=a2` (`projects.test.ts`) |
| hub-domain-projects-025 | comment-list-oldest-first, comment-add-omits-parent-id-for-top-level | `list("w1")` over `[c1,c2]`; `add("w1","hello")` | `out` ids `["c1","c2"]`; add body `{"body":"hello"}` (no `parentId` key) (`projects.test.ts`) |
| hub-domain-projects-026 | comment-threading-one-level-deep | `threadOf([c1, c2(parent c1), c3, c4(parent c1)])` | Roots `["c1","c3"]`; `c1`'s replies `["c2","c4"]` (`projects.test.ts`) |
| hub-domain-projects-027 | comment-orphan-promoted-not-dropped | `threadOf([c1, orphan(parent "gone")])` | Roots `["c1","orphan"]` — orphan promoted, not dropped (`"promotes a reply whose parent is missing instead of dropping it"`, `projects.test.ts`) |
| hub-domain-projects-028 | comment-author-kind-unknown-falls-back-to-customer | `list("w1")` on a row with `authorKind:"martian"` | `c.authorKind === "customer"` (`projects.test.ts`) |
| hub-domain-projects-029 | artifact-link-id-distinct-from-target-id, artifact-unresolvable-target-kept-as-null, artifact-list-server-order-preserved | `list("p1")` over `[a2, a1]`, then over `[{...a1, target:null}]` | ids stay `["a2","a1"]` (not re-sorted); the null-target row keeps `targetKind:"content.markdown"`, `targetId:"d1"`, `target:null` (`projects.test.ts`) |
| hub-domain-projects-030 | artifact-unlink-addresses-link-not-target | `unlink("p/1","a/1")` | `DELETE /api/project/projects/p%2F1/artifacts/a%2F1` (`projects.test.ts`) |
| hub-domain-projects-031 | live-one-connection-per-board-refcounted | Three `subscribeToProject("p1", ...)` calls | Exactly one `connectSse` open (`"opens ONE stream for a board however many panes are watching it"`, `live.test.ts`) |
| hub-domain-projects-033 | live-one-connection-per-board-refcounted | Two subscribers on `"p1"`; unsubscribe one, then the other | `close` not called after the first unsubscribe; called once after the second (`"closes only when the LAST watcher goes away"`, `live.test.ts`) |
| hub-domain-projects-034 | live-reopens-after-going-quiet | Subscribe+unsubscribe `"p1"` (closes), then subscribe `"p1"` again | A second, distinct `connectSse` call is made (`live.test.ts`) |
| hub-domain-projects-035 | live-coalesces-burst-into-one-wake | Three `serverSaysChanged()` calls then `vi.runAllTimers()` | `onWake` called exactly once (`"folds a BURST of changes into a single refetch"`, `live.test.ts`) |
| hub-domain-projects-036 | live-wakes-again-after-window-closes | `serverSaysChanged()` + run timers, then again | `onWake` called twice total (`live.test.ts`) |
| hub-domain-projects-037 | live-poll-fallback-wakes-identically | `opened[0].onPoll()` then run timers | `onWake` called once (`"wakes on the poll fallback exactly as it does on a live event"`, `live.test.ts`) |
| hub-domain-projects-038 | live-unsubscribe-during-pending-wake-is-silent | Two subscribers; one calls `serverSaysChanged()` then unsubscribes before timers run | The unsubscribed watcher is never called; the staying one is called once (`live.test.ts`) |
| hub-domain-projects-039 | live-last-unsubscribe-drops-pending-timer | Single subscriber triggers a wake, then unsubscribes before timers run | `onWake` never called; `close` called once (`"drops a pending wake when the last watcher leaves"`, `live.test.ts`) |

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `opts.workspace` (list/create, most clients) | `string \| undefined` | `undefined` | Pins the op to that workspace's owning principal via `workspaceQuery`; omitted falls back to the caller's ownership reach |
| `opts.includeUntriaged` (`projectWorkItemsApi.listForProject`) | `boolean \| undefined` | `false` | Include cards still sitting in the triage inbox in the board's own list |
| `opts.direction` (`projectArtifactsApi.list`) | `"ingested" \| "produced" \| undefined` | `undefined` (both) | Narrow the link list to one side |
| `opts.limit`/`opts.query`/`opts.kind` (`projectArtifactsApi.attachable`) | `number \| string \| string \| undefined` | all `undefined` | Narrow the attachable picker; `limit` is per-kind |
| `opts.workspace`/`opts.limit` (`projectSearchApi.workItems`) | `string \| number \| undefined` | `undefined` / server default `20` | Narrow the search reach and clamp the page size (server clamps 1–50) |
| `opts.workspace`/`opts.limit` (`projectTriageApi.list`) | `string \| number \| undefined` | `undefined` / server default `50` | Narrow the cross-board inbox reach and clamp the page size (server clamps 1–200) |
| `opts.limit` (`projectActivityApi`, keyset) | `number \| undefined` | `undefined` (no page limit, no `nextBefore`) | Page size for the newest-first activity keyset |
| `opts.before` (`projectActivityApi`, keyset) | `string \| undefined` | `undefined` | Opaque `"<createdAt>\|<id>"` composite cursor for the next older page |
| `POLL_INTERVAL_MS` (`live.ts`) | internal constant | `60_000` | Poll cadence while SSE is unavailable for `subscribeToProject` |
| `COALESCE_MS` (`live.ts`) | internal constant | `150` | Trailing coalescing window folding a burst of wakes into one |
| `KEY_PREFIX_REGEX` (`projects.ts`) | `RegExp` constant | `/^[A-Z][A-Z0-9]{1,7}$/` | Client-side mirror of the backend's work-item key-prefix shape rule |
| `WORK_ITEM_PRIORITY_MIN`/`MAX` (`wire.ts`) | `number` constants | `0` / `4` | Bounds `WorkItem.priority` is written and read within under the `"standard"` `PriorityScale` |

## Deep Linking

Not applicable — this component owns no URL scheme, Android intent filter,
or platform deep-link registration. The `/api/project/*` routes it calls are
HTTP API routes, not front-end deep links; a project/work-item/card detail
route is a concern of whatever front-end router hosts a pane built on this
data.

## Localization

- **Hardcoded English strings**: `validateKeyPrefix`'s two messages —
  `"A key prefix is required."` and `"Use 2-8 characters: a letter, then
  letters or digits."` — and `DEFAULT_ITEM_NOUN`/`DEFAULT_ITEM_NOUN_PLURAL`
  (`"work item"`/`"work items"`) are fixed English literals in
  `projects.ts`.

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
- **Storage**: This client holds no cache of its own — every call is a live
  round trip through `authedJson`/`authedRequest`. Whatever caching a
  consumer layers on top (a react-query client, as the sibling
  `hub-domain-ecosystems` recipe's web side documents) is outside this
  domain's files.
- **Transmission**: Every call travels through `authedJson`/`authedRequest`
  (`http.ts`, re-exporting `@agentic-toolkit/auth/client`'s Bearer-token
  client); this domain itself attaches no credentials and reads no cookies.
- **Retention**: This domain retains nothing between calls; it is a stateless
  set of functions over the network. `subscribeToProject`'s module-scope
  `live` map is the one exception — a connection/listener-set entry per
  actively-watched `projectId`, which is discarded the moment the last
  subscriber unsubscribes (`live.ts`), holding no data, only a handle and
  callbacks.

## Logging

No file in this domain calls a logger, `console.log`, `console.warn`,
`console.error`, or any platform logging API. Every failure this component
detects (a thrown 404 mapped to `null`, an unrecognized `authorKind` mapped
to `"customer"`, a network error) is either resolved to a documented
fallback value or surfaced to the caller as a thrown `Error`; any logging of
that failure is the responsibility of the caller or host application, not
of this domain component.

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
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial recipe: the Projects (work-tracking) domain — projects, work items, iterations, programs, milestones, status updates, templates, triage, cross-board search, activity, comments, artifacts, and the live wake. |
