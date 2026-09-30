<!-- leaf: implement-hub-domain-1/notes · source: hub-domain-notes.md -->

**Rules** (cite as `implement-hub-domain-1/notes#<slug>`):

- `note-type-aliases` MUST
- `taxonomy-type-aliases` MUST
- `note-marker-on-create` MUST
- `create-body-retains-doc-field` MUST
- `create-may-double-file` MAY
- `list-scoped-to-noted-marker` MUST
- `list-opts-type-hides-corpus-flags` MUST
- `id-ops-not-scoped-to-marker` MUST
- `update-fields-only` MUST
- `remove-is-void` MUST
- `workspace-scopes-every-op` MUST
- `org-workspace-note-ownership` MUST
- `taxonomy-re-exported-unchanged` MUST
- `taxonomy-ops-not-workspace-scoped` MUST
- `categories-share-vocabulary` MUST
- `categories-returns-tree-not-flat-names` MUST
- `category-tree-degrades-flat` MUST
- `tags-returns-flat-labels` MUST
- `tag-set-degrades-flat` MUST
- `create-category-conflict-message` MUST
- `errors-propagate-unmodified` MUST
- `tags-array-guaranteed` MUST
- `list-page-size-fixed` MUST
- `device-sync-surface-unused` MUST
- `stateless-client` MUST
- `create-not-idempotent` MUST
- `no-client-side-retry` MUST

# Notes Client

## Overview

`notesApi` (`packages/web/packages/data/src/notes/notes.ts`, re-exported
whole by `notes/index.ts`) is a **logic** component — no visual surface. Per
the module's own header comment, a note IS a markdown document: same row
shape, same version history, same relational category/tags as every other
research document `markdownApi` serves. What makes a document a note is a
`content.notes` storage-bucket MARKER — filed by sending `note: true` on
create and read back by filtering `list` with the same flag. `notesApi`
exists only to bake that marker in so a caller cannot forget it: "this
client is `markdownApi` with the marker baked in — `noted` on the way out,
`note: true` on the way in — and nothing else." It is one of three lenses
over the shared markdown-document surface, alongside `docsApi`
(`hub-domain-docs`, the `content.docs` marker) and the plain research-paper
use of `markdownApi` itself (`hub-domain-markdown`); this recipe describes
only the marker lens `notes.ts` adds, not the underlying client's own
behavior, which the sibling `hub-domain-markdown` recipe already covers.
`notesApi` contains no HTTP call, no wire-shape knowledge, and no taxonomy
logic of its own — every operation forwards directly to `markdownApi` or
re-exports `taxonomyApi` unchanged.

The module comment also records a deliberately unused alternative: a
`/content/notes` backend surface exists, but it is "the device-SYNC marker
surface — content only, no title/category/tags, no workspace — and it has
no web consumer," and this client is documented as never calling it.

## Behavioral Requirements

- **note-type-aliases**: `Note`, `NoteSummary`, and `NoteFilters` MUST be
  direct type aliases of `ResearchDocument`, `ResearchSummary`, and
  `ResearchFilters` respectively (themselves aliases of
  `MarkdownDocumentRow`, `MarkdownDocumentSummaryRow`, and the `q`/
  `category`/`tag` filter shape) — `notes.ts` MUST NOT declare its own
  document, summary, or filter fields.
- **taxonomy-type-aliases**: `NoteCategory` and `NoteTag` MUST be direct type
  aliases of `MarkdownCategoryNode` (`id`, `name`, `parentIds: string[]`,
  `sortOrder`) and `MarkdownKeywordNode` (`id`, `label`) respectively.
- **note-marker-on-create**: `notesApi.create` MUST call `markdownApi.create`
  with `note: true` merged into the caller's `body`, unconditionally, so
  every note `notesApi.create` mints is filed in the notes bucket.
- **create-body-retains-doc-field**: `CreateNoteBody` MUST be
  `Omit<CreateMarkdownBody, "note">`, which removes only `note` and leaves
  the optional `doc` field from `CreateMarkdownBody` present on its type.
