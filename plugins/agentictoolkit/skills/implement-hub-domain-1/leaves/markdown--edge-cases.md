<!-- leaf: implement-hub-domain-1/markdown--edge-cases · source: hub-domain-markdown.md -->

# Hub Domain Markdown Client

**Rules** (cite as `implement-hub-domain-1/markdown--edge-cases#<slug>`):

- `empty-filters-and-opts` MUST
- `whitespace-only-filter-values` MUST
- `corpus-flags-false-is-not-exclude` MUST

## Edge Cases

- **empty-filters-and-opts**: `markdownApi.list()` called with no arguments
  MUST still send `pageSize=200` and nothing else in the query string.
- **whitespace-only-filter-values**: a `filters.q`/`.category`/`.tag` value
  that is non-empty but trims to an empty string MUST be omitted from the
  query string, identically to an absent filter.
- **corpus-flags-false-is-not-exclude**: `opts.noted: false` or
  `opts.doc: false` MUST NOT be read as "exclude this corpus" — the query
  parameter is simply omitted, leaving the list unfiltered by corpus, per
  `MarkdownListOptions`'s own doc comment.
- **markdown-list-page-boundary**: a workspace whose document count exceeds
  the fixed 200-row page has no cursor this client can use to reach the
  remainder; the 201st document onward is simply never returned by `list`.
- **schemas-list-implicit-row-cap**: `schemasApi.list`/`.get` rely on the
  generic CRUD endpoint's own roughly 500-row cap with no client-side
  filter; per the source's comment, this is "fine at settings-page volume"
  but a tenant with more bucket-types than that cap silently loses rows.
- **concurrent-schemas-update-same-id**: two `schemasApi.update` calls
  racing on the same schema id each read their own "current tables"
  snapshot before reconciling; neither detects the other's changes — see
  the open question on schemas-update-reconcile-has-no-rollback-or-lock.
- **schemas-get-error-vs-not-found**: `schemasApi.get` returns `null` for a
  genuinely missing schema and for a transport or server failure alike —
  see the open question on schemas-get-swallows-errors.
- **remove-category-parent-double-call**: calling
  `taxonomyApi.removeCategoryParent` twice in a row for the same
  `(childId, parentId)` pair costs the second call zero DELETE requests,
  by design.
- **delete-category-with-multiply-filed-child**: deleting a category whose
  only child category is also filed under another live parent leaves that
  child untouched and still browsable there.
- **delete-category-with-orphaned-child**: deleting a category whose only
  child category has no other live parent transitively retires that child
  too, inside the backend's own delete transaction.
- **delete-then-recreate-tag**: deleting a tag and later renaming or
  re-creating a category/tag with the exact same label revives the
  tombstoned row (and its prior links) rather than minting a new one,
  because a label is unique per owner.
- **add-category-parent-stale-snapshot**: a caller that has already
  filtered its own "choose a parent" menu against a locally-held graph can
  still receive a 409 (cycle) or 400 (self-link) from `addCategoryParent`,
  because that menu is a snapshot another caller may have changed since.
- **assert-unique-table-names-empty-input**: `assertUniqueTableNames([])`
  is a no-op; the loop has nothing to iterate and no error is thrown.
- **table-name-case-and-whitespace-collision**: two tables named
  `"Contacts "` and `"contacts"` in the same `create`/`update` call collide
  under `assertUniqueTableNames`'s trimmed, case-insensitive comparison and
  raise a client-side error before any request is sent.
