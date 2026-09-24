---
id: b1fa768d-a088-4507-92f6-6296f93bee2c
title: Hub Domain Markdown Client
domain: agentictoolkit://recipes/hub-domain-markdown
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Web data-access package bundling the markdown research-document client, its category and tag taxonomy writer, and a legacy storage-bucket schema CRUD client under one folder.
platforms:
- typescript
- web
tags:
- markdown
- taxonomy
- buckets
- schemas
- crud
- web
depends-on: []
related:
- agentictoolkit://recipes/hub-domain-docs
- agentictoolkit://recipes/hub-domain-buckets
references:
- packages/web/packages/data/src/markdown/markdown.ts (agentictoolkit)
- packages/web/packages/data/src/markdown/schemas.ts (agentictoolkit)
- packages/web/packages/data/src/markdown/taxonomy.ts (agentictoolkit)
- packages/web/packages/data/src/markdown/wire.ts (agentictoolkit)
- packages/web/packages/data/src/markdown/index.ts (agentictoolkit)
- packages/web/packages/data/src/markdown/__tests__/markdown.test.ts (agentictoolkit)
- packages/web/packages/data/src/http.ts (agentictoolkit)
- packages/web/packages/data/src/client-helpers.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Hub Domain Markdown Client

## Overview

This package (`packages/web/packages/data/src/markdown/`, re-exported whole by
`index.ts`) is a stateless, non-visual data-access layer with no store, no
cache, and no subscription mechanism — every call issues one request and
resolves or rejects with its result. It bundles three cooperating but
historically distinct clients:

- **`markdownApi`** (`markdown.ts`) is the sole client for a user's markdown
  research papers: list/search, full CRUD, publish/unpublish under a public
  route, and reads of the shared category/tag taxonomy. `docsApi` and the
  notes client are thin corpus-marker lenses over this same client (see
  `hub-domain-docs`); this recipe describes the client they both sit on.
- **`schemasApi`** (`schemas.ts`) is a CRUD client for storage-bucket schema
  definitions and their tables, addressed at `/api/bucket/buckets` and
  `/api/bucket/bucket-types`. Its own header comment states it plainly: this
  is "the EXISTING (pre-FTD) data layer, mechanically repointed to the
  renamed routes/columns so the hub keeps compiling after the buckets DB
  redesign" — it shares this folder with the markdown clients for historical
  reasons, not a domain relationship. The Apple Hub's `BucketsDataSource`
  (see `hub-domain-buckets`) is a separate implementation over the identical
  backend rows, under different model names (`Bucket`/`BucketTable` there,
  `SchemaDefinition`/`SchemaTable` here).
- **`taxonomyApi`** (`taxonomy.ts`) writes to the category/tag taxonomy that
  `markdownApi.categoryTree()`/`.tagSet()` read: rename, file/unfile under a
  parent, and delete (tombstone). It addresses a different backend door
  (the generic CRUD endpoints for categories, category-edges, and keywords)
  than the markdown-specific routes, by the taxonomy.ts header comment's own
  account of why: those operations already address a row by id, and
  re-publishing them on the markdown surface would just be a second
  representation of the generic layer's behavior.
- **`wire.ts`** is a type-only file: the backend row and request-body shapes
  both the Markdown and Buckets surfaces read and send, narrowed from the
  generated OpenAPI schema so this generic client never imports
  product-specific types.

## Behavioral Requirements

### markdown.ts — research documents (list, CRUD, publish, taxonomy reads)

- **research-document-crud-shape**: `markdownApi` MUST expose exactly these
  thirteen operations: `list`, `get`, `create`, `update`, `remove`,
  `routeAvailable`, `publish`, `unpublish`, `categories`, `categoryTree`,
  `createCategory`, `tags`, `tagSet`.
- **workspace-scopes-every-op**: every markdown.ts operation that accepts an
  `opts.workspace` MUST append it to its request URL via `workspaceQuery`;
  the backend uses it to pin the op to that workspace's owning principal
  (list returns only documents that principal owns, create stamps it as
  owner, item ops resolve org-owned documents another member created), and
  an op called without it falls back to the caller's own documents.
- **list-page-size-fixed**: `markdownApi.list` MUST always request the fixed
  `PAGE_SIZE` of 200 rows (`pageSize=200` in the query string) and MUST NOT
  accept or send any cursor, offset, or page-number parameter from the
  caller.
