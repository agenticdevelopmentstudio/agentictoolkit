---
id: b1622d2b-587f-4207-89ed-2130f8309f8c
title: Status Server Peers
domain: agentictoolkit://recipes/status-server-peers
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'The status server''s peers subsystem: base-url.ts''s URL/self/duplicate
  rules, fetch.ts''s fail-soft peer poller, and fleet.ts''s fleet-assembly contract.'
platforms:
- typescript
- web
tags:
- peers
- fleet
- monitoring
- polling
- server
depends-on:
- agenticdevelopercookbook://guidelines/implementing/networking/timeouts
- agenticdevelopercookbook://guidelines/implementing/networking/retry-and-resilience
- agenticdevelopercookbook://guidelines/implementing/security/token-handling
- agenticdevelopercookbook://guidelines/implementing/security/input-validation
related:
- agentictoolkit://recipes/status-server-config
- agentictoolkit://recipes/status-server-mcp
- agentictoolkit://recipes/status-server-monitor-cycle-runner
references:
- packages/web/packages/status-server/src/peers/base-url.ts (agentictoolkit)
- packages/web/packages/status-server/src/peers/fetch.ts (agentictoolkit)
- packages/web/packages/status-server/src/peers/fleet.ts (agentictoolkit)
- packages/web/packages/status-server/test/peer-base-url.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/peers-fetch.int.test.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

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

## Appearance

Not applicable — this is a fleet-peer polling and assembly module, not a visual component.

## States

Not applicable — this is a fleet-peer polling and assembly module, not a visual component.

## Accessibility

Not applicable — this is a fleet-peer polling and assembly module, not a visual component.

## Conformance Test Vectors

