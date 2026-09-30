<!-- leaf: implement-general-1/hierarchical-category-browser--part-3 · source: hierarchical-category-browser.md -->

# Hierarchical Category Browser — continued (part 3)

## Layout

The browser contributes N rail levels (N = the walked depth + 1) into an
existing
Hierarchical Topic Detail
stack; it draws no chrome of its own:

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
Hierarchical Topic Detail's
own Layout section.

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
| T5 | offer-a-gear-in-every-level-header, target-the-selected-row | no selection at a level | gear opens with exactly five actions in order — Add, Rename, Move, Also file, Delete; Rename/Move/Also file/Delete are disabled; Add is enabled and, on confirm, creates a child of that level's own category |
| T6 | target-the-selected-row | "All" or "Uncategorized" selected, gear opened | Rename/Move/Also file/Delete disabled (neither names a real category) |
| T7 | say-what-a-delete-keeps | delete a category with one child filed only there and one child also filed elsewhere | confirmation names the first child as also-deleted and not the second; item filed under the deleted category becomes uncategorized (not removed) |
| T8 | leave-other-filings-alone-on-move, follow-a-move-to-its-new-place | move a category filed under two parents, walked in via parent A | filing under parent A is rewritten to the new parent; the filing under parent B is untouched; the route becomes the new parent's chain + the moved category + the tail that hung below it |
| T9 | select-by-slug-not-id | select a real category | `onSelectChain` receives the category's slug appended to the ancestor slugs, not its id |
| T10 | clear-to-the-parent-level | at depth 2, call the level's `onClear` | selection becomes the depth-1 chain (one segment shorter), not the root |
| T11 | follow-a-delete-to-the-surviving-level | standing on `work/q3/budget`, delete "Work" from the ROOT level's gear | the route becomes `[]`, not `work/q3`; deleting "Q3" from its own level instead leaves `["work"]`; a delete that rejects leaves the route untouched |
| T12 | select-by-slug-not-id | three sibling categories named "Q3 Plans", "Q3: plans" and "q3 plans" | their slugs are `q3-plans`, `q3-plans-2` and `q3-plans-3`; each resolves to its own row, and a cousin under another parent still gets the bare slug |
| T13 | not-guess-a-contested-slug | standing in `work`, rename Work to a name that slugifies exactly as a sibling root's does | the route is left alone (no navigation); the rail degrades to the level above once the write lands |
| T14 | rederive-the-moved-segment-not-carry-it-over, not-guess-a-contested-slug | Work holds twins "Q 3" (`q-3`) and "Q-3" (`q-3-2`); standing in `work/q-3-2`, move that twin under Archive, which holds no `q-3` | the route becomes `archive/q-3` — the bare slug, not the `-2` it carried under Work |
| T15 | refresh-before-surfacing-a-half-move, skip-an-existing-edge-on-retry, not-navigate-on-a-move-off-chain-or-failed | the add resolves and the remove rejects | `onChanged` fires exactly once before the rejection surfaces, the dialog stays open showing the reason, and no navigation happens; re-confirming the same move issues only the remove |
| T16 | file-a-category-in-a-second-place, not-navigate-on-file | Q3 is filed under Work; standing in `work/q3`, choose Also file and pick Archive | exactly one `addCategoryParent("q3", "archive")`, zero `removeCategoryParent`, and no `onSelectChain` call — the route stays on `work/q3` |
| T17 | disable-not-hide-an-invalid-file-target | open Also file for Q3 (filed under Work and Planning, holding child Budget) | Work, Planning, Q3 itself and Budget are all present but `aria-disabled`; Archive is enabled; Confirm is disabled until a real row is picked |
| T18 | not-call-an-unfiling-a-rooting | Q3 filed under Work AND Planning; standing in `work/q3`, open Move | the no-parent row reads "Remove from “Work”"; confirming it removes only the Work edge, adds nothing, and does NOT navigate. With Q3 filed under Work alone, the same row reads "Top level" and the route becomes `["q3"]` |
| T19 | follow-a-rename-to-the-new-slug | standing on the currently selected category, rename it to an uncontested name | the route swaps only that segment to the new slug and keeps the tail below it unchanged; renaming a category that is not the current selection leaves the route alone; a rename that fails leaves the route alone too |

## Platform Notes

- **React / Web (TypeScript):** `packages/web/packages/features/categories/src/useCategoryLevels.tsx`, exported from `@agentic-toolkit/categories`. `"use client"`.
- Built on `buildCategoryTree`/`resolveCategoryChain`/`categoryKey`/`chainAfterRename`/`chainAfterMove`/`chainAfterDelete` (which returns `null` for an unfiling that leaves the category filed elsewhere) (`external/agenticdevelopertoolkit/packages/web/packages/ui/src/blocks/category-tree.ts`) and `CategoryGearMenu`/`CategoryPickerDialog`/`CategoryRenameDialog`/`CategoryDeleteDialog` (`external/agenticdevelopertoolkit/packages/web/packages/ui/src/blocks/*`), all re-exported from `@agenticdevelopertoolkit/ui/blocks`.
- The three route-following functions, `chainAfterRename`, `chainAfterMove` and
  `chainAfterDelete`, sit in
  `external/agenticdevelopertoolkit/packages/web/packages/ui/src/blocks/category-tree.ts`
  beside the forest and slug functions whose contracts they follow — pure functions over a
  forest and a slug chain, with no notion of a notebook, a list query, or a network.
  `packages/web/packages/features/categories/src/category-scope.ts` re-exports them, so the
  import site every consumer already names still works, and anything that links only
  `@agenticdevelopertoolkit/ui` (the showcase demo among them) calls the SAME function the hub does
  rather than mirroring it.
- `CategoryScope` and the `-all`/`-none` synthetic-row slugs live in
  `packages/web/packages/features/categories/src/category-scope.ts`, imported by both hosts —
  there is exactly one copy (`note-model.ts`'s former local copy was deleted when notebook
  adopted the shared hook).
- Consumers: `packages/web/packages/features/notebook/src/NotebookPane.tsx` (rail + note list, `itemNoun="notes"`) and `packages/web/packages/features/research/src/ResearchPane.tsx` (rail + document list, `itemNoun="documents"`), each supplying its own `rows` fetch, `idPrefix`, and `workspaceSlug`.
- Demo: `local/ui-showcase/app/page.tsx` (Topic id `hierarchical-category-browser`) + the showcase source registry. The demo assembles the same `external/agenticdevelopertoolkit/packages/web/packages/ui/src/blocks` primitives this hook composes — `buildCategoryTree`, `chainAfterRename`, `chainAfterMove`, `CategoryGearMenu`, `CategoryPickerDialog`, `CategoryRenameDialog`, `CategoryDeleteDialog` — against an in-memory `CategoryTreeNode[]` fixture, since `useCategoryLevels` itself reaches a real `taxonomyApi`/`markdownApi` the showcase has no backend for.
- Responsive: verify via the ui-showcase demo at 375 / 768 / 1440 — the rail levels inherit
  Hierarchical Topic Detail's
  own disclosure/narrow-mode behavior; this recipe adds no layout of its own to verify beyond
  the gear menu and its dialogs at each width.
- **SwiftUI**: Not applicable — web-only (platforms: typescript, web).
- **Compose**: Not applicable — web-only (platforms: typescript, web).
- **AppKit / UIKit**: Not applicable — web-only (platforms: typescript, web).
- **WinUI 3**: Not applicable — web-only (platforms: typescript, web).

