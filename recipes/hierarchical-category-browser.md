---
id: e36ff99d-0ebd-42ca-87f0-2881a8bfedea
title: Hierarchical Category Browser
domain: agentictoolkit://recipes/hierarchical-category-browser
type: recipe
version: 1.2.0
status: draft
language: en
created: '2026-08-23'
modified: '2026-08-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: "The category rail every markdown surface shares — one HTDV level per depth walked, All/Uncategorized leading the root level, and a per-level gear (add/rename/move/file/delete) — built from useCategoryLevels over the category DAG fold."
platforms:
- typescript
- web
tags:
- hierarchical
- category
- rail
- navigation
- master-detail
- taxonomy
ingredients:
- agenticdevelopertoolkit://recipes/category-picker-dialog
depends-on:
- agenticdevelopertoolkit://recipes/hierarchical-topic-detail
related:
- agenticdevelopertoolkit://recipes/hierarchical-topic-detail
- agenticdevelopertoolkit://recipes/topic-detail
- agenticdevelopertoolkit://recipes/category-picker-dialog
- agenticdevelopertoolkit://recipes/list-chooser
- agenticdevelopertoolkit://recipes/entity-chooser
references: []
---

# Hierarchical Category Browser

## Overview

The **Hierarchical Category Browser** is the shared rail every markdown surface
that classifies its documents into a category hierarchy — the notebook today, and
research — mounts as the leading levels of a [[hierarchical-topic-detail]] stack.
It is a thin, category-specific layer over that substrate: HTDV owns the stack's
chrome, deep linking, breadcrumb, disclosure and narrow-mode behavior (see
[[hierarchical-topic-detail]] and [[topic-detail]] for that contract, which this
recipe does not restate). What this recipe adds is everything that is TRUE OF
**CATEGORIES** on top of it:

- **The rail is a level-per-depth walk of a DAG**, not a fixed hierarchy — the
  owner's categories are folded from flat `CategoryTreeNode[]` rows into a forest
  by `buildCategoryTree` (`category-tree.ts`), and a category filed under two
  parents is genuinely two rows in two different levels, because it is filed in
  two different places.
- **The root level always leads with two synthetic rows**, "All" and
  "Uncategorized", so the rail's top level answers "what am I looking at" before
  it lists a single real category.
- **Every level's header carries a gear** — Add, Rename, Move, Also file, Delete —
  that acts on the level's own selection, wired to the write operations a category
  vocabulary supports. Move and Also file are deliberately different verbs over the
  same edge table: Move rewrites the filing the user walked in through, Also file
  ADDS one and rewrites nothing. Without the second, the DAG is unreachable from the
  rail and the hierarchy reads as a tree.

It is built as a single hook, `useCategoryLevels` (`@agentic-toolkit/categories`),
that a host calls once with its raw category rows and the URL's resolved chain,
and gets back `levels: TopicLevel[]` (feed straight into
`HierarchicalDetailView`/`HierarchicalTopicDetail`), `scope: CategoryScope` (what
the item list below the rail should show), `chain: CategoryNode[]` (the resolved
breadcrumb, for the host's own navigation), and `dialogs: ReactNode` (render once,
anywhere under the pane — it is every gear dialog, already wired). Two hosts,
`features/notebook` and `features/research`, call the identical hook; nothing
about the rail itself differs between them (see Design Decisions).

## Ingredients

| Name | Domain | Role | Required | Configuration |
|---|---|---|---|---|
| Category Picker | agenticdevelopertoolkit://recipes/category-picker-dialog | The dialog behind BOTH place-picking gear actions — browses the folded forest and returns a place to file the selected category under. | yes | Move: `confirmLabel="Move"`, `allowRoot`, `rootLabel` = "Top level" or "Remove from “<parent>”" (see `not-call-an-unfiling-a-rooting`), `disabledIds` = the moved category + its own descendants. Also file: `confirmLabel="File"`, `initialSelectedId={null}`, NO `allowRoot` (a root is a category with no parents, so there is nothing to add), `disabledIds` = the category + its descendants + every parent it is ALREADY filed under. |

