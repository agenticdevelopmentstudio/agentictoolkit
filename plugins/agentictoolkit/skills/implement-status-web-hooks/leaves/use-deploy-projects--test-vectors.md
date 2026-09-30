<!-- leaf: implement-status-web-hooks/use-deploy-projects--test-vectors · source: status-web-hooks-use-deploy-projects.md -->

# useDeployProjects

## Conformance Test Vectors

No test in the source exercises this module directly; `use-config-status.dom.test.tsx` mocks `fetchUnconfigured` (resolving `{ pending: [...], addable: [], noDomain: [], unconfiguredSites: [] }` or rejecting with `Error("deploy-projects/unconfigured 502")`). The vectors below are traced to the module's code.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| deploy-projects-001 | deploy-projects-path, deploy-projects-no-store, deploy-projects-fresh-default | `fetchDeployProjects(api)` with a stub `api.fetch` | `api.fetch` called once with `"/deploy-projects"` and `{ cache: "no-store" }` |
| deploy-projects-002 | deploy-projects-fresh-path | `fetchDeployProjects(api, { fresh: true })` | `api.fetch` called with `"/deploy-projects?fresh=1"` and `{ cache: "no-store" }` |
| deploy-projects-003 | deploy-projects-success | Stub returns ok response with body `{ "projects": [], "verifiedPlatforms": ["vercel"] }` | Resolves to `{ projects: [], verifiedPlatforms: ["vercel"] }` |
| deploy-projects-004 | deploy-projects-http-error | Stub returns response with `ok: false`, `status: 502` | Rejects with `Error` message `deploy-projects 502` |
| deploy-projects-005 | unconfigured-path, unconfigured-no-store | `fetchUnconfigured(api)` | `api.fetch` called with `"/deploy-projects/unconfigured"` and `{ cache: "no-store" }` |
| deploy-projects-006 | unconfigured-fresh-path | `fetchUnconfigured(api, { fresh: true })` | `api.fetch` called with `"/deploy-projects/unconfigured?fresh=1"` |
| deploy-projects-007 | unconfigured-http-error | Stub returns `ok: false`, `status: 502` | Rejects with `Error` message `deploy-projects/unconfigured 502` |
| deploy-projects-008 | unconfigured-success, unconfigured-response-shape | Stub returns ok body `{ "pending": [{ "platform": "vercel", "projectName": "p" }], "addable": [], "noDomain": [], "unconfiguredSites": [] }` | Resolves to the same object |
| deploy-projects-009 | latch-initial-armed, latch-read-at-start | Fresh module load; mount `useDeployProjects()` | First request path is `/deploy-projects?fresh=1` |
| deploy-projects-010 | latch-disarm-on-success | After vector 009 succeeds, invalidate `["deploy-projects"]` | Second request path is `/deploy-projects` |
| deploy-projects-011 | latch-kept-on-failure | Fresh module load; first request returns `status: 500`; refetch | Both requests use `/deploy-projects?fresh=1`; query `status` is `"error"` after the first |
| deploy-projects-012 | latch-arm | After a successful fetch, call `armFreshDeployProjectsFetch()` then invalidate the query | Next request path is `/deploy-projects?fresh=1` |
| deploy-projects-013 | hook-enabled-false | Mount `useDeployProjects({ enabled: false })` | `api.fetch` is never called |
| deploy-projects-014 | hook-stale-time | Successful fetch, then remount an observer 30 s later | No new request; cached data returned |
| deploy-projects-015 | hook-query-key | Mount the hook with a test `QueryClient` | `queryClient.getQueryState(["deploy-projects"])` is defined |
| deploy-projects-016 | hook-return, deploy-projects-http-error | Hook fetch returns `status: 503`, retries disabled on the test `QueryClient` | Result `status` is `"error"`, `error.message` is `deploy-projects 503` |
| deploy-projects-017 | latch-scope | Latch armed; call `fetchUnconfigured(api)` | Path is `/deploy-projects/unconfigured`; latch remains armed |
| deploy-projects-018 | dedup-by-query-key | Mount two `useDeployProjects()` observers under one `QueryClient` | One request is sent |
