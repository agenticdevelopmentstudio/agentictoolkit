<!-- leaf: implement-status-web-hooks/use-history--edge-cases · source: status-web-hooks-use-history.md -->

# useHistory

**Rules** (cite as `implement-status-web-hooks/use-history--edge-cases#<slug>`):

- `null-slug` MUST
- `empty-slug` MUST
- `special-characters-in-slug` MUST
- `unknown-slug` MUST
- `empty-checks` MUST
- `malformed-body` MUST
- `204-response` MUST
- `server-error` MUST
- `unreachable-server` MUST
- `hung-request` MUST
- `slug-change-mid-flight` MUST
- `concurrent-callers` MUST

## Edge Cases

- **null-slug**: With `slug` `null`, the hook MUST stay idle and return `data` `undefined`; the `slug!` non-null assertion in the query function is never reached because the query is disabled.
- **empty-slug**: The empty string is falsy, so `useHistory("")` MUST behave exactly like `useHistory(null)` and MUST NOT fetch.
- **special-characters-in-slug**: A slug containing spaces, `&`, `/`, `?`, or `=` MUST be percent-encoded so it cannot inject extra query parameters.
- **unknown-slug**: A slug the backend does not recognize is sent as-is; whether the backend answers with an empty `checks` array or an error status is owned by the backend `/history` route, and the hook MUST surface whichever it returns (data, or `history <status>`).
- **empty-checks**: A successful response with `checks: []` MUST resolve as data; the hook applies no emptiness check.
- **malformed-body**: A body that is valid JSON but not shaped like `HistoryResponse` (for example missing `checks`) MUST resolve as data unchanged; the hook performs no shape validation, and a consumer reading `data.checks` receives `undefined`.
- **204-response**: A `204 No Content` response is `ok`, so the hook MUST call `response.json()` on the empty body, which rejects and puts the query in its error state (unlike the client's `json` helper, which maps 204 to `undefined`).
- **server-error**: A non-2xx status MUST produce `Error("history <status>")`; retries after that follow the host `QueryClient` policy (React Query's library default is 3 retries with exponential backoff when the host sets none).
- **unreachable-server**: A rejected `fetch` MUST surface as the query error with no hook-level retry, fallback data, or message rewriting.
- **hung-request**: With no timeout or abort signal from the hook, a request that never settles MUST leave the query in its fetching state indefinitely.
- **slug-change-mid-flight**: When `slug` changes while a request is in flight, the new slug MUST get its own cache entry and request; the earlier request resolves into its own key and does not overwrite the new slug's data.
- **concurrent-callers**: Two components calling `useHistory` with the same slug MUST share one cache entry; React Query deduplicates the in-flight request.
