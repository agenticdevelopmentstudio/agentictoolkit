<!-- leaf: implement-hub-domain-2/projects--part-2 · source: hub-domain-projects.md -->

# Hub Domain: Projects — continued (part 2)

**Rules** (cite as `implement-hub-domain-2/projects--part-2#<slug>`):

- `project-list-workspace-scoping` MUST
- `project-list-sorted-by-name` MUST
- `project-get-null-on-not-found` MUST
- `project-subject-lookup-first-row` MUST
- `project-create-compacts-optionals` MUST
- `project-update-preserves-explicit-null` MUST
- `project-key-prefix-shape` MUST
- `project-key-prefix-empty-refused-not-cleared` MUST
- `project-item-noun-defaults` MUST
- `project-estimate-scale-default` MUST
- `project-priority-scale-default` MUST
- `project-lead-both-or-neither` MUST
- `project-health-derived-not-cached` MUST
- `project-statuses-server-ordered` MUST
- `project-labels-is-a-suggestion-list` MUST
- `project-participant-remove-addressing` MUST
- `project-saved-views-are-shared` MUST
- `work-item-list-excludes-untriaged-by-default` MUST
- `work-item-list-rank-ordered` MUST
- `work-item-rank-is-opaque-byte-order` MUST
- `work-item-update-clears-via-explicit-null` MUST
- `work-item-move-by-named-neighbor` MUST
- `work-item-move-null-survives-compact` MUST
- `work-item-move-returns-moved-card-only` MUST
- `work-item-key-derivation` MUST
- `work-item-estimate-null-distinct-from-zero` MUST
- `work-item-relations-uniform-from-either-end` MUST
- `work-item-dependency-add-returns-raw-edge` MUST

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

