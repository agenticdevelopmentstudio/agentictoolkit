---
id: c68fdd3a-092a-4718-b16e-4cc7a0037edd
title: Notes Client
domain: agentictoolkit://cookbook/data/notes
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Thin corpus-marker lens over the shared markdown-document client: stamps/filters
  the notes bucket marker, renames its category tree, re-exports shared taxonomy.'
platforms:
- typescript
- web
tags:
- notes
- markdown
- taxonomy
- crud
- web
depends-on: []
related:
- agentictoolkit://cookbook/data/markdown
- agentictoolkit://cookbook/data/docs
references:
- packages/web/packages/data/src/notes/notes.ts (agentictoolkit)
- packages/web/packages/data/src/notes/index.ts (agentictoolkit)
- packages/web/packages/data/src/markdown/markdown.ts (agentictoolkit)
- packages/web/packages/data/src/markdown/wire.ts (agentictoolkit)
- packages/web/packages/data/src/markdown/taxonomy.ts (agentictoolkit)
- packages/web/packages/data/src/markdown/__tests__/markdown.test.ts (agentictoolkit)
- packages/web/packages/data/src/http.ts (agentictoolkit)
- packages/web/packages/data/src/client-helpers.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

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

## Appearance

Not applicable — this is a data client (a stateless collection of async functions over HTTP), not a visual component.

## States

Not applicable — this is a data client, not a visual component; the one runtime distinction available, a resolved value versus a rejected promise, is captured under Behavioral Requirements, not a visual-state table.

## Accessibility

Not applicable — this is a data client (a stateless collection of async functions over HTTP), not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| HDN-001 | list-scoped-to-noted-marker | `notesApi.list({}, { workspace: "acme" })` | Underlying call is `markdownApi.list({}, { workspace: "acme", noted: true })`, producing the query string `/api/content/markdown?pageSize=200&noted=true&workspace=acme` |
| HDN-002 | note-marker-on-create | `notesApi.create({ content: "# Hello" })` | The POST body sent by `markdownApi.create` is `JSON.stringify({ content: "# Hello", note: true })` |
| HDN-003 | create-body-retains-doc-field, create-may-double-file | `notesApi.create({ content: "x", doc: true } as CreateNoteBody)` | The POST body is `{ content: "x", doc: true, note: true }` — both markers set on one create call |
| HDN-004 | id-ops-not-scoped-to-marker | `notesApi.get("doc-only-id")`, where the document at that id was created with `doc: true` and no `note` marker | Resolves with that document's full row (no marker check is performed; the call carries no `note` field at all) |
| HDN-005 | tags-array-guaranteed | Backend responds to `notesApi.create`'s POST with `{ id: "d1", title: "T", content: "x", category: null, visibility: "private" }` (no `tags` key) | Resolved `Note.tags` equals `[]`, per `markdown.test.ts`'s `withTags` case "defaults a missing tags field to []" |
| HDN-006 | categories-returns-tree-not-flat-names, category-tree-degrades-flat | Backend answers `GET /api/content/markdown/categories` with `{ items: ["Admin", "Meetings"] }` (no `nodes` key) | `notesApi.categories()` resolves to `[{ id: "Admin", name: "Admin", parentIds: [], sortOrder: 0 }, { id: "Meetings", name: "Meetings", parentIds: [], sortOrder: 1 }]`, per `markdown.test.ts`'s "rebuilds an older backend's flat names as roots, in the order it sent them" |
| HDN-007 | tags-returns-flat-labels | Backend answers `GET /api/content/markdown/tags` with `{ items: ["draft", "final"], nodes: [{ id: "k1", label: "draft" }, { id: "k2", label: "final" }] }` | `notesApi.tags()` resolves to the plain array `["draft", "final"]` — the `nodes` field is ignored, unlike `tagSet` |
| HDN-008 | tag-set-degrades-flat | Backend answers `GET /api/content/markdown/tags` with `{ items: ["draft", "final"] }` (no `nodes` key) | `notesApi.tagSet()` resolves to `[{ id: "draft", label: "draft" }, { id: "final", label: "final" }]`, per `markdown.test.ts`'s tag-node fallback case |
| HDN-009 | create-category-conflict-message | Backend responds 409 to `POST /api/content/markdown/categories` for `{ name: "Meetings" }` | `notesApi.createCategory({ name: "Meetings" })` rejects with `Error` whose message is exactly `A category named "Meetings" already exists somewhere else.` |
| HDN-010 | remove-is-void | Backend responds 204 to `DELETE /api/content/markdown/{id}` | `notesApi.remove(id)` resolves to `undefined`; no `authedJson` call (and therefore no response-body parse) occurs for this operation |
| HDN-011 | taxonomy-ops-not-workspace-scoped | `taxonomyApi.renameCategory("c1", "Renamed")` | The request URL is `/api/content/categories/c1` with no `?workspace=` query segment, regardless of any workspace context the caller may be in |
| HDN-012 | list-page-size-fixed | A workspace has 250 documents matching the notes marker and the given filters | `notesApi.list()` resolves with exactly 200 `NoteSummary` rows; the 201st through 250th are omitted with no cursor or "more available" signal in the result |
| HDN-013 | errors-propagate-unmodified | Backend responds 404 to `GET /api/content/markdown/{id}` | `notesApi.get(id)` rejects with the same error `authedJson` threw (a status-404 `Error`); `notesApi` performs no remapping |
| HDN-014 | categories-returns-tree-not-flat-names | Backend answers `GET /api/content/markdown/categories` with `{ items: ["Meetings"], nodes: [{ id: "c1", name: "Meetings", parentIds: [], sortOrder: 0 }] }` | `notesApi.categories()` resolves to the exact same `nodes` array reference — a `NoteCategory` row, never the bare string `"Meetings"` that `markdownApi.categories()` would resolve from the identical backend endpoint |

