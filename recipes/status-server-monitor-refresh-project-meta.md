---
id: 1c3d8661-12f2-4a84-bef4-7ccd4e3841e7
title: Status Server Monitor Refresh Project Meta
domain: agentictoolkit://recipes/status-server-monitor-refresh-project-meta
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Reconciles the deploy_project_meta table's Vercel rows against a fetched
  snapshot — upserting what still exists and evicting what does not — so the table
  stays a mirror of the account instead of an upsert-only ledger.
platforms:
- typescript
- web
tags:
- monitor
- vercel
- deploy
- persistence
- server
depends-on:
- agenticdevelopercookbook://guidelines/implementing/data/constraints-and-validation
- agenticdevelopercookbook://guidelines/implementing/data/transactions-and-concurrency
related:
- agentictoolkit://recipes/status-server-monitor-fetch-vercel-projects
- agentictoolkit://recipes/status-server-monitor-provider-conn
- agentictoolkit://recipes/status-server-config
- agentictoolkit://recipes/status-server-libsql
references:
- packages/web/packages/status-server/src/monitor/refresh-project-meta.ts (agentictoolkit)
- packages/web/packages/status-server/test/refresh-project-meta.int.test.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/fetch-vercel-projects.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/provider-conn.ts (agentictoolkit)
- packages/web/packages/status-server/src/storage/ports.ts (agentictoolkit)
- packages/web/packages/status-server/src/config/port.ts (agentictoolkit)
- packages/web/packages/status-server/src/libsql/stores/deploy-store.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/sync.ts (agentictoolkit)
- packages/web/packages/status-server/src/routes/reads.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

## Overview

`refresh-project-meta.ts` keeps the `deploy_project_meta` table's Vercel rows in
sync with a fetched account snapshot. Its own module comment states the problem
it fixes directly: the table was previously upsert-only, so a project deleted at
Vercel "was enumerated forever," Auto Configure "kept being offered" it, and its
"dead deploy target reopened an unclearable Problem." This file makes the table a
mirror of the account by pairing every upsert with a matching eviction, and is
"deliberately the only writer, so the prune can never drift from the upsert."

It exports three functions along three narrowing layers: `syncVercelProjectMeta`
(the pure-ish reconcile against storage, given an already-fetched snapshot),
`refreshVercelProjectMeta` (adds the fetch, gated on a raw env token), and
`refreshVercelProjectMetaFromConfig` (adds resolving that token from a
`StatusConfig`/`Storage` pair via `provider-conn.ts`). Only Vercel rows are ever
touched; Cloudflare, Railway, and Crunchy rows in the same table are polled live
elsewhere and are never upserted or pruned by this file.

## Behavioral Requirements

- **sole-writer-of-vercel-rows**: `syncVercelProjectMeta` MUST be the only code
  path that writes a `platform: 'vercel'` row into `deploy_project_meta`, so that
  every eviction it computes reflects every upsert that has ever landed; the
  source's own module comment states this design intent explicitly.
- **unconditional-upsert-on-nonempty-meta**: `syncVercelProjectMeta` MUST call
  `storage.deploy.upsertProjectMeta` whenever `snapshot.meta.length > 0`,
  tagging every row `platform: 'vercel'`, regardless of `snapshot.ok` or
  `snapshot.configured` — a partial (`ok: false`) read still upserts the
  projects it did get, because "a real build failure must not be lost."
- **no-eviction-attempt-when-not-ok-or-not-configured**: `syncVercelProjectMeta`
  MUST return `{ pruned: [], live: null }` immediately, without calling
  `storage.deploy.listProjectMetaNames` or `storage.deploy.deleteProjectMeta`
  at all, whenever `!snapshot.ok || !snapshot.configured`.
- **live-null-means-no-verdict**: a `live: null` result MUST be read by a caller
  as "this read proves nothing about what is gone," never as "nothing is gone" —
  it is the signal that stops a caller narrowing its own owned-target set off a
  partial or unconfigured read.
- **eviction-diffs-live-set-against-stored-names**: when the eviction path does
  run (`snapshot.ok && snapshot.configured`), `syncVercelProjectMeta` MUST build
  `live` as the set of `meta[].projectName` values, read the currently stored
  Vercel names via `storage.deploy.listProjectMetaNames('vercel')`, and compute
  `pruned` as every stored name absent from `live`.
- **delete-only-when-pruned-nonempty**: `syncVercelProjectMeta` MUST call
  `storage.deploy.deleteProjectMeta('vercel', pruned)` only when
  `pruned.length > 0`, and MUST NOT call it with an empty name list.
