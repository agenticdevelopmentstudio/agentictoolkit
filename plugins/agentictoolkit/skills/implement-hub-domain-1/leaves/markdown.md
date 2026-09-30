<!-- leaf: implement-hub-domain-1/markdown · source: hub-domain-markdown.md -->

**Rules** (cite as `implement-hub-domain-1/markdown#<slug>`):

- `research-document-crud-shape` MUST
- `workspace-scopes-every-op` MUST
- `list-page-size-fixed` MUST
- `list-query-omits-blank-filters` MUST
- `list-corpus-flags-are-independent` MUST
- `tags-array-guaranteed` MUST
- `remove-is-a-204-no-content-call` MUST
- `route-availability-excludes-self` MUST
- `publish-conflict-mapping` MUST
- `create-category-conflict-mapping` MUST
- `category-tree-degrades-flat` MUST
- `tag-set-degrades-flat` MUST
- `errors-propagate-unmodified` MUST
- `create-body-has-no-title-field` MUST

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

