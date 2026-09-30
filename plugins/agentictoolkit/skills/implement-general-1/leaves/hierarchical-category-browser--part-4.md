<!-- leaf: implement-general-1/hierarchical-category-browser--part-4 · source: hierarchical-category-browser.md -->

# Hierarchical Category Browser — continued (part 4)

## Design Decisions

- **Decision**: `useCategoryLevels` is called identically by
  `features/notebook` and `features/research` — same options shape, same
  result shape, same dialogs.
  **Rationale**: The category rail is not "notebook's browser, later adapted
  for research"; it is one shared element two features happen to mount
  (well-factored, decoupled, DRY). A third markdown surface would call the
  same hook unchanged.
  **Approved**: pending
- **Decision**: The walk stops at an empty level; it never publishes one.
  **Rationale**: HTDV treats an empty level as its frontier and stops
  rendering anything past it — publishing one for a childless category would
  silently hide the item list underneath, which is the opposite of what
  selecting a leaf category should do. Stopping the walk one level early is
  simpler than teaching HTDV to skip empty levels, and it keeps the "what
  levels exist" answer entirely local to this hook (separation-of-concerns).
  **Approved**: pending
- **Decision**: All/Uncategorized are synthetic rows, not a filter toggle.
  **Rationale**: They occupy the same list as real categories (same keyboard
  nav, same selection model) rather than a separate control, so "show me
  everything" and "show me the unfiled" are just two more rows to pick — no
  second UI to learn, no second state to keep in sync with the rail's own
  selection.
  **Approved**: pending
- **Decision**: No subcategory count, ever.
  **Rationale**: The spec is explicit that a category row shows only its
  name. A count is a fact ABOUT the rail (how many children a node
  materialised), not about the category, and displaying it would have made
  every row two competing pieces of information instead of one legible name
  (principle-of-least-astonishment: the rail is a place to navigate, not a
  dashboard).
  **Approved**: pending
- **Decision**: The gear reads its target from a plain prop, every render.
  **Rationale**: `CategoryGearMenu` is deliberately dumb (see
  Category Picker's
  sibling components) and the hook feeds it `selectedNode`/`levelParent`
  recomputed in the SAME render that builds `selectedId` — because HTDV's
  `levelsKey` cache ignores `ReactNode` props, a gear that closed over a stale
  target at registration time would act on the wrong category after a rename.
  Keeping the target reachable from a prop that DOES change (`selectedId`) is
  what keeps the gear honest.
  **Approved**: pending
- **Decision**: Add is never disabled by the selection.
  **Rationale**: Every other gear verb acts on the selected ROW; Add acts on
  the level's own category (its parent), which is a property of which level
  you are looking at, not of what is selected within it — so it stays enabled
  with no selection, unlike Rename/Move/Delete.
  **Approved**: pending
- **Decision**: Only the ROOT level sorts.
  **Rationale**: The root is the level with no context to read an order from,
  and the one the spec constrains ("followed by the root categories sorted by
  name") — a top-level list scanned alphabetically is one the owner can find a
  category in without remembering how it was entered. Below it, the order
  that arrives is already meaningful: it is the backend's `sortOrder`, which
  is the owner's own arrangement, and `buildCategoryTree` promises to
  preserve it. Sorting everywhere was one line shorter and made the rail
  contradict both that promise and the
  Category Picker
  rendering the same subtree unsorted beside it.
  **Approved**: pending
- **Decision**: A move writes the new parent edge before removing the old one
  (see #integration-requirements/add-before-remove-on-move).
  **Rationale**: A refused add — a cycle the client-side snapshot could not
  see, caught by the backend's guard — then leaves the category filed where
  it started rather than orphaned at the top level mid-write.
  **Approved**: pending
- **Decision**: A move that only half-lands is made survivable rather than
  silent (see #integration-requirements/refresh-before-surfacing-a-half-move
  and #integration-requirements/skip-an-existing-edge-on-retry).
  **Rationale**: The two edge writes behind a move share no transaction, so
  the add can succeed and the remove fail, leaving the category filed in BOTH
  places, with no single write to roll back.
  **Approved**: pending