- **empty-meta-with-ok-and-configured-evicts-everything**: an authenticated,
  complete snapshot with `meta: []` MUST evict every currently stored Vercel
  project, because `configured` — not `meta.length > 0` — is what proves the
  read is trustworthy; the source's own reasoning is that "an empty list from an
  authenticated, complete read is the truth, not a failure," covering the case
  where a real account has had its last project deleted.
- **result-returns-remaining-live-set**: on the eviction path,
  `syncVercelProjectMeta` MUST return the same `live` set it computed for the
  diff, not `null`, so a caller can narrow its own owned-target list from this
  call's verdict instead of re-deriving the same predicate itself.
- **configured-gate-not-inferred-from-meta-length**: `refreshVercelProjectMeta`
  MUST derive `configured` from `!!env.VERCEL_API_TOKEN` alone, never from
  whether `meta` came back non-empty, so that an account whose last project was
  deleted is still `configured: true` and still eligible for eviction.
- **fail-closed-no-network-call-without-token**: `refreshVercelProjectMeta` MUST
  return `{ ok: false, configured: false, pruned: [] }` without calling
  `fetchVercelProductionStates` at all when `!env.VERCEL_API_TOKEN` — zero
  network attempt, not a call that is made and then ignored.
- **meta-only-fetch-mode**: `refreshVercelProjectMeta` MUST call
  `fetchVercelProductionStates` with `metaOnly: true` whenever a token is
  configured, so the request-path read of "which projects exist" asks for the
  shallowest deployment window the Vercel API allows rather than the monitor
  cycle's full history depth.
- **refresh-result-ok-mirrors-fetch-ok**: `refreshVercelProjectMeta` MUST set its
  returned `ok` to the fetch result's own `ok` (`res.ok`), and MUST set `pruned`
  to whatever `syncVercelProjectMeta` computed from that fetch's snapshot.
- **config-resolution-delegated-to-provider-conn**: `refreshVercelProjectMetaFromConfig`
  MUST resolve the Vercel token and team id by calling `providerConn(storage,
  config)` and reading `conn.vercel.token` / `conn.vercel.teamId`; the actual
  lookup that `providerConn` performs is against `config.secrets` (a
  `Readonly<Record<string, string | undefined>>` by-name lookup), not against
  `config.credentials` (the fixed named tuple) as this function's own doc
  comment states — the code's real behavior, traced through `provider-conn.ts`,
  is the by-name `secrets` lookup, and that is the contract this recipe
  documents.
- **concurrent-invocation-not-guarded**: NEEDS REVIEW: Not implemented in source. `syncVercelProjectMeta` performs its reconcile as three separate, unguarded storage calls (the upsert, the `listProjectMetaNames` read, and the conditional delete) with no transaction or lock spanning them, so two overlapping invocations could interleave those steps and evict a name another call's upsert had just restored, or compute a prune list against a set another call is mid-upsert on; this codebase's actual status-server calls this function from more than one independent site with no coordination between them.

## Appearance

Not applicable — this is a server-side data-reconciliation module, not a visual component.

## States

Not applicable — this is a server-side data-reconciliation module, not a visual component.

## Accessibility

Not applicable — this is a server-side data-reconciliation module, not a visual component.

## Conformance Test Vectors

Traced to `test/refresh-project-meta.int.test.ts`'s own assertions unless noted as source-only.

