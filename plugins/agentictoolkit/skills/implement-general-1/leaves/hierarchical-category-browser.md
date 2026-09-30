<!-- leaf: implement-general-1/hierarchical-category-browser · source: hierarchical-category-browser.md -->

# Hierarchical Category Browser

## Overview

The **Hierarchical Category Browser** is the shared rail every markdown surface
that classifies its documents into a category hierarchy — the notebook today, and
research — mounts as the leading levels of a
Hierarchical Topic Detail
stack. It is a thin, category-specific layer over that substrate: HTDV owns the stack's
chrome, deep linking, breadcrumb, disclosure and narrow-mode behavior (see
Hierarchical Topic Detail
and Topic Detail for that contract,
which this recipe does not restate). What this recipe adds is everything that is TRUE OF
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
| Category Picker | agenticdevelopertoolkit://recipes/category-picker-dialog | The dialog behind BOTH place-picking gear actions — browses the folded forest and returns a place to file the selected category under. | yes | Move: `confirmLabel="Move"`, `allowRoot`, `rootLabel` = "Top level" or "Remove from “<parent>”" (see #integration-requirements/not-call-an-unfiling-a-rooting), `disabledIds` = the moved category + its own descendants. Also file: `confirmLabel="File"`, `initialSelectedId={null}`, NO `allowRoot` (a root is a category with no parents, so there is nothing to add), `disabledIds` = the category + its descendants + every parent it is ALREADY filed under. |

The other three gear dialogs (Rename, Delete, and the one-field Add) are plain
compositions of the shared `Dialog`/`Input`/`DialogActions`/`AlertModal`
primitives with no dedicated recipe of their own — see
Dialog,
Dialog Actions and
Alert and Dialog for those.
`useCategoryLevels` wires all four; this recipe documents the whole.

