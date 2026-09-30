<!-- leaf: implement-hub-domain-1/docs · source: hub-domain-docs.md -->

**Rules** (cite as `implement-hub-domain-1/docs#<slug>`):

- `doc-type-aliases` MUST
- `taxonomy-type-aliases` MUST
- `doc-marker-on-create` MUST
- `create-body-retains-note-field` MUST
- `create-may-double-file` MAY
- `list-scoped-to-doc-marker` MUST
- `id-ops-not-scoped-to-marker` MUST
- `update-fields-only` MUST
- `remove-is-void` MUST
- `workspace-scopes-list-and-crud-ops` MUST
- `taxonomy-ops-not-workspace-scoped` MUST
- `categories-share-vocabulary` MUST
- `category-tree-degrades-flat` MUST
- `tag-set-degrades-flat` MUST
- `create-category-conflict-message` MUST
- `errors-propagate-unmodified` MUST
- `tags-array-guaranteed` MUST
- `list-page-size-fixed` MUST
- `stateless-client` MUST
- `create-not-idempotent` MUST
- `no-client-side-retry` MUST

# Docs Client

## Overview

`docsApi` (`packages/web/packages/data/src/docs/docs.ts`, re-exported by
`docs/index.ts`) is a **logic** component — no visual surface. It is the
third lens on the shared markdown-document surface, alongside `notesApi` and
the plain research-paper use of `markdownApi` itself. A doc IS a markdown
document — same row shape, same category/tag taxonomy, same CRUD routes
(`/content/markdown`) — and what makes a document a doc is a `content.docs`
storage-bucket MARKER, minted by sending `doc: true` on create and read back
by filtering `list` with the same flag. `docsApi` exists only to bake that
marker in so a caller cannot forget it; every operation it exposes forwards
directly to `markdownApi` (list/get/create/update/remove/categoryTree/
createCategory/tags/tagSet) or re-exports `taxonomyApi` unchanged for
renaming, filing, unfiling and retiring the categories and tags that
`docsApi.categories`/`docsApi.tagSet` read. `docsApi` itself contains no
HTTP call, no wire-shape knowledge, and no taxonomy logic of its own.

## Behavioral Requirements

- **doc-type-aliases**: `Doc`, `DocSummary`, and `DocFilters` MUST be
  structural aliases of `ResearchDocument` (`MarkdownDocumentRow`:
  `id`, `title`, `content`, `category?`, `tags: string[]`,
  `visibility: "private" | "public"`, `publicRoute?`), `ResearchSummary`
  (`MarkdownDocumentSummaryRow`: the same fields minus `content`, plus an
  optional `excerpt`), and `ResearchFilters` (`q?`, `category?`, `tag?`)
  respectively — `docsApi` MUST NOT define its own document, summary, or
  filter shape.
- **taxonomy-type-aliases**: `DocCategory` and `DocTag` MUST be structural
  aliases of `MarkdownCategoryNode` (`id`, `name`, `parentIds: string[]`,
  `sortOrder`) and `MarkdownKeywordNode` (`id`, `label`) respectively.
- **doc-marker-on-create**: `docsApi.create` MUST call `markdownApi.create`
  with `doc: true` merged into the caller's `body`, unconditionally, so
  every document `docsApi.create` mints is filed in the docs bucket.
- **create-body-retains-note-field**: `CreateDocBody` MUST be
  `Omit<CreateMarkdownBody, "doc">`, which removes only `doc` and leaves the
  optional `note` field from `CreateMarkdownBody` present on its type.
- **create-may-double-file**: A caller MAY set `note: true` on the body
  passed to `docsApi.create`; because `create-body-retains-note-field`
  leaves that field on the type and `doc-marker-on-create` always adds
  `doc: true`, the resulting `markdownApi.create` call MAY carry both
  markers, filing the new document in the notes bucket in addition to the
  docs bucket.
- **list-scoped-to-doc-marker**: `docsApi.list` MUST call `markdownApi.list`
  with `doc: true` merged into (and after) the caller's `opts`, so the
  returned `DocSummary[]` is restricted to documents carrying the docs
  marker.
- **id-ops-not-scoped-to-marker**: `docsApi.get`, `docsApi.update`, and
  `docsApi.remove` MUST forward their `id` and `opts` to the matching
  `markdownApi` operation with no `doc` field attached, and MUST therefore
  be able to read, edit, or delete any markdown document by id, whether or
  not it carries the docs marker — the marker filters what `list` returns,
  not what `get`/`update`/`remove` may address.
- **update-fields-only**: `docsApi.update`'s body type, `UpdateDocBody`, MUST
  be `UpdateMarkdownBody` unmodified (`content?`, `category?`, `tags?`); it
  MUST NOT carry a `doc`/`note` field, so an update call MUST NOT alter
  which bucket marker(s) a document has.
- **remove-is-void**: `docsApi.remove` MUST resolve to `void` and MUST NOT
  attempt to parse a response body, because `markdownApi.remove` issues the
  DELETE with `authedRequest` (not `authedJson`) against a 204 No Content
  response.
- **workspace-scopes-list-and-crud-ops**: `docsApi.list`, `get`, `create`,
  `update`, `remove`, `categories`, `createCategory`, `tags`, and `tagSet`
  MUST accept an optional `opts.workspace` and, when given, MUST forward it
  unchanged to the underlying `markdownApi` call, pinning the operation to
  that workspace's owning principal rather than the caller's own.
