<!-- leaf: implement-status-server-monitor-2/refresh-project-meta · source: status-server-monitor-refresh-project-meta.md -->

**Rules** (cite as `implement-status-server-monitor-2/refresh-project-meta#<slug>`):

- `sole-writer-of-vercel-rows` MUST
- `unconditional-upsert-on-nonempty-meta` MUST
- `no-eviction-attempt-when-not-ok-or-not-configured` MUST
- `live-null-means-no-verdict` MUST
- `eviction-diffs-live-set-against-stored-names` MUST
- `delete-only-when-pruned-nonempty` MUST
- `empty-meta-with-ok-and-configured-evicts-everything` MUST
- `result-returns-remaining-live-set` MUST
- `configured-gate-not-inferred-from-meta-length` MUST
- `fail-closed-no-network-call-without-token` MUST
- `meta-only-fetch-mode` MUST
- `refresh-result-ok-mirrors-fetch-ok` MUST
- `config-resolution-delegated-to-provider-conn` MUST

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

## Configuration

| Name | Type | Source | Effect |
|------|------|--------|--------|
| `env.VERCEL_API_TOKEN` | `string \| undefined` | `refreshVercelProjectMeta`'s `env` parameter | Presence alone sets `configured`; absence short-circuits to a no-network, no-eviction result. |
| `env.VERCEL_TEAM_ID` | `string \| undefined` | `refreshVercelProjectMeta`'s `env` parameter | Forwarded to `fetchVercelProductionStates`; does not itself gate `configured`. |
| `config.secrets.VERCEL_API_TOKEN` / `config.secrets.VERCEL_TEAM_ID` | `string \| undefined` (by-name lookup) | Resolved via `providerConn(storage, config)` inside `refreshVercelProjectMetaFromConfig` | Same effect as the two rows above, one layer further from the caller. |
| `snapshot.ok` | `boolean` | Caller-supplied to `syncVercelProjectMeta` | `false` upserts (if non-empty) but skips the eviction attempt entirely. |
| `snapshot.configured` | `boolean` | Caller-supplied to `syncVercelProjectMeta` | `false` skips the eviction attempt entirely, independent of `ok`. |

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

