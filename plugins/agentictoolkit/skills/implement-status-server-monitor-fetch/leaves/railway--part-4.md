<!-- leaf: implement-status-server-monitor-fetch/railway--part-4 · source: status-server-monitor-fetch-railway.md -->

# Status Server Monitor Fetch Railway — continued (part 4)

## Design Decisions

- **Decision**: retry the project-listing call and each project's own poll exactly ONCE, and only when the retried attempt lost to OUR OWN timeout box — never on a real answer, including an error answer.
  **Rationale**: stated directly in the source comments on `RAILWAY_CALL_TIMEOUT_MS`/`RAILWAY_CALL_ATTEMPTS`: measured from inside the prod container, the per-project GraphQL query's latency tail is "INDEPENDENT per request, not sticky to a slow project," so a second attempt lands in the fast median; a longer single timeout instead "would make a genuinely stuck project hold its concurrency slot for that much longer, spending the overall budget on the one project least likely to answer." Retrying a real answer (including "Not Authorized") would just burn shared budget repeating a verdict that will not change.
  **Approved**: pending
- **Decision**: start the overall budget's deadline before the project-listing call, not after it.
  **Rationale**: stated directly in the source comment — the listing call is part of the poll and its time must count against the deadline; computing the deadline after the listing (an earlier version) let the worst case run past `guard`'s 20-second cap in `sync.ts`, which then discarded the whole (mostly successful) poll as unreachable.
  **Approved**: pending
- **Decision**: poll projects with bounded concurrency of exactly 5 (`RAILWAY_PROJECT_CONCURRENCY`), not serially and not fully unbounded.
  **Rationale**: stated directly in the source comment on the `mapLimit` call — a serial `for..of` loop made total time `N × 6s`, which "with enough projects and a degraded Railway API alone blows the cycle budget and wedges the whole monitor."
  **Approved**: pending
- **Decision**: when the overall budget is spent BEFORE a project's first attempt, mark the poll `skipped` (not an error); when it is spent before a RETRY the project already started, count that project as an `error`.
  **Rationale**: stated directly in the source comment — "Before the FIRST attempt this project was never polled — a partial, exactly as before. Before a RETRY it WAS polled and timed out, which is the provider failing us rather than a project we chose not to start."
  **Approved**: pending
- **Decision**: treat a project's environments-fetch failure as failing the WHOLE project (no rows at all), routed to the same error path as any other provider failure, rather than falling back to keying rows by the raw `environmentId`.
  **Rationale**: stated directly in the source comment — Railway is "the ONE platform whose board target carries the environment segment," so a project polled without its env map previously produced rows keyed by a raw UUID that "matched no roster entry in either index," making every one of that project's deploys invisible; "an absence of data" must never "render as health," so erroring the project routes it to the existing platform-unreachable debounce instead.
  **Approved**: pending
- **Decision**: pin an explicit, large page size (`RAILWAY_ENV_PAGE_SIZE = 200`) on the environments query rather than accepting the server's default, and log — but do not error — when a project's environment count reaches that pinned size.
  **Rationale**: stated directly in the source comment — the per-row environment-id-to-name lookup below is sound only because the map is COMPLETE; an unpinned page size would silently drop deploys in any environment that fell off an undersized default page, "one row at a time," and the drop and a genuine deletion are otherwise indistinguishable. Logging (not erroring) a full page is deliberate: the project answered normally and is reachable, so routing it to the platform-unreachable path would report the wrong kind of outage.
  **Approved**: pending
- **Decision**: keep the row's `url` as the Railway dashboard project link (`https://railway.com/project/<id>`), not the deployment's own `staticUrl`.
  **Rationale**: stated directly in the source comment — the `url` field is "the SOURCE link target," i.e. where a developer goes to debug the deploy, not the public/live URL; the public/live host is resolved elsewhere (from `liveHost`, stamped from config in `sync.ts`, external), so this file deliberately does not attempt to supply it.
  **Approved**: pending
- **Decision**: persist `RAILWAY_NO_BUILD_TEXT` as a real value for a deployment Railway reports as having no associated build, rather than leaving its error text `null`.
  **Rationale**: stated directly in the source comment on `RAILWAY_NO_BUILD_TEXT` — writing a real value "takes the row out of the enrichment candidate set," because otherwise the caller (`enrich-deploy-errors.ts`, external) would re-fetch and re-log the same "does not have an associated build" GraphQL error every cycle for a deployment that will never have logs.
  **Approved**: pending
- **Decision**: share one network call and one error-classification helper (`railwayBuildLogMessages`) between `fetchRailwayBuildLogTail` and `fetchRailwayBuildLog`, differing only in the requested `limit` and the shaping function applied to the result.
  **Rationale**: stated directly in the source comment — the tail (enrichment) and the full read (the on-demand log route) "differ only in how many lines they ask for and how they shape the result," and sharing the fetch and error classification means "the CLI and the details pane would [not] disagree about the same deployment" on whether it is buildless or transiently unreachable.
  **Approved**: pending