- **list-query-omits-blank-filters**: `listQuery` MUST trim `filters.q`,
  `filters.category`, and `filters.tag` and MUST omit each from the query
  string entirely when the trimmed value is empty, rather than sending an
  empty-string parameter.
- **list-corpus-flags-are-independent**: `opts.noted` and `opts.doc` MUST
  each be sent only when truthy (`noted=true`/`doc=true`), and a `false` or
  absent value is not an instruction to exclude that corpus — per the
  source's own comment, the backend offers no such exclusion set, so a
  falsy flag simply leaves the list unfiltered by corpus.
- **tags-array-guaranteed**: `withTags` MUST return its input unchanged (the
  same object reference) when `tags` is already an array, and MUST
  otherwise return a shallow copy with `tags: []`; `markdownApi.list`,
  `.get`, `.create`, `.update`, `.publish`, and `.unpublish` MUST each run
  their result through `withTags` before resolving, so every document this
  client hands back has an array `tags` field regardless of backend
  version.
- **remove-is-a-204-no-content-call**: `markdownApi.remove` MUST issue its
  DELETE through `authedRequest`, not `authedJson`, and MUST resolve `void`
  with no attempt to parse a response body, matching the backend's 204 No
  Content response.
- **route-availability-excludes-self**: `markdownApi.routeAvailable` MUST GET
  `/api/content/markdown/{id}/route-available/{route}` with both `id` and
  `route` percent-encoded as path segments (each via `enc`) and MUST return
  the backend's `{available, reason}` verdict unchanged; per the source
  comment, the backend's own answer already excludes the document's own
  current route from counting as taken.
- **publish-conflict-mapping**: `markdownApi.publish` MUST POST `{route}` to
  `/api/content/markdown/{id}/publish` and, when the request throws a
  conflict (`isConflict`), MUST discard that error and throw a new `Error`
  whose message is exactly `The route "<route>" is already used by one of
  your papers.` (source uses curly quotes around `<route>`); every other
  thrown error MUST propagate unmodified.
- **create-category-idempotent-on-matching-parents**: re-posting an existing
  category name to `markdownApi.createCategory` is documented as idempotent
  when every `parentIds` entry the call asks for is already one of that
  category's parents, and a 409 otherwise, because a category name is
  unique per owner and this call never re-files an existing category.
- **create-category-conflict-mapping**: on a 409 from
  `POST /api/content/markdown/categories`, `markdownApi.createCategory` MUST
  discard the raw error and throw a new `Error` whose message is exactly `A
  category named "<name>" already exists somewhere else.` (source uses
  curly quotes around `<name>`); every other thrown error MUST propagate
  unmodified.
- **category-tree-degrades-flat**: `categoryNodes(res)` MUST return
  `res.nodes` unchanged (same array reference) whenever it is an array,
  including an empty one, and MUST otherwise rebuild `res.items` (or `[]`
  when that is not an array either) into `MarkdownCategoryNode` rows with
  `id` and `name` both set to the item's name string, `parentIds: []`, and
  `sortOrder` set to the item's index in the array.
- **tag-set-degrades-flat**: `tagNodes(res)` MUST follow the identical rule
  as `categoryNodes`, except a rebuilt row's `id` and `label` are both set
  to the item's label string.
- **errors-propagate-unmodified**: every markdown.ts operation other than
  `publish` and `createCategory` MUST let a thrown error from `authedJson`
  or `authedRequest` propagate to its caller unchanged; no other operation
  catches, wraps, logs, or discards an error.
- **create-body-has-no-title-field**: `CreateMarkdownBody`/`UpdateMarkdownBody`
  MUST NOT carry a `title` field; the backend derives a document's title
  from its content (frontmatter, else the first line) so that one document
  reads the same way in every client.

### schemas.ts — bucket/schema-definition CRUD (legacy pre-FTD Buckets data layer)

- **schemas-api-shape**: `schemasApi` MUST expose exactly five operations:
  `list`, `get`, `create`, `update`, `delete`.
- **schema-definition-derivation**: `toDefinition(bucketRow, allTableRows)`
  MUST build a `SchemaDefinition` whose `id`/`name`/`ecosystemId`/
  `createdAt`/`updatedAt` come from the bucket row, whose `description`
  comes from `bucketRow.metadata.description` (empty string when metadata
  or that field is absent), whose `kind` is `bucketRow.kind ?? "custom"`,
  and whose `tables` is every `BucketTypeRow` whose `bucketId` matches the
  bucket's `id`, mapped to `{id, name, type: sqlTableName}`.
