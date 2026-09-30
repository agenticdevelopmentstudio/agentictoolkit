<!-- leaf: implement-general-1/deploy-engine--logging · source: deploy-engine.md -->

# Deploy Engine

## Logging

Subsystem: process `console` | Category: deploy-platform

| Event | Level | Message |
|-------|-------|---------|
| Unknown provider name passed to the cooldown registry | error | `` [cooldown] unknown provider "<provider>" — cooldown not recorded `` |
| A 429 recorded against a known provider | error | `` [cooldown] <provider> rate-limited — backing off <N>s `` |
| Cloudflare `/accounts` discovery threw | error | `Cloudflare /accounts discovery failed: <message>` |
| Cloudflare `workers/domains` listing threw | error | `Cloudflare workers/domains listing failed: <message>` |
| Railway project listing failed (not an aborted caller timeout) | error | `Railway project listing failed: <message>` |
| Railway project-domains fetch failed (not an aborted caller timeout) | error | `Railway project <projectId> domains failed: <message>` |

`listWorkerScripts`, `listWorkerCustomDomains`'s non-OK-but-not-thrown path,
and `fetchProjectDomainList`'s non-OK/thrown path deliberately log nothing —
each returns a typed result the caller is expected to act on instead (see
Edge Cases, including its two open questions).
