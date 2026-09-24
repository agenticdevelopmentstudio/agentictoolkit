---
id: 79c8f46f-e934-46d1-8d0e-4bbee625e163
title: LocalModelCatalog
domain: agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-local-model-catalog
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: AIPluginKit's actor cache mapping a local model server's model name to its
  on-disk size in bytes, fetched from ollama's native /api/tags.
platforms:
- swift
- macos
tags:
- ai-plugin
- local-model
- caching
- ollama
- actor
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

# LocalModelCatalog

## Overview

`LocalModelCatalog` is an `AIPluginKit` **logic** component — no visual
surface — that resolves the on-disk size, in bytes, of a model hosted by a
local model server, so a caller such as `LocalInferenceGuard` can weigh a
model's footprint against the machine's RAM budget before allowing it to
load. A model server exposes no size information over the OpenAI-compatible
`/v1` surface most gateways speak; ollama's own native `/api/tags` listing is
the only one that reports a `size` per model, so `LocalModelCatalog` derives
that native URL from the caller's OpenAI-compatible `baseURL` (via the
sibling type `LocalModelServer.nativeTagsURL(baseURL:)`), fetches and parses
it (`LocalModelServer.parseSizes(_:)`), and looks up one model's size
(`LocalModelServer.size(of:in:)`, which tolerates the `:latest` shorthand).
Because that fetch is a network round trip with real per-call cost — and the
guard runs ahead of every local-model request — results are cached per
`baseURL` with independent time-to-live windows for success (`successTTL`,
default 300 seconds) and failure (`failureTTL`, default 60 seconds): a down
or non-ollama server is retried on a slower cadence than a healthy one, and a
failed refetch never discards a server's last known-good sizes — stale sizes
still serve the guard, because a model already known to be over budget must
never be forgotten just because the server is momentarily busy or
unreachable. `LocalModelCatalog.shared` is the process-wide singleton
instance most callers use; `LocalInferenceGuard.init(catalog:)` defaults to
it.

## Behavioral Requirements

- **actor-isolation**: `LocalModelCatalog` MUST be declared as a Swift
  `actor`, so its stored state (`fetcher`, `successTTL`, `failureTTL`,
  `cache`) is confined to the actor's isolation domain and every call to
  `sizeBytes(model:baseURL:)` or the private `sizes(baseURL:)` on one
  instance executes without a data race, interleaved only at `await`
  suspension points.
- **shared-singleton**: `LocalModelCatalog.shared` MUST provide one
  process-wide instance for callers that do not construct their own; it is
  the default value of `LocalInferenceGuard.init(catalog:)`'s `catalog`
  parameter.
- **fetcher-is-injectable**: `init(fetcher:successTTL:failureTTL:)` MUST
  accept a `Fetcher` (`@Sendable (URL) async throws -> Data`) parameter
  defaulting to `LocalModelCatalog.liveFetcher`, so a caller MAY substitute a
  stub fetcher with no real network dependency.
- **default-ttls**: `init` MUST default `successTTL` to `300` and
  `failureTTL` to `60` (seconds) when the caller does not override them.
- **live-fetcher-request-shape**: `LocalModelCatalog.liveFetcher` MUST issue
  a `GET` request with a `timeoutInterval` of `5` seconds, and MUST throw
  `URLError(.badServerResponse)` when the response is not an
  `HTTPURLResponse` with `statusCode == 200`.
- **size-lookup-short-circuits-on-unknown-sizes**: `sizeBytes(model:baseURL:)`
  MUST return `nil` without calling `LocalModelServer.size(of:in:)` when
  `sizes(baseURL:)` returns `nil` for the given `baseURL`; otherwise it MUST
  return `LocalModelServer.size(of: model, in: sizes)`.
- **cache-key-is-the-raw-base-url**: The `cache` dictionary MUST key entries
  by the exact `baseURL` string passed in, with no normalization applied to
  the key itself. `LocalModelServer.nativeTagsURL(baseURL:)` trims whitespace,
  trailing slashes, and a trailing `/v1` when deriving the fetch URL, but
  that normalization is not reflected back into the cache key — two `baseURL`
  spellings that resolve to the same native tags URL (e.g. with and without a
  trailing slash) MUST be cached and fetched independently of one another.
- **cache-freshness-window**: For a cached entry, `sizes(baseURL:)` MUST
  treat it as fresh — returning `entry.sizes` without fetching — only when
  `Date().timeIntervalSince(entry.fetchedAt)` is strictly less than
  `failureTTL` if `entry.lastFetchFailed` is `true`, or strictly less than
  `successTTL` otherwise; an entry aged exactly `successTTL` or `failureTTL`
  seconds MUST be treated as expired, not fresh.