The other three gear dialogs (Rename, Delete, and the one-field Add) are plain
compositions of the shared `Dialog`/`Input`/`DialogActions`/`AlertModal`
primitives with no dedicated recipe of their own — see [[dialog]],
[[dialog-actions]] and [[alert-and-dialog]] for those. `useCategoryLevels` wires
all four; this recipe documents the whole.

## Integration Requirements

### The level-per-depth walk

- **mirror-the-hierarchy**: The browser MUST render one rail level per
  category depth the user has walked into — depth 0 is the root level; selecting
  a row at depth *n* that has children MUST publish a depth *n+1* level of that
  row's children.
- **not-publish-an-empty-leaf-level**: A selected category with NO children
  MUST NOT publish a level below it. An empty level would pin HTDV's frontier at
  that empty list and hide the item pane beneath it, so the walk simply stops one
  level short of a leaf rather than publishing nothing to select.

### The root level

- **lead-the-root-level-with-all-and-uncategorized**: The root level (depth
  0) MUST lead with "All", then "Uncategorized", in that exact order, followed by
  the root categories sorted by name.
- **keep-the-backend-order-below-the-root**: Every level BELOW the root MUST
  render its siblings in the order `buildCategoryTree` hands them — the backend's
  own `sortOrder`, then name — and MUST NOT re-sort. The root is the one exception
  (above) because it is the one level with no context to read an order from; deeper,
  the arriving order is the owner's, `buildCategoryTree` documents that it preserves
  it, and the [[category-picker]] browsing the same forest does not sort — so a rail
  that re-sorted would discard a deliberate ordering and disagree with the picker
  about the same subtree in the same session.
- **show-only-the-category-name**: A category row MUST render its name and
  nothing else — no sublabel, and in particular a subcategory count MUST NOT be
  shown on any row at any depth.

### The gear

- **offer-a-gear-in-every-level-header**: Every level's header MUST offer a
  gear menu with exactly five actions, in order: Add, Rename, Move, Also file,
  Delete.
- **target-the-selected-row**: Rename, Move, Also file and Delete MUST act on the
  level's currently selected row, and MUST be disabled when nothing is selected
  or when the selection is the synthetic "All" or "Uncategorized" row (neither
  names a real category). Add MUST act on the level's OWN category (its parent —
  `null` at the root level, making a new root) regardless of the row selection.
- **say-what-a-delete-keeps**: The delete confirmation MUST state that items
  filed under the category are not deleted (they become uncategorized), and MUST
  name every subcategory that IS deleted as a side effect — the ones filed
  nowhere else, computed from the same forest the rail draws.
- **leave-other-filings-alone-on-move**: A move MUST rewrite only the
  filing the user walked in through (add the new parent edge, remove the old
  one); a category filed under other parents besides the one the user is
  currently standing in MUST keep those other filings untouched.
- **file-a-category-in-a-second-place**: The gear MUST offer a verb that ADDS
  one filing and changes nothing else — one `addCategoryParent` call, no
  `removeCategoryParent`, and no navigation. The hierarchy is a DAG (a category may
  carry any number of parents), and Move is the wrong shape for saying "this belongs
  here too": it necessarily removes the filing the user walked in through. The
  picker MUST refuse the category itself and its own descendants (either would close
  a cycle the backend rejects) and every parent it is already filed under (the edge
  exists), showing those rows disabled rather than hiding them — a place that is
  missing reads as a place that does not exist, while a greyed one says the filing
  is already there. Filing MUST NOT navigate: the place the user walked in through
  still holds the category, so the route they are standing on is still true.
- **not-call-an-unfiling-a-rooting**: The Move picker's no-parent row MUST say
  what it will actually do. A category with other filings does NOT become a root by
  losing this one — it stops being HERE — so for such a category the row MUST read
  "Remove from “<parent>”" rather than "Top level", and the route MUST be left alone
  (which of the remaining places to open is a question the gesture did not answer,
  and guessing one sends the user somewhere they did not ask to go). When the filing
  being cut is the category's LAST, the row reads "Top level" and the route follows
  the category there as usual.
