<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-local-model-catalog--part-2 · source: ai-plugin-runtime-ai-plugin-kit-local-model-catalog.md -->

# LocalModelCatalog — continued (part 2)

**Rules** (cite as `implement-ai-plugin-1/runtime-ai-plugin-kit-local-model-catalog--part-2#<slug>`):

- `winui-3` MUST — This is the platform this recipe exists to steer. There is no actor concept in C#/.NET, so the serialization …

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