## Edge Cases

- **Empty filters object.** `notesApi.list({})` MUST return every note-marked document in the (optionally workspace-scoped) corpus: `q`, `category`, and `tag` are all omitted from the query string when absent, per `markdown.ts`'s `listQuery`.
- **Blank-string filter values.** `notesApi.list({ q: " " })` MUST behave identically to `notesApi.list({})`: `listQuery` trims each filter and omits it from the query string when the trimmed value is empty.
- **Empty-string id.** `notesApi.get("")`, `.update("", ...)`, and `.remove("")` MUST encode the id via `encodeURIComponent` and send the resulting request unchanged — this client performs no non-empty validation on `id` before building the URL; whatever status the backend returns for that malformed path MUST propagate per `errors-propagate-unmodified`.
- **Create with only `content`.** `notesApi.create({ content: "x" })` MUST send a body with `category` and `tags` both absent (the caller's choice, not a client default); if the backend's response also omits `tags`, the resolved `Note.tags` MUST still be `[]` per `tags-array-guaranteed`.
- **Boundary: exactly 200 matching notes.** `notesApi.list` MUST return all 200 rows in one call.
- **Boundary: 201st matching note.** MUST be silently omitted from the result, per `list-page-size-fixed`.
- **Re-creating an existing category under the same parents.** Per `markdown.ts`'s comment on `createCategory`, this MUST succeed idempotently (no 409) when every parent requested is already one of that category's current parents.
- **Re-creating an existing category under a different, conflicting set of parents.** MUST reject with the mapped 409 message described in `create-category-conflict-message`.
- **Concurrent access: two `notesApi.create` calls fired without awaiting between them.** Per `stateless-client` and `create-not-idempotent`, each call MUST independently POST and MUST resolve to a distinct document with its own id; neither call MUST observe or be blocked by the other.
- **Concurrent access: `taxonomyApi.removeCategoryParent` racing `taxonomyApi.addCategoryParent` on the same category.** `removeCategoryParent` reads the category's current parent edges, then deletes the ones matching the given `parentId`, in two separate requests; a parent link added by a concurrent `addCategoryParent` call after that read completes MUST NOT be included in the delete loop, because the read is a snapshot (documented in `taxonomy.ts`'s module comment on the same snapshot property for `addCategoryParent`).
- **Error state: backend unreachable.** Any `notesApi` operation's `authedJson`/`authedRequest` call rejecting with a network error MUST propagate that rejection unmodified, per `errors-propagate-unmodified` and `no-client-side-retry` — no retry is attempted.
- **Error state: non-2xx status other than the mapped 409.** A 403, 404, or 500 from any operation other than `createCategory` MUST propagate unmodified; no operation besides `createCategory` defines special-case status handling.
- **Error state: repeated `remove` on an already-removed id.** MUST send a second DELETE and MUST propagate whatever the backend returns for it (e.g. a 404); this client does not treat a repeat `remove` call as a guaranteed no-op.
- **Offline or disconnected state.** Every `notesApi` operation is a single network round trip with no built-in timeout, retry, backoff, or offline queue; a connectivity loss mid-request MUST surface as a rejected promise (an unmodified network error) with no automatic reconnection or replay.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `filters.q` | `string` | `undefined` | Free-text filter forwarded to `markdownApi.list`; trimmed, and omitted from the request when blank or absent. |
| `filters.category` | `string` | `undefined` | Exact category-name filter; trimmed, omitted when blank or absent. |
| `filters.tag` | `string` | `undefined` | Exact tag filter; trimmed, omitted when blank or absent. |
| `opts.workspace` | `string` | `undefined` | Owning workspace slug. When set, scopes `list`/`get`/`create`/`update`/`remove`/`categories`/`createCategory`/`tags`/`tagSet` to that workspace's principal instead of the caller's own. Not accepted by any `taxonomyApi` operation. |
| notes marker | `boolean` | `true` (fixed) | Always merged in by `create` (as `note: true`) and by `list` (as `noted: true`); not exposed as a caller-supplied option. |
| `doc` field | `boolean` | `undefined` | Caller-suppliable on `notesApi.create`'s body only; when set to `true`, double-files the new document in the docs bucket as well. Not added or read by `notesApi` itself. |
| page size | `number` | `200` (fixed, from `markdownApi`'s `PAGE_SIZE`) | Not exposed as a parameter; every `list` call requests exactly this many rows with no cursor. |

## Deep Linking

Not applicable: `notes.ts` defines no route, URL pattern, or navigable destination of its own — it is a data client with no UI or navigation surface.

## Localization

`notesApi.createCategory` surfaces `markdownApi.createCategory`'s hardcoded English error string on a name conflict — `A category named "<name>" already exists somewhere else.` (`create-category-conflict-message`) — with no lookup table or locale parameter anywhere in `notes.ts`. This is the only user-facing string this component's own call graph can produce beyond a raw thrown error; every other error `notesApi`'s operations can produce is whatever `authedJson`/`authedRequest` throws, defined outside this file.

## Accessibility Options

Not applicable: `notes.ts` renders nothing and reads no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color) — those apply only to views that later display a `Note`, not to this data client.

