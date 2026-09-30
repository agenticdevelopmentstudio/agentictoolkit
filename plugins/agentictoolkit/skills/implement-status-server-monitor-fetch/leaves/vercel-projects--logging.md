<!-- leaf: implement-status-server-monitor-fetch/vercel-projects--logging · source: status-server-monitor-fetch-vercel-projects.md -->

# Status Server Monitor Fetch Vercel Projects

## Logging

This file uses plain `console.error`/`console.log` calls with no structured subsystem/category object.

| Event | Level | Message |
|-------|-------|---------|
| Enumeration truncated | error (`console.error`, via `reportTruncation`) | `` [vercel-projects] overall budget exceeded — returning partial `` / `` [vercel-projects] a page was refused by the API — returning partial `` / `` [vercel-projects] a page timed out 2x — returning partial `` |
| A non-first page returned a non-ok HTTP status | error (`console.error`) | `` Vercel projects API <status> `` |
| A deployment's `createdAt` failed `toValidDate` | error (`console.error`) | `` Vercel project <projectName> deploy <id> has unparseable createdAt <JSON-stringified value> — skipping `` |
| A team-slug sub-call (`/v2/teams[/<id>]`) threw | error (`console.error`) | `` Vercel team lookup <path> failed: <message> `` |
| The whole call threw past every inner `try`/`catch` | error (`console.error`) | `` Vercel projects fetch failed: <message> `` |
| One or more blind projects were found before the backfill | log (`console.log`) | `` [vercel-projects] <N> project(s) have no verdict in the poll window — reading it directly `` |

A fully successful poll (every page fetched cleanly, no unparseable `createdAt`, no blind projects, no failed team lookup) produces no log output from this file at any level.
