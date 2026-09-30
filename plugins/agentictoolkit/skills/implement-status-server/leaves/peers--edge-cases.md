<!-- leaf: implement-status-server/peers--edge-cases · source: status-server-peers.md -->

# Status Server Peers

**Rules** (cite as `implement-status-server/peers--edge-cases#<slug>`):

- `null-and-empty-input` MUST — peer.token null or empty MUST send no Authorization header (poll-endpoint-and-auth); config.publicBaseUrl empty MUST …
- `boundary-values` MUST — a base URL written with its scheme's default port (:443 on https:, :80 on http:) MUST fold to the portless form, while …
- `concurrent-access` MUST — two overlapping fetchPeers calls writing the same peer's snapshot MUST NOT corrupt that row or cause either call to …
- `error-states` MUST — an HTTP response with ok: false, a thrown or aborted fetch, and a JSON body that fails to parse MUST all be treated …
- `offline-disconnected-state` MUST — AbortSignal.timeout(10_000) bounds every peer's request to a fixed 10-second budget, so a hanging or unreachable peer …

## Edge Cases

- **Null and empty input**: `peer.token` `null` or empty MUST send no `Authorization` header (poll-endpoint-and-auth); `config.publicBaseUrl` empty MUST make `isSelfPeerUrl` always return `false` (self-url-requires-known-public-base-url); zero active peers MUST make `fetchPeers`'s `Promise.all` resolve immediately over an empty array, touching no snapshot row, and MUST make `assembleFleet` return a one-element array containing only the self member.
- **Boundary values**: a base URL written with its scheme's default port (`:443` on `https:`, `:80` on `http:`) MUST fold to the portless form, while a non-default port MUST be preserved (normalize-canonical-form). `isDuplicatePeerError`'s `cause`-chain walk is bounded at three levels; a matching `code` nested at a fourth level or deeper MUST NOT be detected — this bound is a deliberate, documented limit of duplicate-error-detection, not an open gap.
- **Concurrent access**: two overlapping `fetchPeers` calls writing the same peer's snapshot MUST NOT corrupt that row or cause either call to throw — `storage.peers.upsertSnapshot`'s conflict target is `peerId` (external, `libsql/stores/peer-store.ts`), so the result is last-write-wins on that row. `assembleFleet`'s `listActive()` and `listSnapshots()` reads are two separate, non-transactional calls; a peer added, deactivated, or resnapshotted between them SHOULD be reflected in whichever read observes it first — the source gives no consistency guarantee stronger than "whatever each call currently returns."
- **Error states**: an HTTP response with `ok: false`, a thrown or aborted `fetch`, and a JSON body that fails to parse MUST all be treated identically — a single `reachable: false` upsert with the caught error's `message` (poll-failure-upsert, poll-http-error-becomes-failure).
  - **peer-snapshot-payload-unvalidated**: NEEDS REVIEW: Not implemented in source. `fetchPeers` stores the peer's `/snapshot` response body's `overall` field, and the whole `payload`, with no runtime type check — a peer returning a non-string `overall` (or a malformed `payload`) is stored and later read back by `assembleFleet` exactly as received, with no validation boundary anywhere in these three files.
- **Offline/disconnected state**: `AbortSignal.timeout(10_000)` bounds every peer's request to a fixed 10-second budget, so a hanging or unreachable peer MUST fail within that window rather than hang the whole `fetchPeers` call (poll-request-timeout). `fetchPeers` itself runs only on a full-sync cycle (`monitor/cycle-runner.ts`, external), not every cycle, so a peer that stays offline can show a stale card for up to one full-sync interval — that cadence is owned by the caller, not by these three files.
