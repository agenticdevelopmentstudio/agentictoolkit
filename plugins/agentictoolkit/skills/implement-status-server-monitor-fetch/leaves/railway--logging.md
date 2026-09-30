<!-- leaf: implement-status-server-monitor-fetch/railway--logging · source: status-server-monitor-fetch-railway.md -->

# Status Server Monitor Fetch Railway

## Logging

This file uses plain `console.error` calls with no structured subsystem/category object.

| Event | Level | Message |
|-------|-------|---------|
| Per-project environments fetch returned non-ok | error (`console.error`) | `` Railway environments <projectId> <status> `` |
| Per-project environments response carried GraphQL errors or no `environments` payload | error (`console.error`) | `` Railway environments <projectId> unusable: <messages, or "no environments payload"> `` |
| Per-project environments response returned a full page (possible truncation) | error (`console.error`) | `` Railway environments <projectId> returned a FULL page (<count>) — the env map may be truncated and deploys in unlisted environments will be dropped `` |
| Per-project deployments fetch returned non-ok | error (`console.error`) | `` Railway <projectId> <status> `` |
| Per-project deployments response carried GraphQL errors | error (`console.error`) | `` Railway <projectId> GraphQL errors: <messages> `` |
| A deployment's `createdAt` failed `toValidDate` | error (`console.error`) | `` Railway deployment <id> has unparseable createdAt <JSON-stringified value> — skipping `` |
| A deployment's `environmentId` was absent from the resolved map | error (`console.error`) | `` Railway deployment <id> references unknown environment <JSON-stringified environmentId> — skipping `` |
| A per-project fetch threw for a reason other than our own abort | error (`console.error`) | `` Railway fetch `` (plus the caught error, as a second argument) |
| A project timed out on every retry attempt | error (`console.error`) | `` Railway <projectId> timed out on all <RAILWAY_CALL_ATTEMPTS> attempts `` |
| A build-log fetch returned non-ok | error (`console.error`) | `` Railway buildLogs <deploymentId> <status> `` |
| A build-log fetch's response carried GraphQL errors other than the permanent "no associated build" case | error (`console.error`) | `` Railway buildLogs <deploymentId> GraphQL errors: <messages> `` |
| A build-log fetch threw | error (`console.error`) | `` Railway buildLogs <deploymentId> fetch failed `` (plus the caught error) |

A fully successful poll (every project fetched, no 429, budget not exhausted, no truncated environment page) produces no log output from this file at any level.