- **unresolvable-base-url-is-uncached**: When
  `LocalModelServer.nativeTagsURL(baseURL:)` returns `nil` for the given
  `baseURL` (e.g. an empty string, or a string that trims to empty once a
  trailing `/v1` and slashes are stripped), `sizes(baseURL:)` MUST return
  `nil` immediately, without calling `fetcher` and without creating or
  updating a cache entry for that `baseURL`.
- **fetch-throw-yields-no-data**: When `fetcher(url)` throws, `sizes(baseURL:)`
  MUST treat the attempt as having produced no data (`fetched = nil`) rather
  than propagating the thrown error to its own caller.
- **empty-parse-is-treated-as-failure**: When `fetcher(url)` succeeds but
  `LocalModelServer.parseSizes(data)` yields an empty dictionary,
  `sizes(baseURL:)` MUST treat the attempt identically to a fetch failure
  (`fetched = nil`): the resulting cache entry MUST be marked
  `lastFetchFailed: true` and MUST be re-checked on the `failureTTL` cadence,
  not `successTTL`.
- **stale-while-error**: When an attempt yields no data (`fetched == nil`)
  for a `baseURL` that has a prior cached entry, `sizes(baseURL:)` MUST
  retain that entry's last known `sizes` value (`fetched ??
  cache[baseURL]?.sizes`) rather than clearing it to `nil`.
- **never-known-stays-nil**: When an attempt yields no data for a `baseURL`
  with no prior cached entry, or whose prior entry's `sizes` was already
  `nil`, `sizes(baseURL:)` MUST cache and return `nil` for that `baseURL`.
- **every-attempt-refreshes-the-timestamp**: Every time `sizes(baseURL:)`
  performs a fetch attempt — whether it succeeds, throws, or parses to an
  empty dictionary — it MUST replace any prior entry for that `baseURL` with
  a new one whose `fetchedAt` is the current time and whose
  `lastFetchFailed` reflects that attempt's outcome.
- **first-lookup-always-fetches**: `sizes(baseURL:)` MUST attempt a fetch
  (subject to `unresolvable-base-url-is-uncached`) the first time a
  `baseURL` is looked up, since no cache entry exists yet to satisfy
  `cache-freshness-window`.
- **size-tolerates-latest-suffix**: `sizeBytes(model:baseURL:)` MUST resolve
  a size for `model` when the parsed sizes map only contains that model name
  suffixed with `:latest` (delegated to `LocalModelServer.size(of:in:)`).

Three concerns the code's own purpose calls for are left undefined by the
source:

- **concurrent-fetch-deduplication**: NEEDS REVIEW: Not implemented in
  source. `sizes(baseURL:)` checks `cache[baseURL]` for freshness, then
  `await`s `fetcher(url)`, and only afterward writes the new `Entry`. Because
  actor methods are reentrant across `await`, two concurrent calls to
  `sizeBytes`/`sizes` for the same expired or uncached `baseURL` can both
  observe the same pre-fetch cache state and both invoke `fetcher`; the
  `Entry` that ends up cached is whichever call's assignment statement runs
  last, not necessarily the one from the most recently issued request, and
  the server is hit twice (or more) for one logical refresh instead of once.
  No in-flight-request tracking or coalescing exists. This cannot be resolved
  from `LocalModelCatalog.swift` alone; it requires either an explicit
  statement that duplicate concurrent fetches are an accepted cost (the
  guard's own call sites are typically not highly concurrent) or an
  in-flight-`Task` cache keyed by `baseURL`.
- **base-url-locality-is-unenforced**: NEEDS REVIEW: Not implemented in
  source. Both the type's own documentation comment ("Fetches and caches a
  local server's...") and its sibling `LocalModelServer.isLoopback(baseURL:)`
  describe and can test for a *local* server, but `LocalModelCatalog` never
  calls `isLoopback` (or any other check) before deriving a tags URL from
  `baseURL` and issuing a `GET` to it. A caller passing a non-loopback
  `baseURL` — by misconfiguration or a future provider that reuses this
  type — causes `LocalModelCatalog` to make an outbound network request to
  that remote host on every cache miss, with nothing in this file to prevent
  it. `LocalInferenceGuard.verdict(model:baseURL:settings:)`'s own comment
  ("The decision for one request to a loopback provider") states the same
  assumption without enforcing it either. Resolved by either calling
  `LocalModelServer.isLoopback(baseURL:)` and failing closed (returning
  `nil`) for a non-loopback `baseURL`, or a maintainer confirming that
  locality is guaranteed by a caller not present in these sources.
- **fetch-error-is-fully-swallowed**: NEEDS REVIEW: Not implemented in
  source. `if let data = try? await fetcher(url)` discards whatever error
  `fetcher` throws (a timeout, `URLError(.cannotConnectToHost)`, a
  non-`200` status, or any error a substituted fetcher raises) with no log,
  no diagnostic, and no way for a caller to distinguish "server refused the
  connection" from "server returned no models" from "response failed to
  parse." A maintainer investigating why the guard stopped seeing model
  sizes for a given server has no signal from this type. Resolved by logging
  the discarded error (subsystem/category to be defined) or by a maintainer
  confirming that silence is intentional for this internal advisory cache.

## Appearance

Not applicable — this is a per-server model-size cache actor, not a visual
component.

## States

Not applicable — this is a per-server model-size cache actor, not a visual
component.

## Accessibility

Not applicable — this is a per-server model-size cache actor, not a visual
component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| LMC-001 | first-lookup-always-fetches, size-tolerates-latest-suffix, cache-freshness-window | Fetcher returns `{"models":[{"name":"small:latest","size":4900000000}]}`; call `sizeBytes(model: "small:latest", baseURL: "http://localhost:11434/v1")`, then `sizeBytes(model: "small", baseURL: "http://localhost:11434/v1")` | Both calls return `4_900_000_000`; the fetcher runs exactly once (second call served from the fresh cache entry) — `LocalModelCatalogTests.fetchesParsesAndCachesPerBaseURL` |
| LMC-002 | fetch-throw-yields-no-data, empty-parse-is-treated-as-failure (failure branch), cache-freshness-window | Fetcher always throws `URLError(.cannotConnectToHost)`; call `sizeBytes(model: "m", baseURL: "http://localhost:11434/v1")` twice in a row | Both calls return `nil`; the fetcher runs exactly once (second call served from the failure-cached entry within `failureTTL`) — `LocalModelCatalogTests.failureReturnsNilAndIsNotHammered` |
| LMC-003 | size-lookup-short-circuits-on-unknown-sizes | Fetcher returns `{"models":[{"name":"small:latest","size":4900000000}]}`; call `sizeBytes(model: "other", baseURL: "http://localhost:11434/v1")` | Returns `nil` — `LocalModelCatalogTests.unknownModelReturnsNil` |
| LMC-004 | stale-while-error, cache-freshness-window, every-attempt-refreshes-the-timestamp | `successTTL: 0, failureTTL: 3600`; first fetch returns the sample JSON, every subsequent fetch throws; call `sizeBytes` three times for the same model/baseURL | 1st call: `4_900_000_000` (fetch #1, success). 2nd call: `successTTL == 0` forces a refetch that fails, but the result is still `4_900_000_000` (stale-while-error), fetch count now `2`. 3rd call: served from the failure-cache within `failureTTL`, still `4_900_000_000`, fetch count stays `2` — `LocalModelCatalogTests.failedRefetchKeepsKnownSizes` |
| LMC-005 | unresolvable-base-url-is-uncached | `sizeBytes(model: "m", baseURL: "")` | Returns `nil`; the injected fetcher is never invoked — traced to `LocalModelServer.nativeTagsURL(baseURL: "") == nil` (`LocalModelServerTests.nativeTagsURLStripsV1Suffix`) combined with the `guard let url = ... else { return nil }` line in `sizes(baseURL:)`; not exercised directly by `LocalModelCatalogTests`, whose fixtures always use a resolvable `baseURL` |
| LMC-006 | empty-parse-is-treated-as-failure | Fetcher succeeds and returns `Data("not json".utf8)` (or `{"models":[]}`) for a `baseURL` with a prior cached entry | `LocalModelServer.parseSizes` yields `[:]`, so `sizes(baseURL:)` treats the attempt as a failure: the prior known sizes are retained, and the new entry is marked `lastFetchFailed: true` — traced to the `parsed.isEmpty ? nil : parsed` line and `LocalModelServerTests.parseSizesToleratesGarbage` |
| LMC-007 | live-fetcher-request-shape | `LocalModelCatalog.liveFetcher` invoked against a URL whose server responds with HTTP `404` | Throws `URLError(.badServerResponse)` — traced directly to `liveFetcher`'s `guard let http = ... , http.statusCode == 200 else { throw ... }`; not exercised by `LocalModelCatalogTests`, which always injects a fetcher and never runs `liveFetcher` itself |
| LMC-008 | cache-key-is-the-raw-base-url | A fetcher that counts invocations; call `sizeBytes(model: "m", baseURL: "http://localhost:11434/v1")` then `sizeBytes(model: "m", baseURL: "http://localhost:11434/v1/")` | The fetcher runs twice — once per distinct `baseURL` string — even though both resolve to the same native tags URL (`http://localhost:11434/api/tags`); traced directly to `cache[baseURL]` being keyed on the unnormalized parameter in `sizes(baseURL:)`; not exercised by the given test suite, which always calls with one fixed `baseURL` spelling |
| LMC-009 | concurrent-fetch-deduplication (the open question) | Two concurrent `Task`s call `sizeBytes(model: "m", baseURL: "http://localhost:11434/v1")` for a `baseURL` with no cache entry yet, against a fetcher that counts invocations | The fetcher MAY run twice, and the final cached `Entry` is whichever task's write executes last — not exercised by `LocalModelCatalogTests`, whose calls are made sequentially with `await`; traced to the unguarded `await fetcher(url)` between the cache-miss check and `cache[baseURL] = Entry(...)` in `sizes(baseURL:)` |
| LMC-010 | never-known-stays-nil | Fetcher always throws; call `sizeBytes(model: "m", baseURL: "http://localhost:11434/v1")` for a `baseURL` with no prior cache entry | Returns `nil`, and the cached `Entry.sizes` is `nil` (not a previously-seen value, since none exists) — traced to `sizes = fetched ?? cache[baseURL]?.sizes` where both operands are `nil` on a first, failing lookup; the same code path `LocalModelCatalogTests.failureReturnsNilAndIsNotHammered` exercises, generalized to the "no prior entry at all" case |

