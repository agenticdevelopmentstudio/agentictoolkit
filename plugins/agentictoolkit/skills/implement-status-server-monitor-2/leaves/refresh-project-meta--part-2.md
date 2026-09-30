<!-- leaf: implement-status-server-monitor-2/refresh-project-meta--part-2 · source: status-server-monitor-refresh-project-meta.md -->

# Status Server Monitor Refresh Project Meta — continued (part 2)

## Platform Notes

- **SwiftUI**: not a view concern (no UI). An Apple companion backend embedding
  this pattern models the three functions as `async throws` functions (or
  methods on a stateless type) taking a `StorageProtocol`-conforming value and,
  for the config-resolving variant, a `Sendable` `StatusConfig` struct; the
  `VercelMetaSnapshot`/`VercelMetaSyncResult`/`VercelRefreshResult` shapes
  become small `Sendable` structs, with `live: Set<String>?` mirroring the JS
  `Set<string> | null` exactly (nil standing in for the "no verdict" case).
- **Compose**: same non-UI framing as SwiftUI. A Kotlin port models the three
  functions as `suspend fun`s, `VercelMetaSyncResult` as a `data class` whose
  `live: Set<String>?` field is nullable rather than optional, and preserves
  the same ordering (upsert, then read-back, then diff, then conditional
  delete) unless a port deliberately wraps that sequence in a transaction, in
  which case that divergence belongs in that port's own Design Decisions.
- **React/Web** (source platform): lives at
  `packages/web/packages/status-server/src/monitor/refresh-project-meta.ts`;
  three plain exported `async` functions on the Node status backend, depending
  on the in-repo `Storage`/`StatusConfig` port types, `fetchVercelProductionStates`
  (`./fetch-vercel-projects`), and `providerConn` (`./provider-conn`) — none of
  it is client-side React.
- **AppKit / UIKit**: same non-UI framing as SwiftUI — no view renders here; a
  macOS/iOS agent process embedding this pattern has no additional
  consideration beyond the SwiftUI bullet above.
- **WinUI 3**: a .NET port models the three functions as
  `Task<VercelMetaSyncResult> SyncVercelProjectMetaAsync(IStorage storage,
  VercelMetaSnapshot snapshot)`, `Task<VercelRefreshResult>
  RefreshVercelProjectMetaAsync(IStorage storage, VercelEnv env)`, and
  `Task<VercelRefreshResult> RefreshVercelProjectMetaFromConfigAsync(IStorage
  storage, StatusConfig config)`, with `VercelMetaSyncResult.Live` typed as
  `IReadOnlySet<string>?` to preserve the null-means-no-verdict contract from
  `live-null-means-no-verdict`. `env.VERCEL_API_TOKEN` becomes a
  nullable string property read with ordinary null-coalescing rather than a
  JS truthiness check, and `config.secrets` is typed as
  `IReadOnlyDictionary<string, string?>` looked up via `TryGetValue`, the exact
  analogue of the JS bracket lookup returning `undefined` on a miss. The .NET
  Windows App SDK offers no ready-made analogue of this reconcile-and-evict
  pattern; a WinUI 3 host embedding it should still route the actual chunked
  upsert/delete through its own storage layer's transaction API if it wants to
  close the gap described in concurrent-invocation-not-guarded, since neither
  `System.Data.SQLite` nor Entity Framework Core closes that gap automatically
  just by being used in .NET.

## Design Decisions

- **Decision**: make `deploy_project_meta`'s Vercel rows a mirror of the fetched
  account snapshot (upsert plus matching eviction) instead of the previous
  upsert-only table.
  **Rationale**: stated directly in the source's own module comment — the
  upsert-only table meant a deleted Vercel project "was enumerated forever,"
  Auto Configure "kept being offered" it, and its "dead deploy target reopened
  an unclearable Problem"; making this file "the ONLY writer" closes that gap
  "so the prune can never drift from the upsert."
  **Approved**: pending
- **Decision**: gate the eviction attempt on `snapshot.configured` rather than
  on `snapshot.meta.length > 0`.
  **Rationale**: an account whose last project was deleted returns a genuinely
  empty `meta` array from a genuinely authenticated, complete read; treating
  emptiness itself as "not configured" would make that real deletion
  unrepresentable and would never evict the account's last remaining stored
  row — the source's own reasoning is that `configured` "is deliberately NOT
  inferred from `meta.length > 0`."
  **Approved**: pending
- **Decision**: diff stored-vs-live names in JavaScript and delete by an
  explicit, chunked name list, rather than issuing one SQL `NOT IN` (`notInArray`)
  query against the live set.
  **Rationale**: not stated as a deliberate tradeoff in an inline comment;
  demonstrated as a fact of the code, since `deleteProjectMeta` receives an
  explicit `pruned` array rather than the `live` set or a subquery. Recorded
  here per source-fidelity as fact: this keeps the eviction bound by
  `DELETE_CHUNK_NAMES` the same way the upsert is bound by
  `UPSERT_CHUNK_PROJECTS`, at the cost of one extra `listProjectMetaNames`
  round-trip that a single `NOT IN` delete would not need.
  **Approved**: pending
- **Decision**: use no grace window or TTL before evicting a name absent from a
  complete, authenticated read.
  **Rationale**: stated directly in the source's own module comment — "an
  erroneous eviction is repaired by the next cycle's upsert (5 minutes)," so a
  spurious eviction from a transient API omission self-heals on the next
  monitor cycle rather than needing a deliberate hold-back window in this file.
  **Approved**: pending