- **follow-a-move-to-its-new-place**: A successful move of a category ON the
  current chain MUST re-select it where it now sits: the new parent's own chain,
  then the moved category, then whatever of the old chain hung BELOW it (those
  descendants moved with it). Moving to the top level drops everything above it —
  but only when that removal really roots the category; see
  `not-call-an-unfiling-a-rooting`.
  This is `follow-a-rename-to-the-new-slug`'s sibling and for the same reason —
  a move keeps every slug but re-parents the category, so `resolveCategoryChain`
  stops resolving from that segment down and the user who re-filed a category is
  dropped to "All" on a URL that names nothing. Which segment moved is decided by
  the gear's own level, NOT by the frontier: the level at depth *d* targets
  `chain[d]`, which may be far above the deepest selection. A move driven from off
  the chain, and one that FAILS, MUST leave the route alone. The moved category's
  OWN segment MUST be re-derived against its new siblings, never carried over from
  the old chain: slugs are unique per level (`select-by-slug-not-id`), so a
  suffix it only carried because of a twin under the parent it is leaving is not its
  slug under the parent it is joining.  Only the segments BELOW it carry over
  unchanged — their scope is the moved category's own children, which a move does
  not reshape.
- **follow-a-rename-to-the-new-slug**: A successful rename of the
  CURRENTLY SELECTED category MUST re-select it under its new slug and update the
  route to match — a rename changes the category's name, and by
  `select-by-slug-not-id` that IS its URL identity, so the route the user is
  standing on expires the instant the write lands. Leaving it there drops them to
  "All" on a URL that no longer resolves, with nothing said. Renaming a category
  that is NOT the current selection MUST leave the route alone, and a rename that
  FAILS MUST leave it alone too. Only the renamed segment changes: every
  descendant's slug comes from its own name, so a deeper chain keeps its tail. The
  new segment is the slug the NEXT fold will assign, not `slugFor(newName, id)` on
  its own — see `not-guess-a-contested-slug`.
- **not-guess-a-contested-slug**: A rename or move that lands the category on
  a slug ALREADY claimed by one of its (new) siblings MUST leave the route alone
  rather than navigate. Slugs are de-collided per level and the first claimant keeps
  the bare slug (`select-by-slug-not-id`), so which of two twins keeps it
  depends on the level's ORDER — and the write itself can change that order, since
  siblings sort by `sortOrder` then NAME. Navigating on a guess would open the OTHER
  category, which is strictly worse than not moving: the stale chain degrades to the
  deepest ancestor that still resolves, which is the list holding what was just
  renamed or moved. When the slug is uncontested it is exact whatever the order —
  first claimant, no other claimant — so this rule costs nothing in the ordinary case.
- **follow-a-delete-to-the-surviving-level**: A successful delete of a
  category ON the current chain MUST re-select the chain truncated AT that
  category — everything above it, nothing from it down. The third sibling of the
  two rules above, and the one with the sharpest failure: the segments below a
  deleted category are gone with it, so a route that keeps any of them resolves to
  nothing. Which segment went is decided by the gear's own level, NOT by the
  frontier — the level at depth *d* targets `chain[d]`, which may be far above the
  deepest selection, so dropping the LAST segment of the route is only right when
  the gear happened to be the deepest level's. Deleting a category that is not on
  the chain at all, and a delete that FAILS, MUST leave the route alone. The
  navigation happens AFTER the write lands, like the move's and the rename's.

### Selection and navigation