## Edge Cases

- **Empty `baseURL`.** `sizeBytes(model:baseURL:)` with `baseURL: ""` MUST
  return `nil`; `LocalModelServer.nativeTagsURL(baseURL: "")` returns `nil`,
  so no fetch is attempted and no cache entry is created
  (`unresolvable-base-url-is-uncached`).
- **`baseURL` that trims to empty.** A `baseURL` such as `"/v1"` or `"///"`
  trims (via slash- and `/v1`-stripping) to an empty string inside
  `LocalModelServer.nativeTagsURL(baseURL:)`, which then returns `nil` — the
  same `unresolvable-base-url-is-uncached` behavior as a literally empty
  `baseURL`. MUST.
- **Empty `model` name.** `sizeBytes(model: "", baseURL:)` MUST return `nil`
  unless the server's parsed sizes map literally contains the empty string
  as a key (it never does in practice, since ollama model names are
  non-empty) — ordinary dictionary-miss behavior of
  `LocalModelServer.size(of:in:)`, with no special-casing in this file.
- **TTL boundary.** An entry aged exactly `successTTL` (or `failureTTL`)
  seconds MUST be treated as expired, not fresh, because the freshness check
  uses strict `<`, not `<=` (`cache-freshness-window`). MUST.
- **Concurrent access, single instance.** `LocalModelCatalog` is a Swift
  `actor`; distinct calls from different tasks on the same instance are
  serialized at the statement level with no possibility of a torn read or
  write of `cache`. This is applicable — `LocalModelCatalog.shared` is
  read from at least `LocalInferenceGuard`, which itself runs from multiple
  callers — and is safe by construction for memory, but see
  `concurrent-fetch-deduplication` above: statement-level safety does not
  prevent two concurrent callers for the same key from each triggering their
  own network fetch — this is the open question named above.
