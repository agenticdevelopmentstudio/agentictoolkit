<!-- leaf: implement-status-server-monitor-fetch/cloudflare--logging · source: status-server-monitor-fetch-cloudflare.md -->

# Status Server Monitor Fetch Cloudflare

## Logging

This file uses plain `console.error` calls with no structured subsystem/category object.

| Event | Level | Message |
|-------|-------|---------|
| Per-script deployments fetch returned non-2xx | error (`console.error`) | `` Cloudflare Workers <script> <status> `` |
| Per-script deployments fetch threw | error (`console.error`) | `` Cloudflare Workers fetch <script> `` (plus the caught error, as a second argument) |
| A deployment's `created_on` failed `toValidDate` | error (`console.error`) | `` Cloudflare deployment <id> has unparseable created_on <JSON-stringified value> — skipping `` |

A fully successful poll (every script fetched, no 429, budget not exhausted) produces no log output from this file at any level.