| ID | Requirement(s) | Input | Expected | Trace |
|---|---|---|---|---|
| status-server-peers-001 | normalize-canonical-form, normalize-unparseable-fallback | `normalizePeerBaseUrl("  https://b.example.com/// ")` | `"https://b.example.com"` | peer-base-url.test.ts |
| status-server-peers-002 | normalize-canonical-form | `normalizePeerBaseUrl("HTTPS://B.Example.COM")`, `normalizePeerBaseUrl("https://b.example.com:443")`, `normalizePeerBaseUrl("https://b.example.com/?x=1#frag")` | all three equal `"https://b.example.com"` | peer-base-url.test.ts |
| status-server-peers-003 | normalize-canonical-form | `normalizePeerBaseUrl("http://localhost:3000/")`, `normalizePeerBaseUrl("https://b.example.com/status/")` | `"http://localhost:3000"`, `"https://b.example.com/status"` | peer-base-url.test.ts |
| status-server-peers-004 | normalize-unparseable-fallback | `normalizePeerBaseUrl("  b.example.com/ ")` | `"b.example.com"` | peer-base-url.test.ts |
| status-server-peers-005 | valid-base-url-scheme | `isValidPeerBaseUrl("https://b.example.com")`, `isValidPeerBaseUrl("  https://b.example.com/ ")`, `isValidPeerBaseUrl("http://localhost:3000")` | all `true` | peer-base-url.test.ts |
| status-server-peers-006 | valid-base-url-scheme | `isValidPeerBaseUrl` on `"b.example.com"`, `"/relative"`, `""`, `"ftp://b.example.com"`, `"javascript:alert(1)"`, `"file:///etc/passwd"` | all `false` | peer-base-url.test.ts |
| status-server-peers-007 | same-base-url-comparison | `isSamePeerBaseUrl("https://self.example.com", "https://SELF.example.com:443/")` vs `("https://self.example.com", "https://other.example.com")` vs `("https://self.example.com", "http://self.example.com")` | `true`, `false`, `false` | peer-base-url.test.ts |
| status-server-peers-008 | duplicate-error-detection | `isDuplicatePeerError({ code: "SQLITE_CONSTRAINT_UNIQUE" })`, `isDuplicatePeerError(new Error("UNIQUE constraint failed: peers.base_url"))`, an error whose `cause.code` is `"SQLITE_CONSTRAINT_UNIQUE"` | all `true` | peer-base-url.test.ts |
| status-server-peers-009 | duplicate-error-negative | `isDuplicatePeerError(new Error("SQLITE_CONSTRAINT_NOTNULL"))`, `isDuplicatePeerError(new Error("connection refused"))`, `isDuplicatePeerError(null)`, `isDuplicatePeerError(undefined)` | all `false` | peer-base-url.test.ts |
| status-server-peers-010 | duplicate-message-constant | `DUPLICATE_PEER_MESSAGE` | matches `/already exists/i` | base-url.ts |
| status-server-peers-011 | poll-success-upsert | one active peer `{label:"B", baseUrl:"https://b.example.com", token:"t"}`; fake fetch resolves 200 with `{overall:"healthy"}` | stored row has `reachable === true`, `overall === "healthy"` | peers-fetch.int.test.ts |
| status-server-peers-012 | poll-failure-upsert, poll-never-rejects | same peer, no token; fake fetch throws `Error("ECONNREFUSED")` | `fetchPeers` resolves; stored row has `reachable === false`, `error` contains `"ECONNREFUSED"` | peers-fetch.int.test.ts |
| status-server-peers-013 | poll-endpoint-and-auth | active peer with `token: null` | outbound request headers contain no `Authorization` key | fetch.ts |
| status-server-peers-014 | poll-http-error-becomes-failure | fake fetch resolves a `Response` with `ok: false`, `status: 502` | stored row has `reachable: false`, `error` containing `"HTTP 502"` | fetch.ts |
| status-server-peers-015 | fleet-member-order, fleet-self-member-shape | `assembleFleet(storage, { label: "lewis", snapshot: {status:"ok"}, overall: "healthy" })` with zero active peers | one-element array; element 0 has `self: true`, `baseUrl: null`, `reachable: true`, `label: "lewis"`, `overall: "healthy"`, `payload: {status:"ok"}` | fleet.ts |
| status-server-peers-016 | fleet-peer-member-defaults, fleet-inactive-peers-excluded | one active peer with no matching snapshot row, plus one inactive peer that has a stored snapshot | returned array has exactly 2 elements (self + the active peer); the active peer's member has `overall: null`, `reachable: false`, `fetchedAt` equal to `new Date(0).toISOString()`; the inactive peer never appears | fleet.ts |
| status-server-peers-017 | fleet-peer-member-lookup | two active peers `p1`, `p2`; a stored snapshot exists only for `p2` (`overall:"down"`, `reachable:true`) | `p1`'s member is the epoch default of status-server-peers-016; `p2`'s member reflects only `p2`'s own snapshot | fleet.ts |
| status-server-peers-018 | self-url-canonical-match, self-url-requires-known-public-base-url | `isSelfPeerUrl("https://lewis.example.com", { publicBaseUrl: "https://LEWIS.example.com:443/" })` then `isSelfPeerUrl("https://lewis.example.com", { publicBaseUrl: "" })` | `true`, then `false` | base-url.ts |
| status-server-peers-019 | peer-snapshot-payload-unvalidated | peer responds 200 with JSON body `{overall: 42}` | `fetchPeers` still resolves; stored row has `reachable: true`, `error: null`, and `overall` stored as the numeric value `42` unchanged | fetch.ts |

## Edge Cases

- **Null and empty input**: `peer.token` `null` or empty MUST send no `Authorization` header (poll-endpoint-and-auth); `config.publicBaseUrl` empty MUST make `isSelfPeerUrl` always return `false` (self-url-requires-known-public-base-url); zero active peers MUST make `fetchPeers`'s `Promise.all` resolve immediately over an empty array, touching no snapshot row, and MUST make `assembleFleet` return a one-element array containing only the self member.
- **Boundary values**: a base URL written with its scheme's default port (`:443` on `https:`, `:80` on `http:`) MUST fold to the portless form, while a non-default port MUST be preserved (normalize-canonical-form). `isDuplicatePeerError`'s `cause`-chain walk is bounded at three levels; a matching `code` nested at a fourth level or deeper MUST NOT be detected — this bound is a deliberate, documented limit of duplicate-error-detection, not an open gap.
- **Concurrent access**: two overlapping `fetchPeers` calls writing the same peer's snapshot MUST NOT corrupt that row or cause either call to throw — `storage.peers.upsertSnapshot`'s conflict target is `peerId` (external, `libsql/stores/peer-store.ts`), so the result is last-write-wins on that row. `assembleFleet`'s `listActive()` and `listSnapshots()` reads are two separate, non-transactional calls; a peer added, deactivated, or resnapshotted between them SHOULD be reflected in whichever read observes it first — the source gives no consistency guarantee stronger than "whatever each call currently returns."
- **Error states**: an HTTP response with `ok: false`, a thrown or aborted `fetch`, and a JSON body that fails to parse MUST all be treated identically — a single `reachable: false` upsert with the caught error's `message` (poll-failure-upsert, poll-http-error-becomes-failure).
  - **peer-snapshot-payload-unvalidated**: NEEDS REVIEW: Not implemented in source. `fetchPeers` stores the peer's `/snapshot` response body's `overall` field, and the whole `payload`, with no runtime type check — a peer returning a non-string `overall` (or a malformed `payload`) is stored and later read back by `assembleFleet` exactly as received, with no validation boundary anywhere in these three files.
