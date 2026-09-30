<!-- leaf: implement-general-1/auth-client--logging · source: auth-client.md -->

# Auth Client

## Logging

Subsystem: `agentictoolkit` | Category: `auth-client`

| Event | Level | Message |
|-------|-------|---------|
| Refresh network/parse failure | error (via `reportAuthError`, always reaches `console.error`) | `reportAuthError(err, { feature: 'auth', step: 'tokenRefresh' })` (`refresh.ts`) |
| Any reported auth error (unconditional path) | error | `console.error(err, context)` (`report.ts`) |
| Missing AS base at build/runtime (logged once per page load) | error | `'[adh-auth] NEXT_PUBLIC_AUTH_API_URL was not set when this site was built...'` (`sso.ts`) |

No file in this component uses `console.log`, `console.warn`, or `console.info` — every log call site is `console.error`, and every one is either an unexpected-failure report (`report.ts`, `refresh.ts`) or the one-time misconfiguration notice above (`sso.ts`). `report.ts`'s error-status gate (**report-unexpected-status-gate**) is specifically what keeps an expected 4xx (wrong password, stale code) off this log.