- **select-by-slug-not-id**: Each level's `selectedId` and the ids it hands
  `onSelect` MUST be the category's URL `slug` (`slugFor(name, id)`), not its
  backend id — the same identity the rail's deep links resolve against — with the
  two synthetic rows keeping their own reserved slugs (`-all`, `-none`). Two
  siblings whose names slugify identically MUST NOT share a slug: `buildCategoryTree`
  disambiguates within one parent's children — the first claimant keeps the bare
  slug, later ones take `-2`, `-3`… — so a chain segment names exactly one row. The
  scope is one parent's children, so cousins on separate branches keep the same bare
  slug; the top level is one scope across the whole root list.
- **clear-to-the-parent-level**: A level's `onClear` (re-click of the
  selected row, or a breadcrumb-up through HTDV) MUST re-select the chain one
  segment shorter than this level's own ancestors, not the whole chain — it walks
  up one level at a time, the same as the level walk went down.

## Layout

The browser contributes N rail levels (N = the walked depth + 1) into an
existing [[hierarchical-topic-detail]] stack; it draws no chrome of its own:

```
┌───────────────────────────────────────────────────────────────────────┐
│ … ▸ Work ▸ Q3                                          [?] help        │  ← HTDV's one breadcrumb (not this recipe's)
├──────────┬──────────┬──────────┬───────────────────────────────────────┤
│ Categ. ⚙│ Work    ⚙│ Q3      ⚙│  the item list / detail for "Q3"       │
│ ▸ All    │ ▸ Q3     │  (leaf — no level below; Q3 has no children)     │
│   Uncat. │   Q4     │                                                  │
│ ─────────│          │                                                  │
│   Home   │          │                                                  │
│   Work   │          │                                                  │
│   …      │          │                                                  │
└──────────┴──────────┴──────────┴───────────────────────────────────────┘
   root level   depth-1 level   (Q3 has no children → no depth-2 level;
   (All, Uncat,  (Work's own       the pane below is the leaf's own content,
   then roots)   children)         owned by the host, not this recipe)
```

Narrow-mode drill-down, disclosure, and the breadcrumb are entirely HTDV's — see
[[hierarchical-topic-detail]]'s own Layout section.

## Shared State

