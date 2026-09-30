<!-- leaf: implement-status-web-src/telemetry--edge-cases · source: status-web-src-telemetry.md -->

# Status Web Telemetry

**Rules** (cite as `implement-status-web-src/telemetry--edge-cases#<slug>`):

- `nothing-cached` MUST — localCache.load() MUST return null, and the hook falls back to emptySnapshot().
- `corrupt-or-old-shape-cache-entry` MUST — A stored value that is not JSON, or lacks the three top-level fields, MUST load as null rather than throw. The bad …
- `malformed-array-elements-in-cache` MUST — An entry whose errors holds non-ErrorDTO values MUST still load, because the gate checks only that the fields are …
- `storage-unavailable-or-full` MUST — With storage disabled (private mode) or over quota, load MUST return null and save MUST do nothing, silently in both …
- `server-render` MUST — With no window, both cache operations MUST do nothing, which keeps SSR output and the first client paint identical.
- `source-http-failure` MUST — A non-2xx response MUST reject get with an Error naming the path stem and status. The sources do not return an empty …
- `network-failure` MUST — If api.fetch itself rejects (host unreachable), the rejection MUST propagate unchanged out of get.
- `malformed-success-body` MUST — A 2xx body that is not valid JSON MUST reject get with the SyntaxError thrown by Response.json(). Valid JSON of the …
- `turso-partial-failure` MUST — If either request fails, the whole get MUST reject, so no half-populated snapshot is returned. The response to the …
- `timeouts-and-cancellation` SHOULD — The sources SHOULD be treated as having no timeout of their own. A hung request waits as long as the underlying fetch …
- `provider-outage-on-the-server-pipeline` MUST — A FetchResult with ok: false MUST NOT clear persisted data. The client never sees FetchResult.
- `concurrent-calls` MUST — Overlapping get calls MUST each issue their own requests. There is no shared state or deduplication in the sources.
- `empty-lists` MUST — A snapshot with errors: [] and analytics: [] and a non-empty generatedAt is a valid "nothing to report" read, and MUST …

## Edge Cases

- **Nothing cached (first visit)**: `localCache.load()` MUST return `null`, and the hook falls back to `emptySnapshot()`.
- **Corrupt or old-shape cache entry**: A stored value that is not JSON, or lacks the three top-level fields, MUST load as `null` rather than throw. The bad entry stays in storage until the next successful `save` overwrites it.
- **Malformed array elements in cache**: An entry whose `errors` holds non-`ErrorDTO` values MUST still load, because the gate checks only that the fields are arrays. Consumers get the elements unchanged.
- **Storage unavailable or full**: With storage disabled (private mode) or over quota, `load` MUST return `null` and `save` MUST do nothing, silently in both cases.
- **Server render**: With no `window`, both cache operations MUST do nothing, which keeps SSR output and the first client paint identical.
- **Source HTTP failure**: A non-2xx response MUST reject `get` with an `Error` naming the path stem and status. The sources do not return an empty snapshot and do not cache on failure.
- **Network failure**: If `api.fetch` itself rejects (host unreachable), the rejection MUST propagate unchanged out of `get`.
- **Malformed success body**: A 2xx body that is not valid JSON MUST reject `get` with the `SyntaxError` thrown by `Response.json()`. Valid JSON of the wrong shape resolves unchecked (see source-response-trusted).
- **Turso partial failure**: If either request fails, the whole `get` MUST reject, so no half-populated snapshot is returned. The response to the other request is discarded.
- **Timeouts and cancellation**: The sources SHOULD be treated as having no timeout of their own. A hung request waits as long as the underlying fetch and the calling hook allow, which keeps timeout policy in one place (the caller).
- **Provider outage on the server pipeline**: A `FetchResult` with `ok: false` MUST NOT clear persisted data. The client never sees `FetchResult`.
- **Concurrent calls**: Overlapping `get` calls MUST each issue their own requests. There is no shared state or deduplication in the sources.
- **Empty lists**: A snapshot with `errors: []` and `analytics: []` and a non-empty `generatedAt` is a valid "nothing to report" read, and MUST be cached like any other.