- **list-composes-two-endpoints-unfiltered**: `schemasApi.list` MUST fetch
  the full contents of `/api/bucket/buckets` and `/api/bucket/bucket-types`
  in parallel (`Promise.all`, no server-side filter on either), scope the
  bucket rows to the given `ecosystemId` client-side via `scopeByOwner` when
  one is passed, map each into a `SchemaDefinition`, and return the result
  sorted alphabetically by name via `sortByText` (locale-aware
  `localeCompare`, non-mutating).
- **schema-table-name-precondition-undeclared**: `SchemaTable.name`'s doc
  comment documents a caller precondition ("no spaces") that no code in
  schemas.ts enforces; the only validation this file actually performs on
  table names is `assertUniqueTableNames`'s case-insensitive-trimmed
  duplicate check, so a name containing spaces is accepted and sent to the
  backend as-is.
- **create-rejects-duplicate-table-names-first**: `schemasApi.create` MUST
  call `assertUniqueTableNames(input.tables)` before issuing any network
  request, and that function MUST throw synchronously on the first
  case-insensitive, trimmed duplicate name it finds within the given array,
  with message `Duplicate table name "<name>" in this bucket.` (using the
  trimmed, original-case name).
- **create-conflict-mapping**: on a 409 from the initial
  `POST /api/bucket/buckets`, `schemasApi.create` MUST rethrow via
  `rethrowConflict` with message `A bucket named "<name>" already exists.`;
  every other thrown error at that step MUST propagate unmodified.
- **create-sequential-children-with-rollback**: after the parent bucket is
  created, `schemasApi.create` MUST POST each of `input.tables` to
  `/api/bucket/bucket-types` sequentially (one at a time, not in parallel);
  if any of those POSTs throws, it MUST call `rollbackSchema` — which
  deletes every table row created so far and the parent bucket row via
  `Promise.allSettled`, deliberately swallowing any error from the cleanup
  calls themselves — and MUST then rethrow the original table-creation
  error unchanged, per the source's own stated goal of avoiding "orphaning
  a half-built schema."
- **update-is-a-partial-patch**: `schemasApi.update` MUST build its bucket
  PUT body via `compact({name, metadata})`, sending only the fields that
  were actually given (compact drops `undefined` keys, preserves `null`);
  when the resulting patch is empty, it MUST issue a GET of the bucket
  instead of a PUT.
- **update-table-reconcile-ordering**: when `input.tables` is given,
  `schemasApi.update` MUST first delete (sequentially, each awaited) every
  currently-fetched table whose id is absent from the desired set, and only
  after all of those deletions complete MUST it add or patch the desired
  tables; the source's own comment states this ordering exists because
  running both directions in one batch would race the backend's unique
  `(schema, name)` index.
- **update-table-add-vs-patch**: for each table in `input.tables`,
  `schemasApi.update` MUST POST a new bucket-type when the table's id is
  not among the currently-fetched table ids, and MUST PUT (patching only
  `name` and `sqlTableName`) when the id is present and either field
  differs from the currently-fetched row; a table whose id is present and
  whose `name`/`type` both already match MUST trigger no request at all.
- **update-refetches-final-tables**: `schemasApi.update` MUST re-fetch the
  bucket's tables after all table mutations complete, and MUST build the
  returned `SchemaDefinition` from that re-fetched set, because a newly
  added table's id is minted by the backend and unknown until the insert
  response (or a re-fetch) returns it.
- **delete-removes-children-then-parent**: `schemasApi.delete` MUST fetch
  and delete every table belonging to the bucket (in parallel) before
  deleting the parent bucket row, per the source's own stated reason: "No
  DB-level cascade from buckets to bucket_types."
- **schemas-get-swallows-errors**: NEEDS REVIEW: Not implemented in source. `schemasApi.get` wraps its entire body in a bare `catch { return null; }` with no binding on the caught value at all, so a genuine 404, a 500, a 403, and a network failure are all indistinguishable from "no such schema" to every caller; the contract a lookup-by-id normally offers — a distinct not-found outcome from a transport or server failure — is undefined here, and nothing in the source states which of those cases the `null` return is meant to represent.
- **schemas-update-reconcile-has-no-rollback-or-lock**: NEEDS REVIEW: Not implemented in source. Unlike `create`, which explicitly calls `rollbackSchema` and states its purpose is avoiding an orphaned half-built schema, `schemasApi.update`'s table-reconcile loop (delete-then-add/patch) has no compensating action if a DELETE, POST, or PUT partway through the sequence throws, and no lock or version check against a second, concurrently-running `update` call on the same schema id reading the same "current tables" snapshot; either case can leave a schema's persisted table set permanently inconsistent with what any caller asked for, with no defined recovery path.