1. `syncVercelProjectMeta(storage, { meta: [META('live-site','renamed.example.com'), META('new-site')], ok: true, configured: true })` against a table already holding Vercel rows `live-site` and `deleted-site` (plus an untouched Cloudflare row) → `pruned: ['deleted-site']`, `live: {'live-site','new-site'}`; `deleted-site` is gone, `live-site`'s domain is updated to `renamed.example.com`, `new-site` is inserted, and the Cloudflare row is untouched.
2. `syncVercelProjectMeta(storage, { meta: Array(400 projects), ok: true, configured: true })` → all 400 upserted in chunks and `pruned` covers the two previously-stored names (`deleted-site`, `live-site`) that are absent from the 400; a follow-up call with `meta: []` prunes all 400 in chunks, leaving only the untouched Cloudflare row.
3. `syncVercelProjectMeta(storage, { meta: [META('new-site')], ok: false, configured: true })` (a partial/budget-truncated read) → `pruned: []`, `live: null`; `new-site` is still upserted, and the previously-stored `live-site`/`deleted-site` rows are both left in place.
4. `syncVercelProjectMeta(storage, { meta: [], ok: true, configured: false })` (the exact shape `fetchVercelProductionStates` returns with no token) → `pruned: []`, `live: null`; no row is touched.
5. `syncVercelProjectMeta(storage, { meta: [], ok: true, configured: true })` (an authenticated, complete read reporting zero projects) → every stored Vercel row is pruned (`pruned` sorts to `['deleted-site','live-site']`), leaving only the untouched Cloudflare row.
6. `refreshVercelProjectMeta(storage, { VERCEL_API_TOKEN: 'tok' })` against a live fetch mock that returns only `live-site` → `{ ok: true, configured: true, pruned: ['deleted-site'] }`, the stored rows reduce to `['live-site']`, and the outgoing `/v9/projects` request URL contains `latestDeployments=1`.
7. `refreshVercelProjectMeta(storage, {})` (no `VERCEL_API_TOKEN`) against a fetch mock that throws if called at all → `{ ok: false, configured: false, pruned: [] }`, the stored row count is unchanged, and the fetch mock is never invoked.
8. (source-only) `syncVercelProjectMeta(storage, { meta: [], ok: false, configured: true })` → `pruned: []`, `live: null`, and no upsert call at all, since `meta.length` is `0`; distinguishing this from vector 5 pins that `ok` (not merely `configured`) gates the eviction attempt.
9. (source-only) `refreshVercelProjectMeta(storage, { VERCEL_API_TOKEN: 'tok' })` against a fetch that returns `{ ok: true, meta: [], states: [], deploys: [] }` → `configured: true` (token present) but the reconcile still runs and evicts every stored Vercel row, exercising the same "last project deleted" path as vector 5 but reached through the full `refreshVercelProjectMeta` fetch-then-sync composition rather than calling `syncVercelProjectMeta` directly.
10. (source-only) `refreshVercelProjectMetaFromConfig(storage, config)` where `config.secrets.VERCEL_API_TOKEN` is set but `config.credentials.VERCEL_API_TOKEN` is not → the token still resolves and the refresh proceeds, because resolution goes through `providerConn`'s `config.secrets` lookup, not `config.credentials`.

## Edge Cases

- **Null/empty input**: an empty `meta` array on an `ok: true, configured: true`
  snapshot is valid and evicts every stored Vercel row (vector 5); an empty
  `meta` array on any other `ok`/`configured` combination performs neither an
  upsert nor an eviction attempt (vectors 4 and 8).
- **Boundary values**: a `meta` array crossing the storage layer's chunk sizes
  (`UPSERT_CHUNK_PROJECTS = 200`, `DELETE_CHUNK_NAMES = 500` in
  `deploy-store.ts`) is upserted and pruned across multiple chunked statements
  rather than one — the 400-project test vector exists specifically to cross
  the 200-row upsert chunk boundary twice over.
- **Concurrent access**: this file provides no mutual exclusion between
  overlapping calls to `syncVercelProjectMeta`/`refreshVercelProjectMeta`; see
  the open question on concurrent-invocation-not-guarded above.
- **Error states**: a rejected `Promise` from `storage.deploy.upsertProjectMeta`,
  `storage.deploy.listProjectMetaNames`, or `storage.deploy.deleteProjectMeta`
  is never caught inside this file — none of its three exported functions
  contains a `try`/`catch` — so the rejection propagates unchanged to the
  caller. This is a fact about this file, not a swallowed error: what the
  monitor cycle or the request route does with that rejection is decided by
  that external caller, not by this module.
- **Offline/disconnected state**: with no `VERCEL_API_TOKEN`,
  `refreshVercelProjectMeta` reports `{ ok: false, configured: false, pruned:
  [] }` and makes zero network attempts (fail-closed) rather than attempting a
  fetch that would fail; a caller distinguishes this `configured: false` case
  from a `configured: true` fetch that failed, since only the latter should be
  surfaced as an integration problem.

## Configuration

| Name | Type | Source | Effect |
|------|------|--------|--------|
| `env.VERCEL_API_TOKEN` | `string \| undefined` | `refreshVercelProjectMeta`'s `env` parameter | Presence alone sets `configured`; absence short-circuits to a no-network, no-eviction result. |
| `env.VERCEL_TEAM_ID` | `string \| undefined` | `refreshVercelProjectMeta`'s `env` parameter | Forwarded to `fetchVercelProductionStates`; does not itself gate `configured`. |
| `config.secrets.VERCEL_API_TOKEN` / `config.secrets.VERCEL_TEAM_ID` | `string \| undefined` (by-name lookup) | Resolved via `providerConn(storage, config)` inside `refreshVercelProjectMetaFromConfig` | Same effect as the two rows above, one layer further from the caller. |
| `snapshot.ok` | `boolean` | Caller-supplied to `syncVercelProjectMeta` | `false` upserts (if non-empty) but skips the eviction attempt entirely. |
| `snapshot.configured` | `boolean` | Caller-supplied to `syncVercelProjectMeta` | `false` skips the eviction attempt entirely, independent of `ok`. |