- **taxonomy-ops-not-workspace-scoped**: The re-exported `taxonomyApi`
  (`renameCategory`, `categoryParents`, `addCategoryParent`,
  `removeCategoryParent`, `deleteCategory`, `renameTag`, `deleteTag`) MUST
  NOT accept or send a `workspace` parameter on any of its seven operations,
  because the categories/category-edges/keywords tables they address are
  scoped by `customer_id`/`ecosystem_id` ownership, not by an
  `owner_kind`/`owner_id` column a workspace slug could narrow.
- **categories-share-vocabulary**: `docsApi.categories`, `createCategory`,
  `tags`, and `tagSet` MUST read and write the same category and tag rows a
  workspace's notes and other research documents use; there is no
  docs-only taxonomy.
- **category-tree-degrades-flat**: `docsApi.categories` MUST return
  whatever `categoryNodes()` computes: the backend's `nodes` array when the
  response carries one (even when it is empty), otherwise the backend's
  flat `items` name list rebuilt as root-level nodes
  (`id` and `name` both set to the name, `parentIds: []`, `sortOrder` set to
  the array index) in the order the backend sent them.
- **tag-set-degrades-flat**: `docsApi.tagSet` MUST return whatever
  `tagNodes()` computes: the backend's `nodes` array when present (even
  empty), otherwise the backend's flat `items` label list rebuilt with each
  row's `id` set to its own label.
- **create-category-conflict-message**: `docsApi.createCategory` MUST
  propagate `markdownApi.createCategory`'s mapping of a backend 409 to
  `Error('A category named "<name>" already exists somewhere else.')`
  (with `<name>` the requested category's `name`); every other rejection
  from that call MUST propagate unchanged.
- **errors-propagate-unmodified**: Except for `create-category-conflict-message`,
  every `docsApi` operation MUST propagate the exact error `authedJson` or
  `authedRequest` throws — network failure, a non-2xx status, or a
  JSON-parse failure — to its caller unmodified; neither `docsApi` nor
  `markdownApi`'s `list`/`get`/`create`/`update`/`remove` contains a
  `try`/`catch` of its own.
- **tags-array-guaranteed**: Every `Doc`/`DocSummary` returned by
  `docsApi.get`, `create`, `update`, or the rows in `list`'s result MUST
  have a `tags` array — never `undefined` or `null` — because
  `markdownApi` runs every such response through `withTags`, which defaults
  a missing or `null` tags field to `[]` while passing a real array through
  by reference, unchanged.
- **list-page-size-fixed**: `docsApi.list` MUST request `markdownApi`'s
  fixed page size of 200 rows on every call; it accepts no page-size or
  cursor parameter and performs no follow-up fetch, so a workspace with
  more than 200 documents matching the doc marker and filters MUST receive
  only the first 200, with no indication that more exist.
- **stateless-client**: `docsApi` MUST hold no local state, cache, or
  mutable field of its own; every operation issues exactly one HTTP
  request through `markdownApi`/`taxonomyApi` and its result depends only
  on that request's response.
- **create-not-idempotent**: `docsApi.create` MUST NOT deduplicate,
  coalesce, or queue concurrent or repeated calls with identical bodies —
  each call MUST result in one independent POST and therefore one new
  document with its own id.
- **no-client-side-retry**: `docsApi` MUST NOT retry a failed request; a
  rejected `authedJson`/`authedRequest` promise MUST reject the
  corresponding `docsApi` call exactly once, with no backoff or automatic
  replay attempted by this component.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `filters.q` | `string` | `undefined` | Free-text filter forwarded to `markdownApi.list`; trimmed, and omitted from the request when blank or absent. |
| `filters.category` | `string` | `undefined` | Exact category-name filter; trimmed, omitted when blank or absent. |
| `filters.tag` | `string` | `undefined` | Exact tag filter; trimmed, omitted when blank or absent. |
| `opts.workspace` | `string` | `undefined` | Owning workspace slug. When set, scopes `list`/`get`/`create`/`update`/`remove`/`categories`/`createCategory`/`tags`/`tagSet` to that workspace's principal instead of the caller's own. Not accepted by any `taxonomyApi` operation. |
| doc marker | `boolean` | `true` (fixed) | Always merged in by `list` and `create`; not exposed as a caller-supplied option. |
| page size | `number` | `200` (fixed, from `markdownApi`'s `PAGE_SIZE`) | Not exposed as a parameter; every `list` call requests exactly this many rows with no cursor. |

## Localization

`docsApi.createCategory` surfaces a hardcoded English error string on a
name conflict — `A category named "<name>" already exists somewhere
else.` (`create-category-conflict-message`) — with no lookup table or
locale parameter anywhere in `docs.ts` or the `markdownApi.createCategory`
call it forwards to. This is the only user-facing string this component
introduces; every other error this component's operations can produce is
whatever `authedJson`/`authedRequest` throws, defined outside this file.

## Privacy

- **Data collected**: None beyond what the caller explicitly supplies —
  `content`, `category`, `tags`, and (per `create-may-double-file`)
  `note` — plus the fixed `doc: true` marker this client always adds on
  create. No field is appended that the caller did not provide or that this
  recipe's other requirements do not already name.
- **Storage**: None client-side. `docsApi` holds no cache and no local
  copy of any document, category, or tag (`stateless-client`); all
  persistence is the backend's.
- **Transmission**: Every request travels through `authedJson`/
  `authedRequest` (`packages/web/packages/data/src/http.ts`, itself
  re-exporting `@agentic-toolkit/auth/client`), the same bearer-token
  authenticated channel every other data client in this package uses;
  `docs.ts` adds no transmission of its own and performs no additional
  encryption, redaction, or inspection of the document content it sends.
- **Retention**: Not controlled at this layer. `docsApi.remove` performs a
  soft delete on the backend (per the module comment: "the backend
  tombstones the doc marker with the document"); how long a tombstoned row
  is retained is a backend policy this client has no visibility into.

