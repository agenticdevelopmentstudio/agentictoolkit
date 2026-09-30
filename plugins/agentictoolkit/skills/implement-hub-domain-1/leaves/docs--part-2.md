<!-- leaf: implement-hub-domain-1/docs--part-2 · source: hub-domain-docs.md -->

# Docs Client — continued (part 2)

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