- **Offline/disconnected state**: `AbortSignal.timeout(10_000)` bounds every peer's request to a fixed 10-second budget, so a hanging or unreachable peer MUST fail within that window rather than hang the whole `fetchPeers` call (poll-request-timeout). `fetchPeers` itself runs only on a full-sync cycle (`monitor/cycle-runner.ts`, external), not every cycle, so a peer that stays offline can show a stale card for up to one full-sync interval — that cadence is owned by the caller, not by these three files.

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

## Deep Linking

Not applicable — none of the three files constructs or consumes an application deep link; every URL built is a peer server's own API address (`${peer.baseUrl}/snapshot`), never a link into this application.

## Localization

| String Key | Default (en) | Context |
|---|---|---|
| n/a — `DUPLICATE_PEER_MESSAGE` (exported constant, `base-url.ts`) | `A peer with that base URL already exists` | Hardcoded English, shared verbatim by the HTTP `/peers` route (a 409 body) and the `add_peer` MCP tool (both external to these three files) so both surfaces show the same sentence; neither this constant nor either external caller runs it through a localization/i18n layer. |
| n/a — `fetchPeers`'s caught-error `message` (`fetch.ts`) | e.g. `HTTP 502`, or the underlying error's own message | Persisted verbatim into `peer_snapshots.error`; whatever external surface displays it receives this exact English string with no localization. |

## Accessibility Options

Not applicable — none of the three files renders anything; Reduce Motion, Increase Contrast, and Differentiate Without Color have no surface here.

## Feature Flags

Not applicable — none of the three files consults a feature-flag system; a peer's participation is gated only by `PeerRow.isActive` (configuration data), never a flag key.

## Analytics

Not applicable — none of the three files emits a self-referential analytics or telemetry event about its own invocation.

## Privacy

- **Data collected**: `fetch.ts` reads and transiently holds one `PeerRow`'s `baseUrl` and `token` per active peer per poll (from `storage.peers.listActive()`, external), plus whatever the peer's own `/snapshot` response body contains (its `overall` field and the full `payload`), which it persists verbatim. `fleet.ts` reads that mirrored data back plus this monitor's own live snapshot (the caller-supplied `self.snapshot`). Neither file collects end-user personal data; every value is operational/infrastructure data describing the monitors themselves.
- **Storage**: neither file writes storage directly — that is the injected `Storage`/`PeerStore` port's job (external); `fetch.ts` calls only `storage.peers.upsertSnapshot`, and `fleet.ts` calls only the port's read methods.
- **Transmission**: per poll-endpoint-and-auth, `fetch.ts` sends a peer's `token` only via the `Authorization: Bearer` request header, never in the URL, query string, or body. The transport scheme (`http://` vs `https://`) is whatever `peer.baseUrl` specifies; neither file enforces `https://` at request time — that scheme check happens earlier, at write time, in `isValidPeerBaseUrl`, which accepts either scheme.
- **Retention**: neither file caches or retains a `token` beyond the single outbound request it makes for that peer. The persisted artifact is the `peer_snapshots` row (`payload`/`overall`/`reachable`/`error`); its retention policy belongs to the `PeerStore`/schema, external to these three files.

## Logging

None of the three files calls `console.*` or any logger; `fetchPeers` and `fleet.ts` communicate every outcome — success, HTTP failure, thrown error, or missing snapshot — through their return values and the `peer_snapshots` rows they write, never through a log line.

## Platform Notes

