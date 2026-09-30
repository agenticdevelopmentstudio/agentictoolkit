<!-- leaf: implement-status-server-monitor-1/live-types--test-vectors · source: status-server-monitor-live-types.md -->

# Status Server Monitor Live Types

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| live-types-001 | providers-map-is-total | `GET /live` against a database with no configured integrations | `providers` carries `vercel`, `cloudflare-pages`, `railway`, and `crunchy` keys, matching the default fixture in `test/helpers/snapshot.ts`'s `liveSnapshot()` — `reads.int.test.ts`'s `'returns a LiveSnapshot with a token (empty DB does not error)'` |
| live-types-002 | dns-ok-semantics | An endpoint whose latest persisted health check is `status: 'healthy'` | The corresponding `LiveServiceDTO` matches `{ status: 'healthy', responseTimeMs: 42, dnsOk: true }` — `reads.int.test.ts`'s `'/live + /status surface a service derived from the latest health check'` |
| live-types-003 | dns-ok-semantics | An endpoint whose latest persisted health check row has `dnsOk: false` | The corresponding `LiveServiceDTO.dnsOk` is `false` — `reads.int.test.ts`'s `'/live marks a service dnsOk=false when its latest check failed DNS'` |
| live-types-004 | down-since-is-server-truth | An endpoint with an open http/dns issue whose `openedAt` is a known timestamp | `LiveServiceDTO.downSince` equals that issue's `openedAt.toISOString()` — `reads.int.test.ts`'s `'/live stamps downSince from the open http/dns issue openedAt (server-truth "down since")'` |
| live-types-005 | down-since-is-server-truth | A second, healthy endpoint with no open issue | That endpoint's `LiveServiceDTO.downSince` is `null` — same test, second assertion (`live2.services.find(...).downSince` is `null`) |
| live-types-006 | config-degraded-flag, config-reason-nullable-and-unconstrained-when-degraded | `GET /live` against an empty but reachable database | `configDegraded` is `false` and `configReason` is `null` — `reads.int.test.ts`'s `'returns a LiveSnapshot with a token (empty DB does not error)'` |
| live-types-007 | last-cycle-at-is-data-freshness-clock | A fresh database with no health check ever persisted | `LiveSnapshot.lastCycleAt` is `null` — same test |
| live-types-008 | last-cycle-at-is-data-freshness-clock | A database with at least one recently-persisted health check | `LiveSnapshot.lastCycleAt` is an ISO string less than 60 seconds old — `reads.int.test.ts`'s `'/live + /status surface a service derived from the latest health check'` |
| live-types-009 | stale-prod-dto-shape | A persisted `vercelProdState` row for a project an OWNED site monitors | `LiveSnapshot.staleProd` has one entry matching `{ projectName: 'adh', environment: 'production', liveUrl: 'https://adh.example.com' }` — `reads.int.test.ts`'s `'/live derives staleProd from a persisted vercelProdState row for an OWNED project'` |
| live-types-010 | stale-prod-dto-shape | A stale-Vercel issue for a project no live site currently owns | `LiveSnapshot.staleProd` maps to an empty `projectName` list — `reads.int.test.ts`'s `'/live drops a vercel-stale issue for a project NO live site owns'` |
