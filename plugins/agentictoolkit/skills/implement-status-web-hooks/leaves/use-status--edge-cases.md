<!-- leaf: implement-status-web-hooks/use-status--edge-cases · source: status-web-hooks-use-status.md -->

# useStatus

**Rules** (cite as `implement-status-web-hooks/use-status--edge-cases#<slug>`):

- `empty-services-list` MUST — A 200 body with services: [] MUST resolve as-is; the hook does not treat an empty list as an error (MUST).
- `missing-or-malformed-fields-in-a-200-body` MUST — A body lacking services or checkedAt, or with wrong types, MUST resolve without error because the body is cast, not …
- `non-json-200-body` MUST — The query MUST fail with the r.json() syntax error (MUST).
- `non-json-error-body` MUST — The parse failure MUST be caught and replaced by status <code> (MUST).
- `empty-string-or-null-error` MUST — Falsy detail MUST fall back to status <code> (MUST).
- `non-string-error` MUST — A truthy object or number is passed to Error unconverted, yielding a coerced message such as [object Object] or 42; the …
- `network-unreachable-offline` MUST — api.fetch rejects and the query fails with that rejection; the hook adds no retry, backoff or offline detection of its …
- `timeout` MUST — The hook sets no timeout; a request that never settles leaves the query pending until the browser or network stack …
- `cancellation-unmount` MUST — The fetch is not tied to react-query's AbortSignal, so an unmounted or cancelled query's request still completes and …
- `concurrent-callers` MUST — JavaScript is single-threaded and react-query deduplicates by key, so concurrent mounts share one in-flight request; …
- `no-provider-mounted` MUST — useStatusApi() falls back to the module-level default client at /api (MUST).
- `window-focus-while-fresh` MUST — refetchOnWindowFocus: true refetches only when the query is stale per the host staleTime; a fresh query is not …

## Edge Cases

- **Empty services list**: A `200` body with `services: []` MUST resolve as-is; the hook does not treat an empty list as an error (MUST).
- **Missing or malformed fields in a 200 body**: A body lacking `services` or `checkedAt`, or with wrong types, MUST resolve without error because the body is cast, not validated; consumers such as `Dashboard` guard with `status.data?.services ?? []` (MUST, as implemented).
- **Non-JSON 200 body**: The query MUST fail with the `r.json()` syntax error (MUST).
- **Non-JSON error body**: The parse failure MUST be caught and replaced by `status <code>` (MUST).
- **Empty-string or null `error`**: Falsy detail MUST fall back to `status <code>` (MUST).
- **Non-string `error`**: A truthy object or number is passed to `Error` unconverted, yielding a coerced message such as `[object Object]` or `42`; the reason is lossy but the failure is still reported (MUST, as implemented).
- **Network unreachable / offline**: `api.fetch` rejects and the query fails with that rejection; the hook adds no retry, backoff or offline detection of its own beyond the host `QueryClient` defaults (MUST).
- **Timeout**: The hook sets no timeout; a request that never settles leaves the query pending until the browser or network stack gives up (MUST, as implemented).
- **Cancellation / unmount**: The fetch is not tied to react-query's `AbortSignal`, so an unmounted or cancelled query's request still completes and its result may populate the cache (MUST, as implemented).
- **Concurrent callers**: JavaScript is single-threaded and react-query deduplicates by key, so concurrent mounts share one in-flight request; there is no interleaving to order (MUST).
- **No provider mounted**: `useStatusApi()` falls back to the module-level default client at `/api` (MUST).
- **Window focus while fresh**: `refetchOnWindowFocus: true` refetches only when the query is stale per the host `staleTime`; a fresh query is not refetched on focus (MUST, per react-query semantics).
