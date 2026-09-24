---
id: 48ddd102-b78c-4198-b71d-25801082a5b2
title: Docs Client
domain: agentictoolkit://recipes/hub-domain-docs
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Thin corpus-marker lens over the shared markdown-document client: stamps/filters
  the docs bucket marker, re-exports shared category/tag taxonomy.'
platforms:
- typescript
- web
tags:
- docs
- markdown
- taxonomy
- crud
- web
depends-on: []
related: []
references:
- packages/web/packages/data/src/docs/docs.ts (agentictoolkit)
- packages/web/packages/data/src/docs/index.ts (agentictoolkit)
- packages/web/packages/data/src/markdown/markdown.ts (agentictoolkit)
- packages/web/packages/data/src/markdown/wire.ts (agentictoolkit)
- packages/web/packages/data/src/markdown/taxonomy.ts (agentictoolkit)
- packages/web/packages/data/src/notes/notes.ts (agentictoolkit)
- packages/web/packages/data/src/http.ts (agentictoolkit)
- packages/web/packages/data/src/client-helpers.ts (agentictoolkit)
- packages/web/packages/data/src/markdown/__tests__/markdown.test.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

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

## Appearance

Not applicable — this is a data client (a stateless collection of async
functions over HTTP), not a visual component.

## States

Not applicable — this is a data client, not a visual component. The one
runtime distinction available — a resolved value versus a rejected promise
— is captured under Behavioral Requirements
(`errors-propagate-unmodified`, `create-category-conflict-message`), not
as a visual-state table.

## Accessibility

Not applicable — this is a data client (a stateless collection of async
functions over HTTP), not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| HDD-001 | list-scoped-to-doc-marker | `docsApi.list({}, { workspace: "acme" })` | Underlying call is `markdownApi.list({}, { workspace: "acme", doc: true })`, producing the query string `/api/content/markdown?pageSize=200&doc=true&workspace=acme` |
| HDD-002 | doc-marker-on-create | `docsApi.create({ content: "# Hello" })` | The POST body sent by `markdownApi.create` is `JSON.stringify({ content: "# Hello", doc: true })` |
| HDD-003 | create-body-retains-note-field, create-may-double-file | `docsApi.create({ content: "x", note: true } as CreateDocBody)` | The POST body is `{ content: "x", note: true, doc: true }` — both markers set on one create call |
| HDD-004 | id-ops-not-scoped-to-marker | `docsApi.get("note-only-id")`, where the document at that id was created with `note: true` and no `doc` marker | Resolves with that document's full row (no marker check is performed; the call carries no `doc` field at all) |
| HDD-005 | tags-array-guaranteed | Backend responds to `docsApi.create`'s POST with `{ id: "d1", title: "T", content: "x", category: null, visibility: "private" }` (no `tags` key) | Resolved `Doc.tags` equals `[]`, per `markdown.test.ts`'s `withTags` case "defaults a missing tags field to []" |
| HDD-006 | category-tree-degrades-flat | Backend answers `GET /api/content/markdown/categories` with `{ items: ["Admin", "Meetings"] }` (no `nodes` key) | `docsApi.categories()` resolves to `[{ id: "Admin", name: "Admin", parentIds: [], sortOrder: 0 }, { id: "Meetings", name: "Meetings", parentIds: [], sortOrder: 1 }]`, per `markdown.test.ts`'s "rebuilds an older backend's flat names as roots, in the order it sent them" |
| HDD-007 | tag-set-degrades-flat | Backend answers `GET /api/content/markdown/tags` with `{ items: ["draft", "final"] }` (no `nodes` key) | `docsApi.tagSet()` resolves to `[{ id: "draft", label: "draft" }, { id: "final", label: "final" }]`, per `markdown.test.ts`'s tag-node fallback case |
| HDD-008 | create-category-conflict-message | Backend responds 409 to `POST /api/content/markdown/categories` for `{ name: "Meetings" }` | `docsApi.createCategory({ name: "Meetings" })` rejects with `Error` whose message is exactly `A category named "Meetings" already exists somewhere else.` |
| HDD-009 | remove-is-void | Backend responds 204 to `DELETE /api/content/markdown/{id}` | `docsApi.remove(id)` resolves to `undefined`; no `authedJson` call (and therefore no response-body parse) occurs for this operation |
| HDD-010 | taxonomy-ops-not-workspace-scoped | `taxonomyApi.renameCategory("c1", "Renamed")` | The request URL is `/api/content/categories/c1` with no `?workspace=` query segment, regardless of any workspace context the caller may be in |
| HDD-011 | list-page-size-fixed | A workspace has 250 documents matching the doc marker and the given filters | `docsApi.list()` resolves with exactly 200 `DocSummary` rows; the 201st through 250th are omitted with no cursor or "more available" signal in the result |
| HDD-012 | errors-propagate-unmodified | Backend responds 404 to `GET /api/content/markdown/{id}` | `docsApi.get(id)` rejects with the same error `authedJson` threw (a status-404 `Error`); `docsApi` performs no remapping |