- **React/Web** (source platform): all three files live under `packages/web/packages/status-server/src/peers/`, depending only on the package's own `../storage/ports` types (`Storage`, `PeerStore`, `PeerRow`, `PeerSnapshotRow`) and `../config/port`'s `StatusConfig`, plus Node/Web-standard `fetch`, `AbortSignal.timeout`, and `URL`; no ORM or framework import crosses into these three files — the drizzle-backed implementation lives in `libsql/stores/peer-store.ts`, external to this recipe.
- **SwiftUI**: model `PeerRow`/`PeerSnapshotRow`/`FleetMember` as `Sendable` structs with the same optional fields; `normalizePeerBaseUrl`/`isValidPeerBaseUrl`/`isSamePeerBaseUrl`/`isSelfPeerUrl` become pure functions over Foundation's `URLComponents` (needed for the lower-casing and default-port folding that bare `URL` does not do); `fetchPeers` becomes an `async` function over `URLSession` using `URLRequest.timeoutInterval` in place of `AbortSignal.timeout`, dispatching every peer concurrently via `withThrowingTaskGroup` in place of `Promise.all`; `assembleFleet` stays a pure `async` function over an injected storage protocol.
- **Compose**: the same structural mapping as SwiftUI — Kotlin `data class`es for `PeerRow`/`PeerSnapshotRow`/`FleetMember`, `java.net.URI` for the base-URL folding, `coroutineScope { peers.map { async { ... } } }.awaitAll()` in place of `Promise.all`, and `withTimeout(10_000)` in place of `AbortSignal.timeout(10_000)`.
- **AppKit/UIKit**: the identical mapping to SwiftUI's; `URLSession`'s `data(for:)` with a per-request `URLSessionConfiguration.timeoutIntervalForRequest` is the direct analogue of `fetchPeers`'s per-peer 10-second bound.
- **WinUI 3**: a .NET port models `PeerRow`/`PeerSnapshotRow`/`FleetMember` as `record` types with nullable properties; `normalizePeerBaseUrl`/`isValidPeerBaseUrl`/`isSamePeerBaseUrl` become static methods over `System.Uri` (`Uri.TryCreate` plus explicit lower-casing of `Uri.Scheme`/`Uri.Host`, since `Uri` does not fold case the way `new URL()` does); `fetchPeers` becomes an `async Task` using `HttpClient` with a per-call `CancellationTokenSource.CancelAfter(TimeSpan.FromSeconds(10))` as the `AbortSignal.timeout` analogue, and `Task.WhenAll(peers.Select(FetchOneAsync))` in place of `Promise.all`; `System.Text.Json` replaces `res.json()` for the peer's `/snapshot` body; `assembleFleet`'s equivalent is a plain `async Task<IReadOnlyList<FleetMember>>` composing an injected storage abstraction — no `ObservableCollection`/`INotifyPropertyChanged` counterpart applies, since neither function exposes a live-bound collection, only a one-shot result; `Windows.Storage` has no role either, since persistence is the external `PeerStore`'s concern.

## Design Decisions

- **Decision**: `normalizePeerBaseUrl` folds case, the default port, and any query/fragment away, but preserves a non-default port and a path.
  **Rationale**: the `uniq_peer_base_url` index is byte-exact, so anything that varies without naming a different endpoint must fold out before insert or the same monitor could be added twice; a non-default port or a path does name a different endpoint, so those are kept (source comment, `base-url.ts`).
  **Approved**: pending

- **Decision**: an unparseable base-URL string is normalized by trim-and-strip-trailing-slash rather than rejected or thrown.
  **Rationale**: callers normalize before they know whether validation has passed — `isValidPeerBaseUrl` runs as a separate step — so `normalizePeerBaseUrl` is total by design and never blocks that later validation (source comment, `base-url.ts`).
  **Approved**: pending

- **Decision**: `isSelfPeerUrl` treats an empty `config.publicBaseUrl` as "this host's own URL is unknown," never flagging any value as self.
  **Rationale**: stated directly in the source comment; `publicBaseUrl`'s own primary purpose, per `StatusConfig`'s doc comment, is the browser-facing origin for OAuth callbacks, and it defaults to `""` when unset, so treating "unknown" as "cannot self-match" avoids a false-positive self-guard on a monitor that has never had `publicBaseUrl` configured.
  **Approved**: pending

- **Decision**: `fetchPeers` never retries a failed or timed-out peer request within one call, and treats a non-`ok` response, a thrown request, and a timeout identically — one `reachable: false` upsert.
  **Rationale**: this is a plain fact about the code's behavior, recorded here per source fidelity rather than an invented justification; the effect is that a peer failing one poll is retried only by the next scheduled full-sync cycle (`monitor/cycle-runner.ts`, external), never within `fetchPeers` itself.
  **Approved**: pending

