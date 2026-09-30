<!-- leaf: implement-hub-domain-2/projects · source: hub-domain-projects.md -->

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