## Edge Cases

- **Empty filters object.** `docsApi.list({})` MUST return every doc-marked
  document in the (optionally workspace-scoped) corpus: `q`, `category`,
  and `tag` are all omitted from the query string when absent, per
  `markdown.ts`'s `listQuery`.
- **Blank-string filter values.** `docsApi.list({ q: " " })` MUST behave
  identically to `docsApi.list({})`: `listQuery` trims each filter and
  omits it from the query string when the trimmed value is empty.
- **Empty-string id.** `docsApi.get("")`, `update("", ...)`, and
  `remove("")` MUST encode the id via `encodeURIComponent` and send the
  resulting request unchanged — this client performs no non-empty
  validation on `id` before building the URL; whatever status the backend
  returns for that malformed path MUST propagate per
  `errors-propagate-unmodified`.
- **Create with only `content`.** `docsApi.create({ content: "x" })` MUST
  send a body with `category` and `tags` both absent (the caller's choice,
  not a client default); if the backend's response also omits `tags`, the
  resolved `Doc.tags` MUST still be `[]` per `tags-array-guaranteed`.
- **Boundary: exactly 200 matching documents.** `docsApi.list` MUST return
  all 200 rows in one call.
- **Boundary: 201st matching document.** MUST be silently omitted from the
  result, per `list-page-size-fixed`.
- **Re-creating an existing category under the same parents.** Per
  `markdown.ts`'s comment on `createCategory`, this MUST succeed
  idempotently (no 409) when every parent requested is already one of that
  category's current parents.
- **Re-creating an existing category under a different, conflicting set of
  parents.** MUST reject with the mapped 409 message described in
  `create-category-conflict-message`.
- **Concurrent access: two `docsApi.create` calls fired without awaiting
  between them.** Per `stateless-client` and `create-not-idempotent`, each
  call MUST independently POST and MUST resolve to a distinct document with
  its own id; neither call MUST observe or be blocked by the other.
- **Concurrent access: `taxonomyApi.removeCategoryParent` racing
  `taxonomyApi.addCategoryParent` on the same category.**
  `removeCategoryParent` reads the category's current parent edges, then
  deletes the ones matching the given `parentId`, in two separate requests;
  a parent link added by a concurrent `addCategoryParent` call after that
  read completes MUST NOT be included in the delete loop, because the read
  is a snapshot (documented in `taxonomy.ts`'s module comment on the same
  snapshot property for `addCategoryParent`).
- **Error state: backend unreachable.** Any `docsApi` operation's
  `authedJson`/`authedRequest` call rejecting with a network error MUST
  propagate that rejection unmodified, per `errors-propagate-unmodified` and
  `no-client-side-retry` — no retry is attempted.
- **Error state: non-2xx status other than the mapped 409.** A 403, 404, or
  500 from any operation other than `createCategory` MUST propagate
  unmodified; no operation besides `createCategory` defines special-case
  status handling.
- **Error state: repeated `remove` on an already-removed id.** MUST send a
  second DELETE and MUST propagate whatever the backend returns for it
  (e.g. a 404); this client does not treat a repeat `remove` call as a
  guaranteed no-op.
- **Offline or disconnected state.** Every `docsApi` operation is a single
  network round trip with no built-in timeout, retry, backoff, or offline
  queue; a connectivity loss mid-request MUST surface as a rejected promise
  (an unmodified network error) with no automatic reconnection or replay.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `filters.q` | `string` | `undefined` | Free-text filter forwarded to `markdownApi.list`; trimmed, and omitted from the request when blank or absent. |
