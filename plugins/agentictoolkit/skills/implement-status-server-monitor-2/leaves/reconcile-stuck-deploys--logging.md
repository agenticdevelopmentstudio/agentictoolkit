<!-- leaf: implement-status-server-monitor-2/reconcile-stuck-deploys--logging · source: status-server-monitor-reconcile-stuck-deploys.md -->

# Status Server Monitor Reconcile Stuck Deploys

## Logging

This file uses plain `console.log`/`console.error` calls, each with a literal `[reconcile]` prefix, not a structured logger with its own subsystem/category object.

| Event | Level | Message |
|-------|-------|---------|
| `listInFlightCandidates` rejects | error (`console.error`) | `[reconcile] vanished-deploy query failed:` (caught error as the second argument) |
| Vercel by-id detail fetch returns non-ok, non-404, non-429 | error (`console.error`) | `` `[reconcile] Vercel deployment ${uid} detail ${res.status}` `` |
| Railway by-id detail fetch returns non-ok, non-429 | error (`console.error`) | `` `[reconcile] Railway deployment ${id} detail ${res.status}` `` |
| A row's provider fetch resolves `"gone"` | info (`console.log`) | `` `[reconcile] ${row.id} gone at provider → canceling in-flight lifecycle(s)` `` |
| A row's fetch or store call rejects | error (`console.error`) | `` `[reconcile] ${row.id} phase fetch/store failed:` `` (caught error as the second argument) |
| `expireStaleInFlight` collapses one or more rows | info (`console.log`) | `` `[reconcile] ${n} in-flight deploy row(s) unconfirmable for 6h+ → unknown` `` |
| `expireStaleInFlight` rejects | error (`console.error`) | `[reconcile] expiry sweep failed:` (caught error as the second argument) |

No log line is emitted on a successful phase heal, an empty candidate set, a no-pollable-platform short circuit, or an expiry sweep that collapses zero rows — silence is the expected steady state.
