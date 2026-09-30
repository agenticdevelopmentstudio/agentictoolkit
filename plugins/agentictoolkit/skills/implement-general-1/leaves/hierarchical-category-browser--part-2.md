<!-- leaf: implement-general-1/hierarchical-category-browser--part-2 · source: hierarchical-category-browser.md -->

# Hierarchical Category Browser — continued (part 2)

**Rules** (cite as `implement-general-1/hierarchical-category-browser--part-2#<slug>`):

- `mirror-the-hierarchy` MUST
- `not-publish-an-empty-leaf-level` MUST
- `lead-the-root-level-with-all-and-uncategorized` MUST
- `keep-the-backend-order-below-the-root` MUST
- `show-only-the-category-name` MUST
- `offer-a-gear-in-every-level-header` MUST
- `target-the-selected-row` MUST
- `say-what-a-delete-keeps` MUST
- `leave-other-filings-alone-on-move` MUST
- `file-a-category-in-a-second-place` MUST
- `disable-not-hide-an-invalid-file-target` MUST
- `not-navigate-on-file` MUST
- `not-call-an-unfiling-a-rooting` MUST
- `follow-a-move-to-its-new-place` MUST
- `not-navigate-on-a-move-off-chain-or-failed` MUST
- `rederive-the-moved-segment-not-carry-it-over` MUST
- `add-before-remove-on-move` MUST
- `refresh-before-surfacing-a-half-move` MUST
- `skip-an-existing-edge-on-retry` MUST
- `follow-a-rename-to-the-new-slug` MUST
- `not-guess-a-contested-slug` MUST
- `follow-a-delete-to-the-surviving-level` MUST
- `select-by-slug-not-id` MUST
- `clear-to-the-parent-level` MUST

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
  it, and the Category Picker
  browsing the same forest does not sort — so a rail
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
  `removeCategoryParent`. The hierarchy is a DAG (a category may carry any number
  of parents), and Move is the wrong shape for saying "this belongs here too": it
  necessarily removes the filing the user walked in through.
- **disable-not-hide-an-invalid-file-target**: The Also file picker MUST refuse
  the category itself and its own descendants (either would close a cycle the
  backend rejects) and every parent it is already filed under (the edge exists),
  showing those rows disabled rather than hiding them — a place that is missing
  reads as a place that does not exist, while a greyed one says the filing is
  already there.
- **not-navigate-on-file**: Filing MUST NOT navigate: the place the user walked
  in through still holds the category, so the route they are standing on is
  still true.
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
  #integration-requirements/not-call-an-unfiling-a-rooting. This is
  #integration-requirements/follow-a-rename-to-the-new-slug's sibling and for the
  same reason — a move keeps every slug but re-parents the category, so
  `resolveCategoryChain` stops resolving from that segment down and the user who
  re-filed a category is dropped to "All" on a URL that names nothing. Which
  segment moved is decided by the gear's own level, NOT by the frontier: the level
  at depth *d* targets `chain[d]`, which may be far above the deepest selection.
- **not-navigate-on-a-move-off-chain-or-failed**: A move driven from off the
  chain, and one that FAILS, MUST leave the route alone.
- **rederive-the-moved-segment-not-carry-it-over**: The moved category's OWN
  segment MUST be re-derived against its new siblings, never carried over from
  the old chain: slugs are unique per level
  (#integration-requirements/select-by-slug-not-id), so a suffix it only carried
  because of a twin under the parent it is leaving is not its slug under the
  parent it is joining. Only the segments BELOW it carry over unchanged — their
  scope is the moved category's own children, which a move does not reshape.
- **add-before-remove-on-move**: A move MUST write the new parent edge before
  removing the old one, so a refused add — a cycle the client-side snapshot
  could not see, caught by the backend's guard — leaves the category filed
  where it started rather than orphaned at the top level mid-write.
- **refresh-before-surfacing-a-half-move**: The two edge writes behind a move
  share no transaction, so the add can succeed and the remove fail, leaving the
  category filed in BOTH places. When that happens, the rail MUST be refreshed
  before the failure surfaces to the user — a rejection that skipped the refresh
  would show "the move failed" over a tree still drawn from the pre-move forest,
  which displays neither filing.
- **skip-an-existing-edge-on-retry**: A move's add step MUST be skipped when the
  category is already filed under the destination (`node.parentIds` carries every
  filing, in-forest or not) — otherwise a retry after a half-applied move
  reissues an edge that already exists and the move can never be finished.
- **follow-a-rename-to-the-new-slug**: A successful rename of the
  CURRENTLY SELECTED category MUST re-select it under its new slug and update the
  route to match — a rename changes the category's name, and by
  #integration-requirements/select-by-slug-not-id that IS its URL identity, so
  the route the user is standing on expires the instant the write lands. Leaving
  it there drops them to "All" on a URL that no longer resolves, with nothing
  said. Renaming a category that is NOT the current selection MUST leave the
  route alone, and a rename that FAILS MUST leave it alone too. Only the renamed
  segment changes: every descendant's slug comes from its own name, so a deeper
  chain keeps its tail. The new segment is the slug the NEXT fold will assign,
  not `slugFor(newName, id)` on its own — see
  #integration-requirements/not-guess-a-contested-slug.
- **not-guess-a-contested-slug**: A rename or move that lands the category on
  a slug ALREADY claimed by one of its (new) siblings MUST leave the route alone
  rather than navigate. Slugs are de-collided per level and the first claimant keeps
  the bare slug (#integration-requirements/select-by-slug-not-id), so which of two twins keeps it
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
- **clear-to-the-parent-level**: A level at depth *d*'s `onClear` (re-click of
  the selected row, or a breadcrumb-up through HTDV) MUST re-select
  `chain.slice(0, d)` — this level's own ancestors, dropping its own selection —
  not the whole chain: it walks up one level at a time, the same as the level
  walk went down.

