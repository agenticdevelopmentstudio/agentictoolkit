<!-- leaf: implement-status-web/api--test-vectors · source: status-web-api.md -->

# Status Web API

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-web-api-001 | json-204-empty | `json<void>` call whose `fetch` resolves `{ok: true, status: 204}` | resolves `undefined`; `res.json()` is never invoked |
| status-web-api-002 | json-ok-body | `json<T>` call whose `fetch` resolves `{ok: true, status: 200, json: () => ({a: 1})}` | resolves `{a: 1}` |
| status-web-api-003 | json-error-message, json-error-detail, site-crud | `updateSite(api, "x", {name: "New"})`; `fetch` resolves `{ok: false, status: 404}` with JSON body `{"error": "not found"}` | rejects with `Error("PATCH /api/config/sites/x → 404 — not found")` |
| status-web-api-004 | json-error-detail, peer-crud-routes | `createPeer(api, {...})`; `fetch` resolves `{ok: false, status: 500}` with a body that fails to parse as JSON | rejects with `Error("POST /api/config/peers → 500")` — no ` — ` suffix |
| status-web-api-005 | url-join | `basePath: "/api"`, `path: "/config/peers"` | `url(path) === "/api/config/peers"` |
| status-web-api-006 | event-source-target | default client, `path: "/live/stream"` | `eventSource(path)` constructs `new EventSource("/api/live/stream")` |
| status-web-api-007 | (n/a — mapper passthrough, traced to `monitored-sites.test.ts`) | `toGroup({id: "g", slug: "s", name: "N", retentionDays: 14})` | returns `{id: "g", slug: "s", name: "N", retentionDays: 14}` |
| status-web-api-008 | site-group-rename (traced to `monitored-sites.test.ts`) | `toSite({id: "s1", slug: "site", name: "Site", siteGroupId: "g1"})` | `groupId === "g1"` |
| status-web-api-009 | endpoint-optional-field-defaults (traced to `monitored-sites.test.ts`) | `toEndpoint(row)` with `row.environment` absent | `environment === null` |
| status-web-api-010 | endpoint-dns-defaults (traced to `monitored-sites.test.ts`) | `toEndpoint(row)` with `dnsCheckA`/`dnsCheckAaaa`/`dnsCheckCname` all absent | all three `=== true` |
| status-web-api-011 | endpoint-dns-defaults (traced to `monitored-sites.test.ts`) | `toEndpoint(row)` with `dnsCheckCname: false`, the other two absent | `dnsCheckCname === false`, `dnsCheckA === true` |
| status-web-api-012 | peer-token-write-semantics, peer-write-passthrough | `updatePeer(api, "p1", {label: "x"})` | serialized request body is `{"label":"x"}` — no `token` key present at all |
| status-web-api-013 | peer-token-write-semantics | `updatePeer(api, "p1", {token: null})` | serialized request body includes `"token":null` |
| status-web-api-014 | ignore-project-fanout | `ignoreProjects(api, [{platform: "vercel", projectName: "a"}, {platform: "railway", projectName: "b"}])` | exactly two `POST /config/ignored-projects` requests are issued, via `Promise.all`, not sequential `await`s |
| status-web-api-015 | unignore-project-id | `unignoreProject(api, "vercel", "my/app")` | request path is `DELETE /config/ignored-projects/vercel%7Cmy%2Fapp` |
