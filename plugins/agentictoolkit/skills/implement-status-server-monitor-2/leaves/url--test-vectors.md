<!-- leaf: implement-status-server-monitor-2/url--test-vectors · source: status-server-monitor-url.md -->

# Status Server Monitor URL

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-monitor-url-001 | host-of-extraction | `hostOf('https://example.com/path')` | Resolves `'example.com'`, traced to `new URL(url).host`; no dedicated test exists for `hostOf` in the given source tree |
| status-server-monitor-url-002 | host-of-extraction | `hostOf('https://example.com:8080/x')` | Resolves `'example.com:8080'` — `URL.host` includes a non-default port |
| status-server-monitor-url-003 | host-of-invalid-fallback | `hostOf('not a url')` | Resolves `'not a url'` unchanged — the `URL` constructor throws and the `catch` block returns `url` verbatim |
| status-server-monitor-url-004 | host-of-invalid-fallback | `hostOf('')` | Resolves `''` unchanged — `new URL('')` throws, and the `catch` returns the empty string |
| status-server-monitor-url-005 | project-page-url-null-on-falsy | `projectPageUrl(null)`; `projectPageUrl(undefined)`; `projectPageUrl('')` | All three resolve `null` — the `if (!url) return null;` guard short-circuits before any `URL` parsing |
| status-server-monitor-url-006 | project-page-url-vercel-collapse | `projectPageUrl('https://vercel.com/acme/my-app/dpl_abc123')` | Resolves `'https://vercel.com/acme/my-app'` — hostname is `vercel.com`, 3 path segments, origin plus the first two segments returned |
| status-server-monitor-url-007 | project-page-url-drops-suffix | `projectPageUrl('https://vercel.com/acme/my-app/dpl_abc123/logs?tab=build#top')` | Resolves `'https://vercel.com/acme/my-app'` — the fourth segment (`logs`), the query string, and the fragment are all dropped along with the deploy id |
| status-server-monitor-url-008 | project-page-url-vercel-short-path-passthrough | `projectPageUrl('https://vercel.com/acme/my-app')` | Resolves `'https://vercel.com/acme/my-app'` unchanged as the original string (not reconstructed from `origin`) — only 2 path segments, below the 3-segment threshold |
| status-server-monitor-url-009 | project-page-url-non-vercel-passthrough | `projectPageUrl('https://backboard.railway.app/project/xyz/service/abc')` | Resolves the input unchanged — hostname is not `vercel.com` |
| status-server-monitor-url-010 | project-page-url-invalid-fallback | `projectPageUrl('not a url')` | Resolves `'not a url'` unchanged — the `URL` constructor throws and the `catch` returns `url` |
| status-server-monitor-url-011 | pure-synchronous, no-throw | Call `hostOf` and `projectPageUrl` with global `fetch`, `console.*`, and `fs` spied, across every input in vectors 001–010 | Zero recorded calls on any spy; no call throws for any input exercised above |