| `filters.category` | `string` | `undefined` | Exact category-name filter; trimmed, omitted when blank or absent. |
| `filters.tag` | `string` | `undefined` | Exact tag filter; trimmed, omitted when blank or absent. |
| `opts.workspace` | `string` | `undefined` | Owning workspace slug. When set, scopes `list`/`get`/`create`/`update`/`remove`/`categories`/`createCategory`/`tags`/`tagSet` to that workspace's principal instead of the caller's own. Not accepted by any `taxonomyApi` operation. |
| doc marker | `boolean` | `true` (fixed) | Always merged in by `list` and `create`; not exposed as a caller-supplied option. |
| page size | `number` | `200` (fixed, from `markdownApi`'s `PAGE_SIZE`) | Not exposed as a parameter; every `list` call requests exactly this many rows with no cursor. |

## Deep Linking

Not applicable: `docs.ts` defines no route, URL pattern, or navigable
destination of its own — it is a data client with no UI or navigation
surface.

## Localization

`docsApi.createCategory` surfaces a hardcoded English error string on a
name conflict — `A category named "<name>" already exists somewhere
else.` (`create-category-conflict-message`) — with no lookup table or
locale parameter anywhere in `docs.ts` or the `markdownApi.createCategory`
call it forwards to. This is the only user-facing string this component
introduces; every other error this component's operations can produce is
whatever `authedJson`/`authedRequest` throws, defined outside this file.

## Accessibility Options

Not applicable: `docs.ts` renders nothing and reads no accessibility
display setting (Reduce Motion, Increase Contrast, Differentiate Without
Color) — those apply only to views that later display a `Doc`, not to this
data client.

## Feature Flags

Not applicable: `docs.ts` and the `markdownApi`/`taxonomyApi` calls it
forwards to contain no feature-flag or remote-config check of any kind —
every operation always runs unconditionally.

## Analytics

Not applicable: `docs.ts` and its `markdownApi`/`taxonomyApi` dependencies
emit no analytics or telemetry event of any kind, on success or failure.

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

## Logging

Not applicable: `docs.ts` and the `markdown.ts`/`taxonomy.ts` modules it
delegates to contain no `console`/logger call of any kind. Every failure
path either propagates the caller's error unmodified or, for
`createCategory`'s 409, is mapped to a friendlier `Error` and thrown — never
logged.

## Platform Notes

- **SwiftUI**: Port as a plain Swift API namespace (e.g. an `enum DocsAPI`
  or a struct of static members) that wraps a shared `MarkdownAPI` type the
  same way `docsApi` wraps `markdownApi` — never issue a fresh
  `URLSession` call from this type itself. Model `Doc`/`DocSummary`/
  `DocFilters`/`DocCategory`/`DocTag` as `Codable`, `Sendable` structs
  mirroring the wire fields, with a custom `init(from:)` (or a
  post-decode step) that defaults a missing/null `tags` key to `[]`,
  matching `withTags`. Keep the create body's optional `note` field on the
  Swift type explicitly, to preserve the double-filing behavior in
  `create-may-double-file`, and surface the category-name conflict as a
  typed error case (e.g. an `enum DocsError: Error { case categoryNameTaken(String) }`)
  instead of a generic thrown error.
- **Compose**: Port as a Kotlin `object DocsApi` delegating every operation
  to a shared `MarkdownApi` interface or class, using `suspend fun` for
  each one and `kotlinx.serialization` `@Serializable data class`es for
  `Doc`/`DocSummary`/`DocCategory`/`DocTag`, with constructor defaults
  (`val tags: List<String> = emptyList()`) reproducing the same
  never-null-tags guarantee. Use the project's existing HTTP client (e.g.
  Ktor or Retrofit) in place of `authedJson`, and keep the 200-row page
  cap as a named constant rather than a literal embedded in a query
  builder.
- **React/Web**: The source. `docs.ts` has no logic of its own beyond the
  marker merges in `doc-marker-on-create` and `list-scoped-to-doc-marker`;
  it delegates entirely to `markdown.ts` for HTTP, page size, and the
  category/tag-tree degrade helpers (`withTags`, `categoryNodes`,
  `tagNodes`), and re-exports `taxonomy.ts` unchanged. Transport
  (`authedJson`/`authedRequest`) comes from `http.ts`, itself re-exporting
  `@agentic-toolkit/auth/client`; `enc`/`workspaceQuery` come from
  `client-helpers.ts`. Wire types live in `markdown/wire.ts`. Tests for the
  delegated helpers live in `markdown/__tests__/markdown.test.ts`; `docs.ts`
  has no test file of its own.
- **AppKit / UIKit**: Same guidance as SwiftUI — this is a data-layer
  client with no view code, so AppKit and UIKit consumers call the same
  ported async functions; nothing about the port differs between an
  AppKit, UIKit, or SwiftUI host.
