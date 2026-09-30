<!-- leaf: implement-hub-domain-1/markdown--part-3 · source: hub-domain-markdown.md -->

# Hub Domain Markdown Client — continued (part 3)

**Rules** (cite as `implement-hub-domain-1/markdown--part-3#<slug>`):

- `react-web` MUST — this is the source implementation; authedJson/authedRequest (from @agentic-toolkit/auth/client via ../http) and the …

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
