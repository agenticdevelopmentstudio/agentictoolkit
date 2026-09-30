<!-- leaf: implement-status-server-monitor-1/enrich-deploy-errors--logging · source: status-server-monitor-enrich-deploy-errors.md -->

# Status Server Monitor Enrich Deploy Errors

## Logging

This file uses plain `console.error` calls, each with a literal `[enrich]` prefix, not a structured logger with its own subsystem/category object.

| Event | Level | Message |
|-------|-------|---------|
| The `listFailedWithoutError` candidate query rejects | error (`console.error`) | `[enrich] failed-deploy query failed:` (caught error passed as the second `console.error` argument) |
| A candidate row's fetch or `setErrorText` call rejects | error (`console.error`) | `` `[enrich] ${row.id} error fetch/store failed:` `` (caught error passed as the second `console.error` argument) |

No log line is emitted on a successful enrichment, an empty candidate set, or a no-pollable-platform short circuit, at any level — silence is the expected steady state.
