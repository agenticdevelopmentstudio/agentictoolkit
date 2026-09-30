<!-- leaf: implement-general-1/hierarchical-category-browser--edge-cases · source: hierarchical-category-browser.md -->

# Hierarchical Category Browser

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
  rewrites only the filing walked in through
  (#integration-requirements/leave-other-filings-alone-on-move);
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
- **Renaming the currently-open category out from under the URL.** Since
  `slugFor` derives the slug from the CURRENT name, a rename changes the slug the
  instant it lands — see
  #integration-requirements/follow-a-rename-to-the-new-slug. The hook re-selects
  the chain under its new slug as soon as the write succeeds, in the same call
  that also triggers `onChanged`'s refetch, so the already-open level never
  resolves against a slug the rename just invalidated.
- **Deleting the currently-open category.** `chainAfterDelete` finds the deleted
  category ON the chain and truncates there, and the dialog's `onConfirm` navigates
  only once the write has landed. Dropping the LAST segment instead would be the
  same mistake `chainAfterMove` exists to avoid: the gear at depth *d* targets
  `chain[d]`, so deleting a category the user has walked PAST would cut a segment
  off the far end and move them somewhere they never asked to go, while still
  leaving the dead category in the route. Off the chain entirely,
  `chainAfterDelete` returns `null` and the route is left alone.
- **A rename or move onto a contested slug.** `chainAfterRename` and
  `chainAfterMove` both have to predict a slug the next fold has not assigned yet,
  and a slug is only a name until `siblingSlugs` has seen the level. Both go
  through `freeSlugAmong`, which answers exactly when the base slug is free among
  the other siblings and `null` when it is contested (see
  #integration-requirements/not-guess-a-contested-slug).
- **Moving the currently-open category out from under the URL.** Every slug on the
  chain survives a move — but the chain is resolved by WALKING children, so the
  moment the category stops being a child of the parent the URL walked in through,
  that segment and everything below it resolve to nothing. `chainAfterMove` rebuilds
  the route from the pre-move forest (the new parent's own ancestry is not what the
  move changed, so reading it there is exact) and hands it to `onSelectChain` only
  after the write lands
  (#integration-requirements/follow-a-move-to-its-new-place).