| State | Source | Consumer | Direction | Mechanism |
|---|---|---|---|---|
| Raw category rows | the host's list fetch (`notesApi.categories`/research's equivalent) | `useCategoryLevels` | host → hook | `rows: CategoryTreeNode[] \| null` option |
| Resolved chain | `resolveCategoryChain(tree, chainSlugs)` inside the hook | the host's navigation, breadcrumbs, and the item-list scope | hook → host | `chain: CategoryNode[]` result field |
| List scope | the resolved chain, via `scopeFor` | the host's item-list fetch | hook → host | `scope: CategoryScope` result field (`all` / `uncategorized` / `named`) — an EXACT-match name, not a descendant-inclusive filter |
| Rail levels | the walk over `tree` + `chain` | the enclosing `HierarchicalDetailView`/`HierarchicalTopicDetail` | hook → HTDV | `levels: TopicLevel[]` result field, appended before the host's own (e.g. note/document) levels |
| Gear target | the level closure at render time (`selectedNode`, `levelParent`) | the four dialogs | hook (internal) | `pending: { action, target }` state, captured fresh each render so a stale target can never survive a rename (HTDV's `levelsKey` ignores `ReactNode` props) |
| Write result | `taxonomyApi`/`markdownApi` (`@agentic-toolkit/data/markdown`) | the host's list refetch | hook → host | `onChanged: () => void \| Promise<void>` option, called after every successful write |

## Integration Test Vectors

| ID | Requirements | Input | Expected |
|---|---|---|---|
| T1 | mirror-the-hierarchy | rows with a 2-deep chain, `chainSlugs=["work"]` | two levels publish: root (containing "Work") and "Work"'s children |
| T2 | not-publish-an-empty-leaf-level | select a leaf category (no children) | no level appears below the leaf's own level; the host's pane renders directly |
| T3 | lead-the-root-level-with-all-and-uncategorized, keep-the-backend-order-below-the-root | roots and children both arriving in non-alphabetical order | root level's first two items are "All" then "Uncategorized", in that order, ahead of the roots sorted by name; a deeper level's siblings stay in arrival order |
| T4 | show-only-the-category-name | a category with children | its row shows the name only — no count, no second line |
| T5 | offer-a-gear-in-every-level-header, target-the-selected-row | no selection at a level | gear opens; Rename/Move/Delete are disabled; Add is enabled and, on confirm, creates a child of that level's own category |
| T6 | target-the-selected-row | "All" or "Uncategorized" selected, gear opened | Rename/Move/Delete disabled (neither names a real category) |
| T7 | say-what-a-delete-keeps | delete a category with one child filed only there and one child also filed elsewhere | confirmation names the first child as also-deleted and not the second; item filed under the deleted category becomes uncategorized (not removed) |
| T8 | leave-other-filings-alone-on-move, follow-a-move-to-its-new-place | move a category filed under two parents, walked in via parent A | filing under parent A is rewritten to the new parent; the filing under parent B is untouched; the route becomes the new parent's chain + the moved category + the tail that hung below it |
| T9 | select-by-slug-not-id | select a real category | `onSelectChain` receives the category's slug appended to the ancestor slugs, not its id |
| T10 | clear-to-the-parent-level | at depth 2, call the level's `onClear` | selection becomes the depth-1 chain (one segment shorter), not the root |
| T11 | follow-a-delete-to-the-surviving-level | standing on `work/q3/budget`, delete "Work" from the ROOT level's gear | the route becomes `[]`, not `work/q3`; deleting "Q3" from its own level instead leaves `["work"]`; a delete that rejects leaves the route untouched |
| T15 | follow-a-move-to-its-new-place | the add resolves and the remove rejects | `onChanged` fires exactly once before the rejection surfaces, the dialog stays open showing the reason, and no navigation happens; re-confirming the same move issues only the remove |
| T13 | not-guess-a-contested-slug | standing in `work`, rename Work to a name that slugifies exactly as a sibling root's does | the route is left alone (no navigation); the rail degrades to the level above once the write lands |
| T14 | follow-a-move-to-its-new-place, not-guess-a-contested-slug | Work holds twins "Q 3" (`q-3`) and "Q-3" (`q-3-2`); standing in `work/q-3-2`, move that twin under Archive, which holds no `q-3` | the route becomes `archive/q-3` — the bare slug, not the `-2` it carried under Work |
| T16 | file-a-category-in-a-second-place | Q3 is filed under Work; standing in `work/q3`, choose Also file and pick Archive | exactly one `addCategoryParent("q3", "archive")`, zero `removeCategoryParent`, and no `onSelectChain` call — the route stays on `work/q3` |
| T17 | file-a-category-in-a-second-place | open Also file for Q3 (filed under Work and Planning, holding child Budget) | Work, Planning, Q3 itself and Budget are all present but `aria-disabled`; Archive is enabled; Confirm is disabled until a real row is picked |
| T18 | not-call-an-unfiling-a-rooting | Q3 filed under Work AND Planning; standing in `work/q3`, open Move | the no-parent row reads "Remove from “Work”"; confirming it removes only the Work edge, adds nothing, and does NOT navigate. With Q3 filed under Work alone, the same row reads "Top level" and the route becomes `["q3"]` |
| T12 | select-by-slug-not-id | three sibling categories named "Q3 Plans", "Q3: plans" and "q3 plans" | their slugs are `q3-plans`, `q3-plans-2` and `q3-plans-3`; each resolves to its own row, and a cousin under another parent still gets the bare slug |

## Edge Cases

- **Empty vocabulary.** `rows=[]` still publishes the root level with "All" and
  "Uncategorized"; `emptyLabel` reads "No categories yet." (root) or "No
  subcategories." (deeper).
- **The fetch has not landed yet.** `rows=null` publishes the same root level, but
  `emptyLabel` reads "Loading…" at every depth — NOT "No categories yet.". The
  three arms are ordered `error` → loading → empty, and that order is the point: an
  in-flight read has no standing to tell the owner their vocabulary is empty, and a
  first paint that says so (then silently fills in) reads as data loss. `null` and
  `[]` are two different answers and the copy keeps them apart. The host's `error`
  string outranks both — a read that FAILED knows even less than one still running.
- **A category filed under two parents.** It appears as a real row under BOTH
  parents' levels — walking in through either shows the same subtree beneath it.
  A rename or delete acts on the category (affects both placements); a move
  rewrites only the filing walked in through (`leave-other-filings-alone-on-move`);
  Also file is what CREATES this state from the rail in the first place.
- **Unfiling a multi-filed category.** Picking the Move picker's no-parent row is
  two different operations depending on how many filings the category carries, and
  the row's label is the only place the difference is visible. On the last filing it
  roots the category and the route follows. On any earlier one it simply removes
  this filing — the category is still filed elsewhere, `chainAfterMove` returns
  `null` rather than predicting a route into a place the gesture never named, and
  the stale chain degrades to the level the user acted from, which is the honest
  answer since what they did was take the category off that level.
- **A cycle in legacy data.** The rail never sees raw edges directly — it walks
  whatever `buildCategoryTree` folds them into, and that fold breaks a cycle
  where it closes back on the current path, re-seeding the isolated rows as roots
  (see `category-tree.ts`). The rail simply renders one more root than the owner
  might expect; it never hangs and never drops a row.
- **The `MAX_TREE_NODES` cap (4000 nodes).** The budget charges REPEAT drawings
  only: a row's FIRST appearance in the forest is always free, so no row is ever
  dropped however wide the vocabulary — a 5000-category flat list draws in full.
  What the cap bounds is the re-drawing a DAG forces, where one row filed under many
  parents appears once per path; past the budget, an already-drawn row is skipped
  under further parents while its still-undrawn siblings are drawn as normal (which
  is why the child walk skips rather than stops — a wide cousin must not starve a
  later sibling's only drawing). The forest therefore holds at most
  `MAX_TREE_NODES + rows.length` nodes. It never renders an error or leaves the rail
  blank; it exists so a pathological or corrupted DAG (exponential path count)
  cannot hang the rail.
- **Renaming the currently-open category out from under the URL.** The chain is
  re-resolved by slug on every render from the (possibly now-stale) URL slugs;
  since `slugFor` derives the slug from the CURRENT name, a rename changes the
  slug too, and the next navigation from this level uses the new one. The already
  -open level itself does not silently vanish mid-render — `onChanged` triggers a
  refetch, after which the resolved chain reflects the new name.
- **Deleting the currently-open category.** `chainAfterDelete` finds the deleted
  category ON the chain and truncates there, and the dialog's `onConfirm` navigates
  only once the write has landed. Dropping the LAST segment instead — which this
  recipe blessed until the rule above was written — is the same mistake
  `chainAfterMove` exists to avoid: the gear at depth *d* targets `chain[d]`, so
  deleting a category the user has walked PAST would have cut a segment off the far
  end and moved them somewhere they never asked to go, while still leaving the dead
  category in the route. Off the chain entirely, `chainAfterDelete` returns `null`
  and the route is left alone.
- **A rename or move onto a contested slug.** `chainAfterRename` and
  `chainAfterMove` both have to predict a slug the next fold has not assigned yet,
  and a slug is only a name until `siblingSlugs` has seen the level. They used to
  skip that step entirely — the rename returned `slugFor(nextName, id)` and the move
  reused the slug the category carried under its OLD parent — so renaming "Reports"
  to "My notes" beside a sibling actually named "my-notes" navigated into the
  SIBLING, and moving a suffixed twin to a level where its bare slug is free
  navigated to a segment naming nothing. Both now go through `freeSlugAmong`, which
  answers exactly when the base slug is free among the other siblings and `null`
  when it is contested (`not-guess-a-contested-slug`).
- **Moving the currently-open category out from under the URL.** Every slug on the
  chain survives a move — but the chain is resolved by WALKING children, so the
  moment the category stops being a child of the parent the URL walked in through,
  that segment and everything below it resolve to nothing. `chainAfterMove` rebuilds
  the route from the pre-move forest (the new parent's own ancestry is not what the
  move changed, so reading it there is exact) and hands it to `onSelectChain` only
  after the write lands (`follow-a-move-to-its-new-place`).

## Platform Notes

- **React / Web (TypeScript):** `packages/web/packages/features/categories/src/useCategoryLevels.tsx`, exported from `@agentic-toolkit/categories`. `"use client"`.
- Built on `buildCategoryTree`/`resolveCategoryChain`/`categoryKey`/`chainAfterRename`/`chainAfterMove` (which returns `null` for an unfiling that leaves the category filed elsewhere) (`ui/src/blocks/category-tree.ts`) and `CategoryGearMenu`/`CategoryPickerDialog`/`CategoryRenameDialog`/`CategoryDeleteDialog` (`ui/src/blocks/*`), all re-exported from `@agenticdevelopertoolkit/ui/blocks`.
- The two route-following functions, `chainAfterRename` and `chainAfterMove`, sit in
  `ui/src/blocks/category-tree.ts` beside the forest and slug functions whose contracts they
  follow — pure functions over a forest and a slug chain, with no notion of a notebook, a list
  query, or a network. `features/categories/src/category-scope.ts` re-exports them, so the
  import site every consumer already names still works, and anything that links only
  `@agenticdevelopertoolkit/ui` (the showcase demo among them) calls the SAME function the hub does
  rather than mirroring it.
- `CategoryScope` and the `-all`/`-none` synthetic-row slugs live in `features/categories/src/category-scope.ts`, imported by both hosts — there is exactly one copy (`note-model.ts`'s former local copy was deleted when notebook adopted the shared hook).
- Consumers: `features/notebook/src/NotebookPane.tsx` (rail + note list, `itemNoun="notes"`) and `features/research/src/ResearchPane.tsx` (rail + document list, `itemNoun="documents"`), each supplying its own `rows` fetch, `idPrefix`, and `workspaceSlug`.
- Demo: `local/ui-showcase/app/page.tsx` (Topic id `hierarchical-category-browser`) + the showcase source registry. The demo assembles the same `ui/blocks` primitives this hook composes — `buildCategoryTree`, `chainAfterRename`, `chainAfterMove`, `CategoryGearMenu`, `CategoryPickerDialog`, `CategoryRenameDialog`, `CategoryDeleteDialog` — against an in-memory `CategoryTreeNode[]` fixture, since `useCategoryLevels` itself reaches a real `taxonomyApi`/`markdownApi` the showcase has no backend for.
- Responsive: verify via the ui-showcase demo at 375 / 768 / 1440 — the rail levels inherit [[hierarchical-topic-detail]]'s own disclosure/narrow-mode behavior; this recipe adds no layout of its own to verify beyond the gear menu and its dialogs at each width.

## Design Decisions

- **One hook, two hosts, zero divergence.** `useCategoryLevels` is called
  identically by `features/notebook` and `features/research` — same options
  shape, same result shape, same dialogs. The category rail is not
  "notebook's browser, later adapted for research"; it is one shared element two
  features happen to mount (well-factored, decoupled, DRY). A third markdown
  surface (see this plan's Open Question on "docs") would call the same hook
  unchanged.
- **The walk stops at an empty level, never publishes one.** HTDV treats an
  empty level as its frontier and stops rendering anything past it — publishing
  one for a childless category would silently hide the item list underneath,
  which is the opposite of what selecting a leaf category should do. Stopping the
  walk one level early is simpler than teaching HTDV to skip empty levels, and it
  keeps the "what levels exist" answer entirely local to this hook
  (separation-of-concerns).
- **All/Uncategorized are synthetic rows, not a filter toggle.** They occupy the
  same list as real categories (same keyboard nav, same selection model) rather
  than a separate control, so "show me everything" and "show me the unfiled" are
  just two more rows to pick — no second UI to learn, no second state to keep in
  sync with the rail's own selection.
- **No subcategory count, ever.** The spec is explicit that a category row shows
  only its name. A count is a fact ABOUT the rail (how many children a node
  materialised), not about the category, and displaying it would have made every
  row two competing pieces of information instead of one legible name
  (principle-of-least-astonishment: the rail is a place to navigate, not a
  dashboard).
- **The gear reads its target from a plain prop, every render.** `CategoryGearMenu`
  is deliberately dumb (see [[category-picker]]'s sibling components) and the
  hook feeds it `selectedNode`/`levelParent` recomputed in the SAME render that
  builds `selectedId` — because HTDV's `levelsKey` cache ignores `ReactNode`
  props, a gear that closed over a stale target at registration time would act on
  the wrong category after a rename. Keeping the target reachable from a prop
  that DOES change (`selectedId`) is what keeps the gear honest.
- **Add is never disabled by the selection.** Every other gear verb acts on the
  selected ROW; Add acts on the level's own category (its parent), which is a
  property of which level you are looking at, not of what is selected within it —
  so it stays enabled with no selection, unlike Rename/Move/Delete.
- **Only the ROOT level sorts.** The root is the level with no context to read an
  order from, and the one the spec constrains ("followed by the root categories
  sorted by name") — a top-level list scanned alphabetically is one the owner can
  find a category in without remembering how it was entered. Below it, the order
  that arrives is already meaningful: it is the backend's `sortOrder`, which is the
  owner's own arrangement, and `buildCategoryTree` promises to preserve it. Sorting
  everywhere was one line shorter and made the rail contradict both that promise and
  the [[category-picker]] rendering the same subtree unsorted beside it.
- **Move adds before it removes.** The hook writes the new parent edge before
  removing the old one specifically so a refused add (a cycle the client-side
  snapshot could not see, caught by the backend's guard) leaves the category
  filed where it started rather than orphaned at the top level mid-write.
- **A move that only half-lands.** The two edge writes share no transaction, so the
  add can succeed and the remove fail, leaving the category filed in BOTH places.
  Two rules make that survivable rather than silent. The rail MUST be refreshed
  before the failure surfaces — a rejection otherwise skips the refresh, and the
  user reads "the move failed" while looking at a tree drawn from the pre-move
  forest that shows neither filing. And the add MUST be skipped when the category is
  already filed under the destination (`node.parentIds` carries every filing,
  in-forest or not), or the retry re-issues an edge that exists and the move can
  never be finished.

## Compliance

| Check | Status | Category |
|---|---|---|
| Artifact formatting (recipe) | passed | artifact-formatting |
| UI guidelines — `apt-*` tokens, no raw hex, no `!important` | passed | adh-ui-guidelines |
| Live demo exists in ui-showcase (`hierarchical-category-browser`) | passed | demo-exists |
| One hook, two identical hosts (notebook, research); no per-host divergence | passed | implementation |
| Level-per-depth walk with no empty leaf level; All/Uncategorized lead the root | passed | implementation |
| Gear (add/rename/move/also-file/delete) target rules match the spec | passed | implementation |
| Base UI only (via the shared `Dialog`/`AlertModal` primitives), never Radix | passed | adh-ui-guidelines |

## Change History

| Version | Date | Author | Summary |
|---|---|---|---|
| 1.0.0 | 2026-08-23 | Mike Fullerton | Initial recipe, documenting `useCategoryLevels` and the notebook/research rail it drives. |
| 1.1.0 | 2026-08-24 | Mike Fullerton | Added the fifth gear verb, Also file (`must-file-a-category-in-a-second-place`), so the DAG is reachable from the rail; made the Move picker's no-parent row say whether it roots or merely unfiles (`must-not-call-an-unfiling-a-rooting`). |
| 1.2.0 | 2026-09-23 | Mike Fullerton | Renamed every requirement to subject-only kebab-case, dropping the old prefix everywhere it is cited. |
