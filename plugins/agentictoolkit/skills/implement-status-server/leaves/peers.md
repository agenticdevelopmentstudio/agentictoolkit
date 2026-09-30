<!-- leaf: implement-status-server/peers · source: status-server-peers.md -->

**Rules** (cite as `implement-status-server/peers#<slug>`):

- `normalize-canonical-form` MUST
- `normalize-unparseable-fallback` MUST
- `valid-base-url-scheme` MUST
- `same-base-url-comparison` MUST
- `self-url-requires-known-public-base-url` MUST
- `self-url-canonical-match` MUST
- `duplicate-message-constant` MUST
- `duplicate-error-detection` MUST
- `duplicate-error-negative` MUST
- `poll-active-peers-only` MUST
- `poll-concurrent` MUST
- `poll-endpoint-and-auth` MUST
- `poll-request-timeout` MUST
- `poll-success-upsert` MUST
- `poll-http-error-becomes-failure` MUST
- `poll-failure-upsert` MUST
- `poll-never-rejects` MUST
- `poll-fetched-at-per-peer` MUST
- `fleet-member-order` MUST
- `fleet-self-member-shape` MUST
- `fleet-peer-member-lookup` MUST
- `fleet-peer-member-defaults` MUST
- `fleet-inactive-peers-excluded` MUST

## Overview

Three files under `src/peers/` are the status server's peer-fleet subsystem. `base-url.ts` is the one definition of what a peer's `baseUrl` may be and how it is compared: `normalizePeerBaseUrl` (the canonical stored form the `uniq_peer_base_url` index relies on being byte-exact), `isValidPeerBaseUrl` (the absolute-http(s) gate the write path validates with), `isSamePeerBaseUrl` and `isSelfPeerUrl` (canonical-form comparisons used to stop a monitor from adding itself as its own peer), and `DUPLICATE_PEER_MESSAGE`/`isDuplicatePeerError` (the one user-facing sentence and the one unique-constraint detector every write path shares). `fetch.ts`'s `fetchPeers` polls every currently active peer's `/snapshot` endpoint concurrently and fail-softly mirrors each result — reachable or not — into `peer_snapshots`, never throwing regardless of how many peers are unreachable. `fleet.ts`'s `assembleFleet` reads that mirror back out, combines it with this monitor's own freshly built snapshot, and returns the ordered `FleetMember[]` a fleet board renders: self first, then one member per active peer, each annotated with its last-known reachability and freshness. All storage access in `fetch.ts` and `fleet.ts` goes through the injected `Storage`/`PeerStore` port (`../storage/ports`, external to these three files); the SQLite/libSQL implementation, the peer CRUD write path (`createPeer`/`updatePeer`/`deletePeer`), and every HTTP route or MCP tool that calls into these three files are likewise external.

## Behavioral Requirements

### Peer base URL contract (`base-url.ts`)

- **normalize-canonical-form**: `normalizePeerBaseUrl` MUST return the canonical stored form of a well-formed absolute URL: `scheme://host[:port][/path]`, with the scheme and host lower-cased, the scheme's default port dropped, no trailing slash, and no query string or fragment.
- **normalize-unparseable-fallback**: `normalizePeerBaseUrl` MUST NOT throw; when the input does not parse as a URL, it MUST return the trimmed input with every trailing slash stripped.
- **valid-base-url-scheme**: `isValidPeerBaseUrl` MUST return `true` only when the trimmed input parses as an absolute URL whose protocol is `http:` or `https:`, and `false` for a bare host, a relative path, the empty string, or any other scheme (including `ftp:`, `javascript:`, and `file:`).
- **same-base-url-comparison**: `isSamePeerBaseUrl` MUST return `true` for two base URLs if and only if `normalizePeerBaseUrl` produces the identical string for both.
- **self-url-requires-known-public-base-url**: `isSelfPeerUrl` MUST return `false` for every input when `config.publicBaseUrl` is the empty string.
- **self-url-canonical-match**: When `config.publicBaseUrl` is non-empty, `isSelfPeerUrl` MUST return `true` if and only if `isSamePeerBaseUrl(value, config.publicBaseUrl)` is `true`.
- **duplicate-message-constant**: `DUPLICATE_PEER_MESSAGE` MUST be the exported string literal `A peer with that base URL already exists`.
- **duplicate-error-detection**: `isDuplicatePeerError` MUST return `true` when the error passed in, or any object reachable by following up to three levels of its `cause` property, has a `code` field containing `SQLITE_CONSTRAINT_UNIQUE` or a `message` field matching (case-insensitively) `unique constraint failed`.
- **duplicate-error-negative**: `isDuplicatePeerError` MUST return `false` for `null`, `undefined`, an error with an unrelated code such as `SQLITE_CONSTRAINT_NOTNULL`, or an error describing an unrelated failure such as a connection refusal.

