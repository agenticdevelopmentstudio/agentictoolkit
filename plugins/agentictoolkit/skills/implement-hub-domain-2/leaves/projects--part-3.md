<!-- leaf: implement-hub-domain-2/projects--part-3 · source: hub-domain-projects.md -->

# Hub Domain: Projects — continued (part 3)

**Rules** (cite as `implement-hub-domain-2/projects--part-3#<slug>`):

- `iteration-owned-by-workspace-not-project` MUST
- `iteration-state-is-server-derived` MUST
- `iteration-both-dates-required` MUST
- `iteration-work-items-carry-cross-board-fields` MUST
- `iteration-remove-returns-unassigned-count` MUST
- `iteration-remove-never-refuses` MUST
- `iteration-rollover-reads-status-category` MUST
- `iteration-work-items-reach-filtered` MUST
- `program-owned-by-workspace-not-project` MUST
- `program-dates-independent` MUST
- `program-remove-returns-unassigned-count-never-refuses` MUST
- `program-projects-no-folded-health` MUST
- `program-projects-reach-filtered` MUST
- `milestone-owned-by-project` MUST
- `milestone-counts-derived-not-stored` MUST
- `milestone-counts-null-means-not-reported-here` MUST
- `milestone-undated-sorts-last` MUST
- `milestone-progress-excludes-canceled` MUST
- `milestone-progress-empty-is-zero-not-nan` MUST
- `milestone-progress-null-when-counts-absent` MUST
- `milestone-remove-returns-unassigned-count-never-refuses` MUST
- `status-update-only-writable-health-source` MUST
- `status-update-list-newest-first` MUST
- `status-update-create-requires-both-fields` MUST
- `status-update-edit-gated-by-authorship` MUST
- `status-update-remove-rolls-health-back` MUST
- `status-update-caller-must-refetch-project` MUST
- `template-owned-by-workspace-not-board` MUST
- `template-body-validated-strictly-against-kind` MUST
- `template-body-narrowing-never-throws` MUST
- `template-card-count-is-a-preview-not-a-promise` MUST
- `template-update-body-replaces-not-merges` MUST
- `template-update-cannot-rekind` MUST
- `template-remove-is-non-cascading` MUST
- `template-instantiate-work-item-title-scoped-to-parent` MUST
- `template-instantiate-project-milestones-undated` MUST

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

