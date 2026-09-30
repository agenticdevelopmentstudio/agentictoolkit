<!-- leaf: implement-hub-domain-1/notes--test-vectors · source: hub-domain-notes.md -->

# Notes Client

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