### Peer polling (`fetch.ts`)

- **poll-active-peers-only**: `fetchPeers` MUST fetch a snapshot only for the rows `storage.peers.listActive()` returns, never for a peer that is not active.
- **poll-concurrent**: `fetchPeers` MUST issue every active peer's `/snapshot` request concurrently, via `Promise.all` over the active-peer rows, never sequentially.
- **poll-endpoint-and-auth**: For each peer, `fetchPeers` MUST request `${peer.baseUrl}/snapshot` and MUST set an `Authorization: Bearer ${peer.token}` header if and only if `peer.token` is truthy; when `peer.token` is `null` or empty, it MUST send no `Authorization` header.
- **poll-request-timeout**: Each peer's request MUST be bounded by `AbortSignal.timeout(10_000)` (10,000 ms).
- **poll-success-upsert**: When the response's `ok` is `true`, `fetchPeers` MUST upsert a `PeerSnapshotUpsert` for that peer with `reachable: true`, `error: null`, `payload` set to the parsed JSON body, and `overall` set to that body's `overall` field, defaulting to `null` when the field is absent.
- **poll-http-error-becomes-failure**: When the response's `ok` is `false`, `fetchPeers` MUST throw an `Error` naming the HTTP status and catch it within that same peer's own handler, producing the same outcome as poll-failure-upsert.
- **poll-failure-upsert**: On any failure for a peer — a non-`ok` response, a thrown or aborted `fetch` call, or a JSON body that fails to parse — `fetchPeers` MUST upsert a `PeerSnapshotUpsert` for that peer with `reachable: false`, `payload: null`, `overall: null`, and `error` set to the caught error's `message`.
- **poll-never-rejects**: The `Promise` `fetchPeers` returns MUST resolve regardless of how many, or which, individual peers fail; no single peer's failure MUST cause `fetchPeers` itself to reject or prevent any other peer's snapshot from being attempted or stored.
- **poll-fetched-at-per-peer**: Each upserted snapshot's `fetchedAt` MUST be a `Date` captured independently for that peer, at the start of that peer's own fetch attempt.

### Fleet assembly (`fleet.ts`)

- **fleet-member-order**: `assembleFleet` MUST return an array whose first element is the self member and whose remaining elements are one `FleetMember` per row from `storage.peers.listActive()`, in the order that call returns them.
- **fleet-self-member-shape**: The self member MUST have `self: true`, `baseUrl: null`, `reachable: true`, `label`/`overall`/`payload` taken verbatim from the caller-supplied `self` argument's `label`/`overall`/`snapshot` fields respectively, and `fetchedAt` set to the current time at the moment `assembleFleet` is called.
- **fleet-peer-member-lookup**: For each active peer row, `assembleFleet` MUST look up that peer's latest snapshot from `storage.peers.listSnapshots()` by matching `peerId` to the peer's `id`, and MUST populate that member's `overall`/`reachable`/`payload`/`baseUrl`/`label` from that peer row and its matched snapshot (or their documented defaults, see fleet-peer-member-defaults) — never from any other peer's snapshot.
- **fleet-peer-member-defaults**: When no stored snapshot matches a peer's `id`, `assembleFleet` MUST default that member's `overall` to `null`, `reachable` to `false`, `payload` to `null`, and `fetchedAt` to `new Date(0).toISOString()` (the Unix epoch).
- **fleet-inactive-peers-excluded**: `assembleFleet` MUST exclude a peer from the returned array entirely when that peer is not active, even when a snapshot row for it exists in storage.