## Feature Flags

Not applicable: `notes.ts` and the `markdownApi`/`taxonomyApi` calls it forwards to contain no feature-flag or remote-config check of any kind — every operation always runs unconditionally.

## Analytics

Not applicable: `notes.ts` and its `markdownApi`/`taxonomyApi` dependencies emit no analytics or telemetry event of any kind, on success or failure.

## Privacy

- **Data collected**: None beyond what the caller explicitly supplies — `content`, `category`, `tags`, and (per `create-may-double-file`) `doc` — plus the fixed `note: true` marker this client always adds on create. No field is appended that the caller did not provide or that this recipe's other requirements do not already name.
- **Storage**: None client-side. `notesApi` holds no cache and no local copy of any note, category, or tag (`stateless-client`); all persistence is the backend's.
- **Transmission**: Every request travels through `authedJson`/`authedRequest` (`packages/web/packages/data/src/http.ts`, itself re-exporting `@agentic-toolkit/auth/client`), the same bearer-token authenticated channel every other data client in this package uses; `notes.ts` adds no transmission of its own and performs no additional encryption, redaction, or inspection of the note content it sends.
- **Retention**: Not controlled at this layer. `notesApi.remove` performs a soft delete on the backend (per the module comment: "the backend tombstones the note marker with the document"); how long a tombstoned row is retained is a backend policy this client has no visibility into.

## Logging

Not applicable: `notes.ts` and the `markdown.ts`/`taxonomy.ts` modules it delegates to contain no `console`/logger call of any kind. Every failure path either propagates the caller's error unmodified or, for `createCategory`'s 409, is mapped to a friendlier `Error` and thrown — never logged.

## Platform Notes