### taxonomy.ts — category/tag taxonomy writes (generic CRUD door)

- **taxonomy-ops-not-workspace-scoped**: none of `taxonomyApi`'s seven
  operations MUST accept or send a `workspace` query parameter; per the
  module's own header comment, these tables are scoped by `customer_id` +
  `ecosystem_id` as an ownership stamp rather than by an `owner_kind`/
  `owner_id` column the workspace pin could filter on, so a platform
  principal already addresses any row in their own ecosystem without one.
- **rename-by-id-not-by-name**: `renameCategory` and `renameTag` MUST PUT
  `{name}`/`{label}` to `/api/content/categories/{id}` and
  `/api/content/keywords/{id}` respectively, addressing the row by id so
  that every document or edge already pointing at that id is renamed with
  it, with no separate propagation step.
- **category-parents-fetched-fresh-at-write-time**: `categoryParents(childId)`
  MUST GET `/api/content/category-edges?childId={id}` and return the raw
  edge array; `removeCategoryParent` MUST call it at the moment it writes
  (not accept a caller-supplied snapshot), per the source's own comment,
  because a `MarkdownCategoryNode` carries parent ids but not edge ids, and
  acting on the current links rather than whatever the screen last rendered
  from is a deliberate freshness guarantee.
- **add-category-parent-cycle-and-self-link-rejection**: `addCategoryParent`
  MUST POST `{childId, parentId}` to `/api/content/category-edges`; the
  backend is documented to refuse a link that would close a cycle with a
  409 and a self-link with a 400, and the source's own comment states a
  caller MUST handle both even after filtering its own menu, because "the
  graph it filtered against is a snapshot" that another caller may have
  changed since.
- **remove-category-parent-is-idempotent**: `removeCategoryParent` MUST
  fetch the child's current parent edges, then sequentially DELETE
  (awaiting each) only the edges whose `parentId` matches the given
  `parentId`; when no such edge exists it MUST issue zero DELETE calls and
  resolve without error, so a duplicate call or a retry costs the same as
  one call.
- **delete-category-cascades-server-side**: `deleteCategory` MUST issue
  exactly one DELETE to `/api/content/categories/{id}` and rely on the
  backend's own transaction for the category's cascade: a document under
  the deleted category becomes uncategorized rather than hidden, and a
  child category is transitively retired only when it has no other live
  parent; per the source's comment, because the cascade lives entirely in
  the backend, every caller of this endpoint observes the same rule and a
  concurrent re-filing of the same subtree cannot race a caller's own walk
  of it.
- **delete-tag-tombstone-is-revivable**: `deleteTag` MUST issue exactly one
  DELETE to `/api/content/keywords/{id}`; per the source's comment, because
  a label is unique per owner, later renaming or creating a category with
  that exact label revives the tombstoned row (and its old links) rather
  than minting a new one — the one way a tag's delete differs from a
  category's.

### wire.ts — wire shapes and their invariants

- **category-node-is-a-dag**: `MarkdownCategoryNode.parentIds` MUST be an
  array (`[]` for no parents, never a null sentinel), allowing a category to
  sit under any number of parents at once; the backend is documented to
  filter out parent ids not themselves present in `nodes` and to refuse an
  edge that would close a cycle, so a consumer folding this into a tree is
  guaranteed to terminate.
- **update-body-supports-explicit-null-category**: `MarkdownUpdateBody.category`
  MUST accept `string | null | undefined`, where `null` explicitly clears
  the document's category and `undefined` (an omitted field) leaves it
  unchanged — these are two distinct instructions, not one.
- **route-availability-reason-enum**: `MarkdownRouteAvailability.reason` MUST
  be one of exactly `"ok"`, `"invalid"`, `"reserved"`, or `"taken"`, letting
  a caller distinguish a malformed slug from a site-reserved word from one
  already claimed by another of the author's documents.
- **bucket-metadata-is-narrowed-jsonb**: `BucketRow.metadata` MUST be typed
  as `{description?: string} | null`, a client-side narrowing of the
  backend's untyped jsonb column to exactly the one field this package
  reads (`description`); any other key the backend may store there is
  invisible to this client.

## Appearance

Not applicable — this is a web data-access package for markdown research documents, schema definitions, and taxonomy, not a visual component.