- **Server unreachable (network/offline).** When the local server's process
  is not running or the host is otherwise unreachable, `fetcher` throws
  (`URLError(.cannotConnectToHost)` from `liveFetcher`, or any error from an
  injected fetcher); `sizes(baseURL:)` treats this exactly like any other
  failed attempt — `fetch-throw-yields-no-data`, then `stale-while-error` or
  `never-known-stays-nil` depending on prior cache state. MUST. There is no
  separate "offline" code path; connectivity loss is indistinguishable from
  any other fetch failure in this file.
- **Fetch timeout.** `liveFetcher`'s `URLRequest.timeoutInterval` is `5`
  seconds; a server that hangs past that bound causes `URLSession` to throw a
  timeout error, which is caught by the same `try?` as any other thrown
  error and handled identically (`fetch-throw-yields-no-data`). MUST.
- **Task cancellation during a fetch.** If the calling `Task` is cancelled
  while `sizes(baseURL:)` is suspended on `await fetcher(url)`, the source
  applies no special handling: whatever error (or a `CancellationError`,
  depending on the fetcher) surfaces from that suspension is caught by
  `try?` and folds into the ordinary failure path exactly like any other
  thrown error, with no distinct "cancelled" outcome. MUST (this is the
  behavior, not a recommendation).