## Deep Linking

Not applicable: this module has no URL scheme, route, or navigable target of its own — it only reads and writes rows in `deploy_project_meta`.

## Localization

Not applicable: the only string this file produces is the `console.log`
eviction message under Logging below, which is an operator-facing log line, not
user-facing text, and the source defines no other string literal.

## Accessibility Options

Not applicable: this is a server-side module with no UI and responds to none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: none of the three exported functions consults a feature-flag system; every branch in the source is driven by `snapshot.ok`, `snapshot.configured`, `meta.length`, or `env.VERCEL_API_TOKEN`, never a flag lookup.

## Analytics

Not applicable: this file emits no analytics or telemetry event; its only externally visible effects are the storage writes it makes and the one log line described under Logging.

## Privacy

- **Data collected**: this module forwards the operator's own `VERCEL_API_TOKEN`
  and `VERCEL_TEAM_ID` (resolved from `env` or, via `providerConn`, from
  `config.secrets`) to `fetchVercelProductionStates`, and persists per-project
  metadata (`projectName`, `domain`, `gitRepo`, `gitBranch`, `rootDirectory`,
  `framework`) returned by that fetch. It collects nothing from, or about, an
  end user of the monitored product.
- **Storage**: the resolved token and team id are never persisted by this file
  itself — they exist only as call arguments for the duration of one refresh —
  while the project metadata rows they authorize fetching ARE persisted, as
  `deploy_project_meta` rows, which is this module's entire purpose.
- **Transmission**: this file makes no HTTP call itself; it hands the resolved
  token to `fetchVercelProductionStates`, which is what sends it to Vercel's own
  API over HTTPS.
- **Retention**: a project's metadata row is retained until either a later
  snapshot's eviction removes it (see `unconditional-upsert-on-nonempty-meta`
  and `eviction-diffs-live-set-against-stored-names`) or something outside this
  file deletes it directly; this module defines no separate TTL of its own —
  the source's own module comment states that "an erroneous eviction is
  repaired by the next cycle's upsert (5 minutes)," describing the monitor
  cycle's polling interval as the de facto correction window, not a retention
  policy enforced here.

## Logging

`syncVercelProjectMeta` calls `console.log('[project-meta] evicted N deleted
Vercel project(s): ...')` exactly once per invocation, and only when
`pruned.length > 0` — no log line is emitted for an eviction attempt that finds
nothing to prune, for the no-eviction-attempted branches, or for the upsert
itself. No other logger or `console.*` call appears anywhere in this file.

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | Reliability |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |

`unit-test-coverage` passes: `test/refresh-project-meta.int.test.ts` exercises
both `syncVercelProjectMeta` (five cases: full eviction, chunked upsert/prune,
partial-read no-eviction, unconfigured no-eviction, last-project-deleted
eviction) and `refreshVercelProjectMeta` (fetch-then-evict, and no-token
fail-closed) directly against a real storage instance, covering every branch
this recipe documents. `separation-of-concerns` passes: this file owns exactly
one concern — reconciling `deploy_project_meta`'s Vercel rows against a
snapshot — and delegates fetching to `fetchVercelProductionStates` and token
resolution to `providerConn`, reimplementing neither. `explicit-error-handling`
passes on its narrow "MUST NOT silently swallow" bar: none of the three
functions contains a `try`/`catch`, so every storage or fetch rejection
propagates intact to the caller rather than being caught and discarded.
`idempotent-operations` passes: calling `syncVercelProjectMeta` repeatedly with
the same snapshot converges to, and stays at, the same stored row set — the
upsert's `onConflictDoUpdate` and the eviction's set-diff are both naturally
idempotent per the source's own chunking implementation in `deploy-store.ts`.
`data-integrity` is rated partial, not failed, because within a single,
non-overlapping call the three-step reconcile is internally consistent (the
integration tests confirm the intended upsert/evict outcome every time); the
open question on concurrent-invocation-not-guarded is what keeps it from a full
pass — nothing in this file wraps the upsert, the read-back, and the delete in
one transaction or lock, so two overlapping invocations (this codebase's actual
callers include a periodic monitor cycle and a request-path cache, coordinated
with each other in neither file) could interleave and produce an incorrect
prune list or a lost upsert. `graceful-degradation` passes: a partial
(`ok: false`) or unconfigured read degrades to "upsert what came back (if any),
evict nothing" rather than either crashing or wiping the table on incomplete
information, which is exactly the behavior `no-eviction-attempt-when-not-ok-or-not-configured`
and the partial-read test vector pin.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
