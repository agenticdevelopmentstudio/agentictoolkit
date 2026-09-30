<!-- leaf: implement-status-server-monitor-1/integrations--logging · source: status-server-monitor-integrations.md -->

# Status Server Monitor Integrations

## Logging

Neither `integrations.ts` nor `self-check-stability.ts` calls `console.*` or any other logger at any point. Every failure surfaces exclusively through the returned `IntegrationCheck`'s own `state`/`detail`/`unreachable`/`correlated` fields, consumed by the `/integrations` route and rendered on the integrations panel — there is no server-log side channel for this component's own failures, in contrast to sibling deploy fetchers (e.g. the Cloudflare and Railway deploy pollers, external) that do log via `console.error`. A fully healthy run produces no log output from this component at any level, because it produces no log output from this component at ANY level, healthy or not.
