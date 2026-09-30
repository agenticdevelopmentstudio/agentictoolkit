<!-- leaf: implement-hub-domain-1/monitored-sites · source: hub-domain-monitored-sites.md -->

# Hub Domain Monitored Sites

## Overview

`monitored-sites.ts` and `wire.ts`, re-exported by `index.ts` as `@agentic-toolkit/data/monitored-sites`,
are the client for the Status Sites monitoring domain: `site-groups`, `sites`, and `endpoints`, backed
by generic CRUD over `/api/monitoring/site-groups`, `/api/monitoring/sites`, and
`/api/monitoring/endpoints`. Per the module's own top-of-file comment, the model matches the database,
not an earlier prototype: a site belongs to exactly one group (`sites.site_group_id`, `NOT NULL`, FK
`ON DELETE CASCADE`) and an endpoint belongs to exactly one site (same cascade) — a strict 1:M chain,
not the prototype's many-to-many `groupIds[]`. The whole chain is owner-scoped server-side, with an
optional `workspace` parameter on every operation that re-pins it to a workspace's owning principal.
`wire.ts` holds the backend row and request-body shapes (`GroupRow`, `SiteRow`, `EndpointRow`, and their
create/put bodies); `monitored-sites.ts` exports the three `toGroup`/`toSite`/`toEndpoint` mappers, the
`CreateGroupBody`/`UpdateGroupBody`/`CreateSiteBody`/`UpdateSiteBody`/`CreateEndpointBody`/`UpdateEndpointBody`
caller-facing shapes, the `ENDPOINT_KINDS` constant, and twelve exported functions — list/create/update/delete
for each of the three entities — each a thin request builder over the shared `authedJson`/`authedRequest` helpers from
`@agentic-toolkit/auth/client` (re-exported through `./http`). It is a headless **logic** module — no
visual surface — consumed today by the Dashboards (Site Monitoring) feature
(`packages/web/packages/features/dashboards/src/*`), so this recipe marks Appearance, States, and
Accessibility not applicable and carries the runtime contract entirely in Behavioral Requirements, per
the non-UI component guidance this recipe was authored under.