## Configuration

| Option | Type | Default | Description |
|---|---|---|---|
| `peer.baseUrl` | `string` (`PeerRow` field, external — from `storage.peers.listActive()`) | set via `createPeer`/`updatePeer` (external) | The peer's canonical base URL; `fetchPeers` appends `/snapshot` to it. |
| `peer.token` | `string \| null` (`PeerRow` field) | `null` | Bearer credential sent to the peer; when absent, `fetchPeers` sends no `Authorization` header. |
| `peer.isActive` | `boolean` (`PeerRow` field) | `true` (the `peers` table's DB default; the CRUD path is external) | Gates both `fetchPeers`'s poll roster and `assembleFleet`'s member roster — both read from the same `listActive()` call. |
| poll timeout | `number` literal in `fetch.ts` | `10_000` | Not exported, not caller-configurable; the `AbortSignal.timeout` budget for one peer's `/snapshot` request. |
| `config.publicBaseUrl` | `string` (`StatusConfig` field) | `""` | The self-detection input to `isSelfPeerUrl`; empty means "unknown," so no URL is ever flagged as self. |
| `fetchImpl` | `typeof fetch` (optional `fetchPeers` parameter) | global `fetch` | Substitutable for tests; production callers never pass this argument. |
| `self` argument | `{ label: string; snapshot: unknown; overall: string \| null }` (`assembleFleet` parameter) | caller-supplied, no default | This monitor's own compact status, provided by the caller (`routes/fleet.ts`, external) on every call. |

## Localization

| String Key | Default (en) | Context |
|---|---|---|
| n/a — `DUPLICATE_PEER_MESSAGE` (exported constant, `base-url.ts`) | `A peer with that base URL already exists` | Hardcoded English, shared verbatim by the HTTP `/peers` route (a 409 body) and the `add_peer` MCP tool (both external to these three files) so both surfaces show the same sentence; neither this constant nor either external caller runs it through a localization/i18n layer. |
| n/a — `fetchPeers`'s caught-error `message` (`fetch.ts`) | e.g. `HTTP 502`, or the underlying error's own message | Persisted verbatim into `peer_snapshots.error`; whatever external surface displays it receives this exact English string with no localization. |

## Privacy

- **Data collected**: `fetch.ts` reads and transiently holds one `PeerRow`'s `baseUrl` and `token` per active peer per poll (from `storage.peers.listActive()`, external), plus whatever the peer's own `/snapshot` response body contains (its `overall` field and the full `payload`), which it persists verbatim. `fleet.ts` reads that mirrored data back plus this monitor's own live snapshot (the caller-supplied `self.snapshot`). Neither file collects end-user personal data; every value is operational/infrastructure data describing the monitors themselves.
- **Storage**: neither file writes storage directly — that is the injected `Storage`/`PeerStore` port's job (external); `fetch.ts` calls only `storage.peers.upsertSnapshot`, and `fleet.ts` calls only the port's read methods.
- **Transmission**: per poll-endpoint-and-auth, `fetch.ts` sends a peer's `token` only via the `Authorization: Bearer` request header, never in the URL, query string, or body. The transport scheme (`http://` vs `https://`) is whatever `peer.baseUrl` specifies; neither file enforces `https://` at request time — that scheme check happens earlier, at write time, in `isValidPeerBaseUrl`, which accepts either scheme.
- **Retention**: neither file caches or retains a `token` beyond the single outbound request it makes for that peer. The persisted artifact is the `peer_snapshots` row (`payload`/`overall`/`reachable`/`error`); its retention policy belongs to the `PeerStore`/schema, external to these three files.