- **SwiftUI**: Port as a plain Swift API namespace (e.g. an `enum NotesAPI` or a struct of static members) that wraps a shared `MarkdownAPI` type the same way `notesApi` wraps `markdownApi` — never issue a fresh `URLSession` call from this type itself. Model `Note`/`NoteSummary`/`NoteFilters`/`NoteCategory`/`NoteTag` as `Codable`, `Sendable` structs mirroring the wire fields, with a custom `init(from:)` (or a post-decode step) that defaults a missing/null `tags` key to `[]`, matching `withTags`. Keep the create body's optional `doc` field on the Swift type explicitly, to preserve the double-filing behavior in `create-may-double-file`, and surface the category-name conflict as a typed error case (e.g. an `enum NotesError { case categoryNameTaken(String) }`) instead of a generic thrown error. The repo's existing `NotesManager`/`NoteStorage` types (`packages/apple/AgenticAppKit`) are a local, on-device notes store, not a client for this backend surface — do not conflate the two when porting.
- **Compose**: Port as a Kotlin `object NotesApi` delegating every operation to a shared `MarkdownApi` interface or class, using `suspend fun` for each one and `kotlinx.serialization` `@Serializable data class`es for `Note`/`NoteSummary`/`NoteCategory`/`NoteTag`, with constructor defaults (`val tags: List<String> = emptyList()`) reproducing the same never-null-tags guarantee. Use the project's existing HTTP client (e.g. Ktor or Retrofit) in place of `authedJson`, and keep the 200-row page cap as a named constant rather than a literal embedded in a query builder. Model `categories()`'s tree-vs-flat divergence from `tags()` as two distinctly named methods so a caller cannot mistake one shape for the other.
- **React/Web (source platform)**: this is the source implementation; `authedJson`/`authedRequest` (from `@agentic-toolkit/auth/client` via `../http`) and the helpers in `../client-helpers` (`enc`, `workspaceQuery`) are shared with every other client in this data package and MUST be reused, not reimplemented. `notes.ts` has no test file of its own; the fallback helpers it depends on (`withTags`, `categoryNodes`, `tagNodes`) are exercised only via `markdown/__tests__/markdown.test.ts`.
- **AppKit / UIKit**: Same guidance as SwiftUI — this is a data-layer client with no view code, so AppKit and UIKit consumers call the same ported async functions; nothing about the port differs between an AppKit, UIKit, or SwiftUI host.
- **WinUI 3**: This is the platform this recipe exists to steer. Port `notesApi` as a static class or a singleton service (`NotesApi`) that wraps a shared `MarkdownApi` service the same way the source wraps `markdownApi` — `NotesApi` itself should never call `HttpClient` directly. Model `Note`/`NoteSummary`/`NoteCategory`/`NoteTag` as `sealed record` types deserialized with `System.Text.Json` (`JsonSerializer.Deserialize<Note>`), adding a custom converter or a post-deserialize step that defaults `Tags` to an empty `List<string>` rather than `null`, mirroring `withTags`. Use `HttpClient` with `async`/`Task<T>` for every operation, injecting the bearer-token header inside the shared `MarkdownApi` service rather than in `NotesApi`. Give `Categories()` and `Tags()` two distinct return-shape methods on the service interface (one returning tree nodes, one a flat `IReadOnlyList<string>`) so the source's own tree-vs-flat naming split is not accidentally collapsed into one. Return plain `IReadOnlyList<T>` from this client (build an `ObservableCollection<T>` only at the ViewModel layer, matching the source's plain-array contract), and keep the fixed 200-row page size and the absence of a cursor explicit as a named constant so a future consumer does not assume paging support exists. Map the backend's category-name-conflict 409 to a typed exception (e.g. a `CategoryNameConflictException`) the way `markdownApi.createCategory` maps it to a friendly `Error` in TypeScript.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/data/src/notes/notes.ts` |

## Design Decisions

- **Decision**: `notesApi` is implemented as a thin marker lens over `markdownApi` rather than a dedicated `/content/notes` route set, even though that surface exists on the backend.
  **Rationale**: the module's own header comment states a parallel route set "would have had to re-derive the version-snapshot and classification invariants `markdownDocuments.ts` already owns, and would have drifted."
  **Approved**: pending
- **Decision**: the backend's separate `/content/notes` surface is documented but never called by this client.
  **Rationale**: per the module comment, it is "the device-SYNC marker surface — content only, no title/category/tags, no workspace — and it has no web consumer," so it is deliberately not what `notesApi` talks to.
  **Approved**: pending
