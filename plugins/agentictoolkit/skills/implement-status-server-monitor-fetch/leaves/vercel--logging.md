<!-- leaf: implement-status-server-monitor-fetch/vercel--logging · source: status-server-monitor-fetch-vercel.md -->

# Status Server Monitor Fetch Vercel

## Logging

This file uses plain `console.error` calls with no structured subsystem/category object.

| Event | Level | Message |
|-------|-------|---------|
| A page-fetch response is not `ok` | error (`console.error`) | `` Vercel API <status> `` |
| A page fetch call threw | error (`console.error`) | `` Vercel deployments fetch failed: <message> `` |
| A deployment's `created` failed `toValidDate` | error (`console.error`) | `` Vercel deployment <uid> has unparseable created <JSON-stringified value> — skipping `` |
| `fetchVercelDeployError`'s detail response is not `ok` (and not 429) | error (`console.error`) | `` Vercel deployment <uid> detail <status> `` |
| `fetchVercelDeployError`'s fetch call threw | error (`console.error`) | `` Vercel deployment <uid> detail fetch failed: <message> `` |
| `fetchVercelBuildLog`'s events response is not `ok` (and not 429) | error (`console.error`) | `` Vercel deployment <uid> events <status> `` |
| `fetchVercelBuildLog`'s fetch call threw | error (`console.error`) | `` Vercel deployment <uid> events fetch failed: <message> `` |

A fully successful poll or a fully successful on-demand fetch produces no log output from this file at any level.