## States

Not applicable — this is a web data-access package for markdown research documents, schema definitions, and taxonomy, not a visual component.

## Accessibility

Not applicable — this is a web data-access package for markdown research documents, schema definitions, and taxonomy, not a visual component.

## Conformance Test Vectors

| ID | Input | Expected Output / Effect | Source |
|----|-------|---------------------------|--------|
| HDM-001 | `withTags({id: "d1", title: "Doc"})` (no `tags` field) | `{id: "d1", title: "Doc", tags: []}` | markdown.test.ts, "defaults a missing tags field to []" |
| HDM-002 | `withTags({id: "d1", tags: null})` | `.tags` resolves to `[]` | markdown.test.ts, "defaults a null tags field to []" |
| HDM-003 | `withTags({id: "d1", tags: ["a", "b"]})` | returns the exact same object reference, unmodified | markdown.test.ts, "passes a real array through unchanged" |
| HDM-004 | `categoryNodes({items: ["Meetings"], nodes: [{id: "c1", name: "Meetings", parentIds: [], sortOrder: 0}]})` | returns the exact same `nodes` array reference | markdown.test.ts, "passes real nodes through unchanged" |
| HDM-005 | `categoryNodes({items: [], nodes: []})` | `[]` (does not rebuild from empty `items`) | markdown.test.ts, "prefers nodes even when they are EMPTY" |
| HDM-006 | `categoryNodes({items: ["Admin", "Meetings", "Reading"]})` (no `nodes`) | `[{id: "Admin", name: "Admin", parentIds: [], sortOrder: 0}, {id: "Meetings", ...sortOrder: 1}, {id: "Reading", ...sortOrder: 2}]` | markdown.test.ts, "rebuilds an older backend's flat names as roots" |
| HDM-007 | `categoryNodes({})` (neither field present) | `[]`, does not throw | markdown.test.ts, "yields [] when NEITHER field is an array" |
| HDM-008 | `tagNodes({items: ["alpha", "beta"]})` (no `nodes`) | `[{id: "alpha", label: "alpha"}, {id: "beta", label: "beta"}]` | markdown.test.ts, "rebuilds an older backend's flat labels" |
| HDM-009 | `markdownApi.routeAvailable("doc 1", "a/b", {workspace: "acme"})` | issues `GET /api/content/markdown/doc%201/route-available/a%2Fb?workspace=acme` | markdown.test.ts, "asks the author-scoped endpoint with both segments encoded" |
| HDM-010 | backend resolves `routeAvailable` with `{available: false, reason: "reserved"}` | `markdownApi.routeAvailable` resolves with that object unchanged | markdown.test.ts, "returns the backend's verdict unchanged" |
| HDM-011 | `markdownApi.publish(id, route)` where the POST throws a conflict (`isConflict`) | throws `Error('The route "<route>" is already used by one of your papers.')`, discarding the original error | markdown.ts, `publish`'s catch block (no dedicated test exercises this branch) |
| HDM-012 | `markdownApi.createCategory({name})` where the POST throws a conflict | throws `Error('A category named "<name>" already exists somewhere else.')` | markdown.ts, `createCategory`'s catch block (no dedicated test) |
| HDM-013 | `schemasApi.create({tables: [{name: "Contacts"}, {name: "contacts"}], ...}, ecosystemId)` | throws `Error('Duplicate table name "contacts" in this bucket.')` before any network request is issued | schemas.ts, `assertUniqueTableNames` (no test file exists for schemas.ts) |
| HDM-014 | `schemasApi.create` succeeds on the parent bucket but the second table's POST throws | calls `rollbackSchema` (deletes the first created table, then the bucket, via `Promise.allSettled`), then rethrows the table-creation error unchanged | schemas.ts, `create`'s catch block (no test file) |
| HDM-015 | `schemasApi.get(id)` where the underlying GET throws any error (404, 500, or a network failure) | resolves `null` in every case, with no way to distinguish which occurred | schemas.ts, `get`'s bare `catch { return null }` — see the open question on schemas-get-swallows-errors |
| HDM-016 | `schemasApi.list(ecosystemId)` with buckets belonging to several ecosystems | resolves only the buckets whose `ecosystemId` matches, sorted alphabetically by name | schemas.ts, `list` (`scopeByOwner` + `sortByText`, no test file) |
| HDM-017 | `taxonomyApi.removeCategoryParent(childId, parentId)` called when no edge with that `parentId` exists for `childId` | resolves with zero DELETE calls issued | taxonomy.ts, `removeCategoryParent`'s own doc comment (no test file exists for taxonomy.ts) |
| HDM-018 | `markdownApi.list({}, {noted: false, doc: false})` | request query string omits both `noted` and `doc` entirely (not sent as `false`) | markdown.ts, `listQuery` |

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