- **Decision**: `assembleFleet` reports a never-polled peer's `fetchedAt` as `new Date(0).toISOString()` (the Unix epoch) rather than `null` or the current time.
  **Rationale**: a plain fact about the code, noted only briefly in-source; recorded here because a naive reader might expect `null` — a board rendering `fetchedAt` as "time since last seen" must recognize the epoch sentinel to distinguish "never polled" from a normal, if old, timestamp.
  **Approved**: pending

- **Decision**: this recipe's `related` field links to `status-server-config`, `status-server-mcp`, and `status-server-monitor-cycle-runner` one-directionally; the reverse links on those three recipes were not added.
  **Rationale**: authored under an explicit constraint to write only this one file and touch no other; cross-recipe-consistency's own text allows a unidirectional reference ("acceptable but bidirectional is preferred"), so this is a known, intentional gap in the preferred state rather than an oversight, mirroring the same documented choice already made in `status-server-config.md`.
  **Approved**: pending

- **Decision**: the separate `status-web` package deliberately duplicates `normalizePeerBaseUrl`/`isValidPeerBaseUrl` in its own `src/lib/peer-url.ts` (external to these three files) for client-side dirty-checking.
  **Rationale**: that file's own header comment states the mirror is deliberate — the board is a separate Next app that cannot import the backend's module, and "the backend stays the authority" — recorded here as a known, intentional duplication that must be kept in step by hand, not an accidental drift within this recipe's scope to fix.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [timeout-configuration](agenticdevelopercookbook://compliance/access-patterns#timeout-configuration) | passed | Access Patterns |
| [retry-with-backoff](agenticdevelopercookbook://compliance/access-patterns#retry-with-backoff) | failed | Access Patterns |
| [error-response-handling](agenticdevelopercookbook://compliance/access-patterns#error-response-handling) | passed | Access Patterns |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | Reliability |
| [no-pii-in-logs](agenticdevelopercookbook://compliance/privacy-and-data#no-pii-in-logs) | passed | Privacy and Data |
| [secure-transport](agenticdevelopercookbook://compliance/security#secure-transport) | partial | Security |

`separation-of-concerns` passes: all three files depend only on the `Storage`/`PeerStore` port and `StatusConfig`, never on the libSQL/drizzle implementation directly. `unit-test-coverage` is `partial`: `base-url.ts`'s and `fetch.ts`'s success and failure paths are directly tested (`peer-base-url.test.ts`, `peers-fetch.int.test.ts`), but `fleet.ts`/`assembleFleet` and `isSelfPeerUrl` have no dedicated test among the given sources. `explicit-error-handling` passes: every peer's failure (non-`ok`, thrown, unparseable JSON) is caught per-peer and turned into a stored `error` string; no failure is swallowed silently. `timeout-configuration` passes: every peer request is bounded by `AbortSignal.timeout(10_000)`. `retry-with-backoff` fails as written: `fetchPeers` makes exactly one attempt per peer per call, with no retry or backoff; a failed poll is only retried by the next full-sync cycle, external to these files (see the retry Design Decision). `error-response-handling` passes: an HTTP error response, a thrown request, and a JSON-parse failure are all normalized to the same `reachable: false` shape. `graceful-degradation` passes: one peer's failure never prevents any other peer's snapshot from being attempted or stored, and never causes `fetchPeers` itself to reject. `data-integrity` is `partial`: snapshot storage is keyed and idempotent (`upsertSnapshot`'s `peerId` conflict target, external), but the open question on `peer-snapshot-payload-unvalidated` means a malformed `overall`/`payload` from a peer is stored and read back unchecked. `no-pii-in-logs` passes: none of the three files logs anything at all; no `token`, `baseUrl`, or snapshot `payload` is ever written to a log line. `secure-transport` is `partial`: a peer's `token` is sent only via the `Authorization: Bearer` header, never in a URL or body, but neither `isValidPeerBaseUrl` nor `fetchPeers` requires `https://` — an `http://` peer base URL is accepted and polled the same as an `https://` one.

## Change History

| Version | Date | Author | Notes |
|---|---|---|---|
| 1.0.0 | | | Initial creation from `src/peers/base-url.ts`, `src/peers/fetch.ts`, and `src/peers/fleet.ts`; one open question recorded on the unvalidated peer-snapshot `overall`/`payload` field. |