- **create-may-double-file**: A caller MAY set `doc: true` on the body
  passed to `notesApi.create`; because `create-body-retains-doc-field`
  leaves that field on the type and `note-marker-on-create` always adds
  `note: true`, the resulting `markdownApi.create` call MAY carry both
  markers, filing the new document in the docs bucket in addition to the
  notes bucket — per `markdown.ts`'s own comment, "nothing in the schema
  stops one text from sitting on both shelves."
- **list-scoped-to-noted-marker**: `notesApi.list` MUST call
  `markdownApi.list` with the caller's `opts` spread first and `noted: true`
  set after, so the merged flag always wins and the returned
  `NoteSummary[]` is restricted to documents carrying the notes marker.
- **list-opts-type-hides-corpus-flags**: `notesApi.list`'s public `opts`
  parameter type MUST expose only `workspace`, never `noted` or `doc`, so a
  caller of this lens cannot set or unset either corpus flag directly —
  only `notesApi.list`'s own forced `noted: true` reaches
  `markdownApi.list`.
- **id-ops-not-scoped-to-marker**: `notesApi.get`, `.update`, and `.remove`
  MUST forward their `id` and `opts` to the matching `markdownApi` operation
  with no `note` field attached, and MUST therefore be able to read, edit,
  or delete any markdown document by id, whether or not it carries the
  notes marker — the marker filters what `list` returns and what `create`
  stamps, not what `get`/`update`/`remove` may address.
- **update-fields-only**: `notesApi.update`'s body type, `UpdateNoteBody`,
  MUST be `UpdateMarkdownBody` unmodified (`content?`, `category?`,
  `tags?`); it MUST NOT carry a `note`/`doc` field, so an update call MUST
  NOT alter which bucket marker(s) a document has.
- **remove-is-void**: `notesApi.remove` MUST resolve to `void` and MUST NOT
  attempt to parse a response body, because `markdownApi.remove` issues the
  DELETE through `authedRequest` (not `authedJson`) against a 204 No
  Content response; per `notes.ts`'s own comment, this is a "soft-delete"
  where "the backend tombstones the note marker with the document."
- **workspace-scopes-every-op**: `notesApi.list`, `.get`, `.create`,
  `.update`, `.remove`, `.categories`, `.createCategory`, `.tags`, and
  `.tagSet` MUST each accept an optional `opts.workspace` and, when given,
  MUST forward it unchanged to the underlying `markdownApi` call — per
  `notesApi`'s own comment, this "pins every op to that workspace's owning
  principal, exactly as it does for research: list returns the notes that
  principal OWNS, create stamps it as owner."
- **org-workspace-note-ownership**: for an org workspace, an org-owned note
  MUST be treated as an ordinary org-owned document whose marker carries
  only its creator's stamp; per `notesApi`'s own comment, "this is the
  whole of the ownership story today — org-SHARED note semantics are still
  undesigned" beyond that stamp.
- **taxonomy-re-exported-unchanged**: `notesApi` MUST NOT fold any
  `taxonomyApi` operation (`renameCategory`, `categoryParents`,
  `addCategoryParent`, `removeCategoryParent`, `deleteCategory`,
  `renameTag`, `deleteTag`) into itself; `notes.ts` MUST re-export
  `taxonomyApi` from `../markdown/taxonomy` as a separate object, per its
  own comment: "the taxonomy is NOT the notebook's — one owner has one
  vocabulary spanning notes, research papers and board cards, so a rename
  here is a rename there."
- **taxonomy-ops-not-workspace-scoped**: none of the re-exported
  `taxonomyApi`'s seven operations MUST accept or send a `workspace`
  parameter, because the categories/category-edges/keywords tables they
  address carry a `customer_id`/`ecosystem_id` ownership stamp rather than
  an `owner_kind`/`owner_id` column a workspace slug could narrow.