- **Decision**: `CreateNoteBody` omits only `note` from `CreateMarkdownBody`, leaving `doc` available, so one `create` call can file a new document in both the notes and docs buckets.
  **Rationale**: per `markdown.ts`'s comment on `MarkdownCreateBody`, `note` and `doc` are independent markers "because the markers they mint are independent rows: nothing in the schema stops one text from sitting on both shelves" — `CreateNoteBody`'s `Omit` narrows only the one field this client's own contract cares about (that `note` is always `true`) and takes no position on `doc`.
  **Approved**: pending
- **Decision**: the re-exported `taxonomyApi` accepts no `workspace` parameter on any of its seven operations, unlike every other operation this component exposes.
  **Rationale**: per `taxonomy.ts`'s module comment, the categories/category-edges/keywords tables are scoped by `customer_id`/`ecosystem_id` ownership rather than an `owner_kind`/`owner_id` column, so the workspace pin "only applies to tables with owner_kind / owner_id columns, which these do not have" — adding the parameter would not narrow anything and would misstate the endpoint's real scoping.
  **Approved**: pending
- **Decision**: `notesApi.categories()` calls `markdownApi.categoryTree` and returns node rows, while `notesApi.tags()` calls `markdownApi.tags` and returns the plain flat label list — the two sibling lookups do not share one return shape, and only `tagSet()` gets the node-row treatment `categories()` gets by default.
  **Rationale**: `notes.ts`'s own doc comments name the intent directly: `categories()` is described as the notebook rail's hierarchy source, while `tags()` is "the workspace's tag labels (the tag field's autocomplete source)" with `tagSet()` separately documented as "the same tags WITH their ids" for the manager that renames/deletes them — the asymmetry is deliberate, not an oversight, and a port that gives both methods one shared shape would silently change which one degrades and which one is the raw autocomplete source.
  **Approved**: pending
- **Decision**: for an org workspace, `notesApi` leaves org-shared note semantics undefined beyond ordinary org-document ownership.
  **Rationale**: `notesApi`'s own comment states this plainly — "For an ORG workspace this is the whole of the ownership story today — org-SHARED note semantics are still undesigned, so an org note is simply an org-owned document, and the marker carries only its creator stamp" — recorded here as the current, deliberate scope rather than smoothed over.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | failed | Best Practices |
| [error-response-handling](agenticdevelopercookbook://compliance/access-patterns#error-response-handling) | partial | Access Patterns |
| [pagination-support](agenticdevelopercookbook://compliance/access-patterns#pagination-support) | failed | Access Patterns |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | partial | Reliability |
| [data-minimization](agenticdevelopercookbook://compliance/privacy-and-data#data-minimization) | passed | Privacy and Data |

`separation-of-concerns` passes: `notes.ts` owns no HTTP call, wire-shape knowledge, or taxonomy logic of its own — every operation is either a direct forward to `markdownApi`/`taxonomyApi` or a one-line marker merge (`note-marker-on-create`, `list-scoped-to-noted-marker`). `unit-test-coverage` fails: `notes.ts` has no test file of its own, and neither of its two marker-merge lines is exercised by any test in the given sources; the existing coverage in `markdown.test.ts` tests `withTags`/`categoryNodes`/`tagNodes`, which this component depends on but does not itself invoke under test. `error-response-handling` is partial: only `createCategory`'s 409 is mapped to a friendly message (`create-category-conflict-message`); every other documented backend status this client's calls can receive — 403, 404, 500 — propagates unmodified with no per-status handling (`errors-propagate-unmodified`). `pagination-support` fails: `list` requests a fixed 200-row page with no cursor and no follow-up fetch (`list-page-size-fixed`), so a corpus larger than 200 silently loses rows. `idempotent-operations` is partial: `createCategory` is deliberately idempotent when re-posting an existing name under its current parents, but `create` is not idempotent at all (`create-not-idempotent`) and a repeated `remove` on an already-removed id is not guaranteed to be a no-op. `data-minimization` passes: every field sent to the backend is either caller-supplied content/category/tags/doc or the fixed `note: true` marker; no additional data is collected or appended.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial recipe covering notes.ts as a marker lens over markdown.ts and taxonomy.ts. |