- **Non-ollama local server (no `/api/tags`).** A local OpenAI-compatible
  server that isn't ollama has no native tags endpoint; a request to the
  derived `/api/tags` URL either fails outright or returns a body that
  `LocalModelServer.parseSizes` cannot decode into any model entries. Either
  way the outcome folds into `fetch-throw-yields-no-data` or
  `empty-parse-is-treated-as-failure`; the source does not special-case
  "non-ollama server" versus "ollama server that's down." MUST.
- **Malformed or partially malformed `/api/tags` payload.** Garbage bytes
  (`LocalModelServer.parseSizes` returns `[:]` on undecodable JSON) and a
  payload where some model entries have the wrong field types (skipped
  individually, per `LocalModelServerTests.parseSizesSkipsMalformedEntries`)
  both flow through `LocalModelCatalog` unchanged: a wholly malformed
  payload triggers `empty-parse-is-treated-as-failure`; a partially malformed
  payload yields whatever subset of sizes decoded successfully, which is
  cached and served as a normal success. MUST.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `fetcher` | `Fetcher` (`@Sendable (URL) async throws -> Data`) | `LocalModelCatalog.liveFetcher` | Injected HTTP fetch function, supplied to `init`. Tests substitute a stub to avoid real networking and to force success/failure sequences. |
| `successTTL` | `TimeInterval` | `300` | Seconds a successful fetch's sizes remain fresh before the next lookup for that `baseURL` triggers a refetch. |
| `failureTTL` | `TimeInterval` | `60` | Seconds a failed (including empty-parse) attempt's cache entry is honored before the next retry — shorter than `successTTL` so a down or non-ollama server is checked again sooner without being fetched on every single lookup. |
| `model` | `String` | none — required per call | Passed to `sizeBytes(model:baseURL:)`; forwarded verbatim to `LocalModelServer.size(of:in:)`, which additionally tries `model + ":latest"`. |
| `baseURL` | `String` | none — required per call | The OpenAI-compatible base URL (e.g. `http://localhost:11434/v1`) identifying the server; used both as the cache key and, via `LocalModelServer.nativeTagsURL(baseURL:)`, to derive the native tags URL to fetch. |

No environment variable, settings key, or feature flag configures this type;
`import Foundation` is its only dependency, and every tunable is a
constructor parameter.

## Deep Linking

Not applicable: `LocalModelCatalog.swift` defines no routes, URLs consumed
as navigation targets, or navigable destinations of any kind — the only URL
it constructs (`LocalModelServer.nativeTagsURL(baseURL:)`'s result) is a
network fetch target, not a deep link.

## Localization

Not applicable: `LocalModelCatalog.swift` contains no user-facing string
literal of its own — it produces no text for display, only an optional
integer byte count.

## Accessibility Options

Not applicable: `LocalModelCatalog.swift` renders nothing and reads no
accessibility display setting (Reduce Motion, Increase Contrast,
Differentiate Without Color).

## Feature Flags

Not applicable: `LocalModelCatalog.swift` contains no feature-flag or
remote-config check of any kind; its behavior is governed entirely by its
constructor parameters.

## Analytics

Not applicable: `LocalModelCatalog.swift` emits no analytics event — it has
no telemetry call of any kind.

## Privacy

Not applicable: `LocalModelCatalog` carries no user data, credential, or
token. It transmits only a `GET` request (no request body) to a `baseURL`
the caller supplies, and stores only model names and integer byte sizes
in memory (`cache`); nothing it holds is written to disk or leaves the
process except that outbound `GET`.

## Logging

Not applicable: `LocalModelCatalog.swift` contains no `Logger`/`os_log`/
`print` call. Every fetch or parse failure is discarded via `try?` with no
diagnostic emitted — see `fetch-error-is-fully-swallowed` in Behavioral
Requirements.

## Platform Notes

- **SwiftUI**: The source
  (`packages/apple/AgenticToolkit/AIPluginKit/LocalModelCatalog.swift`, its
  sibling `LocalModelServer.swift`, and tests
  `Tests/AIPluginKitTests/LocalModelCatalogTests.swift` /
  `LocalModelServerTests.swift`) has no SwiftUI (or any UI framework)
  dependency — it is a plain `Foundation`-only Swift `actor`, consumed today
  by `LocalInferenceGuard` from `await`-based call sites of any isolation
  domain. Its concurrency safety comes entirely from being an `actor`, not
  from any view-layer construct.
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
same uncached or expired `baseURL` are not deduplicated — see
`concurrent-fetch-deduplication`, the open question in Behavioral
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
