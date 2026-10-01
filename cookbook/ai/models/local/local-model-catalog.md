---
id: 79c8f46f-e934-46d1-8d0e-4bbee625e163
title: Local Model Catalog
domain: agentictoolkit://cookbook/ai/models/local/local-model-catalog
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A cache mapping a local model server's model name to its on-disk size in
  bytes, fetched from Ollama's native /api/tags endpoint.
platforms:
- swift
- macos
tags:
- local-model
- caching
- ollama
- ai-plugin
depends-on: []
related: []
references:
- packages/apple/AgenticToolkit/AIPluginKit/LocalModelCatalog.swift (agentictoolkit)
- packages/apple/AgenticToolkit/AIPluginKit/LocalModelServer.swift (agentictoolkit)
- packages/apple/AgenticToolkit/AIPluginKit/LocalInferenceGuard.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AIPluginKitTests/LocalModelCatalogTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AIPluginKitTests/LocalModelServerTests.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Local Model Catalog

## Overview

The local model catalog is a **logic** component — no visual surface — that
resolves the on-disk size, in bytes, of a model hosted by a local model
server, so a caller such as the inference guard can weigh a model's
footprint against the machine's RAM budget before allowing it to load. A
model server exposes no size information over the OpenAI-compatible `/v1`
surface most gateways speak; Ollama's own native `/api/tags` listing is the
only one that reports a `size` per model, so the catalog derives that native
URL from the caller's OpenAI-compatible base URL (via the model server
helper's native tags URL derivation), fetches and parses it (the model
server helper's response parser), and looks up one model's size (the model
server helper's size resolver, which tolerates the `:latest` shorthand).
Because that fetch is a network round trip with real per-call cost — and the
guard runs ahead of every local-model request — results are cached per base
URL with independent time-to-live windows for success (`successTTL`, default
300 seconds) and failure (`failureTTL`, default 60 seconds): a down or
non-Ollama server is retried on a slower cadence than a healthy one, and a
failed refetch never discards a server's last known-good sizes — stale sizes
still serve the guard, because a model already known to be over budget must
never be forgotten just because the server is momentarily busy or
unreachable. One shared, process-wide instance is available for callers that
do not construct their own; the inference guard defaults to it when
constructed without an explicit catalog.

## Behavioral Requirements

- **serialized-state-access**: The catalog MUST serialize access to its
  internal state (the fetch function, both TTLs, and the cache) so every
  call to the size lookup, or the internal per-server sizes lookup, on one
  instance executes without a data race, interleaved only at defined
  suspension points.
- **shared-singleton**: The catalog MUST provide one process-wide instance
  for callers that do not construct their own; it is the default used when
  the inference guard is constructed without an explicit catalog.
- **fetcher-is-injectable**: Construction MUST accept an injectable fetch
  function that asynchronously returns the response bytes for a given URL
  (or fails), defaulting to a built-in live implementation, so a caller MAY
  substitute a stub fetch function with no real network dependency.
- **default-ttls**: Construction MUST default the success TTL to `300` and
  the failure TTL to `60` (seconds) when the caller does not override them.
- **live-fetcher-request-shape**: The built-in live fetch implementation
  MUST issue a `GET` request with a timeout of `5` seconds, and MUST fail
  when the response is not a successful (HTTP `200`) response.
- **size-lookup-short-circuits-on-unknown-sizes**: The size lookup MUST
  return nothing, without attempting the size resolution, when the
  per-server sizes lookup returns nothing for the given base URL; otherwise
  it MUST return the resolved size for that model within those sizes.
- **cache-key-is-the-raw-base-url**: The cache MUST key entries by the exact
  base URL string passed in, with no normalization applied to the key
  itself. The native tags URL derivation trims whitespace, trailing slashes,
  and a trailing `/v1` when deriving the fetch URL, but that normalization
  is not reflected back into the cache key — two base URL spellings that
  resolve to the same native tags URL (e.g. with and without a trailing
  slash) MUST be cached and fetched independently of one another.
- **cache-freshness-window**: For a cached entry, the per-server sizes
  lookup MUST treat it as fresh — returning its sizes without fetching —
  only when the elapsed time since it was fetched is strictly less than the
  failure TTL if that entry recorded a failed fetch, or strictly less than
  the success TTL otherwise; an entry aged exactly the success TTL or
  failure TTL seconds MUST be treated as expired, not fresh.
- **unresolvable-base-url-is-uncached**: When the native tags URL derivation
  cannot resolve a URL for the given base URL (e.g. an empty string, or a
  string that trims to empty once a trailing `/v1` and slashes are
  stripped), the per-server sizes lookup MUST return nothing immediately,
  without attempting a fetch and without creating or updating a cache entry
  for that base URL.
- **fetch-throw-yields-no-data**: When a fetch attempt fails, the
  per-server sizes lookup MUST treat the attempt as having produced no data
  rather than propagating the failure to its own caller.
- **empty-parse-is-treated-as-failure**: When a fetch attempt succeeds but
  the response parses to an empty set of sizes, the per-server sizes lookup
  MUST treat the attempt identically to a fetch failure: the resulting cache
  entry MUST be marked as a failed fetch and MUST be re-checked on the
  failure TTL cadence, not the success TTL.
- **stale-while-error**: When an attempt yields no data for a base URL that
  has a prior cached entry, the per-server sizes lookup MUST retain that
  entry's last known sizes rather than clearing them.
- **never-known-stays-nil**: When an attempt yields no data for a base URL
  with no prior cached entry, or whose prior entry's sizes were already
  unknown, the per-server sizes lookup MUST cache and return nothing for
  that base URL.
- **every-attempt-refreshes-the-timestamp**: Every time the per-server sizes
  lookup performs a fetch attempt — whether it succeeds, fails, or parses to
  an empty set — it MUST replace any prior entry for that base URL with a
  new one recording the current fetch time and whether that attempt failed.
- **first-lookup-always-fetches**: The per-server sizes lookup MUST attempt
  a fetch (subject to unresolvable-base-url-is-uncached) the first time a
  base URL is looked up, since no cache entry exists yet to satisfy
  cache-freshness-window.
- **size-tolerates-latest-suffix**: The size lookup MUST resolve a size for
  a model when the parsed sizes only contain that model name suffixed with
  `:latest` (delegated to the model server helper's size resolver).

Three concerns the catalog's own purpose calls for are left undefined:

- **concurrent-fetch-deduplication**: NEEDS REVIEW: Not implemented. The
  per-server sizes lookup checks the cache for freshness, then waits on the
  fetch, and only afterward writes the new entry. Because that wait is
  reentrant, two concurrent lookups for the same expired or uncached base
  URL can both observe the same pre-fetch cache state and both trigger a
  fetch; the entry that ends up cached is whichever call's write executes
  last, not necessarily the one from the most recently issued request, and
  the server is hit twice (or more) for one logical refresh instead of once.
  No in-flight-request tracking or coalescing exists. This cannot be
  resolved from the catalog's own behavior alone; it requires either an
  explicit statement that duplicate concurrent fetches are an accepted cost
  (the guard's own call sites are typically not highly concurrent) or an
  in-flight-request cache keyed by base URL.
- **base-url-locality-is-unenforced**: NEEDS REVIEW: Not implemented. Both
  the catalog's own stated purpose (fetching and caching a *local* server's
  sizes) and the model server helper's loopback-detection function describe
  and can test for a local server, but the catalog never calls that check
  before deriving a tags URL from the base URL and issuing a fetch to it. A
  caller passing a non-loopback base URL — by misconfiguration or a future
  provider that reuses this component — causes the catalog to make an
  outbound request to that remote host on every cache miss, with nothing to
  prevent it. The inference guard's own stated assumption (that its decision
  covers one request to a loopback provider) states the same assumption
  without enforcing it either. Resolved by either calling the
  loopback-detection check and failing closed (returning nothing) for a
  non-loopback base URL, or a maintainer confirming that locality is
  guaranteed by a caller outside this component.
- **fetch-error-is-fully-swallowed**: NEEDS REVIEW: Not implemented. A
  failed fetch attempt discards whatever error it produced (a timeout, a
  connection failure, a non-200 status, or any error a substituted fetch
  function raises) with no log, no diagnostic, and no way for a caller to
  distinguish "server refused the connection" from "server returned no
  models" from "response failed to parse." A maintainer investigating why
  the guard stopped seeing model sizes for a given server has no signal from
  this component. Resolved by logging the discarded error (subsystem/
  category to be defined) or by a maintainer confirming that silence is
  intentional for this internal advisory cache.

## Appearance

Not applicable — this is a per-server model-size cache, not a visual
component.

## States

Not applicable — this is a per-server model-size cache, not a visual
component.

## Accessibility

Not applicable — this is a per-server model-size cache, not a visual
component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| LMC-001 | first-lookup-always-fetches, size-tolerates-latest-suffix, cache-freshness-window | The fetch returns `{"models":[{"name":"small:latest","size":4900000000}]}` for base URL `http://localhost:11434/v1`; look up the size for model `small:latest`, then for model `small` | Both calls return `4_900_000_000`; the fetch runs exactly once — the second lookup is served from the fresh cache entry |
| LMC-002 | fetch-throw-yields-no-data, empty-parse-is-treated-as-failure (failure branch), cache-freshness-window | The fetch always fails (cannot connect to the host); look up the size for model `m` and base URL `http://localhost:11434/v1` twice in a row | Both calls return nothing; the fetch runs exactly once — the second call is served from the failure-cached entry within the failure TTL |
| LMC-003 | size-lookup-short-circuits-on-unknown-sizes | The fetch returns `{"models":[{"name":"small:latest","size":4900000000}]}`; look up the size for model `other` and base URL `http://localhost:11434/v1` | Returns nothing |
| LMC-004 | stale-while-error, cache-freshness-window, every-attempt-refreshes-the-timestamp | Success TTL `0`, failure TTL `3600`; the first fetch returns the sample response, every subsequent fetch fails; look up the size for the same model and base URL three times | 1st call: `4_900_000_000` (fetch #1, success). 2nd call: the zero success TTL forces a refetch that fails, but the result is still `4_900_000_000` (stale-while-error), fetch count now `2`. 3rd call: served from the failure cache within the failure TTL, still `4_900_000_000`, fetch count stays `2` |
| LMC-005 | unresolvable-base-url-is-uncached | Look up the size for model `m` with an empty base URL | Returns nothing; the fetch function is never invoked, since no native tags URL can be derived from an empty base URL |
| LMC-006 | empty-parse-is-treated-as-failure | The fetch succeeds but returns non-JSON bytes (or `{"models":[]}`) for a base URL with a prior cached entry | The response parses to no sizes, so the lookup treats the attempt as a failure: the prior known sizes are retained, and the new entry is marked as a failed fetch |
| LMC-007 | live-fetcher-request-shape | The built-in live fetch implementation is invoked against a URL whose server responds with HTTP `404` | The fetch fails, per live-fetcher-request-shape |
| LMC-008 | cache-key-is-the-raw-base-url | A fetch function that counts invocations; look up the size for model `m` and base URL `http://localhost:11434/v1`, then for model `m` and base URL `http://localhost:11434/v1/` | The fetch runs twice — once per distinct base URL string — even though both resolve to the same native tags URL, because the cache is keyed on the unnormalized base URL |
| LMC-009 | concurrent-fetch-deduplication | Two concurrent lookups for model `m` and base URL `http://localhost:11434/v1`, for a base URL with no cache entry yet, against a fetch function that counts invocations | The fetch MAY run twice, and the final cached entry is whichever call's write executes last |
| LMC-010 | never-known-stays-nil | The fetch always fails; look up the size for model `m` and base URL `http://localhost:11434/v1`, for a base URL with no prior cache entry | Returns nothing, and the cached entry's sizes are unknown — not a previously-seen value, since none exists |

## Edge Cases

- **Empty base URL.** The size lookup with `baseURL: ""` MUST return
  nothing; the native tags URL derivation returns nothing, so no fetch is
  attempted and no cache entry is created (unresolvable-base-url-is-uncached).
- **Base URL that trims to empty.** A base URL such as `"/v1"` or `"///"`
  trims (via slash- and `/v1`-stripping) to an empty string inside the
  native tags URL derivation, which then returns nothing — the same
  unresolvable-base-url-is-uncached behavior as a literally empty base URL.
  MUST.
- **Empty model name.** The size lookup for an empty model name MUST return
  nothing unless the server's parsed sizes literally contain the empty
  string as a key (it never does in practice, since Ollama model names are
  non-empty) — ordinary miss behavior of the model server helper's size
  resolver, with no special-casing here.
- **TTL boundary.** An entry aged exactly the success TTL (or failure TTL)
  seconds MUST be treated as expired, not fresh, because the freshness check
  uses strict less-than, not less-than-or-equal (cache-freshness-window).
  MUST.
- **Concurrent access, single instance.** The catalog serializes distinct
  calls from different callers on the same instance at the statement level,
  with no possibility of a torn read or write of the cache. This is
  applicable — the shared instance is read from at least the inference
  guard, which itself runs from multiple callers — and is safe by
  construction for memory, but see the open question on
  concurrent-fetch-deduplication above: statement-level safety does not
  prevent two concurrent callers for the same key from each triggering their
  own network fetch.
- **Server unreachable (network/offline).** When the local server's process
  is not running or the host is otherwise unreachable, the fetch fails with
  a connection failure (or any error from an injected fetch function); the
  per-server sizes lookup treats this exactly like any other failed attempt
  — fetch-throw-yields-no-data, then stale-while-error or never-known-stays-nil
  depending on prior cache state. MUST. There is no separate "offline" code
  path; connectivity loss is indistinguishable from any other fetch failure
  here.
- **Fetch timeout.** The built-in live fetch implementation's timeout is `5`
  seconds; a server that hangs past that bound causes a timeout failure,
  which is handled identically to any other failure
  (fetch-throw-yields-no-data). MUST.
- **Cancellation during a fetch.** If the calling operation is cancelled
  while the per-server sizes lookup is waiting on the fetch, no special
  handling applies: whatever error surfaces from that wait folds into the
  ordinary failure path exactly like any other failure, with no distinct
  "cancelled" outcome. MUST (this is the behavior, not a recommendation).
- **Non-Ollama local server (no `/api/tags`).** A local OpenAI-compatible
  server that isn't Ollama has no native tags endpoint; a request to the
  derived `/api/tags` URL either fails outright or returns a body the
  response parser cannot decode into any model entries. Either way the
  outcome folds into fetch-throw-yields-no-data or
  empty-parse-is-treated-as-failure; "non-Ollama server" is not
  special-cased against "Ollama server that's down." MUST.
- **Malformed or partially malformed `/api/tags` payload.** Garbage bytes
  (parsed to an empty set) and a payload where some model entries have the
  wrong field types (skipped individually) both flow through the catalog
  unchanged: a wholly malformed payload triggers
  empty-parse-is-treated-as-failure; a partially malformed payload yields
  whatever subset of sizes decoded successfully, which is cached and served
  as a normal success. MUST.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `fetcher` | function: URL → response bytes, or failure | built-in live fetch implementation | Injected fetch function, supplied at construction. Tests substitute a stub to avoid real networking and to force success/failure sequences. |
| `successTTL` | number (seconds) | `300` | Seconds a successful fetch's sizes remain fresh before the next lookup for that base URL triggers a refetch. |
| `failureTTL` | number (seconds) | `60` | Seconds a failed (including empty-parse) attempt's cache entry is honored before the next retry — shorter than `successTTL` so a down or non-Ollama server is checked again sooner without being fetched on every single lookup. |
| `model` | string | none — required per call | Passed to the size lookup; forwarded verbatim to the model server helper's size resolver, which additionally tries `model + ":latest"`. |
| `baseURL` | string | none — required per call | The OpenAI-compatible base URL (e.g. `http://localhost:11434/v1`) identifying the server; used both as the cache key and, via the native tags URL derivation, to derive the native tags URL to fetch. |

No environment variable, settings key, or feature flag configures this
component; it has no dependency beyond standard networking, and every
tunable is set at construction.

## Deep Linking

Not applicable: this component defines no routes, URLs consumed as
navigation targets, or navigable destinations of any kind — the only URL it
constructs (the native tags URL) is a network fetch target, not a deep link.

## Localization

Not applicable: this component contains no user-facing string literal of its
own — it produces no text for display, only an optional integer byte count.

## Accessibility Options

Not applicable: this component renders nothing and reads no accessibility
display setting (Reduce Motion, Increase Contrast, Differentiate Without
Color).

## Feature Flags

Not applicable: this component contains no feature-flag or remote-config
check of any kind; its behavior is governed entirely by its construction
parameters.

## Analytics

Not applicable: this component emits no analytics event — it has no
telemetry call of any kind.

## Privacy

Not applicable: the catalog carries no user data, credential, or token. It
transmits only a `GET` request (no request body) to a base URL the caller
supplies, and stores only model names and integer byte sizes in memory;
nothing it holds is written to disk or leaves the process except that
outbound request.

## Logging

Not applicable: this component performs no logging. Every fetch or parse
failure is discarded with no diagnostic emitted — see
fetch-error-is-fully-swallowed in Behavioral Requirements.

## Platform Notes

- **SwiftUI**: The source
  (`packages/apple/AgenticToolkit/AIPluginKit/LocalModelCatalog.swift`, its
  sibling `LocalModelServer.swift`, and tests
  `Tests/AIPluginKitTests/LocalModelCatalogTests.swift` /
  `LocalModelServerTests.swift`) has no SwiftUI (or any UI framework)
  dependency — it is a plain `Foundation`-only Swift `actor`, consumed today
  by `LocalInferenceGuard` from `await`-based call sites of any isolation
  domain. Its concurrency safety comes entirely from being an `actor`, not
  from any view-layer construct. Internally, `serialized-state-access` is
  implemented by declaring the type a Swift `actor`, so calls interleave
  only at `await` suspension points; the injectable fetch function is typed
  `@Sendable (URL) async throws -> Data`, defaulting to a `liveFetcher` that
  issues a `GET` with `URLRequest.timeoutInterval = 5` and throws
  `URLError(.badServerResponse)` on a non-200 `HTTPURLResponse`. The
  `concurrent-fetch-deduplication` open question follows from actor
  reentrancy: two `await`s on `fetcher(url)` before either write to `cache`
  can interleave. The `fetch-error-is-fully-swallowed` open question follows
  from `if let data = try? await fetcher(url)`, which discards whatever
  error `fetcher` throws — including `URLError(.cannotConnectToHost)` on a
  connection failure, or a `CancellationError` on task cancellation.
  `base-url-locality-is-unenforced` follows from `LocalModelCatalog` never
  calling the sibling `LocalModelServer.isLoopback(baseURL:)` before
  fetching.
- **Compose**: There is no Compose-specific consideration since this is a
  data/networking layer, not UI. A Kotlin port would use a class guarded by
  a `kotlinx.coroutines.sync.Mutex` (or a single-threaded
  `CoroutineDispatcher`) around a `MutableMap<String, Entry>` cache to
  reproduce the actor's serialization; `Instant`/`Clock` from
  `kotlinx-datetime` for `fetchedAt` and TTL comparisons; and an
  `HttpClient` (Ktor) or `OkHttp` call with an explicit 5-second timeout for
  `liveFetcher`'s equivalent. Unlike the Swift actor, a `Mutex`-based port
  makes it straightforward to also close the
  `concurrent-fetch-deduplication` gap by caching the in-flight
  `Deferred<Map<String, Long>?>` per `baseURL` instead of only the completed
  result.
- **React/Web**: A module-level `Map<string, Entry>` cache, with
  `Entry { sizes: Record<string, number> | null; fetchedAt: number;
  lastFetchFailed: boolean }`, and an `async function sizeBytes(model,
  baseURL)` mirroring `sizeBytes`/`sizes`. Use `fetch` with `AbortSignal.timeout(5000)`
  for the 5-second bound, and `Date.now()` for TTL comparisons. JavaScript's
  single-threaded event loop still allows the same
  `concurrent-fetch-deduplication` gap across concurrent `await`s on the same
  `baseURL` unless the port explicitly caches and reuses the in-flight
  `Promise` per key — a natural fix to apply during the port even though the
  Swift source does not.
- **AppKit / UIKit**: No AppKit- or UIKit-specific API appears in this file;
  it is UI-framework-agnostic and is called from AppKit-hosted code
  (`LocalInferenceGuard`'s callers) purely through `await`. Nothing in this
  type changes to run under UIKit.
- **WinUI 3**: This is the platform this recipe exists to steer. There is no
  `actor` concept in C#/.NET, so the serialization `LocalModelCatalog` gets
  for free from being an `actor` MUST be reproduced explicitly — for
  example, a `SemaphoreSlim` (count 1) guarding all reads and writes of a
  `Dictionary<string, CacheEntry>`, or, more precisely, a per-`baseURL`
  `Dictionary<string, Lazy<Task<IReadOnlyDictionary<string, long>?>>>` so
  that concurrent callers for the same `baseURL` await the same in-flight
  `Task` instead of each starting their own fetch — directly closing the
  `concurrent-fetch-deduplication` gap flagged above rather than
  reproducing it. Use `HttpClient.Timeout = TimeSpan.FromSeconds(5)` (or a
  linked `CancellationTokenSource`) for `liveFetcher`'s 5-second bound, and
  `System.Text.Json`'s `JsonSerializer.Deserialize<TagsResponse>` — with a
  `JsonSerializerOptions` that tolerates unknown/missing fields — for
  `parseSizes`, iterating entries individually (a `try`/`catch` or nullable
  fields per entry) so one malformed entry doesn't fail the whole
  deserialization, matching `LocalModelServer.parseSizes`'s per-entry
  tolerance. Model the cache entry as a `readonly record struct CacheEntry(
  IReadOnlyDictionary<string, long>? Sizes, DateTimeOffset FetchedAt, bool
  LastFetchFailed)`, and expose `Task<long?> GetSizeBytesAsync(string model,
  string baseUrl)` as the public surface, mirroring `sizeBytes`'s signature
  and null semantics (`long?` for "unknown," never a thrown exception for
  the routine "server down" case).

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/AIPluginKit/LocalModelCatalog.swift` |

## Design Decisions

- **Decision**: A failed refetch keeps the `baseURL`'s last known-good sizes
  (`stale-while-error`) rather than clearing them to `nil`, while still
  shortening the retry cadence to `failureTTL`.
  **Rationale**: Per the type's own doc comment, "stale beats failing open
  for a model already known to be over budget — the server being busy is
  exactly when the guard matters most." A guard that forgot a model's size
  the moment its server hiccuped would fail open at precisely the wrong
  time.
  **Approved**: pending
- **Decision**: A successful fetch that parses to zero model entries
  (`{"models":[]}`, or an otherwise-valid-but-empty payload) is treated
  identically to a fetch failure, not as "definitively zero models."
  **Rationale**: Inferred from the effect of `parsed.isEmpty ? nil : parsed`
  combined with the file's stale-while-error framing; no comment in the
  source states this rationale directly, but the effect is unambiguous —
  an empty parse re-enters the `failureTTL` retry cadence rather than being
  cached as a confirmed "no models on this server" fact.
  **Approved**: pending
- **Decision**: The cache key is the caller's raw `baseURL` string, with no
  normalization (trailing-slash or `/v1`-suffix stripping) applied before
  the `cache[baseURL]` lookup, even though `LocalModelServer.nativeTagsURL(baseURL:)`
  performs exactly that normalization when deriving the fetch URL.
  **Rationale**: Not stated in a source comment; this is a design fact
  rather than a documented rationale — the practical effect is that a
  caller must pass a consistent `baseURL` spelling for one server to get the
  benefit of caching, or it will fetch and cache that server's sizes once
  per distinct spelling used.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | passed | Reliability |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | partial | Reliability |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | failed | Best Practices |

Notes: graceful-degradation passes because a fetch failure never surfaces as
a thrown error or a crash — it resolves to `nil` (never known) or to stale,
previously-known sizes (`stale-while-error`), and `LocalInferenceGuard` fails
open on `nil` rather than blocking a request it cannot evaluate.
fault-tolerance passes because a persistently down or non-ollama server is
retried on the slower `failureTTL` cadence instead of being hit on every
lookup. idempotent-operations is partial because concurrent calls for the
same uncached or expired `baseURL` are not deduplicated — see the
open question on concurrent-fetch-deduplication in Behavioral
Requirements — so repeated concurrent invocations can each trigger their own
network side effect instead of converging on one. explicit-error-handling
fails because every fetch, HTTP-status, and parse failure is discarded via
`try?` with zero diagnostic signal (`fetch-error-is-fully-swallowed`) — there
is no log, no thrown error, and no way for a caller or maintainer to
distinguish the failure modes from one another.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | | | Initial creation |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ai/models/local/. |
