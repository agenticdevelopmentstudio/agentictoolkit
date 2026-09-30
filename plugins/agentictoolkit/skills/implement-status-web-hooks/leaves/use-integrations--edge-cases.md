<!-- leaf: implement-status-web-hooks/use-integrations--edge-cases · source: status-web-hooks-use-integrations.md -->

# useIntegrations

**Rules** (cite as `implement-status-web-hooks/use-integrations--edge-cases#<slug>`):

- `empty-checks` MUST
- `malformed-body` MUST
- `unknown-check-state` MUST
- `204-response` MUST
- `server-error` MUST
- `unreachable-server` MUST
- `error-after-success` MUST
- `ambiguous-error-message` SHOULD
- `hung-request` MUST
- `focus-while-fetching` MUST
- `no-provider` MUST

## Edge Cases

- **empty-checks**: A successful response with `checks: []` MUST resolve as data. The hook applies no emptiness check.
- **malformed-body**: A body that is valid JSON but not shaped like `IntegrationsResponse` (for example, one missing `checks`) MUST resolve as data unchanged. The hook does no shape validation, and a consumer reading `data.checks` gets `undefined`.
- **unknown-check-state**: A `state` or `overall` value outside `"ok" | "warn" | "error"` MUST pass through unchanged. The type is compile-time only.
- **204-response**: A `204 No Content` response counts as `ok`, so the hook MUST call `response.json()` on the empty body. That rejects and puts the query in its error state, unlike the client's `json` helper, which maps 204 to `undefined`.
- **server-error**: A non-2xx status MUST produce `Error("status <status>")`. Retries after that follow the host `QueryClient` policy; when the host sets none, React Query's library default is 3 retries with exponential backoff. What the `/integrations` route returns is owned by the backend.
- **unreachable-server**: A rejected `fetch` MUST surface as the query error. The hook adds no retry, fallback data or message rewriting of its own.
- **error-after-success**: When a refetch fails after an earlier success, React Query MUST keep the previous `data` and set `error`. The two callers read only `data`, so they keep showing the last good snapshot.
- **ambiguous-error-message**: The thrown message is the generic `status <status>`, which does not name the integrations endpoint. A consumer that logs the error cannot tell it from other queries by the message alone. This SHOULD be kept as-is for fidelity; see Design Decisions.
- **hung-request**: The hook sets no timeout or abort signal, so a request that never settles MUST leave the query fetching indefinitely.
- **focus-while-fetching**: A window focus during an in-flight fetch MUST NOT start a second request. React Query deduplicates on the shared key.
- **no-provider**: With no `StatusApiProvider` mounted, the hook MUST fall back to the same-origin default client, `/api`. With no `QueryClientProvider` mounted, React Query throws when the hook is called.