## Configuration

- `ResearchFilters.q` / `.category` / `.tag` — caller-supplied search/filter
  strings for `markdownApi.list`, trimmed before use.
- `MarkdownListOptions.workspace` / `.noted` / `.doc` — caller-supplied
  workspace scope and per-corpus flags for `markdownApi.list`.
- `opts.workspace` — accepted by every other markdown.ts item operation
  (`get`, `create`, `update`, `remove`, `routeAvailable`, `publish`,
  `unpublish`, `categories`, `categoryTree`, `createCategory`, `tags`,
  `tagSet`).
- `ecosystemId` — a plain string parameter (not an `opts` object) accepted
  by `schemasApi.list` and `.create`, scoping which ecosystem's buckets are
  read or which ecosystem a new bucket belongs to.
- taxonomy.ts operations accept no scoping parameter at all; scoping is by
  ownership stamp on the backend side only.
- `PAGE_SIZE` (200) and `BASE` (`/api/content/markdown`) — compiled
  constants in markdown.ts, not configurable by a caller.
- `SCHEMAS` (`/api/bucket/buckets`) and `TABLES` (`/api/bucket/bucket-types`)
  — compiled constants in schemas.ts.
- `CATEGORIES`, `CATEGORY_EDGES`, `KEYWORDS` — compiled route-prefix
  constants in taxonomy.ts.
- the generic CRUD endpoint's roughly 500-row unpaginated cap on
  `schemasApi.list`/`.get` is a backend-side constant this client does not
  expose any way to configure.
- none of the four files read an environment variable or a runtime feature
  toggle.

## Deep Linking

Not applicable: none of the four given sources construct, parse, or resolve a URL beyond the plain path/query strings of their own backend requests.

## Localization

Every user-facing error message this package produces is a hardcoded
English string literal, with no localization hook of any kind:

