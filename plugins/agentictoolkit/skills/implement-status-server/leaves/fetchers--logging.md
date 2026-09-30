<!-- leaf: implement-status-server/fetchers--logging · source: status-server-fetchers.md -->

# Status Server Fetchers

## Logging

Subsystem: process `console` | Category: telemetry

| Event | Level | Message |
|-------|-------|---------|
| GlitchTip issues request returned a non-`ok` HTTP response | warn | `` [telemetry] GlitchTip issues HTTP <status> `` |
| GlitchTip issues response body parsed but was not an array | warn | `[telemetry] GlitchTip issues returned a non-array body — treating as a failed poll` |
| GlitchTip issues request timed out | warn | `` [telemetry] GlitchTip issues fetch timed out after <TIMEOUT_MS>ms `` |
| GlitchTip issues request threw a non-timeout error | warn | `` [telemetry] GlitchTip issues fetch failed: <message> `` |
| A PostHog HogQL query batch stopped early on a failure | warn | `` [telemetry] PostHog poll failed (<failure>) — <answered>/<total> queries answered `` |
