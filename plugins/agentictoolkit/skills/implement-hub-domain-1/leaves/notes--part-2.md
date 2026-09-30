<!-- leaf: implement-hub-domain-1/notes--part-2 · source: hub-domain-notes.md -->

# Notes Client — continued (part 2)

**Rules** (cite as `implement-hub-domain-1/notes--part-2#<slug>`):

- `react-web` MUST — this is the source implementation; authedJson/authedRequest (from @agentic-toolkit/auth/client via ../http) and the …

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

## Localization

`notesApi.createCategory` surfaces `markdownApi.createCategory`'s hardcoded English error string on a name conflict — `A category named "<name>" already exists somewhere else.` (`create-category-conflict-message`) — with no lookup table or locale parameter anywhere in `notes.ts`. This is the only user-facing string this component's own call graph can produce beyond a raw thrown error; every other error `notesApi`'s operations can produce is whatever `authedJson`/`authedRequest` throws, defined outside this file.

## Privacy

- **Data collected**: None beyond what the caller explicitly supplies — `content`, `category`, `tags`, and (per `create-may-double-file`) `doc` — plus the fixed `note: true` marker this client always adds on create. No field is appended that the caller did not provide or that this recipe's other requirements do not already name.
- **Storage**: None client-side. `notesApi` holds no cache and no local copy of any note, category, or tag (`stateless-client`); all persistence is the backend's.
- **Transmission**: Every request travels through `authedJson`/`authedRequest` (`packages/web/packages/data/src/http.ts`, itself re-exporting `@agentic-toolkit/auth/client`), the same bearer-token authenticated channel every other data client in this package uses; `notes.ts` adds no transmission of its own and performs no additional encryption, redaction, or inspection of the note content it sends.
- **Retention**: Not controlled at this layer. `notesApi.remove` performs a soft delete on the backend (per the module comment: "the backend tombstones the note marker with the document"); how long a tombstoned row is retained is a backend policy this client has no visibility into.

## Platform Notes

- **SwiftUI**: Port as a plain Swift API namespace (e.g. an `enum NotesAPI` or a struct of static members) that wraps a shared `MarkdownAPI` type the same way `notesApi` wraps `markdownApi` — never issue a fresh `URLSession` call from this type itself. Model `Note`/`NoteSummary`/`NoteFilters`/`NoteCategory`/`NoteTag` as `Codable`, `Sendable` structs mirroring the wire fields, with a custom `init(from:)` (or a post-decode step) that defaults a missing/null `tags` key to `[]`, matching `withTags`. Keep the create body's optional `doc` field on the Swift type explicitly, to preserve the double-filing behavior in `create-may-double-file`, and surface the category-name conflict as a typed error case (e.g. an `enum NotesError { case categoryNameTaken(String) }`) instead of a generic thrown error. The repo's existing `NotesManager`/`NoteStorage` types (`packages/apple/AgenticAppKit`) are a local, on-device notes store, not a client for this backend surface — do not conflate the two when porting.
- **Compose**: Port as a Kotlin `object NotesApi` delegating every operation to a shared `MarkdownApi` interface or class, using `suspend fun` for each one and `kotlinx.serialization` `@Serializable data class`es for `Note`/`NoteSummary`/`NoteCategory`/`NoteTag`, with constructor defaults (`val tags: List<String> = emptyList()`) reproducing the same never-null-tags guarantee. Use the project's existing HTTP client (e.g. Ktor or Retrofit) in place of `authedJson`, and keep the 200-row page cap as a named constant rather than a literal embedded in a query builder. Model `categories()`'s tree-vs-flat divergence from `tags()` as two distinctly named methods so a caller cannot mistake one shape for the other.
- **React/Web (source platform)**: this is the source implementation; `authedJson`/`authedRequest` (from `@agentic-toolkit/auth/client` via `../http`) and the helpers in `../client-helpers` (`enc`, `workspaceQuery`) are shared with every other client in this data package and MUST be reused, not reimplemented. `notes.ts` has no test file of its own; the fallback helpers it depends on (`withTags`, `categoryNodes`, `tagNodes`) are exercised only via `markdown/__tests__/markdown.test.ts`.
- **AppKit / UIKit**: Same guidance as SwiftUI — this is a data-layer client with no view code, so AppKit and UIKit consumers call the same ported async functions; nothing about the port differs between an AppKit, UIKit, or SwiftUI host.
- **WinUI 3**: This is the platform this recipe exists to steer. Port `notesApi` as a static class or a singleton service (`NotesApi`) that wraps a shared `MarkdownApi` service the same way the source wraps `markdownApi` — `NotesApi` itself should never call `HttpClient` directly. Model `Note`/`NoteSummary`/`NoteCategory`/`NoteTag` as `sealed record` types deserialized with `System.Text.Json` (`JsonSerializer.Deserialize<Note>`), adding a custom converter or a post-deserialize step that defaults `Tags` to an empty `List<string>` rather than `null`, mirroring `withTags`. Use `HttpClient` with `async`/`Task<T>` for every operation, injecting the bearer-token header inside the shared `MarkdownApi` service rather than in `NotesApi`. Give `Categories()` and `Tags()` two distinct return-shape methods on the service interface (one returning tree nodes, one a flat `IReadOnlyList<string>`) so the source's own tree-vs-flat naming split is not accidentally collapsed into one. Return plain `IReadOnlyList<T>` from this client (build an `ObservableCollection<T>` only at the ViewModel layer, matching the source's plain-array contract), and keep the fixed 200-row page size and the absence of a cursor explicit as a named constant so a future consumer does not assume paging support exists. Map the backend's category-name-conflict 409 to a typed exception (e.g. a `CategoryNameConflictException`) the way `markdownApi.createCategory` maps it to a friendly `Error` in TypeScript.

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