- `markdownApi.publish`'s conflict message: `The route "<route>" is already
  used by one of your papers.`
- `markdownApi.createCategory`'s conflict message: `A category named
  "<name>" already exists somewhere else.`
- `schemasApi.create`'s conflict message (via `rethrowConflict`): `A bucket
  named "<name>" already exists.`
- `assertUniqueTableNames`'s duplicate-name message: `Duplicate table name
  "<name>" in this bucket.`

## Accessibility Options

Not applicable: this package has no UI and reads no accessibility setting.

## Feature Flags

Not applicable: none of the four given sources reference a feature flag or A/B-test condition.

## Analytics

Not applicable: none of the four given sources emit an analytics or telemetry event.

## Privacy

None of the four files persist anything client-side (there is no local
cache, no storage write, no cookie access); every request body sent is
exactly the caller-supplied input, or its `compact()`-filtered subset for a
`schemasApi.update` PUT, transmitted over whatever transport `authedJson`/
`authedRequest` use (bearer-token HTTP, defined outside these four files).
The data these operations carry — document content and titles, category and
tag names, bucket/table names and descriptions — is user-authored content,
not a credential or token; none of it is retained, transformed, or
forwarded to any destination other than the single backend route each call
targets.

## Logging

Not applicable: none of the four given sources make a logging call of any
kind; every thrown error either propagates to the caller unchanged or, for
`schemasApi.get`, is discarded with nothing written anywhere — see the open
question on schemas-get-swallows-errors.

## Platform Notes

- **SwiftUI / Swift**: a Swift port of markdown.ts/taxonomy.ts has no
  existing Apple counterpart among this repo's sources; the closest
  relative is `MarkdownStore`/`MarkdownRemoteWriter`
  (`packages/apple/AgenticToolkit/Markdown/`), which is a local notes store,
  not a client for this backend surface. A port of `schemasApi` already
  exists as the Apple Hub's `BucketsDataSource`/`BucketsModels`
  (`hub-domain-buckets`) under different model names for the same rows —
  reconcile naming against that recipe rather than reinventing it. Model
  the three clients as non-`Sendable` structs or an `actor` per the
  concurrency guarantees each caller needs, and use `URLSession`/`Codable`
  in place of `authedJson`/`authedRequest`.
- **Jetpack Compose / Kotlin**: use `kotlinx.serialization` for the wire
  shapes and `Retrofit`/`ktor-client` for the HTTP layer; model the
  three-way scoping split (workspace slug, `ecosystemId` parameter, no
  scoping) as three distinct method-parameter shapes rather than one
  shared options object, to keep the divergence visible in the port's own
  type signatures.
- **React / Web (source platform)**: this is the source implementation;
  `authedJson`/`authedRequest` (from `@agentic-toolkit/auth/client` via
  `../http`) and the helpers in `../client-helpers` (`enc`, `compact`,
  `scopeByOwner`, `sortByText`, `workspaceQuery`) are shared with every
  other client in this data package and MUST be reused, not reimplemented.
- **AppKit / UIKit**: the same guidance as SwiftUI applies at the network
  layer (`URLSession`); there is no view-layer concern here since this
  package has no UI.
- **WinUI 3 / .NET**: use `System.Net.Http.HttpClient` for the transport,
  `System.Text.Json` for the wire shapes, `Task`/`async`-`await` for the
  asynchronous operations, and — if a caller needs to observe the result
  set change over time — an `ObservableCollection` wrapped by a view model
  implementing `INotifyPropertyChanged`; this package itself has no
  persistence, so `Windows.Storage` is only relevant to a caller that
  chooses to cache a result, not to this port.

## Design Decisions

**Decision**: bundle `markdownApi`, `schemasApi`, and `taxonomyApi` — two
unrelated domains — under one `markdown/` folder and one `index.ts`.
**Rationale**: schemas.ts's own header comment states this plainly: it is
"the EXISTING (pre-FTD) data layer, mechanically repointed to the renamed
routes/columns so the hub keeps compiling after the buckets DB redesign,"
placed here as a historical accident of a migration, not a domain
relationship to markdown or taxonomy.
**Approved**: pending.

**Decision**: `schemasApi.create` rolls back every table it created plus the
parent bucket if a later table insert fails, but `schemasApi.update`'s
table-reconcile loop has no equivalent compensation.
**Rationale**: `create`'s own comment states the rollback exists to avoid
"orphaning a half-built schema"; `update` has no comment addressing the
same risk for its own multi-step reconcile, which is the asymmetry recorded
as the open question on schemas-update-reconcile-has-no-rollback-or-lock.
**Approved**: pending.

**Decision**: `schemasApi.update`'s table reconcile deletes removed tables
first, awaits them, and only then adds or patches the desired tables,
rather than issuing all the requests in one batch.
**Rationale**: the source's own comment states that batching both
directions would race the backend's unique `(schema, name)` index — e.g.
renaming a table into a name a same-batch delete just freed could 409 if
the insert reaches the database before the delete does.
**Approved**: pending.

**Decision**: `categoryNodes`/`tagNodes` degrade a too-old backend's flat
`items` list into synthetic root nodes (id = name/label) instead of
throwing or returning an empty set.
**Rationale**: the source's comment explains those flat names/labels are
the entire category/tag set such a backend has, so returning `[]` would
blank a rail whose contents arrived in the very same response; the name or
label is the only identity that backend offers and the one every
by-name/by-label filter already uses.
**Approved**: pending.

**Decision**: `SchemaTable.name`'s doc comment documents a "no spaces"
expectation that no code in schemas.ts validates.
**Rationale**: this is a documented but unenforced caller precondition, not
a gap this recipe treats as a contract failure — the only validation the
source actually performs on table names is the case-insensitive duplicate
check in `assertUniqueTableNames`, and it is recorded here as a fact rather
than smoothed over.
**Approved**: pending.

**Decision**: taxonomy writes (rename, file/unfile, delete) go through the
generic CRUD door (`/content/categories`, `/content/category-edges`,
`/content/keywords`) instead of dedicated `/content/markdown/*` routes,
even though `markdownApi.createCategory` posts to the markdown surface.
**Rationale**: the taxonomy.ts header comment states the markdown surface
owns exactly one taxonomy write (category creation) because a nested create
needs the workspace's owning principal resolved for it; every other
taxonomy operation already addresses a row by id, which the generic layer
already does, so republishing them on the markdown surface would just be a
second representation of the same behavior.
**Approved**: pending.

**Decision**: the three clients in this package each use a different
scoping mechanism — `markdownApi` takes a workspace slug via
`opts.workspace`, `schemasApi` takes a plain `ecosystemId` parameter, and
`taxonomyApi` takes no scoping parameter at all.
**Rationale**: each file's own header comment ties this to what its
underlying tables actually support: markdown rows have an
`owner_kind`/`owner_id` column a workspace slug can filter; bucket rows are
owned by an ecosystem directly; and the taxonomy tables carry only a
`customer_id`/`ecosystem_id` ownership stamp with no separate filterable
scope column at all.
**Approved**: pending.

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | best-practices |
| [error-recovery](agenticdevelopercookbook://compliance/reliability#error-recovery) | partial | reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | reliability |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | partial | reliability |
| [error-response-handling](agenticdevelopercookbook://compliance/access-patterns#error-response-handling) | partial | access-patterns |
| [pagination-support](agenticdevelopercookbook://compliance/access-patterns#pagination-support) | failed | access-patterns |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | internationalization |
| [data-minimization](agenticdevelopercookbook://compliance/privacy-and-data#data-minimization) | passed | privacy-and-data |

**separation-of-concerns**: passed. Each of the three domains — research
documents, legacy bucket/schema definitions, and taxonomy writes — is its
own module with its own route constants and its own exported API object,
and wire.ts isolates every backend shape from all three. The one crossing
point, `markdownApi.createCategory` posting to the markdown surface instead
of the generic taxonomy door, is deliberate and documented in taxonomy.ts's
own header comment.

**unit-test-coverage**: partial. markdown.test.ts covers the three pure
fallback helpers (`withTags`, `categoryNodes`, `tagNodes`) and two cases of
`markdownApi.routeAvailable`, but none of `markdownApi`'s other eleven
operations, and schemas.ts and taxonomy.ts have no test file at all.

**explicit-error-handling**: partial. `markdownApi.publish` and
`.createCategory` each catch a 409 and rethrow a friendly message, and
`schemasApi.create` does the same for the parent bucket; every other
markdown.ts/taxonomy.ts operation lets its error propagate unmodified.
`schemasApi.get`, by contrast, catches every error indiscriminately and
discards it — the open question on schemas-get-swallows-errors.

**error-recovery**: partial. `schemasApi.create` has an explicit
compensating rollback (delete every table it created, then the parent
bucket) if a child-table insert fails partway, stating its own goal is
avoiding an orphaned half-built schema. `schemasApi.update`'s table-reconcile
loop has no equivalent path — the open question on
schemas-update-reconcile-has-no-rollback-or-lock.

**data-integrity**: partial. `assertUniqueTableNames` stops a caller from
creating or renaming into a client-side duplicate before any request is
sent, and `update`'s delete-before-add ordering is explicitly sequenced to
avoid racing the backend's unique index. The same operation's reconcile can
still leave a schema with a half-applied set of tables if one request in
the sequence fails, with nothing to detect or repair it — the open question
on schemas-update-reconcile-has-no-rollback-or-lock.

**idempotent-operations**: partial. `removeCategoryParent`, `deleteCategory`,
and `deleteTag` are each documented as safe to call twice, and
`createCategory` re-posting an existing name is documented as idempotent
when every requested parent is already one of its parents. Create/update/
delete on `markdownApi` and `schemasApi` are ordinary POST/PUT/DELETE with
no such guarantee, and `schemasApi.update`'s reconcile step is the one
operation this package documents no idempotency story for at all.

**error-response-handling**: partial. Three call sites (`markdownApi.publish`,
`markdownApi.createCategory`, `schemasApi.create`) map a 409 to a message a
form can show directly; every other call — including taxonomy.ts's own
documented 409/400 cases on `addCategoryParent` — surfaces the raw thrown
error to its caller with no client-side translation.

**pagination-support**: failed. `markdownApi.list` has no cursor or page
parameter — it always requests the fixed 200-row page — and
`schemasApi.list`/`.get` fetch every bucket and bucket-type row with no
filter at all, relying on the generic CRUD endpoint's own roughly 500-row
cap; a workspace or ecosystem past either limit silently loses rows with no
signal that more exist.

**no-hardcoded-strings**: failed. Every user-facing error message this
package produces — the route-conflict message, the category-conflict
message, the duplicate-table-name message, and the bucket-conflict message
— is a hardcoded English literal with no localization hook.

**data-minimization**: passed. None of the four files persist anything
client-side or add fields beyond what each backend route already expects;
every request body sent is exactly the caller-supplied input, or its
`compact()`-filtered subset for a PUT, and no telemetry, analytics, or
logging call reads any of it.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial recipe covering markdown.ts, schemas.ts, taxonomy.ts, and wire.ts. |