- **categories-share-vocabulary**: `notesApi.categories`, `.createCategory`,
  `.tags`, and `.tagSet` MUST read and write the same category and tag rows
  a workspace's research documents and docs use; there is no notes-only
  taxonomy.
- **categories-returns-tree-not-flat-names**: `notesApi.categories` MUST
  call `markdownApi.categoryTree`, not `markdownApi.categories`; its
  resolved value MUST be `NoteCategory[]` node rows (`id`, `name`,
  `parentIds`, `sortOrder`), never the plain `string[]` name list
  `markdownApi.categories` returns from the same category set.
- **category-tree-degrades-flat**: `notesApi.categories` MUST return
  whatever `categoryNodes()` computes from the backend's categories
  response: the backend's `nodes` array when the response carries one (even
  when it is empty), otherwise the backend's flat `items` name list rebuilt
  as root-level nodes (`id` and `name` both set to the name, `parentIds:
  []`, `sortOrder` set to the array index) in the order the backend sent
  them.
- **tags-returns-flat-labels**: `notesApi.tags` MUST call `markdownApi.tags`
  and resolve the backend's flat `items` label list (`string[]`) unchanged
  — it MUST NOT run the response through `tagNodes` and MUST NOT resolve
  `NoteTag` rows.
- **tag-set-degrades-flat**: `notesApi.tagSet` MUST call
  `markdownApi.tagSet` and return whatever `tagNodes()` computes: the
  backend's `nodes` array when present (even empty), otherwise the
  backend's flat `items` label list rebuilt with each row's `id` set to its
  own label.
- **create-category-conflict-message**: `notesApi.createCategory` MUST
  propagate `markdownApi.createCategory`'s mapping of a backend 409 to
  `Error` with message exactly `A category named "<name>" already exists
  somewhere else.` (with `<name>` the requested category's `name`); every
  other rejection from that call MUST propagate unchanged.
- **errors-propagate-unmodified**: except for
  `create-category-conflict-message`, every `notesApi` operation MUST
  propagate the exact error `authedJson` or `authedRequest` throws —
  network failure, a non-2xx status, or a JSON-parse failure — to its
  caller unmodified; `notes.ts` contains no `try`/`catch` of its own.
- **tags-array-guaranteed**: every `Note`/`NoteSummary` returned by
  `notesApi.get`, `.create`, `.update`, or the rows in `.list`'s result MUST
  have a `tags` array — never `undefined` or `null` — because `markdownApi`
  runs every such response through `withTags`, which defaults a missing or
  `null` tags field to `[]` while passing a real array through by
  reference, unchanged.
- **list-page-size-fixed**: `notesApi.list` MUST request `markdownApi`'s
  fixed page size of 200 rows on every call; it accepts no page-size or
  cursor parameter and performs no follow-up fetch, so a workspace with
  more than 200 documents matching the notes marker and filters MUST
  receive only the first 200, with no indication that more exist.
- **device-sync-surface-unused**: `notesApi` and every operation it
  delegates to MUST issue requests only against `markdownApi`'s
  `/api/content/markdown` base path; per `notes.ts`'s own comment, the
  separate `/content/notes` device-sync marker surface exists on the
  backend but "has no web consumer" and "is deliberately not what this
  client talks to."
- **stateless-client**: `notesApi` MUST hold no local state, cache, or
  mutable field of its own; every operation issues exactly one HTTP request
  through `markdownApi`/`taxonomyApi` and its result depends only on that
  request's response.
- **create-not-idempotent**: `notesApi.create` MUST NOT deduplicate,
  coalesce, or queue concurrent or repeated calls with identical bodies —
  each call MUST result in one independent POST and therefore one new
  document with its own id.
- **no-client-side-retry**: `notesApi` MUST NOT retry a failed request; a
  rejected `authedJson`/`authedRequest` promise MUST reject the
  corresponding `notesApi` call exactly once, with no backoff or automatic
  replay attempted by this component.

