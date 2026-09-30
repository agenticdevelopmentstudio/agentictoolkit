<!-- leaf: implement-status-web-hooks/use-config-status--test-vectors · source: status-web-hooks-use-config-status.md -->

# useConfigStatus

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| config-status-001 | roster-no-provider-dependency, error-classification-reported, classification-http-error | Roster reads return 1 group, 1 site, 1 integration, 1 endpoint; `fetchUnconfigured` rejects with `Error("deploy-projects/unconfigured 502")` (from `use-config-status.dom.test.tsx`) | `configure.sites`, `configure.endpoints`, `configure.integrations` each have length 1; `error` is an `Error` whose message contains `502` |
| config-status-002 | unconfigured-sites-predicate, projects-from-server, counts | Endpoint `{ kind: "http", platform: null, deployProject: null, ignoreProjectWarning: false, isActive: true }`; classification `{ pending: [{ platform: "vercel", projectName: "p" }], addable: [], noDomain: [], unconfiguredSites: [] }` (from `use-config-status.dom.test.tsx`) | `status.counts.total` is `2` (1 site + 1 project); `error` is falsy |
| config-status-003 | empty-until-both | Roster data loaded; classification still pending | `status` equals `EMPTY_STATUS`; `counts.total` is `0`; `isLoading` is `false`; `configure` is populated |
| config-status-004 | paused-fold | Endpoint `{ kind: "http", platform: null, deployProject: null, ignoreProjectWarning: false, isActive: false }`; classification with empty arrays | `status.unconfiguredSites` is empty; `counts.sites` is `0` |
| config-status-005 | paused-fold | Endpoint `{ kind: "http", platform: null, deployProject: null }` with `isActive` absent; classification with empty arrays | `status.unconfiguredSites` contains the endpoint; `counts.sites` is `1` |
| config-status-006 | endpoint-classification | Endpoints of kind `health`, `dns` and `custom`, all with `platform: null` | `status.unconfiguredSites` is empty |
| config-status-007 | endpoint-classification | Endpoint `{ kind: "http", platform: "vercel", deployProject: "web" }` | Not in `status.unconfiguredSites` |
| config-status-008 | by-platform-tally | `pending` platforms `["cloudflare-pages", "cloudflare", "vercel", null]` | `unmonitoredByPlatform` is `{ cloudflare: 2, vercel: 1, "": 1 }`; `counts.projects` is `4` |
| config-status-009 | no-domain-count, addable-from-server | `noDomain` has 3 entries, `addable` has 2 entries | `status.noDomainProjects` is `3`; `status.addableProjects` is the same 2-entry array |
| config-status-010 | error-precedence, error-single-slot | Roster read rejects with `Error("A")`; classification rejects with `Error("B")` | `error` is `Error("A")`; `configure` is `undefined`; `status` equals `EMPTY_STATUS` |
| config-status-011 | roster-all-or-nothing | `listIntegrations` rejects; the other three reads resolve | `configure` is `undefined`; `error` is the `listIntegrations` rejection |
| config-status-012 | invalidate-both, invalidate-result | Call `invalidateConfigQueries(qc)` on a client holding both keys | Both `["configure-data"]` and `["configure-classification"]` are marked invalid and refetched if observed; the promise resolves to `undefined` |
| config-status-013 | enabled-false-no-fetch | Mount `useConfigStatus({ enabled: false })` with no other consumer | No roster read and no `fetchUnconfigured` call occur; `status` equals `EMPTY_STATUS` |
| config-status-014 | refetch-both | Call `refetch()` after both queries loaded | One more run of the four roster reads and one more `fetchUnconfigured` call; the promise resolves to a two-element array |
| config-status-015 | classification-fetch | Classification query runs | `fetchUnconfigured` is called with only the api argument; the request path is `/deploy-projects/unconfigured` (no `?fresh=1`) |
| config-status-016 | configure-data-key, classification-key | Read the exported constants | `CONFIGURE_DATA_KEY` deep-equals `["configure-data"]`; `CONFIGURE_CLASSIFICATION_KEY` deep-equals `["configure-classification"]` |