- **WinUI 3**: This is the platform this recipe exists to steer. Port
  `docsApi` as a static class or a singleton service (`DocsApi`) that
  wraps a shared `MarkdownApi` service the same way the source wraps
  `markdownApi` — `DocsApi` itself should never call `HttpClient`
  directly. Model `Doc`/`DocSummary`/`DocCategory`/`DocTag` as `sealed
  record` types deserialized with `System.Text.Json`
  (`JsonSerializer.Deserialize<Doc>`), adding a custom converter or a
  post-deserialize step that defaults `Tags` to an empty `List<string>`
  rather than `null`, mirroring `withTags`. Use `HttpClient` with
  `async`/`Task<T>` for every operation, injecting the bearer-token header
  inside the shared `MarkdownApi` service rather than in `DocsApi`. Model
  `DocFilters` as a small record with nullable `string?` members, trimming
  and dropping blank values before building the query string exactly as
  `listQuery` does. Return plain `IReadOnlyList<T>` from this client (build
  an `ObservableCollection<T>` only at the ViewModel layer, matching the
  source's plain-array contract), and keep the fixed 200-row page size and
  the absence of a cursor explicit as a named constant so a future
  consumer does not assume paging support exists. Map the backend's
  category-name-conflict 409 to a typed exception (e.g. a
  `CategoryNameConflictException`) the way `markdownApi.createCategory`
  maps it to a friendly `Error` in TypeScript.

## Design Decisions

- **Decision**: `docsApi.get`, `update`, and `remove` address a document
  purely by id, applying no `doc`-marker check, while `list` and `create`
  do apply the marker.
  **Rationale**: per `docs.ts`'s own module comment, the `content.docs`
  marker exists to file a document in "the owner's `docs` storage bucket"
  — it constrains which documents a listing or a new creation touches, not
  which documents a caller who already holds an id may read, edit, or
  delete.
  **Approved**: pending
- **Decision**: `CreateDocBody` omits only `doc` from `CreateMarkdownBody`,
  leaving `note` available, so one `create` call can file a new document
  in both the docs and notes buckets.
  **Rationale**: per `markdown.ts`'s comment on `MarkdownCreateBody`,
  `note` and `doc` are independent markers "because the markers they mint
  are independent rows: nothing in the schema stops one text from sitting
  on both shelves" — `CreateDocBody`'s `Omit` narrows only the one field
  this client's own contract cares about (that `doc` is always `true`) and
  takes no position on `note`.
  **Approved**: pending
- **Decision**: The re-exported `taxonomyApi` accepts no `workspace`
  parameter on any of its seven operations, unlike every other operation
  this component exposes.
  **Rationale**: per `taxonomy.ts`'s module comment, the categories/
  category-edges/keywords tables are scoped by `customer_id`/
  `ecosystem_id` ownership rather than an `owner_kind`/`owner_id` column,
  so "the workspace pin only applies to tables with owner_kind /
  owner_id columns, which these do not have" — adding the parameter would
  not narrow anything and would misstate the endpoint's real scoping.
  **Approved**: pending
- **Decision**: `docsApi.categories()` and `docsApi.tagSet()` degrade a
  pre-hierarchy backend's flat name/label list into synthetic root nodes
  (id equal to the name/label) instead of returning an empty tree or set.
  **Rationale**: per `markdown.ts`'s comments on `categoryNodes` and
  `tagNodes`, those flat lists are "the entire category set such a backend
  HAS," and every existing consumer filters or links a category or tag by
  name/label rather than by id, so rebuilding roots keeps a working (if
  flat) result instead of emptying it.
  **Approved**: pending
- **Decision**: `docsApi.list` always requests a fixed page of 200 rows
  with no cursor or page-size parameter exposed.
  **Rationale**: per `markdown.ts`'s comment on `PAGE_SIZE`, "a user's own
  research set is small, and the master list shows everything at once (no
  pagination UI)," and 200 is stated as the backend's own page cap —
  pagination was not built because no consumer needed it yet, not because
  the backend cannot support it.
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

`separation-of-concerns` passes: `docs.ts` owns no HTTP call, wire-shape
knowledge, or taxonomy logic of its own — every operation is either a
direct forward to `markdownApi`/`taxonomyApi` or a one-line marker merge
(`doc-marker-on-create`, `list-scoped-to-doc-marker`). `unit-test-coverage`
fails: `docs.ts` has no test file of its own, and neither of its two
marker-merge lines is exercised by any test in the given sources; the
existing coverage in `markdown.test.ts` tests `withTags`/`categoryNodes`/
`tagNodes`, which this component depends on but does not itself invoke
under test. `error-response-handling` is partial: only `createCategory`'s
409 is mapped to a friendly message (`create-category-conflict-message`);
every other documented backend status this client's calls can receive —
403, 404, 500 — propagates unmodified with no per-status handling
(`errors-propagate-unmodified`). `pagination-support` fails: `list`
requests a fixed 200-row page with no cursor and no follow-up fetch
(`list-page-size-fixed`), so a corpus larger than 200 silently loses rows.
`idempotent-operations` is partial: `createCategory` is deliberately
idempotent when re-posting an existing name under its current parents, but
`create` is not idempotent at all (`create-not-idempotent`) and a repeated
`remove` on an already-removed id is not guaranteed to be a no-op.
`data-minimization` passes: every field sent to the backend is either
caller-supplied content/category/tags/note or the fixed `doc: true`
marker; no additional data is collected or appended.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | | | Initial creation |
