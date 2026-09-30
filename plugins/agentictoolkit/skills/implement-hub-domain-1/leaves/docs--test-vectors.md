<!-- leaf: implement-hub-domain-1/docs--test-vectors · source: hub-domain-docs.md -->

# Docs Client

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
